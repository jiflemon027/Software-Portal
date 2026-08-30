#Requires -Version 5.1
<#
.SYNOPSIS
    Content pipeline (07-03) - pre-stages the installer files referenced by copied portal
    fixlets into the BigFix Custom Repository so the local URL the Dispatcher's
    rewritePrefetchUrls() produces (the CustomRepository/SoftwarePortal/<sha1>/<file>
    subtree) actually resolves. Started on demand and chained from a successful
    Invoke-ContentSync.ps1.

.DESCRIPTION
    For every ContentItem at stage = 'live' that has not yet been staged, the script
    fetches the new portal fixlet's action script over REST, parses every `prefetch` line
    (Read-PrefetchLine / ContentSyncCore.psm1), and for each one:

      * skips it when a verified ContentCache row already exists for that sha1 (installers
        are shared across fixlets - fetch once);
      * downloads from the ORIGINAL internet url the prefetch line carries (never the
        rewritten local one - the OJO comment at fixlet_dispatcher.ojo L601-605 is explicit);
      * verifies Get-FileHash -Algorithm SHA1 AND the byte length against the prefetch
        line; on ANY mismatch it deletes the temp file, writes a ContentCache row with
        verified = 0 recording the expected/actual hashes, raises Event 8040, and
        continues - nothing unverified ever reaches the repository (T-07-03-01);
      * on a match it creates <StagingRoot>\<sha1-lowercase>\ and moves the file in under
        its original name, then writes a verified = 1 ContentCache row.

    Guards: a per-file size ceiling (PipelineConfig.MaxStageFileMB, default 4096) and a
    per-run -MaxItems cap; exceeding either logs and skips rather than aborting (T-07-03-03).

    -WhatIf: parses everything, reports every url that WOULD be downloaded and the path
    each file WOULD land at, and performs zero downloads, zero file writes and zero DB writes.

.PARAMETER DatabasePath   AutomationState.db on the root server.
.PARAMETER SQLDir         Directory containing sqlite3.exe directly (no arch subfolder).
.PARAMETER BESRootUrl     BigFix REST base URL. Falls back to PipelineConfig.BESRootUrl.
.PARAMETER PortalSite     Portal custom site. Default 'Dereso Software Portal'.
.PARAMETER StagingRoot    Override the on-disk repository root. Default is derived from
                          (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server').wwwRootFolder
                          joined with Uploads\CustomRepository\SoftwarePortal. Never a
                          hard-coded DataDirectory path.
.PARAMETER RunId          Run id. Defaults to a fresh GUID.
.PARAMETER LogDir         Per-run JSON log directory. Defaults to <repo>\logs.
.PARAMETER MaxItems       Cap on how many ContentItems the run processes.
.PARAMETER MaxStageFileMB Per-file download ceiling. Falls back to PipelineConfig.MaxStageFileMB (4096).
.PARAMETER Credential     BigFix operator [pscredential]. Fetched from AKeyless via
                          Get-BigFixCredential.ps1 when omitted. Tests pass a dummy.
.PARAMETER SqliteHelperPath  Shared Dashboard_4_samples\Sqlite-Helper.ps1.
.PARAMETER CoreModulePath    scripts\ContentSyncCore.psm1.

.NOTES
    PowerShell 5.1+ (root server prefers pwsh 7 - assumption A2). Error codes 6920-6999.
      6920  StagingRoot unresolved (registry read failed and no -StagingRoot)
      6910  Sqlite-Helper.ps1 / ContentSyncCore.psm1 not found
    Event Log (Source 'DereseSoftwarePortal', LogName Application):
      8040  a downloaded file's SHA1 / size did not match its prefetch line - discarded
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()][string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db',
    [Parameter()][string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',
    [Parameter()][string]$BESRootUrl,
    [Parameter()][string]$PortalSite = 'Dereso Software Portal',
    [Parameter()][string]$StagingRoot,
    [Parameter()][string]$RunId = ([guid]::NewGuid().ToString()),
    [Parameter()][string]$LogDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'),
    [Parameter()][int]$MaxItems = 50,
    [Parameter()][int]$MaxStageFileMB = 0,
    [Parameter()][pscredential]$Credential,
    [Parameter()][string]$SqliteHelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Dashboard_4_samples\Sqlite-Helper.ps1'),
    [Parameter()][string]$CoreModulePath = (Join-Path $PSScriptRoot 'ContentSyncCore.psm1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:EventLogSource = 'DereseSoftwarePortal'

if (-not (Test-Path $SqliteHelperPath)) { throw "6910: Sqlite-Helper.ps1 not found at: $SqliteHelperPath" }
. $SqliteHelperPath
if (-not (Test-Path $CoreModulePath)) { throw "6910: ContentSyncCore.psm1 not found at: $CoreModulePath" }
Import-Module $CoreModulePath -Force

# =============================================================================
# helpers
# =============================================================================

function Write-RepoStageEvent {
    param([int]$EventId, [string]$Message, [string]$EntryType = 'Error')
    try {
        Write-EventLog -LogName Application -Source $script:EventLogSource -EntryType $EntryType `
            -EventId $EventId -Message $Message
    } catch { }
}

function Get-RsRows {
    param([Parameter(Mandatory)][string]$DatabasePath, [Parameter(Mandatory)][string]$SQLDir,
          [Parameter(Mandatory)][string]$Sql, [hashtable]$P = @{})
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P
    return @($r | ForEach-Object { $_ })
}

function Invoke-RsWrite {
    param([Parameter(Mandatory)][string]$DatabasePath, [Parameter(Mandatory)][string]$SQLDir,
          [Parameter(Mandatory)][string]$Sql, [hashtable]$P = @{})
    if ($WhatIfPreference) { return }
    Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P | Out-Null
}

function Add-TableColumn {
    param([Parameter(Mandatory)][string]$DatabasePath, [Parameter(Mandatory)][string]$SQLDir,
          [Parameter(Mandatory)][string]$Table, [Parameter(Mandatory)][string]$Column, [string]$Type = 'TEXT')
    $cols = @(Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA table_info($Table)" |
                ForEach-Object { $_.name })
    if ($cols -notcontains $Column) {
        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
            -Sql "ALTER TABLE $Table ADD COLUMN $Column $Type" | Out-Null
    }
}

function Get-RsIrmExtra {
    $extra = @{}
    if ($PSVersionTable.PSVersion.Major -ge 6) { $extra['SkipCertificateCheck'] = $true }
    else { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
    return $extra
}

function Resolve-StagingRoot {
    param([string]$Override, [hashtable]$Config)
    if ($Override) { return $Override }
    if ($Config.ContainsKey('StagingRoot') -and -not [string]::IsNullOrWhiteSpace($Config['StagingRoot'])) {
        return $Config['StagingRoot']
    }
    try {
        $www = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server' -ErrorAction Stop).wwwRootFolder
    } catch { $www = $null }
    if ([string]::IsNullOrWhiteSpace($www)) {
        throw "6920: cannot read wwwRootFolder from HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server and no -StagingRoot override is set."
    }
    return (Join-Path $www 'Uploads\CustomRepository\SoftwarePortal')
}

function Get-ActionScriptLines {
    # Every <ActionScript> element's text, flattened to individual lines.
    param([string]$FixletXml)
    $out = New-Object System.Collections.ArrayList
    try {
        $x = [xml]$FixletXml
        foreach ($n in $x.GetElementsByTagName('ActionScript')) {
            foreach ($ln in ([string]$n.InnerText -split "`r?`n")) { [void]$out.Add($ln) }
        }
    } catch {
        foreach ($ln in ([string]$FixletXml -split "`r?`n")) { [void]$out.Add($ln) }
    }
    return $out.ToArray()
}

# =============================================================================
# main
# =============================================================================

function Start-RepoStage {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$SQLDir,
        [string]$BESRootUrl,
        [string]$PortalSite = 'Dereso Software Portal',
        [string]$StagingRoot,
        [string]$RunId = ([guid]::NewGuid().ToString()),
        [string]$LogDir,
        [int]$MaxItems = 50,
        [int]$MaxStageFileMB = 0,
        [pscredential]$Credential,
        [string]$SqliteHelperPath,
        [string]$CoreModulePath
    )

    $started = (Get-Date).ToUniversalTime()
    if (-not $LogDir) { $LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs' }

    $cfg = @{}
    foreach ($r in (Get-RsRows -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "SELECT Key, Value FROM PipelineConfig")) {
        $cfg[[string]$r.Key] = [string]$r.Value
    }
    if (-not $BESRootUrl) {
        $BESRootUrl = if ($cfg.ContainsKey('BESRootUrl') -and $cfg['BESRootUrl']) { $cfg['BESRootUrl'] } else { 'https://localhost:52311' }
    }
    if ($MaxStageFileMB -le 0) {
        $MaxStageFileMB = if ($cfg.ContainsKey('MaxStageFileMB') -and $cfg['MaxStageFileMB'] -match '^\d+$') { [int]$cfg['MaxStageFileMB'] } else { 4096 }
    }

    if (-not $WhatIfPreference) {
        Add-TableColumn -DatabasePath $DatabasePath -SQLDir $SQLDir -Table 'ContentItem'  -Column 'repo_staged_at'
        Add-TableColumn -DatabasePath $DatabasePath -SQLDir $SQLDir -Table 'ContentItem'  -Column 'portal_fixlet_id'
        Add-TableColumn -DatabasePath $DatabasePath -SQLDir $SQLDir -Table 'ContentCache' -Column 'note'
        # seed the ceiling key so an operator can see / tune it (INSERT OR IGNORE - never clobbers)
        Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
INSERT OR IGNORE INTO PipelineConfig (Key, Value, Description)
VALUES ('MaxStageFileMB', @v, 'Per-file download ceiling (MB) for Stage-Repository.ps1 (07-03). A prefetch file larger than this is logged and skipped, not staged.')
"@ -P @{ v = [string]$MaxStageFileMB }
    }

    $staRoot = Resolve-StagingRoot -Override $StagingRoot -Config $cfg
    if (-not $WhatIfPreference -and -not (Test-Path $staRoot)) {
        New-Item -ItemType Directory -Path $staRoot -Force | Out-Null
    }

    $cred = $Credential
    if ($null -eq $cred) {
        $cred = & (Join-Path $PSScriptRoot 'Get-BigFixCredential.ps1') -DatabasePath $DatabasePath -SQLDir $SQLDir -SqliteHelperPath $SqliteHelperPath
    }
    $irm = Get-RsIrmExtra
    $root = $BESRootUrl.TrimEnd('/')
    $siteEnc = [uri]::EscapeDataString($PortalSite)

    Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
INSERT INTO SyncRun (RunID, Type, Started_on, Status) VALUES (@r, 'RepoStage', datetime('now','localtime'), 'running')
"@ -P @{ r = $RunId }

    $items = @(Get-RsRows -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
SELECT fixlet_id, source_site, fixlet_name, is_task, portal_fixlet_id
FROM ContentItem
WHERE stage = 'live' AND (repo_staged_at IS NULL OR repo_staged_at = '')
ORDER BY fixlet_id
LIMIT $MaxItems
"@)

    $staged = 0; $skipped = 0; $discarded = 0
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('reposta-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir -Force -WhatIf:$false | Out-Null

    try {
        foreach ($it in $items) {
            $portalId = [string]$it.portal_fixlet_id
            if ([string]::IsNullOrWhiteSpace($portalId)) {
                Write-Warning "[STAGE] ContentItem $($it.fixlet_id) is 'live' but has no portal_fixlet_id - skipping"
                $skipped++
                continue
            }
            $pType = Get-FixletPathType -IsTask ([bool]([int]$it.is_task))
            $uri = "$root/api/$pType/custom/$siteEnc/$([uri]::EscapeDataString($portalId))"
            try {
                $fxml = Invoke-RestMethod -Method Get -Uri $uri -Credential $cred @irm
            } catch {
                Write-Warning "[STAGE] could not GET action script for portal fixlet $portalId : $($_.Exception.Message)"
                $skipped++
                continue
            }

            $lines = Get-ActionScriptLines -FixletXml ([string]$fxml)
            $itemDiscard = $false
            foreach ($line in $lines) {
                $pf = Read-PrefetchLine -Line $line
                if ($null -eq $pf) { continue }

                $sha1 = $pf.Sha1
                $cached = @(Get-RsRows -DatabasePath $DatabasePath -SQLDir $SQLDir `
                    -Sql "SELECT verified FROM ContentCache WHERE sha1 = @h" -P @{ h = $sha1 })
                if ($cached.Count -gt 0 -and [int]$cached[0].verified -eq 1) {
                    Write-Host "[STAGE] sha1 $sha1 already verified - skipping $($pf.FileName)"
                    $skipped++
                    continue
                }

                if ($pf.Size -gt ([long]$MaxStageFileMB * 1MB)) {
                    Write-Warning "[STAGE] $($pf.FileName) ($([math]::Round($pf.Size/1MB)) MB) exceeds MaxStageFileMB=$MaxStageFileMB - skipping"
                    $skipped++
                    continue
                }

                $dest = Join-Path $staRoot $sha1
                $finalPath = Join-Path $dest $pf.FileName

                if ($WhatIfPreference) {
                    Write-Host "[WOULD DOWNLOAD] $($pf.Url)  ->  $finalPath"
                    continue
                }

                $tmpFile = Join-Path $tmpDir ([guid]::NewGuid().ToString('N'))
                try {
                    Invoke-WebRequest -Uri $pf.Url -OutFile $tmpFile -UseBasicParsing @irm
                } catch {
                    Write-Warning "[STAGE] download failed for $($pf.Url): $($_.Exception.Message)"
                    if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
                    $skipped++
                    continue
                }

                $actualSha = (Get-FileHash -Algorithm SHA1 -Path $tmpFile).Hash.ToLowerInvariant()
                $actualLen = (Get-Item $tmpFile).Length

                if ($actualSha -ne $sha1 -or [long]$actualLen -ne [long]$pf.Size) {
                    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
                    $note = "expected sha1=$sha1 size=$($pf.Size); actual sha1=$actualSha size=$actualLen"
                    Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
INSERT OR IGNORE INTO ContentCache (sha1, filename, original_url, size_bytes, verified, note)
VALUES (@h, @f, @u, @s, 0, @n)
"@ -P @{ h = $sha1; f = $pf.FileName; u = $pf.Url; s = [string]$pf.Size; n = $note }
                    Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE ContentCache SET filename = @f, original_url = @u, verified = 0, note = @n WHERE sha1 = @h
"@ -P @{ f = $pf.FileName; u = $pf.Url; n = $note; h = $sha1 }
                    Write-RepoStageEvent -EventId 8040 -Message "Discarded a swapped/corrupt installer for portal fixlet $portalId - $note. Nothing staged."
                    Write-Warning "[STAGE] HASH MISMATCH - discarded $($pf.FileName). $note"
                    $discarded++
                    $itemDiscard = $true
                    continue
                }

                if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
                Move-Item -Path $tmpFile -Destination $finalPath -Force
                Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
INSERT OR IGNORE INTO ContentCache (sha1, filename, original_url, staged_at, size_bytes, verified, note)
VALUES (@h, @f, @u, datetime('now','localtime'), @s, 1, NULL)
"@ -P @{ h = $sha1; f = $pf.FileName; u = $pf.Url; s = [string]$pf.Size }
                Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE ContentCache SET filename = @f, original_url = @u, staged_at = datetime('now','localtime'),
    size_bytes = @s, verified = 1, note = NULL
WHERE sha1 = @h
"@ -P @{ f = $pf.FileName; u = $pf.Url; s = [string]$pf.Size; h = $sha1 }
                Write-Host "[STAGE] $($pf.FileName) -> $finalPath  (sha1 $sha1 verified)"
                $staged++
            }

            if (-not $WhatIfPreference -and -not $itemDiscard) {
                Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir `
                    -Sql "UPDATE ContentItem SET repo_staged_at = datetime('now','localtime') WHERE fixlet_id = @i AND source_site = @s" `
                    -P @{ i = [string]$it.fixlet_id; s = [string]$it.source_site }
            }
        }
    } finally {
        Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
    }

    $status = if ($discarded -gt 0) { 'partial' } else { 'success' }
    Invoke-RsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE SyncRun SET Ended_on = datetime('now','localtime'), Status = @st,
    Items_Copied = @staged, Items_Failed = @disc, Error_Count = Error_Count + @disc, Summary = @sum
WHERE RunID = @r
"@ -P @{
        st = $status; staged = [string]$staged; disc = [string]$discarded; r = $RunId
        sum = ("staged {0}, skipped {1}, discarded {2} across {3} live item(s)" -f $staged, $skipped, $discarded, $items.Count)
    }

    $log = [pscustomobject]@{
        run_id = $RunId; type = 'RepoStage'; whatif = [bool]$WhatIfPreference
        started = $started.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        ended   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        staging_root = $staRoot
        items_seen = $items.Count
        staged = $staged; skipped = $skipped; discarded = $discarded
        max_stage_file_mb = $MaxStageFileMB
        status = $status
    }
    New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null
    $logPath = Join-Path $LogDir ("repo-stage-{0}.json" -f $started.ToString('yyyyMMdd-HHmmss'))
    Set-Content -Path $logPath -Value ($log | ConvertTo-Json -Depth 6 -Compress) -Encoding UTF8 -WhatIf:$false

    Write-Host "----RUN SUMMARY----"
    Write-Host ($log | ConvertTo-Json -Depth 6 -Compress)
    Write-Host ("[DONE] Stage-Repository complete{0}." -f $(if ($WhatIfPreference) { ' [WhatIf - no writes made]' } else { '' }))
    return $log
}

# --- guarded entrypoint ------------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    $rsArgs = @{
        DatabasePath = $DatabasePath; SQLDir = $SQLDir; BESRootUrl = $BESRootUrl; PortalSite = $PortalSite
        StagingRoot = $StagingRoot; RunId = $RunId; LogDir = $LogDir; MaxItems = $MaxItems
        MaxStageFileMB = $MaxStageFileMB; Credential = $Credential
        SqliteHelperPath = $SqliteHelperPath; CoreModulePath = $CoreModulePath
    }
    Start-RepoStage @rsArgs -WhatIf:$WhatIfPreference
}
