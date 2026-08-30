#Requires -Version 5.1
<#
.SYNOPSIS
    Pure, side-effect-free building blocks for the per-region role snapshot publisher
    (07-02 Task 1) and the per-region policy Fixlet template renderer (07-02 Task 2).

.DESCRIPTION
    This module contains ONLY pure functions - it performs no file I/O, opens no
    database, and makes no network call. Every input is a parameter; every output is a
    return value. That keeps the snapshot shape and the prefetch/relevance strings
    unit-testable without a sqlite3.exe or a BigFix server.

    Exported functions:

      Build-RegionSnapshot   projects UserRole + RolePublication rows into the extended
                             D-11 region-snapshot object (users are objects, not ids).
      New-PrefetchLine       renders the single BigFix `prefetch` line for a file.
      New-RoleRefRelevance   renders the combined client-relevance string for a region's
                             policy Fixlet (DB guard AND region gate AND freshness gate).

    NOTE (Constrained Language Mode): the root-server publisher that imports this module
    runs under full language mode, so [Array]::Sort with a [StringComparer] is fine here.
    Reconcile-LocalRoles.ps1 (the CLM-hardened endpoint script) does NOT import this
    module - it re-reads the snapshot with ConvertFrom-Json instead.
#>

Set-StrictMode -Version Latest

function Get-SbProp {
    # Defensive property read: returns $Default when the property is absent or $null.
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)] [string]$Name,
        $Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    $p = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    if ($null -eq $p.Value) { return $Default }
    return $p.Value
}

function ConvertTo-SbOrdinalSorted {
    # Ordinal (culture-invariant, byte-wise) sort so two runs over identical data emit
    # byte-identical JSON regardless of the host's current culture.
    param([Parameter()] [AllowEmptyCollection()] [string[]]$Items = @())
    $arr = [string[]]@($Items)
    if ($arr.Length -gt 1) { [Array]::Sort($arr, [System.StringComparer]::Ordinal) }
    return ,$arr
}

function Test-SbActive {
    # sqlite json returns 1/0 integers; unit tests may pass [int]/[string]/[bool].
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    $s = [string]$Value
    return ($s -eq '1' -or $s -eq 'true' -or $s -eq 'True')
}

function Build-RegionSnapshot {
    <#
    .SYNOPSIS
        Projects UserRole rows + RolePublication rows into the extended-D-11 region
        snapshot object for ONE region. Pure.

    .PARAMETER Rows
        UserRole rows. Each needs: UserID, Role, Source_Type, Source_Value, Active.
        (The 07-01 ingest already carries Source_Type / Source_Value on every row - D-08.)

    .PARAMETER Publication
        RolePublication rows already LEFT JOINed to Region. Each needs: Role, Active, and
        EITHER a null/blank RegionID (meaning "all regions") OR a Region name that this
        function compares case-insensitively to -Region. A row is honoured only when its
        Active is truthy AND (RegionID is blank OR Region -ieq -Region).

    .PARAMETER Region
        Target region - must be exactly one Region.GPC_Sub_Name (the caller validates it).

    .PARAMETER RunId
        The publish run id, copied verbatim into snapshot.run_id.

    .PARAMETER ValidityMonths
        Copied verbatim into snapshot.validity_months.

    .PARAMETER BuiltOn
        The build timestamp. Defaults to "now" in UTC. Exposed as a parameter so tests can
        pin it and assert byte-identical output across two calls.

    .OUTPUTS
        [pscustomobject] { run_id, region, built_on (ISO 8601 Z), validity_months,
                           roles: [ { role, users: [ { id, source_type, source_value } ] } ] }
        - roles is ALWAYS an array (empty when nothing is published for the region).
        - "General Access" is never synthesised - only roles with an Active RolePublication
          row appear, and a user in no role block simply holds no specific role.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Rows,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Publication,
        [Parameter(Mandatory)] [string]$Region,
        [Parameter(Mandatory)] [string]$RunId,
        [Parameter(Mandatory)] [int]$ValidityMonths,
        [Parameter()] [datetime]$BuiltOn = (Get-Date).ToUniversalTime()
    )

    # --- 1. which roles are published for THIS region --------------------------------
    $publishedRoles = New-Object System.Collections.Specialized.OrderedDictionary ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @($Publication)) {
        if (-not (Test-SbActive (Get-SbProp $p 'Active' 1))) { continue }
        $regionId  = Get-SbProp $p 'RegionID' ''
        $regionNm  = [string](Get-SbProp $p 'Region' '')
        $allRegions = [string]::IsNullOrWhiteSpace([string]$regionId)
        if (-not $allRegions -and ($regionNm -ne $Region) -and -not ($regionNm -ieq $Region)) { continue }
        $role = [string](Get-SbProp $p 'Role' '')
        if ([string]::IsNullOrWhiteSpace($role)) { continue }
        if (-not $publishedRoles.Contains($role)) { $publishedRoles.Add($role, $role) }
    }

    # --- 2. per published role, collapse users -------------------------------------
    $roleBlocks = @()
    foreach ($roleName in (ConvertTo-SbOrdinalSorted ([string[]]@($publishedRoles.Keys)))) {
        # gather this role's active UserRole rows, keyed by lowercased user id
        $byUser = @{}
        foreach ($r in @($Rows)) {
            if (-not (Test-SbActive (Get-SbProp $r 'Active' 1))) { continue }
            $rrole = [string](Get-SbProp $r 'Role' '')
            if (-not ($rrole -ieq $roleName)) { continue }
            $uid = [string](Get-SbProp $r 'UserID' '')
            if ([string]::IsNullOrWhiteSpace($uid)) { continue }
            $key = $uid.ToLowerInvariant()
            if (-not $byUser.ContainsKey($key)) {
                $byUser[$key] = [pscustomobject]@{ Id = $uid; Pairs = @() }
            }
            $byUser[$key].Pairs += [pscustomobject]@{
                Value = [string](Get-SbProp $r 'Source_Value' '')
                Type  = [string](Get-SbProp $r 'Source_Type'  '')
            }
        }

        $userEntries = @()
        foreach ($key in (ConvertTo-SbOrdinalSorted ([string[]]@($byUser.Keys)))) {
            $u = $byUser[$key]
            # distinct granting groups, ordinal-sorted, pipe-joined
            $values = ConvertTo-SbOrdinalSorted ([string[]]@($u.Pairs | ForEach-Object { $_.Value } | Where-Object { $_ -ne '' } | Select-Object -Unique))
            $types  = ConvertTo-SbOrdinalSorted ([string[]]@($u.Pairs | ForEach-Object { $_.Type  } | Where-Object { $_ -ne '' } | Select-Object -Unique))
            $userEntries += [pscustomobject]@{
                id           = $u.Id
                source_type  = ($types  -join '|')
                source_value = ($values -join '|')
            }
        }

        $roleBlocks += [pscustomobject]@{
            role  = $roleName
            users = ([object[]]$userEntries)
        }
    }

    return [pscustomobject]@{
        run_id          = $RunId
        region          = $Region
        built_on        = $BuiltOn.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        validity_months = $ValidityMonths
        roles           = ([object[]]$roleBlocks)
    }
}

function New-PrefetchLine {
    <#
    .SYNOPSIS
        Renders the single BigFix prefetch line for a snapshot file. Pure.
        Shape matches fixlet_dispatcher.ojo rewritePrefetchUrls() byte-for-byte:

            prefetch <FileName> sha1:<sha1> size:<size> <UrlBase>/<FileName>
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FileName,
        [Parameter(Mandatory)] [string]$Sha1,
        [Parameter(Mandatory)] [long]$Size,
        [Parameter(Mandatory)] [string]$UrlBase
    )
    $base = $UrlBase.TrimEnd('/')
    return ('prefetch {0} sha1:{1} size:{2} {3}/{0}' -f $FileName, $Sha1.ToLowerInvariant(), $Size, $base)
}

function New-RoleRefRelevance {
    <#
    .SYNOPSIS
        Renders the combined client-relevance string for a region's policy Fixlet. Pure.

        Three clauses, ANDed:
          1. RoleAwareness.db existence guard (verbatim from Dereso SWD.bes / role_assigner)
          2. single-region gate on the GPC_Sub_Name client setting (region lower-cased)
          3. freshness gate - reapply if the roleref_<region>_applied client setting is
             missing OR older than one day. The `not exists` branch is written first so a
             malformed stored value can never make the whole relevance error out.

    .PARAMETER Region
        The region name. Lower-cased into the relevance literals.

    .PARAMETER IncludeFreshnessGate
        Default $true. 07-05 can pass $false to disable the gate for one region without a
        code edit (Discretion Resolution row 4).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Region,
        [Parameter()] [bool]$IncludeFreshnessGate = $true
    )
    $rlc = $Region.ToLowerInvariant()

    $dbGuard = '(exists folder it whose (exists files "RoleAwareness.db" whose (exists sqlite database of it) of it)) of ((concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal"))))'

    $regionGate = ('(exists setting "GPC_Sub_Name" whose (value of it as string as lowercase = "{0}") of client)' -f $rlc)

    $clauses = @("($dbGuard)", $regionGate)

    if ($IncludeFreshnessGate) {
        $freshGate = ('((not exists setting "roleref_{0}_applied" of client) OR (exists setting "roleref_{0}_applied" of client whose (now - ((value of it as string) as time) > 1 * day)))' -f $rlc)
        $clauses += $freshGate
    }

    return ($clauses -join ' AND ')
}

Export-ModuleMember -Function Build-RegionSnapshot, New-PrefetchLine, New-RoleRefRelevance
