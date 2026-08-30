#Requires -Version 5.1
# Pester 5 suite for the D-18 Map migration in Dashboard_4_samples/Initialize-RoleDb.ps1
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Initialize-RoleDb.Tests.ps1 -Output Detailed -CI
#
# The migration test needs sqlite3.exe (resolved from $env:SQLDIR / probe list) and the
# tests/fixtures/phase-07/roleawareness-v2.db pre-migration fixture. When sqlite3.exe
# cannot be found the migration context is skipped (not failed).

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
        foreach ($p in $probes) { if ($p -and (Test-Path (Join-Path $p 'sqlite3.exe'))) { return $p } }
        return $null
    }

    $script:RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ScriptPath = Join-Path $script:RepoRoot 'Dashboard_4_samples\Initialize-RoleDb.ps1'
    $script:Fixture    = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\roleawareness-v2.db'
    $script:HelperPath = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:SqliteDir  = Find-SqliteDir
    $script:NewCols    = @('Source_Type','Source_Value','Region','Assigned_By')

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('roledb-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:MapCols {
            param([string]$Db)
            @((Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql "PRAGMA table_info(Map)") | ForEach-Object { $_.name })
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

Describe 'Initialize-RoleDb.ps1 - source guarantees' {
    BeforeAll { $script:src = Get-Content -Raw $script:ScriptPath }

    It 'adds the four D-18 columns inside the PRAGMA table_info(Map) migration block' {
        foreach ($c in $script:NewCols) {
            $script:src | Should -Match ([regex]::Escape("ALTER TABLE Map ADD COLUMN `$col TEXT"))
        }
        # the loop names all four
        $script:src | Should -Match "foreach \(\`$col in 'Source_Type','Source_Value','Region','Assigned_By'\)"
    }
    It 'contains exactly one INSERT OR REPLACE and it targets the Users table' {
        $iorMatches = [regex]::Matches($script:src, 'INSERT OR REPLACE')
        $iorMatches.Count | Should -Be 1
        $line = @($script:src -split "`r?`n" | Where-Object { $_ -match 'INSERT OR REPLACE' })[0]
        $line | Should -Match 'INTO Users'
    }
    It 'still keeps UNIQUE(UserID, Role) and the Locked_by_Override guard' {
        $script:src | Should -Match 'UNIQUE\(UserID, Role\)'
        $script:src | Should -Match 'Locked_by_Override = 0'
    }
}

Describe 'Initialize-RoleDb.ps1 - D-18 Map migration' -Skip:(-not $HasSqlite) {

    BeforeAll {
        $script:Db = Join-Path $script:TmpRoot 'roleawareness.db'
        Copy-Item $script:Fixture $script:Db -Force
        $script:ColsBefore   = script:MapCols -Db $script:Db
        $script:RowsBefore   = [int](script:Q -Db $script:Db -Sql "SELECT COUNT(*) AS n FROM Map")[0].n
        $script:KnownBefore  = (script:Q -Db $script:Db -Sql "SELECT Active, Locked_by_Override, Created_on FROM Map WHERE UserID='adavis' AND Role='Business Operations'")[0]
        & $script:ScriptPath -DatabasePath $script:Db -SQLDir $script:SqliteDir *>&1 | Out-Null
        $script:ColsAfter1   = script:MapCols -Db $script:Db
        & $script:ScriptPath -DatabasePath $script:Db -SQLDir $script:SqliteDir *>&1 | Out-Null
        $script:ColsAfter2   = script:MapCols -Db $script:Db
    }

    It 'the fixture starts without any of the four columns' {
        foreach ($c in $script:NewCols) { $script:ColsBefore | Should -Not -Contain $c }
    }
    It 'adds all four columns on the first run' {
        foreach ($c in $script:NewCols) { $script:ColsAfter1 | Should -Contain $c }
    }
    It 'preserves the pre-existing Map row count' {
        [int](script:Q -Db $script:Db -Sql "SELECT COUNT(*) AS n FROM Map")[0].n | Should -Be $script:RowsBefore
    }
    It 'leaves Active / Locked_by_Override / Created_on on a known row untouched' {
        $now = (script:Q -Db $script:Db -Sql "SELECT Active, Locked_by_Override, Created_on FROM Map WHERE UserID='adavis' AND Role='Business Operations'")[0]
        [int]$now.Active             | Should -Be ([int]$script:KnownBefore.Active)
        [int]$now.Locked_by_Override | Should -Be ([int]$script:KnownBefore.Locked_by_Override)
        $now.Created_on              | Should -Be $script:KnownBefore.Created_on
    }
    It 'is idempotent - a second run adds no duplicate columns' {
        ($script:ColsAfter2 | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        ($script:ColsAfter2 | Sort-Object) -join ',' | Should -Be (($script:ColsAfter1 | Sort-Object) -join ',')
    }
}
