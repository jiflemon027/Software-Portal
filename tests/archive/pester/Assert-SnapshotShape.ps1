#Requires -Version 5.1
<#
.SYNOPSIS
    The SINGLE definition of the extended-D-11 region-snapshot shape contract.

    Dot-source this file (it is NOT a module):

        . "$PSScriptRoot\Assert-SnapshotShape.ps1"

    Then call:

        Assert-RoleRefSnapshotShape -Snapshot $obj [-ExpectedRegion 'AAG-UK']

    07-00's fixture test and 07-02's publisher + reconcile suites all dot-source this
    same file, so the shape is asserted in exactly one place and the two plans cannot
    drift.

.DESCRIPTION
    Snapshot body contract (07-CONTEXT D-11 amendment 2026-08-29):

      { run_id, region, built_on, validity_months,
        roles: [ { role, users: [ { id, source_type, source_value } ] } ] }

      id           lowercased sAMAccountName match key (UserRole.UserID)
      source_type  a D-08 Source_Type ("AD Security Group" | "Mailing List" |
                   "Azure AD Group" | ...)
      source_value granting group CN / display name; '|'-joined when more than one
                   group granted that role to that user (may be an empty string, but
                   the property must be present)

    "General Access" is never a published role and is never enumerated in a snapshot.
    Absence of a user from every role block is the General-Access default - it is legal
    and this assertion never requires any particular user to be present.
#>

Set-StrictMode -Version Latest

function Assert-RoleRefSnapshotShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Snapshot,

        [Parameter()]
        [string]$ExpectedRegion
    )

    if ($null -eq $Snapshot) {
        throw "Snapshot shape: snapshot is null."
    }

    $names = @($Snapshot.PSObject.Properties.Name)
    foreach ($top in 'run_id', 'region', 'built_on', 'validity_months', 'roles') {
        if ($names -notcontains $top) {
            throw "Snapshot shape: missing top-level key '$top'."
        }
    }

    foreach ($nonBlank in 'run_id', 'region', 'built_on') {
        if ([string]::IsNullOrWhiteSpace([string]$Snapshot.$nonBlank)) {
            throw "Snapshot shape: top-level '$nonBlank' must be a non-blank string."
        }
    }

    if ($ExpectedRegion -and ([string]$Snapshot.region -ne $ExpectedRegion)) {
        throw "Snapshot shape: region '$($Snapshot.region)' does not equal expected '$ExpectedRegion'."
    }

    $rolesIsArray = ($Snapshot.roles -is [System.Array]) -or ($Snapshot.roles -is [System.Collections.IEnumerable] -and $Snapshot.roles -isnot [string])
    if (-not $rolesIsArray) {
        throw "Snapshot shape: 'roles' must be an array (it may be empty)."
    }

    foreach ($roleEntry in @($Snapshot.roles)) {
        $rNames = @($roleEntry.PSObject.Properties.Name)
        if ($rNames -notcontains 'role' -or [string]::IsNullOrWhiteSpace([string]$roleEntry.role)) {
            throw "Snapshot shape: every roles[] entry needs a non-blank 'role'."
        }
        if ($rNames -notcontains 'users') {
            throw "Snapshot shape: roles[] entry '$($roleEntry.role)' is missing 'users'."
        }
        $usersIsArray = ($roleEntry.users -is [System.Array]) -or ($roleEntry.users -is [System.Collections.IEnumerable] -and $roleEntry.users -isnot [string])
        if (-not $usersIsArray) {
            throw "Snapshot shape: roles[].users for '$($roleEntry.role)' must be an array (it may be empty)."
        }

        foreach ($u in @($roleEntry.users)) {
            if ($u -is [string]) {
                throw "Snapshot shape: roles[].users for '$($roleEntry.role)' contains a bare string '$u' - entries must be objects { id, source_type, source_value }."
            }
            $uNames = @($u.PSObject.Properties.Name)
            if ($uNames -notcontains 'id' -or [string]::IsNullOrWhiteSpace([string]$u.id)) {
                throw "Snapshot shape: a users[] entry in role '$($roleEntry.role)' has no non-blank 'id'."
            }
            if ($uNames -notcontains 'source_type' -or [string]::IsNullOrWhiteSpace([string]$u.source_type)) {
                throw "Snapshot shape: users[] entry '$($u.id)' in role '$($roleEntry.role)' has no non-blank 'source_type'."
            }
            if ($uNames -notcontains 'source_value') {
                throw "Snapshot shape: users[] entry '$($u.id)' in role '$($roleEntry.role)' is missing 'source_value' (it may be an empty string, but the key must be present)."
            }
        }
    }

    return $true
}
