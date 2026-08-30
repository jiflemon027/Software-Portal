#Requires -Version 5.1
<#
.SYNOPSIS
    Returns a [pscredential] for the BigFix operator account, fetched at runtime from
    AKeyless using Cyera's existing universal identity (D-20). No secret is ever
    written to disk, a log file, or PipelineConfig.

.DESCRIPTION
    Wraps the call sequence proven in G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1:

      1. Read Cyera's .vault-token (RoleSync READS ONLY - Cyera's rotator is the sole
         writer; a missing/stale token is a distinct, actionable error).
      2. POST https://api.akeyless.io/auth  (access-type = universal_identity).
      3. Take $auth.token.
      4. POST https://api.akeyless.io/get-secret-value  (names = @($SecretPath)).
      5. Read the plaintext back as $resp.$SecretPath, wrap it in a SecureString, and
         return [pscredential]::new($UserName, <SecureString>).

    Mandatory deviations from the Cyera analog: no transcript logging of any kind; the
    plaintext is confined to a single local variable and is never written to any output
    stream, never assigned to a script-scope variable, never put in a log object.

    Every distinguishable failure mode logs Windows Event 8001 (Source
    'DereseSoftwarePortal', LogName Application) with the failure class and $SecretPath
    - never the token or the secret - then rethrows.

.PARAMETER DatabasePath
    AutomationState.db - used only to resolve unset -TokenFile / -SecretPath / -UserName
    from the PipelineConfig keys AKeylessTokenFile / AKeylessSecretPath / BESOperatorUser.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder).

.PARAMETER TokenFile
    Path to Cyera's .vault-token. Falls back to PipelineConfig.AKeylessTokenFile.

.PARAMETER SecretPath
    AKeyless secret path for the operator password. Falls back to
    PipelineConfig.AKeylessSecretPath.

.PARAMETER UserName
    BigFix operator username. Falls back to PipelineConfig.BESOperatorUser.

.PARAMETER SqliteHelperPath
    Path to the single shared Sqlite-Helper.ps1 (dot-sourced from Dashboard_4_samples\
    by default; copying it into scripts\ is not permitted).

.PARAMETER WhatIf
    Validate that the token file exists and the config keys resolve, emit a JSON
    summary, and make ZERO Invoke-RestMethod calls.

.OUTPUTS
    [pscredential]

.NOTES
    PowerShell 5.1+. Constrained Language Mode safe. No secret at rest.
    Failure classes (all -> Event 8001, all rethrown):
      token-file-missing      -TokenFile does not exist
      egress-unreachable      api.akeyless.io could not be reached
      auth-no-token           UID auth returned an empty token (clock skew / revoked id)
      secret-empty            get-secret-value returned nothing for -SecretPath
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$TokenFile,

    [Parameter()]
    [string]$SecretPath,

    [Parameter()]
    [string]$UserName,

    [Parameter()]
    [string]$SqliteHelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Dashboard_4_samples\Sqlite-Helper.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EventLogSource = 'DereseSoftwarePortal'
$AuthUri   = 'https://api.akeyless.io/auth'
$SecretUri = 'https://api.akeyless.io/get-secret-value'

function Write-CredFailureEvent {
    param([string]$FailureClass, [string]$Detail)
    # Never includes the token or the secret - only the failure class and the secret PATH.
    $msg = "Get-BigFixCredential failed [$FailureClass] for secret path '$SecretPath'. $Detail"
    try {
        Write-EventLog -LogName Application -Source $EventLogSource -EntryType Error -EventId 8001 -Message $msg -WhatIf:$false
    } catch {
        # An unregistered source must not mask the real error - swallow and move on.
    }
}

try {
    # --- resolve unset params from PipelineConfig ---------------------------
    if (-not $TokenFile -or -not $SecretPath -or -not $UserName) {
        if (-not (Test-Path $SqliteHelperPath)) {
            throw "Sqlite-Helper.ps1 not found at: $SqliteHelperPath (needed to resolve unset -TokenFile / -SecretPath / -UserName from PipelineConfig)."
        }
        . $SqliteHelperPath
        $rows = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
            -Sql "SELECT Key, Value FROM PipelineConfig WHERE Key IN ('AKeylessTokenFile','AKeylessSecretPath','BESOperatorUser')"
        $cfg = @{}
        foreach ($r in $rows) { $cfg[$r.Key] = $r.Value }
        if (-not $TokenFile  -and $cfg.ContainsKey('AKeylessTokenFile'))  { $TokenFile  = $cfg['AKeylessTokenFile'] }
        if (-not $SecretPath -and $cfg.ContainsKey('AKeylessSecretPath')) { $SecretPath = $cfg['AKeylessSecretPath'] }
        if (-not $UserName   -and $cfg.ContainsKey('BESOperatorUser'))    { $UserName   = $cfg['BESOperatorUser'] }
    }

    if ([string]::IsNullOrWhiteSpace($SecretPath)) {
        throw "No AKeyless secret path: pass -SecretPath or set PipelineConfig.AKeylessSecretPath."
    }
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        throw "No BigFix operator username: pass -UserName or set PipelineConfig.BESOperatorUser."
    }

    # --- token file (Cyera's; read-only) -----------------------------------
    if ([string]::IsNullOrWhiteSpace($TokenFile) -or -not (Test-Path $TokenFile)) {
        Write-CredFailureEvent -FailureClass 'token-file-missing' -Detail "Token file '$TokenFile' not found."
        throw "AKeyless token file missing: '$TokenFile'. Cyera's rotator is the ONLY writer of .vault-token; RoleSync must only READ it. Confirm the Cyera integration is provisioned and its rotator has run."
    }

    # --- WhatIf: validate only, no REST calls -----------------------------
    if ($WhatIfPreference) {
        $plan = [pscustomobject]@{
            whatif      = $true
            token_file  = $TokenFile
            token_found = $true
            secret_path = $SecretPath
            user_name   = $UserName
            rest_calls  = 0
        }
        Write-Host "----RUN SUMMARY----"
        Write-Host ($plan | ConvertTo-Json -Depth 4)
        return
    }

    $uidToken = (Get-Content -Path $TokenFile -Raw).ToString().Trim()

    # --- 1. universal-identity auth --------------------------------------
    try {
        $auth = Invoke-RestMethod -Method POST -Uri $AuthUri -ContentType 'application/json' `
            -Body (@{ 'access-type' = 'universal_identity'; 'uid-token' = $uidToken } | ConvertTo-Json -Compress)
    } catch {
        Write-CredFailureEvent -FailureClass 'egress-unreachable' -Detail 'auth endpoint'
        throw "api.akeyless.io unreachable (auth): $($_.Exception.Message)"
    }
    if ($null -eq $auth -or [string]::IsNullOrEmpty($auth.token)) {
        Write-CredFailureEvent -FailureClass 'auth-no-token' -Detail 'UID auth returned no token.'
        throw "AKeyless UID auth returned no token (clock skew, or the universal identity was revoked)."
    }

    # --- 2. fetch the secret ------------------------------------------
    try {
        $resp = Invoke-RestMethod -Method POST -Uri $SecretUri -ContentType 'application/json' `
            -Body (@{ names = @($SecretPath); token = $auth.token } | ConvertTo-Json -Compress)
    } catch {
        Write-CredFailureEvent -FailureClass 'egress-unreachable' -Detail 'get-secret-value endpoint'
        throw "api.akeyless.io unreachable (get-secret-value): $($_.Exception.Message)"
    }

    $secretPlain = $null
    if ($null -ne $resp) { $secretPlain = $resp.$SecretPath }
    if ([string]::IsNullOrEmpty($secretPlain)) {
        Write-CredFailureEvent -FailureClass 'secret-empty' -Detail 'get-secret-value returned an empty value.'
        throw "AKeyless returned an empty secret for '$SecretPath' (the secret path may not exist yet, or the identity is not authorised to read it)."
    }

    # --- 3. wrap and return; plaintext goes out of scope immediately ---
    $cred = [pscredential]::new($UserName, (ConvertTo-SecureString $secretPlain -AsPlainText -Force))
    $secretPlain = $null
    return $cred

} catch {
    throw
}
