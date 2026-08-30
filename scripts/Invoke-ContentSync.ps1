#Requires -Version 5.1
<#
.SYNOPSIS
    Content pipeline (07-03) - scheduled server-side replacement for the
    fixlet_update_tracker.ojo scan + copy loop. Scans the configured source sites for
    fixlets that are newer versions of products already in the Dereso Software Portal
    site (or brand-new arrivals), records them as `discovered` ContentItems, and - only
    for items an operator has advanced to `stage = 'ready'` (or every discovered item
    when -AutoApprove is passed, OFF by default per D-26) - performs the authoritative
    4-step copy with category + Associated_Roles MIME transfer and stamps the superseded
    portal item with exactly one X-Superseded-By MIMEField.

.DESCRIPTION
    Intent is UNCHANGED from the superseded 2026-08-01 design (old D-09 / D-10 / D-11 /
    D-16). Table names only: ContentItem / ContentCache / the shared SyncRun with a Type
    column.

    Nothing is copied by a bare run - the scan records `discovered` rows and stops.
    The copy engine runs in the same invocation immediately after the scan, but it only
    ever touches rows at `stage = 'ready'` unless -AutoApprove is given.

    -WhatIf: the read-only scan + version diff still run (POST /api/query and GET are
    reads); the script reports what WOULD be recorded / copied and makes ZERO DB writes,
    ZERO POST/PUT calls and no Start-ScheduledTask call.

    Additive ContentItem columns (idempotent, PRAGMA table_info-gated, same mechanism as
    the D-18 Map migration - the shared Initialize-AutomationDb.ps1 is NOT touched):
      discovery_kind    'update' | 'new'  - the 07-04 Content Queue surfaces both
      portal_fixlet_id  id of the new portal fixlet a copy created (Stage-Repository.ps1
                        reads this to fetch the action script)
      reject_reason     why a copy failed (stage='rejected')
      repo_staged_at    set by Stage-Repository.ps1 once every prefetch line is staged

.PARAMETER DatabasePath   AutomationState.db on the root server.
.PARAMETER SQLDir         Directory containing sqlite3.exe directly (no arch subfolder).
.PARAMETER BESRootUrl     BigFix REST base URL. Falls back to PipelineConfig.BESRootUrl.
.PARAMETER SourceSites    Source sites to scan (array or comma-separated). Falls back to
                          PipelineConfig.ContentSourceSites, seeded on first run with the
                          fixlet_update_tracker.ojo PORTAL_CONFIG.sourceSites list.
.PARAMETER PortalSite     Portal custom site. Default 'Dereso Software Portal'.
.PARAMETER RunId          Run id. Defaults to a fresh GUID.
.PARAMETER LogDir         Per-run JSON log directory. Defaults to <repo>\logs.
.PARAMETER AutoApprove    Copy every `discovered` row, not just `ready` ones. OFF by
                          default (D-26 rollout).
.PARAMETER MaxItems       Cap on how many items the copy engine processes per run.
.PARAMETER SourceSiteType REST container segment for the source sites' GET path
                          (external | custom | operator | master). Default 'external'.
.PARAMETER Credential     BigFix operator [pscredential]. Fetched from AKeyless via
                          Get-BigFixCredential.ps1 when omitted. Tests pass a dummy.
.PARAMETER SqliteHelperPath  Shared Dashboard_4_samples\Sqlite-Helper.ps1.
.PARAMETER CoreModulePath    scripts\ContentSyncCore.psm1.

.NOTES
    PowerShell 5.1+ (root server prefers pwsh 7 - assumption A2). Error codes 6900-6999.
      6900  ContentSourceSites unresolved and no fallback
      6910  Sqlite-Helper.ps1 / ContentSyncCore.psm1 not found
    Event Log (Source 'DereseSoftwarePortal', LogName Application):
      8030  a copy step failed for one item (item rejected, run continues)
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()][string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db',
    [Parameter()][string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',
    [Parameter()][string]$BESRootUrl,
    [Parameter()][string[]]$SourceSites,
    [Parameter()][string]$PortalSite = 'Dereso Software Portal',
    [Parameter()][string]$RunId = ([guid]::NewGuid().ToString()),
    [Parameter()][string]$LogDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'),
    [Parameter()][switch]$AutoApprove,
    [Parameter()][int]$MaxItems = 25,
    [Parameter()][string]$SourceSiteType = 'external',
    [Parameter()][pscredential]$Credential,
    [Parameter()][string]$SqliteHelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Dashboard_4_samples\Sqlite-Helper.ps1'),
    [Parameter()][string]$CoreModulePath = (Join-Path $PSScriptRoot 'ContentSyncCore.psm1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:EventLogSource = 'DereseSoftwarePortal'

# The site list fixlet_update_tracker.ojo PORTAL_CONFIG.sourceSites carries - seeded into
# PipelineConfig.ContentSourceSites on first run so pipeline and dashboard agree.
$script:DefaultSourceSites = @('BigFix Software Installer Library for Windows')

# --- load shared helper + pure module -------------------------------------------
if (-not (Test-Path $SqliteHelperPath)) { throw "6910: Sqlite-Helper.ps1 not found at: $SqliteHelperPath" }
. $SqliteHelperPath
if (-not (Test-Path $CoreModulePath)) { throw "6910: ContentSyncCore.psm1 not found at: $CoreModulePath" }
Import-Module $CoreModulePath -Force

# =============================================================================
# helpers
# =============================================================================

function Write-ContentSyncEvent {
    param([int]$EventId, [string]$Message, [string]$EntryType = 'Error')
    try {
        Write-EventLog -LogName Application -Source $script:EventLogSource -EntryType $EntryType `
            -EventId $EventId -Message $Message
    } catch { }
}

function Get-CsRows {
    param([Parameter(Mandatory)][string]$DatabasePath, [Parameter(Mandatory)][string]$SQLDir,
          [Parameter(Mandatory)][string]$Sql, [hashtable]$P = @{})
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P
    return @($r | ForEach-Object { $_ })
}

function Invoke-CsWrite {
    # Single WhatIf write gate: every DB mutation goes through here.
    param([Parameter(Mandatory)][string]$DatabasePath, [Parameter(Mandatory)][string]$SQLDir,
          [Parameter(Mandatory)][string]$Sql, [hashtable]$P = @{}, [switch]$Force)
    if ($WhatIfPreference -and -not $Force) { return }
    Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P | Out-Null
}

function Add-ContentItemColumn {
    param([Parameter(Mandatory)][string]$DatabasePath, [Parameter(Mandatory)][string]$SQLDir,
          [Parameter(Mandatory)][string]$Column, [string]$Type = 'TEXT')
    $cols = @(Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA table_info(ContentItem)" |
                ForEach-Object { $_.name })
    if ($cols -notcontains $Column) {
        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
            -Sql "ALTER TABLE ContentItem ADD COLUMN $Column $Type" | Out-Null
    }
}

function Get-CsIrmExtra {
    $extra = @{}
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $extra['SkipCertificateCheck'] = $true
    } else {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }
    return $extra
}

function Get-CsCredential {
    param([pscredential]$Credential, [string]$DatabasePath, [string]$SQLDir, [string]$SqliteHelperPath)
    if ($Credential) { return $Credential }
    return & (Join-Path $PSScriptRoot 'Get-BigFixCredential.ps1') `
        -DatabasePath $DatabasePath -SQLDir $SQLDir -SqliteHelperPath $SqliteHelperPath
}

function ConvertFrom-CsQueryResponse {
    # Normalise POST /api/query result to a flat string[] of answer tuples. Accepts the
    # { result: [...] } JSON shape (RESEARCH A6) and the <BESAPI>...<Answer> XML shape.
    param($Response)
    if ($null -eq $Response) { return @() }
    if ($Response.PSObject.Properties['result']) { return @($Response.result | ForEach-Object { [string]$_ }) }
    $xml = $null
    if ($Response -is [xml]) { $xml = $Response }
    elseif ($Response -is [string]) { try { $xml = [xml]$Response } catch { return @() } }
    if ($null -eq $xml) { return @() }
    $ans = $xml.SelectNodes('//Answer')
    if ($ans) { return @($ans | ForEach-Object { [string]$_.InnerText }) }
    return @()
}

function Invoke-BigFixQuery {
    param([Parameter(Mandatory)][string]$BESRootUrl, [Parameter(Mandatory)][string]$Relevance,
          [pscredential]$Credential, [hashtable]$IrmExtra = @{})
    $uri = ($BESRootUrl.TrimEnd('/')) + '/api/query'
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Body @{ relevance = $Relevance } -Credential $Credential @IrmExtra
    return (ConvertFrom-CsQueryResponse -Response $resp)
}

function Get-SiteInventory {
    <#
      One row per fixlet/task in $Site: id, name, site, is_task, container. Ported from
      fixlet_update_tracker.ojo scanNextSite (L1146-1175) - the \x1F-delimited tuple over
      `bes fixlets whose (name of site of it = "..." and (fixlet flag of it or task flag
      of it))`.
    #>
    param([Parameter(Mandatory)][string]$BESRootUrl, [Parameter(Mandatory)][string]$Site,
          [pscredential]$Credential, [hashtable]$IrmExtra = @{})

    $d = [string][char]0x1F
    $safe = $Site.Replace('"', '""')
    $rel = @"
(id of it as string & "$d" & name of it & "$d" & name of site of it & "$d" & (if task flag of it then "task" else "fixlet") & "$d" & (if custom site flag of site of it then "custom" else if external site flag of site of it then "external" else if operator site flag of site of it then "operator" else "master")) of bes fixlets whose (name of site of it = "$safe" and (fixlet flag of it or task flag of it))
"@
    $tuples = Invoke-BigFixQuery -BESRootUrl $BESRootUrl -Relevance $rel -Credential $Credential -IrmExtra $IrmExtra
    $out = New-Object System.Collections.ArrayList
    foreach ($t in $tuples) {
        $p = ([string]$t).Split($d)
        if ($p.Count -lt 4) { continue }
        [void]$out.Add([pscustomobject]@{
            id        = $p[0]
            name      = $p[1]
            site      = $p[2]
            is_task   = ($p[3] -eq 'task')
            container = if ($p.Count -ge 5 -and $p[4]) { $p[4] } else { 'external' }
        })
    }
    return $out.ToArray()
}

function Build-DiscoverySet {
    <#
      Key both sides on Get-StrippedName. A source product present on the portal side and
      strictly newer (Compare-FixletVersion > 0 against ANY portal match) -> kind='update'.
      A source product with no portal match -> kind='new'. Portal-only products are
      ignored. Parity with fixlet_update_tracker.ojo buildScanResults.
    #>
    param([object[]]$SourceItems, [object[]]$PortalItems)

    $portalMap = @{}
    foreach ($p in @($PortalItems)) {
        $k = Get-StrippedName -Name ([string]$p.name)
        if (-not $portalMap.ContainsKey($k)) { $portalMap[$k] = New-Object System.Collections.ArrayList }
        [void]$portalMap[$k].Add($p)
    }

    $out = New-Object System.Collections.ArrayList
    foreach ($s in @($SourceItems)) {
        $k  = Get-StrippedName -Name ([string]$s.name)
        $sv = Get-ExtractedVersion -Name ([string]$s.name)
        if ($portalMap.ContainsKey($k)) {
            $newer = $false
            foreach ($pm in $portalMap[$k]) {
                $pv = Get-ExtractedVersion -Name ([string]$pm.name)
                if ((Compare-FixletVersion -Left $sv -Right $pv) -gt 0) { $newer = $true }
            }
            if ($newer) {
                [void]$out.Add([pscustomobject]@{
                    fixlet_id = [string]$s.id; source_site = [string]$s.site
                    fixlet_name = [string]$s.name; is_task = [int][bool]$s.is_task; kind = 'update'
                })
            }
        } else {
            [void]$out.Add([pscustomobject]@{
                fixlet_id = [string]$s.id; source_site = [string]$s.site
                fixlet_name = [string]$s.name; is_task = [int][bool]$s.is_task; kind = 'new'
            })
        }
    }
    return $out.ToArray()
}

function Get-CsFixletIdFromResponse {
    param($Response)
    if ($null -eq $Response) { return $null }
    if ($Response -is [string]) {
        $m = [regex]::Match($Response, '<Fixlet[^>]*\bID="(\d+)"'); if ($m.Success) { return $m.Groups[1].Value }
        $m = [regex]::Match($Response, '<Task[^>]*\bID="(\d+)"');   if ($m.Success) { return $m.Groups[1].Value }
        $m = [regex]::Match($Response, '<ID>(\d+)</ID>');           if ($m.Success) { return $m.Groups[1].Value }
        return $null
    }
    if ($Response -is [xml]) {
        $n = $Response.SelectSingleNode('//*[@ID]'); if ($n) { return $n.GetAttribute('ID') }
    }
    foreach ($p in 'id','ID','Id') { if ($Response.PSObject.Properties[$p]) { return [string]$Response.$p } }
    return $null
}

function Get-XmlText {
    param([xml]$Xml, [string]$Tag)
    $n = $Xml.GetElementsByTagName($Tag)
    if ($n.Count -gt 0) { return [string]$n[0].InnerText }
    return ''
}

function Get-MimeFieldValue {
    param([string]$RawXml, [string]$FieldName)
    $rx = [regex]::new('<MIMEField>\s*<Name>\s*' + [regex]::Escape($FieldName) + '\s*</Name>\s*<Value>([\s\S]*?)</Value>\s*</MIMEField>',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $m = $rx.Match([string]$RawXml)
    if ($m.Success) {
        $v = $m.Groups[1].Value
        return [System.Net.WebUtility]::HtmlDecode($v)
    }
    return ''
}

function New-PortalCopyXml {
    <#
      Build the NEW portal object XML FROM SCRATCH (copier.ojo pattern - never by mutating
      fetched Task XML, memory bigfix-task-to-fixlet-post). Carries the source relevance +
      action script, the resolved category, and the Associated_Roles MIME field.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceXml,
        [string]$Category,
        [string]$AssociatedRoles,
        [string]$SourceId
    )
    $sx = [xml]$SourceXml
    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }

    $title = Get-XmlText -Xml $sx -Tag 'Title'
    $descNodes = $sx.GetElementsByTagName('Description')
    $descInner = if ($descNodes.Count -gt 0) { $descNodes[0].InnerXml } else { '' }

    $relNodes = $sx.GetElementsByTagName('Relevance')
    $relParts = @()
    foreach ($r in $relNodes) { $relParts += (& $esc $r.InnerText) }
    if ($relParts.Count -eq 0) { $relParts = @('true') }

    $asNodes = $sx.GetElementsByTagName('ActionScript')
    $actionScript = if ($asNodes.Count -gt 0) { $asNodes[0].InnerText } else { '' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">')
    [void]$sb.AppendLine('<Fixlet>')
    [void]$sb.AppendLine("<Title>$(& $esc $title)</Title>")
    [void]$sb.AppendLine("<Description>$descInner</Description>")
    foreach ($rp in $relParts) { [void]$sb.AppendLine("<Relevance>$rp</Relevance>") }
    [void]$sb.AppendLine("<Category>$(& $esc $Category)</Category>")
    [void]$sb.AppendLine('<Source>Internal</Source>')
    [void]$sb.AppendLine("<SourceID>$(& $esc $SourceId)</SourceID>")
    [void]$sb.AppendLine("<SourceReleaseDate>$(Get-Date -Format 'yyyy-MM-dd')</SourceReleaseDate>")
    [void]$sb.AppendLine('<SourceSeverity></SourceSeverity>')
    [void]$sb.AppendLine('<CVENames></CVENames>')
    [void]$sb.AppendLine('<SANSID></SANSID>')
    if (-not [string]::IsNullOrWhiteSpace($AssociatedRoles)) {
        [void]$sb.AppendLine("<MIMEField><Name>Associated_Roles</Name><Value>$(& $esc $AssociatedRoles)</Value></MIMEField>")
    }
    [void]$sb.AppendLine('<MIMEField><Name>x-content-sync</Name><Value>07-03 Invoke-ContentSync.ps1</Value></MIMEField>')
    [void]$sb.AppendLine('<Domain>BESC</Domain>')
    [void]$sb.AppendLine('<DefaultAction ID="Action1">')
    [void]$sb.AppendLine("<ActionScript MIMEType=""application/x-Fixlet-Windows-Shell"">$(& $esc $actionScript)</ActionScript>")
    [void]$sb.AppendLine('</DefaultAction>')
    [void]$sb.AppendLine('</Fixlet>')
    [void]$sb.AppendLine('</BES>')
    return $sb.ToString()
}

function Invoke-CopyEngine {
    <#
      4-step copy per fixlet_update_tracker.ojo copyNextItem (L1533-1614), partial-failure
      model (recurse on both branches -> here: continue the loop on any step failure):
        1. GET the superseded portal item XML (category + Associated_Roles source)
        2. GET the source item XML (SINGULAR path, Get-FixletPathType by is_task)
        3. POST the from-scratch portal XML to fixlets/custom/<PortalSite>  (PLURAL)
        4. PUT the superseded portal item back with New-SupersededXml applied  (SINGULAR)
    #>
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$SQLDir,
        [Parameter(Mandatory)][string]$BESRootUrl,
        [Parameter(Mandatory)][string]$PortalSite,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$SourceSiteType,
        [Parameter(Mandatory)][bool]$AutoApprove,
        [Parameter(Mandatory)][int]$MaxItems,
        [pscredential]$Credential,
        [hashtable]$IrmExtra = @{}
    )

    $root    = $BESRootUrl.TrimEnd('/')
    $siteEnc = [uri]::EscapeDataString($PortalSite)
    $stages  = if ($AutoApprove) { @("'discovered'", "'ready'") } else { @("'ready'") }
    $inList  = $stages -join ','

    $rows = @(Get-CsRows -DatabasePath $DatabasePath -SQLDir $SQLDir `
        -Sql "SELECT fixlet_id, source_site, fixlet_name, is_task, stage FROM ContentItem WHERE stage IN ($inList) ORDER BY fixlet_id LIMIT $MaxItems")

    $copied = 0; $failed = 0
    if ($rows.Count -eq 0) { return [pscustomobject]@{ Copied = 0; Failed = 0 } }

    # portal inventory keyed by stripped name -> the item a copy supersedes
    $portalInv = @(Get-SiteInventory -BESRootUrl $BESRootUrl -Site $PortalSite -Credential $Credential -IrmExtra $IrmExtra)
    $portalByKey = @{}
    foreach ($pi in $portalInv) {
        $k = Get-StrippedName -Name ([string]$pi.name)
        if (-not $portalByKey.ContainsKey($k)) { $portalByKey[$k] = $pi }
    }

    foreach ($row in $rows) {
        $itemId   = [string]$row.fixlet_id
        $itemSite = [string]$row.source_site
        $isTask   = [bool]([int]$row.is_task)
        $srcType  = Get-FixletPathType -IsTask $isTask
        $key      = Get-StrippedName -Name ([string]$row.fixlet_name)
        $portalMatch = if ($portalByKey.ContainsKey($key)) { $portalByKey[$key] } else { $null }

        try {
            # --- step 1: GET superseded portal XML (if any) ---
            $portalXml = $null; $category = ''; $roles = ''
            if ($portalMatch) {
                $pType = Get-FixletPathType -IsTask ([bool]$portalMatch.is_task)
                $pUri  = "$root/api/$pType/custom/$siteEnc/$([uri]::EscapeDataString([string]$portalMatch.id))"
                $portalXml = Invoke-RestMethod -Method Get -Uri $pUri -Credential $Credential @IrmExtra
                $category  = Get-MimeFieldValue -RawXml ([string]$portalXml) -FieldName 'Category'
                if ([string]::IsNullOrWhiteSpace($category)) {
                    try { $category = Get-XmlText -Xml ([xml][string]$portalXml) -Tag 'Category' } catch { $category = '' }
                }
                $roles = Get-MimeFieldValue -RawXml ([string]$portalXml) -FieldName 'Associated_Roles'
            }

            # --- step 2: GET source XML (SINGULAR path) ---
            $srcUri = "$root/api/$srcType/$SourceSiteType/$([uri]::EscapeDataString($itemSite))/$([uri]::EscapeDataString($itemId))"
            $sourceXml = Invoke-RestMethod -Method Get -Uri $srcUri -Credential $Credential @IrmExtra

            # --- build the from-scratch portal XML ---
            $newXml = New-PortalCopyXml -SourceXml ([string]$sourceXml) -Category $category `
                -AssociatedRoles $roles -SourceId $itemId

            if ($WhatIfPreference) {
                Write-Host "[WOULD POST] fixlets/custom/$PortalSite  (item $itemId, kind copy)"
                if ($portalMatch) {
                    Write-Host "[WOULD PUT ] $($srcType)/custom/$PortalSite/$($portalMatch.id)  (X-Superseded-By stamp)"
                }
                continue
            }

            # --- step 3: POST to the PLURAL create path ---
            $postUri = "$root/api/fixlets/custom/$siteEnc"
            $postResp = Invoke-RestMethod -Method Post -Uri $postUri -Credential $Credential `
                -Body $newXml -ContentType 'application/xml' @IrmExtra
            $newId = Get-CsFixletIdFromResponse -Response $postResp
            if (-not $newId) { throw "POST to $postUri succeeded but no new fixlet id could be parsed from the response." }

            # --- step 4: PUT the superseded portal item (SINGULAR path) ---
            if ($portalMatch) {
                $pType = Get-FixletPathType -IsTask ([bool]$portalMatch.is_task)
                $stampXml = New-SupersededXml -FixletXml ([string]$portalXml) -SupersededByValue $newId
                $putUri = "$root/api/$pType/custom/$siteEnc/$([uri]::EscapeDataString([string]$portalMatch.id))"
                Invoke-RestMethod -Method Put -Uri $putUri -Credential $Credential `
                    -Body $stampXml -ContentType 'application/xml' @IrmExtra | Out-Null
            }

            Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE ContentItem SET stage = 'live', copied_at = datetime('now','localtime'),
    category = @cat, roles = @roles, portal_fixlet_id = @pid, reject_reason = NULL
WHERE fixlet_id = @id AND source_site = @site
"@ -P @{ cat = $category; roles = $roles; pid = [string]$newId; id = $itemId; site = $itemSite }
            $copied++
            Write-Host "[COPY] $itemId '$($row.fixlet_name)' -> portal fixlet $newId"
        } catch {
            $failed++
            $reason = $_.Exception.Message
            if ($reason.Length -gt 500) { $reason = $reason.Substring(0, 500) }
            if (-not $WhatIfPreference) {
                Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE ContentItem SET stage = 'rejected', reject_reason = @r
WHERE fixlet_id = @id AND source_site = @site
"@ -P @{ r = $reason; id = $itemId; site = $itemSite }
                Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir `
                    -Sql "UPDATE SyncRun SET Error_Count = Error_Count + 1 WHERE RunID = @r" -P @{ r = $RunId }
            }
            Write-ContentSyncEvent -EventId 8030 -Message "Content copy FAILED for item '$itemId' (site '$itemSite'): $reason"
            Write-Warning "[COPY] item $itemId FAILED - $reason; continuing with the next item"
        }
    }
    return [pscustomobject]@{ Copied = $copied; Failed = $failed }
}

# =============================================================================
# main
# =============================================================================

function Start-ContentSync {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$SQLDir,
        [string]$BESRootUrl,
        [string[]]$SourceSites,
        [string]$PortalSite = 'Dereso Software Portal',
        [string]$RunId = ([guid]::NewGuid().ToString()),
        [string]$LogDir,
        [bool]$AutoApprove = $false,
        [int]$MaxItems = 25,
        [string]$SourceSiteType = 'external',
        [pscredential]$Credential,
        [string]$SqliteHelperPath,
        [string]$CoreModulePath
    )

    $started = (Get-Date).ToUniversalTime()
    if (-not $LogDir) { $LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs' }

    # --- config -------------------------------------------------------------
    $cfg = @{}
    foreach ($r in (Get-CsRows -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "SELECT Key, Value FROM PipelineConfig")) {
        $cfg[[string]$r.Key] = [string]$r.Value
    }

    if (-not $BESRootUrl) {
        if ($cfg.ContainsKey('BESRootUrl') -and $cfg['BESRootUrl']) { $BESRootUrl = $cfg['BESRootUrl'] }
        else { $BESRootUrl = 'https://localhost:52311' }
    }

    $sites = @()
    if ($SourceSites -and $SourceSites.Count -gt 0) {
        $sites = @($SourceSites | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } elseif ($cfg.ContainsKey('ContentSourceSites') -and -not [string]::IsNullOrWhiteSpace($cfg['ContentSourceSites'])) {
        $sites = @($cfg['ContentSourceSites'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
        $sites = @($script:DefaultSourceSites)
        # seed the key so the dashboard and the pipeline share one list
        Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
INSERT OR IGNORE INTO PipelineConfig (Key, Value, Description)
VALUES ('ContentSourceSites', @v, 'Comma-separated BigFix source sites the content pipeline scans for newer/added product fixlets (07-03). Seeded from fixlet_update_tracker.ojo PORTAL_CONFIG.sourceSites.')
"@ -P @{ v = ($sites -join ',') }
    }
    if ($sites.Count -eq 0) { throw "6900: no source sites - pass -SourceSites or set PipelineConfig.ContentSourceSites." }

    # --- additive ContentItem columns (idempotent; skipped under -WhatIf) --
    if (-not $WhatIfPreference) {
        foreach ($col in 'discovery_kind','portal_fixlet_id','reject_reason','repo_staged_at') {
            Add-ContentItemColumn -DatabasePath $DatabasePath -SQLDir $SQLDir -Column $col
        }
    }

    $cred = Get-CsCredential -Credential $Credential -DatabasePath $DatabasePath -SQLDir $SQLDir -SqliteHelperPath $SqliteHelperPath
    $irm  = Get-CsIrmExtra

    # --- SyncRun open -----------------------------------------------------
    Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
INSERT INTO SyncRun (RunID, Type, Started_on, Status) VALUES (@r, 'ContentSync', datetime('now','localtime'), 'running')
"@ -P @{ r = $RunId }

    # --- scan -----------------------------------------------------------
    $sourceItems = New-Object System.Collections.ArrayList
    $siteN = 0
    foreach ($site in $sites) {
        $siteN++
        $inv = @(Get-SiteInventory -BESRootUrl $BESRootUrl -Site $site -Credential $cred -IrmExtra $irm)
        foreach ($x in $inv) { [void]$sourceItems.Add($x) }
        Write-Host ("[SCAN] site {0} of {1}: '{2}' - {3} fixlet(s)/task(s) ({4} so far)" -f `
            $siteN, $sites.Count, $site, @($inv).Count, $sourceItems.Count)
    }
    $portalItems = @(Get-SiteInventory -BESRootUrl $BESRootUrl -Site $PortalSite -Credential $cred -IrmExtra $irm)
    Write-Host ("[SCAN] portal site '{0}' - {1} fixlet(s)/task(s)" -f $PortalSite, @($portalItems).Count)

    # --- diff ---------------------------------------------------------
    $disco = @(Build-DiscoverySet -SourceItems @($sourceItems) -PortalItems @($portalItems))
    $nUpdate = @($disco | Where-Object { $_.kind -eq 'update' }).Count
    $nNew    = @($disco | Where-Object { $_.kind -eq 'new' }).Count
    Write-Host ("[DIFF] {0} discovered ({1} update, {2} new arrival)" -f $disco.Count, $nUpdate, $nNew)

    foreach ($d in $disco) {
        if ($WhatIfPreference) {
            Write-Host ("[WOULD RECORD] discovered/{0}: {1} '{2}' (site '{3}')" -f $d.kind, $d.fixlet_id, $d.fixlet_name, $d.source_site)
            continue
        }
        # D-12 discipline: INSERT OR IGNORE on the composite key, then a guarded UPDATE
        # that refreshes name/kind/is_task but ONLY while the row is still 'discovered'.
        # A delete-and-reinsert upsert is never used (it would drop an advanced stage).
        Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
INSERT OR IGNORE INTO ContentItem (fixlet_id, source_site, fixlet_name, stage, is_task, discovery_kind)
VALUES (@id, @site, @name, 'discovered', @task, @kind)
"@ -P @{ id = $d.fixlet_id; site = $d.source_site; name = $d.fixlet_name; task = [string]([int]$d.is_task); kind = $d.kind }
        Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE ContentItem SET fixlet_name = @name, is_task = @task, discovery_kind = @kind
WHERE fixlet_id = @id AND source_site = @site AND stage = 'discovered'
"@ -P @{ name = $d.fixlet_name; task = [string]([int]$d.is_task); kind = $d.kind; id = $d.fixlet_id; site = $d.source_site }
    }

    # --- copy engine (gated on stage='ready' unless -AutoApprove) --------
    $copyResult = Invoke-CopyEngine -DatabasePath $DatabasePath -SQLDir $SQLDir -BESRootUrl $BESRootUrl `
        -PortalSite $PortalSite -RunId $RunId -SourceSiteType $SourceSiteType -AutoApprove $AutoApprove `
        -MaxItems $MaxItems -Credential $cred -IrmExtra $irm

    # --- chain to the staging task (skipped under -WhatIf) --------------
    if (-not $WhatIfPreference -and $copyResult.Copied -gt 0) {
        try {
            Start-ScheduledTask -TaskName 'DeresoRepoStage' -ErrorAction Stop
            Write-Host "[CHAIN] started DeresoRepoStage"
        } catch {
            Write-Warning "[CHAIN] could not start DeresoRepoStage (register it via Register-AutomationTasks.ps1): $($_.Exception.Message)"
        }
    }

    # --- SyncRun close + JSON log -------------------------------------
    $errCount = 0
    if (-not $WhatIfPreference) {
        $er = @(Get-CsRows -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "SELECT Error_Count AS n FROM SyncRun WHERE RunID = @r" -P @{ r = $RunId })
        if ($er.Count -gt 0) { $errCount = [int]$er[0].n }
    }
    $status = if ($errCount -gt 0) { 'partial' } else { 'success' }

    Invoke-CsWrite -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql @"
UPDATE SyncRun SET Ended_on = datetime('now','localtime'), Status = @st,
    Items_Discovered = @disc, Items_Copied = @cop, Items_Failed = @fail, Summary = @sum
WHERE RunID = @r
"@ -P @{
        st = $status; disc = [string]$disco.Count; cop = [string]$copyResult.Copied
        fail = [string]$copyResult.Failed; r = $RunId
        sum = ("scanned {0} source site(s); {1} discovered ({2} update / {3} new); {4} copied, {5} failed" -f `
            $sites.Count, $disco.Count, $nUpdate, $nNew, $copyResult.Copied, $copyResult.Failed)
    }

    $log = [pscustomobject]@{
        run_id           = $RunId
        type             = 'ContentSync'
        whatif           = [bool]$WhatIfPreference
        query_mechanism  = 'POST /api/query (session relevance, \x1F tuple)'
        started          = $started.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        ended            = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        source_sites     = $sites
        portal_site      = $PortalSite
        items_discovered = $disco.Count
        items_update     = $nUpdate
        items_new        = $nNew
        items_copied     = $copyResult.Copied
        items_failed     = $copyResult.Failed
        status           = $status
        auto_approve     = [bool]$AutoApprove
    }

    New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null
    $logPath = Join-Path $LogDir ("content-sync-{0}.json" -f $started.ToString('yyyyMMdd-HHmmss'))
    Set-Content -Path $logPath -Value ($log | ConvertTo-Json -Depth 6 -Compress) -Encoding UTF8 -WhatIf:$false

    Write-Host "----RUN SUMMARY----"
    Write-Host ($log | ConvertTo-Json -Depth 6 -Compress)
    Write-Host ("[DONE] Invoke-ContentSync complete{0}." -f $(if ($WhatIfPreference) { ' [WhatIf - no writes made]' } else { '' }))
    return $log
}

# --- guarded entrypoint: only runs when the script is invoked, not dot-sourced ---
if ($MyInvocation.InvocationName -ne '.') {
    $csArgs = @{
        DatabasePath = $DatabasePath; SQLDir = $SQLDir; BESRootUrl = $BESRootUrl
        SourceSites = $SourceSites; PortalSite = $PortalSite; RunId = $RunId; LogDir = $LogDir
        AutoApprove = [bool]$AutoApprove; MaxItems = $MaxItems; SourceSiteType = $SourceSiteType
        Credential = $Credential; SqliteHelperPath = $SqliteHelperPath; CoreModulePath = $CoreModulePath
    }
    Start-ContentSync @csArgs -WhatIf:$WhatIfPreference
}
