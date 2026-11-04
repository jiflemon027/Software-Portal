#Requires -Version 5.1
# Version: 1.1.0
<#
.SYNOPSIS
    Endpoint role-mapping writer for the Operator-Role-Group model. Given a role, a
    username and the issuing operator, ensures the user exists in RoleAwareness.db and
    upserts a UserID -> Role row into the Map table, using the same D-12 discipline as
    Reconcile-LocalRoles.ps1 (INSERT OR IGNORE + a conditional UPDATE guarded by
    Locked_by_Override = 0).

.DESCRIPTION
    This is the endpoint half of a deliberately simpler assignment model than the Axonius
    snapshot pipeline:

      * One automatic Computer Group per role. Its membership relevance carries the list
        of operator usernames that hold the role and admits a device only when EXACTLY
        ONE logged-on user is in that list.
      * One policy action per group runs this script. The ActionScript resolves the
        single matching user and passes it as -UserName, so this script does no
        logged-on-user parsing of its own - it trusts its inputs.
      * BigFix Operator -> Role assignments are the source of truth. There is no CSV, no
        snapshot, no GroupRoleMap.

    Revoke: none. When an operator loses the role they drop out of the Computer Group,
    the policy action stops applying, and the Map row lapses at Valid_to (age-out) - the
    same no-revoke model as Reconcile-LocalRoles.ps1 v1.

    Constrained Language Mode safe: no Add-Type, no System.Data.SQLite, no dynamic .NET
    type loading. Every database call goes through Sqlite-Helper.ps1 (bundled sqlite3.exe).
    Assumes Sqlite-Helper.ps1 and sqlite3.exe are already staged on the endpoint by the
    "Init  Current User and UserRole DB" task (787); the task's <Relevance> gates on that.

.PARAMETER Role
    The role name to assign, e.g. "IT Operations". Inserted into Roles if new to this
    endpoint (D-15 parity with Reconcile-LocalRoles.ps1). Trimmed, case preserved.

.PARAMETER UserName
    The user to map. Any DOMAIN\ prefix or UPN "@domain" suffix is stripped; the result
    is lower-cased to match how Initialize-RoleDb.ps1 stores UserID.

.PARAMETER AssignedBy
    Value written to Map.Assigned_By - the identity of the operator who issued the task
    (the ActionScript substitutes it). Default 'OperatorRoleGroup' for a manual run.

.PARAMETER Region
    Value written to Map.Region (D-17, regional role groups). Baked into the per-(role,region)
    policy Task's ActionScript at Publish time by fixlet_role_manager.ojo -- NOT derived from
    any client-side setting, unlike the retired Axonius-era GPC_Sub_Name passthrough. Empty
    string for the default/no-region group (the common case; Map.Region stays blank, same as
    before this parameter existed).

.PARAMETER ValidityMonths
    How far forward the mapped row's Valid_to is pushed. Default 6 (mirrors
    Initialize-RoleDb.ps1 -ValidityMonths / PORTAL_CONFIG.validityMonths).

.PARAMETER DatabasePath
    Full path to RoleAwareness.db.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder).

.PARAMETER SqliteHelperPath
    Path to the shared Sqlite-Helper.ps1. Default: Sqlite-Helper.ps1 in the same folder
    as -DatabasePath (the layout task 787 lays down).

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
    [string]$AssignedBy = 'OperatorRoleGroup',

    [Parameter()]
    [string]$Region = '',

    [Parameter()]
    [int]$ValidityMonths = 6,

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
    try { Add-Content -Path $logfile -Value ("{0} assign-role {1}" -f (Get-Date -Format 's'), $line) -WhatIf:$false } catch { }
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

# --- normalise inputs -------------------------------------------------------
$Role = $Role.Trim()
$user = $UserName.Trim().TrimStart('@').Split('\')[-1]
$user = $user.Split('@')[0].ToLowerInvariant()

$result = [ordered]@{
    whatif               = [bool]$WhatIfPreference
    role                 = $Role
    user                 = $user
    assigned_by          = $AssignedBy
    region               = $Region
    validity_months      = $ValidityMonths
    roles_created        = 0
    rows_updated         = 0
    rows_blocked_by_lock = 0
    outcome              = $null
}

function Write-RunLog {
    $dir = Split-Path $DatabasePath
    $path = Join-Path $dir ("assign-role-{0}.json" -f ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')))
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

    $validModifier = "+$ValidityMonths months"

    if ($WhatIfPreference) {
        Write-Tag 'WOULD' ("ensure user '{0}', upsert Map: role='{1}' Assigned_By='{2}' Valid_to=now{3}" -f $user, $Role, $AssignedBy, $validModifier)
        $result.outcome = 'whatif'
        Write-RunLog
        return
    }

    # 1. Users: INSERT OR IGNORE + UPDATE LastSeen (never delete-and-reinsert)
    Invoke-DbWrite "INSERT OR IGNORE INTO Users (UserID, LastSeen) VALUES (@u, datetime('now','localtime'))" @{ u = $user }
    Invoke-DbWrite "UPDATE Users SET LastSeen = datetime('now','localtime') WHERE UserID = @u" @{ u = $user }

    # 2. Roles: role new to this endpoint propagates without an init redeploy (D-15)
    $before = @(Get-DbRows "SELECT COUNT(*) AS n FROM Roles WHERE Role = @r" @{ r = $Role })
    Invoke-DbWrite "INSERT OR IGNORE INTO Roles (Role) VALUES (@r)" @{ r = $Role }
    $after = @(Get-DbRows "SELECT COUNT(*) AS n FROM Roles WHERE Role = @r" @{ r = $Role })
    if ([int]$before[0].n -eq 0 -and [int]$after[0].n -eq 1) { $result.roles_created++ }

    # 3. Map: create the row if absent, without disturbing any existing state
    Invoke-DbWrite "INSERT OR IGNORE INTO Map (UserID, Role, Active, Created_on) VALUES (@u, @r, 1, datetime('now','localtime'))" `
        @{ u = $user; r = $Role }

    # 4. guarded UPDATE + connection-scoped changes() in ONE call (see Initialize-RoleDb.ps1 error 5350 note)
    $upd = @(Get-DbRows @"
UPDATE Map SET Active = 1, Updated_on = datetime('now','localtime'),
    Valid_to = datetime('now','localtime', @v),
    Source_Type = 'BigFix Role', Source_Value = @sv, Assigned_By = @ab, Region = @rg
WHERE UserID = @u AND Role = @r AND Locked_by_Override = 0;
SELECT changes() AS n
"@ @{ v = $validModifier; sv = $Role; ab = $AssignedBy; rg = $Region; u = $user; r = $Role })
    $changed = if ($upd.Count -gt 0) { [int]$upd[0].n } else { 0 }

    if ($changed -gt 0) {
        $result.rows_updated += $changed
        $result.outcome = 'mapped'
        Write-Tag 'UPSERT' ("user='{0}' role='{1}' region='{2}' -> Assigned_By={3}, Valid_to +{4}mo" -f $user, $Role, $Region, $AssignedBy, $ValidityMonths)
    } else {
        $lockRow = @(Get-DbRows "SELECT COUNT(*) AS n FROM Map WHERE UserID = @u AND Role = @r AND Locked_by_Override = 1" @{ u = $user; r = $Role })
        if ([int]$lockRow[0].n -gt 0) {
            $result.rows_blocked_by_lock++
            $result.outcome = 'blocked-by-lock'
            Write-Tag 'LOCKED' ("user='{0}' role='{1}' has Locked_by_Override=1 - left untouched" -f $user, $Role)
        } else {
            $result.outcome = 'no-change'
            Write-Tag 'OK' ("user='{0}' role='{1}' already current - no change" -f $user, $Role)
        }
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
