#Requires -Version 5.1
<#
.SYNOPSIS
    Registers (or unregisters) the Phase 7 root-server Windows Scheduled Tasks from a
    single authoritative table. SKELETON in Wave 0: the table is intentionally empty,
    so a plain run registers zero tasks and exits 0.

.DESCRIPTION
    $AutomationTaskTable is an APPEND-ONLY contract shared by later plans:

      * 07-02 adds  DeresoRoleIngest   and  DeresoRolePublish
      * 07-03 adds  DeresoContentSync  and  DeresoRepoStage

    No plan may reorder, rewrite, or remove a row another plan added. Each row is a
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
# APPEND-ONLY. Row keys (exact): Name, Script, Arguments, Trigger, RunLevel, User, Description
# Wave 0: EMPTY. 07-02 appends DeresoRoleIngest + DeresoRolePublish; 07-03 appends
# DeresoContentSync + DeresoRepoStage. No plan reorders / rewrites / removes another
# plan's row.
# =========================================================================
$AutomationTaskTable = @(
    @{
        Name        = 'DeresoRoleIngest'
        Script      = 'Import-AxoniousExport.ps1'
        Arguments   = "-DatabasePath `"$DatabasePath`" -SQLDir `"$SQLDir`" -LogDir `"$LogDir`""
        Trigger     = 'Daily'
        RunLevel    = 'Highest'
        User        = 'SYSTEM'
        Description = 'Dereso role pipeline (07-01): daily streaming ingest of the Axonius user export into AutomationState.db.'
    }
    @{
        Name        = 'DeresoRolePublish'
        Script      = 'Publish-RoleSnapshot.ps1'
        Arguments   = "-DatabasePath `"$DatabasePath`" -SQLDir `"$SQLDir`" -LogDir `"$LogDir`""
        Trigger     = 'Daily'
        RunLevel    = 'Highest'
        User        = 'SYSTEM'
        Description = 'Dereso role pipeline (07-02): daily per-region snapshot publish + policy-Fixlet re-PUT. Intended to run AFTER DeresoRoleIngest (07-05 run-book sequences the two 3am triggers / adds task chaining).'
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
