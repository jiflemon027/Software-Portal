#Requires -Version 5.1
<#
.SYNOPSIS
    Daily streaming ingest of the Axonius user export into AutomationState.db.

.DESCRIPTION
    This is the only place the external world enters the role pipeline (07-CONTEXT D-05..D-09).
    The export (~383-401 MB, 47 columns, UTF-8 BOM, RFC-4180 with quoted embedded newlines) is
    streamed with a single unassigned  Import-Csv | ForEach-Object  pipeline so working set
    stays bounded (07-RESEARCH Pitfall 1 / Pitfall 9). Never assign the pipeline to a variable;
    never place Select-Object / Where-Object / Sort-Object / Group-Object inside the loop.

    CLM-safe: every database call goes through Dashboard_4_samples\Sqlite-Helper.ps1
    (the sqlite3.exe CLI). No dynamic .NET type loading, no ADO SQLite provider, no
    hand-rolled line reader - the streaming CSV parser is the built-in Import-Csv cmdlet.

    Wave-1 Task 1 scope: streaming reader + 11-column header/BOM validation + stale-file guard
    (warn, never abort) + SyncRun(Type='Ingest') open/finalise + per-run JSON log + the single
    -WhatIf write gate. The per-row transform, GroupRoleMap resolution, batched upsert and the
    age-out sweep are layered on by Tasks 2-4.

.PARAMETER DatabasePath
    Full path to AutomationState.db on the root server.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder).

.PARAMETER SqliteHelperPath
    Path to the single shared Sqlite-Helper.ps1 (dot-sourced; never copied into scripts\).

.PARAMETER ExportPath
    Full path to the Axonius CSV. Falls back to PipelineConfig.AxoniousExportPath.

.PARAMETER RunId
    Ingest run identifier. Generated as [guid]::NewGuid().ToString('N') when not supplied.

.PARAMETER BatchSize
    Rows per batched INSERT transaction (Tasks 3-4). Default 400.

.PARAMETER LogDir
    Directory for the per-run JSON log. Defaults to a 'logs' folder beside AutomationState.db.

.PARAMETER WhatIf
    Full read + all counting + the JSON log, and ZERO database writes - including the SyncRun
    insert. Every write routes through Invoke-DbWrite so the gate exists in exactly one place.

.NOTES
    Error codes (continuing the Initialize-RoleDb.ps1 / Initialize-AutomationDb.ps1 scheme):
      6700  header validation: one or more of the 11 required columns is missing
      6710  no -ExportPath supplied and PipelineConfig.AxoniousExportPath is empty
      6720  export contains a header but no data rows
    Windows Event Log (source 'DereseSoftwarePortal', LogName Application):
      8010  stale export warning        8011  GroupRoleMap has no active rules
      8012  age-out sweep brake tripped 8013  terminating failure
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$SqliteHelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Dashboard_4_samples\Sqlite-Helper.ps1'),

    [Parameter()]
    [string]$ExportPath,

    [Parameter()]
    [string]$RunId,

    [Parameter()]
    [int]$BatchSize = 400,

    [Parameter()]
    [string]$LogDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EventLogSource = 'DereseSoftwarePortal'

# The 11 columns the pipeline depends on (V5 input validation). Missing any = hard abort 6700.
$RequiredColumns = @(
    'Azure Ad: AD sAMAccountName',
    'Azure Ad: AD User Principal Name',
    'Aggregated: User Name',
    'Aggregated: Display Name',
    'Aggregated: Domain',
    'Aggregated: Adapter Connections',
    'Aggregated: Assigned Groups: Name',
    'Aggregated: Assigned Groups: Display Name',
    'Aggregated: Assigned Groups: Group Type',
    'Aggregated: Assigned Groups: Email',
    'Aggregated: Assigned Groups: Adapter Source Application'
)

# --- logging ---------------------------------------------------------------
function Write-Log { param([string]$Message) Write-Host $Message }

function Write-AppEvent {
    param([int]$EventId, [string]$EntryType = 'Warning', [string]$Message)
    # An unregistered source must never mask the underlying condition.
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
            Write-EventLog -LogName Application -Source $EventLogSource -EventId $EventId `
                -EntryType $EntryType -Message $Message -ErrorAction Stop
        }
    } catch { }
}

# --- resolve the shared Sqlite-Helper.ps1 --------------------------------
if (-not (Test-Path $SqliteHelperPath)) {
    throw "Sqlite-Helper.ps1 not found at: $SqliteHelperPath`nPass -SqliteHelperPath pointing at the single shared Dashboard_4_samples\Sqlite-Helper.ps1."
}
. $SqliteHelperPath

# --- pure-function module (the per-row transform test seams) -------------
$ModulePath = Join-Path $PSScriptRoot 'AxoniousParse.psm1'
if (-not (Test-Path $ModulePath)) { throw "AxoniousParse.psm1 not found at: $ModulePath" }
Import-Module $ModulePath -Force

function Get-Field {
    param($Row, [string]$Name)
    $p = $Row.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return '' }
    return [string]$p.Value
}

function Get-DbRows {
    param([string]$Sql, [hashtable]$Parameters = @{})
    return Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $Parameters
}

# The ONE -WhatIf write gate. Every write in this script (all tasks) routes through here.
function Invoke-DbWrite {
    param([string]$Sql, [hashtable]$Parameters = @{})
    if ($WhatIfPreference) { $script:WouldWriteCalls++; return @() }
    return Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $Parameters
}

# --- PipelineConfig ------------------------------------------------------
$cfg = @{}
try {
    foreach ($r in @(Get-DbRows -Sql "SELECT Key, Value FROM PipelineConfig")) {
        if ($null -ne $r.Key) { $cfg[[string]$r.Key] = [string]$r.Value }
    }
} catch { Write-Log "[WARN] could not read PipelineConfig: $($_.Exception.Message)" }

function Get-Cfg {
    param([string]$Key, [string]$Default = '')
    if ($cfg.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace($cfg[$Key])) { return $cfg[$Key] }
    return $Default
}

if ([string]::IsNullOrWhiteSpace($ExportPath)) { $ExportPath = Get-Cfg 'AxoniousExportPath' '' }
if ([string]::IsNullOrWhiteSpace($ExportPath)) {
    Write-Log "[ABORT] 6710 no -ExportPath supplied and PipelineConfig.AxoniousExportPath is empty"
    throw 6710
}
if (-not (Test-Path $ExportPath)) { throw "Export file not found: $ExportPath" }

$maxAgeDays        = [double](Get-Cfg 'MaxExportAgeDays' '2')
$maxAgeOutFraction = [double](Get-Cfg 'MaxAgeOutFraction' '0.5')
$usernamePriority  = Get-Cfg 'UsernameSourcePriority' 'sam,upn,username'

if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = [guid]::NewGuid().ToString('N') }

if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $dbParent = Split-Path $DatabasePath -Parent
    if ([string]::IsNullOrWhiteSpace($dbParent)) { $dbParent = (Get-Location).Path }
    $LogDir = Join-Path $dbParent 'logs'
}
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null }

# --- counters / run state ---------------------------------------------
$script:WouldWriteCalls = 0
$rowsIn            = 0
$usersSeen         = @{}
$rolesSeen         = @{}
$entitlements      = 0
$groupsParsed      = 0
$skippedNoUserName = 0
$agedOut           = 0
$errorCount        = 0
$rulesLoaded       = 0
$sweepApplied      = $false
$staleWarning      = $false
$status            = 'failed'
$startedOn         = (Get-Date).ToString('s')
$syncRunOpened     = $false

$exportItem      = Get-Item $ExportPath
$exportLastWrite = $exportItem.LastWriteTime.ToString('s')

function Write-JsonLog {
    $logPath = Join-Path $LogDir ("Import-AxoniousExport-$RunId.json")
    $body = [ordered]@{
        RunId                = $RunId
        ExportPath           = $ExportPath
        Export_LastWriteTime = $exportLastWrite
        StaleWarning         = [bool]$staleWarning
        Rows_In              = $rowsIn
        Users_Seen           = $usersSeen.Count
        Roles_Seen           = $rolesSeen.Count
        Entitlements         = $entitlements
        Groups_Parsed        = $groupsParsed
        Skipped_NoUserName   = $skippedNoUserName
        Rules_Loaded         = $rulesLoaded
        Aged_Out             = $agedOut
        Sweep_Applied        = [bool]$sweepApplied
        Error_Count          = $errorCount
        Started_on           = $startedOn
        Ended_on             = (Get-Date).ToString('s')
        WhatIf               = [bool]$WhatIfPreference
        Status               = $status
    }
    ($body | ConvertTo-Json -Depth 6) | Set-Content -Path $logPath -Encoding UTF8 -WhatIf:$false
    Write-Log "[LOG] $logPath"
}

Write-Log "----Import-AxoniousExport RunId=$RunId$(if ($WhatIfPreference) { ' [WhatIf]' }) ($startedOn)"

try {
    # --- open the SyncRun row immediately (skipped entirely under -WhatIf) ---
    Invoke-DbWrite -Sql "INSERT INTO SyncRun (RunID, Type, Status) VALUES (@run, 'Ingest', 'running')" `
        -Parameters @{ run = $RunId } | Out-Null
    if (-not $WhatIfPreference) { $syncRunOpened = $true }

    # --- stale-file guard (D-05): WARN and continue, never abort ---------
    $ageDays = (New-TimeSpan -Start $exportItem.LastWriteTime -End (Get-Date)).TotalDays
    if ($ageDays -gt $maxAgeDays) {
        $staleWarning = $true
        Write-Log ("[WARN] export is {0:N1} days old (> {1}) - continuing; a stale export only slows revocation, it never grants" -f $ageDays, $maxAgeDays)
        Write-AppEvent -EventId 8010 -EntryType Warning `
            -Message "Axonius export stale: $([math]::Round($ageDays,1)) days old (limit $maxAgeDays). RunId $RunId. Continuing."
    }

    # --- header / column-map validation (BOM-mangling detector for A8) ---
    $script:firstRow = $null
    Import-Csv -Path $ExportPath | Select-Object -First 1 | ForEach-Object { $script:firstRow = $_ }
    if ($null -eq $script:firstRow) { Write-Log "[ABORT] 6720 export has a header but no data rows"; throw 6720 }

    $headerNames = @($script:firstRow.PSObject.Properties.Name)
    $bomChar     = [char]0xFEFF
    $firstReq    = 'Aggregated: Adapter Connections'
    $colAdapterConns = $firstReq
    if (($headerNames -notcontains $firstReq) -and ($headerNames -contains ($bomChar + $firstReq))) {
        # A BOM corrupts the FIRST header name specifically. Strip it and retry once.
        Write-Log "[INFO] stripping UTF-8 BOM from the first header before validation (A8)"
        $colAdapterConns = $bomChar + $firstReq
        $headerNames = @($headerNames | ForEach-Object { if ($_ -eq ($bomChar + $firstReq)) { $firstReq } else { $_ } })
    }

    $missing = @($RequiredColumns | Where-Object { $headerNames -notcontains $_ })
    if ($missing.Count -gt 0) {
        Write-Log "[ABORT] 6700 missing required column(s): $($missing -join ', ')"
        throw 6700
    }
    Write-Log "[OK] all $($RequiredColumns.Count) required columns present"

    # Logical -> actual column names. Only AdapterConnections is BOM-sensitive.
    $col = @{
        Sam                = 'Azure Ad: AD sAMAccountName'
        Upn                = 'Azure Ad: AD User Principal Name'
        UserName           = 'Aggregated: User Name'
        DisplayName        = 'Aggregated: Display Name'
        Domain             = 'Aggregated: Domain'
        AdapterConnections = $colAdapterConns
        GroupName          = 'Aggregated: Assigned Groups: Name'
        GroupDisplay       = 'Aggregated: Assigned Groups: Display Name'
        GroupType          = 'Aggregated: Assigned Groups: Group Type'
        GroupEmail         = 'Aggregated: Assigned Groups: Email'
        GroupSource        = 'Aggregated: Assigned Groups: Adapter Source Application'
    }

    # --- main streaming loop: ONE unassigned pipeline, no buffering cmdlets ---
    # >>> INGEST LOOP START
    Import-Csv -Path $ExportPath | ForEach-Object {
        $row = $_
        $rowsIn++
        if (($rowsIn % 1000) -eq 0) {
            Write-Log "[SCAN] row $rowsIn ($($usersSeen.Count) users so far)"
        }

        # --- username coalesce (D-06) ---
        $resolved = Resolve-UserName `
            -Sam      (Get-Field $row $col.Sam) `
            -Upn      (Get-Field $row $col.Upn) `
            -UserName (Get-Field $row $col.UserName) `
            -Priority $usernamePriority
        if ($null -eq $resolved) { $skippedNoUserName++; return }
        $uid = $resolved.UserID
        $usersSeen[$uid] = $true

        # --- defensive multi-value group parse (D-07: no index-zip) ---
        $groupRows = Get-GroupRows `
            -Name      (Get-Field $row $col.GroupName) `
            -Display   (Get-Field $row $col.GroupDisplay) `
            -GroupType (Get-Field $row $col.GroupType) `
            -Email     (Get-Field $row $col.GroupEmail) `
            -Source    (Get-Field $row $col.GroupSource)

        $firstAdapter = $null
        foreach ($a in [regex]::Split((Get-Field $row $col.AdapterConnections), "\r\n|\r|\n")) {
            $at = $a.Trim()
            if ($at) { $firstAdapter = $at; break }
        }

        foreach ($g in $groupRows) {
            $rawGroup =
                if (-not [string]::IsNullOrWhiteSpace($g.Name)) { $g.Name }
                elseif (-not [string]::IsNullOrWhiteSpace($g.Display)) { $g.Display }
                else { '' }
            if ($rawGroup -eq '') { continue }
            $groupsParsed++

            $views      = Get-GroupViews -Raw $rawGroup -Display $g.Display
            $sourceType = Get-SourceType -GroupType $g.GroupType -Email $g.Email
            $sourceSystem =
                if (-not [string]::IsNullOrWhiteSpace($g.Source)) { $g.Source }
                elseif ($null -ne $firstAdapter) { $firstAdapter }
                else { $null }

            # Task 3 resolves roles through GroupRoleMap and queues the batched upsert here.
        }
    }
    # <<< INGEST LOOP END

    Write-Log "[DONE] streamed $rowsIn rows"
    if ($status -ne 'partial') { $status = 'success' }

} catch {
    $errorCount++
    $status = 'failed'
    Write-Log "[ERROR] $($_.Exception.Message)"
    Write-AppEvent -EventId 8013 -EntryType Error `
        -Message "Import-AxoniousExport failed (RunId $RunId): $($_.Exception.Message)"
    throw
} finally {
    if ($syncRunOpened) {
        try {
            $summaryText = "Ingest ${RunId}: rows_in=$rowsIn users=$($usersSeen.Count) roles=$($rolesSeen.Count) entitlements=$entitlements aged_out=$agedOut errors=$errorCount status=$status"
            Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE SyncRun SET Ended_on = datetime('now','localtime'), Status = @st, Rows_In = @ri,
       Users_Seen = @us, Roles_Seen = @rs, Entitlements = @en, Error_Count = @ec, Summary = @sm
 WHERE RunID = @run
"@ -Parameters @{ st = $status; ri = $rowsIn; us = $usersSeen.Count; rs = $rolesSeen.Count
                 en = $entitlements; ec = $errorCount; sm = $summaryText; run = $RunId } | Out-Null
        } catch { Write-Log "[WARN] SyncRun finalise failed: $($_.Exception.Message)" }
        try { Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA wal_checkpoint(TRUNCATE)" | Out-Null } catch { }
    }
    try { Write-JsonLog } catch { Write-Log "[WARN] JSON log write failed: $($_.Exception.Message)" }
}
