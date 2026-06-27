
#Requires -Version 5.1
<#
.SYNOPSIS
    Creates the SQLite database and schema for the Role Aware Software Distribution.

.DESCRIPTION
    Initialises RoleAwareness.db with the Roles, Users, Map, and Overrides tables.
    Safe to re-run: uses CREATE TABLE IF NOT EXISTS. Already-present tables are
    skipped with a [SKIP] message. No data is modified on skip.

    v2 changes:
      - Map gains Updated_on (TEXT) and Valid_to (TEXT) columns.
      - Migration block (error 5400) adds both columns to existing tables if absent.
      - idx_map_expiry partial index added after migration for efficient expiry queries.

.PARAMETER DatabasePath
    Full path to the SQLite database file to create or open.
    Default: C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SoftwarePortal\RoleAwareness.db

.PARAMETER SQLDir
    Directory containing the System.Data.SQLite.dll subfolders (x64\ and x86\).

.EXAMPLE
    .\Initialize-RoleDb.ps1 -DatabasePath .\RoleAwareness.db -SQLDir .\SQLite

.NOTES
    PowerShell 5.1 only. No external modules required (D-15).
    Uses System.Data.SQLite.dll — NOT PSSQLite from PSGallery.
    Re-run safe: CREATE TABLE IF NOT EXISTS; column migration uses PRAGMA table_info.

    Upsert pattern (D-12): downstream scripts use INSERT OR IGNORE + conditional UPDATE
    to preserve deploy state across re-imports. INSERT OR REPLACE is prohibited — it
    destroys existing Active / Locked_by_Override values by deleting and re-inserting.

    Error codes:
      5100  Table creation
      5150  idx_overrides_lookup index
      5200  Default role seeding
      5300  Current user detection
      5400  Map column migration + idx_map_expiry index
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SoftwarePortal\RoleAwareness.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SQLite',

    [Parameter()]
    [string]$MapUser,       # single username to map

    [Parameter()]
    [string[]]$MapRoles     # one or more role names to assign
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$arch    = if ([IntPtr]::Size -eq 8) { 'x64' } else { 'x86' }
$dllPath = Join-Path $SQLDir "$arch\System.Data.SQLite.dll"

if (-not (Test-Path $dllPath)) {
    throw "System.Data.SQLite.dll not found at: $dllPath`nSet -SQLDir to the directory containing x64\ and x86\ subfolders."
}

Add-Type -Path $dllPath

$connStr = "Data Source=$DatabasePath;Journal Mode=WAL;BusyTimeout=30000"
$conn    = $null

try {
    $conn = [System.Data.SQLite.SQLiteConnection]::new($connStr)
    $conn.Open()

    $rolesDdl = @"
CREATE TABLE IF NOT EXISTS Roles (
    RoleID  INTEGER PRIMARY KEY AUTOINCREMENT,
    Role    TEXT NOT NULL UNIQUE
)
"@

    $usersDdl = @"
CREATE TABLE IF NOT EXISTS Users (
    UID       INTEGER PRIMARY KEY AUTOINCREMENT,
    UserID    TEXT UNIQUE NOT NULL,
    LastSeen  TEXT NOT NULL
)
"@

    $mapDdl = @"
CREATE TABLE IF NOT EXISTS Map (
    MapID              INTEGER PRIMARY KEY AUTOINCREMENT,
    UserID             TEXT NOT NULL,
    Role               TEXT NOT NULL,
    Active             INTEGER NOT NULL DEFAULT 1,
    Locked_by_Override INTEGER NOT NULL DEFAULT 0,
    Created_on         TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    Updated_on         TEXT,
    Valid_to           TEXT,
    UNIQUE(UserID, Role)
)
"@

    $overridesDdl = @"
CREATE TABLE IF NOT EXISTS Overrides (
    OID             INTEGER PRIMARY KEY AUTOINCREMENT,
    Override_Type   TEXT NOT NULL,
    Override_Key    TEXT NOT NULL,
    Override_Value  TEXT NOT NULL,
    Override_Reason TEXT NOT NULL,
    Overridden_By   TEXT NOT NULL,
    Overriden_On    TEXT DEFAULT (concat(date('now'), ' ', time('now'))),
    Valid_To        TEXT DEFAULT (concat(date('now'), ' ', time('now', '+1 hours')))
)
"@

    $cmd = $conn.CreateCommand()

    ## Build Tables
    try {
        foreach ($tbl in @(
            @{ Name = 'Roles';     Ddl = $rolesDdl     }
            @{ Name = 'Users';     Ddl = $usersDdl     }
            @{ Name = 'Map';       Ddl = $mapDdl       }
            @{ Name = 'Overrides'; Ddl = $overridesDdl }
        )) {
            $cmd.CommandText = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=@n"
            [void]$cmd.Parameters.AddWithValue('@n', $tbl.Name)
            $before = [int]$cmd.ExecuteScalar()
            [void]$cmd.Parameters.Clear()

            if ($before -eq 1) {
                Write-Host "[SKIP] $($tbl.Name) table already exists - no changes made"
            } else {
                $cmd.CommandText = $tbl.Ddl
                [void]$cmd.ExecuteNonQuery()
                Write-Host "[CREATE] $($tbl.Name) table created"
            }
        }
    } catch { throw 5100 }


    ## Add index for fast override lookups
    try {
        $cmd.CommandText = @"
CREATE INDEX IF NOT EXISTS idx_overrides_lookup
    ON Overrides (Override_Type, Override_Key, Override_Value)
    WHERE Valid_to > datetime('now', 'localtime')
"@
        [void]$cmd.ExecuteNonQuery()
    } catch { throw 5150 }


    ## Migrate Map table: add Updated_on and Valid_to if absent, then add expiry index.
    ## Safe on re-run: PRAGMA table_info checks before each ALTER; index uses IF NOT EXISTS.
    ## idx_map_expiry is created here (not in the index block above) because Valid_to must
    ## exist before the partial index that references it can be created.
    try {
        $cmd.CommandText = "PRAGMA table_info(Map)"
        $reader  = $cmd.ExecuteReader()
        $mapCols = [System.Collections.Generic.List[string]]::new()
        while ($reader.Read()) { $mapCols.Add($reader['name']) }
        $reader.Close()

        if ($mapCols -notcontains 'Updated_on') {
            $cmd.CommandText = "ALTER TABLE Map ADD COLUMN Updated_on TEXT"
            [void]$cmd.ExecuteNonQuery()
            Write-Host "[MIGRATE] Map.Updated_on column added"
        } else {
            Write-Host "[SKIP] Map.Updated_on already present"
        }

        if ($mapCols -notcontains 'Valid_to') {
            $cmd.CommandText = "ALTER TABLE Map ADD COLUMN Valid_to TEXT"
            [void]$cmd.ExecuteNonQuery()
            Write-Host "[MIGRATE] Map.Valid_to column added"
        } else {
            Write-Host "[SKIP] Map.Valid_to already present"
        }

        # Partial index for the periodic expiry task:
        #   SELECT ... FROM Map WHERE Active=1 AND Locked_by_Override=0 AND Valid_to < datetime(...)
        $cmd.CommandText = @"
CREATE INDEX IF NOT EXISTS idx_map_expiry
    ON Map (Valid_to)
    WHERE Active = 1 AND Locked_by_Override = 0
"@
        [void]$cmd.ExecuteNonQuery()
        Write-Host "[INDEX] idx_map_expiry ready"
    } catch { throw 5400 }


    ## Load Default Roles (skip if already populated)
    try {
        $cmd.CommandText = "SELECT COUNT(*) FROM Roles"
        $roleCount = [int]$cmd.ExecuteScalar()

        if ($roleCount -gt 0) {
            Write-Host "[SKIP] Roles already populated - no changes made"
        } else {
            $defaultRoles = @(
                'IT Developer', 'IT Support', 'DB Developer',
                'DB Administrator', 'Payments Processor', 'Marketer'
            )
            $cmd.CommandText = "INSERT OR IGNORE INTO Roles (Role) VALUES (@role)"
            foreach ($role in $defaultRoles) {
                [void]$cmd.Parameters.AddWithValue('@role', $role)
                [void]$cmd.ExecuteNonQuery()
                [void]$cmd.Parameters.Clear()
            }
            Write-Host "[CREATE] Roles populated with defaults"
        }
    } catch { throw 5200 }


    ## Load Current User
    try {
        $users = Get-WinEvent -FilterHashtable @{Logname = 'Security'; ID = 4672} -MaxEvents 20 |
            Where-Object { $_.Properties[1].Value -notmatch 'SYSTEM|NETWORK SERVICE|LOCAL SERVICE' } |
            Select-Object @{Name = 'UserName'; Expression = {$_.Properties[1].Value}} -First 1

        if (-not $users) {
            Write-Host "[SKIP] No eligible user found in Security event log"
        } else {
            $cmd.CommandText = "INSERT OR REPLACE INTO Users (UserID, LastSeen) VALUES (@uid, datetime('now', 'localtime'))"
            [void]$cmd.Parameters.AddWithValue('@uid', $users.UserName)
            [void]$cmd.ExecuteNonQuery()
            [void]$cmd.Parameters.Clear()
            Write-Host "[UPSERT] User '$($users.UserName)' written to Users table"
        }
    } catch { throw 5300 }

} finally {
    if ($conn) {
        try {
            $ckpt = $conn.CreateCommand()
            $ckpt.CommandText = "PRAGMA wal_checkpoint(TRUNCATE)"
            [void]$ckpt.ExecuteNonQuery()
            $ckpt.Dispose()
        } catch {}
        try { $conn.Close() } catch {}
    }
}
