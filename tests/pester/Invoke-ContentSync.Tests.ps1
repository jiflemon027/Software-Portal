#Requires -Version 5.1
# Pester 5 suite for scripts/ContentSyncCore.psm1 and scripts/Invoke-ContentSync.ps1 (07-03).
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Invoke-ContentSync.Tests.ps1 -Output Detailed -CI
#
# The pure-function Describe needs no sqlite3.exe. The scan/diff/copy Describe builds a
# throwaway AutomationState.db from tests/fixtures/phase-07/automation-db-schema.sql and
# mocks Invoke-RestMethod; when sqlite3.exe cannot be found that Describe is skipped.

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
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts\Invoke-ContentSync.ps1'
    $script:HelperPath = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:SchemaSql  = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\automation-db-schema.sql'

    Import-Module $script:ModulePath -Force

    $script:DummyCred = [pscredential]::new('svc', (ConvertTo-SecureString 'pw' -AsPlainText -Force))
    $script:US        = [string][char]0x1F   # the scan tuple delimiter

    function script:Tuple {
        param([string]$Id, [string]$Name, [string]$Site, [string]$Type = 'fixlet', [string]$Container = 'external')
        return ($Id, $Name, $Site, $Type, $Container) -join $script:US
    }

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('contentsync-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:New-TestDb {
            $db  = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.db')
            $ddl = Get-Content -Raw $script:SchemaSql
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql $ddl | Out-Null
            return $db
        }
        function script:Q {
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }
        function script:Count {
            param([string]$Db, [string]$Table, [string]$Where = '1=1')
            [int](script:Q $Db "SELECT COUNT(*) AS n FROM $Table WHERE $Where")[0].n
        }

        # dot-source the script under test: runs the param block with defaults, defines
        # Start-ContentSync / Invoke-CopyEngine / ..., and (guard) does NOT execute main.
        . $script:ScriptPath

        $script:SrcSite    = 'BigFix Software Installer Library for Windows'
        $script:PortalSite = 'Dereso Software Portal'

        function script:Run-Sync {
            param([string]$Db, [hashtable]$Extra = @{})
            $a = @{
                DatabasePath     = $Db
                SQLDir           = $script:SqliteDir
                SqliteHelperPath = $script:HelperPath
                CoreModulePath   = $script:ModulePath
                Credential       = $script:DummyCred
                LogDir           = (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N')))
                PortalSite       = $script:PortalSite
                SourceSites      = @($script:SrcSite)
                BESRootUrl       = 'https://bes.example:52311'
            }
            foreach ($k in $Extra.Keys) { $a[$k] = $Extra[$k] }
            Start-ContentSync @a
        }
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item -Path $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'ContentSyncCore.psm1 - pure functions' {

    Context 'Get-StrippedName - parity with tests/unit/update_tracker.test.js stripVersion' {
        It 'strips the version from a 7-Zip name' {
            Get-StrippedName -Name '7-Zip (MSI) v26.01 - Windows (x64)' | Should -Be '7-Zip (MSI) - Windows (x64)'
        }
        It 'strips a multi-part version (Eclipse Temurin, unversioned product name)' {
            Get-StrippedName -Name 'Eclipse Temurin JDK with Hotspot v21.0.11.10 - Windows (x64)' |
                Should -Be 'Eclipse Temurin JDK with Hotspot - Windows (x64)'
        }
        It 'preserves a numeric product-family label (Eclipse Temurin 25)' {
            Get-StrippedName -Name 'Eclipse Temurin JDK with Hotspot 25 v25.0.3.9 - Windows (x64)' |
                Should -Be 'Eclipse Temurin JDK with Hotspot 25 - Windows (x64)'
        }
        It 'strips only the long token; keeps the v2 product-family label in AWS CLI v2' {
            Get-StrippedName -Name 'AWS Command Line Interface v2 v2.35.9.0 - Windows (x64)' |
                Should -Be 'AWS Command Line Interface v2 - Windows (x64)'
        }
        It 'returns the name unchanged when no version token is present' {
            Get-StrippedName -Name 'Generic Product - Windows (x64)' | Should -Be 'Generic Product - Windows (x64)'
        }
    }

    Context 'Get-ExtractedVersion - parity with extractVersion' {
        It 'extracts 26.01 from the 7-Zip name' {
            Get-ExtractedVersion -Name '7-Zip (MSI) v26.01 - Windows (x64)' | Should -Be '26.01'
        }
        It 'extracts a 4-part version from Eclipse Temurin' {
            Get-ExtractedVersion -Name 'Eclipse Temurin JDK with Hotspot v21.0.11.10 - Windows (x64)' | Should -Be '21.0.11.10'
        }
        It 'yields empty (null) when no version token is present (JS returns "")' {
            [string](Get-ExtractedVersion -Name 'no version here') | Should -Be ''
        }
    }

    Context 'Compare-FixletVersion - numeric, not lexical' {
        It 'orders 1.2 before 1.10' { Compare-FixletVersion -Left '1.2' -Right '1.10' | Should -Be -1 }
        It '26.02 > 26.01' { Compare-FixletVersion -Left '26.02' -Right '26.01' | Should -Be 1 }
        It '9.0 < 10.0 (not lexical)' { Compare-FixletVersion -Left '9.0' -Right '10.0' | Should -Be -1 }
        It 'equal multi-part' { Compare-FixletVersion -Left '11.0.31.11' -Right '11.0.31.11' | Should -Be 0 }
        It 'later segment differs' { Compare-FixletVersion -Left '2.35.9.0' -Right '2.35.8.0' | Should -Be 1 }
        It '1.0 < 2.0' { Compare-FixletVersion -Left '1.0' -Right '2.0' | Should -Be -1 }
        It 'treats a missing segment as 0 (1 == 1.0)' { Compare-FixletVersion -Left '1' -Right '1.0' | Should -Be 0 }
        It 'treats a missing segment as 0 (1.2 > 1)' { Compare-FixletVersion -Left '1.2' -Right '1' | Should -Be 1 }
        It 'treats a null/empty side as 0' { Compare-FixletVersion -Left '' -Right '0.0' | Should -Be 0 }
    }

    Context 'Get-FixletPathType' {
        It 'returns task for a Task' { Get-FixletPathType -IsTask $true | Should -Be 'task' }
        It 'returns fixlet otherwise' { Get-FixletPathType -IsTask $false | Should -Be 'fixlet' }
    }

    Context 'module purity' {
        It 'contains no I/O cmdlets (acceptance: grep -v ''^#'' | grep -cE ... = 0)' {
            $lines = @(Get-Content $script:ModulePath | Where-Object { $_ -notmatch '^#' })
            @($lines | Where-Object { $_ -match 'Invoke-RestMethod|Invoke-SqliteCommand|Set-Content|Write-Host' }).Count |
                Should -Be 0
        }
    }
}

Describe 'Invoke-ContentSync.ps1 - scan, diff, record' -Skip:(-not $script:HasSqlite) {

    BeforeEach {
        $script:SrcTuples    = @()
        $script:PortalTuples = @()
        Mock -CommandName Invoke-RestMethod -MockWith {
            if ($Uri -like '*/api/query*') {
                $rel = [string]$Body.relevance
                if ($rel -match [regex]::Escape($script:PortalSite)) { return [pscustomobject]@{ result = $script:PortalTuples } }
                if ($rel -match [regex]::Escape($script:SrcSite))    { return [pscustomobject]@{ result = $script:SrcTuples } }
                return [pscustomobject]@{ result = @() }
            }
            return ''
        }
    }

    It 'a strictly-newer source version produces one discovered/update row' {
        $db = script:New-TestDb
        $script:PortalTuples = @( (script:Tuple '10' '7-Zip (MSI) v26.01 - Windows (x64)' $script:PortalSite) )
        $script:SrcTuples    = @( (script:Tuple '200' '7-Zip (MSI) v26.02 - Windows (x64)' $script:SrcSite) )
        script:Run-Sync -Db $db | Out-Null

        script:Count $db 'ContentItem' | Should -Be 1
        $row = (script:Q $db "SELECT stage, discovery_kind, fixlet_id FROM ContentItem")[0]
        $row.stage | Should -Be 'discovered'
        $row.discovery_kind | Should -Be 'update'
        $row.fixlet_id | Should -Be '200'
    }

    It 'an equal version produces no row' {
        $db = script:New-TestDb
        $script:PortalTuples = @( (script:Tuple '10' 'Firefox v130.0 - Windows (x64)' $script:PortalSite) )
        $script:SrcTuples    = @( (script:Tuple '200' 'Firefox v130.0 - Windows (x64)' $script:SrcSite) )
        script:Run-Sync -Db $db | Out-Null
        script:Count $db 'ContentItem' | Should -Be 0
    }

    It 'an older source version produces no row' {
        $db = script:New-TestDb
        $script:PortalTuples = @( (script:Tuple '10' '7-Zip (MSI) v26.02 - Windows (x64)' $script:PortalSite) )
        $script:SrcTuples    = @( (script:Tuple '200' '7-Zip (MSI) v26.01 - Windows (x64)' $script:SrcSite) )
        script:Run-Sync -Db $db | Out-Null
        script:Count $db 'ContentItem' | Should -Be 0
    }

    It 'a source-only product is recorded as discovered/new (new arrival)' {
        $db = script:New-TestDb
        $script:PortalTuples = @()
        $script:SrcTuples    = @( (script:Tuple '201' 'BrandNewApp v1.0 - Windows (x64)' $script:SrcSite 'task') )
        script:Run-Sync -Db $db | Out-Null

        $row = (script:Q $db "SELECT stage, discovery_kind, is_task FROM ContentItem")[0]
        $row.stage | Should -Be 'discovered'
        $row.discovery_kind | Should -Be 'new'
        [int]$row.is_task | Should -Be 1
    }

    It 'a re-scan does not downgrade a row already at stage = ready' {
        $db = script:New-TestDb
        script:Q $db "INSERT INTO ContentItem (fixlet_id, source_site, fixlet_name, stage, is_task) VALUES ('X', @s, 'Foo v1.0 - Windows (x64)', 'ready', 0)" @{ s = $script:SrcSite } | Out-Null
        $script:PortalTuples = @()
        $script:SrcTuples    = @( (script:Tuple 'X' 'Foo v2.0 - Windows (x64)' $script:SrcSite) )
        # MaxItems 0 keeps the copy engine a no-op so this asserts the scan path only
        script:Run-Sync -Db $db -Extra @{ MaxItems = 0 } | Out-Null

        $row = (script:Q $db "SELECT stage, fixlet_name FROM ContentItem WHERE fixlet_id = 'X'")[0]
        $row.stage | Should -Be 'ready'
        $row.fixlet_name | Should -Be 'Foo v1.0 - Windows (x64)'   # guarded UPDATE only touches 'discovered'
    }

    It '-WhatIf writes no ContentItem and no SyncRun row' {
        $db = script:New-TestDb
        $script:PortalTuples = @()
        $script:SrcTuples    = @( (script:Tuple '201' 'BrandNewApp v1.0 - Windows (x64)' $script:SrcSite) )
        script:Run-Sync -Db $db -Extra @{ WhatIf = $true } | Out-Null

        script:Count $db 'ContentItem' | Should -Be 0
        script:Count $db 'SyncRun' | Should -Be 0
    }

    It 'records a ContentSync SyncRun row with Items_Discovered on a real run' {
        $db = script:New-TestDb
        $script:PortalTuples = @( (script:Tuple '10' '7-Zip (MSI) v26.01 - Windows (x64)' $script:PortalSite) )
        $script:SrcTuples    = @(
            (script:Tuple '200' '7-Zip (MSI) v26.02 - Windows (x64)' $script:SrcSite),
            (script:Tuple '201' 'BrandNewApp v1.0 - Windows (x64)' $script:SrcSite)
        )
        script:Run-Sync -Db $db | Out-Null

        $sr = (script:Q $db "SELECT Type, Status, Items_Discovered FROM SyncRun")[0]
        $sr.Type | Should -Be 'ContentSync'
        [int]$sr.Items_Discovered | Should -Be 2
    }

    It 'the script contains no INSERT OR REPLACE' {
        (Get-Content -Raw $script:ScriptPath) -split "`n" | Where-Object { $_ -notmatch '^\s*#' } |
            ForEach-Object { $_ } | Out-String | Should -Not -Match 'INSERT OR REPLACE'
    }
}
