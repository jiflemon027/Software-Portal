#Requires -Version 5.1
# Pester 5 suite for bes/RoleRef-Policy-template.bes + the policy-Fixlet lifecycle in
# scripts/Publish-RoleSnapshot.ps1 (rendered via SnapshotBuild.psm1 Format-RoleRefFixletXml).
#
#   Invoke-Pester tests/pester/RoleRefPolicyBes.Tests.ps1 -Output Detailed -CI
#
# The rendering tests need no BigFix server and no sqlite3.exe. The POST/PUT lifecycle
# tests mock Invoke-RestMethod and need sqlite3.exe (skipped, not failed, when absent).

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

    $script:SqliteDir   = Find-SqliteDir
    $script:RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $script:ModulePath  = Join-Path $script:RepoRoot 'scripts\archive\SnapshotBuild.psm1'
    $script:ScriptPath  = Join-Path $script:RepoRoot 'scripts\archive\Publish-RoleSnapshot.ps1'
    $script:HelperPath  = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:SchemaSql   = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\automation-db-schema.sql'
    $script:TemplateBes = Join-Path $script:RepoRoot 'bes\archive\RoleRef-Policy-template.bes'

    Import-Module $script:ModulePath -Force

    $script:TemplateText = Get-Content -Raw $script:TemplateBes
    $script:SnapLine   = 'prefetch roleref-aag-uk-latest.json sha1:0123abcd4567ef89 size:1337 http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/roleref-aag-uk-latest.json'
    $script:ScriptLine = 'prefetch Reconcile-LocalRoles.ps1 sha1:feedface00 size:9001 http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/Reconcile-LocalRoles.ps1'

    function script:Render {
        param([string]$Region = 'AAG-UK', [bool]$Fresh = $true)
        Format-RoleRefFixletXml -TemplateText $script:TemplateText -Region $Region `
            -SnapshotPrefetchLine $script:SnapLine -ScriptPrefetchLine $script:ScriptLine -IncludeFreshnessGate $Fresh
    }
    function script:GetRelevanceInner {
        param([string]$Xml)
        $m = [regex]::Match($Xml, '(?s)<Relevance><!\[CDATA\[(.*?)\]\]></Relevance>')
        return $m.Groups[1].Value
    }
    function script:GetActionScript {
        param([string]$Xml)
        $m = [regex]::Match($Xml, '(?s)<ActionScript[^>]*><!\[CDATA\[(.*?)\]\]></ActionScript>')
        return $m.Groups[1].Value
    }

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('rolerefbes-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:New-TestDb {
            $db  = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.db')
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql (Get-Content -Raw $script:SchemaSql) | Out-Null
            foreach ($rn in 'AAG-UK','AAG-FR') {
                Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql "INSERT INTO Region (GPC_Sub_Name, Active) VALUES (@n,1)" -Parameters @{ n = $rn } | Out-Null
            }
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql "INSERT INTO RolePublication (Role, RegionID, Active) VALUES ('IT Operations', NULL, 1)" | Out-Null
            Invoke-SqliteCommand -DatabasePath $db -SQLDir $script:SqliteDir -Sql "INSERT INTO UserRole (UserID, Role, Source_Type, Source_Value, Active) VALUES ('jsmith','IT Operations','AD Security Group','g',1)" | Out-Null
            return $db
        }
        function script:Q {
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }
        $script:DummyCred = [pscredential]::new('op', (ConvertTo-SecureString 'x' -AsPlainText -Force))
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) { Remove-Item $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'bes/RoleRef-Policy-template.bes (static)' {
    It 'parses as XML, root fixlet element is Fixlet, no SourcedFixletAction' {
        { [xml](Get-Content -Raw $script:TemplateBes) } | Should -Not -Throw
        $x = [xml](Get-Content -Raw $script:TemplateBes)
        $x.BES.Fixlet | Should -Not -BeNullOrEmpty
        @(Select-String -Path $script:TemplateBes -Pattern 'SourcedFixletAction' -SimpleMatch).Count | Should -Be 0
    }
    It 'has zero createfile blocks and zero doubled closing braces' {
        @(Select-String -Path $script:TemplateBes -Pattern 'createfile' -SimpleMatch).Count | Should -Be 0
        @(Select-String -Path $script:TemplateBes -Pattern '}}' -SimpleMatch).Count | Should -Be 0
    }
    It 'contains the required literal markers' {
        $t = $script:TemplateText
        $t | Should -Match 'GPC_Sub_Name'
        $t | Should -Match 'name of current user'
        $t | Should -Match 'roleref___REGION_LC___applied'
        $t | Should -Match 'action uses wow64 redirection'
        $t | Should -Match 'Reconcile-LocalRoles\.ps1'
    }
}

Describe 'Format-RoleRefFixletXml (rendered)' {
    It 'leaves no residual __REGION_LC__ or __PREFETCH_LINE__ token' {
        $r = script:Render
        $r | Should -Not -Match '__REGION_LC__'
        $r | Should -Not -Match '__PREFETCH_LINE__'
        $r | Should -Not -Match '__RECONCILE_PREFETCH__'
    }
    It 'renders as parseable XML with a Fixlet root and no SourcedFixletAction' {
        $r = script:Render
        { [xml]$r } | Should -Not -Throw
        ([xml]$r).BES.Fixlet | Should -Not -BeNullOrEmpty
        $r | Should -Not -Match 'SourcedFixletAction'
    }
    It 'relevance contains all three ANDed clauses, region literal lower-cased, no upper-case region' {
        $rel = script:GetRelevanceInner (script:Render -Region 'AAG-UK')
        $parts = $rel -split ' AND '
        $parts.Count | Should -Be 3
        $rel | Should -Match 'RoleAwareness\.db'
        $rel | Should -Match 'exists setting "GPC_Sub_Name"'
        $rel | Should -Match 'roleref_aag-uk_applied'
        ($rel -cmatch 'AAG-UK') | Should -BeFalse -Because 'the region literal must be lower-cased'
        $rel | Should -Be (New-RoleRefRelevance -Region 'AAG-UK')
    }
    It 'omits the freshness clause when -IncludeFreshnessGate is $false' {
        $rel = script:GetRelevanceInner (script:Render -Region 'AAG-UK' -Fresh $false)
        ($rel -split ' AND ').Count | Should -Be 2
        $rel | Should -Not -Match 'roleref_aag-uk_applied'
    }
    It 'prefetch line matches extractPrefetchLines() regex with the manifest sha1/size' {
        $as = script:GetActionScript (script:Render)
        $line = @($as -split "`n" | Where-Object { $_ -match 'roleref-aag-uk-latest\.json sha1:' })[0].Trim()
        ($line -match '^(?:prefetch\s+)?(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:(\d+)\s+(\S+)') | Should -BeTrue
        $Matches[2] | Should -Be '0123abcd4567ef89'
        $Matches[3] | Should -Be '1337'
    }
    It 'ActionScript has "action uses wow64 redirection" before the waithidden powershell.exe line' {
        $as = script:GetActionScript (script:Render)
        $iWow = $as.IndexOf('action uses wow64 redirection')
        $iRun = $as.IndexOf('waithidden powershell.exe')
        $iWow | Should -BeGreaterThan -1
        $iRun | Should -BeGreaterThan $iWow
    }
    It 'rendered template has zero createfile and zero }}' {
        $r = script:Render
        $r | Should -Not -Match 'createfile'
        $r | Should -Not -Match '\}\}'
    }
}

Describe 'Publish-RoleSnapshot.ps1 policy-Fixlet lifecycle (mocked REST)' -Skip:(-not $script:HasSqlite) {

    It '-SkipFixletPut invokes Invoke-RestMethod zero times' {
        $db = script:New-TestDb
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        Mock Invoke-RestMethod { throw 'should not be called' }
        & $script:ScriptPath -DatabasePath $db -SQLDir $script:SqliteDir -SqliteHelperPath $script:HelperPath `
            -LogDir (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) -OutputDir $out `
            -SkipFixletPut -Credential $script:DummyCred *>&1 | Out-Null
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'first publish POSTs (plural) and records the returned id in PipelineConfig; the next run PUTs (singular) with that id' {
        $db = script:New-TestDb
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        Mock Invoke-RestMethod { '<BESAPI><Fixlet Name="x" ID="4242"></Fixlet></BESAPI>' }

        & $script:ScriptPath -DatabasePath $db -SQLDir $script:SqliteDir -SqliteHelperPath $script:HelperPath `
            -LogDir (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) -OutputDir $out `
            -Region 'AAG-UK' -Credential $script:DummyCred -BESSite 'Dereso Software Portal' *>&1 | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Method -eq 'Post' -and $Uri -match '/api/fixlets/custom/' }
        $row = script:Q $db "SELECT Value FROM PipelineConfig WHERE Key = 'RoleRefFixletId_aag-uk'"
        [string]$row[0].Value | Should -Be '4242'
        (script:Q $db "SELECT Status FROM Snapshot WHERE Region='AAG-UK' ORDER BY SnapshotID DESC LIMIT 1")[0].Status | Should -Be 'published'

        & $script:ScriptPath -DatabasePath $db -SQLDir $script:SqliteDir -SqliteHelperPath $script:HelperPath `
            -LogDir (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) -OutputDir $out `
            -Region 'AAG-UK' -Credential $script:DummyCred -BESSite 'Dereso Software Portal' *>&1 | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Method -eq 'Put' -and $Uri -match '/api/fixlet/custom/.*/4242$' }
    }

    It 'a non-2xx PUT/POST sets Snapshot.Status = failed for that region and does NOT abort the others' {
        $db = script:New-TestDb
        $out = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        Mock Invoke-RestMethod {
            if ($Body -match 'AAG-FR') { throw [System.Net.WebException]::new('500 Internal Server Error') }
            return '<BESAPI><Fixlet ID="77"></Fixlet></BESAPI>'
        }

        & $script:ScriptPath -DatabasePath $db -SQLDir $script:SqliteDir -SqliteHelperPath $script:HelperPath `
            -LogDir (Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))) -OutputDir $out `
            -Credential $script:DummyCred -BESSite 'Dereso Software Portal' *>&1 | Out-Null

        $uk = (script:Q $db "SELECT Status FROM Snapshot WHERE Region='AAG-UK' ORDER BY SnapshotID DESC LIMIT 1")[0].Status
        $fr = (script:Q $db "SELECT Status FROM Snapshot WHERE Region='AAG-FR' ORDER BY SnapshotID DESC LIMIT 1")[0].Status
        $uk | Should -Be 'published'
        $fr | Should -Be 'failed'
        (script:Q $db "SELECT Status FROM SyncRun ORDER BY Started_on DESC LIMIT 1")[0].Status | Should -Be 'partial'
    }
}
