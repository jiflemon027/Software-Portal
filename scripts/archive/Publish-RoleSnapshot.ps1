#Requires -Version 5.1
<#
.SYNOPSIS
    Per-region role snapshot publisher (07-02). Emits one compact JSON snapshot per
    published region into the BigFix Custom Repository roleref subtree, writes a matching
    .sha1 manifest, records Snapshot + SyncRun rows, and (Task 2) re-PUTs each region's
    policy Fixlet so its prefetch line always names the hash on disk right now.

.DESCRIPTION
    Distribution mechanism that replaces the rejected per-ComputerID design (D-02/D-11).
    Region scoping is the endpoint's job (its own GPC_Sub_Name client setting); this
    script only decides WHICH regions get a file, and never emits a ComputerID.

    Output directory precedence:
      1. -OutputDir parameter
      2. PipelineConfig.SnapshotOutputDir  (when non-blank)
      3. (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server').wwwRootFolder
         + '\Uploads\CustomRepository\SoftwarePortal\roleref'
    A registry read failure with no override set is a hard abort.

    Per published region it writes:
      roleref-<region-lc>-<yyyyMMdd>.json      (dated)
      roleref-<region-lc>-latest.json          (pointer, byte-identical copy)
      roleref-<region-lc>-latest.json.sha1     ("<sha1>  <leaf>", ASCII, no newline)

    "Published region" = a region with at least one Active RolePublication row, OR every
    Active region when a RolePublication row has a NULL RegionID (all regions).

    -WhatIf computes every snapshot, reports the file name / size / sha1 that WOULD be
    written, writes the JSON run log, and touches neither the roleref directory nor the DB.

.PARAMETER DatabasePath
    AutomationState.db on the root server.

.PARAMETER SQLDir
    Directory containing sqlite3.exe directly (no arch subfolder).

.PARAMETER Region
    Publish only this region (must be an exact, Active Region.GPC_Sub_Name). Omit to
    publish every region that has at least one Active RolePublication row.

.PARAMETER OutputDir
    Override the roleref output directory (see precedence above).

.PARAMETER RunId
    Publish run id. Defaults to a fresh GUID. Copied into snapshot.run_id, Snapshot.RunID
    and the SyncRun row.

.PARAMETER LogDir
    Directory the per-run JSON log is written to. Defaults to <repo>\logs.

.PARAMETER SkipFixletPut
    Skip the BigFix policy-Fixlet POST/PUT lifecycle (Task 2). CI and -WhatIf use this.

.PARAMETER SqliteHelperPath
    Path to the single shared Sqlite-Helper.ps1 (dot-sourced from Dashboard_4_samples\).

.PARAMETER SnapshotModulePath
    Path to SnapshotBuild.psm1. Defaults next to this script.

.NOTES
    PowerShell 5.1+ (root server prefers pwsh 7 - assumption A2). Error codes 6800-6899.
      6800  registry-derived output dir unreadable and no override
      6810  unknown / inactive -Region
      6820  snapshot build / write failure
      6830  policy-Fixlet template missing

.PARAMETER Credential
    BigFix operator [pscredential] for the policy-Fixlet POST/PUT. When omitted it is
    fetched from AKeyless via scripts/Get-BigFixCredential.ps1. Tests pass a dummy so
    Invoke-RestMethod can be mocked without a live AKeyless round-trip.

.PARAMETER BESSite
    Custom site the policy Fixlets live in. Defaults to PipelineConfig.RoleRefSite, then
    'Dereso Software Portal'.

.PARAMETER TemplatePath
    Path to bes/RoleRef-Policy-template.bes. Defaults to <repo>\bes\RoleRef-Policy-template.bes.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$DatabasePath = 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db',

    [Parameter()]
    [string]$SQLDir = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite',

    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [string]$RunId = ([guid]::NewGuid().ToString()),

    [Parameter()]
    [string]$LogDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'),

    [Parameter()]
    [switch]$SkipFixletPut,

    [Parameter()]
    [string]$SqliteHelperPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Dashboard_4_samples\Sqlite-Helper.ps1'),

    [Parameter()]
    [string]$SnapshotModulePath = (Join-Path $PSScriptRoot 'SnapshotBuild.psm1'),

    [Parameter()]
    [pscredential]$Credential,

    [Parameter()]
    [string]$BESSite,

    [Parameter()]
    [string]$TemplatePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bes\RoleRef-Policy-template.bes')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$EventLogSource = 'DereseSoftwarePortal'

# --- helpers ------------------------------------------------------------------

function Get-Rows {
    # Flatten Sqlite-Helper's (return ,$rows) wrapper so multi-row .Count is correct.
    param([string]$Sql, [hashtable]$P = @{})
    $r = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P
    return @($r | ForEach-Object { $_ })
}

function Invoke-DbWrite {
    param([string]$Sql, [hashtable]$P = @{})
    if ($WhatIfPreference) { return }
    Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $Sql -Parameters $P | Out-Null
}

function Write-PublishEvent {
    param([int]$EventId, [string]$Message, [string]$EntryType = 'Error')
    try {
        Write-EventLog -LogName Application -Source $EventLogSource -EntryType $EntryType -EventId $EventId -Message $Message -WhatIf:$false
    } catch { }
}

function Resolve-OutputDir {
    param([hashtable]$Config)
    if ($OutputDir) { return $OutputDir }
    if ($Config.ContainsKey('SnapshotOutputDir') -and -not [string]::IsNullOrWhiteSpace($Config['SnapshotOutputDir'])) {
        return $Config['SnapshotOutputDir']
    }
    try {
        $www = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server' -ErrorAction Stop).wwwRootFolder
    } catch {
        $www = $null
    }
    if ([string]::IsNullOrWhiteSpace($www)) {
        throw "6800: cannot read wwwRootFolder from HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server and no -OutputDir / PipelineConfig.SnapshotOutputDir override is set."
    }
    return (Join-Path $www 'Uploads\CustomRepository\SoftwarePortal\roleref')
}

function Get-FixletIdFromResponse {
    param($Response)
    if ($null -eq $Response) { return $null }
    # BigFix POST /api/fixlets/custom/<site> returns <BESAPI><Fixlet ... ID="N"> (XML) or,
    # with Accept: application/json, { fixlet: { id: N } }. Cover both + a raw int.
    if ($Response -is [string]) {
        $m = [regex]::Match($Response, '<Fixlet[^>]*\bID="(\d+)"')
        if ($m.Success) { return $m.Groups[1].Value }
        $m = [regex]::Match($Response, '<ID>(\d+)</ID>')
        if ($m.Success) { return $m.Groups[1].Value }
        return $null
    }
    if ($Response -is [xml] -or $Response.PSObject.Properties['BESAPI']) {
        $node = $Response.SelectSingleNode('//Fixlet[@ID]')
        if ($node) { return $node.GetAttribute('ID') }
    }
    foreach ($p in 'id','ID','Id') {
        if ($Response.PSObject.Properties[$p]) { return [string]$Response.$p }
    }
    if ($Response.PSObject.Properties['fixlet'] -and $Response.fixlet.PSObject.Properties['id']) {
        return [string]$Response.fixlet.id
    }
    return $null
}

function Invoke-RoleRefFixletLifecycle {
    <#
      For each published region: render bes/RoleRef-Policy-template.bes with the fresh
      snapshot + script prefetch lines, then POST (first publish, PLURAL fixlets/custom)
      or PUT (subsequent, SINGULAR fixlet/custom/<id>) it. A non-2xx is logged (Event 8020),
      sets Snapshot.Status='failed' for that region, bumps SyncRun.Error_Count, and DOES NOT
      abort the remaining regions. On success Snapshot.Status is promoted to 'published' and
      a body diff (prefetch sha1/size/leaf) is written to the run log.
    #>
    param(
        [Parameter(Mandatory)] [object[]]$RegionResults,
        [Parameter(Mandatory)] [hashtable]$Config,
        [Parameter(Mandatory)] [string]$UrlBase,
        [Parameter(Mandatory)] [string]$SnapshotDir
    )

    if (-not (Test-Path $TemplatePath)) { throw "6830: policy-Fixlet template not found at: $TemplatePath" }
    $template = Get-Content -Raw $TemplatePath

    $besRoot = 'https://localhost:52311'
    if ($Config.ContainsKey('BESRootUrl') -and -not [string]::IsNullOrWhiteSpace($Config['BESRootUrl'])) { $besRoot = $Config['BESRootUrl'].TrimEnd('/') }

    $site = $BESSite
    if ([string]::IsNullOrWhiteSpace($site) -and $Config.ContainsKey('RoleRefSite') -and -not [string]::IsNullOrWhiteSpace($Config['RoleRefSite'])) { $site = $Config['RoleRefSite'] }
    if ([string]::IsNullOrWhiteSpace($site)) { $site = 'Dereso Software Portal' }
    $siteEnc = [uri]::EscapeDataString($site)

    $cred = $Credential
    if ($null -eq $cred) {
        $cred = & (Join-Path $PSScriptRoot 'Get-BigFixCredential.ps1') -DatabasePath $DatabasePath -SQLDir $SQLDir -SqliteHelperPath $SqliteHelperPath
    }

    $irmExtra = @{}
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $irmExtra['SkipCertificateCheck'] = $true
    } else {
        # PS 5.1 fallback: no -SkipCertificateCheck. Trust-all callback, Add-Type free.
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    # Ship Reconcile-LocalRoles.ps1 as a prefetched file resource (RESEARCH Pitfall 11 -
    # no embedded createfile block, no brace escaping). Stage it beside the snapshots and
    # pin its own sha1/size.
    $reconcileSrc = Join-Path $PSScriptRoot 'Reconcile-LocalRoles.ps1'
    $scriptLine = $null
    if (Test-Path $reconcileSrc) {
        Copy-Item -Path $reconcileSrc -Destination (Join-Path $SnapshotDir 'Reconcile-LocalRoles.ps1') -Force -WhatIf:$false
        $rSha  = (Get-FileHash -Algorithm SHA1 -Path $reconcileSrc).Hash.ToLowerInvariant()
        $rSize = (Get-Item $reconcileSrc).Length
        $scriptLine = New-PrefetchLine -FileName 'Reconcile-LocalRoles.ps1' -Sha1 $rSha -Size $rSize -UrlBase $UrlBase
    } else {
        # Task 3 delivers the script; until then emit a placeholder so the template still renders.
        $scriptLine = New-PrefetchLine -FileName 'Reconcile-LocalRoles.ps1' -Sha1 ('0' * 40) -Size 0 -UrlBase $UrlBase
    }

    foreach ($rr in $RegionResults) {
        $rlc = ([string]$rr.region).ToLowerInvariant()
        $snapLine = New-PrefetchLine -FileName $rr.file -Sha1 $rr.sha1 -Size ([long]$rr.size_bytes) -UrlBase $UrlBase

        $incFresh = $true
        $fkey = "RoleRefFreshnessGate_$rlc"
        if ($Config.ContainsKey($fkey) -and $Config[$fkey] -match '^(0|false|no|off)$') { $incFresh = $false }

        $xml = Format-RoleRefFixletXml -TemplateText $template -Region $rr.region `
            -SnapshotPrefetchLine $snapLine -ScriptPrefetchLine $scriptLine -IncludeFreshnessGate $incFresh

        $idKey = "RoleRefFixletId_$rlc"
        $existingId = $null
        $idRow = @(Get-Rows "SELECT Value FROM PipelineConfig WHERE Key = @k" @{ k = $idKey })
        if ($idRow.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$idRow[0].Value)) { $existingId = [string]$idRow[0].Value }

        try {
            if ($existingId) {
                $uri = "$besRoot/api/fixlet/custom/$siteEnc/$existingId"
                $resp = Invoke-RestMethod -Method Put -Uri $uri -Credential $cred -Body $xml -ContentType 'application/xml' @irmExtra
                $fixId = $existingId
                $verb = 'PUT'
            } else {
                $uri = "$besRoot/api/fixlets/custom/$siteEnc"
                $resp = Invoke-RestMethod -Method Post -Uri $uri -Credential $cred -Body $xml -ContentType 'application/xml' @irmExtra
                $fixId = Get-FixletIdFromResponse -Response $resp
                $verb = 'POST'
                if ($fixId) {
                    Invoke-DbWrite "INSERT OR REPLACE INTO PipelineConfig (Key, Value, Description) VALUES (@k, @v, 'RoleRef policy Fixlet id (auto-recorded on first publish)')" @{ k = $idKey; v = [string]$fixId }
                }
            }

            Invoke-DbWrite "UPDATE Snapshot SET Status = 'published' WHERE RunID = @r AND Region = @rgn" @{ r = $RunId; rgn = $rr.region }
            $rr.fixlet = [pscustomobject]@{
                id = $fixId; verb = $verb
                prefetch_sha1 = $rr.sha1; prefetch_size = $rr.size_bytes; prefetch_leaf = $rr.file
            }
            Write-Host ("[FIXLET] {0} region {1}: {2} id={3}  prefetch sha1={4} size={5} leaf={6}" -f $verb, $rr.region, 'ok', $fixId, $rr.sha1, $rr.size_bytes, $rr.file)
        } catch {
            Invoke-DbWrite "UPDATE Snapshot SET Status = 'failed' WHERE RunID = @r AND Region = @rgn" @{ r = $RunId; rgn = $rr.region }
            Invoke-DbWrite "UPDATE SyncRun SET Error_Count = Error_Count + 1 WHERE RunID = @r" @{ r = $RunId }
            Write-PublishEvent -EventId 8020 -Message ("RoleRef policy Fixlet publish FAILED for region '{0}': {1}" -f $rr.region, $_.Exception.Message)
            Write-Warning ("[FIXLET] region {0}: FAILED - {1}; continuing with remaining regions" -f $rr.region, $_.Exception.Message)
        }
    }
}

# --- load helper + module ---------------------------------------------------

if (-not (Test-Path $SqliteHelperPath)) { throw "Sqlite-Helper.ps1 not found at: $SqliteHelperPath" }
. $SqliteHelperPath
if (-not (Test-Path $SnapshotModulePath)) { throw "SnapshotBuild.psm1 not found at: $SnapshotModulePath" }
Import-Module $SnapshotModulePath -Force

$started = (Get-Date).ToUniversalTime()
$builtOn = $started

# --- config -----------------------------------------------------------------

$cfg = @{}
foreach ($row in (Get-Rows "SELECT Key, Value FROM PipelineConfig")) { $cfg[[string]$row.Key] = [string]$row.Value }

$validityMonths = 6
if ($cfg.ContainsKey('ValidityMonths') -and $cfg['ValidityMonths'] -match '^\d+$') { $validityMonths = [int]$cfg['ValidityMonths'] }

$urlBase = 'http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref'
if ($cfg.ContainsKey('SnapshotUrlBase') -and -not [string]::IsNullOrWhiteSpace($cfg['SnapshotUrlBase'])) { $urlBase = $cfg['SnapshotUrlBase'] }

$outDir = Resolve-OutputDir -Config $cfg
if (-not $WhatIfPreference) {
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
}

# --- SyncRun open ----------------------------------------------------------

Invoke-DbWrite "INSERT INTO SyncRun (RunID, Type, Started_on, Status) VALUES (@r, 'Publish', datetime('now','localtime'), 'running')" @{ r = $RunId }

# --- region validation / selection --------------------------------------

$activeRegions = @(Get-Rows "SELECT GPC_Sub_Name FROM Region WHERE Active = 1" | ForEach-Object { [string]$_.GPC_Sub_Name })

$targetRegions = @()
if ($Region) {
    $match = @(Get-Rows "SELECT GPC_Sub_Name FROM Region WHERE Active = 1 AND GPC_Sub_Name = @r" @{ r = $Region })
    if ($match.Count -eq 0) {
        Invoke-DbWrite "UPDATE SyncRun SET Ended_on = datetime('now','localtime'), Status = 'failed', Summary = @s, Error_Count = 1 WHERE RunID = @r" @{ r = $RunId; s = "unknown region '$Region'" }
        throw "6810: region '$Region' is not an Active row in Region (GPC_Sub_Name). Refusing to write a snapshot for a region not in the seed table."
    }
    $targetRegions = @([string]$match[0].GPC_Sub_Name)
} else {
    $pub = @(Get-Rows @"
SELECT rp.Role AS Role, rp.RegionID AS RegionID, rp.Active AS Active, r.GPC_Sub_Name AS Region
FROM RolePublication rp
LEFT JOIN Region r ON r.RegionID = rp.RegionID
WHERE rp.Active = 1
"@)
    $hasAllRegions = @($pub | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.RegionID) }).Count -gt 0
    if ($hasAllRegions) {
        $targetRegions = @($activeRegions)
    } else {
        $named = @($pub | ForEach-Object { [string]$_.Region } | Where-Object { $_ -ne '' } | Select-Object -Unique)
        $targetRegions = @($named | Where-Object { $activeRegions -contains $_ })
    }
}

# --- load all publication rows + all needed UserRole rows (WR-02: separate calls) --

$allPub = @(Get-Rows @"
SELECT rp.Role AS Role, rp.RegionID AS RegionID, rp.Active AS Active, r.GPC_Sub_Name AS Region
FROM RolePublication rp
LEFT JOIN Region r ON r.RegionID = rp.RegionID
WHERE rp.Active = 1
"@)

$publishedRoleNames = @($allPub | ForEach-Object { [string]$_.Role } | Where-Object { $_ -ne '' } | Select-Object -Unique)

$userRoleRows = @()
if ($publishedRoleNames.Count -gt 0) {
    $inList = ($publishedRoleNames | ForEach-Object { ConvertTo-SqliteLiteral -Value $_ }) -join ','
    $userRoleRows = @(Get-Rows "SELECT DISTINCT UserID, Role, Source_Type, Source_Value FROM UserRole WHERE Active = 1 AND Role IN ($inList)")
}

# --- per region: build, serialise, write, record ------------------------

$regionResults = @()

foreach ($rgn in $targetRegions) {
    $rlc  = $rgn.ToLowerInvariant()
    $leafLatest = "roleref-$rlc-latest.json"
    $leafDated  = "roleref-$rlc-{0}.json" -f $builtOn.ToString('yyyyMMdd')
    $leafSha    = "$leafLatest.sha1"

    $snap = Build-RegionSnapshot -Rows ([object[]]@($userRoleRows)) -Publication ([object[]]@($allPub)) `
        -Region $rgn -RunId $RunId -ValidityMonths $validityMonths -BuiltOn $builtOn

    $json = $snap | ConvertTo-Json -Depth 6 -Compress

    $roleCount = @($snap.roles).Count
    $userCount = @($snap.roles | ForEach-Object { $_.users } | ForEach-Object { $_.id } | Select-Object -Unique).Count

    # write dir: real roleref dir, or a throwaway temp dir under -WhatIf so we can still
    # compute an honest size + sha1 without touching the published tree.
    if ($WhatIfPreference) {
        $writeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('roleref-whatif-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $writeDir -Force -WhatIf:$false | Out-Null
    } else {
        $writeDir = $outDir
    }

    $pathDated  = Join-Path $writeDir $leafDated
    $pathLatest = Join-Path $writeDir $leafLatest
    $pathSha    = Join-Path $writeDir $leafSha

    try {
        Set-Content -Path $pathDated -Value $json -Encoding UTF8 -NoNewline -WhatIf:$false
        Copy-Item -Path $pathDated -Destination $pathLatest -Force -WhatIf:$false

        $sha1 = (Get-FileHash -Algorithm SHA1 -Path $pathLatest).Hash.ToLowerInvariant()
        $size = (Get-Item $pathLatest).Length

        Set-Content -Path $pathSha -Value ("{0}  {1}" -f $sha1, $leafLatest) -Encoding ASCII -NoNewline -WhatIf:$false

        if ($size -ne (Get-Item $pathLatest).Length) {
            throw "on-disk length changed between hash and record for $leafLatest"
        }
    } catch {
        Invoke-DbWrite "UPDATE SyncRun SET Error_Count = Error_Count + 1 WHERE RunID = @r" @{ r = $RunId }
        throw "6820: failed to build/write snapshot for region '$rgn': $($_.Exception.Message)"
    }

    Invoke-DbWrite @"
INSERT INTO Snapshot (RunID, Built_on, File_Name, SHA1, Size_Bytes, Role_Count, User_Count, Region, Status)
VALUES (@run, @built, @file, @sha, @size, @rc, @uc, @rgn, 'built')
"@ @{
        run = $RunId; built = $builtOn.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
        file = $leafLatest; sha = $sha1; size = [string]$size; rc = [string]$roleCount; uc = [string]$userCount; rgn = $rgn
    }

    if ($WhatIfPreference) {
        Write-Host ("[WOULD WRITE] {0}\{1}  size={2}  sha1={3}" -f $outDir, $leafLatest, $size, $sha1)
        Write-Host ("[WOULD WRITE] {0}\{1}" -f $outDir, $leafDated)
        Write-Host ("[WOULD WRITE] {0}\{1}  ({2}  {3})" -f $outDir, $leafSha, $sha1, $leafLatest)
        Remove-Item -Path $writeDir -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
    } else {
        Write-Host ("[WRITE] {0}  size={1}  sha1={2}  roles={3}  users={4}" -f $leafLatest, $size, $sha1, $roleCount, $userCount)
    }

    $regionResults += [pscustomobject]@{
        region      = $rgn
        file        = $leafLatest
        dated_file  = $leafDated
        sha1        = $sha1
        size_bytes  = $size
        role_count  = $roleCount
        user_count  = $userCount
        fixlet      = $null   # populated by Task 2 when -SkipFixletPut is not set
    }
}

# --- Fixlet lifecycle ----------------------------------------------------
# Re-PUT (or first-time POST) each published region's policy Fixlet so its prefetch line
# always names the hash of the file just written. Skipped under -SkipFixletPut / -WhatIf.
if (-not $SkipFixletPut -and -not $WhatIfPreference -and $regionResults.Count -gt 0) {
    Invoke-RoleRefFixletLifecycle -RegionResults $regionResults -Config $cfg -UrlBase $urlBase -SnapshotDir $outDir
}

# --- SyncRun close + JSON log ------------------------------------------

$status = 'success'
$errCount = 0
if (-not $WhatIfPreference) {
    $errRow = @(Get-Rows "SELECT Error_Count AS n FROM SyncRun WHERE RunID = @r" @{ r = $RunId })
    if ($errRow.Count -gt 0) { $errCount = [int]$errRow[0].n }
    if ($errCount -gt 0) { $status = 'partial' }
}

Invoke-DbWrite @"
UPDATE SyncRun SET Ended_on = datetime('now','localtime'), Status = @st,
    Roles_Seen = @roles, Entitlements = @ents, Summary = @sum
WHERE RunID = @r
"@ @{
    r = $RunId; st = $status
    roles = [string]$publishedRoleNames.Count
    ents  = [string]$userRoleRows.Count
    sum   = ("published {0} region(s): {1}" -f $regionResults.Count, (($regionResults | ForEach-Object { $_.region }) -join ', '))
}

$log = [pscustomobject]@{
    run_id     = $RunId
    type       = 'Publish'
    whatif     = [bool]$WhatIfPreference
    started    = $started.ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    ended      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture)
    output_dir = $outDir
    status     = $status
    error_count = $errCount
    regions    = @($regionResults | ForEach-Object {
        [pscustomobject]@{
            region = $_.region; file = $_.file; dated_file = $_.dated_file
            sha1 = $_.sha1; size_bytes = $_.size_bytes
            role_count = $_.role_count; user_count = $_.user_count
            fixlet = $_.fixlet
        }
    })
}

New-Item -ItemType Directory -Path $LogDir -Force -WhatIf:$false | Out-Null
$logPath = Join-Path $LogDir ("publish-rolesnapshot-{0}.json" -f $started.ToString('yyyyMMdd-HHmmss'))
Set-Content -Path $logPath -Value ($log | ConvertTo-Json -Depth 8 -Compress) -Encoding UTF8 -WhatIf:$false

Write-Host "----RUN SUMMARY----"
Write-Host ($log | ConvertTo-Json -Depth 8 -Compress)
Write-Host ("[DONE] Publish-RoleSnapshot complete{0}." -f $(if ($WhatIfPreference) { ' [WhatIf]' } else { '' }))
