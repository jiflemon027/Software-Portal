#Requires -Version 5.1
# Pester 5 suite that runs scripts/Invoke-WhatIfAudit.ps1 as part of the normal estate:
#
#   Import-Module Pester -MinimumVersion 5.0
#   Invoke-Pester -Path tests/pester/WhatIfAudit.Tests.ps1 -Output Detailed -CI
#
# It asserts, for every one of the six Phase 7 scripts (07-11: the three retired Axonius
# reference-DB pipeline drivers -- Import-AxoniousExport.ps1, Publish-RoleSnapshot.ps1,
# Reconcile-LocalRoles.ps1 -- were removed from the audited set when 07-10 archived them,
# and Sync-RoleGroups.ps1, the D-06 drift-check driver, was added in their place), that a
# -WhatIf run makes zero file / database side effects and still produces a run-audit
# record; that the phase-wide source scan finds zero forbidden constructs; and - the
# negative control - that the audit itself reports a FAILURE when pointed at a script that
# writes despite -WhatIf, so a silently broken audit cannot pass.
#
# Every audited script needs sqlite3.exe to run at all. When it cannot be located the
# whole suite is skipped (not failed), matching the other DB-backed suites.

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
    $script:RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:AuditScript = Join-Path $script:RepoRoot 'scripts\Invoke-WhatIfAudit.ps1'
    $script:TmpRoot     = Join-Path ([System.IO.Path]::GetTempPath()) ('whatif-audit-tests-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TmpRoot -Force | Out-Null

    # ---- full audit of the six scripts (one run, reused by every It) ----
    $script:MainResultPath = Join-Path $script:TmpRoot 'main-result.json'
    & $script:AuditScript -ResultJsonPath $script:MainResultPath *>&1 | Out-Null
    $script:MainExit = $LASTEXITCODE
    $script:Audit = if (Test-Path $script:MainResultPath) {
        Get-Content -Raw $script:MainResultPath | ConvertFrom-Json
    } else { $null }

    # ---- negative control: a script that writes a file despite -WhatIf ----
    $script:EvilScript = Join-Path $script:TmpRoot 'evil-writer.ps1'
    @'
[CmdletBinding(SupportsShouldProcess = $true)]
param()
# A silently-broken script: it declares -WhatIf support but writes anyway.
Set-Content -LiteralPath (Join-Path $env:WHATIF_AUDIT_WORKDIR 'evil-side-effect.txt') -Value 'boom' -WhatIf:$false
'@ | Set-Content -LiteralPath $script:EvilScript -Encoding UTF8

    $script:NegResultPath = Join-Path $script:TmpRoot 'neg-result.json'
    & $script:AuditScript -CustomScriptPath $script:EvilScript -CustomScriptArgs @{ WhatIf = $true } `
        -ResultJsonPath $script:NegResultPath *>&1 | Out-Null
    $script:NegExit = $LASTEXITCODE
    $script:NegAudit = if (Test-Path $script:NegResultPath) {
        Get-Content -Raw $script:NegResultPath | ConvertFrom-Json
    } else { $null }
}

AfterAll {
    if ($script:TmpRoot -and (Test-Path $script:TmpRoot)) {
        Remove-Item -LiteralPath $script:TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-WhatIfAudit.ps1 - per-script -WhatIf side-effect audit' -Skip:(-not $script:HasSqlite) {

    It 'produced a result JSON and exited 0 overall' {
        $script:Audit | Should -Not -BeNullOrEmpty
        $script:Audit.overall_pass | Should -BeTrue
        $script:MainExit | Should -Be 0
    }

    It '<name> makes zero file / DB side effects under -WhatIf' -ForEach @(
        @{ name = 'Initialize-AutomationDb.ps1' }
        @{ name = 'Get-BigFixCredential.ps1' }
        @{ name = 'Invoke-ContentSync.ps1' }
        @{ name = 'Stage-Repository.ps1' }
        @{ name = 'Register-AutomationTasks.ps1' }
        @{ name = 'Sync-RoleGroups.ps1' }
    ) {
        $row = $script:Audit.scripts | Where-Object { $_.name -eq $name }
        $row | Should -Not -BeNullOrEmpty
        $row.pass | Should -BeTrue -Because ("reasons: " + (@($row.reasons) -join ' | '))
    }

    It '<name> produced its dry-run audit record' -ForEach @(
        @{ name = 'Initialize-AutomationDb.ps1' }
        @{ name = 'Get-BigFixCredential.ps1' }
        @{ name = 'Invoke-ContentSync.ps1' }
        @{ name = 'Stage-Repository.ps1' }
        @{ name = 'Register-AutomationTasks.ps1' }
        @{ name = 'Sync-RoleGroups.ps1' }
    ) {
        $row = $script:Audit.scripts | Where-Object { $_.name -eq $name }
        $row.audit_record_ok | Should -BeTrue
    }

    It 'no audited script made a mutating REST or scheduled-task call' {
        foreach ($s in $script:Audit.scripts) {
            @($s.bad_stub_calls).Count | Should -Be 0 -Because "$($s.name): $(@($s.bad_stub_calls) -join ', ')"
        }
    }
}

Describe 'Invoke-WhatIfAudit.ps1 - source scan' -Skip:(-not $script:HasSqlite) {

    It 'finds zero forbidden constructs across the six scripts' {
        $script:Audit.source_scan.pass | Should -BeTrue
        @($script:Audit.source_scan.violations).Count | Should -Be 0
    }
}

Describe 'Invoke-WhatIfAudit.ps1 - negative control' -Skip:(-not $script:HasSqlite) {

    It 'reports a FAILURE for a script that writes despite -WhatIf' {
        $script:NegAudit | Should -Not -BeNullOrEmpty
        $script:NegAudit.overall_pass | Should -BeFalse
        $script:NegExit | Should -Be 1
    }

    It 'the failure names the disallowed file write' {
        $row = $script:NegAudit.scripts | Select-Object -First 1
        $row.pass | Should -BeFalse
        (@($row.reasons) -join ' ') | Should -Match 'evil-side-effect\.txt'
    }
}
