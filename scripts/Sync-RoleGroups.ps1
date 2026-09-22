#Requires -Version 5.1
<#
.SYNOPSIS
    Root-server D-06 periodic drift-check driver (07-05). For every role recorded in the
    RolePublish.db D-05 audit store, rebuilds the "exactly one of N logged on" Computer
    Group relevance from that role's CURRENT username snapshot and re-PUTs the role's
    automatic Computer Group when the live relevance differs. Never creates a group --
    group creation is the dashboard's Publish responsibility (D-13); this job only
    corrects drift on a group that already exists.

.DESCRIPTION
    D-06 is a locked decision: the dashboard's Publish flow is on-demand and not
    transactional, so a group can be left stale by a half-completed Publish, a console
    operator hand-editing the group, or a REST 5xx. This job is the safety net that makes
    the RolePublish.db audit store -- not the group's live relevance text -- the actual
    source of truth (D-05).

    Per role:
      1. Get-CurrentRoleUsers (RoleGroupRelevance.psm1) -> the role's current membership
         from the MAX(RunID) snapshot.
      2. New-RoleGroupRelevance (RoleGroupRelevance.psm1) -> the EXPECTED relevance --
         byte-identical to fixlet_role_manager.ojo's buildRoleGroupRelevance (07-04).
      3. Find the role's Computer Group by title ($GroupTitlePrefix + role) via GET
         computergroups/custom/<site> (PLURAL, list). If none exists, log [MISSING] and
         move on -- this job never POSTs to computergroups/custom.
      4. GET the group's live relevance via GET computergroup/custom/<site>/<id>
         (SINGULAR).
      5. Compare (CDATA-unwrap + surrounding-whitespace-only normalisation, no case
         folding). Equal -> [OK]. Different -> PUT a freshly-built <ComputerGroup>
         document (never a mutated fetch) and log [DRIFT-FIXED] with a short excerpt --
         or, under -WhatIf, log [WOULD PUT] and issue no PUT.
      6. Any per-role exception is caught, logged [FAIL], written to the Windows Event
         Log (8050), and the loop continues with the next role -- one role's failure
         never aborts the run. The run exits non-zero only when every role failed.

    -DatabasePath points at RolePublish.db (the D-05 audit store) -- NOT the content
    pipeline's unrelated automation-state database. Pointing this script at the wrong
    file is a distinct, actionable abort (see .NOTES), not a silent zero-role no-op.

.PARAMETER DatabasePath
    Full path to RolePublish.db, the D-05 root-server audit store this job reads. This is
    a DIFFERENT file from the content pipeline's unrelated automation-state database --
    passing that path here aborts with a distinct exit code (5503) rather than silently
    reporting zero roles.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder).

.PARAMETER BESRootUrl
    BigFix REST API base URL. When omitted, this script makes one best-effort attempt to
    read a PipelineConfig.BESRootUrl row from -DatabasePath (harmless no-op against a
    RolePublish.db that carries no PipelineConfig table) and otherwise falls back to
    'https://localhost:52311' -- the correct default for a job that always runs locally,
    as SYSTEM, on the BES root server itself.

.PARAMETER SiteName
    The custom site the role Computer Groups live in. Default 'Dereso Software Portal'.

.PARAMETER GroupTitlePrefix
    Prefix used to locate each role's Computer Group by title. Default 'DSP Role - '.

.PARAMETER Credential
    BigFix operator [pscredential]. When omitted, fetched at runtime via
    scripts/Get-BigFixCredential.ps1 (AKeyless universal identity, D-20) -- exactly as
    scripts/Invoke-ContentSync.ps1 does. Tests pass a dummy so Invoke-RestMethod can be
    exercised (or fail fast against an unreachable host) without a live AKeyless
    round-trip.

.PARAMETER Role
    Optional filter: only sync this one role. Omit to sync every role with at least one
    RolePublishRun row.

.PARAMETER RunId
    Run id used in the per-run JSON log. Defaults to a fresh GUID.

.PARAMETER LogDir
    Directory the per-run JSON log is written to. Defaults to <repo>\logs.

.PARAMETER SqliteHelperPath
    Path to the shared Dashboard_4_samples\Sqlite-Helper.ps1.

.PARAMETER RoleModulePath
    Path to scripts\RoleGroupRelevance.psm1 (written in 07-05 Task 1). Defaults next to
    this script.

.PARAMETER WhatIf
    Performs every GET and comparison, logs what it WOULD PUT, and issues zero PUT calls.

.NOTES
    PowerShell 5.1+ (root server prefers pwsh 7). Constrained Language Mode safe -- no
    dynamic .NET type-loading, no System.Data.SQLite.

    Exit codes 5500-5599:
      5500  Sqlite-Helper.ps1 or RoleGroupRelevance.psm1 not found
      5501  sqlite3.exe not found under -SQLDir
      5502  -DatabasePath file does not exist
      5503  -DatabasePath opened but has no RolePublishRun table -- "is not a
            RolePublish.db audit store" (the exact failure mode a wrong -DatabasePath
            produces; never silently reports zero roles)
      5510  every role failed (Event 8050 written per failure; the run still attempted
            every role -- see T-07-05-05)

    Windows Event Log (Source 'DereseSoftwarePortal', LogName Application):
      8050  a role's drift-check failed (role-scoped; the run continues)
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\RolePublish.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$BESRootUrl,

    [Parameter()]
    [string]$SiteName = 'Dereso Software Portal',

    [Parameter()]
    [string]$GroupTitlePrefix = 'DSP Role - ',

    [Parameter()]
    [pscredential]$Credential,

    [Parameter()]
    [string]$Role,

    [Parameter()]
    [string]$RunId = ([guid]::NewGuid().ToString()),

    [Parameter()]
    [string]$LogDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'),

    [Parameter()]
    [string]$SqliteHelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Dashboard_4_samples\Sqlite-Helper.ps1'),

    [Parameter()]
    [string]$RoleModulePath = (Join-Path $PSScriptRoot 'RoleGroupRelevance.psm1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:EventLogSource = 'DereseSoftwarePortal'

function Write-Tag {
    param([string]$Tag, [string]$Message)
    Write-Host "[$Tag] $Message"
}

function Write-SrgEvent {
    param([int]$EventId, [string]$Message, [string]$EntryType = 'Error')
    try {
        Write-EventLog -LogName Application -Source $script:EventLogSource -EntryType $EntryType `
            -EventId $EventId -Message $Message -WhatIf:$false
    } catch { }
}

# --- Step 1: resolve tooling (no DB / no REST yet) --------------------------------------
if (-not (Test-Path -LiteralPath $SqliteHelperPath) -or -not (Test-Path -LiteralPath $RoleModulePath)) {
    Write-Tag 'ABORT' "Sqlite-Helper.ps1 or RoleGroupRelevance.psm1 not found (helper: $SqliteHelperPath ; module: $RoleModulePath)"
    exit 5500
}
$sqlite3Exe = Join-Path $SQLDir 'sqlite3.exe'
if (-not (Test-Path -LiteralPath $sqlite3Exe)) {
    Write-Tag 'ABORT' "sqlite3.exe not found at: $sqlite3Exe (set -SQLDir to the directory containing it)"
    exit 5501
}

. $SqliteHelperPath
# RoleGroupRelevance.psm1's Get-CurrentRoleUsers calls Invoke-SqliteCommand but dot-sources
# nothing itself (by design -- see the module's own comment-based help). A module imported
# via Import-Module always resolves its parent scope to the SESSION'S global scope, never
# to this script's own local scope, so the function just dot-sourced above (scoped to THIS
# script) is otherwise invisible from inside the module. Promoting the single entry-point
# function to global scope closes that gap; Invoke-SqliteCommand's own internal calls to
# its private helpers (ConvertTo-SqliteLiteral etc.) keep resolving correctly because a
# PowerShell ScriptBlock's command lookups follow its original lexical definition context,
# not the scope it is later invoked from.
Set-Item -Path function:\global:Invoke-SqliteCommand -Value (Get-Item function:\Invoke-SqliteCommand).ScriptBlock -WhatIf:$false
Import-Module $RoleModulePath -Force

if (-not (Test-Path -LiteralPath $DatabasePath)) {
    Write-Tag 'ABORT' "RolePublish.db not found at: $DatabasePath"
    exit 5502
}

function Get-SrgRows {
    param([string]$Sql, [hashtable]$P = @{})
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P
    return @($r | ForEach-Object { $_ })
}

# --- Step 2: wrong-database guard --------------------------------------------------------
$tableCheck = @(Get-SrgRows "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name='RolePublishRun'")
if ($tableCheck.Count -eq 0 -or [int]$tableCheck[0].n -eq 0) {
    Write-Tag 'ABORT' "$DatabasePath is not a RolePublish.db audit store"
    exit 5503
}

$roleSql = "SELECT DISTINCT Role FROM RolePublishRun"
$roleParams = @{}
if (-not [string]::IsNullOrWhiteSpace($Role)) {
    $roleSql += " WHERE Role = @role"
    $roleParams['role'] = $Role
}
$roles = @(Get-SrgRows $roleSql $roleParams | ForEach-Object { [string]$_.Role } | Where-Object { $_ -ne '' })

Write-Tag 'INFO' "$($roles.Count) role(s) selected from $DatabasePath"

# --- Step 3: resolve BESRootUrl -----------------------------------------------------------
# Best-effort: this job's -DatabasePath is RolePublish.db, which carries no PipelineConfig
# table, so this probe is normally a harmless no-op and the SYSTEM-local default applies.
if (-not $BESRootUrl) {
    $BESRootUrl = 'https://localhost:52311'
    try {
        $cfgRows = @(Get-SrgRows "SELECT Value FROM PipelineConfig WHERE Key = 'BESRootUrl'")
        if ($cfgRows.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$cfgRows[0].Value)) {
            $BESRootUrl = [string]$cfgRows[0].Value
        }
    } catch { }
}

# --- Step 4: resolve credential + REST extras --------------------------------------------
$cred = $Credential
if (-not $cred) {
    $cred = & (Join-Path $PSScriptRoot 'Get-BigFixCredential.ps1')
}

$irm = @{}
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $irm['SkipCertificateCheck'] = $true
} else {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

# =============================================================================
# helpers
# =============================================================================

function ConvertTo-SrgXml {
    param($Response)
    if ($Response -is [xml]) { return $Response }
    return [xml]([string]$Response)
}

function Find-SrgGroupIdByTitle {
    param(
        [Parameter(Mandatory)][string]$Title,
        [pscredential]$Cred,
        [hashtable]$IrmExtra = @{}
    )
    $siteEnc = [uri]::EscapeDataString($SiteName)
    $uri = "$($BESRootUrl.TrimEnd('/'))/api/computergroups/custom/$siteEnc"
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Credential $Cred @IrmExtra
    $xml = ConvertTo-SrgXml -Response $resp
    $nodes = $xml.SelectNodes('//ComputerGroup')
    foreach ($n in $nodes) {
        $nameNode = $n.SelectSingleNode('Name')
        if ($nameNode -and ([string]$nameNode.InnerText) -eq $Title) {
            $idNode = $n.SelectSingleNode('ID')
            if ($idNode) { return [string]$idNode.InnerText }
        }
    }
    return $null
}

function Get-SrgGroupRelevance {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [pscredential]$Cred,
        [hashtable]$IrmExtra = @{}
    )
    $siteEnc = [uri]::EscapeDataString($SiteName)
    $uri = "$($BESRootUrl.TrimEnd('/'))/api/computergroup/custom/$siteEnc/$GroupId"
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Credential $Cred @IrmExtra
    $xml = ConvertTo-SrgXml -Response $resp
    $node = $xml.SelectSingleNode('//SearchComponentRelevance/Relevance')
    if (-not $node) { return '' }
    return ([string]$node.InnerText).Trim()
}

function New-SrgComputerGroupXml {
    <#
      Six-element <ComputerGroup> body -- Title/Domain/JoinByIntersection/IsDynamic/
      EvaluateOnClient/SearchComponentRelevance -- matching fixlet_role_manager.ojo's
      buildComputerGroupXml() (07-04), itself the exact shape 07-01's live spike
      confirmed the BES REST API accepts and round-trips (07-SPIKE-FINDINGS.md Check A).
      Always built from scratch -- never a mutated fetched document.
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Relevance,
        [string]$Domain = 'BESC'
    )
    $escTitle  = [System.Security.SecurityElement]::Escape($Title)
    $escDomain = [System.Security.SecurityElement]::Escape($Domain)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n")
    [void]$sb.Append('<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">' + "`r`n")
    [void]$sb.Append("  <ComputerGroup>`r`n")
    [void]$sb.Append("    <Title>$escTitle</Title>`r`n")
    [void]$sb.Append("    <Domain>$escDomain</Domain>`r`n")
    [void]$sb.Append("    <JoinByIntersection>true</JoinByIntersection>`r`n")
    [void]$sb.Append("    <IsDynamic>true</IsDynamic>`r`n")
    [void]$sb.Append("    <EvaluateOnClient>true</EvaluateOnClient>`r`n")
    [void]$sb.Append("    <SearchComponentRelevance Comparison=`"IsTrue`">`r`n")
    [void]$sb.Append("      <Relevance><![CDATA[$Relevance]]></Relevance>`r`n")
    [void]$sb.Append("    </SearchComponentRelevance>`r`n")
    [void]$sb.Append("  </ComputerGroup>`r`n")
    [void]$sb.Append('</BES>')
    return $sb.ToString()
}

function Set-SrgGroupRelevance {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Relevance,
        [pscredential]$Cred,
        [hashtable]$IrmExtra = @{}
    )
    $siteEnc = [uri]::EscapeDataString($SiteName)
    $uri = "$($BESRootUrl.TrimEnd('/'))/api/computergroup/custom/$siteEnc/$GroupId"
    $xml = New-SrgComputerGroupXml -Title $Title -Relevance $Relevance
    Invoke-RestMethod -Method Put -Uri $uri -Credential $Cred -Body $xml -ContentType 'application/xml' @IrmExtra | Out-Null
}

function Get-SrgExcerpt {
    param([string]$Text, [int]$MaxLen = 120)
    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $MaxLen) { return $Text }
    return $Text.Substring(0, $MaxLen) + '...'
}

# =============================================================================
# main
# =============================================================================

if ($WhatIfPreference) {
    Write-Tag 'WHATIF' 'dry-run: every role is GET-compared; no ComputerGroup PUT will be issued this run'
}

$outcomes = @{ ok = 0; fixed = 0; missing = 0; failed = 0 }
$roleLog = New-Object System.Collections.ArrayList

foreach ($r in $roles) {
    try {
        $currentUsers = Get-CurrentRoleUsers -DatabasePath $DatabasePath -SQLDir $SQLDir -Role $r
        $expected     = New-RoleGroupRelevance -UserName $currentUsers
        $groupTitle   = $GroupTitlePrefix + $r

        $groupId = Find-SrgGroupIdByTitle -Title $groupTitle -Cred $cred -IrmExtra $irm
        if (-not $groupId) {
            Write-Tag 'MISSING' $r
            $outcomes.missing++
            [void]$roleLog.Add([pscustomobject]@{ role = $r; outcome = 'missing' })
            continue
        }

        $live = Get-SrgGroupRelevance -GroupId $groupId -Cred $cred -IrmExtra $irm

        if ($live.Trim() -ceq $expected.Trim()) {
            Write-Tag 'OK' $r
            $outcomes.ok++
            [void]$roleLog.Add([pscustomobject]@{ role = $r; outcome = 'ok' })
        } else {
            $beforeExcerpt = Get-SrgExcerpt -Text $live
            $afterExcerpt  = Get-SrgExcerpt -Text $expected
            if ($WhatIfPreference) {
                Write-Tag 'WOULD PUT' "$r  before='$beforeExcerpt'  after='$afterExcerpt'"
            } else {
                Set-SrgGroupRelevance -GroupId $groupId -Title $groupTitle -Relevance $expected -Cred $cred -IrmExtra $irm
                Write-Tag 'DRIFT-FIXED' "$r  before='$beforeExcerpt'  after='$afterExcerpt'"
            }
            $outcomes.fixed++
            [void]$roleLog.Add([pscustomobject]@{ role = $r; outcome = 'drift-fixed'; before = $beforeExcerpt; after = $afterExcerpt })
        }
    } catch {
        $outcomes.failed++
        $msg = $_.Exception.Message
        Write-Tag 'FAIL' "$r $msg"
        Write-Warning "[FAIL] $r $msg; continuing with the next role"
        Write-SrgEvent -EventId 8050 -Message "Role Computer Group drift-check FAILED for role '$r': $msg"
        [void]$roleLog.Add([pscustomobject]@{ role = $r; outcome = 'failed'; error = $msg })
    }
}

# --- run summary JSON (same directory convention as Invoke-ContentSync.ps1) -------------
$started = (Get-Date).ToUniversalTime()
$log = [pscustomobject]@{
    run_id       = $RunId
    type         = 'RoleGroupSync'
    whatif       = [bool]$WhatIfPreference
    database     = $DatabasePath
    site         = $SiteName
    started      = $started.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    roles_total  = $roles.Count
    ok           = $outcomes.ok
    fixed        = $outcomes.fixed
    missing      = $outcomes.missing
    failed       = $outcomes.failed
    roles        = @($roleLog)
}

try {
    New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null
    $logPath = Join-Path $LogDir ("sync-rolegroups-{0}.json" -f $started.ToString('yyyyMMdd-HHmmss'))
    Set-Content -Path $logPath -Value ($log | ConvertTo-Json -Depth 6 -Compress) -Encoding UTF8 -WhatIf:$false
} catch {
    Write-Warning "[LOG] could not write run summary JSON to $LogDir : $($_.Exception.Message)"
}

Write-Host "----RUN SUMMARY----"
Write-Host ($log | ConvertTo-Json -Depth 6 -Compress)
Write-Host ("[DONE] Sync-RoleGroups complete{0}." -f $(if ($WhatIfPreference) { ' [WhatIf - no PUT calls made]' } else { '' }))

if ($roles.Count -gt 0 -and $outcomes.failed -eq $roles.Count) {
    exit 5510
}
exit 0
