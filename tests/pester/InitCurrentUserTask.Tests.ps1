#Requires -Version 5.1
# Pester 5 suite locking the Pattern 6 diff applied to task 787's source .bes: the retired
# Reconcile-LocalRoles.ps1 wiring is stripped out, and the D-18 Map migration + the
# Unregister-ScheduledTask pre-guard survive unmodified.
#
#   Invoke-Pester tests/pester/InitCurrentUserTask.Tests.ps1 -Output Detailed -CI
#
# Pure text/XML assertion suite -- no sqlite3.exe dependency, no SQLDIR gate needed.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:BesPath  = Join-Path $script:RepoRoot 'Dashboard_4_samples\Init  Current User and UserRole DB.bes'
    $script:src      = Get-Content -Raw $script:BesPath
}

Describe 'Task 787 - retired Reconcile-LocalRoles wiring is gone' {
    It 'does not reference Reconcile-LocalRoles' {
        $script:src | Should -Not -Match ([regex]::Escape('Reconcile-LocalRoles'))
    }
    It 'does not reference actionReconcile' {
        $script:src | Should -Not -Match ([regex]::Escape('actionReconcile'))
    }
    It 'does not reference a roleref folder' {
        $script:src | Should -Not -Match ([regex]::Escape('roleref'))
    }
    It 'does not register the old two-action array' {
        $script:src | Should -Not -Match ([regex]::Escape('@($actionInit, $actionReconcile)'))
    }
}

Describe 'Task 787 - load-bearing content survives' {
    It 'registers the scheduled task with the single-action array' {
        $script:src | Should -Match ([regex]::Escape('-Action @($actionInit)'))
    }
    It 'still unconditionally unregisters RoleDB_Maintenance before the re-register guard' {
        $script:src | Should -Match ([regex]::Escape("Unregister-ScheduledTask -TaskName 'RoleDB_Maintenance'"))
    }
    It 'still gates re-registration on the task not already existing' {
        $script:src | Should -Match ([regex]::Escape('not (exists (scheduled tasks whose (name of it = "RoleDB_Maintenance")))'))
    }
    It 'still contains the PRAGMA table_info(Map) migration probe' {
        $script:src | Should -Match ([regex]::Escape('PRAGMA table_info(Map)'))
    }
    It 'still contains the D-18 four-column ALTER loop' {
        $script:src | Should -Match ([regex]::Escape("foreach (`$col in 'Source_Type','Source_Value','Region','Assigned_By')"))
    }
    It 'still contains ALTER TABLE Map ADD COLUMN' {
        $script:src | Should -Match ([regex]::Escape('ALTER TABLE Map ADD COLUMN'))
    }
    It 'the D-18 ALTER loop region names all four provenance columns' -ForEach @(
        @{ Column = 'Source_Type' }
        @{ Column = 'Source_Value' }
        @{ Column = 'Region' }
        @{ Column = 'Assigned_By' }
    ) {
        $script:src | Should -Match ([regex]::Escape($Column))
    }
    It 'exactly one New-ScheduledTaskAction call remains' {
        ([regex]::Matches($script:src, 'New-ScheduledTaskAction')).Count | Should -Be 1
    }
}

Describe 'Task 787 - structural integrity' {
    It 'the file casts cleanly to [xml]' {
        { [xml]$script:src } | Should -Not -Throw
    }
    It 'still contains a begin/end prefetch block' {
        $script:src | Should -Match ([regex]::Escape('begin prefetch block'))
        $script:src | Should -Match ([regex]::Escape('end prefetch block'))
    }
    It 'the prefetch block still pins Initialize-RoleDb.ps1 and Sqlite-Helper.ps1' {
        # Initialize-RoleDb.ps1 and Sqlite-Helper.ps1 are landed via createfile, not prefetch --
        # assert their createfile-and-move targets are still present in the ActionScript.
        $script:src | Should -Match ([regex]::Escape('Initialize-RoleDb.ps1"'))
        $script:src | Should -Match ([regex]::Escape('Sqlite-Helper.ps1"'))
    }
    It 'the prefetch block still pins unzip.exe and the sqlite tools zip' {
        $script:src | Should -Match ([regex]::Escape('add prefetch item name=unzip.exe'))
        $script:src | Should -Match ([regex]::Escape('add prefetch item name=sqlite-tools-win-x64-3530100.zip'))
    }
    It 'zero occurrences of a stray triple brace' {
        ([regex]::Matches($script:src, '\}\}\}')).Count | Should -Be 0
    }
}
