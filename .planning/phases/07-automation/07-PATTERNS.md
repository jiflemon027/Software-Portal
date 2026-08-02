# Phase 7: End-to-End Automation — Pattern Map

**Mapped:** 2026-08-01
**Files analyzed:** 21 new/modified files
**Analogs found:** 17 / 21 (4 have no codebase analog; use RESEARCH.md patterns)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/Initialize-AutomationDb.ps1` | script | batch | `Dashboard_4_samples/Initialize-RoleDb.ps1` | exact |
| `scripts/Parse-AxoniousExport.ps1` | utility | transform | `parseCsv()` in `tests/unit/role_assigner.test.js` lines 40–70 | role-match |
| `scripts/Get-UserComputerMap.ps1` | service | request-response | `EvaluateRelevance` pattern in `fixlet_update_tracker.ojo` line 1167 | partial |
| `scripts/Invoke-RoleSync.ps1` | service | batch | `buildAssignActionXml` / `buildAssignActionScript` in `fixlet_role_assigner.ojo` lines 527–640 | role-match |
| `scripts/Invoke-ContentSync.ps1` | service | batch | `copyNextItem` / `scanNextSite` in `fixlet_update_tracker.ojo` lines 1146–1175, 1533–1611 | role-match |
| `scripts/Stage-Repository.ps1` | utility | file-I/O | `rewritePrefetchUrls()` in `fixlet_dispatcher.ojo` lines 391–399 | partial |
| `config/GroupRoleMap.json` | config | transform | `PORTAL_CONFIG` in `fixlet_role_assigner.ojo` lines 40–53 | partial |
| `config/PipelineConfig.json` | config | key-value | `PORTAL_CONFIG` in `fixlet_dispatcher.ojo` lines 38–42 | partial |
| `Existing Dashboards/fixlet_automation_monitor.ojo` | dashboard | event-driven | `fixlet_update_tracker.ojo` (multi-tab, scan engine, API calls) | exact |
| `Dashboard_4_samples/Dereso SWD Automation.bes` | analysis | event-driven | `Dashboard_4_samples/Dereso SWD.bes` | exact |
| `tests/unit/automation_monitor.test.js` | test | transform | `tests/unit/update_tracker.test.js` | exact |
| `tests/integration/automation.integration.test.js` | test | request-response | `tests/integration/update_tracker.integration.test.js` | exact |
| `tests/fixtures/phase-07/sample-axonious.csv` | fixture | file-I/O | `tests/fixtures/phase-04/sample.csv` | role-match |
| `tests/fixtures/phase-07/sample-portal-fixlets.xml` | fixture | file-I/O | `tests/fixtures/phase-06/portal-fixlet-with-roles.xml` | exact |
| `tests/fixtures/phase-07/sample-prefetch-script.txt` | fixture | file-I/O | prefetch line format in `fixlet_dispatcher.ojo` lines 391–399 | partial |
| `tests/fixtures/phase-07/sample-grouprolemap.json` | fixture | transform | RESEARCH.md D-03 spec only | none |
| `tests/fixtures/phase-07/sample-automation-db.sql` | fixture | CRUD | RESEARCH.md D-05 schema only | none |
| `config/task-RoleSync.xml` | config | batch | RESEARCH.md Pattern 9 only | none |
| `config/task-ContentSync.xml` | config | batch | RESEARCH.md Pattern 9 only | none |
| `config/task-RepoStage.xml` | config | batch | RESEARCH.md Pattern 9 only | none |
| `docs/automation-admin-guide.md` | doc | — | no analog | none |

---

## Pattern Assignments

### `scripts/Initialize-AutomationDb.ps1` (script, batch)

**Analog:** `Dashboard_4_samples/Initialize-RoleDb.ps1` — exact match (same purpose, same Sqlite-Helper.ps1, same CREATE TABLE IF NOT EXISTS idiom)

**Param block and strict-mode header** (`Initialize-RoleDb.ps1` lines 44–60):
```powershell
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter()]
    [string]$DatabasePath,

    [Parameter()]
    [string]$SQLDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Sqlite-Helper.ps1"
```

**Table existence check + CREATE pattern** (`Initialize-RoleDb.ps1` lines 107–127):
```powershell
try {
    foreach ($tbl in @(
        @{ Name = 'Roles'; Ddl = $rolesDdl }
        @{ Name = 'Users'; Ddl = $usersDdl }
    )) {
        $before = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
            -Sql "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name=@n" `
            -Parameters @{ n = $tbl.Name }

        if ($before[0].n -eq 1) {
            Write-Host "[SKIP] $($tbl.Name) table already exists - no changes made"
        } else {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $tbl.Ddl | Out-Null
            Write-Host "[CREATE] $($tbl.Name) table created"
        }
    }
} catch { throw 5100 }
```

**Numeric error code convention** (`Initialize-RoleDb.ps1` lines 37–42 and usage pattern):
```
Error codes:
  5100  Table creation
  5150  Index creation
  5200  Default data seeding
  5300  Current user detection
  5400  Column migration + index
Phase 7 range: 8000–8099 (Windows Event Log — see D-18 shared pattern below)
```

**WAL checkpoint in finally block** (`Initialize-RoleDb.ps1` lines 213–217):
```powershell
} finally {
    try {
        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA wal_checkpoint(TRUNCATE)" | Out-Null
    } catch {}
}
```

**AutomationState.db DDL to add** (use RESEARCH.md D-05 schema — not in codebase yet):
All six CREATE TABLE IF NOT EXISTS blocks from RESEARCH.md Code Examples section (SyncRun, RoleAssignment, ContentItem, CacheEntry, GroupRoleMap, PipelineConfig). Register Windows Event Log source (`New-EventLog`) in this script before any pipeline script runs.

---

### `scripts/Parse-AxoniousExport.ps1` (utility, transform)

**Analog:** `parseCsv()` in `tests/unit/role_assigner.test.js` lines 40–70 — same header-detection pattern, same multi-row loop; different columns

**CSV header detection pattern** (`tests/unit/role_assigner.test.js` lines 40–52):
```javascript
// Reference — translate to PowerShell for the PS script
var lines   = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
var headers = lines[0] ? lines[0].split(',').map(function(h){ return h.trim().toLowerCase(); }) : [];
var userIdx = headers.indexOf('user');
var compIdx = headers.indexOf('computer_id');
var roleIdx = headers.indexOf('role');
if (userIdx < 0 || compIdx < 0 || roleIdx < 0) {
    return { error: 'Missing required columns: user, Computer_ID, role' };
}
```

**PowerShell equivalent** (copy this pattern, adapting column names to Axonious columns):
```powershell
$lines = (Get-Content -Path $ExportPath -Encoding UTF8) -replace "`r`n", "`n" -split "`n"
$headers = ($lines[0] -split ',') | ForEach-Object { $_.Trim().ToLower() }
$userIdx  = [Array]::IndexOf($headers, 'username')
$adIdx    = [Array]::IndexOf($headers, 'ad_groups')
$mailIdx  = [Array]::IndexOf($headers, 'mailing_groups')
if ($userIdx -lt 0 -or $adIdx -lt 0 -or $mailIdx -lt 0) {
    throw "Missing required columns: username, AD_Groups, Mailing_Groups"
}
```

**Multi-delimiter group split** (CONTEXT.md `<specifics>` section — no codebase analog):
```powershell
# D-02: lowercase all usernames. D-01: split on all three delimiters
$username = $parts[$userIdx].Trim().ToLower()
$groups   = ($parts[$adIdx] + '|' + $parts[$mailIdx]) -split '[|;,]' |
             ForEach-Object { $_.Trim() } |
             Where-Object   { $_ -ne '' } |
             Select-Object  -Unique
```

**GroupRoleMap wildcard matching** (RESEARCH.md Pattern 12):
```powershell
function Resolve-RolesForGroup($groupName, $groupRoleMapRows) {
    $roles = @()
    $lower = $groupName.ToLower()
    foreach ($row in ($groupRoleMapRows | Sort-Object Priority)) {
        if (-not $row.active) { continue }
        $pattern = $row.group_pattern.ToLower()
        if ($pattern.EndsWith('*')) {
            if ($lower.StartsWith($pattern.Substring(0, $pattern.Length - 1))) {
                $roles += $row.role
            }
        } elseif ($lower -eq $pattern) {
            $roles += $row.role
        }
    }
    return $roles | Select-Object -Unique
}
```

---

### `scripts/Get-UserComputerMap.ps1` (service, request-response)

**Analog:** `EvaluateRelevance` call in `fixlet_update_tracker.ojo` line 1167 — partial match (OJO calls `EvaluateRelevance`; this PS script calls `POST /api/query` for the same server-side relevance evaluation)

**BigFix REST auth and POST /api/query** (RESEARCH.md Pattern 2):
```powershell
# No CLM on root server — [System.Convert] and Invoke-RestMethod are available
$pair    = "$BESUser:$BESPassword"
$encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
$headers = @{ Authorization = "Basic $encoded"; "Content-Type" = "application/json" }

$rel  = '(id of it as string & "|" & (names of logged on users of it as lowercase) joined by ",") of bes computers whose (exists logged on users of it)'
$body = (@{ type = "session"; relevance = $rel } | ConvertTo-Json -Compress)

$response = Invoke-RestMethod -Uri "https://localhost:52311/api/query" `
    -Method Post -Body $body -Headers $headers -SkipCertificateCheck
# $response.result is an array like @("12345|user1,user2", "67890|user3")
```

**Parse result into user→computer map** (CONTEXT.md D-04):
```powershell
$userComputerMap = @{}
foreach ($entry in $response.result) {
    $parts      = $entry -split '\|', 2
    $computerId = $parts[0].Trim()
    $users      = if ($parts.Count -gt 1) { $parts[1] -split ',' } else { @() }
    foreach ($u in $users) {
        $u = $u.Trim()
        if ($u -eq '') { continue }
        if (-not $userComputerMap.ContainsKey($u)) { $userComputerMap[$u] = @() }
        $userComputerMap[$u] += $computerId
    }
}
```

**Fallback: RoleAwareness.db Users.LastSeen** (CONTEXT.md D-07, via `Sqlite-Helper.ps1`):
```powershell
$threshold = $LastSeenThresholdDays  # default 90
$fallbackRows = Invoke-SqliteCommand -DatabasePath $RoleDbPath -SQLDir $SQLDir `
    -Sql "SELECT u.UserID, m.CompID FROM Users u JOIN Map m ON u.UserID = m.UserID
          WHERE u.LastSeen >= datetime('now','localtime',@cutoff) AND m.Active = 1" `
    -Parameters @{ cutoff = "-$threshold days" }
foreach ($row in $fallbackRows) {
    $u = $row.UserID.ToLower()
    if (-not $userComputerMap.ContainsKey($u)) { $userComputerMap[$u] = @() }
    $userComputerMap[$u] += $row.CompID
}
```

---

### `scripts/Invoke-RoleSync.ps1` (service, batch)

**Analog:** `fixlet_role_assigner.ojo` lines 527–640 — role-match (OJO builds same XML; this PS script replicates the build in PowerShell and POSTs it server-side)

**Base64 chunk encoding in PowerShell** (RESEARCH.md Pattern 5; OJO source at `fixlet_role_assigner.ojo` lines 288–313):
```powershell
# No CLM on root server; [System.Convert] is available
$CHUNK_SIZE = 3000
$matrix = @{ computers = $computerIds; users = $userNames } | ConvertTo-Json -Compress
$b64    = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($matrix))

$chunkParamLines = ""
$chunkCount = 0
for ($i = 0; $i -lt $b64.Length; $i += $CHUNK_SIZE) {
    $len   = [Math]::Min($CHUNK_SIZE, $b64.Length - $i)
    $chunk = $b64.Substring($i, $len)
    $chunkParamLines += "`tparameter `"chunk$chunkCount`"=`"$chunk`"`r`n"
    $chunkCount++
}
$chunkParamLines += "`tparameter `"chunkCount`"=`"$chunkCount`"`r`n"
```

**buildAssignActionXml in PowerShell** (translate from `fixlet_role_assigner.ojo` lines 527–550):
```powershell
# OJO source: fixlet_role_assigner.ojo lines 527-550
function Build-AssignActionXml($role, [string[]]$computerIds, $actionScript, $suffix, $relevance) {
    $title = "Dereso_$role Assign_$suffix"
    $xml   = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`r`n"
    $xml  += "<BES xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`" xsi:noNamespaceSchemaLocation=`"BES.xsd`">`r`n"
    $xml  += "  <SingleAction>`r`n"
    $xml  += "    <Title>$([System.Security.SecurityElement]::Escape($title))</Title>`r`n"
    $xml  += "    <Relevance>$([System.Security.SecurityElement]::Escape($relevance))</Relevance>`r`n"
    $xml  += "    <ActionScript MIMEType=`"application/x-Fixlet-Windows-Shell`"><![CDATA[$actionScript]]></ActionScript>`r`n"
    $xml  += "    <Settings><ActionUITitle>$([System.Security.SecurityElement]::Escape($title))</ActionUITitle></Settings>`r`n"
    $xml  += "    <Target>`r`n"
    foreach ($cid in $computerIds) {
        $xml += "      <ComputerID>$([System.Security.SecurityElement]::Escape($cid))</ComputerID>`r`n"
    }
    $xml  += "    </Target>`r`n"
    $xml  += "  </SingleAction>`r`n"
    $xml  += "</BES>"
    return $xml
}
```

**POST /api/actions** (RESEARCH.md Pattern 2):
```powershell
$actionHeaders = @{ Authorization = "Basic $encoded"; "Content-Type" = "application/xml" }
$actionResponse = Invoke-RestMethod -Uri "https://localhost:52311/api/actions" `
    -Method Post -Body $actionXml -Headers $actionHeaders -SkipCertificateCheck
# Parse action ID from $actionResponse XML (look for <Action ID="...">)
```

**Idempotency guard** (RESEARCH.md Pitfall 8 — query RoleAssignment table before deploying):
```powershell
$existing = Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "SELECT COUNT(*) AS n FROM RoleAssignment
          WHERE username=@u AND computer_id=@c AND role=@r
          AND deployed_at > datetime('now','localtime',@cutoff)" `
    -Parameters @{ u = $username; c = $computerId; r = $role; cutoff = "-90 days" }
if ($existing[0].n -gt 0) { continue }  # skip — already assigned within threshold
```

**Two-step upsert for RoleAssignment table** (`Initialize-RoleDb.ps1` lines 203–209, adapted):
```powershell
# Step 1: create if missing
Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "INSERT OR IGNORE INTO RoleAssignment (run_id, username, computer_id, role, action_id, deployed_at)
          VALUES (@rid, @u, @c, @r, @aid, datetime('now','localtime'))" `
    -Parameters @{ rid = $runId; u = $username; c = $computerId; r = $role; aid = $actionId } | Out-Null
```

---

### `scripts/Invoke-ContentSync.ps1` (service, batch)

**Analog:** `fixlet_update_tracker.ojo` lines 1146–1175 (scan) and 1533–1611 (copy) — role-match (same 4-step copy pattern, same API endpoints; OJO uses callbacks, PS uses sequential Invoke-RestMethod calls)

**Version-strip in PowerShell** (RESEARCH.md Pattern 11; OJO source `fixlet_update_tracker.ojo` line 987–988):
```powershell
# CRITICAL: regex is ' v\d[\d.]+' — same as OJO stripVersion() line 988
function Strip-Version([string]$name) {
    return [regex]::Replace($name, ' v\d[\d.]+', '')
}
```

**Enumerate source site fixlets** (adapt from `fixlet_update_tracker.ojo` `scanNextSite` lines 1156–1175):
```powershell
# OJO uses EvaluateRelevance; PS uses GET /api/fixlets/<siteType>/<siteName>
# OJO Pitfall 1 in RESEARCH: plural 'fixlets' for list, singular 'fixlet' for GET/PUT individual
$siteName    = [System.Web.HttpUtility]::UrlEncode($sourceSiteName)
$siteType    = "external"  # or "custom" from PipelineConfig
$listResp    = Invoke-RestMethod -Uri "https://localhost:52311/api/fixlets/$siteType/$siteName" `
    -Method Get -Headers $headers -SkipCertificateCheck
# $listResp is XML; parse Fixlet/Task elements: id, name, Category, Task flag
```

**4-step copy sequence** (translate from `fixlet_update_tracker.ojo` `copyNextItem` lines 1533–1611):
```powershell
# Step 1: GET old portal fixlet XML (singular path — fixlet or task)
$pathType   = if ($item.is_task) { "task" } else { "fixlet" }  # Pitfall 1: fixlet vs task
$portalGet  = "$pathType/custom/$(UrlEncode 'Dereso Software Portal')/$($item.portal_fixlet_id)"
$portalXml  = Invoke-RestMethod -Uri "https://localhost:52311/api/$portalGet" `
    -Method Get -Headers $headers -SkipCertificateCheck -ContentType "application/xml"

# Step 2: GET source fixlet XML
$srcGet  = "fixlet/$($item.source_site_type)/$(UrlEncode $item.source_site)/$($item.fixlet_id)"
$srcXml  = Invoke-RestMethod -Uri "https://localhost:52311/api/$srcGet" ...

# Step 3: POST copy — plural 'fixlets/custom/...' (Pitfall 2: OJO fixlet_update_tracker.ojo line 1578)
$newXml  = Build-CopyXml -SourceXml $srcXml -Category $item.category -Roles $item.roles
$postPath = "fixlets/custom/$(UrlEncode 'Dereso Software Portal')"
$postResp = Invoke-RestMethod -Uri "https://localhost:52311/api/$postPath" `
    -Method Post -Body $newXml -Headers $actionHeaders -SkipCertificateCheck

# Step 4: PUT X-Superseded-By on old portal fixlet (singular path, Pitfall 1)
$supXml  = Build-SupersededXml -OldXml $portalXml -NewId $newFixletId
$putPath = "$pathType/custom/$(UrlEncode 'Dereso Software Portal')/$($item.portal_fixlet_id)"
$putResp = Invoke-RestMethod -Uri "https://localhost:52311/api/$putPath" `
    -Method Put -Body $supXml -Headers $actionHeaders -SkipCertificateCheck
```

**Always-recurse error model** (OJO `copyNextItem` lines 1554–1555 — partial failures logged, loop continues):
```powershell
# PowerShell equivalent: catch each step individually; log error; continue loop
try { ... } catch {
    $errorList += @{ item = $item.fixlet_name; message = $_.Exception.Message }
    continue  # always continue even on failure
}
```

**Task chain trigger at end of script** (RESEARCH.md Pitfall 3):
```powershell
# End of Invoke-ContentSync.ps1: start RepoStage immediately
Start-ScheduledTask -TaskName "Dereso\SoftwarePortal-RepoStage"
```

---

### `scripts/Stage-Repository.ps1` (utility, file-I/O)

**Analog:** `fixlet_dispatcher.ojo` lines 391–399 — partial match (`rewritePrefetchUrls()` is the consumer of what this script stages; the regex shows the exact URL format)

**Prefetch line regex** (derived from `fixlet_dispatcher.ojo` lines 391–399):
```javascript
// OJO source: fixlet_dispatcher.ojo lines 392-399 — the consumer
/^(prefetch\s+(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:\d+\s+)\S+((?:\s+sha256:[0-9a-fA-F]+)?)$/gim
```

```powershell
# PowerShell equivalent for Stage-Repository.ps1 (RESEARCH.md Pattern 6):
$prefetchRegex = [regex]'^prefetch\s+(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:\d+\s+(\S+)'
foreach ($line in $actionScriptLines) {
    $m = $prefetchRegex.Match($line)
    if ($m.Success) {
        $filename = $m.Groups[1].Value
        $sha1     = $m.Groups[2].Value
        $url      = $m.Groups[3].Value
        $targetDir  = Join-Path $repoBase $sha1
        $targetFile = Join-Path $targetDir $filename
    }
}
```

**Registry path detection** (CONTEXT.md D-10, RESEARCH.md anti-pattern: never hardcode):
```powershell
$dataDir  = (Get-ItemProperty "HKLM:\SOFTWARE\BigFix\EnterpriseServer\GlobalSettings").DataDirectory
$repoBase = Join-Path $dataDir "wwwrootbes\Uploads\CustomRepository\SoftwarePortal"
```

**SHA1 verification before staging** (RESEARCH.md Pattern 6):
```powershell
Invoke-WebRequest -Uri $url -OutFile "$targetFile.tmp" -UseBasicParsing
$hash = (Get-FileHash -Path "$targetFile.tmp" -Algorithm SHA1).Hash
if ($hash -ieq $sha1) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Move-Item "$targetFile.tmp" $targetFile
    # record CacheEntry: verified = 1
} else {
    Remove-Item "$targetFile.tmp" -Force
    $errorList += @{ item = $filename; message = "SHA1 mismatch: expected $sha1 got $hash" }
}
```

---

### `config/GroupRoleMap.json` (config, transform)

**Analog:** `PORTAL_CONFIG` in `fixlet_role_assigner.ojo` lines 40–53 — partial match (OJO uses an embedded JS object; this file is its server-side JSON equivalent)

**OJO PORTAL_CONFIG roles section** (`fixlet_role_assigner.ojo` lines 40–53):
```javascript
var PORTAL_CONFIG = {
  targetGroups: ['All Workstations', 'IT Department', 'Finance Department', 'All Servers'],
  roles: ["IT Operations", "Business Operations"],
  actionNamePrefix: 'DSD_',
  validityMonths: 6
};
```

**GroupRoleMap.json structure** (CONTEXT.md D-03 — JSON equivalent):
```json
{
  "mappings": [
    { "group_pattern": "IT-All",       "role": "IT Operations",       "priority": 0, "active": true },
    { "group_pattern": "IT-Dev*",      "role": "IT Operations",       "priority": 1, "active": true },
    { "group_pattern": "Finance-*",    "role": "Finance",             "priority": 0, "active": true },
    { "group_pattern": "MAIL-Finance*","role": "Finance",             "priority": 1, "active": true }
  ]
}
```

This file is the import source for `Initialize-AutomationDb.ps1` to seed the `GroupRoleMap` SQLite table on first run. Subsequent edits are made via the Config tab in the dashboard (which writes to the table directly).

---

### `config/PipelineConfig.json` (config, key-value)

**Analog:** `PORTAL_CONFIG` in `fixlet_dispatcher.ojo` lines 38–42 — partial match (OJO PORTAL_CONFIG = embedded defaults; this file = server-side defaults for the key-value SQLite table)

**OJO PORTAL_CONFIG defaults** (`fixlet_dispatcher.ojo` lines 38–42):
```javascript
var PORTAL_CONFIG = {
  defaultExpirationDays: 7,
  retryCount:            1,
  retryDelayMinutes:     10
};
```

**PipelineConfig.json structure** (CONTEXT.md D-17 keys):
```json
{
  "AxoniousExportPath":        "C:\\BESData\\SoftwarePortal\\axonious-export.csv",
  "BESRootPath":               "",
  "BESOperatorUser":           "admin",
  "BESOperatorPassword":       "",
  "SourceSites":               "Software Installer Library for Windows",
  "AutoApproveCategories":     "",
  "UserLastSeenThresholdDays": "90",
  "MaxExportAgeDays":          "2",
  "ContentSyncSchedule":       "Weekly",
  "RoleSyncSchedule":          "Daily",
  "AlertWebhook":              "",
  "SQLDir":                    "C:\\BESData\\SoftwarePortal\\sqlite"
}
```

---

### `Existing Dashboards/fixlet_automation_monitor.ojo` (dashboard, event-driven)

**Analog:** `Existing Dashboards/fixlet_update_tracker.ojo` — exact match (5-tab OJO in the same family; same IE9 constraints, same PORTAL_CONFIG, same EvaluateRelevance/GetRelevance, same API.Get/Post/Put)

**PORTAL_CONFIG block** (copy structure from `fixlet_update_tracker.ojo` lines 41–76):
```javascript
// ==========================================================================
// PORTAL CONFIGURATION — edit only this block
var PORTAL_CONFIG = {
  sourceSites: ["Software Installer Library for Windows"],
  roles:       ["IT Operations", "Business Operations"],
  categories:  ["Cloud & File Sync", "Communication & Conferencing" /* ... */],
  validityMonths: 6
};
// END PORTAL CONFIGURATION
// ==========================================================================
```

**IE9 btoa polyfill** (copy verbatim from `fixlet_role_assigner.ojo` lines 58–72):
```javascript
if (typeof btoa === 'undefined') {
  btoa = function(s) {
    var CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var str = String(s), out = '', i = 0;
    while (i < str.length) {
      var b0 = str.charCodeAt(i++), b1 = str.charCodeAt(i++), b2 = str.charCodeAt(i++);
      out += CHARS.charAt(b0 >> 2)
           + CHARS.charAt(((b0 & 3) << 4) | (b1 >> 4))
           + (isNaN(b1) ? '=' : CHARS.charAt(((b1 & 15) << 2) | (b2 >> 6)))
           + (isNaN(b2) ? '=' : CHARS.charAt(b2 & 63));
    }
    return out;
  };
}
```

**GetRelevance pattern for Analysis reads** (`fixlet_role_assigner.ojo` lines 797–817):
```javascript
// Read AutomationState.db summary from Dereso SWD Automation.bes Analysis
function loadStatusTab() {
  try {
    var rel = '(name of computer of it as string & "|||" & value of it as string) ' +
              'of results whose (value of it != "") ' +
              'of bes property whose (name of it = "Last RoleSync" AND analysis flag of it)';
    var data = GetRelevance(rel);
    if (!data || data.length === 0) {
      document.getElementById("roleSyncStatus").innerText = "Analysis not reporting";
      return;
    }
    var parts = String(data[0]).split("|||");
    renderSyncStatus(parts[1]);
  } catch(e) {
    // Fallback: EvaluateRelevance or REST read of JSON log file
    loadStatusViaRest();
  }
}
```

**Msxml2.DOMDocument.6.0 for XML** (`fixlet_update_tracker.ojo` lines 1504–1509):
```javascript
// Exact ActiveXObject call required by IE9 OJO runtime
var origDoc = new ActiveXObject("Msxml2.DOMDocument.6.0");
origDoc.async            = false;
origDoc.validateOnParse  = false;
origDoc.resolveExternals = false;
origDoc.setProperty("SelectionLanguage", "XPath");  // required for selectSingleNode
origDoc.loadXML(xmlString);
var node = origDoc.selectSingleNode("//Fixlet") || origDoc.selectSingleNode("//Task");
```

**EvaluateRelevance for source site enumeration** (`fixlet_update_tracker.ojo` lines 1156–1174):
```javascript
// Equivalent of PS Invoke-RestMethod GET /api/fixlets/... — same data, OJO path
var safesite = siteName.replace(/"/g, '""');
var rel =
  '(id of it as string & "\x1F" & name of it & "\x1F" & name of (site of it)' +
  ' & "\x1F" & (if custom site flag of (site of it) then "custom" else "external"))' +
  ' of bes fixlets whose (name of (site of it) = "' + safesite + '"' +
  '   and (fixlet flag of it or task flag of it))';
var data = EvaluateRelevance(rel);
```

**Button disable-on-click guard** (RESEARCH.md Pitfall 10):
```javascript
// Apply to all "Run Now" trigger buttons in the dashboard
function triggerRoleSync() {
  var btn = document.getElementById("roleSyncBtn");
  if (btn) { btn.disabled = true; btn.value = "Running..."; }
  var xml = buildTriggerActionXml("Invoke-RoleSync");
  API.Post("actions", xml, function(e, s, b) {
    if (s === 200 || s === 201) { setStatus("Role sync triggered."); }
    else { setStatus("Failed: " + s); }
    if (btn) { btn.disabled = false; btn.value = "Run Now"; }
  });
}
```

**API.Post / API.Put / API.Get calls** (`fixlet_update_tracker.ojo` lines 1580–1609):
```javascript
// POST to copy a fixlet — plural 'fixlets/custom/...' (Pitfall 2)
var postPath = "fixlets/custom/" + encodeURIComponent("Dereso Software Portal");
API.Post(postPath, newXml, function(e, s, b) {
  if (s !== 200 && s !== 201) { /* error */ return; }
  // ...
});

// PUT to stamp superseded — singular 'fixlet/custom/...' (Pitfall 1)
var putPath = pathType + "/custom/" + encodeURIComponent("Dereso Software Portal") + "/" + id;
API.Put(putPath, supersededXml, function(e, s, b) { /* ... */ });
```

---

### `Dashboard_4_samples/Dereso SWD Automation.bes` (analysis, event-driven)

**Analog:** `Dashboard_4_samples/Dereso SWD.bes` — exact match (same BES Analysis XML structure, same DB existence guard in top-level Relevance, same Property pattern using SQLite session relevance)

**Analysis structure** (`Dereso SWD.bes` lines 1–19 — copy verbatim, changing DB path and property names):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Analysis>
    <Title>Dereso SWD Automation</Title>
    <Description><![CDATA[...]]></Description>
    <!-- DB existence guard (same pattern as Dereso SWD.bes line 6) -->
    <Relevance>(exists file "AutomationState.db" of folder it) of ("/path/to/SoftwarePortal" as folder)</Relevance>
    <Domain>BESC</Domain>
    <!-- Properties read AutomationState.db SyncRun table, one property per pipeline -->
    <Property Name="Last RoleSync" ID="1" EvaluationPeriod="PT5M">
      concatenation of (rows of statement "SELECT type || '|' || status || '|' || ended_at FROM SyncRun WHERE type='RoleSync' ORDER BY started_at DESC LIMIT 1" of it)
      of sqlite database of file "AutomationState.db" of folder it of ("/path/to/SoftwarePortal" as folder)
    </Property>
  </Analysis>
</BES>
```

**DB path construction** (copy pattern from `Dereso SWD.bes` line 6 — uses `pathname of parent folder of parent folder of client folder of site "actionsite"` to compute the EC\SoftwarePortal path; for the automation DB, use the configurable path from PipelineConfig or a fixed known path on the root server).

---

### `tests/unit/automation_monitor.test.js` (test, transform)

**Analog:** `tests/unit/update_tracker.test.js` — exact match (same file structure, same Node.js `assert` module, same `expect`/`section` runner, same summary footer)

**File header and module imports** (`tests/unit/update_tracker.test.js` lines 1–28):
```javascript
/**
 * automation_monitor.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_automation_monitor.ojo
 *
 * Running: node tests/unit/automation_monitor.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 */
"use strict";
var assert = require("assert");
```

**Test runner infrastructure** (`tests/unit/update_tracker.test.js` lines 165–183):
```javascript
var passed   = 0;
var failures = 0;

function expect(label, fn) {
  try {
    fn();
    passed++;
  } catch(e) {
    failures++;
    console.error("  FAIL: " + label);
    console.error("        " + (e.message || String(e)));
  }
}

function section(name) {
  console.log("\n--- Testing " + name + " ---");
}
```

**Summary footer** (`tests/unit/update_tracker.test.js` lines 419–430):
```javascript
console.log("\n========================================");
console.log("Results: " + passed + " passed, " + failures + " failed");
console.log("========================================");

if (failures > 0) {
  console.error("\nOne or more tests failed.");
  process.exit(1);
} else {
  console.log("\nAll tests passed.");
  process.exit(0);
}
```

**Functions to extract and test** (pure JS from `fixlet_automation_monitor.ojo` — these have no IE9-only dependencies):
- `resolveRolesForGroup(groupName, mappings)` — wildcard matching (CONTEXT.md D-03)
- `stripVersion(name)` — copy from `fixlet_update_tracker.ojo` line 987 (already tested in update_tracker.test.js; re-test here for the automation context)
- `parsePrefetchLine(line)` — extract filename/sha1/url from a prefetch line
- `buildSyncStatusHtml(syncRunRow)` — format a SyncRun row for Status tab display
- `htmlEscape(s)` — copy from `fixlet_modifier.ojo` / `fixlet_dispatcher.ojo` lines 70–77

**PORTAL_CONFIG stub pattern** (`tests/unit/update_tracker.test.js` lines 31–39):
```javascript
// Minimal stub — covers only the test cases (same pattern as update_tracker.test.js)
var PORTAL_CONFIG = {
  sourceSites: ["Software Installer Library for Windows"],
  roles:       ["IT Operations", "Business Operations"],
  categories:  ["Cloud & File Sync", "File Management & Archiving"]
};
```

---

### `tests/integration/automation.integration.test.js` (test, request-response)

**Analog:** `tests/integration/update_tracker.integration.test.js` — exact match (same GROUP A / GROUP B split, same `BIGFIX_AVAILABLE` guard, same `apiRequest()` helper, same async Promise runner)

**File header / BIGFIX_AVAILABLE guard** (`tests/integration/update_tracker.integration.test.js` lines 1–58):
```javascript
"use strict";
var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";
var BIGFIX_AVAILABLE = !!(BIGFIX_URL && BIGFIX_USER && BIGFIX_TOKEN);

if (!BIGFIX_AVAILABLE) {
  console.log("NOTE: BIGFIX_URL, BIGFIX_USER, BIGFIX_TOKEN not set.");
  console.log("      GROUP A (fixture structure) tests will run normally.");
  console.log("      GROUP B (API round-trip) tests will be SKIPPED.");
}
```

**apiRequest helper** (copy verbatim from `tests/integration/update_tracker.integration.test.js` lines 81–125):
```javascript
var https = require("https");
var fs    = require("fs");
var path  = require("path");

function apiRequest(method, relativePath, bodyXml, callback) {
  var parsed = new URL(BIGFIX_URL);
  var authHeader = "Basic " + Buffer.from(BIGFIX_USER + ":" + BIGFIX_TOKEN).toString("base64");
  var requestOptions = {
    hostname: parsed.hostname,
    port:     parsed.port || 52311,
    path:     "/api/" + relativePath,
    method:   method,
    headers:  { "Authorization": authHeader, "Accept": "application/xml" },
    rejectUnauthorized: true
  };
  // ... (copy lines 101-125 verbatim)
}
```

**runAsyncTest Promise wrapper** (`tests/integration/update_tracker.integration.test.js` lines 186–204):
```javascript
function runAsyncTest(name, fn) {
  return new Promise(function(resolve) {
    fn(function(err) {
      if (err && err.isSkip) {
        console.log("  SKIP: " + name + " -- " + err.message);
        skipped++;
      } else if (err) {
        console.log("  FAIL: " + name);
        failed++;
        failures.push({ name: name, message: err.message || String(err) });
      } else {
        console.log("  PASS: " + name);
        passed++;
      }
      resolve();
    });
  });
}
```

**GROUP A fixture structure tests** (pattern from `tests/integration/update_tracker.integration.test.js` lines 312–366):
```javascript
// GROUP A always runs — no BigFix connectivity needed
// Verify fixture files have expected content (keys, columns, schema)
runTest("sample-axonious.csv has required columns", function() {
  var csv = fs.readFileSync(
    path.join(__dirname, "..", "fixtures", "phase-07", "sample-axonious.csv"), "utf8"
  );
  var headers = csv.split('\n')[0].toLowerCase();
  assert(headers.indexOf("username") >= 0, "Expected 'username' column");
  assert(headers.indexOf("ad_groups") >= 0, "Expected 'AD_Groups' column");
  assert(headers.indexOf("mailing_groups") >= 0, "Expected 'Mailing_Groups' column");
});
```

---

### `tests/fixtures/phase-07/sample-axonious.csv` (fixture, file-I/O)

**Analog:** `tests/fixtures/phase-04/sample.csv` — role-match (same CSV fixture format; different columns for Axonious export)

**phase-04/sample.csv structure** (lines 1–6 — copy header pattern):
```
user,Computer_ID,role
jsmith,100001,IT Operations
jsmith,100002,Finance
bdoe,100001,IT Operations
adavis,100003,HR
```

**phase-07 axonious CSV structure** (adapt to Axonious columns from CONTEXT.md D-01):
```
username,AD_Groups,Mailing_Groups
jsmith,IT-All|IT-Dev-Alpha,MAIL-Finance-Team
bdoe,Finance-North|Finance-All,
adavis,HR-EMEA,,
nogroup_user,UnmappedGroup,MAIL-NoMatch
```
Include multi-delimiter test cases: pipe (`|`), semicolon (`;`), and comma-with-space for groups. Include a user with no matching groups (for zero-role code path).

---

### `tests/fixtures/phase-07/sample-portal-fixlets.xml` (fixture, file-I/O)

**Analog:** `tests/fixtures/phase-06/portal-fixlet-with-roles.xml` — exact match (copy structure verbatim, add `prefetch` line in ActionScript for Stage-Repository tests)

**phase-06 portal fixture pattern** (`portal-fixlet-with-roles.xml` lines 1–27):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>7-Zip (MSI) v26.01 - Windows (x64)</Title>
    <Category>File Management &amp; Archiving</Category>
    <MIMEField>
      <Name>Associated_Roles</Name>
      <Value>IT Support|General Access</Value>
    </MIMEField>
    <Domain>BESC</Domain>
    <ID>12345</ID>
    <DefaultAction ID="Action1">
      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">// placeholder action script</ActionScript>
    </DefaultAction>
  </Fixlet>
</BES>
```

**Phase-07 addition**: ActionScript should include a real `prefetch` line so `Stage-Repository.ps1` tests can parse it:
```
prefetch 7z2601-x64.msi sha1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa size:1234567 http://example.com/7z2601-x64.msi
```

---

### `tests/fixtures/phase-07/sample-prefetch-script.txt` (fixture, file-I/O)

**Analog:** `rewritePrefetchUrls()` regex in `fixlet_dispatcher.ojo` lines 391–399 — partial match (regex shows the exact prefetch line format)

**Prefetch line format** (from `fixlet_dispatcher.ojo` line 393 — the regex input format):
```
prefetch 7z2601-x64.msi sha1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa size:1234567 http://example.com/7z2601-x64.msi
prefetch setup.exe sha1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb size:987654 https://vendor.example.com/setup.exe sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
// this line is a comment — must be ignored by the parser
not-a-prefetch-line
```
Include: one standard prefetch, one with `sha256:` tail, one comment line, one non-prefetch line. Used by `Stage-Repository.ps1` regex unit tests.

---

## Shared Patterns

### Shared Pattern A: Sqlite-Helper.ps1 Dot-Source
**Source:** `Dashboard_4_samples/Sqlite-Helper.ps1` + usage in `Dashboard_4_samples/Initialize-RoleDb.ps1` line 60
**Apply to:** All new PowerShell scripts (`Initialize-AutomationDb.ps1`, `Parse-AxoniousExport.ps1`, `Get-UserComputerMap.ps1`, `Invoke-RoleSync.ps1`, `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`)

```powershell
# ALWAYS first line after param block. Path is relative to $PSScriptRoot.
# For scripts in scripts/ directory: Sqlite-Helper.ps1 is in Dashboard_4_samples/
. "$PSScriptRoot\..\Dashboard_4_samples\Sqlite-Helper.ps1"
```

**Constraints (copy from `Sqlite-Helper.ps1` lines 19–29 header):**
- `-SQLDir` = directory containing `sqlite3.exe` directly (no x64/x86 subfolder — SCHEMA-06)
- ONE result-returning statement per `Invoke-SqliteCommand` call (WR-02)
- Multiple DDL/DML in one `-Sql` are fine; two SELECTs throw
- `PRAGMA busy_timeout=30000` is automatically prepended; callers must NOT add it
- Non-ASCII columns: select as `hex(col) AS col__hex`; helper decodes automatically

### Shared Pattern B: Two-Step Upsert (INSERT OR IGNORE + UPDATE)
**Source:** `Dashboard_4_samples/Initialize-RoleDb.ps1` lines 203–209
**Apply to:** All writes to `RoleAssignment`, `ContentItem`, `CacheEntry` tables where rows may already exist

```powershell
# Step 1: create if missing — preserves all existing fields
Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "INSERT OR IGNORE INTO Map (UserID, Role, Active, Created_on, Valid_to)
          VALUES (@uid, @role, 1, datetime('now','localtime'), datetime('now','localtime',@validity))" `
    -Parameters @{ uid = $user; role = $Role; validity = "+$ValidityMonths months" } | Out-Null

# Step 2: update only — respects Locked_by_Override = 1
Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "UPDATE Map SET Active = 1, Updated_on = datetime('now','localtime'),
          Valid_to = datetime('now','localtime',@validity)
          WHERE UserID = @uid AND Role = @role AND Locked_by_Override = 0" `
    -Parameters @{ uid = $user; role = $Role; validity = "+$ValidityMonths months" } | Out-Null
```

**NEVER use `INSERT OR REPLACE`** — it deletes and re-inserts, destroying `Active`, `Created_on` values.

### Shared Pattern C: Structured JSON Log Output (D-18)
**Source:** RESEARCH.md Pattern 10 (D-18 spec)
**Apply to:** `Invoke-RoleSync.ps1`, `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`

```powershell
$log = @{
    run_id     = [System.Guid]::NewGuid().ToString("N")
    started_at = $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
    ended_at   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    status     = "success"   # success | partial | failed
    counts     = @{ processed = $total; succeeded = $ok; failed = $fail }
    errors     = @($errorList)  # @( @{item="..."; message="..."} )
}
$logPath = Join-Path $logDir ("RoleSync-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
$log | ConvertTo-Json -Depth 5 | Set-Content -Path $logPath -Encoding UTF8

# Windows Event Log on failure (D-18: Event IDs 8000-8099)
if ($log.status -ne "success") {
    if (-not [System.Diagnostics.EventLog]::SourceExists("DereseSoftwarePortal")) {
        New-EventLog -LogName Application -Source "DereseSoftwarePortal"
    }
    Write-EventLog -LogName Application -Source "DereseSoftwarePortal" `
        -EventId 8001 -EntryType Error `
        -Message "RoleSync failed: $($log.errors | ConvertTo-Json -Compress)"
}
```

### Shared Pattern D: IE9 JavaScript Constraints
**Source:** `fixlet_role_assigner.ojo` header comment + btoa polyfill lines 58–72
**Apply to:** `fixlet_automation_monitor.ojo` — entire file

```
MUST use:
  var (never let/const)
  function declarations (never => arrow functions)
  String concatenation (never template literals ``)
  for loops (never Array.from, no .forEach where avoidable)
  Msxml2.DOMDocument.6.0 for XML
  API.Get / API.Post / API.Put for REST calls
  GetRelevance() for Analysis property reads
  EvaluateRelevance() for live server-side relevance

MUST NOT use:
  let / const
  Arrow functions =>
  Template literals ``
  fetch() API
  Promise (use callback chains like copyNextItem pattern)
  document.querySelectorAll (use getElementById / getElementsByTagName)
```

### Shared Pattern E: htmlEscape (XSS guard)
**Source:** `fixlet_role_assigner.ojo` lines 83–89 (identical in all OJOs)
**Apply to:** `fixlet_automation_monitor.ojo` — all innerHTML assignments from untrusted data

```javascript
// Copy verbatim — this exact implementation is in all 5 existing OJOs
function htmlEscape(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
```

### Shared Pattern F: BigFix REST Auth Header (PowerShell)
**Source:** RESEARCH.md Pattern 2 (derived from OJO `API.Get/Post/Put` with Basic auth)
**Apply to:** `Get-UserComputerMap.ps1`, `Invoke-RoleSync.ps1`, `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`

```powershell
# Build once at script start; reuse for all REST calls in the same script
$pair    = "$BESUser:$BESPassword"
$encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
$headers = @{
    Authorization  = "Basic $encoded"
    "Content-Type" = "application/xml"   # or "application/json" for /api/query
}
# -SkipCertificateCheck requires pwsh.exe (PS7). Scripts specify pwsh.exe in D-08.
$response = Invoke-RestMethod -Uri "https://localhost:52311/api/..." `
    -Method Get -Headers $headers -SkipCertificateCheck
```

### Shared Pattern G: Plural vs Singular Fixlet Path (Pitfall 1)
**Source:** `fixlet_update_tracker.ojo` line 1578 (plural POST) and line 1598 (singular PUT)
**Apply to:** `Invoke-ContentSync.ps1`, `fixlet_automation_monitor.ojo`

```
POST list   → plural:   fixlets/custom/<site>            (creates new)
GET list    → plural:   fixlets/custom/<site>            (enumerates)
GET single  → singular: fixlet/custom/<site>/<id>        (reads one)
PUT single  → singular: fixlet/custom/<site>/<id>        (updates one)
             OR:         task/custom/<site>/<id>          (if item is a Task)
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `tests/fixtures/phase-07/sample-grouprolemap.json` | fixture | transform | No existing JSON config fixture; use RESEARCH.md D-03 spec |
| `tests/fixtures/phase-07/sample-automation-db.sql` | fixture | CRUD | No SQL DDL fixture exists in codebase; use RESEARCH.md D-05 schema DDL directly |
| `config/task-RoleSync.xml` | config | batch | No Scheduled Task XML in codebase; generate via `schtasks.exe /Query /TN ... /XML` after `Register-ScheduledTask` |
| `config/task-ContentSync.xml` | config | batch | Same as above |
| `config/task-RepoStage.xml` | config | batch | Same as above |
| `docs/automation-admin-guide.md` | doc | — | No existing admin guide markdown in codebase |

---

## Metadata

**Analog search scope:** `Dashboard_4_samples/`, `Existing Dashboards/`, `tests/unit/`, `tests/integration/`, `tests/fixtures/`
**Files scanned:** 17 (2 PS scripts, 5 OJO files, 2 BES files, 6 test files, 4 fixture files)
**Pattern extraction date:** 2026-08-01
