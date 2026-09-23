
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

    v3 changes:
      - This script is re-run on every logon by the RoleDB_Maintenance scheduled task
        (registered by the init .bes; see Scheduled_RoleDb_mnc.ps1), not just once at
        DB-creation time. The "Load Current User" step (error 5300) now also renews
        Valid_to on the logged-on user's active, non-overridden Map rows (error 5350) --
        same D-12 upsert philosophy as Assign-RoleMapping.ps1's CSV-deploy path, just
        applied automatically on every logon instead of by admin action.

    v4 changes (Phase 7, D-18):
      - Map gains four additive TEXT columns, added by the same PRAGMA table_info(Map)-
        gated ALTER TABLE mechanism as Updated_on / Valid_to (error 5400):
          Source_Type   provenance kind - e.g. "AD Security Group" | "Mailing List" |
                        "Azure AD Group". '|'-joined when a role was granted by more
                        than one group.
          Source_Value  the granting group's CN / display name. '|'-joined likewise.
          Region        the endpoint's own GPC_Sub_Name client-setting value at the
                        time the role was assigned.
          Assigned_By   one of "AxoniousSync" | "AdminCSV" | "Logon".
      - These columns were WRITTEN by Reconcile-LocalRoles.ps1 (07-02) under the retired
        Axonius pipeline; that script was archived 2026-09-21 (D-15) and the columns are
        now written by scripts/Assign-RoleMapping.ps1 instead (D-12 discipline
        unchanged). This script only guarantees the columns exist. UNIQUE(UserID, Role),
        Active, Locked_by_Override, Valid_to and the D-12 renew upsert are unchanged.

.PARAMETER DatabasePath
    Full path to the SQLite database file to create or open.
    Default: C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SoftwarePortal\RoleAwareness.db

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no x64\/x86\ arch subfolder).

.PARAMETER ValidityMonths
    How far to push a renewed row's Valid_to forward, expressed as SQLite datetime()
    modifier months. Default: 6, mirroring PipelineConfig.ValidityMonths (formerly
    PORTAL_CONFIG.validityMonths in the now-archived, retired fixlet_role_assigner.ojo,
    D-15). Keep the two in sync if that default ever changes -- RoleDB_Maintenance does
    not pass -ValidityMonths explicitly, so redeploying the init task is enough to
    change the script default without touching the scheduled task.

.EXAMPLE
    .\Initialize-RoleDb.ps1 -DatabasePath .\RoleAwareness.db -SQLDir .\SQLite

.NOTES
    PowerShell 5.1 only. No external modules required (D-15).
    Uses the bundled sqlite3.exe CLI via Sqlite-Helper.ps1 -- NOT System.Data.SQLite.dll
    and NOT PSSQLite from PSGallery. Zero Add-Type calls (Constrained Language Mode safe).
    Re-run safe: CREATE TABLE IF NOT EXISTS; column migration uses PRAGMA table_info.

    Upsert pattern (D-12): downstream scripts use INSERT OR IGNORE + conditional UPDATE
    to preserve deploy state across re-imports. A delete-and-reinsert upsert is
    prohibited on any stateful table -- it destroys existing Active /
    Locked_by_Override values. (The Users table is the sole exception: it carries only
    UserID + LastSeen, no state, so its one delete-and-reinsert write is safe.)

    Error codes:
      5100  Table creation
      5150  idx_overrides_lookup index
      5200  Default role seeding
      5300  Current user detection
      5350  Map.Valid_to renewal for the logged-on user
      5400  Map column migration (Updated_on, Valid_to, Source_Type, Source_Value,
            Region, Assigned_By) + idx_map_expiry index
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\SoftwarePortal\RoleAwareness.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [int]$ValidityMonths = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logfile = Join-Path (Split-Path $DatabasePath) 'SWDlog.log'

Add-Content -Path $logfile -Value "----Starting"

. "$PSScriptRoot\Sqlite-Helper.ps1"

try {

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

    ## Build Tables
    try {
        foreach ($tbl in @(
            @{ Name = 'Roles';     Ddl = $rolesDdl     }
            @{ Name = 'Users';     Ddl = $usersDdl     }
            @{ Name = 'Map';       Ddl = $mapDdl       }
            @{ Name = 'Overrides'; Ddl = $overridesDdl }
        )) {
            $before = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
                -Sql "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name=@n" `
                -Parameters @{ n = $tbl.Name }

            if ($before[0].n -eq 1) {
                Write-Host "[SKIP] $($tbl.Name) table already exists - no changes made"
				Add-Content -Path $logfile -Value "[SKIP] $($tbl.Name) table already exists - no changes made"
            } else {
                Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $tbl.Ddl | Out-Null
                Write-Host "[CREATE] $($tbl.Name) table created"
				Add-Content -Path $logfile -Value "[CREATE] $($tbl.Name) table created"
            }
        }
    } catch { throw 5100 }


    ## Add index for fast override lookups
    try {
        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
CREATE INDEX IF NOT EXISTS idx_overrides_lookup
    ON Overrides (Override_Type, Override_Key, Override_Value)
    WHERE Valid_to > datetime('now', 'localtime')
"@ | Out-Null
    } catch { throw 5150 }

    try {
        $mapColRows = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA table_info(Map)"
        $mapCols = @($mapColRows | ForEach-Object { $_.name })

        if ($mapCols -notcontains 'Updated_on') {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "ALTER TABLE Map ADD COLUMN Updated_on TEXT" | Out-Null
            Write-Host "[MIGRATE] Map.Updated_on column added"
				Add-Content -Path $logfile -Value "[MIGRATE] Map.Updated_on column added"
        } else {
            Write-Host "[SKIP] Map.Updated_on already present"
			Add-Content -Path $logfile -Value "[SKIP] Map.Updated_on already present"
        }

        if ($mapCols -notcontains 'Valid_to') {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "ALTER TABLE Map ADD COLUMN Valid_to TEXT" | Out-Null
            Write-Host "[MIGRATE] Map.Valid_to column added"
			Add-Content -Path $logfile -Value "[MIGRATE] Map.Valid_to column added"
        } else {
            Write-Host "[SKIP] Map.Valid_to already present"
			Add-Content -Path $logfile -Value "[SKIP] Map.Valid_to already present"
        }

        # v4 (Phase 7, D-18): four additive provenance columns, same mechanism as above.
        # Originally written by the now-archived Reconcile-LocalRoles.ps1 (07-02,
        # retired 2026-09-21, D-15); now written by scripts/Assign-RoleMapping.ps1
        # instead. This block only ensures the columns exist.
        foreach ($col in 'Source_Type','Source_Value','Region','Assigned_By') {
            if ($mapCols -notcontains $col) {
                Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "ALTER TABLE Map ADD COLUMN $col TEXT" | Out-Null
                Write-Host "[MIGRATE] Map.$col column added"
                Add-Content -Path $logfile -Value "[MIGRATE] Map.$col column added"
            } else {
                Write-Host "[SKIP] Map.$col already present"
                Add-Content -Path $logfile -Value "[SKIP] Map.$col already present"
            }
        }

        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
CREATE INDEX IF NOT EXISTS idx_map_expiry
    ON Map (Valid_to)
    WHERE Active = 1 AND Locked_by_Override = 0
"@ | Out-Null
        Write-Host "[INDEX] idx_map_expiry ready"
		Add-Content -Path $logfile -Value  "[INDEX] idx_map_expiry ready"
    } catch { throw 5400 }


    ## Load Default Roles (skip if already populated)
    try {
        $roleCount = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "SELECT COUNT(*) AS n FROM Roles"

        if ($roleCount[0].n -gt 0) {
            Write-Host "[SKIP] Roles already populated - no changes made"
			Add-Content -Path $logfile -Value "[SKIP] Roles already populated - no changes made"
        } else {
            $defaultRoles = @(
                'IT Operations', 'Business Operations', 'Business Default'
            )
            foreach ($role in $defaultRoles) {
                Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
                    -Sql "INSERT OR IGNORE INTO Roles (Role) VALUES (@role)" -Parameters @{ role = $role } | Out-Null
            }
            Write-Host "[CREATE] Roles populated with defaults"
			Add-Content -Path $logfile -Value "[CREATE] Roles populated with defaults"
        }
    } catch { throw 5200 }


    ## Load Current User
    try {
        $users = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" | Invoke-CimMethod -MethodName GetOwner | Select-Object -ExpandProperty User -Unique
        foreach ($u in @($users)) {
            Write-Host "[DIAG] GetOwner().User='$u'"
			Add-Content -Path $logfile -Value "[DIAG] GetOwner().User='$u'"
        }		
        if (-not $users) {
            Write-Host "[SKIP] No current user found"
			Add-Content -Path $logfile -Value "[SKIP] No current user found"
        } else {
			foreach($user in $users) {
				$bareUser = $user.Split('\')[-1].ToLower()
				Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
					-Sql "INSERT OR REPLACE INTO Users (UserID, LastSeen) VALUES (@uid, datetime('now', 'localtime'))" `
					-Parameters @{ uid = $bareUser } | Out-Null
				Write-Host "[UPSERT] User '$bareUser' written to Users table"
				Add-Content -Path $logfile -Value "[UPSERT] User '$bareUser' written to Users table"
			}
        }
    } catch { throw 5300 }


    ## Renew Valid_to on the logged-on user's active, non-overridden Map rows.
    ## Runs every time this script runs -- both the one-shot init and every RoleDB_Maintenance
    ## logon rerun -- so a brand-new user's first run is simply a no-op (no Map rows yet).
    ## Locked_by_Override = 1 rows are intentionally excluded: an admin override is a
    ## deliberate "stop auto-renewing this mapping" signal that this step must never fight.
    ## UPDATE + SELECT changes() must be ONE Invoke-SqliteCommand call: each call opens a
    ## fresh sqlite3.exe process, and changes() is scoped to that single connection --
    ## splitting them across two calls would always read back 0.
    try {
        if ($users) {
            $validModifier = "+$ValidityMonths months"
            foreach ($user in $users) {
                $bareUser = $user.Split('\')[-1].ToLower()
                $renewed = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
                    -Sql "UPDATE Map SET Updated_on = datetime('now','localtime'), Valid_to = datetime('now','localtime',@validModifier) WHERE UserID = @uid AND Active = 1 AND Locked_by_Override = 0;
SELECT changes() AS n" `
                    -Parameters @{ uid = $bareUser; validModifier = $validModifier }
                $renewedCount = if ($renewed.Count -gt 0) { $renewed[0].n } else { 0 }

                Write-Host "[RENEW] User '$bareUser': $renewedCount active role mapping(s) extended to +$ValidityMonths months"
				Add-Content -Path $logfile -Value "[RENEW] User '$bareUser': $renewedCount active role mapping(s) extended to +$ValidityMonths months"
            }
        }
    } catch { throw 5350 }

} finally {
    try {
        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA wal_checkpoint(TRUNCATE)" | Out-Null
    } catch {}
}

