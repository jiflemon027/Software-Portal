#Requires -Version 5.1
<#
.SYNOPSIS
    Endpoint reconcile (07-02). Upserts the console user's roles from this region's
    snapshot JSON into the local RoleAwareness.db Map table, using the D-12 discipline
    (INSERT OR IGNORE + a conditional UPDATE guarded by Locked_by_Override = 0) and
    writing the four provenance columns Source_Type / Source_Value / Region / Assigned_By.

.DESCRIPTION
    Runs on managed endpoints under PowerShell 5.1 and Constrained Language Mode: no
    dynamic .NET type loading, no ADO SQLite provider, no stream-reader objects - every
    database call goes through Sqlite-Helper.ps1 (bundled sqlite3.exe).

    Two invocation paths:

      * Policy-action path (bes/RoleRef-Policy-template.bes) - always passes -ConsoleUser,
        substituted from client relevance (PipelineConfig.ConsoleUserRelevance, default
        "name of current user"). That one config key stays the single seam for a later
        switch to the plural "names of logged on users" (RESEARCH Pitfall 2).

      * RoleDB_Maintenance logon-task path (D-19) - runs as SYSTEM with NO relevance
        engine, so it passes -ConsoleUser blank and -Region blank. When -ConsoleUser is
        blank this script falls back to the explorer.exe / GetOwner query that
        Initialize-RoleDb.ps1 already uses; when -Region is blank it reads the
        GPC_Sub_Name client setting from the local BES client registry. Both fallbacks
        are user-approved (2026-08-29) and are SCOPED TO THE LOGON-TASK PATH ONLY -
        D-04's "no GetOwner" applies to the policy-action path, which never hits either
        fallback.

    Region is checked twice (defence in depth, D-15): the policy Fixlet's <Relevance>
    gates on GPC_Sub_Name, and this script ABORTS if snapshot.region (the field INSIDE
    the file, not the file name) does not equal -Region.

    "General Access" is the implicit default for a user with no specific server-side
    role. It is never enumerated in a snapshot. A console user who matches no role block
    is the NORMAL case: this script writes no AxoniousSync role, writes the freshness
    stamp exactly as on a matching run, logs [OK], and exits 0 - it is not an error, not
    a warning, and raises no Event Log entry.

    There is NO revoke path in v1 (D-16). A role the user no longer holds is simply not
    renewed and lapses at Valid_to.

.PARAMETER ConsoleUser
    The console user's bare lower-cased sAMAccountName. Blank => GetOwner fallback
    (logon-task path only).

.PARAMETER Region
    The endpoint's own GPC_Sub_Name. Blank => read it from the local BES client
    registry (logon-task path only).

.PARAMETER SnapshotDir
    Directory holding roleref-<region-lc>-latest.json.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly.

.PARAMETER DatabasePath
    Full path to RoleAwareness.db.

.PARAMETER ValidityMonths
    How far forward a reconciled row's Valid_to is pushed. Default 6 (mirrors
    Initialize-RoleDb.ps1 -ValidityMonths / PORTAL_CONFIG.validityMonths).

.PARAMETER SqliteHelperPath
    Path to the shared Sqlite-Helper.ps1 (default: next to this script - the endpoint
    layout under EC\SoftwarePortal).

.PARAMETER SnapshotShapePath
    Optional path to tests/pester/Assert-SnapshotShape.ps1. When present the snapshot is
    validated against that single shared contract in addition to the inline checks. Not
    shipped to endpoints - absence is fine.

.PARAMETER StampRegistryPath
    BES client "manual setting" registry root. Default is the real client path; tests
    point it at a writable HKCU key. The freshness stamp is written as a subkey
    roleref_<region-lc>_applied with `value` + `effective date` string values.

.NOTES
    PowerShell 5.1, Constrained Language Mode safe. Error/abort via throw (non-zero
    exit); [SKIP] / [OK] no-match cases return 0.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$ConsoleUser,

    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$SnapshotDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SoftwarePortal\roleref',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SoftwarePortal\RoleAwareness.db',

    [Parameter()]
    [int]$ValidityMonths = 6,

    [Parameter()]
    [string]$SqliteHelperPath = (Join-Path $PSScriptRoot 'Sqlite-Helper.ps1'),

    [Parameter()]
    [string]$SnapshotShapePath = (Join-Path $PSScriptRoot 'Assert-SnapshotShape.ps1'),

    [Parameter()]
    [string]$StampRegistryPath = 'HKLM:\SOFTWARE\Wow6432Node\BigFix\EnterpriseClient\Settings\Client'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logfile = Join-Path (Split-Path $DatabasePath) 'SWDlog.log'

function Write-Tag {
    param([string]$Tag, [string]$Message)
    $line = "[$Tag] $Message"
    Write-Host $line
    try { Add-Content -Path $logfile -Value ("{0} reconcile {1}" -f (Get-Date -Format 's'), $line) -WhatIf:$false } catch { }
}

function Get-DbRows {
    # Flatten Sqlite-Helper's (return ,$rows) wrapper so multi-row .Count is correct.
    param([string]$Sql, [hashtable]$P = @{})
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P
    return @($r | ForEach-Object { $_ })
}

function Invoke-DbWrite {
    param([string]$Sql, [hashtable]$P = @{})
    if ($WhatIfPreference) { return }
    Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P | Out-Null
}

if (-not (Test-Path $SqliteHelperPath)) { throw "Sqlite-Helper.ps1 not found at: $SqliteHelperPath" }
. $SqliteHelperPath

$result = [ordered]@{
    whatif               = [bool]$WhatIfPreference
    console_user         = $null
    region               = $null
    roles_matched        = 0
    rows_updated         = 0
    rows_blocked_by_lock = 0
    roles_created        = 0
    stamp_written        = $false
    outcome              = $null
}

function Write-ReconcileLog {
    $dir = Split-Path $DatabasePath
    $path = Join-Path $dir ("reconcile-{0}.json" -f ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')))
    try {
        Set-Content -Path $path -Value ([pscustomobject]$result | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8 -WhatIf:$false
    } catch { }
    Write-Host "----RUN SUMMARY----"
    Write-Host ([pscustomobject]$result | ConvertTo-Json -Depth 5 -Compress)
}

# --- console user resolution --------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ConsoleUser)) {
    # Logon-task path ONLY (see D-04 SCOPING NOTE in the header): SYSTEM, no relevance engine.
    try {
        $owner = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue |
            Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty User -ErrorAction SilentlyContinue)
        if ($owner.Count -gt 0 -and $owner[0]) {
            $ConsoleUser = ($owner[0].Split('\')[-1])
        }
    } catch { }
}
if ([string]::IsNullOrWhiteSpace($ConsoleUser)) {
    Write-Tag 'SKIP' 'no console user (unattended host) - nothing to reconcile'
    $result.outcome = 'skip-no-console-user'
    Write-ReconcileLog
    return
}
$ConsoleUser = $ConsoleUser.ToLowerInvariant()
$result.console_user = $ConsoleUser

# --- region resolution -----------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Region)) {
    # Logon-task path ONLY: read the endpoint's own GPC_Sub_Name from the BES client registry.
    try {
        $rk = Join-Path $StampRegistryPath 'GPC_Sub_Name'
        if (Test-Path $rk) { $Region = [string](Get-ItemProperty -Path $rk -Name 'value' -ErrorAction SilentlyContinue).value }
    } catch { }
}
if ([string]::IsNullOrWhiteSpace($Region)) {
    Write-Tag 'SKIP' 'no region (GPC_Sub_Name not set and -Region not passed)'
    $result.outcome = 'skip-no-region'
    Write-ReconcileLog
    return
}
$result.region = $Region
$rlc = $Region.ToLowerInvariant()

# --- load + validate the snapshot (region checked against the BODY, not the name) --
$snapPath = Join-Path $SnapshotDir ("roleref-{0}-latest.json" -f $rlc)
if (-not (Test-Path $snapPath)) {
    throw "[ABORT] snapshot file not found: $snapPath"
}
$snapRaw = Get-Content -Raw -Path $snapPath
try {
    $snap = $snapRaw | ConvertFrom-Json
} catch {
    throw "[ABORT] snapshot is not valid JSON: $snapPath ($($_.Exception.Message))"
}
if ($null -eq $snap -or -not ($snap.PSObject.Properties.Name -contains 'roles')) {
    throw "[ABORT] snapshot has no 'roles' array: $snapPath"
}
$rolesIsArray = ($snap.roles -is [System.Array]) -or ($snap.roles -is [System.Collections.IEnumerable] -and $snap.roles -isnot [string])
if (-not $rolesIsArray) {
    throw "[ABORT] snapshot 'roles' is not an array: $snapPath"
}
if (-not ($snap.PSObject.Properties.Name -contains 'region') -or `
    [string]::Compare([string]$snap.region, $Region, [System.StringComparison]::OrdinalIgnoreCase) -ne 0) {
    throw "[ABORT] snapshot region mismatch: file body says '$($snap.region)', endpoint region is '$Region' - refusing to apply"
}
if (Test-Path $SnapshotShapePath) {
    . $SnapshotShapePath
    Assert-RoleRefSnapshotShape -Snapshot $snap -ExpectedRegion $Region | Out-Null
}

$builtOn = [string]$snap.built_on

# --- find this console user's roles in the snapshot -------------------------
$matched = @()
foreach ($roleEntry in @($snap.roles)) {
    foreach ($u in @($roleEntry.users)) {
        if ($null -eq $u) { continue }
        if ([string]::Compare([string]$u.id, $ConsoleUser, [System.StringComparison]::OrdinalIgnoreCase) -eq 0) {
            $matched += [pscustomobject]@{
                Role         = [string]$roleEntry.role
                Source_Type  = [string]$u.source_type
                Source_Value = [string]$u.source_value
            }
        }
    }
}
$result.roles_matched = $matched.Count

# --- per-role D-12 upsert --------------------------------------------------
$validModifier = "+$ValidityMonths months"
foreach ($m in $matched) {
    if ($WhatIfPreference) {
        Write-Tag 'WOULD' ("upsert Map: user='{0}' role='{1}' Source_Type='{2}' Source_Value='{3}' Region='{4}' Assigned_By='AxoniousSync' Valid_to=now{5}" -f `
            $ConsoleUser, $m.Role, $m.Source_Type, $m.Source_Value, $Region, $validModifier)
        continue
    }

    # 1. role new to this endpoint propagates without an init redeploy (D-15)
    $before = @(Get-DbRows "SELECT COUNT(*) AS n FROM Roles WHERE Role = @r" @{ r = $m.Role })
    Invoke-DbWrite "INSERT OR IGNORE INTO Roles (Role) VALUES (@r)" @{ r = $m.Role }
    $after = @(Get-DbRows "SELECT COUNT(*) AS n FROM Roles WHERE Role = @r" @{ r = $m.Role })
    if ([int]$before[0].n -eq 0 -and [int]$after[0].n -eq 1) { $result.roles_created++ }

    # 2. create the Map row if absent, without disturbing any existing state
    Invoke-DbWrite "INSERT OR IGNORE INTO Map (UserID, Role, Active, Created_on) VALUES (@u, @r, 1, datetime('now','localtime'))" `
        @{ u = $ConsoleUser; r = $m.Role }

    # 3. guarded UPDATE + connection-scoped changes() in ONE call
    $upd = @(Get-DbRows @"
UPDATE Map SET Active = 1, Updated_on = datetime('now','localtime'),
    Valid_to = datetime('now','localtime', @v),
    Source_Type = @st, Source_Value = @sv, Region = @rg, Assigned_By = 'AxoniousSync'
WHERE UserID = @u AND Role = @r AND Locked_by_Override = 0;
SELECT changes() AS n
"@ @{ v = $validModifier; st = $m.Source_Type; sv = $m.Source_Value; rg = $Region; u = $ConsoleUser; r = $m.Role })
    $changed = if ($upd.Count -gt 0) { [int]$upd[0].n } else { 0 }

    # keep the endpoint Users row fresh (INSERT OR IGNORE + UPDATE - never a delete-and-reinsert)
    Invoke-DbWrite "INSERT OR IGNORE INTO Users (UserID, LastSeen) VALUES (@u, datetime('now','localtime'))" @{ u = $ConsoleUser }
    Invoke-DbWrite "UPDATE Users SET LastSeen = datetime('now','localtime') WHERE UserID = @u" @{ u = $ConsoleUser }

    if ($changed -gt 0) {
        $result.rows_updated += $changed
        Write-Tag 'UPSERT' ("user='{0}' role='{1}' -> Assigned_By=AxoniousSync, Region='{2}', Valid_to +{3}mo, Source='{4}'/'{5}'" -f `
            $ConsoleUser, $m.Role, $Region, $ValidityMonths, $m.Source_Type, $m.Source_Value)
    } else {
        $lockRow = @(Get-DbRows "SELECT COUNT(*) AS n FROM Map WHERE UserID = @u AND Role = @r AND Locked_by_Override = 1" @{ u = $ConsoleUser; r = $m.Role })
        if ([int]$lockRow[0].n -gt 0) {
            $result.rows_blocked_by_lock++
            Write-Tag 'LOCKED' ("user='{0}' role='{1}' has Locked_by_Override=1 - left untouched" -f $ConsoleUser, $m.Role)
        }
    }
}

# --- freshness stamp (written on BOTH a matching run and the General-Access no-match run) --
function Set-RoleRefStamp {
    param([string]$Value)
    if ($WhatIfPreference) { return $false }
    $ok = $false
    # sidecar file next to the snapshots - cheap, always writable, useful for diagnostics
    try {
        Set-Content -Path (Join-Path $SnapshotDir ("roleref_{0}_applied.json" -f $rlc)) `
            -Value ([pscustomobject]@{ region = $Region; built_on = $Value; stamped_on = (Get-Date).ToUniversalTime().ToString('s') } | ConvertTo-Json -Compress) `
            -Encoding UTF8 -WhatIf:$false
        $ok = $true
    } catch { }
    # BES client "manual setting" registry key: <root>\roleref_<rlc>_applied with value + effective date
    try {
        $key = Join-Path $StampRegistryPath ("roleref_{0}_applied" -f $rlc)
        if (-not (Test-Path $key)) { New-Item -Path $key -Force -WhatIf:$false | Out-Null }
        $eff = (Get-Date).ToUniversalTime().ToString("ddd, dd MMM yyyy HH:mm:ss +0000", [System.Globalization.CultureInfo]::InvariantCulture)
        New-ItemProperty -Path $key -Name 'value' -Value $Value -PropertyType String -Force -WhatIf:$false | Out-Null
        New-ItemProperty -Path $key -Name 'effective date' -Value $eff -PropertyType String -Force -WhatIf:$false | Out-Null
        $ok = $true
    } catch {
        Write-Tag 'WARN' ("freshness stamp (client setting) not written: {0} - the action will re-run, which is safe" -f $_.Exception.Message)
    }
    return $ok
}

if ($matched.Count -eq 0) {
    Write-Tag 'OK' 'no specific role in snapshot - General Access default (routine, not an error)'
    $result.outcome = 'general-access-default'
} else {
    $result.outcome = 'reconciled'
}

if (-not $WhatIfPreference) {
    $result.stamp_written = [bool](Set-RoleRefStamp -Value $builtOn)
}

Write-ReconcileLog
return
