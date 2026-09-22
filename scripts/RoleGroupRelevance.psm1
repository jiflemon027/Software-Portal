#Requires -Version 5.1
<#
.SYNOPSIS
    Pure, side-effect-free PowerShell twin of fixlet_role_manager.ojo's
    buildRoleGroupRelevance() (07-04), plus the D-05 current-membership reader the
    root-server drift-check driver (Sync-RoleGroups.ps1, 07-05) needs.

.DESCRIPTION
    New-RoleGroupRelevance performs NO file I/O, opens NO database, and makes NO network
    call -- it is the cross-language contract half that
    tests/fixtures/phase-07/role-group-relevance.golden.txt pins, alongside
    tests/unit/role_manager.test.js's JS twin. This module follows the same pure-seam
    convention as scripts/SnapshotBuild.psm1: no dynamic .NET type-loading, no System.Data.SQLite,
    Export-ModuleMember at the bottom, comment-based help per function.

    Get-CurrentRoleUsers is the one function that touches SQLite, and it does so ONLY via
    Invoke-SqliteCommand -- a function this module does NOT define and does NOT
    dot-source itself. The caller (Sync-RoleGroups.ps1) is responsible for dot-sourcing
    Dashboard_4_samples\Sqlite-Helper.ps1 exactly once before calling Get-CurrentRoleUsers,
    the same injected-helper seam scripts/Publish-RoleSnapshot.ps1 uses for
    scripts/SnapshotBuild.psm1.

.NOTES
    Ground-truth resolution (07-05 Task 1, Step 1): 07-SPIKE-FINDINGS.md Check B confirms
    Assumption A2 HELD for CLIENT relevance -- the only dialect this phase's Computer
    Group SearchComponentRelevance ever uses. 07-04-SUMMARY.md independently confirms no
    deviation was needed for buildRoleGroupRelevance. Therefore New-RoleGroupRelevance
    below is authored directly against RESEARCH Pattern 2 / the live fixlet_role_manager.ojo
    source, with NO reduced/fallback form.

    IMPORTANT parity note: fixlet_role_manager.ojo's buildRoleGroupRelevance() does NOT
    sort usernames -- it lower-cases, trims, and de-duplicates on the lower-cased key
    while preserving FIRST-SEEN insertion order (confirmed directly against the live
    07-04 dashboard source and against tests/unit/role_manager.test.js, whose dedup
    assertion ["Alice","ALICE","  alice  "] -> a single "alice" entry does not exercise
    sort order, and whose ["alice","bob"] assertion is order-preserving-consistent
    because the input was already alphabetical). New-RoleGroupRelevance below
    deliberately mirrors INSERTION ORDER, not an ordinal sort, so the two languages stay
    byte-identical -- this is a plan-text vs. actual-shipped-code correction, documented
    in the 07-05 plan summary.
#>

Set-StrictMode -Version Latest

function New-RoleGroupRelevance {
    <#
    .SYNOPSIS
        D-09/D-10 "exactly one of N logged on" Computer Group relevance builder. Pure --
        byte-for-byte twin of fixlet_role_manager.ojo's buildRoleGroupRelevance(). An
        empty or all-blank -UserName list ALWAYS returns the literal string "false" --
        this guard beats every other branch, including a supplied scope group
        (T-07-04-01 / T-07-05-01, the single highest-impact bug this generator could ship
        on either side of the language boundary).

    .DESCRIPTION
        Per username: trim, lower-case (InvariantCulture), drop blanks, de-duplicate on
        the lower-cased key while preserving first-seen order (see module .NOTES -- the
        dashboard does NOT sort), double any embedded double-quote (T-07-04-02 /
        T-07-05-02), and join with ";" inside a `set of (...)` clause:

            (number of (logged on users whose (name of it as lowercase is contained by
              set of ("alice";"bob")))) = 1

        When -ScopeGroupId is supplied (D-10) and is not blank/"0" -- mirroring the
        dashboard's `if(scopeGroupId)` JS truthiness check -- an additional AND clause is
        appended, with -ScopeSiteName lower-cased and double-quote-escaped the same way:

            ... = 1 AND (member of group <id> of site whose (name of it as lowercase =
              "<site>" as lowercase))

    .PARAMETER UserName
        The role's current username list, any order / casing / whitespace / duplicates.

    .PARAMETER ScopeGroupId
        Optional D-10 scope group id. Blank, $null, or the literal "0" emit no AND
        clause.

    .PARAMETER ScopeSiteName
        Site name for the scope clause. Only consulted when -ScopeGroupId is truthy.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$UserName,

        [Parameter()]
        [AllowNull()]
        [string]$ScopeGroupId = '',

        [Parameter()]
        [AllowNull()]
        [string]$ScopeSiteName = ''
    )

    if ($null -eq $UserName -or @($UserName).Count -eq 0) { return 'false' }

    $seen   = @{}
    $quoted = New-Object System.Collections.ArrayList
    foreach ($raw in $UserName) {
        if ($null -eq $raw) { continue }
        $u = ([string]$raw).ToLowerInvariant()
        $u = $u.Trim()
        if ($u -eq '') { continue }
        if ($seen.ContainsKey($u)) { continue }
        $seen[$u] = $true
        [void]$quoted.Add('"' + $u.Replace('"', '""') + '"')
    }
    if ($quoted.Count -eq 0) { return 'false' }

    $base = '(number of (logged on users whose (name of it as lowercase is contained by ' +
        'set of (' + ($quoted -join ';') + ')))) = 1'

    $hasScope = -not [string]::IsNullOrWhiteSpace($ScopeGroupId) -and $ScopeGroupId -ne '0'
    if ($hasScope) {
        $safeSite = ''
        if (-not [string]::IsNullOrWhiteSpace($ScopeSiteName)) {
            $safeSite = $ScopeSiteName.ToLowerInvariant().Replace('"', '""')
        }
        $base += ' AND (member of group ' + $ScopeGroupId + ' of site whose ' +
            '(name of it as lowercase = "' + $safeSite + '" as lowercase))'
    }

    return $base
}

function Get-CurrentRoleUsers {
    <#
    .SYNOPSIS
        Returns the CURRENT (latest-run) membership of one role from the RolePublish.db
        D-05 audit store, via the canonical MAX(RunID) query 07-03-SUMMARY.md records
        verbatim:

            SELECT u.UserID FROM RoleUsers u
            WHERE u.RunID = (SELECT MAX(RunID) FROM RolePublishRun WHERE Role = @role)
            ORDER BY u.UserID

    .DESCRIPTION
        Dot-sources nothing. Calls Invoke-SqliteCommand -- defined by
        Dashboard_4_samples\Sqlite-Helper.ps1, which the CALLER must dot-source before
        this function runs (the same injected-helper seam scripts/Publish-RoleSnapshot.ps1
        uses for scripts/SnapshotBuild.psm1's Build-RegionSnapshot).

        Flattens Sqlite-Helper's `return ,$rows` wrapper the way
        scripts/AxoniousParse.psm1's Get-DbRows / scripts/Publish-RoleSnapshot.ps1's
        Get-Rows do -- a bare `@($rows)` on the doubly-wrapped return value from
        Invoke-SqliteCommand can miscount a multi-row result, so every row is piped
        through `ForEach-Object { $_ }` first.

    .PARAMETER DatabasePath
        Full path to RolePublish.db (the D-05 audit store -- NOT AutomationState.db).

    .PARAMETER SQLDir
        Directory containing sqlite3.exe directly (no arch subfolder).

    .PARAMETER Role
        The role name to look up.

    .OUTPUTS
        [string[]] UserIDs in ORDER BY UserID order. An empty array (never $null) when
        the role has no RolePublishRun row yet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DatabasePath,

        [Parameter(Mandatory)]
        [string]$SQLDir,

        [Parameter(Mandatory)]
        [string]$Role
    )

    $sql = @"
SELECT u.UserID FROM RoleUsers u
WHERE u.RunID = (SELECT MAX(RunID) FROM RolePublishRun WHERE Role = @role)
ORDER BY u.UserID
"@

    $raw  = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $sql -Parameters @{ role = $Role }
    $rows = @($raw | ForEach-Object { $_ })
    if ($rows.Count -eq 0) { return [string[]]@() }
    return [string[]]@($rows | ForEach-Object { [string]$_.UserID })
}

Export-ModuleMember -Function Get-CurrentRoleUsers, New-RoleGroupRelevance
