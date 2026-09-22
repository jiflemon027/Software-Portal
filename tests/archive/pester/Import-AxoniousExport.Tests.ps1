#Requires -Version 5.1
# Pester 5 suite for scripts/Import-AxoniousExport.ps1
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Import-AxoniousExport.Tests.ps1 -ExcludeTagFilter Slow -Output Detailed -CI
#
# DB-backed contexts need sqlite3.exe (resolved from $env:SQLDIR then a probe list - see
# tests/pester/README.md). When it cannot be found those contexts are skipped, not failed,
# so the suite still exits 0 on a host without it. Tests that touch the full 400 MB export
# are tagged Slow and excluded from CI.

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
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:HasSlow = Test-Path (Join-Path $repo 'SampleAxonious\axonious-users_anond.csv')
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

    $script:SqliteDir  = Find-SqliteDir
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\archive\Import-AxoniousExport.ps1'
    $script:HelperPath = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:SchemaSql  = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\automation-db-schema.sql'
    $script:SampleCsv  = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\axonious-sample-50.csv'
    $script:EdgeCsv    = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\axonious-multivalue-edge.csv'
    $script:RuleSeed   = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\grouprolemap-seed.json'
    $script:SlowFile   = Join-Path $script:RepoRoot 'SampleAxonious\axonious-users_anond.csv'

    # The Axonius export's exact 47-column header (order matters for round-tripped test CSVs).
    $script:AxHeaders = @(
        'Aggregated: Adapter Connections','Aggregated: Asset Unique ID','Aggregated: Last Seen (UTC)',
        'Aggregated: Associated Devices: Device Labels','Aggregated: Associated Devices: Device Name',
        'Aggregated: Associated Devices: Device Serial','Aggregated: Associated Devices: Device OS Type',
        'Aggregated: Associated Devices: Device Model','Aggregated: Associated Devices: Device Model Family',
        'Aggregated: Associated Devices: Device OS Version','Aggregated: Associated Devices: Device OS Distribution',
        'Aggregated: Associated Devices: Device OS Edition','Aggregated: Associated Devices: Device OS End Of Life',
        'Aggregated: Associated Devices: Device Unique ID','Aggregated: Associated Devices: Device Preferred MAC Address',
        'Aggregated: Associated Devices: Device Associated SaaS Applications Names',
        'Aggregated: Last Fetched From Connection Label','Aggregated: Assigned Groups: Email',
        'Aggregated: Assigned Groups: Remote Id','Aggregated: Assigned Groups: Name',
        'Aggregated: Assigned Groups: Display Name','Aggregated: Assigned Groups: Is Excessive',
        'Aggregated: Assigned Groups: Is Admin','Aggregated: Assigned Groups: Has Administrative Permissions',
        'Aggregated: Assigned Groups: Group Type','Aggregated: Assigned Groups: SID',
        'Aggregated: Assigned Groups: Adapter Connection Id','Aggregated: Assigned Groups: Adapter Source Application',
        'Aggregated: Assigned Groups: Justifications','Aggregated: Assigned Groups: Is Justified',
        'Aggregated: Assigned Groups: Declared Administrative Permissions','Aggregated: Assigned Groups: Declared Super Admin',
        'Aggregated: Mail','Aggregated: User Name','Aggregated: Display Name','Aggregated: Domain',
        'Aggregated: Last Logon Date (UTC)','Aggregated: User Remote Id','Aggregated: User Title',
        'Aggregated: User Department','Aggregated: User Company','Azure Ad: extensionAttribute5',
        'Azure Ad: extensionAttribute6','Azure Ad: extensionAttribute7','Azure Ad: AD sAMAccountName',
        'Azure Ad: AD User Principal Name','Azure Ad: Last Logon Date (UTC)'
    )

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('aximport-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:New-TestDb {
            param([string]$Name = ([guid]::NewGuid().ToString('N') + '.db'))
            $db  = Join-Path $script:TmpRoot $Name
            $ddl = Get-Content -Raw $script:SchemaSql
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql $ddl | Out-Null
            return $db
        }
        function script:Q {
            # Flatten Sqlite-Helper's (return ,$rows) wrapper so multi-row results count correctly.
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }
        function script:Seed-Rules {
            param([string]$Db, [object[]]$Rules)
            foreach ($r in $Rules) {
                Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir `
                    -Sql "INSERT INTO GroupRoleMap (Pattern, Match_On, Role, Priority, Active) VALUES (@p,@m,@r,@pr,@a)" `
                    -Parameters @{ p = $r.Pattern; m = $r.Match_On; r = $r.Role; pr = $r.Priority; a = $r.Active } | Out-Null
            }
        }
        function script:New-AxCsv {
            # Rows: array of hashtables keyed by real Axonius header names; unspecified columns blank.
            param([string]$Path, [hashtable[]]$Rows)
            $objs = foreach ($rw in $Rows) {
                $o = [ordered]@{}
                foreach ($h in $script:AxHeaders) { $o[$h] = '' }
                foreach ($k in $rw.Keys) { $o[$k] = $rw[$k] }
                [pscustomobject]$o
            }
            $objs | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        }
        function script:Run-Import {
            param([string]$Db, [string]$Csv, [string]$LogDir, [switch]$WhatIf, [hashtable]$Extra = @{})
            if (-not $LogDir) { $LogDir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N')) }
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
            $a = @{
                DatabasePath     = $Db
                SQLDir           = $script:SqliteDir
                SqliteHelperPath = $script:HelperPath
                LogDir           = $LogDir
            }
            if ($Csv) { $a['ExportPath'] = $Csv }
            foreach ($k in $Extra.Keys) { $a[$k] = $Extra[$k] }
            if ($WhatIf) { $a['WhatIf'] = $true }
            $outFile = Join-Path $LogDir '_run.out'
            $threw = $false
            try {
                & $script:ScriptPath @a *>&1 | Tee-Object -FilePath $outFile | Out-Null
            } catch {
                $threw = $true
                ($_ | Out-String) | Add-Content -Path $outFile
            }
            $out = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { '' }
            return [pscustomobject]@{ Output = $out; LogDir = $LogDir; Threw = $threw }
        }
        function script:Get-JsonLog {
            param([string]$LogDir)
            $f = Get-ChildItem -Path $LogDir -Filter 'Import-AxoniousExport-*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $f) { return $null }
            return (Get-Content -Raw $f.FullName | ConvertFrom-Json)
        }
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Import-AxoniousExport.ps1 - source guarantees' {

    BeforeAll {
        $script:src  = Get-Content -Raw $script:ScriptPath
        $script:code = (($script:src -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $m = [regex]::Match($script:src, '# >>> INGEST LOOP START(?<body>.*?)# <<< INGEST LOOP END', 'Singleline')
        $script:loopBody = if ($m.Success) { $m.Groups['body'].Value } else { '' }
    }

    It 'streams with Import-Csv and ForEach-Object' {
        $script:code | Should -Match 'Import-Csv'
        $script:code | Should -Match 'ForEach-Object'
    }
    It 'never assigns the Import-Csv pipeline to a variable' {
        [regex]::Matches($script:code, '\$\w+\s*=\s*Import-Csv').Count | Should -Be 0
    }
    It 'never uses a CLM-blocked reader or Add-Type' {
        [regex]::Matches($script:code, 'System\.IO\.StreamReader|System\.IO\.File\]::OpenText|Add-Type').Count | Should -Be 0
    }
    It 'has no Select-Object / Where-Object / Sort-Object / Group-Object inside the ingest loop' {
        $script:loopBody | Should -Not -BeNullOrEmpty
        $script:loopBody | Should -Not -Match 'Select-Object'
        $script:loopBody | Should -Not -Match 'Where-Object'
        $script:loopBody | Should -Not -Match 'Sort-Object'
        $script:loopBody | Should -Not -Match 'Group-Object'
    }
    It 'never uses INSERT OR REPLACE' {
        $script:src | Should -Not -Match 'INSERT OR REPLACE'
    }
    It 'routes writes through a single -WhatIf gate' {
        $script:src | Should -Match 'function Invoke-DbWrite'
        $script:src | Should -Match '\$WhatIfPreference'
    }
    It 'opens a SyncRun row of Type Ingest' {
        $script:src | Should -Match "INSERT INTO SyncRun .*'Ingest'"
    }
    It 'names the stale-export and failure Event IDs' {
        $script:src | Should -Match '8010'
        $script:src | Should -Match '8013'
    }
    It 'names all four 8000-range Event IDs (8010 8011 8012 8013)' {
        foreach ($id in '8010', '8011', '8012', '8013') { $script:src | Should -Match $id }
    }
    It 'never deletes from UserRole or RefUser (age-out marks, never deletes)' {
        [regex]::Matches($script:code, 'DELETE FROM UserRole|DELETE FROM RefUser').Count | Should -Be 0
    }
    It 'co-locates the Active=0 sweep UPDATE with SELECT changes() in one statement' {
        $script:src | Should -Match "(?s)UPDATE UserRole SET Active = 0.*?SELECT changes\(\)"
    }
}

Describe 'Import-AxoniousExport.ps1 - runtime' -Skip:(-not $HasSqlite) {

    Context 'streaming the real 44-record fixture (Pitfall 1 assertion)' {
        BeforeAll {
            $script:Db1  = script:New-TestDb
            $script:Res1 = script:Run-Import -Db $script:Db1 -Csv $script:SampleCsv
            $script:Json1 = script:Get-JsonLog -LogDir $script:Res1.LogDir
        }

        It 'sets Rows_In to the Import-Csv record count, not the physical line count' {
            $recordCount = @(Import-Csv -Path $script:SampleCsv).Count
            $physical    = (Get-Content -Path $script:SampleCsv).Count
            $recordCount | Should -Be 44
            $script:Json1.Rows_In | Should -Be $recordCount
            $script:Json1.Rows_In | Should -Not -Be $physical
        }
        It 'opens exactly one Ingest SyncRun row and finalises it' {
            $rows = @(script:Q -Db $script:Db1 -Sql "SELECT Status, Ended_on, Rows_In FROM SyncRun WHERE Type='Ingest'")
            $rows.Count | Should -Be 1
            $rows[0].Status   | Should -BeIn @('success', 'partial')
            $rows[0].Ended_on | Should -Not -BeNullOrEmpty
            [int]$rows[0].Rows_In | Should -Be 44
        }
        It 'writes a JSON log with WhatIf false and Status success' {
            $script:Json1.WhatIf | Should -BeFalse
            $script:Json1.Status | Should -Be 'success'
        }
        It 'did not throw' {
            $script:Res1.Threw | Should -BeFalse
        }
    }

    Context 'a fixture missing a required column' {
        It 'aborts with error 6700 and names the missing column' {
            $bad = Join-Path $script:TmpRoot 'missing-col.csv'
            $hdr = (($script:AxHeaders | Where-Object { $_ -ne 'Aggregated: Domain' }) -join ',')
            Set-Content -Path $bad -Value $hdr -Encoding UTF8
            Add-Content -Path $bad -Value ('x' + (',' * ($script:AxHeaders.Count - 2))) -Encoding UTF8
            $db  = script:New-TestDb
            $res = script:Run-Import -Db $db -Csv $bad
            $res.Threw          | Should -BeTrue
            $res.Output         | Should -Match '6700'
            $res.Output         | Should -Match 'Aggregated: Domain'
        }
    }

    Context 'a stale export (older than MaxExportAgeDays)' {
        It 'warns and still completes with Status success' {
            $stale = Join-Path $script:TmpRoot 'stale.csv'
            Copy-Item $script:SampleCsv $stale -Force
            (Get-Item $stale).LastWriteTime = (Get-Date).AddDays(-10)
            $db  = script:New-TestDb
            $res = script:Run-Import -Db $db -Csv $stale
            $json = script:Get-JsonLog -LogDir $res.LogDir
            $json.StaleWarning | Should -BeTrue
            $json.Status       | Should -Be 'success'
            $res.Output        | Should -Match '\[WARN\].*days old'
        }
    }

    Context '-WhatIf' {
        It 'creates no SyncRun row, no RefUser rows, and still writes the JSON log' {
            $db  = script:New-TestDb
            $res = script:Run-Import -Db $db -Csv $script:SampleCsv -WhatIf
            [int](script:Q -Db $db -Sql "SELECT COUNT(*) AS n FROM SyncRun")[0].n  | Should -Be 0
            [int](script:Q -Db $db -Sql "SELECT COUNT(*) AS n FROM RefUser")[0].n  | Should -Be 0
            $json = script:Get-JsonLog -LogDir $res.LogDir
            $json.WhatIf | Should -BeTrue
        }
    }

    Context 'GroupRoleMap resolution + batched upsert (Task 3)' {
        BeforeAll {
            $script:Db3 = script:New-TestDb
            script:Seed-Rules -Db $script:Db3 -Rules @(
                @{ Pattern = 'BNX-M365-E3';       Match_On = 'cn';      Role = 'IT Operations';   Priority = 10;  Active = 1 }
                @{ Pattern = 'All Tenant Members'; Match_On = 'display'; Role = 'Business Default'; Priority = 100; Active = 1 }
            )
            $script:Res3  = script:Run-Import -Db $script:Db3 -Csv $script:SampleCsv
            $script:Json3 = script:Get-JsonLog -LogDir $script:Res3.LogDir
        }

        It 'writes RefUser rows for every distinct user' {
            [int](script:Q -Db $script:Db3 -Sql "SELECT COUNT(*) AS n FROM RefUser")[0].n | Should -Be 44
        }
        It 'writes UserRole rows and records Entitlements / Roles_Seen on the SyncRun' {
            [int](script:Q -Db $script:Db3 -Sql "SELECT COUNT(*) AS n FROM UserRole")[0].n | Should -BeGreaterThan 0
            $sr = (script:Q -Db $script:Db3 -Sql "SELECT Entitlements, Roles_Seen FROM SyncRun WHERE Type='Ingest'")[0]
            [int]$sr.Entitlements | Should -BeGreaterThan 0
            [int]$sr.Roles_Seen   | Should -Be 2
        }
        It 'stamps every UserRole row with Source_Type, Source_Value and Last_RunID' {
            $bad = [int](script:Q -Db $script:Db3 -Sql "SELECT COUNT(*) AS n FROM UserRole WHERE Source_Type IS NULL OR Source_Value IS NULL OR Last_RunID IS NULL")[0].n
            $bad | Should -Be 0
        }
    }

    Context 'two GroupRoleMap rules mapping one group to two roles' {
        It 'produces two UserRole rows with distinct Matched_Rule for the same user+group' {
            $db = script:New-TestDb
            script:Seed-Rules -Db $db -Rules @(
                @{ Pattern = 'TESTGRP'; Match_On = 'cn'; Role = 'Role A'; Priority = 10; Active = 1 }
                @{ Pattern = 'TESTGRP'; Match_On = 'cn'; Role = 'Role B'; Priority = 20; Active = 1 }
                @{ Pattern = 'GONE';    Match_On = 'cn'; Role = 'Role Z'; Priority = 30; Active = 0 }
            )
            $csv = Join-Path $script:TmpRoot 'tworole.csv'
            script:New-AxCsv -Path $csv -Rows @(
                @{ 'Azure Ad: AD sAMAccountName' = 'twou'; 'Azure Ad: AD User Principal Name' = 'twou@x.com'
                   'Aggregated: User Name' = 'twou'
                   'Aggregated: Assigned Groups: Name' = "TESTGRP`nGONE"
                   'Aggregated: Assigned Groups: Group Type' = "AD Security Group`nAD Security Group" }
            )
            $null = script:Run-Import -Db $db -Csv $csv
            $rows = @(script:Q -Db $db -Sql "SELECT Role, Matched_Rule FROM UserRole WHERE UserID='twou' ORDER BY Role")
            $rows.Count | Should -Be 2
            ($rows.Role -join ',')          | Should -Be 'Role A,Role B'
            ($rows.Matched_Rule | Select-Object -Unique).Count | Should -Be 2
            # the Active=0 rule never fires
            @(script:Q -Db $db -Sql "SELECT 1 FROM UserRole WHERE Role='Role Z'").Count | Should -Be 0
        }
    }

    Context 'SQL-injection payload in a group value (T-07-01-01)' {
        It 'stores the literal payload in Source_Value and never executes it' {
            $payload = "EVIL'); DROP TABLE UserRole;--"
            $db = script:New-TestDb
            script:Seed-Rules -Db $db -Rules @(@{ Pattern = $payload; Match_On = 'cn'; Role = 'IT Operations'; Priority = 1; Active = 1 })
            $csv = Join-Path $script:TmpRoot 'inject.csv'
            script:New-AxCsv -Path $csv -Rows @(
                @{ 'Azure Ad: AD sAMAccountName' = 'evil1'; 'Azure Ad: AD User Principal Name' = 'evil1@x.com'
                   'Aggregated: User Name' = 'evil1'
                   'Aggregated: Assigned Groups: Name' = $payload
                   'Aggregated: Assigned Groups: Group Type' = 'AD Security Group' }
            )
            $res = script:Run-Import -Db $db -Csv $csv
            $res.Threw | Should -BeFalse
            @(script:Q -Db $db -Sql "SELECT name FROM sqlite_master WHERE type='table' AND name='UserRole'").Count | Should -Be 1
            $rows = @(script:Q -Db $db -Sql "SELECT Source_Value FROM UserRole WHERE UserID='evil1'")
            $rows.Count            | Should -Be 1
            $rows[0].Source_Value  | Should -Be $payload
        }
    }

    Context 'a second run preserves First_Seen and never uses INSERT OR REPLACE' {
        It 'keeps the original First_Seen on a pre-existing RefUser / UserRole row' {
            $db = script:New-TestDb
            script:Seed-Rules -Db $db -Rules @(@{ Pattern = 'KEEP'; Match_On = 'cn'; Role = 'IT Operations'; Priority = 1; Active = 1 })
            $csv = Join-Path $script:TmpRoot 'firstseen.csv'
            script:New-AxCsv -Path $csv -Rows @(
                @{ 'Azure Ad: AD sAMAccountName' = 'keepu'; 'Azure Ad: AD User Principal Name' = 'keepu@x.com'
                   'Aggregated: User Name' = 'keepu'
                   'Aggregated: Assigned Groups: Name' = 'KEEP'
                   'Aggregated: Assigned Groups: Group Type' = 'AD Security Group' }
            )
            $null = script:Run-Import -Db $db -Csv $csv
            $ruFirst = (script:Q -Db $db -Sql "SELECT First_Seen FROM RefUser WHERE UserID='keepu'")[0].First_Seen
            $urFirst = (script:Q -Db $db -Sql "SELECT First_Seen FROM UserRole WHERE UserID='keepu'")[0].First_Seen
            Start-Sleep -Seconds 1
            $null = script:Run-Import -Db $db -Csv $csv
            (script:Q -Db $db -Sql "SELECT First_Seen FROM RefUser WHERE UserID='keepu'")[0].First_Seen | Should -Be $ruFirst
            (script:Q -Db $db -Sql "SELECT First_Seen FROM UserRole WHERE UserID='keepu'")[0].First_Seen | Should -Be $urFirst
            (script:Q -Db $db -Sql "SELECT COUNT(*) AS n FROM UserRole WHERE UserID='keepu'")[0].n | Should -Be 1
        }
    }

    Context 'age-out sweep (D-09) - mark, never delete' {
        BeforeAll {
            $script:AoDb = script:New-TestDb
            script:Seed-Rules -Db $script:AoDb -Rules @(@{ Pattern = 'KEEP'; Match_On = 'cn'; Role = 'IT Operations'; Priority = 1; Active = 1 })
            function script:AoCsv { param([string[]]$Users, [string]$Name)
                $rows = foreach ($u in $Users) {
                    @{ 'Azure Ad: AD sAMAccountName' = $u; 'Azure Ad: AD User Principal Name' = "$u@x.com"
                       'Aggregated: User Name' = $u
                       'Aggregated: Assigned Groups: Name' = 'KEEP'
                       'Aggregated: Assigned Groups: Group Type' = 'AD Security Group' }
                }
                $p = Join-Path $script:TmpRoot $Name
                script:New-AxCsv -Path $p -Rows $rows
                return $p
            }
            $null = script:Run-Import -Db $script:AoDb -Csv (script:AoCsv -Users 'alice','bob','carol' -Name 'ao1.csv')
            $script:AoRes2 = script:Run-Import -Db $script:AoDb -Csv (script:AoCsv -Users 'alice','bob' -Name 'ao2.csv')
        }

        It 'marks the departed user Active=0 but keeps the row (count unchanged)' {
            [int](script:Q -Db $script:AoDb -Sql "SELECT COUNT(*) AS n FROM UserRole")[0].n | Should -Be 3
            [int](script:Q -Db $script:AoDb -Sql "SELECT Active FROM UserRole WHERE UserID='carol'")[0].Active | Should -Be 0
        }
        It 'leaves the still-present users Active=1' {
            [int](script:Q -Db $script:AoDb -Sql "SELECT COUNT(*) AS n FROM UserRole WHERE Active=1")[0].n | Should -Be 2
        }
        It 'records Aged_Out on the JSON log and Sweep_Applied true' {
            $j = script:Get-JsonLog -LogDir $script:AoRes2.LogDir
            [int]$j.Aged_Out | Should -Be 1
            $j.Sweep_Applied | Should -BeTrue
        }
        It 're-activates a user who returns in a later run' {
            $null = script:Run-Import -Db $script:AoDb -Csv (script:AoCsv -Users 'alice','bob','carol' -Name 'ao3.csv')
            [int](script:Q -Db $script:AoDb -Sql "SELECT Active FROM UserRole WHERE UserID='carol'")[0].Active | Should -Be 1
            [int](script:Q -Db $script:AoDb -Sql "SELECT COUNT(*) AS n FROM UserRole")[0].n | Should -Be 3
        }
    }

    Context 'MaxAgeOutFraction brake - a bad export cannot mass-revoke' {
        It 'leaves every row Active=1 and sets SyncRun.Status = partial when > half would age out' {
            $db = script:New-TestDb
            script:Seed-Rules -Db $db -Rules @(@{ Pattern = 'KEEP'; Match_On = 'cn'; Role = 'IT Operations'; Priority = 1; Active = 1 })
            $r1 = foreach ($u in 'u1', 'u2', 'u3') {
                @{ 'Azure Ad: AD sAMAccountName' = $u; 'Azure Ad: AD User Principal Name' = "$u@x.com"
                   'Aggregated: User Name' = $u; 'Aggregated: Assigned Groups: Name' = 'KEEP'
                   'Aggregated: Assigned Groups: Group Type' = 'AD Security Group' }
            }
            $c1 = Join-Path $script:TmpRoot 'brake1.csv'; script:New-AxCsv -Path $c1 -Rows $r1
            $null = script:Run-Import -Db $db -Csv $c1 -Extra @{ RunId = 'brake-run-1' }
            # second run: one unrelated user, no KEEP membership -> all 3 would age out (100% > 50%)
            $c2 = Join-Path $script:TmpRoot 'brake2.csv'
            script:New-AxCsv -Path $c2 -Rows @(
                @{ 'Azure Ad: AD sAMAccountName' = 'stranger'; 'Azure Ad: AD User Principal Name' = 'stranger@x.com'
                   'Aggregated: User Name' = 'stranger'; 'Aggregated: Assigned Groups: Name' = 'OTHER'
                   'Aggregated: Assigned Groups: Group Type' = 'AD Security Group' }
            )
            $res = script:Run-Import -Db $db -Csv $c2 -Extra @{ RunId = 'brake-run-2' }
            [int](script:Q -Db $db -Sql "SELECT COUNT(*) AS n FROM UserRole WHERE Active=1")[0].n | Should -Be 3
            (script:Q -Db $db -Sql "SELECT Status FROM SyncRun WHERE RunID='brake-run-2'")[0].Status | Should -Be 'partial'
            $j = script:Get-JsonLog -LogDir $res.LogDir
            $j.Sweep_Applied | Should -BeFalse
            [int]$j.Aged_Out | Should -Be 0
            $res.Output | Should -Match '\[ABORT-SWEEP\]'
        }
    }

    Context 'SyncRun + JSON log audit trail (NFR-NEW)' {
        BeforeAll {
            $script:AuDb = script:New-TestDb
            script:Seed-Rules -Db $script:AuDb -Rules @(
                @{ Pattern = 'BNX-M365-E3'; Match_On = 'cn'; Role = 'IT Operations'; Priority = 1; Active = 1 }
            )
            $script:AuRes = script:Run-Import -Db $script:AuDb -Csv $script:SampleCsv
            $script:AuJsonPath = (Get-ChildItem -Path $script:AuRes.LogDir -Filter 'Import-AxoniousExport-*.json' | Select-Object -First 1).FullName
        }

        It 'writes exactly one SyncRun row for the run with a populated Ended_on and Summary' {
            $rows = @(script:Q -Db $script:AuDb -Sql "SELECT Ended_on, Summary FROM SyncRun WHERE Type='Ingest'")
            $rows.Count      | Should -Be 1
            $rows[0].Ended_on | Should -Not -BeNullOrEmpty
            $rows[0].Summary  | Should -Not -BeNullOrEmpty
        }
        It 'the JSON log contains none of the fixture usernames (counts only)' {
            $raw = Get-Content -Raw $script:AuJsonPath
            $sams = @(Import-Csv -Path $script:SampleCsv |
                    ForEach-Object { $_.'Azure Ad: AD sAMAccountName' } |
                    Where-Object { $_ -and $_.Length -ge 4 })
            $sams.Count | Should -BeGreaterThan 0
            foreach ($s in $sams) { $raw | Should -Not -Match ([regex]::Escape($s)) }
        }
    }

    Context '-WhatIf performs no sweep and no writes' {
        It 'writes the JSON log with Sweep_Applied false and Aged_Out 0, and no SyncRun row' {
            $db = script:New-TestDb
            script:Seed-Rules -Db $db -Rules @(@{ Pattern = 'BNX-M365-E3'; Match_On = 'cn'; Role = 'IT Operations'; Priority = 1; Active = 1 })
            $res = script:Run-Import -Db $db -Csv $script:SampleCsv -WhatIf
            [int](script:Q -Db $db -Sql "SELECT COUNT(*) AS n FROM SyncRun")[0].n  | Should -Be 0
            [int](script:Q -Db $db -Sql "SELECT COUNT(*) AS n FROM UserRole")[0].n | Should -Be 0
            $j = script:Get-JsonLog -LogDir $res.LogDir
            $j.WhatIf        | Should -BeTrue
            $j.Sweep_Applied | Should -BeFalse
            [int]$j.Aged_Out | Should -Be 0
        }
    }

    Context '-ReportGroupFrequency' {
        It 'writes a CSV of Source_Value / Source_Type / UserCount ranked by the most common group' {
            $db = script:New-TestDb
            script:Seed-Rules -Db $db -Rules @(
                @{ Pattern = 'POPULAR'; Match_On = 'cn'; Role = 'IT Operations';   Priority = 1; Active = 1 }
                @{ Pattern = 'RARE';    Match_On = 'cn'; Role = 'Business Default'; Priority = 2; Active = 1 }
            )
            $rows = @()
            foreach ($u in 'a', 'b', 'c') {
                $rows += @{ 'Azure Ad: AD sAMAccountName' = $u; 'Azure Ad: AD User Principal Name' = "$u@x.com"
                           'Aggregated: User Name' = $u; 'Aggregated: Assigned Groups: Name' = 'POPULAR'
                           'Aggregated: Assigned Groups: Group Type' = 'AD Security Group' }
            }
            $rows += @{ 'Azure Ad: AD sAMAccountName' = 'z'; 'Azure Ad: AD User Principal Name' = 'z@x.com'
                       'Aggregated: User Name' = 'z'; 'Aggregated: Assigned Groups: Name' = 'RARE'
                       'Aggregated: Assigned Groups: Group Type' = 'AD Security Group' }
            $csv = Join-Path $script:TmpRoot 'freq.csv'
            script:New-AxCsv -Path $csv -Rows $rows
            $null = script:Run-Import -Db $db -Csv $csv

            $logDir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
            $res = script:Run-Import -Db $db -Csv $null -LogDir $logDir -Extra @{ ReportGroupFrequency = $true }
            $repFile = Get-ChildItem -Path $logDir -Filter 'group-frequency-*.csv' | Select-Object -First 1
            $repFile | Should -Not -BeNullOrEmpty
            $rep = @(Import-Csv -Path $repFile.FullName)
            ($rep[0].PSObject.Properties.Name -join ',') | Should -Be 'Source_Value,Source_Type,UserCount'
            $rep[0].Source_Value | Should -Be 'POPULAR'
            [int]$rep[0].UserCount | Should -Be 3
        }
    }

    Context 'A7 runtime profile against the full anonymised export' {
        It 'ingests the full export and records a wall-clock time' -Tag 'Slow' -Skip:(-not $HasSlow) {
            $db = script:New-TestDb
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $res = script:Run-Import -Db $db -Csv $script:SlowFile
            $sw.Stop()
            $json = script:Get-JsonLog -LogDir $res.LogDir
            $json.Rows_In | Should -BeGreaterThan 0
            Write-Host "A7 profile: $([math]::Round($sw.Elapsed.TotalSeconds,1))s for $($json.Rows_In) rows"
        }
    }
}
