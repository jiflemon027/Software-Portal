#Requires -Version 5.1
# Pester 5 suite for scripts/AxoniousParse.psm1 - the pure ingest transforms.
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/AxoniousParse.Tests.ps1 -Output Detailed -CI
#
# No sqlite3.exe needed - every function here is side-effect free.

BeforeAll {
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\archive\AxoniousParse.psm1'
    $script:SampleCsv  = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\axonious-sample-50.csv'
    Import-Module $script:ModulePath -Force
}

AfterAll { Remove-Module AxoniousParse -Force -ErrorAction SilentlyContinue }

Describe 'AxoniousParse.psm1 - module surface' {
    It 'exports the four public contract functions' {
        $names = (Get-Command -Module AxoniousParse).Name
        foreach ($f in 'Resolve-UserName', 'Get-GroupViews', 'Get-SourceType', 'Resolve-Roles') {
            $names | Should -Contain $f
        }
    }
    It 'declares Export-ModuleMember naming exactly the four contract functions' {
        $src = Get-Content -Raw $script:ModulePath
        $src | Should -Match 'Export-ModuleMember -Function Resolve-UserName, Get-GroupViews, Get-SourceType, Resolve-Roles'
    }
    It 'is pure - no Invoke-SqliteCommand / Write-Host / Set-Content / Add-Content / Invoke-RestMethod' {
        $code = ((Get-Content $script:ModulePath) | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        [regex]::Matches($code, 'Invoke-SqliteCommand|Write-Host|Set-Content|Add-Content|Invoke-RestMethod').Count | Should -Be 0
    }
}

Describe 'Resolve-UserName (D-06)' {
    It 'picks sAMAccountName when present, Username_Src = sam' {
        $r = Resolve-UserName -Sam 'JSmith' -Upn 'jsmith@corp.com' -UserName 'John Smith'
        $r.UserID       | Should -Be 'jsmith'
        $r.Username_Src  | Should -Be 'sam'
    }
    It 'falls back to the UPN local-part when SAM is blank, Username_Src = upn' {
        $r = Resolve-UserName -Sam '' -Upn 'eowens@corp.example.com' -UserName 'Elaine Owens'
        $r.UserID      | Should -Be 'eowens'
        $r.Username_Src | Should -Be 'upn'
    }
    It 'falls back to Aggregated: User Name when SAM and UPN are both blank' {
        $r = Resolve-UserName -Sam '' -Upn '' -UserName 'Kenji.Tanaka'
        $r.UserID      | Should -Be 'kenji.tanaka'
        $r.Username_Src | Should -Be 'username'
    }
    It 'takes the first non-blank line of a multi-valued User Name cell' {
        $r = Resolve-UserName -Sam '' -Upn '' -UserName "`n  `nlager-lang`nlager-langenhagen"
        $r.UserID      | Should -Be 'lager-lang'
        $r.Username_Src | Should -Be 'username'
    }
    It 'always lower-cases the key' {
        (Resolve-UserName -Sam 'LadenVK01_WIT').UserID | Should -Be 'ladenvk01_wit'
    }
    It 'honours a custom -Priority that reverses precedence' {
        $r = Resolve-UserName -Sam 'sammy' -Upn 'up@x.com' -UserName 'u' -Priority 'upn,sam,username'
        $r.UserID      | Should -Be 'up'
        $r.Username_Src | Should -Be 'upn'
    }
    It 'returns $null when every candidate is blank or whitespace' {
        Resolve-UserName -Sam '' -Upn '' -UserName '   ' | Should -BeNullOrEmpty
        Resolve-UserName -Sam $null -Upn $null -UserName $null | Should -BeNullOrEmpty
    }
    It 'reports Username_Src = upn for a blank-SAM row of the real fixture' {
        $blankSam = @(Import-Csv -Path $script:SampleCsv |
                Where-Object { [string]::IsNullOrWhiteSpace($_.'Azure Ad: AD sAMAccountName') -and
                               -not [string]::IsNullOrWhiteSpace($_.'Azure Ad: AD User Principal Name') })[0]
        $blankSam | Should -Not -BeNullOrEmpty
        $r = Resolve-UserName -Sam $blankSam.'Azure Ad: AD sAMAccountName' `
                              -Upn $blankSam.'Azure Ad: AD User Principal Name' `
                              -UserName $blankSam.'Aggregated: User Name'
        $r.Username_Src | Should -Be 'upn'
    }
}

Describe 'Get-GroupViews (Pitfall 10)' {
    It 'extracts the first CN= RDN from a full DN' {
        $v = Get-GroupViews -Raw 'CN=BNX-M365-E3,OU=Service Groups,DC=office,DC=bzn'
        $v.cn      | Should -Be 'BNX-M365-E3'
        $v.dn      | Should -Be 'CN=BNX-M365-E3,OU=Service Groups,DC=office,DC=bzn'
        $v.display | Should -Be 'CN=BNX-M365-E3,OU=Service Groups,DC=office,DC=bzn'
    }
    It 'returns the raw string in all three slots for a bare display name' {
        $v = Get-GroupViews -Raw 'All Tenant Members'
        $v.cn | Should -Be 'All Tenant Members'
        $v.dn | Should -Be 'All Tenant Members'
        $v.display | Should -Be 'All Tenant Members'
    }
    It 'uses the supplied -Display for the display view' {
        $v = Get-GroupViews -Raw 'CN=BNX-M365-E3,OU=x,DC=y' -Display 'BNX M365 E3'
        $v.cn      | Should -Be 'BNX-M365-E3'
        $v.display | Should -Be 'BNX M365 E3'
    }
    It 'does not truncate the CN at a backslash-escaped comma' {
        (Get-GroupViews -Raw 'CN=Smith\, John,OU=People,DC=corp').cn | Should -Be 'Smith, John'
    }
    It 'never throws on a malformed value' {
        { Get-GroupViews -Raw '' } | Should -Not -Throw
        { Get-GroupViews -Raw $null } | Should -Not -Throw
        (Get-GroupViews -Raw 'CN=').cn | Should -Be ''
    }
}

Describe 'Get-SourceType (D-08)' {
    It 'returns Mailing List when an Email is present, beating the Group Type' {
        Get-SourceType -GroupType 'AD Security Group' -Email 'team@corp.com' | Should -Be 'Mailing List'
    }
    It 'maps a security group type' {
        Get-SourceType -GroupType 'AD Security Group' -Email '' | Should -Be 'AD Security Group'
    }
    It 'maps a distribution group type' {
        Get-SourceType -GroupType 'Distribution Group' -Email '' | Should -Be 'Distribution Group'
    }
    It 'maps a unified / Microsoft 365 group type' {
        Get-SourceType -GroupType 'Unified Group' -Email '' | Should -Be 'Azure AD Group'
    }
    It 'returns Unknown for a blank or unrecognised group type' {
        Get-SourceType -GroupType '' -Email '' | Should -Be 'Unknown'
        Get-SourceType -GroupType 'provisioning_managed_group' -Email '' | Should -Be 'Unknown'
    }
    It 'never returns null or empty' {
        Get-SourceType -GroupType $null -Email $null | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-GroupRows (D-07 defensive combine)' {
    It 'a 3 / 2 / 4 ragged shape yields 4 rows and throws no index exception' {
        { Get-GroupRows -Name "a`nb`nc" -Display "x`ny" -GroupType "p`nq`nr`ns" } | Should -Not -Throw
        $rows = Get-GroupRows -Name "a`nb`nc" -Display "x`ny" -GroupType "p`nq`nr`ns"
        @($rows).Count        | Should -Be 4
        @($rows)[3].GroupType | Should -Be 's'
        @($rows)[3].Name      | Should -Be ''
    }
    It 'a row with zero groups yields zero rows and no exception' {
        @(Get-GroupRows -Name '' -Display '' -GroupType '' -Email '' -Source '').Count | Should -Be 0
    }
    It 'a blank middle slot does not shift sibling alignment' {
        $rows = Get-GroupRows -Name "Domain Users`n`nContractors-UK" -GroupType "AD Security Group`n`nAD Security Group"
        @($rows)[2].Name      | Should -Be 'Contractors-UK'
        @($rows)[2].GroupType | Should -Be 'AD Security Group'
    }
    It 'builds a row from the Display slot when the Name slot is blank' {
        $rows = Get-GroupRows -Name "`nAAUK Comms" -Display "AAUK Comms Display`nAAUK Comms"
        @($rows)[0].Name    | Should -Be ''
        @($rows)[0].Display | Should -Be 'AAUK Comms Display'
    }
}
