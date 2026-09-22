#Requires -Version 5.1
# Pester 5 suite for scripts/Stage-Repository.ps1 + ContentSyncCore.psm1 Read-PrefetchLine
# and the 07-03 rows appended to scripts/Register-AutomationTasks.ps1.
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester -Path tests/pester/Stage-Repository.Tests.ps1,tests/pester/Invoke-ContentSync.Tests.ps1 -Output Detailed -CI
#
# The download/verify Describe builds a throwaway AutomationState.db and mocks
# Invoke-WebRequest / Invoke-RestMethod; when sqlite3.exe cannot be found it is skipped.

function Find-SqliteDir {
    $probes = @()
    if ($env:SQLDIR) { $probes += $env:SQLDIR }
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite'
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\sqlite'
    $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($cmd) { $probes += (Split-Path $cmd.Source -Parent) }
    foreach ($p in $probes) { if ($p -and (Test-Path (Join-Path $p 'sqlite3.exe'))) { return $p } }
    return $null
}

BeforeDiscovery { $script:HasSqlite = [bool](Find-SqliteDir) }

BeforeAll {
    function Find-SqliteDir {
        $probes = @()
        if ($env:SQLDIR) { $probes += $env:SQLDIR }
        $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite'
        $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\sqlite'
        $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
        if ($cmd) { $probes += (Split-Path $cmd.Source -Parent) }
        foreach ($p in $probes) { if ($p -and (Test-Path (Join-Path $p 'sqlite3.exe'))) { return $p } }
        return $null
    }

    $script:SqliteDir  = Find-SqliteDir
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\ContentSyncCore.psm1'
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\Stage-Repository.ps1'
    $script:RegScript  = Join-Path $script:RepoRoot 'scripts\Register-AutomationTasks.ps1'
    $script:HelperPath = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:SchemaSql  = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\automation-db-schema.sql'

    Import-Module $script:ModulePath -Force
    $script:DummyCred = [pscredential]::new('svc', (ConvertTo-SecureString 'pw' -AsPlainText -Force))

    if ($script:SqliteDir) {
        . $script:HelperPath
        . $script:ScriptPath   # dot-source: defines Start-RepoStage etc., guard skips main

        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('reposta-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:New-TestDb {
            $db  = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.db')
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql (Get-Content -Raw $script:SchemaSql) | Out-Null
            foreach ($c in 'portal_fixlet_id','repo_staged_at','discovery_kind','reject_reason') {
                Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql "ALTER TABLE ContentItem ADD COLUMN $c TEXT" | Out-Null
            }
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql "ALTER TABLE ContentCache ADD COLUMN note TEXT" | Out-Null
            return $db
        }
        function script:Q {
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }
        function script:Seed-Live {
            param([string]$Db, [string]$Id = '200', [string]$PortalId = '500', [int]$IsTask = 0)
            script:Q $Db "INSERT INTO ContentItem (fixlet_id, source_site, fixlet_name, stage, is_task, portal_fixlet_id) VALUES (@i, 'SrcSite', 'App v1.0 - Windows (x64)', 'live', @t, @p)" `
                @{ i = $Id; t = "$IsTask"; p = $PortalId } | Out-Null
        }
        function script:Run-Stage {
            param([string]$Db, [string]$Staging, [hashtable]$Extra = @{})
            $a = @{
                DatabasePath     = $Db
                SQLDir           = $script:SqliteDir
                SqliteHelperPath = $script:HelperPath
                CoreModulePath   = $script:ModulePath
                Credential       = $script:DummyCred
                StagingRoot      = $Staging
                LogDir           = (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N')))
                BESRootUrl       = 'https://bes.example:52311'
            }
            foreach ($k in $Extra.Keys) { $a[$k] = $Extra[$k] }
            Start-RepoStage @a
        }
        # a real 50-byte payload + its true SHA1
        $script:PayloadBytes = [byte[]](0..49)
        $tmp = Join-Path $script:TmpRoot 'payload.bin'
        [System.IO.File]::WriteAllBytes($tmp, $script:PayloadBytes)
        $script:PayloadSha1 = (Get-FileHash -Algorithm SHA1 -Path $tmp).Hash.ToLowerInvariant()
        $script:PayloadSize = $script:PayloadBytes.Length
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item -Path $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'ContentSyncCore.psm1 - Read-PrefetchLine' {

    It 'parses a canonical prefetch line including the optional sha256 suffix' {
        $r = Read-PrefetchLine -Line 'prefetch setup.exe sha1:ABCDEF0123456789 size:2048 http://vendor.example/setup.exe sha256:00ff00ff'
        $r.FileName | Should -Be 'setup.exe'
        $r.Sha1     | Should -Be 'abcdef0123456789'   # lower-cased
        $r.Size     | Should -Be 2048
        $r.Size     | Should -BeOfType ([long])
        $r.Url      | Should -Be 'http://vendor.example/setup.exe'
        $r.Sha256   | Should -Be '00ff00ff'
    }

    It 'parses a line without the prefetch keyword and without sha256' {
        $r = Read-PrefetchLine -Line 'x.msi sha1:DEADBEEF size:10 https://h/x.msi'
        $r.FileName | Should -Be 'x.msi'
        $r.Sha1     | Should -Be 'deadbeef'
        $r.Sha256   | Should -BeNullOrEmpty
    }

    It 'returns $null for a non-prefetch line' {
        Read-PrefetchLine -Line 'waithidden msiexec.exe /i "{pathname of ...}"' | Should -BeNullOrEmpty
        Read-PrefetchLine -Line '' | Should -BeNullOrEmpty
    }
}

Describe 'Stage-Repository.ps1 - download, SHA1 verify, place' -Skip:(-not $script:HasSqlite) {

    BeforeEach {
        $script:Prefetch = "prefetch installer.exe sha1:$($script:PayloadSha1) size:$($script:PayloadSize) http://vendor.example/installer.exe"
        Mock -CommandName Invoke-RestMethod -MockWith {
            "<?xml version='1.0'?><BES><Task><Title>t</Title><DefaultAction ID='Action1'><ActionScript MIMEType='application/x-Fixlet-Windows-Shell'>$($script:Prefetch)`nwaithidden installer.exe /S</ActionScript></DefaultAction></Task></BES>"
        }
        Mock -CommandName Invoke-WebRequest -MockWith {
            [System.IO.File]::WriteAllBytes($OutFile, $script:PayloadBytes)
        }
    }

    It 'a matching hash lands the file under the lower-cased sha1 folder and writes verified = 1' {
        $db = script:New-TestDb
        script:Seed-Live $db -IsTask 1
        $staging = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        script:Run-Stage -Db $db -Staging $staging | Out-Null

        $expected = Join-Path (Join-Path $staging $script:PayloadSha1) 'installer.exe'
        Test-Path $expected | Should -BeTrue
        $row = (script:Q $db "SELECT verified, filename, original_url FROM ContentCache WHERE sha1 = @h" @{ h = $script:PayloadSha1 })[0]
        [int]$row.verified | Should -Be 1
        $row.filename | Should -Be 'installer.exe'
        (script:Q $db "SELECT repo_staged_at FROM ContentItem WHERE fixlet_id='200'")[0].repo_staged_at | Should -Not -BeNullOrEmpty
    }

    It 'the GET used the SINGULAR task path (is_task = 1)' {
        $db = script:New-TestDb
        script:Seed-Live $db -IsTask 1
        script:Run-Stage -Db $db -Staging (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) | Out-Null
        Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter { $Uri -match '/task/custom/' }
    }

    It 'a SHA1 mismatch leaves zero files under StagingRoot, writes verified = 0, and the run still finishes' {
        $db = script:New-TestDb
        script:Seed-Live $db
        $script:Prefetch = "prefetch installer.exe sha1:$('0' * 40) size:$($script:PayloadSize) http://vendor.example/installer.exe"
        $staging = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        $log = script:Run-Stage -Db $db -Staging $staging

        @(Get-ChildItem -Path $staging -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        $row = (script:Q $db "SELECT verified, note FROM ContentCache WHERE sha1 = @h" @{ h = ('0' * 40) })[0]
        [int]$row.verified | Should -Be 0
        $row.note | Should -Match 'actual sha1='
        $log.status | Should -Be 'partial'
        (script:Q $db "SELECT repo_staged_at FROM ContentItem WHERE fixlet_id='200'")[0].repo_staged_at | Should -BeNullOrEmpty
    }

    It 'a size mismatch (right sha1, wrong size) is also discarded' {
        $db = script:New-TestDb
        script:Seed-Live $db
        $script:Prefetch = "prefetch installer.exe sha1:$($script:PayloadSha1) size:999999 http://vendor.example/installer.exe"
        $staging = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        script:Run-Stage -Db $db -Staging $staging | Out-Null
        @(Get-ChildItem -Path $staging -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        [int](script:Q $db "SELECT verified FROM ContentCache WHERE sha1 = @h" @{ h = $script:PayloadSha1 })[0].verified | Should -Be 0
    }

    It 'a sha1 already cached with verified = 1 is not re-downloaded' {
        $db = script:New-TestDb
        script:Seed-Live $db
        script:Q $db "INSERT INTO ContentCache (sha1, filename, original_url, staged_at, size_bytes, verified) VALUES (@h, 'installer.exe', 'http://x', datetime('now'), @s, 1)" `
            @{ h = $script:PayloadSha1; s = "$($script:PayloadSize)" } | Out-Null
        script:Run-Stage -Db $db -Staging (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) | Out-Null
        Should -Invoke -CommandName Invoke-WebRequest -Times 0
    }

    It 'a file exceeding MaxStageFileMB is skipped and never downloaded' {
        $db = script:New-TestDb
        script:Seed-Live $db
        $script:Prefetch = "prefetch big.iso sha1:$($script:PayloadSha1) size:9999999999 http://vendor.example/big.iso"
        $staging = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        script:Run-Stage -Db $db -Staging $staging -Extra @{ MaxStageFileMB = 1 } | Out-Null
        Should -Invoke -CommandName Invoke-WebRequest -Times 0
        @(Get-ChildItem -Path $staging -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It '-WhatIf performs zero downloads and creates zero directories under StagingRoot' {
        $db = script:New-TestDb
        script:Seed-Live $db
        $staging = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        script:Run-Stage -Db $db -Staging $staging -Extra @{ WhatIf = $true } | Out-Null
        Should -Invoke -CommandName Invoke-WebRequest -Times 0
        @(Get-ChildItem -Path $staging -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
        [int](script:Q $db "SELECT COUNT(*) AS n FROM ContentCache")[0].n | Should -Be 0
        [int](script:Q $db "SELECT COUNT(*) AS n FROM SyncRun")[0].n | Should -Be 0
    }

    It 'the script never references a rewritten 127.0.0.1 URL outside comments' {
        @(Get-Content $script:ScriptPath | Where-Object { $_ -notmatch '^#' } | Where-Object { $_ -match '127\.0\.0\.1' }).Count | Should -Be 0
    }
}

Describe 'Register-AutomationTasks.ps1 - four rows after 07-03' {
    BeforeAll { $script:RegSrc = Get-Content -Raw $script:RegScript }

    It 'the shared table now holds all four task names, one definition, APPEND-ONLY header intact' {
        ([regex]::Matches($script:RegSrc, '\$AutomationTaskTable\s*=')).Count | Should -Be 1
        foreach ($n in 'DeresoRoleIngest','DeresoRolePublish','DeresoContentSync','DeresoRepoStage') {
            $script:RegSrc | Should -Match "Name\s*=\s*'$n'"
        }
        $script:RegSrc | Should -Match 'APPEND-ONLY'
    }

    It 'the config task XMLs exist and parse as XML' {
        $cs = Join-Path $script:RepoRoot 'config\task-DeresoContentSync.xml'
        $rs = Join-Path $script:RepoRoot 'config\task-DeresoRepoStage.xml'
        Test-Path $cs | Should -BeTrue
        Test-Path $rs | Should -BeTrue
        { [xml](Get-Content -Raw $cs) } | Should -Not -Throw
        { [xml](Get-Content -Raw $rs) } | Should -Not -Throw
    }

    It '-WhatIf selects every registered task and invokes Register-ScheduledTask zero times' {
        # NOTE: this count intentionally grows as later plans append rows to the
        # APPEND-ONLY $AutomationTaskTable (07-05 added a 5th row, DeresoRoleGroupSync) --
        # asserting "at least the four 07-03 names are present" above is the stable
        # contract; the raw selected-count below is recomputed from the table itself so
        # this test does not need editing again on every future append.
        Mock -CommandName Register-ScheduledTask -MockWith { }
        $cfg = Join-Path $script:TmpRoot ('cfg-' + [guid]::NewGuid().ToString('N'))
        $expectedCount = ([regex]::Matches($script:RegSrc, "(?m)^\s*Name\s*=\s*'[^']+'")).Count
        $out = & $script:RegScript -ConfigDir $cfg -WhatIf *>&1 | Out-String
        $out | Should -Match "$expectedCount task\(s\) selected"
        Should -Invoke -CommandName Register-ScheduledTask -Times 0
    }
}
