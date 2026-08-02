# Phase 7: End-to-End Automation — Research

**Researched:** 2026-08-01
**Domain:** PowerShell automation pipelines, BigFix REST API (server-side), SQLite (CLM-safe via sqlite3.exe), BigFix OJO dashboard (IE9 JS), Windows Scheduled Tasks
**Confidence:** HIGH — all patterns drawn from existing verified codebase

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Axonious Export Format** — CSV with columns `username`, `AD_Groups`, `Mailing_Groups` (pipe/semicolon/comma separated). Both group columns checked for role entitlement.
- **D-02: Username Case Normalization** — All usernames lowercased via `.ToLower()` before any comparison or storage.
- **D-03: Group-to-Role Mapping Config** — `GroupRoleMap` SQLite table in `AutomationState.db`. Supports exact match and `*`-suffix wildcard, case-insensitive. Editable via Config tab in dashboard.
- **D-04: User→Computer Resolution** — `POST /api/query` with session relevance `(id of it as string & "|" & names of logged on users of it as lowercase joined by ",") of bes computers whose (exists logged on users of it)`. Falls back to `Users.LastSeen` in `RoleAwareness.db` (90-day threshold default).
- **D-05: AutomationState.db Schema** — Tables: `SyncRun`, `RoleAssignment`, `ContentItem` (stages: discovered/staged/categorized/ready/live/rejected), `CacheEntry`, `GroupRoleMap`, `PipelineConfig`. Location configurable; example `C:\BESData\SoftwarePortal\AutomationState.db`.
- **D-06: Invoke-RoleSync.ps1** — Master role orchestrator. Reads Axonious export, applies GroupRoleMap, calls BigFix REST API, cross-joins to triples (user, role, computer_id), batches by role with one `POST /api/actions` per role, logs to `SyncRun` + `RoleAssignment`.
- **D-07: Get-UserComputerMap.ps1** — Standalone script; `POST /api/query` for session relevance. Falls back to `RoleAwareness.db` Users.LastSeen via Dereso SWD Analysis.
- **D-08: RoleSync Scheduled Task** — Name `Dereso\SoftwarePortal-RoleSync`, daily at 06:00, `pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "..."`, local service account with BigFix operator permissions.
- **D-09: Invoke-ContentSync.ps1** — Enumerates source sites via BigFix REST API, applies version-strip regex (`/ v\d[\d.]+/g`), copies approved items via `POST /api/fixlets/custom/...`, stamps superseded fixlets via `PUT`.
- **D-10: Stage-Repository.ps1** — Parses prefetch lines from portal fixlet action scripts, downloads missing files, verifies SHA1 via `Get-FileHash -Algorithm SHA1`, places at `{BES_ROOT}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\{sha1}\{filename}`. BES root from registry `HKLM:\SOFTWARE\BigFix\EnterpriseServer\GlobalSettings` → `DataDirectory`.
- **D-11: Content Pipeline Scheduled Tasks** — `Dereso\SoftwarePortal-ContentSync` (weekly), `Dereso\SoftwarePortal-RepoStage` (triggered after ContentSync).
- **D-12: End-User Experience** — Role-aware offers via BigFix Self Service. Dispatcher remains human deploy step. Automation delivers to "Ready" stage only.
- **D-13–D-17: Automation Dashboard** — `fixlet_automation_monitor.ojo` with 5 tabs: Status, Role Pipeline, Content Queue (approve/reject/force-push), Repository Cache, Config.
- **D-18: Script Output/Error Reporting** — Structured JSON log per run. Windows Event Log on failure (Source: `DereseSoftwarePortal`, Event IDs 8000–8099). Optional webhook alert (key `AlertWebhook` in PipelineConfig).
- **D-19: Existing Tool Reuse** — All existing OJO patterns reused verbatim (copier, modifier, dispatcher, role assigner, update tracker, Sqlite-Helper.ps1, Initialize-RoleDb.ps1, Dereso SWD.bes).
- **D-20: Phased Rollout** — Week 1 dry-run (-WhatIf), Week 2 role pipeline live, Week 3 content pipeline live (approval OFF), Week 4 auto-approve for selected categories.

### Claude's Discretion

No explicit discretion areas noted in CONTEXT.md.

### Deferred Ideas (OUT OF SCOPE)

- Phase 8: Autonomous Dispatch (fully automatic dispatch of "Ready" fixlets)
- Revoke Automation (automated role revocation)
- Multi-tenant / Multi-BigFix support
- AD Direct Integration (LDAP instead of Axonious intermediary)
- Fixlet Rollback
- Self-Service Catalog UI
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FR-01 | Fixlet copy from external sites | `Invoke-ContentSync.ps1` replicates copier OJO API calls (`POST /api/fixlets/custom/...`) at pipeline level |
| FR-02 | Role-based fixlet association | `Invoke-RoleSync.ps1` + GroupRoleMap table drive automated role assignment to RoleAwareness.db |
| FR-03 | Role-based relevance modification | Modifier dashboard remains the role-categorization step for pipeline items at "Staged" stage |
| FR-04 | Role-based description update | Inherited from existing Modifier dashboard patterns (not new automation logic) |
| FR-05 | Target group deployment | Dispatcher remains human deploy step; pipeline delivers to "Ready" state |
| FR-06 | Automatic offer creation | Dispatcher patterns reused for human-confirmed deploy step |
| FR-07 | Default deployment options | Dispatcher patterns unchanged |
| FR-08 | Automatic user registration on logon | `UpdateUserOnLogon` scheduled task from Phase 5 provides Users.LastSeen used as fallback by `Get-UserComputerMap.ps1` |
| FR-09 | Role-aware web report | Not modified in Phase 7 |
| FR-10 | Fixlet version update tracking | `Invoke-ContentSync.ps1` automates the scan+copy loop from the Update Tracker dashboard |
| NFR-NEW | Scheduled unattended operation with audit trail | `SyncRun` table + JSON logs + Windows Event Log + `-WhatIf` dry-run cover the audit trail NFR |
</phase_requirements>

---

## Summary

Phase 7 is an **integration and automation phase**, not a greenfield build. Every new script and dashboard function reuses patterns that are already proven and tested in the existing codebase. The primary risk is not unknown technology but correct orchestration of the existing pieces: the exact parameter shapes, API endpoint paths, and constraint boundaries (IE9 in OJO, CLM-awareness in Sqlite-Helper.ps1) are all well-established.

The three pipelines share a common pattern: call the BigFix REST API (`POST /api/query` for relevance, `GET/POST/PUT /api/fixlets` for content, `POST /api/actions` for deployments), record state in `AutomationState.db` via `Sqlite-Helper.ps1`, and emit structured JSON logs. The Automation Dashboard is a fifth OJO file in the existing family, following the same IE9-compatible JavaScript + `Msxml2.DOMDocument.6.0` patterns.

One architectural decision the planner must make explicit: how the Automation Dashboard reads `AutomationState.db`. The preferred approach (based on existing patterns) is a new BigFix Analysis BES file (`Dereso SWD Automation.bes`) deployed to the root server as a managed BES client. The dashboard reads from it via `GetRelevance()`. A direct REST fallback using `EvaluateRelevance()` with a session relevance expression handles cases where the Analysis is stale or not yet deployed.

**Primary recommendation:** Reuse every pattern from the existing 6 phases verbatim. Phase 7 is a wiring exercise — the hard problems are already solved.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Axonious CSV parsing | Root Server (PS script) | — | File lives on root server; no OJO interaction needed |
| Group-to-role mapping | Root Server (PS script) | Automation Dashboard (Config tab) | Config stored in AutomationState.db; dashboard edits config |
| User→computer resolution | BigFix REST API | RoleAwareness.db (fallback) | POST /api/query evaluates against all BES clients server-side |
| Role assignment deployment | BigFix REST API | Root Server (POST /api/actions) | PS script posts SingleAction XML; BigFix distributes to clients |
| RoleAwareness.db writes | BES Client (ActionScript) | — | Same as Phase 4 — clients run the embedded PS script |
| AutomationState.db reads | BigFix Analysis (BES client = root server) | OJO direct EvaluateRelevance | GetRelevance reads cached Analysis results |
| AutomationState.db writes | Root Server (PS scripts) | — | Scripts run on root server where DB resides |
| Fixlet discovery | BigFix REST API | — | GET /api/fixlets/<siteType>/<siteName> enumerates source sites |
| Fixlet copy | BigFix REST API | — | POST /api/fixlets/custom/Dereso Software Portal (plural) |
| Supersede stamp | BigFix REST API | — | PUT /api/fixlet/custom/... or task/custom/... (singular) |
| Repository staging | Root Server file system | BigFix REST API (prefetch line parse) | Files placed directly on root server disk |
| SHA1 verification | Root Server (PS script) | — | Get-FileHash -Algorithm SHA1; no client involvement |
| Pipeline status display | Automation Dashboard (OJO) | BigFix Analysis | Dashboard tab reads from Analysis or direct EvaluateRelevance |
| Content queue approval | Automation Dashboard (OJO) | BigFix REST API | Dashboard updates ContentItem.stage in AutomationState.db via a BigFix action (or direct write if root server is a BES client) |
| Scheduled task registration | Root Server (Register-ScheduledTask) | Scheduled Task XML files | PS cmdlet for programmatic registration; XML for admin import |

---

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| PowerShell (pwsh.exe) | 7.x (D-08) | All root server orchestration scripts | Already on root server; `-SkipCertificateCheck` available in PS7 |
| `Sqlite-Helper.ps1` | (project — existing) | CLM-safe SQLite access for all scripts | Verified CLM-safe, used by Phases 3–6; no DLL, no Add-Type |
| sqlite3.exe | 3.53.1 (bundled as prefetch item) | SQLite CLI backend for Sqlite-Helper.ps1 | Already distributed to BES clients; root server needs a local copy in configured SQLDir |
| Node.js | v24.15.0 (verified on host) | JS unit tests for OJO dashboard functions | Existing test harness (all 5 previous test files use Node.js + assert) |
| BigFix REST API | HTTP/1.1 at :52311 | All external data (computers, fixlets, actions) | The only way for server-side PS to interact with BigFix |

### Supporting

| Library / Tool | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| `Initialize-RoleDb.ps1` | (project — existing) | Reference for DB init pattern and upsert idiom | Wave 0 foundation — schema reference for AutomationState.db init script |
| `Dereso SWD.bes` | (project — existing) | Analysis providing Users.LastSeen fallback | Dependency for Get-UserComputerMap.ps1 fallback path |
| `Get-FileHash` | Built-in PS5.1+ | SHA1 verification in Stage-Repository.ps1 | `Get-FileHash -Algorithm SHA1 -Path <file>` |
| `Invoke-RestMethod` | Built-in PS7 | BigFix REST API calls in PS scripts | Use with `-SkipCertificateCheck` for BigFix self-signed cert |
| `Register-ScheduledTask` | Built-in Windows PS | Scheduled task registration | Preferred over schtasks.exe for programmatic registration |
| `Write-EventLog` | Built-in PS | Windows Event Log failure alerts (D-18) | Error reporting for Event IDs 8000–8099 |
| `ConvertTo-Json` / `ConvertFrom-Json` | Built-in PS3+ | JSON log output (D-18) and Axonious export parsing | All script structured output |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Invoke-RestMethod` (PS7, `-SkipCertificateCheck`) | `Invoke-WebRequest` + cert callback | Either works; `Invoke-RestMethod` is cleaner for JSON responses; `-SkipCertificateCheck` only in PS7 |
| `Register-ScheduledTask` | `schtasks.exe /Create /XML <file>` | Schtasks.exe is lower-level but cross-version; Register-ScheduledTask is idiomatic PS7 |
| `Get-FileHash -Algorithm SHA1` | Custom SHA1 implementation | Never hand-roll hash; PS built-in is correct and tested |

**Installation:** No npm installs required. No pip installs required. No nuget installs required. All tooling is either built-in to PowerShell or already present in the project.

---

## Package Legitimacy Audit

> Phase 7 introduces zero new external packages. All dependencies are built-in PowerShell cmdlets, existing project files, or pre-vetted tools (sqlite3.exe already in use since Phase 3).

| Package | Registry | Status | Disposition |
|---------|----------|--------|-------------|
| `Sqlite-Helper.ps1` | Project (existing) | Verified in use since Phase 3 | Approved |
| `sqlite3.exe 3.53.1` | Bundled BigFix prefetch (sha1 verified in existing .bes files) | Verified sha1=184d4d0b75cd75c2118fb22a1727e9220f843b98 | Approved |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck not run — no new external packages recommended.*

---

## Architecture Patterns

### System Architecture Diagram

```
[Axonious Export CSV]
        |
        v
[Parse-AxoniousExport.ps1]
        |
        v (user -> [roles] map via GroupRoleMap table)
[Get-UserComputerMap.ps1] <-- POST /api/query (session relevance)
        |                 <-- RoleAwareness.db Users.LastSeen (fallback)
        v (user -> [computer_ids] map)
[Invoke-RoleSync.ps1] -----> POST /api/actions (one per role, SingleAction XML)
        |                     Clients: ActionScript runs, writes RoleAwareness.db
        v
[AutomationState.db]
  SyncRun / RoleAssignment tables
        |
        v (via BigFix Analysis on root server BES client)
[fixlet_automation_monitor.ojo]
  Status / Role Pipeline tabs

---

[BigFix Source Sites] <-- GET /api/fixlets/<siteType>/<siteName>
        |
        v (version-strip, compare, stage decision)
[Invoke-ContentSync.ps1]
        |                 --> POST /api/fixlets/custom/Dereso Software Portal (copy)
        |                 --> PUT /api/fixlet/custom/Dereso Software Portal/<id> (supersede)
        v
[AutomationState.db]
  ContentItem table (discovered -> staged -> categorized -> ready -> live)
        |
        v (on success)
[Stage-Repository.ps1]
        |  parses prefetch lines from portal fixlets
        |  downloads installer files
        |  verifies SHA1 via Get-FileHash
        v
{BES_ROOT}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\{sha1}\{filename}
  (satisfies Dispatcher rewritePrefetchUrls() at deploy time)
        |
        v
[AutomationState.db] CacheEntry table
        |
        v (via BigFix Analysis)
[fixlet_automation_monitor.ojo]
  Content Queue / Repository Cache tabs

---

[fixlet_automation_monitor.ojo] Config tab
        |  admin edits GroupRoleMap / PipelineConfig rows
        v
[AutomationState.db] GroupRoleMap / PipelineConfig tables
  (read by PS scripts on next scheduled run)
```

### Recommended Project Structure

```
scripts/                         # NEW — root server automation scripts
├── Initialize-AutomationDb.ps1  # Wave 0: schema init for AutomationState.db
├── Parse-AxoniousExport.ps1     # Wave 1: CSV parser + GroupRoleMap lookup
├── Get-UserComputerMap.ps1      # Wave 1: BigFix REST user->computer resolver
├── Invoke-RoleSync.ps1          # Wave 1: role pipeline orchestrator
├── Invoke-ContentSync.ps1       # Wave 2: content pipeline orchestrator
└── Stage-Repository.ps1         # Wave 2: installer file pre-staging
config/                          # NEW — config templates
├── GroupRoleMap.json            # Template (imported to DB on first run)
└── PipelineConfig.json          # Default key-value config
Existing Dashboards/
└── fixlet_automation_monitor.ojo  # Wave 3: new automation dashboard
Dashboard_4_samples/
├── Dereso SWD Automation.bes    # NEW Wave 0: Analysis reading AutomationState.db
├── Sqlite-Helper.ps1            # EXISTING — dot-sourced by all new PS scripts
└── Initialize-RoleDb.ps1       # EXISTING — schema reference
tests/
├── fixtures/phase-07/           # Wave 0: test data
│   ├── sample-axonious.csv
│   ├── sample-grouprolemap.json
│   ├── sample-automation-db.sql
│   ├── sample-portal-fixlets.xml
│   └── sample-prefetch-script.txt
├── unit/automation_monitor.test.js  # Wave 3: OJO dashboard function tests
└── integration/automation.integration.test.js  # Wave 4: end-to-end fixtures
docs/
└── automation-admin-guide.md    # Wave 4
```

### Pattern 1: Sqlite-Helper.ps1 Dot-Source and Invocation

**What:** All PowerShell scripts dot-source `Sqlite-Helper.ps1` for all SQLite access. No direct sqlite3.exe calls.

**When to use:** Any time an automation script reads or writes AutomationState.db (or RoleAwareness.db via the Analysis fallback path).

```powershell
# Source: Dashboard_4_samples/Sqlite-Helper.ps1 (verified in codebase)
# Dot-source once at top of script
. "$PSScriptRoot\..\Dashboard_4_samples\Sqlite-Helper.ps1"

# Write (DDL or DML) — returns @()
Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "INSERT OR IGNORE INTO SyncRun (type, started_at, status) VALUES (@type, @start, 'running')" `
    -Parameters @{ type = "RoleSync"; start = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") } | Out-Null

# Read — returns array of PSObjects; access by column name
$rows = Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "SELECT run_id, status, summary FROM SyncRun WHERE type=@type ORDER BY started_at DESC LIMIT 1" `
    -Parameters @{ type = "RoleSync" }
if ($rows.Count -gt 0) { $lastStatus = $rows[0].status }

# Non-ASCII column: use __hex suffix convention
$rows = Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "SELECT hex(summary) AS summary__hex FROM SyncRun WHERE run_id=@id" `
    -Parameters @{ id = $runId }
$summary = $rows[0].summary  # __hex suffix stripped, value decoded by helper
```

**Constraints (MUST follow):**
- `-SQLDir` is the directory containing `sqlite3.exe` directly (no x64/x86 subfolder — SCHEMA-06)
- ONE result-returning statement per call (WR-02 — the helper throws if two SELECT results appear)
- Multiple DDL/DML statements in one `-Sql` are fine (none are result-returning)
- PRAGMA `busy_timeout=30000` is automatically prepended by the helper; callers must NOT add it

### Pattern 2: BigFix REST API from PowerShell

**What:** Server-side PS scripts call the BigFix REST API for relevance evaluation, fixlet enumeration, and action deployment.

**When to use:** All three pipeline scripts need this. Scripts run on root server where BigFix instance is localhost.

```powershell
# Source: CONTEXT.md D-04, D-07 (verified pattern; auth and cert handling [ASSUMED])

# Build Basic auth header (no CLM on root server — [System.Convert] is available)
$pair = "$BESUser:$BESPassword"
$encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
$headers = @{ Authorization = "Basic $encoded"; "Content-Type" = "application/json" }

# POST /api/query — session relevance evaluation (equivalent to OJO EvaluateRelevance)
$body = '{"type":"session","relevance":"(id of it as string & \"|\" & (names of logged on users of it as lowercase) joined by \",\") of bes computers whose (exists logged on users of it)"}'
$response = Invoke-RestMethod -Uri "https://localhost:52311/api/query" `
    -Method Post -Body $body -Headers $headers -SkipCertificateCheck
# $response.result is an array of strings like "12345|user1,user2"

# POST /api/actions — deploy SingleAction XML (same XML as OJO buildAssignActionXml output)
$actionXml = '<BES>...</BES>'  # SingleAction XML (see Pattern 4)
$actionHeaders = @{ Authorization = "Basic $encoded"; "Content-Type" = "application/xml" }
$actionResponse = Invoke-RestMethod -Uri "https://localhost:52311/api/actions" `
    -Method Post -Body $actionXml -Headers $actionHeaders -SkipCertificateCheck
# Parse action ID from response XML

# GET /api/fixlets/<siteType>/<siteName> — list all fixlets in a site
$fixletListResponse = Invoke-RestMethod -Uri "https://localhost:52311/api/fixlets/custom/Dereso%20Software%20Portal" `
    -Method Get -Headers $headers -SkipCertificateCheck
```

**Note:** `-SkipCertificateCheck` requires PS7. D-08 specifies `pwsh.exe` so PS7 is the target runtime. [ASSUMED: BigFix root server certificate is self-signed requiring cert bypass]

### Pattern 3: Upsert Pattern (from Initialize-RoleDb.ps1)

**What:** Two-step upsert that preserves existing Active/Locked_by_Override state. Never use `INSERT OR REPLACE` (it deletes and re-inserts, losing all non-key fields).

**When to use:** All writes to `Map`, `RoleAssignment`, `ContentItem` tables where a row may already exist.

```powershell
# Source: Dashboard_4_samples/Initialize-RoleDb.ps1 lines 203-209 (D-12 upsert pattern)
# Step 1: create if missing (preserves all existing fields)
Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "INSERT OR IGNORE INTO Map (UserID, Role, Active, Created_on, Updated_on, Valid_to)
          VALUES (@uid, @role, 1, datetime('now','localtime'), datetime('now','localtime'),
                  datetime('now','localtime',@validity))" `
    -Parameters @{ uid = $user; role = $Role; validity = "+$ValidityMonths months" } | Out-Null

# Step 2: update timestamp only (respects Locked_by_Override = 1)
Invoke-SqliteCommand -DatabasePath $DbPath -SQLDir $SQLDir `
    -Sql "UPDATE Map SET Active = 1, Updated_on = datetime('now','localtime'),
          Valid_to = datetime('now','localtime',@validity)
          WHERE UserID = @uid AND Role = @role AND Locked_by_Override = 0" `
    -Parameters @{ uid = $user; role = $Role; validity = "+$ValidityMonths months" } | Out-Null
```

### Pattern 4: SingleAction XML for Role Assignment

**What:** Exact XML structure the Role Assigner OJO uses. Invoke-RoleSync.ps1 must produce identical XML for consistency.

**When to use:** `Invoke-RoleSync.ps1` — one XML document per role per pipeline run.

```xml
<!-- Source: Existing Dashboards/fixlet_role_assigner.ojo lines 527-550 (verified) -->
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <SingleAction>
    <Title>Dereso_IT Operations Assign_20260801-0600</Title>
    <Relevance><!-- DB existence guard from Initialize-RoleDb.ps1 --></Relevance>
    <ActionScript MIMEType="application/x-Fixlet-Windows-Shell"><![CDATA[
begin prefetch block
    add prefetch item name=unzip.exe sha1=... size=... url=...
    add prefetch item name=sqlite-tools-win-x64-3530100.zip sha1=184d4d0b... size=... url=...
end prefetch block

    parameter "RootDir"="{ (pathname of parent folder of parent folder of client folder of site "actionsite") as string}"
    parameter "ECDir"="..."
    parameter "SWPDir"="..."
    parameter "TargetStore"="..."
    parameter "SQLiteDir"="..."
    parameter "CompID"="{computer id}"
    parameter "Role"="IT Operations"
    parameter "ValidityMonths"="6"
    parameter "chunk0"="<base64-segment-1>"
    parameter "chunkCount"="1"

    waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ...
    ]]></ActionScript>
    <Settings>
      <ActionUITitle>Dereso_IT Operations Assign_20260801-0600</ActionUITitle>
    </Settings>
    <Target>
      <ComputerID>12345</ComputerID>
      <ComputerID>67890</ComputerID>
    </Target>
  </SingleAction>
</BES>
```

### Pattern 5: Base64 Chunk Encoding in PowerShell

**What:** Replicates the OJO `safeB64Encode` + `chunkString` + `buildChunkParams` chain in PowerShell for the role sync script.

**When to use:** `Invoke-RoleSync.ps1` — encode the user/computer matrix before building the SingleAction XML.

```powershell
# Source: Existing Dashboards/fixlet_role_assigner.ojo lines 288-310 (verified)
# No CLM on root server — [System.Convert]::ToBase64String is available
$matrix = @{ computers = $computerIds; users = $userNames } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($matrix)
$b64 = [System.Convert]::ToBase64String($bytes)

# Chunk into 3000-char segments (CHUNK_SIZE = 3000 from OJO)
$CHUNK_SIZE = 3000
$chunkParamLines = ""
$chunkCount = 0
for ($i = 0; $i -lt $b64.Length; $i += $CHUNK_SIZE) {
    $len = [Math]::Min($CHUNK_SIZE, $b64.Length - $i)
    $chunk = $b64.Substring($i, $len)
    $chunkParamLines += "`tparameter `"chunk$chunkCount`"=`"$chunk`"`r`n"
    $chunkCount++
}
$chunkParamLines += "`tparameter `"chunkCount`"=`"$chunkCount`"`r`n"
```

### Pattern 6: Prefetch Line Parsing for Stage-Repository.ps1

**What:** Extracts sha1, filename, and URL from ActionScript prefetch lines to identify files that must be staged.

**When to use:** `Stage-Repository.ps1` — parse all portal fixlet action scripts.

```powershell
# Source: CONTEXT.md D-10; regex derived from fixlet_dispatcher.ojo lines 388-398 (verified)
$prefetchRegex = [regex]'^prefetch\s+(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:\d+\s+(\S+)'
foreach ($line in $actionScriptLines) {
    $m = $prefetchRegex.Match($line)
    if ($m.Success) {
        $filename = $m.Groups[1].Value
        $sha1     = $m.Groups[2].Value
        $url      = $m.Groups[3].Value
        # target path on root server
        $targetDir  = Join-Path $repoBase $sha1
        $targetFile = Join-Path $targetDir $filename
        if (-not (Test-Path $targetFile)) {
            # download and verify
            Invoke-WebRequest -Uri $url -OutFile "$targetFile.tmp" -UseBasicParsing
            $hash = (Get-FileHash -Path "$targetFile.tmp" -Algorithm SHA1).Hash
            if ($hash -eq $sha1.ToUpper()) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                Move-Item "$targetFile.tmp" $targetFile
            } else {
                Remove-Item "$targetFile.tmp" -Force
                # log as failed
            }
        }
    }
}
```

### Pattern 7: rewritePrefetchUrls Reference (dispatcher.ojo)

The Dispatcher OJO function that this staging satisfies:

```javascript
// Source: Existing Dashboards/fixlet_dispatcher.ojo lines 388-398 (verified)
function rewritePrefetchUrls(script){
  return script.replace(
    /^(prefetch\s+(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:\d+\s+)\S+((?:\s+sha256:[0-9a-fA-F]+)?)$/gim,
    function(match, leader, filename, sha1, tail){
      var newLine = leader + 'http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/' + sha1 + '/' + filename + tail;
      return '// ' + match + '\r\n' + newLine;
    }
  );
}
```

Target path on disk (root server): `{DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\{sha1}\{filename}`

Served at: `http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/{sha1}/{filename}`

### Pattern 8: OJO Automation Dashboard (IE9 Constraints)

**What:** All five tabs of `fixlet_automation_monitor.ojo` must follow the same IE9 constraints as all existing OJO dashboards.

**When to use:** Wave 3 — the entire OJO file.

```javascript
// Source: Existing Dashboards/fixlet_role_assigner.ojo lines 1-56 (verified IE9 pattern)
// MUST use: var, function declarations only
// MUST NOT use: let, const, arrow functions =>, template literals ``, Array.forEach
// MUST use: Msxml2.DOMDocument.6.0 for XML
// MUST use: API.Get / API.Post / API.Put for REST calls
// MUST use: GetRelevance() for Analysis property reads
// MUST use: EvaluateRelevance() for live server-side relevance

// Reading AutomationState.db summary from BigFix Analysis
function loadStatusTab() {
  try {
    var rel = '(name of computer of it as string & "|||" & value of it as string) ' +
              'of results whose (value of it != "") ' +
              'of bes property whose (name of it = "Last SyncRun")';
    var data = GetRelevance(rel);
    // parse and render data
  } catch(e) {
    setStatus("Analysis not available; loading via REST...");
    loadStatusViaRest();
  }
}

// Triggering a manual pipeline run via BigFix Action
function triggerRoleSync() {
  var xml = buildTriggerActionXml("Invoke-RoleSync");
  API.Post("actions", xml, function(e, s, b) {
    if (s === 200 || s === 201) { setStatus("Role sync triggered."); }
    else { setStatus("Failed: " + s); }
  });
}
```

### Pattern 9: Windows Scheduled Task Registration

**What:** Two scheduled tasks registered via PowerShell `Register-ScheduledTask`. Also produce XML files for admin manual import.

**When to use:** `Initialize-AutomationDb.ps1` includes task registration, or a standalone `Register-Tasks.ps1` created in Wave 0.

```powershell
# Source: CONTEXT.md D-08 (pattern [ASSUMED] — standard PS7 cmdlet; no custom code needed)
$scriptsDir = "C:\Program Files (x86)\BigFix Enterprise\BES Server\scripts"
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"$scriptsDir\Invoke-RoleSync.ps1`""
$trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName "Dereso\SoftwarePortal-RoleSync" `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force

# Export XML for admin documentation (schtasks.exe /Query /TN ... /XML)
schtasks.exe /Query /TN "Dereso\SoftwarePortal-RoleSync" /XML > "config\task-RoleSync.xml"
```

**Task chaining (ContentSync → RepoStage):** Windows Task Scheduler does not have a built-in "on completion" dependency between separate tasks. Implement by calling `Start-ScheduledTask -TaskName "Dereso\SoftwarePortal-RepoStage"` at the end of `Invoke-ContentSync.ps1` — simpler and more reliable than event-trigger XML.

### Pattern 10: Structured JSON Log Output (D-18)

**What:** Every pipeline script emits a structured JSON log file alongside its outputs.

**When to use:** All three orchestrator scripts (`Invoke-RoleSync.ps1`, `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`).

```powershell
# Source: CONTEXT.md D-18 (log format specified)
$log = @{
    run_id     = [System.Guid]::NewGuid().ToString("N")
    started_at = $startTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
    ended_at   = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    status     = "success"   # success | partial | failed
    counts     = @{ processed = $total; succeeded = $ok; failed = $fail }
    errors     = @($errorList)
}
$logPath = Join-Path $logDir ("RoleSync-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
$log | ConvertTo-Json -Depth 5 | Set-Content -Path $logPath -Encoding UTF8

# Windows Event Log on failure (Event IDs 8000-8099)
if ($log.status -ne "success") {
    Write-EventLog -LogName Application -Source "DereseSoftwarePortal" `
        -EventId 8001 -EntryType Error -Message "RoleSync failed: $($log.errors | ConvertTo-Json)"
}
# Event Source must be registered first:
# New-EventLog -LogName Application -Source "DereseSoftwarePortal"
```

### Pattern 11: Version Strip and Content Sync Logic

**What:** Same regex as the Update Tracker OJO, applied in PowerShell for the content pipeline.

```powershell
# Source: Existing Dashboards/fixlet_update_tracker.ojo line 988 (verified)
function Strip-Version($name) {
    return [regex]::Replace($name, ' v\d[\d.]+', '')
}

# Compare versions to find updates
$portalMap = @{}
foreach ($fixlet in $portalFixlets) {
    $key = Strip-Version $fixlet.Name
    if (-not $portalMap.ContainsKey($key)) { $portalMap[$key] = @() }
    $portalMap[$key] += $fixlet
}
```

### Pattern 12: GroupRoleMap Wildcard Matching

**What:** Apply group-to-role mapping with exact match and `*`-suffix wildcard.

```powershell
# Source: CONTEXT.md D-03
function Resolve-RolesForGroup($groupName, $groupRoleMapRows) {
    $roles = @()
    $lower = $groupName.ToLower()
    foreach ($row in ($groupRoleMapRows | Sort-Object Priority)) {
        if (-not $row.Active) { continue }
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

### Anti-Patterns to Avoid

- **`INSERT OR REPLACE` in SQLite:** Deletes and re-inserts the row, destroying `Active`, `Locked_by_Override`, `Created_on` values. Always use the two-step `INSERT OR IGNORE` + conditional `UPDATE` pattern from Initialize-RoleDb.ps1.
- **Multiple result-returning statements in one Invoke-SqliteCommand call:** WR-02 enforces one SELECT per call. Mixing two SELECTs in one `-Sql` will throw.
- **`Add-Type` or DLL loading in scripts:** Even though CLM doesn't apply on the root server, project convention is CLM-safe. Use `Sqlite-Helper.ps1` for all SQLite access.
- **`POST /api/fixlets/...` vs `GET /api/fixlet/...`:** POST/list uses plural `fixlets`; GET/PUT individual uses singular `fixlet`. (Verified: update_tracker.ojo line 1578 uses plural `"fixlets/custom/..."` for POST.)
- **Hardcoding BES root path:** Always read from registry `HKLM:\SOFTWARE\BigFix\EnterpriseServer\GlobalSettings` → `DataDirectory`.
- **Hardcoding BigFix credentials:** Store in `PipelineConfig` table; never embed in script source.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite access from PowerShell | Custom sqlite3.exe invocation / DLL loading | `Sqlite-Helper.ps1` (`Invoke-SqliteCommand`) | Injection-safe, busy-timeout, JSON mode, hex decode — all already solved |
| SHA1 file verification | Custom hash loop | `Get-FileHash -Algorithm SHA1` | Built-in, tested, correct |
| Base64 encoding | Custom char table loop | `[System.Convert]::ToBase64String` (no CLM on root server) | Standard .NET; use custom only if you must match the OJO IE9 polyfill byte-for-byte |
| BigFix REST auth | Custom HTTP socket | `Invoke-RestMethod` with Authorization header | Standard PS; handles redirect, timeouts, response parsing |
| Scheduled task XML format | Handwritten XML | `Register-ScheduledTask` + `schtasks.exe /Query ... /XML` for export | Task XML format is complex and version-sensitive |
| JSON log serialization | String concatenation | `ConvertTo-Json -Depth 5` | Handles escaping, nested objects; no manual JSON building |
| Windows Event Log writes | Custom event viewer ETW | `Write-EventLog` | Built-in; just need to register the source once |
| Version comparison | Custom semver parser | `[System.Version]::Parse()` (for dotted) or the same `extractVersion` regex from update tracker | OJO uses string comparison which is fragile for non-dotted; `[System.Version]` is robust |
| Wildcard pattern matching | Full regex engine | Simple `EndsWith('*')` + `StartsWith(...)` (CONTEXT D-03 specifies `*` suffix only) | The spec says only `*` suffix — don't over-engineer to full glob |

**Key insight:** Every hard problem in Phase 7 was already solved in Phases 1–6. The pattern library is complete. The only new code is the glue between existing patterns.

---

## Common Pitfalls

### Pitfall 1: Fixlet vs. Task path singularity on PUT
**What goes wrong:** `PUT /api/fixlet/custom/...` works for a Fixlet; but if the portal item is a Task, the PUT path must be `task/custom/...`.
**Why it happens:** The Update Tracker OJO already handles this: `var pathType = item.isTask ? "task" : "fixlet"`. The content sync script must preserve this distinction.
**How to avoid:** When fetching portal fixlets via REST, check the XML element type (`<Fixlet>` vs `<Task>`) and store in `ContentItem` table as a `is_task` column. Use that column to construct PUT path.
**Warning signs:** HTTP 404 on PUT calls to fixlet-type path for items that are actually Tasks.

### Pitfall 2: BigFix self-signed certificate in PowerShell
**What goes wrong:** `Invoke-RestMethod` throws `The underlying connection was closed: Could not establish trust relationship` against BigFix root server.
**Why it happens:** BigFix ships with a self-signed certificate; PS5.1 `Invoke-RestMethod` has no `-SkipCertificateCheck` parameter.
**How to avoid:** Use `pwsh.exe` (PS7) as specified in D-08. `-SkipCertificateCheck` is a native PS7 parameter for `Invoke-RestMethod`.
**Warning signs:** SSL error on first REST call; works fine from browser with "accept cert" override.

### Pitfall 3: Scheduled Task chaining ContentSync → RepoStage via events
**What goes wrong:** Implementing task chaining via Windows Task Scheduler event triggers (Event ID 102 in Microsoft-Windows-TaskScheduler/Operational) is complex and brittle. The event must be correlated to the specific task instance.
**Why it happens:** No native "on success" trigger between two named tasks in Task Scheduler.
**How to avoid:** End `Invoke-ContentSync.ps1` with `Start-ScheduledTask -TaskName "Dereso\SoftwarePortal-RepoStage"`. Simple, explicit, testable.
**Warning signs:** RepoStage never fires; or fires even when ContentSync failed.

### Pitfall 4: Invoke-SqliteCommand WR-02 multiple result sets
**What goes wrong:** Combining two SELECT statements in one `-Sql` string causes the helper to throw "produced 2 result sets."
**Why it happens:** WR-02 enforcement in Sqlite-Helper.ps1 (verified in source lines 220-223).
**How to avoid:** One SELECT per `Invoke-SqliteCommand` call. Multiple DDL/DML statements are fine (no result sets). Schema creation scripts can combine all DDL.
**Warning signs:** "produced N result sets" exception from helper.

### Pitfall 5: Windows Event Log source registration
**What goes wrong:** `Write-EventLog` throws "The source 'DereseSoftwarePortal' is not registered in log 'Application'."
**Why it happens:** Event sources must be registered before first use (requires admin, done once).
**How to avoid:** `Initialize-AutomationDb.ps1` (Wave 0) calls `New-EventLog -LogName Application -Source "DereseSoftwarePortal"` if not already registered. Check first: `[System.Diagnostics.EventLog]::SourceExists("DereseSoftwarePortal")`.
**Warning signs:** Error on first pipeline run failure; subsequent runs also fail to log.

### Pitfall 6: Axonious group column delimiter normalization
**What goes wrong:** Groups like `"IT-All,IT-Dev, Finance"` parsed with just `,` split miss pipe or semicolon delimiters from different Axonious export configurations.
**Why it happens:** Different Axonious export profiles use different delimiters.
**How to avoid:** Split on `[|;,]` (all three), then trim whitespace and deduplicate. (Specified in CONTEXT.md `<specifics>` section.)
**Warning signs:** Users get zero roles despite having matching groups in the export.

### Pitfall 7: AutomationState.db accessibility from Automation Dashboard
**What goes wrong:** The OJO dashboard cannot directly open a file on the root server; it can only make BigFix API calls.
**Why it happens:** OJO dashboards run in the BigFix Console, not on the server.
**How to avoid:** Deploy a BigFix Analysis BES file (`Dereso SWD Automation.bes`) that reads from `AutomationState.db` on the root server. The root server must be a managed BES client (standard in BigFix deployments). The dashboard reads via `GetRelevance("results of bes property...")`. Provide a fallback via `EvaluateRelevance()` for summary counts.
**Warning signs:** Status tab always shows "no data" even though scripts are running successfully.

### Pitfall 8: Duplicate action deployment (idempotency)
**What goes wrong:** Each `Invoke-RoleSync.ps1` run creates new `POST /api/actions` even for already-assigned users, flooding BigFix with redundant actions.
**Why it happens:** D-06 specifies "for each triple not already in RoleAssignment table" — but this requires checking the RoleAssignment table correctly.
**How to avoid:** Before creating a new assignment, query `RoleAssignment WHERE username=@u AND computer_id=@c AND role=@r AND deployed_at > datetime('now', '-90 days')`. Only create if no current record exists.
**Warning signs:** Action count in BigFix grows unboundedly; client endpoints run the assignment script repeatedly.

### Pitfall 9: PowerShell `ConvertTo-Json` and `-Compress` flag
**What goes wrong:** `ConvertTo-Json` without `-Compress` wraps long strings with line continuations (line length limit), breaking the BigFix REST API body.
**Why it happens:** Default `ConvertTo-Json` inserts newlines into property values over ~$JsonMaxLength chars.
**How to avoid:** Always use `ConvertTo-Json -Compress` for REST API bodies. Use non-compressed for log files (human-readable).
**Warning signs:** BigFix REST API returns 400 Bad Request on `POST /api/query`.

### Pitfall 10: Dashboard trigger button causing double-fire
**What goes wrong:** Admin clicks "Run Now" trigger button; OJO fires an action; then the action appears in BigFix as "Open" and admin clicks it again.
**Why it happens:** IE9-era button click events sometimes fire twice on rapid click; also no guard on re-trigger.
**How to avoid:** Disable the trigger button immediately on click (`document.getElementById("triggerBtn").disabled = true`), show "Running..." status, re-enable on callback completion. Same pattern as the Deploy button in the Dispatcher OJO (verified in fixlet_dispatcher.ojo).

---

## Code Examples

### AutomationState.db Schema (Initialize-AutomationDb.ps1)

```sql
-- Source: CONTEXT.md D-05 (verified schema design; SQL syntax [ASSUMED correct for SQLite])
CREATE TABLE IF NOT EXISTS SyncRun (
    run_id       TEXT PRIMARY KEY,
    type         TEXT NOT NULL,  -- 'RoleSync' | 'ContentSync' | 'RepoStage'
    started_at   TEXT NOT NULL,
    ended_at     TEXT,
    status       TEXT NOT NULL DEFAULT 'running',  -- running | success | partial | failed
    summary      TEXT
);

CREATE TABLE IF NOT EXISTS RoleAssignment (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id       TEXT NOT NULL REFERENCES SyncRun(run_id),
    username     TEXT NOT NULL,
    computer_id  TEXT NOT NULL,
    role         TEXT NOT NULL,
    action_id    TEXT,
    deployed_at  TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);

CREATE TABLE IF NOT EXISTS ContentItem (
    fixlet_id    TEXT NOT NULL,
    source_site  TEXT NOT NULL,
    fixlet_name  TEXT NOT NULL,
    stage        TEXT NOT NULL DEFAULT 'discovered',
    category     TEXT,
    roles        TEXT,
    is_task      INTEGER NOT NULL DEFAULT 0,
    copied_at    TEXT,
    dispatched_at TEXT,
    PRIMARY KEY (fixlet_id, source_site)
);

CREATE TABLE IF NOT EXISTS CacheEntry (
    sha1         TEXT PRIMARY KEY,
    filename     TEXT NOT NULL,
    original_url TEXT,
    staged_at    TEXT,
    size_bytes   INTEGER,
    verified     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS GroupRoleMap (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    group_pattern TEXT NOT NULL,
    role          TEXT NOT NULL,
    priority      INTEGER NOT NULL DEFAULT 0,
    active        INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS PipelineConfig (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT
);
```

### GetRelevance Call for Automation Monitor Dashboard

```javascript
// Source: Existing Dashboards/fixlet_role_assigner.ojo lines 797-817 (verified GetRelevance pattern)
// Adapted for automation monitor Status tab
function loadLastSyncStatus() {
  try {
    var rel = '(name of computer of it as string & "|||" & value of it as string) ' +
              'of results whose (value of it != "") ' +
              'of bes property whose (name of it = "Last RoleSync" AND analysis flag of it)';
    var data = GetRelevance(rel);
    if (!data || data.length === 0) {
      document.getElementById("roleSyncStatus").innerText = "No data (Analysis not reporting)";
      return;
    }
    // parse "computername|||status_json" format
    var parts = String(data[0]).split("|||");
    renderSyncStatus(parts[1]);
  } catch(e) {
    document.getElementById("roleSyncStatus").innerText = "Error: " + e.message;
  }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Dashboard-only (admin-driven) | Scheduled PS pipelines + dashboard for governance | Phase 7 | Admins only review exceptions, not every item |
| BigFix Analysis for role mapping | RoleAwareness.db on clients + Analysis to surface it | Phases 4–5 | DB-backed, not relevance-only; survives user session gaps |
| Manual fixlet copy via OJO | `Invoke-ContentSync.ps1` automated with review queue | Phase 7 | Weekly automation with human approval gate |

**Deprecated/outdated patterns for Phase 7:**
- **Manual CSV upload to Role Assigner:** Replaced by Invoke-RoleSync.ps1 reading Axonious export. Manual CSV via dashboard remains as override/fallback, not primary flow.
- **Admin-driven Update Tracker scan:** Update Tracker remains as preview/manual tool; pipeline runs automatically on schedule.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | BigFix root server is also a managed BES client (required for Analysis approach to read AutomationState.db) | Architecture Patterns, Pitfall 7 | Dashboard cannot surface pipeline status without redesign; must use REST-only fallback throughout |
| A2 | `pwsh.exe` (PS7) is installed on BigFix root server; `-SkipCertificateCheck` available | Standard Stack, Pattern 2 | Must fall back to PS5.1 TrustCertificate callback or proxy cert registration; revisit cert bypass method |
| A3 | BigFix REST API returns `{"result":[...]}` JSON from `POST /api/query` (specific response shape) | Pattern 2 | Response parsing code needs adjustment; API may return XML instead depending on Accept header |
| A4 | `ContentItem` stage `categorized` is set by admin after using Modifier dashboard externally, not by any automation script in Phase 7 | Architecture Map | Stage transition logic in dashboard needs explicit "mark as categorized" button; planner must include this in Content Queue tab spec |
| A5 | sqlite3.exe will be placed in a known path on the root server (not prefetched from BigFix) | Standard Stack | Initialize-AutomationDb.ps1 needs to download or locate sqlite3.exe before any DB operations; planner must add a "check/download sqlite3.exe" task to Wave 0 |
| A6 | `Invoke-ContentSync.ps1` enumerates fixlets via `GET /api/fixlets/<siteType>/<siteName>` REST endpoint (BigFix returns XML list) | Pattern 2 | May need to use `POST /api/query` with session relevance instead; EvaluateRelevance equivalent in PS |
| A7 | `PipelineConfig` key `BESOperatorPassword` is stored as plain text in the SQLite table (no encryption) | Pattern 2 | Credential exposure risk; planner should consider ConvertTo-SecureString storage or Windows Credential Manager |

---

## Open Questions

1. **sqlite3.exe distribution to root server**
   - What we know: sqlite3.exe is distributed to BES clients via BigFix prefetch (sha1 verified). Root server scripts need it too.
   - What's unclear: Is sqlite3.exe already present on the root server from a prior manual install or BES client self-management? Or must `Initialize-AutomationDb.ps1` download it?
   - Recommendation: Wave 0 plan should include a task to download sqlite3.exe to a configured `SQLDir` on the root server if not already present. Provide a `Check-Prerequisites.ps1` script.

2. **AutomationState.db accessibility from OJO dashboard**
   - What we know: BigFix Analysis reads from BES client file systems. If root server is a BES client, the Analysis approach works. Dashboard uses `GetRelevance()`.
   - What's unclear: Is the root server in the environment enrolled as a managed BES client?
   - Recommendation: Design dashboard to always have a REST fallback (read pipeline JSON log files from a web-accessible path, or use `EvaluateRelevance` to query if the path exists). Document both code paths in the OJO.

3. **Credential storage for BigFix operator credentials in PipelineConfig**
   - What we know: Scripts need BigFix operator credentials to call REST API.
   - What's unclear: How sensitive is the environment; whether Windows Credential Manager is acceptable.
   - Recommendation: Store credentials encrypted using `ConvertTo-SecureString | ConvertFrom-SecureString` (DPAPI, machine-scoped). Write a `Set-BESCredential.ps1` helper in Wave 0 that prompts and stores securely.

4. **Automation Dashboard read-back of ContentItem changes**
   - What we know: Dashboard Config tab writes to `GroupRoleMap` and `PipelineConfig` in `AutomationState.db`. But the OJO cannot directly write to a server-side file.
   - What's unclear: The mechanism by which the OJO dashboard modifies `AutomationState.db`. Options: (a) fire a BigFix Action that runs a PS script to write the change, or (b) use a BigFix REST custom property to proxy writes.
   - Recommendation: Config tab changes fire a SingleAction targeted at the root server (BES client) containing a PS script that writes the new config row. This is the same pattern as role assignment. Planner must include a "trigger config-write action" sub-pattern in the Config tab spec.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | JS unit tests | ✓ | v24.15.0 | — |
| PowerShell (pwsh.exe) | All PS scripts | ✓ | 7.6.3 | — |
| sqlite3.exe | Sqlite-Helper.ps1 | ? | unknown — not in bash PATH | Download from BigFix prefetch URL used by existing .bes files (SHA1 verified) |
| BigFix REST API at :52311 | All pipeline scripts | ? (dev machine only) | unknown | Use `-WhatIf` dry-run mode; skip integration tests without `BIGFIX` env var |
| Windows Scheduled Task cmdlets | Task registration | ✓ | Windows 11 Pro (confirmed host) | schtasks.exe /Create /XML fallback |

**Missing dependencies with no fallback:**
- sqlite3.exe must be present on the BES root server at the configured `SQLDir` before any pipeline script can run. Wave 0 must include a step to provision it.

**Missing dependencies with fallback:**
- BigFix REST API: all integration tests use the existing `BIGFIX` env-var skip pattern. `-WhatIf` dry-run mode covers manual pre-production testing.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Node.js built-in `assert` module (verified: all 5 existing test files use this pattern) |
| Config file | none — `node tests/unit/<file>.test.js` invoked directly |
| Quick run command | `node tests/unit/automation_monitor.test.js` |
| Full suite command | `node tests/unit/copier.test.js && node tests/unit/modifier.test.js && node tests/unit/dispatcher.test.js && node tests/unit/role_assigner.test.js && node tests/unit/update_tracker.test.js && node tests/unit/automation_monitor.test.js` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FR-01 (automation layer) | `Invoke-ContentSync.ps1` copies fixlet via POST /api/fixlets/... | integration (BIGFIX-gated) | `node tests/integration/automation.integration.test.js` | ❌ Wave 0 |
| FR-02 (automation layer) | GroupRoleMap wildcard matching: `IT-Dev*` matches `IT-Dev-Alpha` | unit | `node tests/unit/automation_monitor.test.js` | ❌ Wave 0 |
| FR-10 (automation layer) | Content sync version-strip matches same products as Update Tracker | unit | `node tests/unit/automation_monitor.test.js` | ❌ Wave 0 |
| D-05 schema | AutomationState.db schema SQL is valid and all 6 tables created | unit (fixture) | `node tests/integration/automation.integration.test.js` — GROUP A | ❌ Wave 0 |
| D-10 repo stage | Prefetch line regex extracts sha1/filename/url correctly | unit | `node tests/unit/automation_monitor.test.js` | ❌ Wave 0 |
| D-18 log format | JSON log output matches schema `{run_id, started_at, ended_at, status, counts, errors}` | unit | `node tests/unit/automation_monitor.test.js` | ❌ Wave 0 |
| D-03 wildcard | `*`-suffix and exact match in GroupRoleMap resolve to correct roles | unit | `node tests/unit/automation_monitor.test.js` | ❌ Wave 0 |
| D-20 dry-run | `-WhatIf` produces log output without making any API calls | integration (manual) | manual — human-verified | N/A |

### Sampling Rate
- **Per task commit:** `node tests/unit/automation_monitor.test.js`
- **Per wave merge:** Full 6-suite regression gate (161 + new assertions)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/fixtures/phase-07/sample-axonious.csv` — covers Axonious parse patterns (multi-delimiter groups)
- [ ] `tests/fixtures/phase-07/sample-grouprolemap.json` — covers wildcard pattern matching
- [ ] `tests/fixtures/phase-07/sample-automation-db.sql` — schema DDL for in-memory test DB (SQLite-compatible)
- [ ] `tests/fixtures/phase-07/sample-portal-fixlets.xml` — covers prefetch line extraction
- [ ] `tests/fixtures/phase-07/sample-prefetch-script.txt` — covers Stage-Repository regex
- [ ] `tests/unit/automation_monitor.test.js` — covers all pure JS functions in fixlet_automation_monitor.ojo
- [ ] `tests/integration/automation.integration.test.js` — GROUP A: fixture assertions (no BIGFIX), GROUP B: API round-trips (BIGFIX-gated)

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | BigFix operator credentials for REST API; stored via DPAPI ConvertTo-SecureString |
| V3 Session Management | no | Scripts are batch processes; no session state |
| V4 Access Control | yes | BigFix operator permissions scope which computers/sites are visible; no additional RBAC needed |
| V5 Input Validation | yes | Axonious CSV: validate expected columns before processing; group names sanitized before SQL insertion (Sqlite-Helper.ps1 handles injection) |
| V6 Cryptography | no | SHA1 used for file integrity (not security hashing); BigFix prefetch SHA1 is pre-existing spec requirement |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| SQL injection via Axonious CSV group/username fields | Tampering | `Invoke-SqliteCommand` `@param` substitution via `ConvertTo-SqliteLiteral` (single-quote doubling) — verified in Sqlite-Helper.ps1 |
| Plaintext BigFix credentials in PipelineConfig | Info Disclosure | Store via `ConvertTo-SecureString | ConvertFrom-SecureString` (DPAPI); provide `Set-BESCredential.ps1` helper |
| Malicious prefetch URL in a source fixlet replacing a legitimate installer | Tampering | SHA1 verification via `Get-FileHash` before staging; mismatch = download failure + log |
| Unauthorized modification of GroupRoleMap (role escalation) | Elevation of Privilege | GroupRoleMap writes require a BigFix Action (operator must authenticate via BigFix Console); direct DB writes require local admin on root server (which is already a trust boundary) |
| Dashboard trigger button fires pipeline as wrong operator | Elevation of Privilege | BigFix Console enforces operator permissions; `API.Post("actions")` runs as the logged-in operator — same as all existing OJO dashboards |
| Stale Axonious export re-processed (role retention beyond entitlement) | Elevation of Privilege | Check export file modification timestamp; warn if file is older than `MaxExportAgeDays` (configurable, default 2) before processing |

---

## Sources

### Primary (HIGH confidence)

- Codebase: `Dashboard_4_samples/Sqlite-Helper.ps1` — Invoke-SqliteCommand implementation, parameter substitution, WR-02 constraint, hex decode convention
- Codebase: `Dashboard_4_samples/Initialize-RoleDb.ps1` — RoleAwareness.db schema (all 4 tables), upsert pattern, error code range, PRAGMA wal_checkpoint
- Codebase: `Existing Dashboards/fixlet_dispatcher.ojo` lines 388–398 — `rewritePrefetchUrls()` exact regex and output format
- Codebase: `Existing Dashboards/fixlet_role_assigner.ojo` lines 283–795 — `safeB64Encode`, `chunkString`, `buildChunkParams` (CHUNK_SIZE=3000), `buildAssignActionXml`, `buildAssignActionScript`, `GetRelevance` usage, btoa polyfill
- Codebase: `Existing Dashboards/fixlet_update_tracker.ojo` — `stripVersion` regex, `scanNextSite` EvaluateRelevance pattern, `buildSupersededXml`, `copyNextItem` 4-step callback, `fixlets/custom/...` plural vs `fixlet/custom/...` singular
- Codebase: `Dashboard_4_samples/Dereso SWD.bes` — BigFix Analysis property format for reading SQLite DB from BES clients; guards against missing DB

### Secondary (MEDIUM confidence)

- `CONTEXT.md` D-01 through D-20 — 20 locked decisions specifying exact script names, DB schema, table names, stage values, scheduled task names, log format, event ID range
- Bash: `node --version` → v24.15.0, `pwsh --version` → 7.6.3 — confirmed environment availability

### Tertiary (LOW confidence — tagged [ASSUMED] in Assumptions Log)

- BigFix REST API response shape for `POST /api/query` — assumed `{"result":[...]}` based on training data; should be verified against live BigFix instance [ASSUMED]
- PS7 `-SkipCertificateCheck` on `Invoke-RestMethod` accepted by BigFix self-signed cert — assumed; verified as PS7 feature [ASSUMED]
- Root server enrolled as managed BES client — assumed standard deployment; not confirmed for this environment [ASSUMED]

---

## Metadata

**Confidence breakdown:**
- Existing code patterns (Sqlite-Helper, DB schema, OJO functions, prefetch rewrite): HIGH — read directly from source files
- New PowerShell orchestration patterns (BigFix REST from PS7, scheduled tasks, JSON logs): MEDIUM — standard PS7 patterns, BigFix REST assumptions [A1–A3]
- Dashboard read-back of AutomationState.db via Analysis: MEDIUM — standard BigFix Analysis pattern, conditional on root server enrollment [A1]

**Research date:** 2026-08-01
**Valid until:** 2026-09-01 (BigFix API stable; PS7 stable)
