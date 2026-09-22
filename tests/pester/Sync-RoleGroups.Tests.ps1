#Requires -Version 5.1
# Pester 5 suite for scripts/RoleGroupRelevance.psm1 (07-05 Task 1) and
# scripts/Sync-RoleGroups.ps1 (07-05 Task 2) -- the D-06 periodic drift-check job.
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester tests/pester/Sync-RoleGroups.Tests.ps1 -Output Detailed -CI
#
# Golden-file conformance, New-RoleGroupRelevance edge cases, and the source-guarantee
# Describe need no sqlite3.exe and always run. Everything that opens a real RolePublish.db
# (Get-CurrentRoleUsers, the wrong-database guard, the mocked-REST drift scenarios, and the
# -WhatIf contract) is gated on $HasSqlite (resolved from $env:SQLDIR then a probe list,
# same convention as every other DB-backed suite in this repo) and is SKIPPED, not failed,
# when sqlite3.exe cannot be found.

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
    $script:RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ModulePath  = Join-Path $script:RepoRoot 'scripts\RoleGroupRelevance.psm1'
    $script:ScriptPath  = Join-Path $script:RepoRoot 'scripts\Sync-RoleGroups.ps1'
    $script:UpsertPath  = Join-Path $script:RepoRoot 'scripts\Upsert-RolePublish.ps1'
    $script:HelperPath  = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:GoldenPath  = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\role-group-relevance.golden.txt'
    $script:ScriptText  = Get-Content -Raw $script:ScriptPath

    Import-Module $script:ModulePath -Force
    $script:Golden = @(Get-Content -Raw $script:GoldenPath) -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne '' }

    if ($script:SqliteDir) {
        . $script:HelperPath
        # Same cross-scope fix Sync-RoleGroups.ps1 itself applies: promote the
        # already-dot-sourced Invoke-SqliteCommand to global scope so this test file can
        # also call RoleGroupRelevance.psm1's Get-CurrentRoleUsers directly (an
        # Import-Module'd module's parent scope is always the session's global scope).
        Set-Item -Path function:\global:Invoke-SqliteCommand -Value (Get-Item function:\Invoke-SqliteCommand).ScriptBlock -WhatIf:$false

        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('srg-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:Q {
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }

        function script:New-TestDb {
            # Fresh directory per DB, carrying its own Sqlite-Helper.ps1 copy so every
            # Upsert-RolePublish.ps1 call below exercises its DEFAULT -SqliteHelperPath
            # resolution (beside -DatabasePath), matching Upsert-RolePublish.Tests.ps1.
            $dir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Copy-Item $script:HelperPath (Join-Path $dir 'Sqlite-Helper.ps1') -Force
            return (Join-Path $dir 'RolePublish.db')
        }

        function script:Publish-TestRole {
            param([string]$Db, [string]$Role, [string[]]$Users, [string]$By = 'tester')
            $obj  = [ordered]@{ role = $Role; published_by = $By; users = @($Users) }
            $json = $obj | ConvertTo-Json -Depth 5 -Compress
            $path = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.json')
            Set-Content -Path $path -Value $json -Encoding UTF8
            & $script:UpsertPath -PayloadPath $path -DatabasePath $Db -SQLDir $script:SqliteDir *>&1 | Out-Null
        }

        function script:Run-Sync {
            param([string]$Db, [hashtable]$Extra = @{}, [switch]$WhatIfRun)
            $cred = [pscredential]::new('dummy', (ConvertTo-SecureString 'dummy' -AsPlainText -Force))
            $logDir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
            $p = @{
                DatabasePath = $Db
                SQLDir       = $script:SqliteDir
                BESRootUrl   = 'https://bes.example.invalid:52311'
                Credential   = $cred
                LogDir       = $logDir
            }
            foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
            if ($WhatIfRun) { $p['WhatIf'] = $true }
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

# ---------------------------------------------------------------------------
# Golden-file conformance -- keeps PowerShell and JS pinned to the same string.
# ---------------------------------------------------------------------------

Describe 'New-RoleGroupRelevance vs. the golden fixture' {

    It 'golden file has exactly 3 non-blank lines' {
        $script:Golden.Count | Should -Be 3
    }

    It 'line 1 (alice,bob, no scope) matches exactly' {
        (New-RoleGroupRelevance -UserName @('alice', 'bob')) | Should -BeExactly $script:Golden[0]
    }

    It 'line 2 (alice,bob, scope group 12345 / Dereso Software Portal) matches exactly' {
        (New-RoleGroupRelevance -UserName @('alice', 'bob') -ScopeGroupId '12345' -ScopeSiteName 'Dereso Software Portal') |
            Should -BeExactly $script:Golden[1]
    }

    It 'line 3 (empty list) matches exactly and is the literal word "false"' {
        (New-RoleGroupRelevance -UserName @()) | Should -BeExactly $script:Golden[2]
        $script:Golden[2] | Should -BeExactly 'false'
    }
}

Describe 'New-RoleGroupRelevance edge cases (D-09/D-10, T-07-04-01/02)' {

    It 'empty array returns exactly "false"' {
        New-RoleGroupRelevance -UserName @() | Should -BeExactly 'false'
    }

    It 'null returns exactly "false"' {
        New-RoleGroupRelevance -UserName $null | Should -BeExactly 'false'
    }

    It 'a scope group id set but an empty username list is still exactly "false" (guard wins)' {
        New-RoleGroupRelevance -UserName @() -ScopeGroupId '12345' -ScopeSiteName 'Dereso Software Portal' | Should -BeExactly 'false'
    }

    It 'dedups case-insensitively and trims whitespace, preserving first-seen order' {
        $rel = New-RoleGroupRelevance -UserName @('Alice', 'ALICE', '  alice  ')
        $rel | Should -BeExactly '(number of (logged on users whose (name of it as lowercase is contained by set of ("alice")))) = 1'
    }

    It 'preserves first-seen insertion order rather than sorting' {
        $rel = New-RoleGroupRelevance -UserName @('bob', 'alice')
        $rel | Should -Match '\("bob";"alice"\)'
    }

    It 'escapes an embedded double-quote by doubling it, with an even quote count inside the set' {
        $rel = New-RoleGroupRelevance -UserName @('ali"ce')
        $rel | Should -Match 'ali""ce'
        $setOf = [regex]::Match($rel, 'set of \((.*)\)\)\)\)')
        $setOf.Success | Should -BeTrue
        (($setOf.Groups[1].Value.ToCharArray() | Where-Object { $_ -eq '"' }).Count % 2) | Should -Be 0
    }

    It 'appends the exact AND clause when a scope group id + site name are given' {
        $rel = New-RoleGroupRelevance -UserName @('alice') -ScopeGroupId '12345' -ScopeSiteName 'Dereso Software Portal'
        $rel | Should -Match ([regex]::Escape(' AND (member of group 12345 of site whose (name of it as lowercase = "dereso software portal" as lowercase))'))
        $rel.Substring($rel.Length - 1) | Should -Be ')'
    }

    It 'blank, null, or "0" scope group id emits no AND clause' {
        (New-RoleGroupRelevance -UserName @('alice') -ScopeGroupId '' -ScopeSiteName 'site') | Should -Not -Match 'member of group'
        (New-RoleGroupRelevance -UserName @('alice') -ScopeGroupId $null -ScopeSiteName 'site') | Should -Not -Match 'member of group'
        (New-RoleGroupRelevance -UserName @('alice') -ScopeGroupId '0' -ScopeSiteName 'site') | Should -Not -Match 'member of group'
    }

    It 'result never contains the literal word "true"' {
        (New-RoleGroupRelevance -UserName @()) | Should -Not -Match 'true'
        (New-RoleGroupRelevance -UserName @('alice')) | Should -Not -Match '\btrue\b'
    }
}

Describe 'Get-CurrentRoleUsers (D-05 canonical MAX(RunID) query)' -Skip:(-not $HasSqlite) {

    It 'returns only the latest run''s users, in ORDER BY UserID order' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('bob', 'alice')
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('carol')

        $users = Get-CurrentRoleUsers -DatabasePath $db -SQLDir $script:SqliteDir -Role 'IT Operations'
        @($users) | Should -Be @('carol')
    }

    It 'orders a multi-user latest run by UserID ascending' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('charlie', 'alice', 'bob')

        $users = Get-CurrentRoleUsers -DatabasePath $db -SQLDir $script:SqliteDir -Role 'IT Operations'
        @($users) | Should -Be @('alice', 'bob', 'charlie')
    }

    It 'returns an empty array (not $null) for a role that has never been published' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('alice')

        $users = Get-CurrentRoleUsers -DatabasePath $db -SQLDir $script:SqliteDir -Role 'Nonexistent Role'
        ($null -eq $users) | Should -BeFalse -Because 'the function must return an empty array, never $null'
        $users.GetType().IsArray | Should -BeTrue
        @($users).Count | Should -Be 0
    }
}

Describe 'Sync-RoleGroups.ps1 - source guarantees' {
    BeforeAll {
        $noBlockComments = [regex]::Replace($script:ScriptText, '(?s)<#.*?#>', '')
        $script:Body = ($noBlockComments -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    It 'contains computergroup/custom (singular, GET/PUT of one group)' {
        $script:ScriptText | Should -Match ([regex]::Escape('computergroup/custom'))
    }

    It 'never POSTs to computergroups/custom (plural) -- group creation stays the dashboard''s job' {
        $listUsages = [regex]::Matches($script:ScriptText, '.*computergroups/custom.*')
        foreach ($m in $listUsages) {
            $m.Value | Should -Not -Match '-Method\s+Post'
        }
        $script:Body | Should -Not -Match '-Method\s+Post'
    }

    It 'contains no dynamic .NET type-loading (Add-Type)' {
        $script:Body | Should -Not -Match 'Add-Type'
    }

    It 'declares SupportsShouldProcess' {
        $script:ScriptText | Should -Match 'SupportsShouldProcess\s*=\s*\$true'
    }

    It 'default -DatabasePath literal ends in RolePublish.db and the file contains no reference to AutomationState.db' {
        $script:ScriptText | Should -Match ([regex]::Escape('RolePublish.db'))
        $script:ScriptText | Should -Not -Match ([regex]::Escape('AutomationState.db'))
    }

    It 'emits the [DRIFT-FIXED], [OK], [MISSING] and [FAIL] literals' {
        $script:ScriptText | Should -Match ([regex]::Escape('[DRIFT-FIXED]'))
        $script:ScriptText | Should -Match "'OK'"
        $script:ScriptText | Should -Match "'MISSING'"
        $script:ScriptText | Should -Match "'FAIL'"
    }

    It 'parses cleanly under the PowerShell AST parser' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$errors) | Out-Null
        @($errors).Count | Should -Be 0
    }
}

Describe 'Sync-RoleGroups.ps1 - wrong-database guard' -Skip:(-not $HasSqlite) {

    It 'aborts with a distinct code and emits no PUT when -DatabasePath has no RolePublishRun table' {
        $dir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $badDb = Join-Path $dir 'not-a-rolepublish.db'
        script:Q $badDb "CREATE TABLE SomeOtherTable (x INTEGER)" | Out-Null

        Mock Invoke-RestMethod { throw 'REST must never be called for a wrong-database abort' }

        $res = script:Run-Sync -Db $badDb
        $res.ExitCode | Should -Not -Be 0
        ($res.Output -join "`n") | Should -Match 'is not a RolePublish\.db audit store'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'aborts with a distinct, different code when the database file does not exist at all' {
        $dir = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $missingDb = Join-Path $dir 'does-not-exist.db'

        $res = script:Run-Sync -Db $missingDb
        $res.ExitCode | Should -Not -Be 0
        ($res.Output -join "`n") | Should -Match 'not found'
    }
}

Describe 'Sync-RoleGroups.ps1 - drift detection and correction (mocked REST)' -Skip:(-not $HasSqlite) {
    # NOTE: Mock scriptblocks below deliberately avoid the $script: scope modifier for
    # any mutable state (e.g. a call counter/toggle). $script: inside a Mock body does
    # NOT reliably resolve to this .Tests.ps1 file's script scope once the mocked
    # command is invoked from deep inside a nested `& scripts\Sync-RoleGroups.ps1` call
    # (confirmed empirically -- it throws "variable has not been set" under
    # Set-StrictMode even immediately after a BeforeEach assignment). Plain lexically-
    # captured local variables (ordinary closures) and Pester's own
    # `Should -Invoke -ParameterFilter` call-counting are used instead, both of which
    # ARE reliable across that boundary.

    It 'a group whose live relevance already matches is reported [OK] and issues no PUT' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('alice', 'bob')
        $expected = New-RoleGroupRelevance -UserName @('alice', 'bob')

        Mock Invoke-RestMethod {
            param($Method, $Uri, $Credential, $Body, $ContentType)
            if ($Method -eq 'Get' -and $Uri -like '*computergroups/custom/*') {
                return [xml]@"
<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BESAPI.xsd">
  <ComputerGroup Resource="https://bes.example.invalid:52311/api/computergroup/custom/Dereso%20Software%20Portal/555">
    <Name>DSP Role - IT Operations</Name>
    <ID>555</ID>
  </ComputerGroup>
</BESAPI>
"@
            }
            if ($Method -eq 'Get' -and $Uri -like '*computergroup/custom/*') {
                return [xml]@"
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <ComputerGroup>
    <Title>DSP Role - IT Operations</Title>
    <Domain>BESC</Domain>
    <JoinByIntersection>true</JoinByIntersection>
    <SearchComponentRelevance Comparison="IsTrue">
      <Relevance><![CDATA[$expected]]></Relevance>
    </SearchComponentRelevance>
  </ComputerGroup>
</BES>
"@
            }
            if ($Method -eq 'Put') { return [xml]'<BESAPI></BESAPI>' }
            throw "unexpected mock Invoke-RestMethod call: $Method $Uri"
        }

        $res = script:Run-Sync -Db $db
        $res.ExitCode | Should -Be 0
        ($res.Output -join "`n") | Should -Match '\[OK\] IT Operations'
        ($res.Output -join "`n") | Should -Not -Match '\[DRIFT-FIXED\]'
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Put' } -Times 0 -Exactly
    }

    It 'a group whose live relevance has drifted is reported [DRIFT-FIXED] and PUT exactly once with the expected relevance' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('alice', 'bob')
        $expected = New-RoleGroupRelevance -UserName @('alice', 'bob')

        Mock Invoke-RestMethod {
            param($Method, $Uri, $Credential, $Body, $ContentType)
            if ($Method -eq 'Get' -and $Uri -like '*computergroups/custom/*') {
                return [xml]@"
<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BESAPI.xsd">
  <ComputerGroup Resource="https://bes.example.invalid:52311/api/computergroup/custom/Dereso%20Software%20Portal/555">
    <Name>DSP Role - IT Operations</Name>
    <ID>555</ID>
  </ComputerGroup>
</BESAPI>
"@
            }
            if ($Method -eq 'Get' -and $Uri -like '*computergroup/custom/*') {
                return [xml]@'
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <ComputerGroup>
    <Title>DSP Role - IT Operations</Title>
    <Domain>BESC</Domain>
    <JoinByIntersection>true</JoinByIntersection>
    <SearchComponentRelevance Comparison="IsTrue">
      <Relevance><![CDATA[(number of (logged on users whose (name of it as lowercase is contained by set of ("stale-user")))) = 1]]></Relevance>
    </SearchComponentRelevance>
  </ComputerGroup>
</BES>
'@
            }
            if ($Method -eq 'Put') { return [xml]'<BESAPI></BESAPI>' }
            throw "unexpected mock Invoke-RestMethod call: $Method $Uri"
        }

        $res = script:Run-Sync -Db $db
        $res.ExitCode | Should -Be 0
        ($res.Output -join "`n") | Should -Match '\[DRIFT-FIXED\] IT Operations'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Put' -and
            $Body -match [regex]::Escape($expected) -and
            $Body -match '<ComputerGroup>' -and
            $Body -match '<EvaluateOnClient>true</EvaluateOnClient>'
        }
    }

    It 'a role with no matching Computer Group is reported [MISSING] and issues no PUT' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'Ghost Role' -Users @('alice')

        Mock Invoke-RestMethod {
            param($Method, $Uri, $Credential, $Body, $ContentType)
            if ($Method -eq 'Get' -and $Uri -like '*computergroups/custom/*') {
                return [xml]'<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BESAPI.xsd"></BESAPI>'
            }
            throw "unexpected mock Invoke-RestMethod call: $Method $Uri"
        }

        $res = script:Run-Sync -Db $db
        $res.ExitCode | Should -Be 0
        ($res.Output -join "`n") | Should -Match '\[MISSING\] Ghost Role'
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Put' } -Times 0 -Exactly
    }

    It 'a per-role REST failure is caught, logged [FAIL], and does not abort a second role in the same run' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'Broken Role' -Users @('alice')
        script:Publish-TestRole -Db $db -Role 'Ghost Role'  -Users @('bob')

        # Reference-type local variable, captured by the Mock closure lexically (NOT
        # $script:-qualified) -- this toggle survives across the two Invoke-RestMethod
        # calls the run makes, one per role, in call order.
        $callState = [pscustomobject]@{ FirstListCallDone = $false }

        Mock Invoke-RestMethod {
            param($Method, $Uri, $Credential, $Body, $ContentType)
            if ($Method -eq 'Get' -and $Uri -like '*computergroups/custom/*') {
                if ($callState.FirstListCallDone) {
                    return [xml]'<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BESAPI.xsd"></BESAPI>'
                }
                $callState.FirstListCallDone = $true
                throw 'simulated REST failure'
            }
            throw "unexpected mock Invoke-RestMethod call: $Method $Uri"
        }

        $res = script:Run-Sync -Db $db
        $joined = ($res.Output -join "`n")
        $joined | Should -Match '\[FAIL\] Broken Role'
        $joined | Should -Match '\[MISSING\] Ghost Role' -Because 'one role failing must not abort the remaining roles'
    }

    It 'exits non-zero only when every role failed' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'Only Role' -Users @('alice')

        Mock Invoke-RestMethod { throw 'simulated total REST outage' }

        $res = script:Run-Sync -Db $db
        $res.ExitCode | Should -Not -Be 0
    }
}

Describe 'Sync-RoleGroups.ps1 - -WhatIf contract' -Skip:(-not $HasSqlite) {

    It '-WhatIf against an unreachable BESRootUrl issues no PUT and emits a [WHATIF] log line' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('alice', 'bob')

        $res = script:Run-Sync -Db $db -Extra @{ BESRootUrl = 'https://127.0.0.1:1' } -WhatIfRun
        $joined = ($res.Output -join "`n")
        $joined | Should -Match ([regex]::Escape('[WHATIF]'))
        $joined | Should -Not -Match '\[DRIFT-FIXED\]'
    }

    It '-WhatIf on a drifted group logs [WOULD PUT] and issues zero real PUT calls' {
        $db = script:New-TestDb
        script:Publish-TestRole -Db $db -Role 'IT Operations' -Users @('alice', 'bob')

        Mock Invoke-RestMethod {
            param($Method, $Uri, $Credential, $Body, $ContentType)
            if ($Method -eq 'Get' -and $Uri -like '*computergroups/custom/*') {
                return [xml]@"
<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BESAPI.xsd">
  <ComputerGroup Resource="https://bes.example.invalid:52311/api/computergroup/custom/Dereso%20Software%20Portal/555">
    <Name>DSP Role - IT Operations</Name>
    <ID>555</ID>
  </ComputerGroup>
</BESAPI>
"@
            }
            if ($Method -eq 'Get' -and $Uri -like '*computergroup/custom/*') {
                return [xml]'<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd"><ComputerGroup><Title>DSP Role - IT Operations</Title><Domain>BESC</Domain><JoinByIntersection>true</JoinByIntersection><SearchComponentRelevance Comparison="IsTrue"><Relevance><![CDATA[stale]]></Relevance></SearchComponentRelevance></ComputerGroup></BES>'
            }
            if ($Method -eq 'Put') { return [xml]'<BESAPI></BESAPI>' }
            throw "unexpected mock Invoke-RestMethod call: $Method $Uri"
        }

        $res = script:Run-Sync -Db $db -WhatIfRun
        $joined = ($res.Output -join "`n")
        $joined | Should -Match ([regex]::Escape('[WOULD PUT]'))
        Should -Invoke Invoke-RestMethod -ParameterFilter { $Method -eq 'Put' } -Times 0 -Exactly
    }
}
