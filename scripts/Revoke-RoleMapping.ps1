#Requires -Version 5.1
# Version: 1.0.0
<#
.SYNOPSIS
    Endpoint immediate-revoke writer for the Operator-Role-Group model (D-18). Given a role
    and a username, deactivates that user's Map row on THIS endpoint right now, instead of
    waiting for the role's Computer Group membership change to naturally stop reapplying.

.DESCRIPTION
    The normal removal path (drop a username from the Role Manager dashboard's Roles tab,
    Save, Publish) only stops the role's policy action from reapplying on that user's
    machine going forward -- it never touches the Map row the earlier Assign-RoleMapping.ps1
    run already wrote there, and nothing in this pipeline ever ages that row out on its own
    (Active is never cleared by anything else; Valid_to just stops being refreshed). Dropped
    users keep showing as "mapped" in every Analysis property that reads Active=1 until this
    script -- or the eventual Valid_to expiry the dashboard's Analysis properties now also
    check -- catches up.

    This script is the deliberate, immediate alternative: it sets Active=0 AND
    Locked_by_Override=1 in one guarded UPDATE, so the revoke cannot be silently undone by a
    stale/in-flight reapply of the OLD Computer Group definition racing the new one during
    Publish's rollout. Re-granting the SAME role to this user later requires clearing
    Locked_by_Override first (a deliberate, visible step) -- Assign-RoleMapping.ps1's own
    guarded UPDATE (`WHERE ... AND Locked_by_Override = 0`) will otherwise keep no-op'ing
    against this row forever.

    Constrained Language Mode safe: no Add-Type, no System.Data.SQLite, no dynamic .NET type
    loading. Every database call goes through Sqlite-Helper.ps1 (bundled sqlite3.exe).
    Targeted ONLY at machines whose RoleAwareness.db actually has a matching Active=1 row
    (the dashboard's deployed SingleAction's own CustomRelevance enforces this) -- this script
    does not re-check that itself; it trusts its caller the same way Assign-RoleMapping.ps1
    trusts its inputs.

.PARAMETER Role
    The role name the mapping belongs to, e.g. "IT Operations". Trimmed, case preserved.

.PARAMETER UserName
    The user to revoke. Any DOMAIN\ prefix or UPN "@domain" suffix is stripped; the result is
    lower-cased to match how Initialize-RoleDb.ps1 stores UserID.

.PARAMETER DatabasePath
    Full path to RoleAwareness.db.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder).

.PARAMETER SqliteHelperPath
    Path to the shared Sqlite-Helper.ps1. Default: Sqlite-Helper.ps1 in the same folder as
    -DatabasePath (the layout task 787 lays down).

.NOTES
    PowerShell 5.1, Constrained Language Mode safe. Aborts via throw (non-zero exit).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Role,

    [Parameter(Mandatory = $true)]
    [string]$UserName,

    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SoftwarePortal\RoleAwareness.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$SqliteHelperPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SqliteHelperPath)) {
    $SqliteHelperPath = Join-Path (Split-Path $DatabasePath) 'Sqlite-Helper.ps1'
}

$logfile = Join-Path (Split-Path $DatabasePath) 'SWDlog.log'

function Write-Tag {
    param([string]$Tag, [string]$Message)
    $line = "[$Tag] $Message"
    Write-Host $line
    try { Add-Content -Path $logfile -Value ("{0} revoke-role {1}" -f (Get-Date -Format 's'), $line) -WhatIf:$false } catch { }
}

function Get-DbRows {
    # Flatten Sqlite-Helper's (return ,$rows) wrapper so multi-row .Count is correct.
    param([string]$Sql, [hashtable]$P = @{})
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P
    return @($r | ForEach-Object { $_ })
}

# --- normalise inputs -------------------------------------------------------
$Role = $Role.Trim()
$user = $UserName.Trim().TrimStart('@').Split('\')[-1]
$user = $user.Split('@')[0].ToLowerInvariant()

$result = [ordered]@{
    whatif       = [bool]$WhatIfPreference
    role         = $Role
    user         = $user
    rows_revoked = 0
    outcome      = $null
}

function Write-RunLog {
    $dir = Split-Path $DatabasePath
    $path = Join-Path $dir ("revoke-role-{0}.json" -f ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')))
    try {
        Set-Content -Path $path -Value ([pscustomobject]$result | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8 -WhatIf:$false
    } catch { }
    Write-Host "----RUN SUMMARY----"
    Write-Host ([pscustomobject]$result | ConvertTo-Json -Depth 5 -Compress)
}

try {
    if ([string]::IsNullOrWhiteSpace($Role)) { throw "[ABORT] -Role is empty" }
    if ([string]::IsNullOrWhiteSpace($user)) { throw "[ABORT] -UserName is empty after normalisation" }

    if (-not (Test-Path $SqliteHelperPath)) { throw "[ABORT] Sqlite-Helper.ps1 not found at: $SqliteHelperPath (endpoint not initialised by task 787?)" }
    . $SqliteHelperPath

    if (-not (Test-Path $DatabasePath)) { throw "[ABORT] RoleAwareness.db not found at: $DatabasePath" }

    if ($WhatIfPreference) {
        Write-Tag 'WOULD' ("revoke user '{0}' role '{1}' -> Active=0, Locked_by_Override=1" -f $user, $Role)
        $result.outcome = 'whatif'
        Write-RunLog
        return
    }

    # Guarded UPDATE + connection-scoped changes() in ONE call (see Initialize-RoleDb.ps1
    # error 5350 note / Assign-RoleMapping.ps1's identical discipline). No WHERE ... AND
    # Locked_by_Override = 0 guard here -- revoking an ALREADY-locked row (e.g. a second
    # revoke click, or one locked by a prior manual override) is still the correct outcome,
    # never a silent no-op.
    $upd = @(Get-DbRows @"
UPDATE Map SET Active = 0, Locked_by_Override = 1, Updated_on = datetime('now','localtime')
WHERE UserID = @u AND Role = @r;
SELECT changes() AS n
"@ @{ u = $user; r = $Role })
    $changed = if ($upd.Count -gt 0) { [int]$upd[0].n } else { 0 }

    $result.rows_revoked = $changed
    if ($changed -gt 0) {
        $result.outcome = 'revoked'
        Write-Tag 'REVOKE' ("user='{0}' role='{1}' -> Active=0, Locked_by_Override=1" -f $user, $Role)
    } else {
        $result.outcome = 'no-matching-row'
        Write-Tag 'OK' ("user='{0}' role='{1}' -> no matching Map row on this endpoint" -f $user, $Role)
    }

    Write-RunLog
}
finally {
    try {
        if (Get-Command Invoke-SqliteCommand -ErrorAction SilentlyContinue) {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA wal_checkpoint(TRUNCATE)" | Out-Null
        }
    } catch { }
}
