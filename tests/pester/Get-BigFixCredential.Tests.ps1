#Requires -Version 5.1
# Pester 5 suite for scripts/Get-BigFixCredential.ps1 and the scripts/Register-AutomationTasks.ps1 skeleton
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Get-BigFixCredential.Tests.ps1 -Output Detailed -CI
#
# Invoke-RestMethod is mocked - these tests never touch the network or AKeyless.

BeforeAll {
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:CredScript = Join-Path $script:RepoRoot 'scripts\Get-BigFixCredential.ps1'
    $script:RegScript  = Join-Path $script:RepoRoot 'scripts\Register-AutomationTasks.ps1'

    $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('cred-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

    $script:TokenFile     = Join-Path $script:TmpRoot 'vault.token'
    Set-Content -Path $script:TokenFile -Value 'dummy-uid-token-value' -NoNewline
    $script:MissingToken  = Join-Path $script:TmpRoot 'nope.token'
    # Kept as plain literals (also duplicated inside the Mock bodies below - a mock
    # scriptblock does not see $script:-scoped test variables).
    $script:TestSecretPath = '/gpc/test/BigFix-RoleSync-Operator'
    $script:TestUser       = 'svc-rolesync'
    $script:TestSecret     = 'S3cr3t-P@ssw0rd!'

    function script:Invoke-Cred {
        param([hashtable]$Extra = @{})
        $a = @{
            TokenFile  = $script:TokenFile
            SecretPath = $script:TestSecretPath
            UserName   = $script:TestUser
        }
        foreach ($k in $Extra.Keys) { $a[$k] = $Extra[$k] }
        & $script:CredScript @a
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Get-BigFixCredential.ps1' {

    BeforeEach {
        Mock -CommandName Write-EventLog -MockWith { }
        Mock -CommandName Invoke-RestMethod -MockWith {
            if ($Uri -like '*akeyless.io/auth*') {
                return [pscustomobject]@{ token = 'AUTH-TOKEN-OK' }
            }
            $o = [pscustomobject]@{}
            $o | Add-Member -NotePropertyName '/gpc/test/BigFix-RoleSync-Operator' -NotePropertyValue 'S3cr3t-P@ssw0rd!'
            return $o
        }
    }

    It 'returns a [pscredential] whose UserName matches and whose password decrypts to the secret' {
        $cred = script:Invoke-Cred
        $cred | Should -BeOfType ([pscredential])
        $cred.UserName | Should -Be $script:TestUser
        $cred.GetNetworkCredential().Password | Should -Be $script:TestSecret
    }

    It 'calls Invoke-RestMethod exactly twice (auth + get-secret-value)' {
        script:Invoke-Cred | Out-Null
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }

    It 'throws a distinct error when the token file is absent' {
        { script:Invoke-Cred -Extra @{ TokenFile = $script:MissingToken } } | Should -Throw '*token file missing*'
    }

    It 'throws when UID auth returns an empty token' {
        Mock -CommandName Invoke-RestMethod -MockWith {
            if ($Uri -like '*akeyless.io/auth*') { return [pscustomobject]@{ token = '' } }
            $o = [pscustomobject]@{}; $o | Add-Member -NotePropertyName '/gpc/test/BigFix-RoleSync-Operator' -NotePropertyValue 'x'; return $o
        }
        { script:Invoke-Cred } | Should -Throw '*no token*'
    }

    It 'throws when get-secret-value returns an empty value for the path' {
        Mock -CommandName Invoke-RestMethod -MockWith {
            if ($Uri -like '*akeyless.io/auth*') { return [pscustomobject]@{ token = 'AUTH-TOKEN-OK' } }
            $o = [pscustomobject]@{}; $o | Add-Member -NotePropertyName '/gpc/test/BigFix-RoleSync-Operator' -NotePropertyValue ''; return $o
        }
        { script:Invoke-Cred } | Should -Throw '*empty secret*'
    }

    It 'makes ZERO Invoke-RestMethod calls under -WhatIf' {
        script:Invoke-Cred -Extra @{ WhatIf = $true } | Out-Null
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe 'Get-BigFixCredential.ps1 - source guarantees (secret never leaks)' {
    BeforeAll { $script:credSrc = Get-Content -Raw $script:CredScript }

    It 'never starts a transcript' {
        $script:credSrc | Should -Not -Match 'Start-Transcript'
    }
    It 'never writes the plaintext secret variable to any output stream' {
        $script:credSrc | Should -Not -Match 'Write-(Host|Output|Verbose|Debug|Information)[^\r\n]*\$secretPlain'
    }
    It 'never persists the secret via DPAPI / ConvertFrom-SecureString' {
        $script:credSrc | Should -Not -Match 'ConvertFrom-SecureString'
        $script:credSrc | Should -Not -Match 'DPAPI'
    }
    It 'uses the universal-identity auth flow and returns a [pscredential]' {
        $script:credSrc | Should -Match 'universal_identity'
        $script:credSrc | Should -Match 'get-secret-value'
        $script:credSrc | Should -Match '\[pscredential\]'
    }
}

Describe 'Register-AutomationTasks.ps1 - shared task table' {
    BeforeAll { $script:regSrc = Get-Content -Raw $script:RegScript }

    It 'parses without error' {
        { [scriptblock]::Create($script:regSrc) } | Should -Not -Throw
    }
    It 'carries the shared task-table contract markers' {
        $script:regSrc | Should -Match 'AutomationTaskTable'
        $script:regSrc | Should -Match 'Register-ScheduledTask'
        $script:regSrc | Should -Match 'schtasks\.exe'
        $script:regSrc | Should -Match 'APPEND-ONLY'
    }
    It 'holds all four rows after 07-02 (role) + 07-03 (content), still one table definition' {
        ([regex]::Matches($script:regSrc, '\$AutomationTaskTable\s*=')).Count | Should -Be 1
        $script:regSrc | Should -Match "Name\s*=\s*'DeresoRoleIngest'"
        $script:regSrc | Should -Match "Name\s*=\s*'DeresoRolePublish'"
        $script:regSrc | Should -Match "Name\s*=\s*'DeresoContentSync'"
        $script:regSrc | Should -Match "Name\s*=\s*'DeresoRepoStage'"
        # the 07-02 role rows are still byte-identical (APPEND-ONLY) and the header comment intact
        $script:regSrc | Should -Match "07-02 adds  DeresoRoleIngest"
    }
    It 'selects all four tasks and registers nothing under -WhatIf' {
        Mock Register-ScheduledTask { }
        $out = & $script:RegScript -ConfigDir (Join-Path $script:TmpRoot 'cfg') -WhatIf *>&1 | Out-String
        $LASTEXITCODE | Should -BeIn @(0, $null)
        $out | Should -Match '4 task\(s\) selected'
        $out | Should -Match '\[WOULD REGISTER\]'
        $out | Should -Match '\[DONE\]'
        Should -Invoke Register-ScheduledTask -Times 0
    }
}
