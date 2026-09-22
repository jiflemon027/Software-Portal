#Requires -Version 5.1
# Pester 5 suite for scripts/Reconcile-LocalRoles.ps1 (07-02 Task 3) and the .bes /
# Register-AutomationTasks wiring (07-02 Task 4).
#
#   Invoke-Pester tests/pester/Reconcile-LocalRoles.Tests.ps1 -Output Detailed -CI
#
# DB-backed contexts need sqlite3.exe (resolved from $env:SQLDIR then a probe list). When
# it cannot be found those contexts are skipped, not failed.

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
    $script:ScriptPath  = Join-Path $script:RepoRoot 'scripts\Reconcile-LocalRoles.ps1'
    $script:HelperPath  = Join-Path $script:RepoRoot 'Dashboard_4_samples\Sqlite-Helper.ps1'
    $script:InitRoleDb  = Join-Path $script:RepoRoot 'Dashboard_4_samples\Initialize-RoleDb.ps1'
    $script:ShapePath   = Join-Path $script:RepoRoot 'tests\pester\Assert-SnapshotShape.ps1'
    $script:V2Db        = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\roleawareness-v2.db'
    $script:SnapFixture = Join-Path $script:RepoRoot 'tests\fixtures\phase-07\roleref-AAG-UK-sample.json'
    $script:BesFile     = Join-Path $script:RepoRoot 'Dashboard_4_samples\Init  Current User and UserRole DB.bes'
    $script:RegScript   = Join-Path $script:RepoRoot 'scripts\Register-AutomationTasks.ps1'
    $script:StampReg    = 'HKCU:\Software\DeresoRoleRefTest'
    $script:ScriptText  = Get-Content -Raw $script:ScriptPath

    if ($script:SqliteDir) {
        . $script:HelperPath
        $script:TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('reconcile-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

        function script:Q {
            param([string]$Db, [string]$Sql, [hashtable]$P = @{})
            $r = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $script:SqliteDir -Sql $Sql -Parameters $P
            return @($r | ForEach-Object { $_ })
        }
        function script:New-EndpointDb {
            $db = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N') + '.db')
            Copy-Item $script:V2Db $db -Force
            & $script:InitRoleDb -DatabasePath $db -SQLDir $script:SqliteDir *>&1 | Out-Null
            return $db
        }
        function script:New-SnapDir {
            param([string]$Leaf = 'roleref-aag-uk-latest.json', [string]$Content)
            $d = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            if ($PSBoundParameters.ContainsKey('Content')) {
                Set-Content -Path (Join-Path $d $Leaf) -Value $Content -Encoding UTF8
            } else {
                Copy-Item $script:SnapFixture (Join-Path $d $Leaf) -Force
            }
            return $d
        }
        function script:Run-Reconcile {
            param([string]$Db, [string]$SnapDir, [string]$ConsoleUser, [string]$Region = 'AAG-UK', [switch]$WhatIf)
            $p = @{
                DatabasePath      = $Db
                SQLDir            = $script:SqliteDir
                SnapshotDir       = $SnapDir
                SqliteHelperPath  = $script:HelperPath
                SnapshotShapePath = $script:ShapePath
                StampRegistryPath = $script:StampReg
                Region            = $Region
            }
            if ($ConsoleUser) { $p['ConsoleUser'] = $ConsoleUser }
            if ($WhatIf) { $p['WhatIf'] = $true }
            & $script:ScriptPath @p *>&1
        }
        function script:Map-Fingerprint {
            param([string]$Db, [string]$User, [string]$Role)
            $r = script:Q $Db "SELECT MapID, UserID, Role, Active, Locked_by_Override, Created_on, Updated_on, Valid_to, Source_Type, Source_Value, Region, Assigned_By FROM Map WHERE UserID=@u AND Role=@r" @{ u = $User; r = $Role }
            if ($r.Count -eq 0) { return '<none>' }
            return ($r[0] | ConvertTo-Json -Compress)
        }
    }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) { Remove-Item $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $script:StampReg -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Reconcile-LocalRoles.ps1 - source guarantees' {
    It 'contains no delete-and-reinsert Map upsert, no Map row deletion, no dynamic .NET type loading' {
        $body = ($script:ScriptText -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        ($body -match 'INSERT OR REPLACE INTO Map') | Should -BeFalse
        ($body -match 'DELETE FROM Map')            | Should -BeFalse
        ($body -match 'Add-Type')                   | Should -BeFalse
        ($body -match 'System\.Data\.SQLite')       | Should -BeFalse
    }
    It 'every UPDATE Map here-string carries the Locked_by_Override = 0 guard and a co-located SELECT changes()' {
        $chunks = $script:ScriptText -split '@"'
        $mapChunks = @($chunks | Where-Object { $_ -match 'UPDATE Map SET' })
        $mapChunks.Count | Should -BeGreaterThan 0
        foreach ($c in $mapChunks) {
            $c | Should -Match 'Locked_by_Override = 0'
            $c | Should -Match 'SELECT changes\(\)'
        }
    }
    It 'header records that the GetOwner fallback is scoped to the logon-task path only (D-04)' {
        $script:ScriptText | Should -Match 'SCOPING NOTE'
        $script:ScriptText | Should -Match 'GetOwner'
        $script:ScriptText | Should -Match 'logon-task path'
    }
}

Describe 'Reconcile-LocalRoles.ps1 - behaviour' -Skip:(-not $script:HasSqlite) {

    It 'a user in the snapshot gets a Map row per role: Assigned_By=AxoniousSync, Region set, Valid_to in the future' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir
        script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'jsmith' | Out-Null

        foreach ($role in 'IT Operations', 'Business Default') {
            $row = script:Q $db "SELECT Assigned_By, Region, Valid_to FROM Map WHERE UserID='jsmith' AND Role=@r" @{ r = $role }
            $row.Count | Should -Be 1
            $row[0].Assigned_By | Should -Be 'AxoniousSync'
            $row[0].Region      | Should -Be 'AAG-UK'
            ([datetime]$row[0].Valid_to) | Should -BeGreaterThan (Get-Date)
        }
    }

    It 'a Locked_by_Override = 1 row is byte-identical before and after a reconcile that would otherwise update it' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir
        $before = script:Map-Fingerprint $db 'adavis' 'Business Operations'
        $before | Should -Not -Be '<none>'
        script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'adavis' | Out-Null
        (script:Map-Fingerprint $db 'adavis' 'Business Operations') | Should -Be $before
    }

    It 'a snapshot role absent from Roles (Contract Support) is created by INSERT OR IGNORE INTO Roles' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir
        (script:Q $db "SELECT COUNT(*) AS n FROM Roles WHERE Role='Contract Support'")[0].n | Should -Be 0
        script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'cjones' | Out-Null
        [int](script:Q $db "SELECT COUNT(*) AS n FROM Roles WHERE Role='Contract Support'")[0].n | Should -Be 1
    }

    It 'Source_Type / Source_Value are written verbatim from the matched snapshot user object, including the pipe-joined case' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir
        script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'adavis' | Out-Null
        $row = script:Q $db "SELECT Source_Type, Source_Value FROM Map WHERE UserID='adavis' AND Role='IT Operations'"
        $row.Count | Should -Be 1
        $row[0].Source_Type  | Should -Be 'AD Security Group'
        $row[0].Source_Value | Should -Be 'BNX-M365-E3|IT-Admins-UK'
    }

    It 'a -Region of AAG-FR against the AAG-UK snapshot ABORTS and changes zero rows' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir -Leaf 'roleref-aag-fr-latest.json'
        $countBefore = [int](script:Q $db "SELECT COUNT(*) AS n FROM Map")[0].n
        { script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'jsmith' -Region 'AAG-FR' } | Should -Throw
        [int](script:Q $db "SELECT COUNT(*) AS n FROM Map")[0].n | Should -Be $countBefore
        [int](script:Q $db "SELECT COUNT(*) AS n FROM Map WHERE Assigned_By='AxoniousSync'")[0].n | Should -Be 0
    }

    It 'a missing snapshot file aborts cleanly' {
        $db = script:New-EndpointDb
        $sd = Join-Path $script:TmpRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $sd -Force | Out-Null
        { script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'jsmith' } | Should -Throw
    }

    It 'a truncated / invalid JSON snapshot aborts cleanly' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir -Content '{ "region": "AAG-UK", "roles": [ '
        { script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'jsmith' } | Should -Throw
    }

    It 'a snapshot with no roles array aborts cleanly' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir -Content '{ "region": "AAG-UK", "built_on": "2026-08-29T04:07:00Z", "run_id": "x", "validity_months": 6 }'
        { script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'jsmith' } | Should -Throw
    }

    It 'a blank -ConsoleUser with the explorer.exe branch mocked out logs [SKIP] and exits 0 with no row change' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir
        Mock Get-CimInstance { }
        $before = [int](script:Q $db "SELECT COUNT(*) AS n FROM Map")[0].n
        $out = & $script:ScriptPath -DatabasePath $db -SQLDir $script:SqliteDir -SnapshotDir $sd `
            -SqliteHelperPath $script:HelperPath -SnapshotShapePath $script:ShapePath `
            -StampRegistryPath $script:StampReg -Region 'AAG-UK' *>&1
        ($out -join "`n") | Should -Match '\[SKIP\]'
        [int](script:Q $db "SELECT COUNT(*) AS n FROM Map")[0].n | Should -Be $before
    }

    It 'a console user absent from the snapshot (General Access) changes zero rows, exits 0, and emits no warning or Event Log entry' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir
        Mock Write-EventLog { }
        $before      = [int](script:Q $db "SELECT COUNT(*) AS n FROM Map")[0].n
        $bwongActive = (script:Q $db "SELECT Active FROM Map WHERE UserID='bwong' AND Role='Business Default'")[0].Active
        $out = script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'ktanaka'
        ($out -join "`n") | Should -Match '\[OK\]'
        ($out -join "`n") | Should -Not -Match '\[WARN\]'
        @($out | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
        [int](script:Q $db "SELECT COUNT(*) AS n FROM Map")[0].n | Should -Be $before
        [int](script:Q $db "SELECT COUNT(*) AS n FROM Map WHERE Assigned_By='AxoniousSync'")[0].n | Should -Be 0
        (script:Q $db "SELECT Active FROM Map WHERE UserID='bwong' AND Role='Business Default'")[0].Active | Should -Be $bwongActive
        Should -Invoke Write-EventLog -Times 0
    }

    It '-WhatIf changes zero rows' {
        $db = script:New-EndpointDb
        $sd = script:New-SnapDir
        $before = script:Map-Fingerprint $db 'jsmith' 'IT Operations'
        script:Run-Reconcile -Db $db -SnapDir $sd -ConsoleUser 'jsmith' -WhatIf | Out-Null
        (script:Map-Fingerprint $db 'jsmith' 'IT Operations') | Should -Be $before
        [int](script:Q $db "SELECT COUNT(*) AS n FROM Map WHERE Assigned_By='AxoniousSync'")[0].n | Should -Be 0
    }
}

Describe 'RoleDB_Maintenance rewiring - Init  Current User and UserRole DB.bes (Task 4)' {
    BeforeAll { $script:Bes = Get-Content -Raw $script:BesFile }

    It 'parses as XML' {
        { [xml]$script:Bes } | Should -Not -Throw
    }
    It 'no longer ships Reconcile-LocalRoles.ps1 (Pattern 6 diff, 07-02 rewrite: the Axonius pipeline was retired -- see tests/pester/InitCurrentUserTask.Tests.ps1 for the full regression suite)' {
        $script:Bes | Should -Not -Match 'add prefetch item name=Reconcile-LocalRoles\.ps1 sha1='
        $script:Bes | Should -Not -Match 'copy "__Download\\Reconcile-LocalRoles\.ps1"'
        $script:Bes | Should -Not -Match '\$actionReconcile'
        $script:Bes | Should -Not -Match 'Reconcile-LocalRoles\.ps1`" -Region'
        $script:Bes | Should -Match '-Action @\(\$actionInit\)'
    }
    It 'runs Unregister-ScheduledTask before the "not (exists (scheduled tasks" guard' {
        $iUnreg = $script:Bes.IndexOf('Unregister-ScheduledTask')
        $iGuard = $script:Bes.IndexOf('not (exists (scheduled tasks')
        $iUnreg | Should -BeGreaterThan -1
        $iGuard | Should -BeGreaterThan $iUnreg
    }
    It 'contains zero doubled closing braces' {
        ([regex]::Matches($script:Bes, '\}\}')).Count | Should -Be 0
    }
    It 'every createfile block extracted content contains no doubled closing brace' {
        $rx = [regex]'(?s)createfile until (_[A-Z0-9]+_)\r?\n(.*?)\r?\n\1'
        $blocks = $rx.Matches($script:Bes)
        $blocks.Count | Should -BeGreaterThan 0
        foreach ($b in $blocks) {
            $body = $b.Groups[2].Value
            ([regex]::Matches($body, '\}\}')).Count | Should -Be 0
        }
    }
}

Describe 'Register-AutomationTasks.ps1 - the appended role rows (07-02) + content rows (07-03)' {
    BeforeAll { $script:RegText = Get-Content -Raw $script:RegScript }

    It 'still carries the APPEND-ONLY header comment' {
        $script:RegText | Should -Match 'APPEND-ONLY'
    }
    It 'has exactly one $AutomationTaskTable definition holding the two 07-02 role rows' {
        ([regex]::Matches($script:RegText, '\$AutomationTaskTable\s*=')).Count | Should -Be 1
        $script:RegText | Should -Match "Name\s*=\s*'DeresoRoleIngest'"
        $script:RegText | Should -Match "Name\s*=\s*'DeresoRolePublish'"
        $script:RegText | Should -Match "Script\s*=\s*'Import-AxoniousExport\.ps1'"
        $script:RegText | Should -Match "Script\s*=\s*'Publish-RoleSnapshot\.ps1'"
    }
    It 'now also carries the two 07-03 content rows (APPEND-ONLY, role rows untouched)' {
        $script:RegText | Should -Match "Name\s*=\s*'DeresoContentSync'"
        $script:RegText | Should -Match "Name\s*=\s*'DeresoRepoStage'"
        $script:RegText | Should -Match "Script\s*=\s*'Invoke-ContentSync\.ps1'"
        $script:RegText | Should -Match "Script\s*=\s*'Stage-Repository\.ps1'"
    }

    It '-WhatIf invokes Register-ScheduledTask zero times' {
        Mock Register-ScheduledTask { }
        Mock schtasks.exe { '<Task />' }
        $cfg = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        & $script:RegScript -ConfigDir $cfg -WhatIf *>&1 | Out-Null
        Should -Invoke Register-ScheduledTask -Times 0
    }
    It 'a normal run invokes Register-ScheduledTask once per task (4)' {
        Mock Register-ScheduledTask { }
        Mock schtasks.exe { '<Task />' }
        Mock Set-Content { }
        $cfg = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        & $script:RegScript -ConfigDir $cfg *>&1 | Out-Null
        Should -Invoke Register-ScheduledTask -Times 4
        Remove-Item $cfg -Recurse -Force -ErrorAction SilentlyContinue
    }
    It '-TaskName DeresoRoleIngest invokes Register-ScheduledTask exactly once' {
        Mock Register-ScheduledTask { }
        Mock schtasks.exe { '<Task />' }
        Mock Set-Content { }
        $cfg = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        & $script:RegScript -TaskName 'DeresoRoleIngest' -ConfigDir $cfg *>&1 | Out-Null
        Should -Invoke Register-ScheduledTask -Times 1
        Remove-Item $cfg -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'config/task-*.xml exports (Task 4)' {
    It 'task-DeresoRoleIngest.xml exists and parses as XML' {
        $p = Join-Path $script:RepoRoot 'config\task-DeresoRoleIngest.xml'
        Test-Path $p | Should -BeTrue
        { [xml](Get-Content -Raw $p) } | Should -Not -Throw
    }
    It 'task-DeresoRolePublish.xml exists and parses as XML' {
        $p = Join-Path $script:RepoRoot 'config\task-DeresoRolePublish.xml'
        Test-Path $p | Should -BeTrue
        { [xml](Get-Content -Raw $p) } | Should -Not -Throw
    }
}
