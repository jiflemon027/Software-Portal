#Requires -Version 5.1
<#
.SYNOPSIS
    Creates the combined AutomationState.db on the BigFix root server: the 11-table
    role + content schema, the 13-value Region seed, the 3 canonical Role names, the
    PipelineConfig key/value seed, and the Windows Event Log source used for failure
    logging by every Phase 7 root-server script.

.DESCRIPTION
    Both Phase 7 pipelines (role + content) share this one SQLite database. Safe to
    re-run: CREATE TABLE IF NOT EXISTS for every table, INSERT OR IGNORE for every
    seed, and a PRAGMA table_info-gated additive-migration hook for future column
    adds. A second run reports [SKIP] for every already-present object and changes no
    row counts.

    CLM-safe: all database access goes through Dashboard_4_samples\Sqlite-Helper.ps1
    (the sqlite3.exe CLI) - no dynamic .NET type loading, no ADO SQLite provider. Same
    house conventions as Initialize-RoleDb.ps1 (INTEGER PRIMARY KEY AUTOINCREMENT,
    datetime('now','localtime'), partial/plain indexes, numeric throw error codes,
    PRAGMA wal_checkpoint(TRUNCATE) in finally).

    Naming resolutions (07-RESEARCH.md, D-01): PipelineConfig (not Config);
    ContentCache (the superseded 2026-08-01 design used a different table name); one
    wide SyncRun table with a Type column and nullable content-only columns.

.PARAMETER DatabasePath
    Full path to AutomationState.db. Default is a path under the BES Server data
    directory; override for a test/scratch DB.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no x64\/x86\ arch subfolder).

.PARAMETER SqliteHelperPath
    Path to the single shared Sqlite-Helper.ps1. Copying that file into scripts\ is
    NOT permitted (single-implementation rule); it is dot-sourced from
    Dashboard_4_samples\ by default. Every scripts\*.ps1 in later plans uses this same
    resolution convention.

.PARAMETER PipelineConfigDefaults
    Path to config\PipelineConfig.defaults.json - the documented seed values for the
    PipelineConfig table. Never contains a secret value.

.PARAMETER WhatIf
    Emit the full plan of [WOULD CREATE] / [WOULD SEED] lines plus a JSON run summary
    and make ZERO write calls (no Invoke-SqliteCommand writes, no New-EventLog).
    Read-only sqlite_master / PRAGMA probes still run so the plan is accurate.

.EXAMPLE
    .\Initialize-AutomationDb.ps1 -DatabasePath .\AutomationState.db -SQLDir .\sqlite

.EXAMPLE
    .\Initialize-AutomationDb.ps1 -WhatIf

.NOTES
    PowerShell 5.1+. No external modules. Constrained Language Mode safe (no dynamic
    .NET type loading).

    Error codes (continuing the Initialize-RoleDb.ps1 numeric scheme):
      6000  Preflight: sqlite3.exe not found under -SQLDir
      6100  Create the 9 role/shared tables
      6150  Create idx_grm_active / idx_userrole_role / idx_userrole_user
      6200  Create the 2 content tables (ContentItem, ContentCache)
      6300  Seed Region (13 fixed GPC_Sub_Name values, D-21)
      6350  Seed Role (IT Operations, Business Operations, Business Default)
      6400  Seed PipelineConfig from config\PipelineConfig.defaults.json (INSERT OR IGNORE)
      6500  Register the Windows Event Log source 'DereseSoftwarePortal'
      6600  PRAGMA table_info-gated additive-migration hook (empty; future column adds)
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
    [string]$PipelineConfigDefaults = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\PipelineConfig.defaults.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EventLogSource = 'DereseSoftwarePortal'

# --- logging -------------------------------------------------------------------
$dbFolder = Split-Path $DatabasePath -Parent
$logfile  = if ($dbFolder) { Join-Path $dbFolder 'SWDlog.log' } else { Join-Path (Get-Location) 'SWDlog.log' }

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    try {
        if ($dbFolder -and (Test-Path $dbFolder)) {
            Add-Content -Path $logfile -Value $Message -WhatIf:$false
        }
    } catch { }
}

# WhatIf-aware wrapper: read-only probes always run; writes are suppressed under -WhatIf.
function Invoke-Db {
    param(
        [Parameter(Mandatory)][string]$Sql,
        [hashtable]$Parameters = @{},
        [switch]$Write
    )
    if ($Write -and $WhatIfPreference) { return @() }
    return Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $Parameters
}

function Test-TableExists {
    param([string]$Name)
    if ($WhatIfPreference -and -not (Test-Path $DatabasePath)) { return $false }
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
        -Sql "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name=@n" `
        -Parameters @{ n = $Name }
    return ($r.Count -gt 0 -and [int]$r[0].n -eq 1)
}

function Get-RowCount {
    param([string]$Table)
    if ($WhatIfPreference -and -not (Test-Path $DatabasePath)) { return 0 }
    if (-not (Test-TableExists -Name $Table)) { return 0 }
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "SELECT COUNT(*) AS n FROM $Table"
    if ($r.Count -gt 0) { return [int]$r[0].n } else { return 0 }
}

Write-Log "----Starting Initialize-AutomationDb ($(Get-Date -Format s))$(if ($WhatIfPreference) { ' [WhatIf]' })"

# --- table DDL ---------------------------------------------------------------
$roleDdl = @"
CREATE TABLE IF NOT EXISTS Role (
  RoleID      INTEGER PRIMARY KEY AUTOINCREMENT,
  Role        TEXT NOT NULL UNIQUE COLLATE NOCASE,
  Description TEXT,
  Active      INTEGER NOT NULL DEFAULT 1,
  Created_on  TEXT NOT NULL DEFAULT (datetime('now','localtime'))
)
"@

$regionDdl = @"
CREATE TABLE IF NOT EXISTS Region (
  RegionID     INTEGER PRIMARY KEY AUTOINCREMENT,
  GPC_Sub_Name TEXT NOT NULL UNIQUE COLLATE NOCASE,
  Description  TEXT,
  Active       INTEGER NOT NULL DEFAULT 1,
  Created_on   TEXT NOT NULL DEFAULT (datetime('now','localtime'))
)
"@

$groupRoleMapDdl = @"
CREATE TABLE IF NOT EXISTS GroupRoleMap (
  GRMID      INTEGER PRIMARY KEY AUTOINCREMENT,
  Pattern    TEXT NOT NULL,
  Match_On   TEXT NOT NULL DEFAULT 'cn',
  Role       TEXT NOT NULL COLLATE NOCASE,
  Priority   INTEGER NOT NULL DEFAULT 100,
  Active     INTEGER NOT NULL DEFAULT 1,
  Notes      TEXT,
  Created_by TEXT,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Updated_on TEXT
)
"@

$refUserDdl = @"
CREATE TABLE IF NOT EXISTS RefUser (
  RefUserID    INTEGER PRIMARY KEY AUTOINCREMENT,
  UserID       TEXT NOT NULL UNIQUE COLLATE NOCASE,
  SamAccount   TEXT,
  Upn          TEXT,
  Display_Name TEXT,
  Domain       TEXT,
  Username_Src TEXT NOT NULL,
  RegionID     INTEGER REFERENCES Region(RegionID),
  First_Seen   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_Seen    TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_RunID   TEXT
)
"@

$userRoleDdl = @"
CREATE TABLE IF NOT EXISTS UserRole (
  URID          INTEGER PRIMARY KEY AUTOINCREMENT,
  UserID        TEXT NOT NULL COLLATE NOCASE,
  Role          TEXT NOT NULL COLLATE NOCASE,
  Source_Type   TEXT NOT NULL,
  Source_Value  TEXT NOT NULL,
  Source_System TEXT,
  Matched_Rule  INTEGER REFERENCES GroupRoleMap(GRMID),
  Active        INTEGER NOT NULL DEFAULT 1,
  First_Seen    TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_Seen     TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_RunID    TEXT,
  UNIQUE (UserID, Role, Source_Value)
)
"@

$rolePublicationDdl = @"
CREATE TABLE IF NOT EXISTS RolePublication (
  RPID       INTEGER PRIMARY KEY AUTOINCREMENT,
  Role       TEXT NOT NULL COLLATE NOCASE,
  RegionID   INTEGER REFERENCES Region(RegionID),
  Active     INTEGER NOT NULL DEFAULT 1,
  Created_by TEXT,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  UNIQUE (Role, RegionID)
)
"@

$snapshotDdl = @"
CREATE TABLE IF NOT EXISTS Snapshot (
  SnapshotID INTEGER PRIMARY KEY AUTOINCREMENT,
  RunID      TEXT NOT NULL,
  Built_on   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  File_Name  TEXT NOT NULL,
  SHA1       TEXT NOT NULL,
  Size_Bytes INTEGER,
  Role_Count INTEGER,
  User_Count INTEGER,
  Region     TEXT,
  Status     TEXT NOT NULL DEFAULT 'built'
)
"@

$syncRunDdl = @"
CREATE TABLE IF NOT EXISTS SyncRun (
  RunID           TEXT PRIMARY KEY,
  Type            TEXT NOT NULL,
  Started_on      TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Ended_on        TEXT,
  Status          TEXT NOT NULL DEFAULT 'running',
  Rows_In         INTEGER,
  Users_Seen      INTEGER,
  Roles_Seen      INTEGER,
  Entitlements    INTEGER,
  Items_Discovered INTEGER,
  Items_Copied    INTEGER,
  Items_Failed    INTEGER,
  Summary         TEXT,
  Error_Count     INTEGER NOT NULL DEFAULT 0
)
"@

$pipelineConfigDdl = @"
CREATE TABLE IF NOT EXISTS PipelineConfig (
  Key         TEXT PRIMARY KEY,
  Value       TEXT,
  Description TEXT
)
"@

# ContentCache is the chosen name per D-01. The superseded 2026-08-01 design used a
# different table name for the same concept; it is not carried forward.
$contentItemDdl = @"
CREATE TABLE IF NOT EXISTS ContentItem (
  fixlet_id    TEXT NOT NULL,
  source_site  TEXT NOT NULL,
  fixlet_name  TEXT NOT NULL,
  stage        TEXT NOT NULL DEFAULT 'discovered',
  category     TEXT,
  roles        TEXT,
  is_task      INTEGER NOT NULL DEFAULT 0,
  copied_at    TEXT,
  dispatched_at TEXT,
  PRIMARY KEY (fixlet_id, source_site)
)
"@

$contentCacheDdl = @"
CREATE TABLE IF NOT EXISTS ContentCache (
  sha1         TEXT PRIMARY KEY,
  filename     TEXT NOT NULL,
  original_url TEXT,
  staged_at    TEXT,
  size_bytes   INTEGER,
  verified     INTEGER NOT NULL DEFAULT 0
)
"@

$roleSharedTables = @(
    @{ Name = 'Role';            Ddl = $roleDdl }
    @{ Name = 'Region';          Ddl = $regionDdl }
    @{ Name = 'GroupRoleMap';    Ddl = $groupRoleMapDdl }
    @{ Name = 'RefUser';         Ddl = $refUserDdl }
    @{ Name = 'UserRole';        Ddl = $userRoleDdl }
    @{ Name = 'RolePublication'; Ddl = $rolePublicationDdl }
    @{ Name = 'Snapshot';        Ddl = $snapshotDdl }
    @{ Name = 'SyncRun';         Ddl = $syncRunDdl }
    @{ Name = 'PipelineConfig';  Ddl = $pipelineConfigDdl }
)
$contentTables = @(
    @{ Name = 'ContentItem';  Ddl = $contentItemDdl }
    @{ Name = 'ContentCache'; Ddl = $contentCacheDdl }
)

# D-21 - exactly these 13, this spelling and case.
$regionSeed = @(
    'UAP', 'MOT', 'APAC', 'APAC-MOT', 'APAC-M&A',
    'AAG-DE', 'AAG-FR', 'AAG-UK', 'AAG-ES', 'AAG-BLX', 'AAG-PL', 'AAG-PT', 'GPC'
)
# The three canonical role names Init  Current User and UserRole DB.bes already seeds on endpoints.
$roleSeed = @('IT Operations', 'Business Operations', 'Business Default')

$summary = [ordered]@{
    database        = $DatabasePath
    whatif          = [bool]$WhatIfPreference
    tables_created  = @()
    tables_skipped  = @()
    indexes         = @()
    regions_seeded  = 0
    roles_seeded    = 0
    config_seeded   = @()
    config_skipped  = @()
    eventlog_source = ''
}

# --- resolve the shared Sqlite-Helper.ps1 ------------------------------------
if (-not (Test-Path $SqliteHelperPath)) {
    throw "Sqlite-Helper.ps1 not found at: $SqliteHelperPath`nPass -SqliteHelperPath pointing at the single shared Dashboard_4_samples\Sqlite-Helper.ps1 (copying it into scripts\ is not permitted)."
}
. $SqliteHelperPath

try {

    # --- 6000  preflight: sqlite3.exe ------------------------------------------
    try {
        $sqlite3exe = Join-Path $SQLDir 'sqlite3.exe'
        if (-not (Test-Path $sqlite3exe)) {
            throw @"
sqlite3.exe not found at: $sqlite3exe
The root server must be provisioned with the pinned sqlite tools before this script runs
(07-05 run-book): version 3.53.1, zip sha1 184d4d0b75cd75c2118fb22a1727e9220f843b98.
Download from the BES CustomRepository URL
http://<root-server>:52311/Uploads/CustomRepository/sqlite_util/sqlite-tools-win-x64-3530100.zip
verify the sha1, unzip so sqlite3.exe sits directly under -SQLDir (no arch subfolder),
then re-run. This script does NOT download it unattended.
"@
        }
        Write-Log "[OK] sqlite3.exe found at $sqlite3exe"
    } catch { throw 6000 }

    # --- 6100  role/shared tables --------------------------------------------
    try {
        foreach ($tbl in $roleSharedTables) {
            if (Test-TableExists -Name $tbl.Name) {
                Write-Log "[SKIP] $($tbl.Name) table already exists - no changes made"
                $summary.tables_skipped += $tbl.Name
            } elseif ($WhatIfPreference) {
                Write-Log "[WOULD CREATE] $($tbl.Name) table"
                $summary.tables_created += $tbl.Name
            } else {
                Invoke-Db -Sql $tbl.Ddl -Write | Out-Null
                Write-Log "[CREATE] $($tbl.Name) table created"
                $summary.tables_created += $tbl.Name
            }
        }
    } catch { throw 6100 }

    # --- 6150  indexes ------------------------------------------------------
    try {
        $indexes = @(
            'CREATE INDEX IF NOT EXISTS idx_grm_active ON GroupRoleMap (Active, Role)'
            'CREATE INDEX IF NOT EXISTS idx_userrole_role ON UserRole (Role, Active)'
            'CREATE INDEX IF NOT EXISTS idx_userrole_user ON UserRole (UserID, Active)'
        )
        foreach ($ix in $indexes) {
            $ixName = ($ix -split '\s+')[5]
            if ($WhatIfPreference) {
                Write-Log "[WOULD CREATE] index $ixName"
            } else {
                Invoke-Db -Sql $ix -Write | Out-Null
                Write-Log "[INDEX] $ixName ready"
            }
            $summary.indexes += $ixName
        }
    } catch { throw 6150 }

    # --- 6200  content tables --------------------------------------------------
    try {
        foreach ($tbl in $contentTables) {
            if (Test-TableExists -Name $tbl.Name) {
                Write-Log "[SKIP] $($tbl.Name) table already exists - no changes made"
                $summary.tables_skipped += $tbl.Name
            } elseif ($WhatIfPreference) {
                Write-Log "[WOULD CREATE] $($tbl.Name) table"
                $summary.tables_created += $tbl.Name
            } else {
                Invoke-Db -Sql $tbl.Ddl -Write | Out-Null
                Write-Log "[CREATE] $($tbl.Name) table created"
                $summary.tables_created += $tbl.Name
            }
        }
    } catch { throw 6200 }

    # --- 6300  Region seed (13, D-21) ---------------------------------------
    try {
        if ((Get-RowCount -Table 'Region') -gt 0) {
            Write-Log "[SKIP] Region already populated - no changes made"
        } else {
            foreach ($r in $regionSeed) {
                if ($WhatIfPreference) {
                    Write-Log "[WOULD SEED] Region '$r'"
                } else {
                    Invoke-Db -Write -Sql "INSERT OR IGNORE INTO Region (GPC_Sub_Name) VALUES (@v)" -Parameters @{ v = $r } | Out-Null
                    Write-Log "[SEED] Region '$r'"
                }
                $summary.regions_seeded++
            }
        }
    } catch { throw 6300 }

    # --- 6350  Role seed (3 canonical) ------------------------------------
    try {
        if ((Get-RowCount -Table 'Role') -gt 0) {
            Write-Log "[SKIP] Role already populated - no changes made"
        } else {
            foreach ($r in $roleSeed) {
                if ($WhatIfPreference) {
                    Write-Log "[WOULD SEED] Role '$r'"
                } else {
                    Invoke-Db -Write -Sql "INSERT OR IGNORE INTO Role (Role) VALUES (@v)" -Parameters @{ v = $r } | Out-Null
                    Write-Log "[SEED] Role '$r'"
                }
                $summary.roles_seeded++
            }
        }
    } catch { throw 6350 }

    # --- 6400  PipelineConfig seed (INSERT OR IGNORE - operator edits survive) --
    try {
        if (-not (Test-Path $PipelineConfigDefaults)) {
            throw "PipelineConfig defaults file not found at: $PipelineConfigDefaults"
        }
        $configRows = Get-Content -Path $PipelineConfigDefaults -Raw | ConvertFrom-Json
        $configTableReady = Test-TableExists -Name 'PipelineConfig'
        foreach ($row in $configRows) {
            $present = $false
            if ($configTableReady -and -not ($WhatIfPreference -and -not (Test-Path $DatabasePath))) {
                $chk = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
                    -Sql "SELECT COUNT(*) AS n FROM PipelineConfig WHERE Key=@k" -Parameters @{ k = $row.Key }
                $present = ($chk.Count -gt 0 -and [int]$chk[0].n -gt 0)
            }
            if ($present) {
                Write-Log "[SKIP] PipelineConfig '$($row.Key)' already set - operator value preserved"
                $summary.config_skipped += $row.Key
            } elseif ($WhatIfPreference) {
                Write-Log "[WOULD SEED] PipelineConfig '$($row.Key)'"
                $summary.config_seeded += $row.Key
            } else {
                Invoke-Db -Write -Sql "INSERT OR IGNORE INTO PipelineConfig (Key, Value, Description) VALUES (@k, @v, @d)" `
                    -Parameters @{ k = $row.Key; v = [string]$row.Value; d = [string]$row.Description } | Out-Null
                Write-Log "[SEED] PipelineConfig '$($row.Key)'"
                $summary.config_seeded += $row.Key
            }
        }
    } catch { throw 6400 }

    # --- 6500  Windows Event Log source -------------------------------------
    try {
        if ($WhatIfPreference) {
            Write-Log "[WOULD REGISTER] Event Log source '$EventLogSource' (LogName Application)"
            $summary.eventlog_source = 'would-register'
        } else {
            try {
                if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
                    New-EventLog -LogName Application -Source $EventLogSource -ErrorAction Stop
                    Write-Log "[CREATE] Event Log source '$EventLogSource' registered"
                    $summary.eventlog_source = 'registered'
                } else {
                    Write-Log "[SKIP] Event Log source '$EventLogSource' already registered"
                    $summary.eventlog_source = 'already-registered'
                }
            } catch {
                Write-Warning "Could not register Event Log source '$EventLogSource' (needs an elevated run once): $($_.Exception.Message). Schema init continues."
                $summary.eventlog_source = 'deferred-needs-admin'
            }
        }
    } catch { throw 6500 }

    # --- 6600  additive-migration hook -------------------------------------
    # Empty-but-present, shaped exactly like Initialize-RoleDb.ps1's PRAGMA table_info(Map)
    # block, so future additive column adds to any AutomationState.db table have a home
    # here and do not need a fresh DB.
    try {
        if ((Test-TableExists -Name 'PipelineConfig') -and -not ($WhatIfPreference -and -not (Test-Path $DatabasePath))) {
            $pcColRows = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA table_info(PipelineConfig)"
            $pcCols = @($pcColRows | ForEach-Object { $_.name })
            foreach ($col in @()) {
                if ($pcCols -notcontains $col) {
                    Invoke-Db -Write -Sql "ALTER TABLE PipelineConfig ADD COLUMN $col TEXT" | Out-Null
                    Write-Log "[MIGRATE] PipelineConfig.$col column added"
                } else {
                    Write-Log "[SKIP] PipelineConfig.$col already present"
                }
            }
        }
        Write-Log "[OK] additive-migration hook - nothing pending"
    } catch { throw 6600 }

    Write-Log "[DONE] Initialize-AutomationDb complete$(if ($WhatIfPreference) { ' [WhatIf - no writes made]' })"

} finally {
    if (-not $WhatIfPreference) {
        try {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA wal_checkpoint(TRUNCATE)" | Out-Null
        } catch { }
    }
}

# --- run summary (always; the -WhatIf plan output) ---------------------------
$summaryJson = ([pscustomobject]$summary) | ConvertTo-Json -Depth 6
Write-Host "----RUN SUMMARY----"
Write-Host $summaryJson
try { if ($dbFolder -and (Test-Path $dbFolder)) { Add-Content -Path $logfile -Value $summaryJson -WhatIf:$false } } catch { }
