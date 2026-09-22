#Requires -Version 5.1
# Pester 5 suite for scripts/SnapshotBuild.psm1 (Build-RegionSnapshot / New-PrefetchLine)
# and scripts/Publish-RoleSnapshot.ps1.
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Publish-RoleSnapshot.Tests.ps1 -Output Detailed -CI
#
# The Build-RegionSnapshot unit tests need no sqlite3.exe. The Publish-RoleSnapshot
# integration Context needs it (resolved from $env:SQLDIR then a probe list); when it
# cannot be found that Context is skipped, not failed.

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

    $script:SqliteDir  = Find-SqliteDir
    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:ModulePath = Join-Path $script:RepoRoot 'scripts\archive\SnapshotBuild.psm1'
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\archive\Publish-RoleSnapshot.ps1'
    $script:HelperPath = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:SchemaSql  = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\automation-db-schema.sql'
    $script:ShapePath  = Join-Path $script:RepoRoot 'tests\archive\pester\Assert-SnapshotShape.ps1'

    Import-Module $script:ModulePath -Force
    . $script:ShapePath

    $script:FixedTime = [datetime]::SpecifyKind([datetime]'2026-08-29T04:07:00', [System.DateTimeKind]::Utc)

    function script:UR {
        param([string]$UserID, [string]$Role, [string]$Type = 'AD Security Group', [string]$Value = 'grp', $Active = 1)
        [pscustomobject]@{ UserID = $UserID; Role = $Role; Source_Type = $Type; Source_Value = $Value; Active = $Active }
    }
    function script:PUB {
        param([string]$Role, $RegionID = 1, [string]$Region = 'AAG-UK', $Active = 1)
        [pscustomobject]@{ Role = $Role; RegionID = $RegionID; Region = $Region; Active = $Active }
    }
    function script:Build {
        param([object[]]$Rows, [object[]]$Publication, [string]$Region = 'AAG-UK')
        Build-RegionSnapshot -Rows ([object[]]@($Rows)) -Publication ([object[]]@($Publication)) `
            -Region $Region -RunId 'run-abc' -ValidityMonths 6 -BuiltOn $script:FixedTime
    }

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('pubsnap-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:New-TestDb {
            $db  = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.db')
            $ddl = Get-Content -Raw $script:SchemaSql
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql $ddl | Out-Null
            return $db
        }
        function script:Exec {
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P | Out-Null
        }
        function script:Query {
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }
        function script:Seed-Db {
            param([string]$Db)
            foreach ($rn in 'AAG-UK','AAG-FR') {
                script:Exec $Db "INSERT INTO Region (GPC_Sub_Name, Active) VALUES (@n, 1)" @{ n = $rn }
            }
            script:Exec $Db "INSERT INTO RolePublication (Role, RegionID, Active) VALUES ('IT Operations', 1, 1)"
            script:Exec $Db "INSERT INTO RolePublication (Role, RegionID, Active) VALUES ('Business Default', NULL, 1)"
            script:Exec $Db "INSERT INTO RolePublication (Role, RegionID, Active) VALUES ('Retired Role', 1, 0)"
            script:Exec $Db "INSERT INTO UserRole (UserID, Role, Source_Type, Source_Value, Active) VALUES ('jsmith','IT Operations','AD Security Group','BNX-M365-E3',1)"
            script:Exec $Db "INSERT INTO UserRole (UserID, Role, Source_Type, Source_Value, Active) VALUES ('adavis','IT Operations','AD Security Group','IT-Admins-UK',1)"
            script:Exec $Db "INSERT INTO UserRole (UserID, Role, Source_Type, Source_Value, Active) VALUES ('adavis','IT Operations','AD Security Group','BNX-M365-E3',1)"
            script:Exec $Db "INSERT INTO UserRole (UserID, Role, Source_Type, Source_Value, Active) VALUES ('bwong','Business Default','Mailing List','aauk-comms@corp.example.com',1)"
            script:Exec $Db "INSERT INTO UserRole (UserID, Role, Source_Type, Source_Value, Active) VALUES ('ghost','IT Operations','AD Security Group','Stale',0)"
        }
        function script:Run-Publish {
            param([string]$Db, [hashtable]$Extra = @{})
            $logDir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
            $args = @{
                DatabasePath     = $Db
                SQLDir           = $script:SqliteDir
                SqliteHelperPath = $script:HelperPath
                LogDir           = $logDir
                SkipFixletPut    = $true
            }
            foreach ($k in $Extra.Keys) { $args[$k] = $Extra[$k] }
            & $script:ScriptPath @args *>&1 | Out-Null
            return $args
        }
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item -Path $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Build-RegionSnapshot (pure)' {

    It 'includes a region-specific Active publication and honours a NULL-region publication' {
        $snap = script:Build -Rows @(
            (script:UR 'jsmith' 'IT Operations'),
            (script:UR 'bwong'  'Business Default' 'Mailing List' 'list@x')
        ) -Publication @(
            (script:PUB 'IT Operations' 1 'AAG-UK'),
            (script:PUB 'Business Default' $null $null)
        )
        @($snap.roles.role) | Should -Contain 'IT Operations'
        @($snap.roles.role) | Should -Contain 'Business Default'
    }

    It 'excludes a publication for a different region' {
        $snap = script:Build -Rows @((script:UR 'jsmith' 'IT Operations')) -Publication @(
            (script:PUB 'IT Operations' 2 'AAG-FR')
        )
        @($snap.roles).Count | Should -Be 0
    }

    It 'excludes an inactive publication' {
        $snap = script:Build -Rows @((script:UR 'jsmith' 'IT Operations')) -Publication @(
            (script:PUB 'IT Operations' 1 'AAG-UK' 0)
        )
        @($snap.roles).Count | Should -Be 0
    }

    It 'excludes an inactive UserRole row' {
        $snap = script:Build -Rows @(
            (script:UR 'jsmith' 'IT Operations' 'AD Security Group' 'g' 1),
            (script:UR 'ghost'  'IT Operations' 'AD Security Group' 'g' 0)
        ) -Publication @((script:PUB 'IT Operations'))
        $role = $snap.roles | Where-Object { $_.role -eq 'IT Operations' }
        @($role.users.id) | Should -Be @('jsmith')
    }

    It 'emits users DISTINCT and ordinally sorted by id' {
        $snap = script:Build -Rows @(
            (script:UR 'charlie' 'IT Operations'),
            (script:UR 'Alice'   'IT Operations'),
            (script:UR 'bob'     'IT Operations'),
            (script:UR 'bob'     'IT Operations' 'AD Security Group' 'other-grp')
        ) -Publication @((script:PUB 'IT Operations'))
        $ids = @(($snap.roles | Where-Object { $_.role -eq 'IT Operations' }).users.id)
        $ids | Should -Be @('Alice', 'bob', 'charlie')
    }

    It 'every users entry is an object with id, source_type and source_value (never a bare string)' {
        $snap = script:Build -Rows @((script:UR 'jsmith' 'IT Operations')) -Publication @((script:PUB 'IT Operations'))
        $u = ($snap.roles | Where-Object { $_.role -eq 'IT Operations' }).users[0]
        $u | Should -Not -BeOfType ([string])
        @($u.PSObject.Properties.Name) | Should -Contain 'id'
        @($u.PSObject.Properties.Name) | Should -Contain 'source_type'
        @($u.PSObject.Properties.Name) | Should -Contain 'source_value'
    }

    It 'collapses one role granted by two groups into ONE users entry with pipe-joined source_value / source_type' {
        $snap = script:Build -Rows @(
            (script:UR 'adavis' 'IT Operations' 'AD Security Group' 'IT-Admins-UK'),
            (script:UR 'adavis' 'IT Operations' 'Mailing List'      'BNX-M365-E3')
        ) -Publication @((script:PUB 'IT Operations'))
        $users = @(($snap.roles | Where-Object { $_.role -eq 'IT Operations' }).users)
        $users.Count | Should -Be 1
        $users[0].source_value | Should -Be 'BNX-M365-E3|IT-Admins-UK'
        $users[0].source_type  | Should -Be 'AD Security Group|Mailing List'
    }

    It 'collapses two same-type groups to a single distinct source_type' {
        $snap = script:Build -Rows @(
            (script:UR 'adavis' 'IT Operations' 'AD Security Group' 'IT-Admins-UK'),
            (script:UR 'adavis' 'IT Operations' 'AD Security Group' 'BNX-M365-E3')
        ) -Publication @((script:PUB 'IT Operations'))
        $u = @(($snap.roles | Where-Object { $_.role -eq 'IT Operations' }).users)[0]
        $u.source_value | Should -Be 'BNX-M365-E3|IT-Admins-UK'
        $u.source_type  | Should -Be 'AD Security Group'
    }

    It 'produces byte-identical JSON for two runs over identical input' {
        $rows = @((script:UR 'jsmith' 'IT Operations'), (script:UR 'adavis' 'IT Operations' 'AD Security Group' 'x'))
        $pub  = @((script:PUB 'IT Operations'))
        $j1 = (script:Build -Rows $rows -Publication $pub) | ConvertTo-Json -Depth 6 -Compress
        $j2 = (script:Build -Rows $rows -Publication $pub) | ConvertTo-Json -Depth 6 -Compress
        $j1 | Should -Be $j2
    }

    It 'returns an empty roles array (not null) when nothing is published' {
        $snap = script:Build -Rows @((script:UR 'jsmith' 'IT Operations')) -Publication @()
        @($snap.roles).Count | Should -Be 0
        @($snap.PSObject.Properties.Name) | Should -Contain 'roles'
        ($snap | ConvertTo-Json -Depth 6 -Compress) | Should -Match '"roles":\s*\[\s*\]'
    }

    It 'passes Assert-RoleRefSnapshotShape' {
        $snap = script:Build -Rows @(
            (script:UR 'jsmith' 'IT Operations'),
            (script:UR 'adavis' 'IT Operations' 'AD Security Group' 'x'),
            (script:UR 'bwong'  'Business Default' 'Mailing List' 'list@x')
        ) -Publication @(
            (script:PUB 'IT Operations' 1 'AAG-UK'),
            (script:PUB 'Business Default' $null $null)
        )
        Assert-RoleRefSnapshotShape -Snapshot $snap -ExpectedRegion 'AAG-UK' | Should -BeTrue
    }
}

Describe 'New-PrefetchLine (pure)' {
    It 'renders the rewritePrefetchUrls() shape' {
        $line = New-PrefetchLine -FileName 'roleref-aag-uk-latest.json' -Sha1 'ABCDEF0123' -Size 1234 `
            -UrlBase 'http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/'
        $line | Should -Be 'prefetch roleref-aag-uk-latest.json sha1:abcdef0123 size:1234 http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/roleref-aag-uk-latest.json'
    }
    It 'matches the extractPrefetchLines() regex' {
        $line = New-PrefetchLine -FileName 'roleref-aag-uk-latest.json' -Sha1 'deadbeef' -Size 42 -UrlBase 'http://h/roleref'
        ($line -match '^(?:prefetch\s+)?(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:(\d+)\s+(\S+)') | Should -BeTrue
        $Matches[2] | Should -Be 'deadbeef'
        $Matches[3] | Should -Be '42'
    }
}

Describe 'Publish-RoleSnapshot.ps1 (integration)' -Skip:(-not $script:HasSqlite) {

    It 'writes the dated file, the latest pointer and a matching .sha1 manifest' {
        $db = script:New-TestDb
        script:Seed-Db $db
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        script:Run-Publish -Db $db -Extra @{ OutputDir = $out } | Out-Null

        $latest = Join-Path $out 'roleref-aag-uk-latest.json'
        $dated  = Get-ChildItem $out -Filter 'roleref-aag-uk-2*.json' | Select-Object -First 1
        $sha    = Join-Path $out 'roleref-aag-uk-latest.json.sha1'
        Test-Path $latest | Should -BeTrue
        $dated  | Should -Not -BeNullOrEmpty
        Test-Path $sha | Should -BeTrue
    }

    It 'the .sha1 file content equals Get-FileHash SHA1 of the latest json, lower-cased' {
        $db = script:New-TestDb
        script:Seed-Db $db
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        script:Run-Publish -Db $db -Extra @{ OutputDir = $out } | Out-Null

        $latest = Join-Path $out 'roleref-aag-uk-latest.json'
        $expected = (Get-FileHash -Algorithm SHA1 -Path $latest).Hash.ToLowerInvariant()
        $shaContent = (Get-Content -Raw (Join-Path $out 'roleref-aag-uk-latest.json.sha1'))
        $shaContent | Should -Be ("$expected  roleref-aag-uk-latest.json")
    }

    It 'the recorded Snapshot.Size_Bytes equals the on-disk length of the latest file' {
        $db = script:New-TestDb
        script:Seed-Db $db
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        script:Run-Publish -Db $db -Extra @{ OutputDir = $out; Region = 'AAG-UK' } | Out-Null

        $onDisk = (Get-Item (Join-Path $out 'roleref-aag-uk-latest.json')).Length
        $row = script:Query $db "SELECT Size_Bytes AS n FROM Snapshot WHERE Region = 'AAG-UK' ORDER BY SnapshotID DESC LIMIT 1"
        [int]$row[0].n | Should -Be $onDisk
    }

    It 'the built snapshot passes Assert-RoleRefSnapshotShape and contains the pipe-joined adavis entry' {
        $db = script:New-TestDb
        script:Seed-Db $db
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        script:Run-Publish -Db $db -Extra @{ OutputDir = $out; Region = 'AAG-UK' } | Out-Null

        $snap = Get-Content -Raw (Join-Path $out 'roleref-aag-uk-latest.json') | ConvertFrom-Json
        Assert-RoleRefSnapshotShape -Snapshot $snap -ExpectedRegion 'AAG-UK' | Should -BeTrue
        $it = $snap.roles | Where-Object { $_.role -eq 'IT Operations' }
        $adavis = $it.users | Where-Object { $_.id -eq 'adavis' }
        $adavis.source_value | Should -Be 'BNX-M365-E3|IT-Admins-UK'
    }

    It 'an unknown -Region aborts and writes no file' {
        $db = script:New-TestDb
        script:Seed-Db $db
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        { & $script:ScriptPath -DatabasePath $db -SQLDir $script:SqliteDir -SqliteHelperPath $script:HelperPath `
            -LogDir (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) -SkipFixletPut `
            -OutputDir $out -Region 'NOPE-REGION' -ErrorAction Stop } | Should -Throw
        @(Get-ChildItem $out -Filter '*.json' -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It '-WhatIf writes no file under the output dir and no Snapshot row' {
        $db = script:New-TestDb
        script:Seed-Db $db
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $out -Force | Out-Null
        & $script:ScriptPath -DatabasePath $db -SQLDir $script:SqliteDir -SqliteHelperPath $script:HelperPath `
            -LogDir (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) -SkipFixletPut `
            -OutputDir $out -WhatIf *>&1 | Out-Null

        @(Get-ChildItem $out -Recurse -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        $rows = script:Query $db "SELECT COUNT(*) AS n FROM Snapshot"
        [int]$rows[0].n | Should -Be 0
    }
}
