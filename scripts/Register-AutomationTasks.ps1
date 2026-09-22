#Requires -Version 5.1
<#
.SYNOPSIS
    Registers (or unregisters) the Phase 7 root-server Windows Scheduled Tasks from a
    single authoritative table. SKELETON in Wave 0: the table is intentionally empty,
    so a plain run registers zero tasks and exits 0.

.DESCRIPTION
    $AutomationTaskTable is an APPEND-ONLY contract shared by later plans, with one
    documented exception (RESEARCH.md Pitfall 8): the 2026-09-21 Operator-Role-Group
    rewrite retired the Axonius reference-DB pipeline entirely, and plan 07-11 removed
    the two dead ingest/publish rows that pipeline had added here rather than leaving
    them pointing at scripts archived in 07-10 (see 07-10-SUMMARY.md / 07-11-SUMMARY.md
    for exactly which rows). Surviving rows:

      * 07-03 adds  DeresoContentSync  and  DeresoRepoStage
      * 07-05 adds  DeresoRoleGroupSync (D-06 drift check, daily @ 04:00 -- reads the D-05
        RolePublish.db audit store via the new -RolePublishDbPath parameter below, NEVER
        the shared -DatabasePath the other two rows use)

    Outside that one named phase-level pipeline replacement, no plan may reorder,
    rewrite, or remove a row another plan added. Each row is a
    hashtable with EXACTLY these keys:

      Name         task name (also the config\task-<Name>.xml export filename)
      Script       script file under -ScriptRoot to run
      Arguments    argument string appended after -File "<script>"
      Trigger      'Daily' | 'Weekly' | 'AtStartup' | 'OnDemand'  (helper maps these)
      RunLevel     'Highest' | 'Limited'
      User         'SYSTEM' (default) or a service account
      Description  human-readable task description

    Register-AutomationTask consumes one row: it prefers pwsh.exe and falls back to
    powershell.exe (RESEARCH A5), records which was chosen, builds the action/trigger/
    settings, calls Register-ScheduledTask -User "SYSTEM" -RunLevel Highest -Force, then
    exports the registered task with schtasks.exe /Query /TN <name> /XML to
    config\task-<Name>.xml.

.PARAMETER TaskName
    Only act on rows whose Name matches this (wildcards allowed). Default: all rows.

.PARAMETER Unregister
    Remove the matching tasks instead of registering them.

.PARAMETER ScriptRoot
    Directory the row .Script paths are resolved against. Default: this script's folder.

.PARAMETER DatabasePath
    AutomationState.db - passed through to registered scripts that need it.

.PARAMETER SQLDir
    sqlite3.exe directory - passed through to registered scripts that need it.

.PARAMETER LogDir
    Directory for task run logs - passed through to registered scripts.

.PARAMETER ConfigDir
    Where task-<Name>.xml exports are written. Default: <repo>\config.

.PARAMETER WhatIf
    Print the command lines that would be run and register nothing.

.NOTES
    PowerShell 5.1+. Constrained Language Mode safe.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$TaskName = '*',

    [Parameter()]
    [switch]$Unregister,

    [Parameter()]
    [string]$ScriptRoot = $PSScriptRoot,

    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db',

    # D-05 role audit store (07-05). This is a DIFFERENT file from -DatabasePath above --
    # RolePublish.db carries the RolePublishRun/RoleUsers tables the content pipeline's
    # database knows nothing about. Consumed ONLY by the DeresoRoleGroupSync row; every
    # other row keeps using the shared -DatabasePath.
    [Parameter()]
    [string]$RolePublishDbPath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\RolePublish.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$LogDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\logs',

    [Parameter()]
    [string]$ConfigDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =========================================================================
# APPEND-ONLY, with one documented exception (RESEARCH.md Pitfall 8): the 2026-09-21
# Operator-Role-Group rewrite retired the Axonius reference-DB pipeline, and 07-11
# removed the two dead ingest/publish rows that pipeline had added here, rather than
# leaving them pointing at scripts archived in 07-10. Row keys
# (exact): Name, Script, Arguments, Trigger, RunLevel, User, Description.
# Surviving rows: 07-03 appends DeresoContentSync + DeresoRepoStage; 07-05 appends
# DeresoRoleGroupSync. Outside that one named exception, no plan reorders / rewrites /
# removes another plan's row.
# =========================================================================
$AutomationTaskTable = @(
    @{
        Name        = 'DeresoContentSync'
        Script      = 'Invoke-ContentSync.ps1'
        Arguments   = "-DatabasePath `"$DatabasePath`" -SQLDir `"$SQLDir`" -LogDir `"$LogDir`""
        Trigger     = 'Weekly'
        RunLevel    = 'Highest'
        User        = 'SYSTEM'
        Description = 'Dereso content pipeline (07-03): weekly scan of the configured source sites for newer/added product fixlets. Records ContentItems as discovered - the 4-step copy is operator-gated (stage=ready) and AutoApprove is OFF by default (D-26). Chains DeresoRepoStage on a successful run.'
    }
    @{
        Name        = 'DeresoRepoStage'
        Script      = 'Stage-Repository.ps1'
        Arguments   = "-DatabasePath `"$DatabasePath`" -SQLDir `"$SQLDir`" -LogDir `"$LogDir`""
        Trigger     = 'OnDemand'
        RunLevel    = 'Highest'
        User        = 'SYSTEM'
        Description = 'Dereso content pipeline (07-03): no schedule; started on demand and chained from a successful DeresoContentSync. Downloads + SHA1-verifies installer prefetch files for copied fixlets into the Custom Repository; a hash mismatch is always discarded (T-07-03-01).'
    }
    @{
        Name        = 'DeresoRoleGroupSync'
        Script      = 'Sync-RoleGroups.ps1'
        Arguments   = "-DatabasePath `"$RolePublishDbPath`" -SQLDir `"$SQLDir`" -LogDir `"$LogDir`""
        Trigger     = 'Daily@04:00'
        RunLevel    = 'Highest'
        User        = 'SYSTEM'
        Description = 'D-06 drift check (07-05): re-syncs each role''s automatic Computer Group relevance against the RolePublish.db audit store. Reads RolePublish.db, NOT AutomationState.db.'
    }
)

function Resolve-PsHost {
    # RESEARCH A5: prefer PS7, fall back to Windows PowerShell. Return the exe path and
    # a label so the choice is recorded in the exported task XML comment.
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwsh) { return [pscustomobject]@{ Exe = $pwsh.Source; Label = 'pwsh.exe (PS7)' } }
    return [pscustomobject]@{ Exe = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'); Label = 'powershell.exe (PS5.1 fallback)' }
}

function New-TriggerFromSpec {
    param([string]$Spec)
    switch ($Spec) {
        'Daily'     { return (New-ScheduledTaskTrigger -Daily -At 3am) }
        'Weekly'    { return (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am) }
        'AtStartup' { return (New-ScheduledTaskTrigger -AtStartup) }
        'OnDemand'  { return $null }   # registered with no trigger; started explicitly
        'Daily@04:00' { return (New-ScheduledTaskTrigger -Daily -At 4am) }   # 07-05 D-06 drift check -- after the 3am content-pipeline window so the two never contend
        default     { throw "Unknown Trigger spec '$Spec' (expected Daily|Weekly|AtStartup|OnDemand)." }
    }
}

function Register-AutomationTask {
    param([Parameter(Mandatory)][hashtable]$Row)

    $required = 'Name','Script','Arguments','Trigger','RunLevel','User','Description'
    foreach ($k in $required) {
        if (-not $Row.ContainsKey($k)) { throw "Task row is missing required key '$k'." }
    }

    $psHost     = Resolve-PsHost
    $scriptFile = Join-Path $ScriptRoot $Row.Script
    $argLine    = "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`" $($Row.Arguments)".Trim()
    $cmdLine    = "$($psHost.Exe) $argLine"

    if ($WhatIfPreference) {
        Write-Host "[WOULD REGISTER] $($Row.Name)  ($($psHost.Label))"
        Write-Host "                 $cmdLine"
        return
    }

    $action   = New-ScheduledTaskAction -Execute $psHost.Exe -Argument $argLine
    $trigger  = New-TriggerFromSpec -Spec $Row.Trigger
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0

    $regArgs = @{
        TaskName    = $Row.Name
        Action      = $action
        Settings    = $settings
        User        = 'SYSTEM'
        RunLevel    = 'Highest'
        Description = $Row.Description
        Force       = $true
    }
    if ($trigger) { $regArgs['Trigger'] = $trigger }
    Register-ScheduledTask @regArgs | Out-Null
    Write-Host "[REGISTER] $($Row.Name)  ($($psHost.Label))"

    if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }
    $xmlOut = Join-Path $ConfigDir ("task-{0}.xml" -f $Row.Name)
    & schtasks.exe /Query /TN $Row.Name /XML | Set-Content -Path $xmlOut -Encoding Unicode
    Write-Host "[EXPORT]   $xmlOut"
}

function Unregister-AutomationTask {
    param([Parameter(Mandatory)][hashtable]$Row)
    if ($WhatIfPreference) { Write-Host "[WOULD UNREGISTER] $($Row.Name)"; return }
    Unregister-ScheduledTask -TaskName $Row.Name -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "[UNREGISTER] $($Row.Name)"
}

# --- main --------------------------------------------------------------------
$selected = @($AutomationTaskTable | Where-Object { $_.Name -like $TaskName })
Write-Host "Register-AutomationTasks: $($selected.Count) task(s) selected (table has $($AutomationTaskTable.Count) row(s))."

foreach ($row in $selected) {
    if ($Unregister) { Unregister-AutomationTask -Row $row } else { Register-AutomationTask -Row $row }
}

Write-Host "[DONE] Register-AutomationTasks complete$(if ($WhatIfPreference) { ' [WhatIf]' })."
