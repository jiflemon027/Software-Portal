#Requires -Version 5.1
<#
.SYNOPSIS
    Root-server audit-store initialiser + per-Publish snapshot writer (D-05). Reads a
    Publish-event payload (role, publishing operator, full username list) and writes it
    as one immutable, timestamped row-set into RolePublish.db.

.DESCRIPTION
    D-05 makes this store - not the Computer Group's relevance text and not a JSON file -
    the source of truth for "who holds which role", and NFR-03's audit trail. The
    dashboard writes a JSON payload (see -PayloadPath), and this script:

      1. Ensures the RolePublishRun / RoleUsers schema exists (CREATE TABLE IF NOT
         EXISTS, never DROP, never ALTER an existing column).
      2. Inserts one RolePublishRun row for the Publish event.
      3. Inserts one RoleUsers row per (normalised, de-duplicated) username, tagged with
         that run's RunID.

    The store is append-only: every Publish creates a NEW run and a NEW full snapshot of
    that role's membership. Nothing is ever UPDATEd or DELETEd, and no upsert-by-replace
    write is ever used - history cannot be silently rewritten (T-07-03-03). The "current
    membership" of a role is always the RoleUsers rows belonging to the MAX(RunID) for
    that role - see the canonical query in .NOTES.

    Constrained Language Mode safe: no dynamic .NET type-loading helper, no
    System.Data.SQLite, no Invoke-Expression. Every database call goes through
    Sqlite-Helper.ps1 (bundled sqlite3.exe); every value goes through
    Invoke-SqliteCommand -Parameters (T-07-03-02) - the payload is data, never script
    (T-07-03-04).

.PARAMETER PayloadPath
    Path to a UTF-8 JSON file shaped:
        { "role": "IT Operations", "published_by": "jfannon", "users": ["alice","bob"] }
    An empty "users" array is legal - it means the role now has zero members - and is
    recorded as a run with UserCount = 0, not treated as an error.

.PARAMETER DatabasePath
    Full path to RolePublish.db on the root server.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder).

.PARAMETER SqliteHelperPath
    Path to the shared Sqlite-Helper.ps1. Default: Sqlite-Helper.ps1 beside -DatabasePath
    (same resolution Assign-RoleMapping.ps1 already uses).

.PARAMETER WhatIf
    Validates the payload and prints every statement that would run (schema DDL, the
    RolePublishRun insert, every RoleUsers insert) with parameter values shown, via
    [WHATIF] Write-Host lines. Performs zero database access - not even a read - so a
    -DatabasePath that does not yet exist is left untouched (sqlite3.exe materialises a
    file merely by opening one, so this script never opens the database at all under
    -WhatIf).

.EXAMPLE
    .\Upsert-RolePublish.ps1 -PayloadPath .\publish.json -DatabasePath D:\RolePublish\RolePublish.db -SQLDir D:\sqlite

.NOTES
    PowerShell 5.1, Constrained Language Mode safe.

    Canonical "current membership of a role" query (plan 07-05 uses this verbatim):
        SELECT u.UserID FROM RoleUsers u
        WHERE u.RunID = (SELECT MAX(RunID) FROM RolePublishRun WHERE Role = @role)
        ORDER BY u.UserID

    Exit codes:
      0     success
      5401  Sqlite-Helper.ps1 not found at the resolved -SqliteHelperPath
      5402  sqlite3.exe not found under -SQLDir
      5410  payload missing / not valid JSON / role blank / published_by blank / users
            not an array
      5411  users array exceeds the 5000-entry sanity cap
      1     unexpected error writing the schema or the run (see the [ABORT] message)
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadPath,

    [Parameter(Mandatory = $true)]
    [string]$DatabasePath,

    [Parameter(Mandatory = $true)]
    [string]$SQLDir,

    [Parameter()]
    [string]$SqliteHelperPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MaxUsers  = 5000
$BatchSize = 400

function Write-Tag {
    param([string]$Tag, [string]$Message)
    Write-Host "[$Tag] $Message"
}

# --- Step 1: resolve + validate tooling (no DB access yet) -----------------------------
if ([string]::IsNullOrWhiteSpace($SqliteHelperPath)) {
    $SqliteHelperPath = Join-Path (Split-Path $DatabasePath) 'Sqlite-Helper.ps1'
}

if (-not (Test-Path -LiteralPath $SqliteHelperPath)) {
    Write-Tag 'ABORT' "Sqlite-Helper.ps1 not found at: $SqliteHelperPath"
    exit 5401
}

$sqlite3Exe = Join-Path $SQLDir 'sqlite3.exe'
if (-not (Test-Path -LiteralPath $sqlite3Exe)) {
    Write-Tag 'ABORT' "sqlite3.exe not found at: $sqlite3Exe (set -SQLDir to the directory containing it)"
    exit 5402
}

. $SqliteHelperPath

# --- Step 2: read + validate the payload (no DB access) --------------------------------
if (-not (Test-Path -LiteralPath $PayloadPath)) {
    Write-Tag 'ABORT' "Payload file not found: $PayloadPath"
    exit 5410
}

try {
    $payload = Get-Content -Raw -LiteralPath $PayloadPath | ConvertFrom-Json
} catch {
    Write-Tag 'ABORT' "Payload is not valid JSON: $PayloadPath ($($_.Exception.Message))"
    exit 5410
}

if ($null -eq $payload) {
    Write-Tag 'ABORT' "Payload parsed to nothing: $PayloadPath"
    exit 5410
}

# Property-existence check first (Set-StrictMode -Version Latest throws
# PropertyNotFoundStrict on a bare $payload.role access when the JSON key is absent --
# same defensive idiom Reconcile-LocalRoles.ps1 uses for its snapshot body).
$payloadProps = @($payload.PSObject.Properties.Name)
$Role         = if ($payloadProps -contains 'role')         { [string]$payload.role }         else { '' }
$PublishedBy  = if ($payloadProps -contains 'published_by') { [string]$payload.published_by }  else { '' }

if ([string]::IsNullOrWhiteSpace($Role)) {
    Write-Tag 'ABORT' "payload 'role' is missing or blank"
    exit 5410
}
if ([string]::IsNullOrWhiteSpace($PublishedBy)) {
    Write-Tag 'ABORT' "payload 'published_by' is missing or blank"
    exit 5410
}

$Role        = $Role.Trim()
$PublishedBy = $PublishedBy.Trim()

# users: null (key absent, or an empty JSON array -- PS5.1 collapses [] to $null) is a
# legal empty list. Anything present that is NOT enumerable (a string, a number, a JSON
# object) is a type error.
$rawUsers = if ($payloadProps -contains 'users') { $payload.users } else { $null }
if ($null -eq $rawUsers) {
    $usersArray = @()
} else {
    $isArrayLike = ($rawUsers -is [System.Array]) -or `
        ($rawUsers -is [System.Collections.IEnumerable] -and $rawUsers -isnot [string])
    if (-not $isArrayLike) {
        Write-Tag 'ABORT' "payload 'users' is not an array"
        exit 5410
    }
    $usersArray = @($rawUsers)
}

if ($usersArray.Count -gt $MaxUsers) {
    Write-Tag 'ABORT' "payload 'users' has $($usersArray.Count) entries, exceeding the $MaxUsers-entry sanity cap"
    exit 5411
}

# Normalise: trim + lower-case, drop empties, de-duplicate, ordinal-sort deterministically.
$seen       = @{}
$normalized = New-Object System.Collections.ArrayList
foreach ($u in $usersArray) {
    if ($null -eq $u) { continue }
    $t = ([string]$u).Trim().ToLowerInvariant()
    if ($t -eq '') { continue }
    if (-not $seen.ContainsKey($t)) {
        $seen[$t] = $true
        [void]$normalized.Add($t)
    }
}
$normUsers = $normalized.ToArray()
if ($normUsers.Length -gt 1) { [Array]::Sort($normUsers, [System.StringComparer]::Ordinal) }

# --- Step 6: -WhatIf short-circuit ------------------------------------------------------
# Zero database access under -WhatIf: sqlite3.exe materialises a file merely by opening
# one, so even a read-only schema probe against a -DatabasePath that does not yet exist
# would leave a file behind. Describe every statement that WOULD run instead.
if ($WhatIfPreference) {
    Write-Tag 'WHATIF' "would ensure schema exists: CREATE TABLE IF NOT EXISTS RolePublishRun, CREATE TABLE IF NOT EXISTS RoleUsers, CREATE INDEX IF NOT EXISTS idx_roleusers_run, CREATE INDEX IF NOT EXISTS idx_roleusers_role"
    Write-Tag 'WHATIF' ("would insert RolePublishRun row: Role='{0}' Published_by='{1}' UserCount={2}" -f $Role, $PublishedBy, $normUsers.Count)
    foreach ($u in $normUsers) {
        Write-Tag 'WHATIF' ("would insert RoleUsers row: Role='{0}' UserID='{1}'" -f $Role, $u)
    }
    Write-Tag 'WHATIF' "no writes performed; $DatabasePath left untouched"
    exit 0
}

# --- Step 3: ensure schema --------------------------------------------------------------
function Test-TableExists {
    param([string]$Name)
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
        -Sql "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name=@n" `
        -Parameters @{ n = $Name }
    return ([int]$r[0].n -eq 1)
}

$runPublishDdl = @"
CREATE TABLE IF NOT EXISTS RolePublishRun (
    RunID        INTEGER PRIMARY KEY AUTOINCREMENT,
    Role         TEXT NOT NULL,
    Published_by TEXT NOT NULL,
    Published_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    UserCount    INTEGER NOT NULL
)
"@

$roleUsersDdl = @"
CREATE TABLE IF NOT EXISTS RoleUsers (
    RUID   INTEGER PRIMARY KEY AUTOINCREMENT,
    RunID  INTEGER NOT NULL REFERENCES RolePublishRun(RunID),
    Role   TEXT NOT NULL,
    UserID TEXT NOT NULL
)
"@

try {
    foreach ($tbl in @(
        @{ Name = 'RolePublishRun'; Ddl = $runPublishDdl }
        @{ Name = 'RoleUsers';      Ddl = $roleUsersDdl }
    )) {
        if (Test-TableExists -Name $tbl.Name) {
            Write-Tag 'SKIP' "$($tbl.Name) already exists - no changes made"
        } else {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $tbl.Ddl | Out-Null
            Write-Tag 'CREATE' "$($tbl.Name) created"
        }
    }

    Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
        -Sql "CREATE INDEX IF NOT EXISTS idx_roleusers_run ON RoleUsers(RunID)" | Out-Null
    Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
        -Sql "CREATE INDEX IF NOT EXISTS idx_roleusers_role ON RoleUsers(Role)" | Out-Null
    Write-Tag 'INDEX' "idx_roleusers_run, idx_roleusers_role ready"
} catch {
    Write-Tag 'ABORT' "failed to ensure schema: $($_.Exception.Message)"
    exit 1
}

# --- Step 4: write the run (append-only - no UPDATE, no DELETE, no upsert-by-replace) ---
try {
    # INSERT + SELECT last_insert_rowid() must be ONE call: last_insert_rowid() is scoped
    # to the connection that performed the insert, and Sqlite-Helper spawns a fresh
    # sqlite3.exe process per Invoke-SqliteCommand call.
    $insertPrefix = "INSERT INTO RolePublishRun (Role, Published_by, UserCount) VALUES"
    $runSql       = $insertPrefix + " (@role, @pubby, @cnt);`nSELECT last_insert_rowid() AS id"
    $insertResult = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
        -Sql $runSql `
        -Parameters @{ role = $Role; pubby = $PublishedBy; cnt = $normUsers.Count }
    $runId = [int]$insertResult[0].id

    for ($i = 0; $i -lt $normUsers.Count; $i += $BatchSize) {
        $end   = [Math]::Min($i + $BatchSize - 1, $normUsers.Count - 1)
        $chunk = $normUsers[$i..$end]

        $valuesClauses = New-Object System.Collections.ArrayList
        $params        = @{ runid = $runId; role = $Role }
        for ($j = 0; $j -lt $chunk.Count; $j++) {
            $key = "u$j"
            [void]$valuesClauses.Add("(@runid, @role, @$key)")
            $params[$key] = $chunk[$j]
        }

        $ruInsertPrefix = "INSERT INTO RoleUsers (RunID, Role, UserID) VALUES"
        $ruSql          = $ruInsertPrefix + "`n" + ($valuesClauses -join ",`n")
        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $ruSql -Parameters $params | Out-Null
    }
} catch {
    Write-Tag 'ABORT' "failed to write RolePublishRun/RoleUsers: $($_.Exception.Message)"
    exit 1
}

# --- Step 7: success ---------------------------------------------------------------------
Write-Host "[OK] RunID=$runId Role=$Role Users=$($normUsers.Count)"
exit 0
