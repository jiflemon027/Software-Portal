#Requires -Version 5.1
# Pester 5 suite for scripts/Upsert-RolePublish.ps1 (07-03 Task 1) - the D-05 root-server
# audit store (RolePublishRun / RoleUsers schema + per-Publish snapshot writer).
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Upsert-RolePublish.Tests.ps1 -Output Detailed -CI
#
# The source-guarantee Describe needs no sqlite3.exe and always runs. The schema-and-
# writes Describe needs sqlite3.exe (resolved from $env:SQLDIR then a probe list); when
# it cannot be found that Describe is skipped, not failed, matching every other DB-backed
# suite in this repo.

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
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\Upsert-RolePublish.ps1'
    $script:HelperPath = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:ScriptText = Get-Content -Raw $script:ScriptPath

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('upsert-rolepublish-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:Q {
            # Flatten Sqlite-Helper's (return ,$rows) wrapper so multi-row .Count is correct.
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }

        function script:New-TestDb {
            # Fresh directory per DB, carrying its own Sqlite-Helper.ps1 copy so every
            # Run-Upsert call below exercises the script's DEFAULT -SqliteHelperPath
            # resolution (Join-Path (Split-Path -DatabasePath) 'Sqlite-Helper.ps1'),
            # never passing -SqliteHelperPath explicitly.
            $dir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Copy-Item $script:HelperPath (Join-Path $dir 'Sqlite-Helper.ps1') -Force
            return (Join-Path $dir 'RolePublish.db')
        }

        function script:New-Payload {
            param([string]$Role, [string]$PublishedBy, [object[]]$Users = @())
            $obj  = [ordered]@{ role = $Role; published_by = $PublishedBy; users = @($Users) }
            $json = $obj | ConvertTo-Json -Depth 5 -Compress
            $path = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.json')
            Set-Content -Path $path -Value $json -Encoding UTF8
            return $path
        }

        function script:Write-RawPayload {
            param([string]$Content)
            $path = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.json')
            Set-Content -Path $path -Value $Content -Encoding UTF8
            return $path
        }

        function script:Run-Upsert {
            param([string]$Db, [string]$PayloadPath, [switch]$WhatIf)
            $p = @{
                PayloadPath  = $PayloadPath
                DatabasePath = $Db
                SQLDir       = $script:SqliteDir
            }
            if ($WhatIf) { $p['WhatIf'] = $true }
            $out = & $script:ScriptPath @p *>&1
            return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
        }
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item -Path $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Upsert-RolePublish.ps1 - source guarantees' {
    BeforeAll {
        # Strip comment-only lines so a doc comment describing what the script AVOIDS
        # (e.g. ".NOTES: no Add-Type") cannot itself trip these checks.
        $script:Body = ($script:ScriptText -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'contains no dynamic type loading, no System.Data.SQLite, no INSERT OR REPLACE, no DROP TABLE' {
        ($script:Body -match 'Add-Type')             | Should -BeFalse
        ($script:Body -match 'System\.Data\.SQLite') | Should -BeFalse
        ($script:Body -match 'INSERT OR REPLACE')    | Should -BeFalse
        ($script:Body -match 'DROP TABLE')            | Should -BeFalse
    }

    It 'declares the four CREATE ... IF NOT EXISTS statements from the D-05 schema' {
        $script:ScriptText | Should -Match ([regex]::Escape('CREATE TABLE IF NOT EXISTS RolePublishRun'))
        $script:ScriptText | Should -Match ([regex]::Escape('CREATE TABLE IF NOT EXISTS RoleUsers'))
        $script:ScriptText | Should -Match ([regex]::Escape('CREATE INDEX IF NOT EXISTS idx_roleusers_run'))
        $script:ScriptText | Should -Match ([regex]::Escape('CREATE INDEX IF NOT EXISTS idx_roleusers_role'))
    }

    It 'declares -PayloadPath, -DatabasePath, -SQLDir, -SqliteHelperPath and SupportsShouldProcess' {
        $script:ScriptText | Should -Match '\[string\]\$PayloadPath'
        $script:ScriptText | Should -Match '\[string\]\$DatabasePath'
        $script:ScriptText | Should -Match '\[string\]\$SQLDir'
        $script:ScriptText | Should -Match '\[string\]\$SqliteHelperPath'
        $script:ScriptText | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
    }
}

Describe 'Upsert-RolePublish.ps1 - schema and writes' -Skip:(-not $HasSqlite) {

    It 'first run against a nonexistent DB creates both tables' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('alice'))
        $res.ExitCode | Should -Be 0
        $tables = @((script:Q $db "SELECT name FROM sqlite_master WHERE type='table'").name)
        $tables | Should -Contain 'RolePublishRun'
        $tables | Should -Contain 'RoleUsers'
    }

    It 'first run against a nonexistent DB creates both indexes' {
        $db  = script:New-TestDb
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('alice')) | Out-Null
        $idx = @((script:Q $db "SELECT name FROM sqlite_master WHERE type='index'").name)
        $idx | Should -Contain 'idx_roleusers_run'
        $idx | Should -Contain 'idx_roleusers_role'
    }

    It 'idempotency: a second run adds no duplicate tables or indexes' {
        $db = script:New-TestDb
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('alice')) | Out-Null
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('bob'))   | Out-Null
        $names = @((script:Q $db "SELECT name FROM sqlite_master WHERE type IN ('table','index')").name)
        ($names | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }

    It 'idempotency: SELECT COUNT(*) FROM RolePublishRun is exactly 2 after two runs, no rows lost' {
        $db = script:New-TestDb
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('alice')) | Out-Null
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('bob'))   | Out-Null
        $n = [int](script:Q $db "SELECT COUNT(*) AS n FROM RolePublishRun")[0].n
        $n | Should -Be 2
    }

    It 'snapshot semantics: the canonical MAX(RunID) membership query returns only the latest run''s users' {
        $db = script:New-TestDb
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('bob', 'alice')) | Out-Null
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('carol'))         | Out-Null

        $current = script:Q $db @"
SELECT u.UserID FROM RoleUsers u
WHERE u.RunID = (SELECT MAX(RunID) FROM RolePublishRun WHERE Role = @role)
ORDER BY u.UserID
"@ @{ role = 'IT Operations' }
        @($current.UserID) | Should -Be @('carol')
    }

    It 'snapshot semantics: history is preserved, not overwritten (3 RoleUsers rows across both runs)' {
        $db = script:New-TestDb
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('bob', 'alice')) | Out-Null
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('carol'))         | Out-Null
        $n = [int](script:Q $db "SELECT COUNT(*) AS n FROM RoleUsers WHERE Role='IT Operations'")[0].n
        $n | Should -Be 3
    }

    It 'multi-role independence (D-04): publishing a second role does not change the first role''s latest run' {
        $db = script:New-TestDb
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('alice')) | Out-Null
        $before = [int](script:Q $db "SELECT MAX(RunID) AS r FROM RolePublishRun WHERE Role=@r" @{ r = 'IT Operations' })[0].r

        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'Business Operations' -PublishedBy 'jfannon' -Users @('alice')) | Out-Null
        $after = [int](script:Q $db "SELECT MAX(RunID) AS r FROM RolePublishRun WHERE Role=@r" @{ r = 'IT Operations' })[0].r

        $after | Should -Be $before
    }

    It 'empty list is legal: UserCount=0, zero RoleUsers rows, exit 0' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @())
        $res.ExitCode | Should -Be 0
        $run = script:Q $db "SELECT UserCount FROM RolePublishRun WHERE Role=@r ORDER BY RunID DESC LIMIT 1" @{ r = 'IT Operations' }
        [int]$run[0].UserCount | Should -Be 0
        $rows = [int](script:Q $db "SELECT COUNT(*) AS n FROM RoleUsers WHERE Role=@r" @{ r = 'IT Operations' })[0].n
        $rows | Should -Be 0
    }

    It 'SQL injection (T-07-03-02): a DROP-TABLE-payload username exits 0 and RoleUsers survives in sqlite_master' {
        $db   = script:New-TestDb
        $evil = "o'brien'); DROP TABLE RoleUsers;--"
        $res  = script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @($evil))
        $res.ExitCode | Should -Be 0
        $tables = @((script:Q $db "SELECT name FROM sqlite_master WHERE type='table'").name)
        $tables | Should -Contain 'RoleUsers'
    }

    It 'SQL injection (T-07-03-02): the crafted username is stored verbatim (lower-cased), not executed' {
        $db   = script:New-TestDb
        $evil = "o'brien'); DROP TABLE RoleUsers;--"
        script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @($evil)) | Out-Null
        $stored = script:Q $db "SELECT UserID FROM RoleUsers WHERE Role=@r" @{ r = 'IT Operations' }
        $stored[0].UserID | Should -Be $evil.ToLowerInvariant()
    }

    It 'normalisation: mixed-case / padded duplicates collapse to two ordinal-sorted rows' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('Alice', '  alice ', 'BOB'))
        $res.ExitCode | Should -Be 0
        $stored = script:Q $db "SELECT UserID FROM RoleUsers WHERE Role=@r ORDER BY RUID" @{ r = 'IT Operations' }
        @($stored.UserID) | Should -Be @('alice', 'bob')
    }

    It '-WhatIf performs zero database access: the DB file does not exist afterwards' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:New-Payload -Role 'IT Operations' -PublishedBy 'jfannon' -Users @('alice')) -WhatIf
        $res.ExitCode | Should -Be 0
        Test-Path -LiteralPath $db | Should -BeFalse
    }

    It 'bad payload: missing file produces a non-zero exit code and touches no DB file' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (Join-Path $script:TmpRoot 'does-not-exist.json')
        $res.ExitCode | Should -Not -Be 0
        Test-Path -LiteralPath $db | Should -BeFalse
    }

    It 'bad payload: malformed JSON produces a non-zero exit code and touches no DB file' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:Write-RawPayload -Content '{ this is not json')
        $res.ExitCode | Should -Not -Be 0
        Test-Path -LiteralPath $db | Should -BeFalse
    }

    It 'bad payload: missing role produces a non-zero exit code and touches no DB file' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:Write-RawPayload -Content '{"published_by":"jfannon","users":["alice"]}')
        $res.ExitCode | Should -Not -Be 0
        Test-Path -LiteralPath $db | Should -BeFalse
    }

    It 'bad payload: missing published_by produces a non-zero exit code and touches no DB file' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:Write-RawPayload -Content '{"role":"IT Operations","users":["alice"]}')
        $res.ExitCode | Should -Not -Be 0
        Test-Path -LiteralPath $db | Should -BeFalse
    }

    It 'bad payload: users as a string instead of an array produces a non-zero exit code and touches no DB file' {
        $db  = script:New-TestDb
        $res = script:Run-Upsert -Db $db -PayloadPath (script:Write-RawPayload -Content '{"role":"IT Operations","published_by":"jfannon","users":"alice"}')
        $res.ExitCode | Should -Not -Be 0
        Test-Path -LiteralPath $db | Should -BeFalse
    }
}
