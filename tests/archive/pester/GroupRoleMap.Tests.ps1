#Requires -Version 5.1
# Pester 5 suite for the GroupRoleMap matcher (Resolve-Roles in scripts/AxoniousParse.psm1).
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/GroupRoleMap.Tests.ps1 -Output Detailed -CI
#
# Pure-function coverage of D-08: exact NOCASE, *-suffix wildcard, Match_On cn/display/dn,
# all-matches-apply, Priority as advisory ordering only, Active=0 never fires. No sqlite3.exe.

BeforeAll {
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\AxoniousParse.psm1'
    $script:SeedPath   = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\grouprolemap-seed.json'
    Import-Module $script:ModulePath -Force

    # Load the synthetic rule set and attach a synthetic GRMID (as GroupRoleMap would have).
    $seed = (Get-Content -Raw $script:SeedPath | ConvertFrom-Json).rules
    $i = 0
    $script:Rules = @(foreach ($r in $seed) {
        $i++
        [pscustomobject]@{ GRMID = $i; Pattern = $r.Pattern; Match_On = $r.Match_On
                           Role = $r.Role; Priority = $r.Priority; Active = $r.Active }
    })

    function script:Views { param([string]$Cn = '', [string]$Display = '', [string]$Dn = '')
        @{ cn = $Cn; display = $Display; dn = $Dn }
    }
    function script:Roles { param($Result) @(@($Result) | ForEach-Object { $_.Role }) }
}

AfterAll { Remove-Module AxoniousParse -Force -ErrorAction SilentlyContinue }

Describe 'Resolve-Roles - exact NOCASE match' {
    It 'matches case-insensitively when the view is lower-cased' {
        script:Roles (Resolve-Roles -GroupViews (script:Views -Cn 'bnx-m365-e3') -Rules $script:Rules) |
            Should -Contain 'IT Operations'
    }
    It 'matches case-insensitively when the pattern casing differs from the view' {
        script:Roles (Resolve-Roles -GroupViews (script:Views -Cn 'BNX-M365-E3') -Rules $script:Rules) |
            Should -Contain 'IT Operations'
    }
}

Describe 'Resolve-Roles - *-suffix wildcard' {
    It 'matches a prefix' {
        script:Roles (Resolve-Roles -GroupViews (script:Views -Cn 'IT-Dev-Team') -Rules $script:Rules) |
            Should -Contain 'IT Operations'
    }
    It 'does not match a string shorter than the prefix' {
        $r = Resolve-Roles -GroupViews (script:Views -Cn 'IT-De') -Rules $script:Rules
        @($r).Count | Should -Be 0
    }
    It 'treats a * in the MIDDLE of a pattern as a literal, not a glob' {
        $mid = @([pscustomobject]@{ GRMID = 99; Pattern = 'IT*Dev'; Match_On = 'cn'; Role = 'X'; Priority = 1; Active = 1 })
        (Resolve-Roles -GroupViews (script:Views -Cn 'IT-Dev')  -Rules $mid | Measure-Object).Count | Should -Be 0
        (Resolve-Roles -GroupViews (script:Views -Cn 'IT*Dev')  -Rules $mid | Measure-Object).Count | Should -Be 1
    }
}

Describe 'Resolve-Roles - Match_On selects the view' {
    It 'Match_On=display tests the display view and ignores cn' {
        script:Roles (Resolve-Roles -GroupViews (script:Views -Cn 'irrelevant' -Display 'All Tenant Members') -Rules $script:Rules) |
            Should -Contain 'Business Default'
    }
    It 'a display-only rule does not fire off the cn view' {
        $r = Resolve-Roles -GroupViews (script:Views -Cn 'All Tenant Members' -Display 'something else') -Rules $script:Rules
        script:Roles $r | Should -Not -Contain 'Business Default'
    }
    It 'Match_On=dn tests the raw DN' {
        script:Roles (Resolve-Roles -GroupViews (script:Views -Dn 'CN=Domain Users,OU=OFFICE Groups,DC=office,DC=bzn') -Rules $script:Rules) |
            Should -Contain 'Business Operations'
    }
}

Describe 'Resolve-Roles - Active and all-matches-apply' {
    It 'an Active=0 rule never fires' {
        $r = Resolve-Roles -GroupViews (script:Views -Cn 'LegacyRetiredGroup') -Rules $script:Rules
        @($r).Count | Should -Be 0
    }
    It 'two active rules matching the same group both fire, with distinct GRMID' {
        $r = @(Resolve-Roles -GroupViews (script:Views -Cn 'gaa_UK-KnowBe4') -Rules $script:Rules)
        $r.Count | Should -Be 2
        (script:Roles $r | Sort-Object) -join ',' | Should -Be 'Business Default,Security Awareness'
        ($r.GRMID | Select-Object -Unique).Count | Should -Be 2
    }
}

Describe 'Resolve-Roles - Priority and no-match behaviour' {
    It 'Priority only changes emitted order, never suppresses a match' {
        $rules = @(
            [pscustomobject]@{ GRMID = 1; Pattern = 'G'; Match_On = 'cn'; Role = 'Low';  Priority = 90; Active = 1 }
            [pscustomobject]@{ GRMID = 2; Pattern = 'G'; Match_On = 'cn'; Role = 'High'; Priority = 10; Active = 1 }
        )
        $out = @(Resolve-Roles -GroupViews (script:Views -Cn 'G') -Rules $rules)
        $out.Count      | Should -Be 2
        $out[0].Role    | Should -Be 'High'
        $out[1].Role    | Should -Be 'Low'
    }
    It 'an unmatched group yields an empty result, not $null-with-error' {
        $r = Resolve-Roles -GroupViews (script:Views -Cn 'nothing-matches-this') -Rules $script:Rules
        @($r).Count | Should -Be 0
        { @($r).Count } | Should -Not -Throw
    }
    It 'a $null rule set returns empty and does not throw' {
        { Resolve-Roles -GroupViews (script:Views -Cn 'x') -Rules $null } | Should -Not -Throw
        @(Resolve-Roles -GroupViews (script:Views -Cn 'x') -Rules $null).Count | Should -Be 0
    }
}
