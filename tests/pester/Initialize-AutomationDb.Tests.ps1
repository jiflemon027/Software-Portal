#Requires -Version 5.1
# Pester 5 suite for scripts/Initialize-AutomationDb.ps1
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Initialize-AutomationDb.Tests.ps1 -Output Detailed -CI
#
# DB-backed contexts need sqlite3.exe. Location resolves from $env:SQLDIR, then a
# documented probe list (see tests/pester/README.md). When it cannot be found those
# contexts are skipped (not failed) so the suite still exits 0 on a host without it.

function Find-SqliteDir {
    $probes = @()
    if ($env:SQLDIR) { $probes += $env:SQLDIR }
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite'
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\sqlite'
    $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($cmd) { $probes += (Split-Path $cmd.Source -Parent) }
    foreach ($p in $probes) {
        if ($p -and (Test-Path (Join-Path $p 'sqlite3.exe'))) { return $p }
    }
    return $null
}

BeforeDiscovery {
    $script:HasSqlite = [bool](Find-SqliteDir)
}

BeforeAll {
    function Find-SqliteDir {
        $probes = @()
        if ($env:SQLDIR) { $probes += $env:SQLDIR }
        $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite'
        $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\sqlite'
        $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
        if ($cmd) { $probes += (Split-Path $cmd.Source -Parent) }
        foreach ($p in $probes) {
            if ($p -and (Test-Path (Join-Path $p 'sqlite3.exe'))) { return $p }
        }
        return $null
    }

    $script:SqliteDir     = Find-SqliteDir
    $script:RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ScriptPath    = Join-Path $script:RepoRoot 'scripts\Initialize-AutomationDb.ps1'
    $script:HelperPath    = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:ConfigDefault = Join-Path $script:RepoRoot 'config\PipelineConfig.defaults.json'

    $script:ExpectedTables = @(
        'Role','Region','GroupRoleMap','RefUser','UserRole','RolePublication',
        'Snapshot','SyncRun','PipelineConfig','ContentItem','ContentCache'
    )
    $script:ExpectedRegions = @(
        'UAP','MOT','APAC','APAC-MOT','APAC-M&A',
        'AAG-DE','AAG-FR','AAG-UK','AAG-ES','AAG-BLX','AAG-PL','AAG-PT','GPC'
    )
    $script:ExpectedRoles = @('IT Operations','Business Operations','Business Default')

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('autodb-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:Run-Init {
            param([string]$Db, [switch]$WhatIf)
            $a = @{
                DatabasePath           = $Db
                SQLDir                 = $script:SqliteDir
                SqliteHelperPath       = $script:HelperPath
                PipelineConfigDefaults = $script:ConfigDefault
            }
            if ($WhatIf) { $a['WhatIf'] = $true }
            & $script:ScriptPath @a *>&1 | Out-String
        }
        function script:Q {
            param([string]$Db, [string]$Sql)
            Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql
        }
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Initialize-AutomationDb.ps1 - source guarantees' {

    BeforeAll { $script:src = Get-Content -Raw $script:ScriptPath }

    It 'declares at least 11 CREATE TABLE IF NOT EXISTS statements' {
        ([regex]::Matches($script:src, 'CREATE TABLE IF NOT EXISTS')).Count | Should -BeGreaterOrEqual 11
    }
    It 'never uses INSERT OR REPLACE' {
        $script:src | Should -Not -Match 'INSERT OR REPLACE'
    }
    It 'never loads a dynamic .NET type or the ADO SQLite provider' {
        $script:src | Should -Not -Match 'Add-Type'
        $script:src | Should -Not -Match 'System\.Data\.SQLite'
    }
    It 'does not carry the superseded content-cache table name or the dropped assignment table' {
        $script:src | Should -Not -Match 'CacheEntry'
        $script:src | Should -Not -Match 'RoleAssignment'
    }
    It 'names the Event Log source and checkpoints the WAL' {
        $script:src | Should -Match 'DereseSoftwarePortal'
        $script:src | Should -Match 'wal_checkpoint'
    }
}

Describe 'PipelineConfig.defaults.json' {
    It 'parses as JSON and carries all 7 documented keys (07-11: the six Axonius-only keys were removed)' {
        $rows = Get-Content -Raw $script:ConfigDefault | ConvertFrom-Json
        $keys = @($rows | ForEach-Object { $_.Key })
        $keys.Count | Should -Be 7
        foreach ($k in @(
            'BESRootUrl','AKeylessTokenFile','AKeylessSecretPath','BESOperatorUser',
            'ValidityMonths','SQLDir','AlertWebhook'
        )) { $keys | Should -Contain $k }
        foreach ($k in @(
            'AxoniousExportPath','MaxExportAgeDays','SnapshotOutputDir','SnapshotUrlBase',
            'UsernameSourcePriority','ConsoleUserRelevance'
        )) { $keys | Should -Not -Contain $k }
    }
    It 'contains no secret value (AKeylessSecretPath is a path)' {
        $rows = Get-Content -Raw $script:ConfigDefault | ConvertFrom-Json
        ($rows | Where-Object { $_.Key -eq 'AKeylessSecretPath' }).Value | Should -Match '^/'
    }
}

Describe 'Initialize-AutomationDb.ps1 - runtime' -Skip:(-not $HasSqlite) {

    Context 'fresh initialisation' {
        BeforeAll {
            $script:Db = Join-Path $script:TmpRoot 'fresh.db'
            $script:Out1 = script:Run-Init -Db $script:Db
        }

        It 'produces a database file' {
            Test-Path $script:Db | Should -BeTrue
        }
        It 'creates all 11 tables' {
            $names = @((script:Q -Db $script:Db -Sql "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'") | ForEach-Object { $_.name })
            foreach ($t in $script:ExpectedTables) { $names | Should -Contain $t }
        }
        It 'seeds exactly the 13 D-21 Region values' {
            $regions = @((script:Q -Db $script:Db -Sql "SELECT GPC_Sub_Name FROM Region ORDER BY RegionID") | ForEach-Object { $_.GPC_Sub_Name })
            $regions.Count | Should -Be 13
            ($regions | Sort-Object) -join '|' | Should -Be (($script:ExpectedRegions | Sort-Object) -join '|')
        }
        It 'seeds the 3 canonical Role names' {
            $roles = @((script:Q -Db $script:Db -Sql "SELECT Role FROM Role") | ForEach-Object { $_.Role })
            foreach ($r in $script:ExpectedRoles) { $roles | Should -Contain $r }
        }
        It 'seeds every PipelineConfig key from the defaults file' {
            $want = @((Get-Content -Raw $script:ConfigDefault | ConvertFrom-Json) | ForEach-Object { $_.Key })
            $have = @((script:Q -Db $script:Db -Sql "SELECT Key FROM PipelineConfig") | ForEach-Object { $_.Key })
            foreach ($k in $want) { $have | Should -Contain $k }
        }
    }

    Context 'idempotent re-run' {
        BeforeAll {
            $script:Db2 = Join-Path $script:TmpRoot 'rerun.db'
            script:Run-Init -Db $script:Db2 | Out-Null
            $script:CountsBefore = @{}
            foreach ($t in $script:ExpectedTables) {
                $script:CountsBefore[$t] = [int](script:Q -Db $script:Db2 -Sql "SELECT COUNT(*) AS n FROM $t")[0].n
            }
            $script:Out2 = script:Run-Init -Db $script:Db2
        }

        It 'changes no row counts on the second run' {
            foreach ($t in $script:ExpectedTables) {
                $now = [int](script:Q -Db $script:Db2 -Sql "SELECT COUNT(*) AS n FROM $t")[0].n
                $now | Should -Be $script:CountsBefore[$t]
            }
        }
        It 'logs [SKIP] for tables and no [CREATE] on the second run' {
            $script:Out2 | Should -Match '\[SKIP\] Role table already exists'
            $script:Out2 | Should -Not -Match '\[CREATE\] .* table created'
        }
    }

    Context 'operator-modified PipelineConfig value survives a re-run' {
        BeforeAll {
            $script:Db3 = Join-Path $script:TmpRoot 'opedit.db'
            script:Run-Init -Db $script:Db3 | Out-Null
            Invoke-SqliteCommand -DatabasePath $script:Db3 -SQLDir $script:SqliteDir `
                -Sql "UPDATE PipelineConfig SET Value=@v WHERE Key='BESOperatorUser'" `
                -Parameters @{ v = 'svc-role-sync' } | Out-Null
            script:Run-Init -Db $script:Db3 | Out-Null
        }
        It 'keeps the operator value' {
            (script:Q -Db $script:Db3 -Sql "SELECT Value FROM PipelineConfig WHERE Key='BESOperatorUser'")[0].Value |
                Should -Be 'svc-role-sync'
        }
    }

    Context '-WhatIf' {
        It 'creates no file when the target DB path does not exist' {
            $ghost = Join-Path $script:TmpRoot 'ghostdir\ghost.db'
            script:Run-Init -Db $ghost -WhatIf | Out-Null
            Test-Path $ghost | Should -BeFalse
        }
        It 'emits a JSON run summary and makes no writes against an existing DB' {
            $db4 = Join-Path $script:TmpRoot 'whatif.db'
            script:Run-Init -Db $db4 | Out-Null
            $before = [int](script:Q -Db $db4 -Sql "SELECT COUNT(*) AS n FROM PipelineConfig")[0].n
            $out = script:Run-Init -Db $db4 -WhatIf
            $out | Should -Match 'RUN SUMMARY'
            $out | Should -Match '"whatif":\s*true'
            [int](script:Q -Db $db4 -Sql "SELECT COUNT(*) AS n FROM PipelineConfig")[0].n | Should -Be $before
        }
    }
}
