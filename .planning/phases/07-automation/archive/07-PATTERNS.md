# Phase 7: End-to-End Automation - Pattern Map

**Mapped:** 2026-08-29
**Supersedes:** the stale 2026-08-01 07-PATTERNS.md (mapped deleted files `Get-UserComputerMap.ps1`, `Parse-AxoniousExport.ps1`, per-ComputerID SingleActions). This file is built from the 2026-08-29 07-CONTEXT.md rewrite (D-01..D-26) + 07-RESEARCH.md + DESIGN.md.
**Files analyzed:** 20 new/modified (8 root-server scripts, 3 modified server-side files, 1 policy-fixlet template, scheduled-task XML, 3 dashboards, 2 config seeds, 2 test suites, 1 doc)
**Analogs found:** 17 with a concrete in-repo analog / 20 total (streaming CSV ingest, Pester suites, and JSON config seeds have no close analog)

---

## File Classification

| New / Modified file | Role | Data flow | Closest analog | Match quality |
|---|---|---|---|---|
| `scripts/Initialize-AutomationDb.ps1` (NEW) | config / schema-init | batch DDL + key/value seed | `Dashboard_4_samples/Initialize-RoleDb.ps1` | role-match (endpoint DB -> root DB; same idioms) |
| `scripts/Get-BigFixCredential.ps1` (NEW) | utility / credential provider | request-response (HTTPS) | `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1` | exact (same AKeyless call sequence) |
| `scripts/Import-AxoniousExport.ps1` (NEW) | service / ETL ingest | streaming transform + batch upsert | `Initialize-RoleDb.ps1` + `Sqlite-Helper.ps1` `ConvertTo-SqliteLiteral` + `fixlet_update_tracker.ojo` `scanNextSite` loop shape | partial (no streaming-CSV analog in repo) |
| `scripts/Publish-RoleSnapshot.ps1` (NEW) | service / publisher | file-I/O + request-response (REST PUT) | `fixlet_dispatcher.ojo` `rewritePrefetchUrls()`/`extractPrefetchLines()` + `fixlet_update_tracker.ojo` `copyNextItem` PUT | role-match |
| `scripts/Reconcile-LocalRoles.ps1` (NEW, endpoint) | service / reconcile | transform + CRUD upsert | `Initialize-RoleDb.ps1` renew block (L234-257) + `fixlet_role_assigner.ojo` `buildAssignActionScript` embedded upsert (L763-772) | exact (D-12 upsert) |
| `scripts/Invoke-ContentSync.ps1` (NEW) | service / content pipeline | request-response (REST) + transform | `fixlet_update_tracker.ojo` `scanNextSite` (L1146) + `copyNextItem` (L1533) + `buildSupersededXml` (L1499) + `stripVersion` (L987) | role-match (OJO -> PS port) |
| `scripts/Stage-Repository.ps1` (NEW) | service / pre-stage | file-I/O + streaming download + SHA1 verify | `fixlet_dispatcher.ojo` `extractPrefetchLines()` (L606) + `buildStagingActionScript` (L637) + `PREFETCH_STAGE_SCRIPT` | role-match |
| `scripts/Register-AutomationTasks.ps1` (NEW) | config / task registration | batch | `Scheduled_RoleDb_mnc.ps1` block in `Init  Current User and UserRole DB.bes` (L632-685) | role-match |
| `Dashboard_4_samples/Initialize-RoleDb.ps1` (MODIFIED - D-18 Map migration) | config / schema-migration | batch DDL | itself, `PRAGMA table_info(Map)` block (L158-187) | exact (copy the mechanism verbatim) |
| `Dashboard_4_samples/Init  Current User and UserRole DB.bes` (MODIFIED - D-19) | migration / .bes task | ActionScript createfile + schtasks | itself (L620-693) + the two embedded-PS `createfile until _EOF_` blocks | exact |
| `Dashboard_4_samples/Dereso SWD.bes` (MODIFIED - D-23 Source/Region props) | provider / Analysis | Analysis property (client relevance SQLite read) | itself, `mapped_users in r.db` property (L16) | exact (add 2, copy the tuple-split idiom) |
| `bes/RoleRef-Policy-<region>.bes` (NEW template) | route / policy fixlet | prefetch + ActionScript -> embedded PS | `Init  Current User and UserRole DB.bes` prefetch block (L37-47) + relevance guard from `Dereso SWD.bes` `<Relevance>` (L6) / `fixlet_role_assigner.ojo` L459 | role-match |
| `config/task-*.xml` (NEW - scheduled task XML) | config | XML export | `Scheduled_RoleDb_mnc.ps1` `Register-ScheduledTask` block (`Init...DB.bes` L656-678) | role-match (register, then `schtasks /Query /XML` export) |
| `Existing Dashboards/fixlet_role_admin.ojo` (NEW) | component / dashboard | request-response (API.Get/Post/Put) + tab UI | `fixlet_role_assigner.ojo` (split from) + `fixlet_console.ojo` `switchTab` (L322) | role-match |
| `Existing Dashboards/fixlet_role_assigner.ojo` (MODIFIED - D-23) | component / dashboard | Analysis read (GetRelevance) | itself, `loadAnalysisView()` (L798) | exact |
| `Existing Dashboards/fixlet_automation_monitor.ojo` (NEW) | component / dashboard | request-response + tab UI + table render | `fixlet_update_tracker.ojo` `switchTab` (L1358) + `renderUpdatesTable` (L1194) + scan loop; `fixlet_console.ojo` sub-tabs | role-match |
| `config/GroupRoleMap.json` + `config/PipelineConfig.defaults.json` (NEW seeds) | config | static JSON | `PORTAL_CONFIG` block (`fixlet_role_assigner.ojo` L40-53); `scripts/category_map_output.js` (generated JSON shape) | partial |
| `tests/pester/*.Tests.ps1` (NEW - Pester 5) | test | - | none (no PowerShell test precedent in repo) | none |
| `tests/unit/role_admin.test.js` (NEW - Node assert) | test | - | `tests/unit/role_assigner.test.js`, `tests/unit/copier.test.js` | exact |
| `docs/automation-admin-guide.md` (NEW) | doc | - | `docs/role-assigner-admin-guide.md` | exact (same heading skeleton) |

---

## Pattern Assignments

### `scripts/Initialize-AutomationDb.ps1` (schema-init, batch DDL)

**Analog:** `Dashboard_4_samples/Initialize-RoleDb.ps1` (whole file, 264 lines - read it end to end)

**Header + strict-mode + dot-source pattern** (`Initialize-RoleDb.ps1` L1-2, L60-79):
```powershell
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$DatabasePath = '...\AutomationState.db',
    [string]$SQLDir       = '...\sqlite',
    [int]$ValidityMonths  = 6
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$logfile = Join-Path (Split-Path $DatabasePath) 'SWDlog.log'
Add-Content -Path $logfile -Value "----Starting"
. "$PSScriptRoot\Sqlite-Helper.ps1"
```

**Table-exists guard + [CREATE]/[SKIP] logging** (`Initialize-RoleDb.ps1` L126-146) - copy this loop shape for every new table (`Role`, `Region`, `GroupRoleMap`, `RefUser`, `UserRole`, `RolePublication`, `Snapshot`, `SyncRun`, `PipelineConfig`, `ContentItem`, `ContentCache`):
```powershell
$before = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
    -Sql "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name=@n" `
    -Parameters @{ n = $tbl.Name }
if ($before[0].n -eq 1) { Write-Host "[SKIP] $($tbl.Name) ..."; Add-Content ... }
else { Invoke-SqliteCommand ... -Sql $tbl.Ddl | Out-Null; Write-Host "[CREATE] ..." }
```

**DDL house style** (`Initialize-RoleDb.ps1` L83-123): `CREATE TABLE IF NOT EXISTS`, `INTEGER PRIMARY KEY AUTOINCREMENT`, `TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))`, `UNIQUE(col, col)` on its own line. Full role-table DDL is already written in 07-RESEARCH.md L738-807 and DESIGN.md L119-246 - use those verbatim, they were authored in this style.

**Partial index pattern** (`Initialize-RoleDb.ps1` L150-155, L180-184):
```powershell
Invoke-SqliteCommand ... -Sql @"
CREATE INDEX IF NOT EXISTS idx_map_expiry ON Map (Valid_to)
    WHERE Active = 1 AND Locked_by_Override = 0
"@ | Out-Null
```

**Role seeding = INSERT OR IGNORE, skip-if-populated** (`Initialize-RoleDb.ps1` L191-208) - use the same shape for the 13-value `Region` seed (D-21) and the `PipelineConfig` key/value seed (keys listed in 07-RESEARCH.md Discretion Resolutions L147 / DESIGN.md L248-256):
```powershell
$roleCount = Invoke-SqliteCommand ... -Sql "SELECT COUNT(*) AS n FROM Roles"
if ($roleCount[0].n -gt 0) { Write-Host "[SKIP] ..." }
else { foreach ($r in $defaultRoles) { Invoke-SqliteCommand ... -Sql "INSERT OR IGNORE INTO Roles (Role) VALUES (@role)" -Parameters @{ role = $r } | Out-Null } }
```

**WAL checkpoint in finally** (`Initialize-RoleDb.ps1` L259-263):
```powershell
} finally {
    try { Invoke-SqliteCommand ... -Sql "PRAGMA wal_checkpoint(TRUNCATE)" | Out-Null } catch {}
}
```

**New-in-this-file (no analog):** `New-EventLog`/`SourceExists("DereseSoftwarePortal")` registration (07-RESEARCH.md Pitfall 7 L688-689) and the root-server `sqlite3.exe` provisioning check (07-RESEARCH.md Runtime State L606) - both are greenfield; follow the research text.

**Numeric error-code convention:** `Initialize-RoleDb.ps1` uses `throw 5100..5400` per step (L146, L156, L187, L208, L231, L257). Continue the scheme for the new steps.

---

### `scripts/Get-BigFixCredential.ps1` (credential provider, request-response)

**Analog:** `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1` (41 lines, exact)

**Auth + fetch sequence** (`0_Retrieve_AKeylessVal.ps1` L17-30):
```powershell
$uidToken = (Get-Content -Path $vaultkeypath).ToString()
$auth = Invoke-RestMethod -Method POST -Uri 'https://api.akeyless.io/auth' -ContentType 'application/json' `
        -Body (@{ 'access-type'='universal_identity'; 'uid-token'=$uidToken } | ConvertTo-Json)
if ([string]::IsNullOrEmpty($auth.token)) { throw 'Akeyless UID auth returned no token' }
$resp = Invoke-RestMethod -Method POST -Uri 'https://api.akeyless.io/get-secret-value' -ContentType 'application/json' `
        -Body (@{ names=@($path); token=$auth.token } | ConvertTo-Json)
$pwPlain = $resp.$path
if ([string]::IsNullOrEmpty($pwPlain)) { throw "Akeyless returned empty password for $path" }
```

**Deviations required from the analog (07-RESEARCH.md Pattern 7 L487-510, Security Domain L1039):**
- Token file = `PipelineConfig.AKeylessTokenFile` = `...\BES Client\EC\Cyera\.vault-token` (Cyera's - read only, never write it).
- Secret path = `PipelineConfig.AKeylessSecretPath` = `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator`.
- Return `[pscredential]::new($UserName, (ConvertTo-SecureString $pw -AsPlainText -Force))` - do NOT return plaintext.
- **DO NOT COPY** the analog's `Write-Host "  fetched, length=... Value=$pwPlain"` (L30) or `Start-Transcript` (L9) - the wrapper must never log the secret or the token.
- Fail loud on: missing token file, blocked egress, empty secret, clock-skew UID rejection (Event 8000-8099).

---

### `scripts/Import-AxoniousExport.ps1` (ETL ingest, streaming transform + batch upsert)

**Analog (partial - no streaming-CSV file exists in repo):** compose from four sources.

1. **Streaming read + no-collection rule** - 07-RESEARCH.md Pattern 2 (L386-407) and Pitfall 9 (L701-706). There is no codebase analog; use `Import-Csv -Path $csv | ForEach-Object { ... }` with no variable assignment. Column access by exact header string, e.g. `$row.'Azure Ad: AD sAMAccountName'` (07-RESEARCH.md L409).

2. **Batched multi-row INSERT** built with `ConvertTo-SqliteLiteral` - the helper exports it (`Sqlite-Helper.ps1` L69-84). Batch 200-500 rows per `BEGIN;...COMMIT;` call (07-RESEARCH.md Pattern 2 L388-406, Pitfall 6 L678-683):
```powershell
$sql = "BEGIN;`nINSERT OR IGNORE INTO UserRole (...) VALUES`n$values;`nCOMMIT;"
Invoke-SqliteCommand -DatabasePath $Db -SQLDir $SQLDir -Sql $sql | Out-Null
```
Multiple non-result statements per call are allowed (WR-02, `Sqlite-Helper.ps1` L20-28).

3. **Per-user RefUser upsert** = `INSERT OR IGNORE` + `UPDATE ... SET Last_Seen=..., Last_RunID=@run` (07-RESEARCH.md Pattern 1 L365-369). Same two-step discipline as `Initialize-RoleDb.ps1` L224-231 - but note that file's `Users` table uses `INSERT OR REPLACE` (L225); **do not copy that** onto any table with state columns (07-RESEARCH.md Anti-patterns L555).

4. **Scan-loop / progress-logging shape** - `fixlet_update_tracker.ojo` `scanNextSite` (L1146-1175): iterate a config-driven list, accumulate into a flat array, log "N of M ... (X so far)". Port the shape to PS with `SyncRun` row updates instead of `setStatus`.

**Pure functions to factor out for Pester (07-RESEARCH.md Seams L980-986):**
- `Resolve-Roles -GroupViews @{cn=..;display=..;dn=..} -Rules $rows` (GroupRoleMap matcher: exact NOCASE + `*`-suffix, `Match_On` selects the view - D-08, Pitfall 10 L708-716).
- username coalesce sam -> upn-localpart -> `Aggregated: User Name`, `.ToLower()`, record `Username_Src` (D-06).
- `Source_Type` derivation from `Assigned Groups: Group Type` + `Assigned Groups: Email` presence (D-08).
- age-out sweep: `UPDATE UserRole SET Active=0 WHERE Last_RunID <> @run` (D-09).

**No auth/guard** - this script never touches BigFix; it reads a disk file and writes the local `AutomationState.db`.

---

### `scripts/Publish-RoleSnapshot.ps1` (publisher, file-I/O + REST PUT)

**Analogs:** `fixlet_dispatcher.ojo` (prefetch URL shape) + `fixlet_update_tracker.ojo` `copyNextItem` (REST) + `Initialize-RoleDb.ps1` (SQLite reads).

**Snapshot query** (07-RESEARCH.md L845-846) - one result-returning SELECT per `Invoke-SqliteCommand` call (WR-02):
```sql
SELECT DISTINCT ur.UserID FROM UserRole ur WHERE ur.Active=1 AND ur.Role=@role
```
filtered to `(role, region)` Active in `RolePublication` (RegionID match OR NULL).

**Snapshot write + `.sha1` manifest** (07-RESEARCH.md Code Examples L850-858):
```powershell
$json  = $snapshot | ConvertTo-Json -Depth 6 -Compress      # -Compress is mandatory (Anti-patterns L562)
$sha1  = (Get-FileHash -Algorithm SHA1 -Path $latest).Hash.ToLower()
Set-Content -Path "$latest.sha1" -Value "$sha1  $(Split-Path $latest -Leaf)" -Encoding ASCII
```
Output dir derived from registry `HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server` -> `wwwRootFolder` then `\Uploads\CustomRepository\SoftwarePortal\roleref\` (07-RESEARCH.md Pattern 9 L549, A10 L908). `PipelineConfig.SnapshotOutputDir` is an override, not the default.

**Prefetch line the re-PUT must emit** (must match `rewritePrefetchUrls()` in `fixlet_dispatcher.ojo` L591-599 byte-for-byte):
```
prefetch roleref-<region>-latest.json sha1:<sha1> size:<bytes> http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/roleref-<region>-latest.json
```

**REST PUT of the per-region policy fixlet** - pattern from `fixlet_update_tracker.ojo` `copyNextItem` step 4 (L1596-1610): `PUT fixlet/custom/<site>/<id>` (singular for one item), dual-status check `s === 200 || s === 201`, always handle the failure branch. In PS: `Invoke-RestMethod -Method PUT` with `Get-BigFixCredential` output and (PS7) `-SkipCertificateCheck`. **Pitfall 3 (L642-653): this re-PUT every run is the single most important operational detail** - the `sha1:`/`size:` change daily.

**Logging:** write `Snapshot` + `SyncRun` (Type=`Publish`) rows (D-13), same style as `Initialize-RoleDb.ps1` step logging.

---

### `scripts/Reconcile-LocalRoles.ps1` (endpoint reconcile, CRUD upsert)  [prompt lists this under scripts/; 07-RESEARCH.md L325-326 suggests endpoint/ - planner's call]

**Analogs:** `Initialize-RoleDb.ps1` renew block (L234-257) + `fixlet_role_assigner.ojo` `buildAssignActionScript` embedded upsert (L744-780).

**Param seam** (07-RESEARCH.md Pattern 6 L470-483) - `-ConsoleUser` is the test seam; CI never exercises the `explorer.exe` branch:
```powershell
param([string]$ConsoleUser, [string]$Region, [string]$SnapshotDir, [string]$SQLDir, [string]$DatabasePath)
if ([string]::IsNullOrWhiteSpace($ConsoleUser)) {
    # logon-task path only - same query Initialize-RoleDb.ps1 L213 already uses
    $ConsoleUser = (Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" |
        Invoke-CimMethod -MethodName GetOwner | Select-Object -ExpandProperty User -First 1)
    if ($ConsoleUser) { $ConsoleUser = $ConsoleUser.Split('\')[-1].ToLower() }
}
if (-not $ConsoleUser) { Write-Host "[SKIP] no console user"; return }
```

**Region re-check / abort** (D-15): read `roleref-<region>-latest.json`, `ConvertFrom-Json`, abort if `snapshot.region -ne $Region`.

**D-12 upsert - copy verbatim from `Initialize-RoleDb.ps1` L242-257** (the `UPDATE ... ; SELECT changes() AS n` must be ONE `Invoke-SqliteCommand` call - `changes()` is connection-scoped, comment at L239-241). Extended for the new `Map` columns (07-RESEARCH.md Pattern 1 L377-383):
```powershell
# step 1
Invoke-SqliteCommand ... -Sql "INSERT OR IGNORE INTO Roles (Role) VALUES (@r)" -Parameters @{ r=$role } | Out-Null
Invoke-SqliteCommand ... -Sql "INSERT OR IGNORE INTO Map (UserID, Role, Active, Created_on) VALUES (@u,@r,1,datetime('now','localtime'))" -Parameters @{ u=$ConsoleUser; r=$role } | Out-Null
# step 2 - guarded UPDATE, never INSERT OR REPLACE
$res = Invoke-SqliteCommand ... -Sql @"
UPDATE Map SET Active=1, Updated_on=datetime('now','localtime'),
       Valid_to=datetime('now','localtime',@v),
       Source_Type=@st, Source_Value=@sv, Region=@rg, Assigned_By='AxoniousSync'
 WHERE UserID=@u AND Role=@r AND Locked_by_Override = 0;
SELECT changes() AS n
"@ -Parameters @{ v="+$ValidityMonths months"; st=$srcType; sv=$srcVal; rg=$Region; u=$ConsoleUser; r=$role }
```
`Source_Value` is `|`-joined if the user got the role from >1 group (D-15).

**Freshness stamp** (07-RESEARCH.md Discretion Resolutions L150, recommended v1): after a successful reconcile write client setting `roleref_<region>_applied` = `snapshot.built_on`.

**Compare to `fixlet_role_assigner.ojo` L763-772** - the CSV break-glass path does the same three statements (`INSERT OR IGNORE Users`, `INSERT OR IGNORE Map`, guarded `UPDATE Map`) but keyed on a `{computer id}` match; the reconcile drops the ComputerID match entirely (D-02) and keys on `$ConsoleUser`.

---

### `scripts/Invoke-ContentSync.ps1` (content pipeline, REST + transform) - UNCHANGED intent (07-03)

**Analogs:** `fixlet_update_tracker.ojo` + `fixlet_copier.ojo`.

- **Site scan:** `scanNextSite` (`fixlet_update_tracker.ojo` L1146-1175) - `EvaluateRelevance` over `bes fixlets whose (name of site of it = "..." and (fixlet flag of it or task flag of it))`, `\x1F`-delimited tuple, iterate `PORTAL_CONFIG.sourceSites`. Port to `POST /api/query` or `GET /api/fixlets/<type>/<site>`.
- **Version strip:** `stripVersion` (`fixlet_update_tracker.ojo` L987) = `[regex]::Replace($name, ' v\d[\d.]+', '')`; `extractVersion` L992. (07-RESEARCH.md Pattern 9 L542, Don't-Hand-Roll L580).
- **4-step copy:** `copyNextItem` (`fixlet_update_tracker.ojo` L1533-1614): GET portal XML -> GET source XML -> `POST fixlets/custom/<site>` (**plural**, BigFix infers Task vs Fixlet from body) -> `PUT <fixlet|task>/custom/<site>/<id>` (**singular**). Always recurse on success AND error (partial-failure model). `pathType = item.IsTask ? 'task' : 'fixlet'` (07-RESEARCH.md Pattern 9 L544).
- **Supersede stamp:** `buildSupersededXml` (`fixlet_update_tracker.ojo` L1499-1528) - strip any existing `X-Superseded-By` MIMEField via regex first (idempotent), then insert before `<Domain>`. Uses `Msxml2.DOMDocument.6.0` in OJO; in PS use `[xml]` or string regex.
- **Category/role MIME transfer:** `buildRoleRelevanceFromValue` (`fixlet_update_tracker.ojo` L1383), `CATEGORY_MAP`.
- **Task chaining:** end the script with `Start-ScheduledTask -TaskName '<RepoStage task>'` (07-RESEARCH.md Pattern 9 L550).
- **DB:** write `ContentItem` (stages `discovered|staged|categorized|ready|live|rejected`) + `SyncRun` (Type=`ContentSync`), schema at 07-RESEARCH.md L812-817.

---

### `scripts/Stage-Repository.ps1` (pre-stage, file-I/O + SHA1 verify) - UNCHANGED intent (07-03)

**Analog:** `fixlet_dispatcher.ojo` `extractPrefetchLines()` (L606-620) + `buildStagingActionScript` (L637) + `PREFETCH_STAGE_SCRIPT` / `Invoke-PrefetchStage.ps1`.

**Prefetch-line regex** (07-RESEARCH.md Pattern 9 L547, matches `extractPrefetchLines` L608):
```powershell
$rx = [regex]'^(?:prefetch\s+)?(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:(\d+)\s+(\S+)(?:\s+sha256:([0-9a-fA-F]+))?'
```
Download from the **original** URL (`m[4]`, not a rewritten `127.0.0.1` one - the OJO comment at L601-605 is explicit), `Get-FileHash -Algorithm SHA1`, verify against `sha1:`, place under `{wwwRootFolder}\Uploads\CustomRepository\SoftwarePortal\<sha1-lowercase>\<file>`. Mismatch = discard + log (Security Domain L1037). `wwwRootFolder` from the registry (07-RESEARCH.md Pattern 9 L549). Write `ContentCache` + `SyncRun` (Type=`RepoStage`).

---

### `scripts/Register-AutomationTasks.ps1` + `config/task-*.xml` (task registration)

**Analog:** the `Scheduled_RoleDb_mnc.ps1` block embedded in `Init  Current User and UserRole DB.bes` (L632-685):
```powershell
$action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"...`" -DatabasePath `"...`" -SQLDir `"...`""
$trigger = New-ScheduledTaskTrigger -AtLogOn        # for ingest/publish use -Daily -At
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
Register-ScheduledTask -TaskName "..." -Action $action -Trigger $trigger -Settings $settings -User "SYSTEM" -RunLevel Highest -Force
```
Then `schtasks.exe /Query /TN <name> /XML > config/task-<name>.xml` to export for the run-book (07-RESEARCH.md Supporting L198). New root tasks: ingest (daily), publish (daily, after ingest), content-sync, repo-stage.

**Guard caveat (Pitfall 5, L667-676):** the analog gates registration on `if {not (exists (scheduled tasks whose (name of it = "RoleDB_Maintenance")))}`. For `RoleDB_Maintenance` re-registration (D-19) you must `Unregister-ScheduledTask -TaskName RoleDB_Maintenance -Confirm:$false` (ignore-not-found) *before* the guarded re-register, or gate on a version marker file - otherwise already-provisioned endpoints never pick up the new command line.

---

### `Dashboard_4_samples/Initialize-RoleDb.ps1` (MODIFIED - D-18 Map migration)

**Analog:** itself, the `PRAGMA table_info(Map)` block at **L158-187**. Add a fourth-through-seventh column exactly like `Updated_on`/`Valid_to` (07-RESEARCH.md Code Examples L826-834):
```powershell
$mapCols = @(Invoke-SqliteCommand ... -Sql "PRAGMA table_info(Map)" | ForEach-Object { $_.name })
foreach ($c in 'Source_Type','Source_Value','Region','Assigned_By') {
  if ($mapCols -notcontains $c) {
    Invoke-SqliteCommand ... -Sql "ALTER TABLE Map ADD COLUMN $c TEXT" | Out-Null
    Add-Content -Path $logfile -Value "[MIGRATE] Map.$c column added"
  } else { Add-Content -Path $logfile -Value "[SKIP] Map.$c already present" }
}
```
Keep `throw 5400` for this block. No change to `UNIQUE(UserID, Role)`, `Active`, `Locked_by_Override`, `Valid_to`, or the L242-257 renew upsert. Also finalise the uncommitted v3 logon-rework already in the working tree (memory `role-awareness-logon-rework-status`) and commit it under Phase 7 (D-18).

---

### `Dashboard_4_samples/Init  Current User and UserRole DB.bes` (MODIFIED - D-19)

**Analog:** itself. The file already has the full pattern to copy from:
- `begin prefetch block` / `add prefetch item name=... sha1=... size=... url=http://127.0.0.1:{...port...}/Uploads/CustomRepository/...` (L37-40).
- Directory param idioms `parameter "SWPDir"="{(concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal")))}"` (L43-47).
- `createfile until _EOF_` ... `_EOF_` ... `move __createfile "..."` (L91-345, L349-615) - **note the `{`->`{{` escaping inside these blocks** (e.g. `@{{`, `if (...) {{`, closing `}` stays single).
- `action uses wow64 redirection {x64 of operating system}` + `waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "..." -DatabasePath "..." -SQLDir "..."` (L617-618, L687-688).
- `RoleDB_Maintenance` registration nested in `if {exists file (parameter "TargetStore")}` + `if {not (exists (scheduled tasks whose (name of it = "RoleDB_Maintenance")))}` (L624-693).

**Change (D-19):** the `Scheduled_RoleDb_mnc.ps1` it writes (L634-684) must register a task that runs **both** `Initialize-RoleDb.ps1` and `Reconcile-LocalRoles.ps1` (or a small wrapper), and must `Unregister-ScheduledTask` first (Pitfall 5). Also createfile `Reconcile-LocalRoles.ps1` into `SWPDir` alongside the existing two embedded PS files.

---

### `Dashboard_4_samples/Dereso SWD.bes` (MODIFIED - D-23, add 2 Analysis properties)

**Analog:** itself, `mapped_users in r.db` (ID=3, **L16**):
```
<Property Name="mapped_users in r.db" ID="3" EvaluationPeriod="PT5M"> (following text of first "%22" of tuple string item 0 of it, preceding text of first "%22" of tuple string item 1 of it) of((((rows of statement "select UserID || ', ' || Role from map where Active = 1" of it) as string)) of sqlite database of file "RoleAwareness.db" of folder it)  of ((concatenation (if windows of operating system then "\" else "/") of ( (item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal"))) )</Property>
```
Add `map_source in r.db` (ID=5) and `map_region in r.db` (ID=6), `EvaluationPeriod="PT5M"`, SELECT `UserID || ', ' || Role || ', ' || coalesce(Source_Value,'')` / `coalesce(Region,'')`, with a 3-item tuple split (07-RESEARCH.md Discretion Resolutions L152, Code Examples L863-871). Keep the top-level `<Relevance>` DB-existence guard (L6) untouched.

---

### `bes/RoleRef-Policy-<region>.bes` (NEW - per-region policy fixlet template)

**Analogs:** `Init  Current User and UserRole DB.bes` (prefetch + param + wow64 idioms, above) + the DB-existence relevance guard.

**Combined `<Relevance>`** (07-RESEARCH.md Pattern 4 L420-435) - build ONE string, ANDed:
```
# DB-existence guard - verbatim from Dereso SWD.bes L6 / fixlet_role_assigner.ojo L459
(exists folder it whose (exists files "RoleAwareness.db" whose (exists sqlite database of it) of it)) of
  ((concatenation (if windows of operating system then "\" else "/") of
    ((item 0 of it;item 1 of it;item 2 of it) of
     ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal"))))
AND (exists setting "GPC_Sub_Name" whose (value of it as string as lowercase = "<region-lc>") of client)
AND ((not exists setting "roleref_<region-lc>_applied" of client)
     OR (now - ((value of setting "roleref_<region-lc>_applied" of client) as string as time) > 1 * day))
```
The `<region-lc>` literal is substituted by `Publish-RoleSnapshot.ps1` when it renders the per-region `.bes` from this template.

**ActionScript** (07-RESEARCH.md Pattern 5 L442-461): `prefetch roleref-<region>-latest.json sha1:<from-manifest> size:<bytes> http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/roleref-<region>-latest.json`, then `parameter "SWPDir"=...` / `parameter "ConsoleUser"="{name of current user as lowercase}"` / `parameter "Region"="{value of setting "GPC_Sub_Name" of client as string}"`, `copy "__Download\..." "{parameter "SWPDir"}\roleref\..."`, `action uses wow64 redirection {x64 of operating system}`, `waithidden powershell.exe ... -File "{parameter "SWPDir"}\Reconcile-LocalRoles.ps1" -ConsoleUser "{parameter "ConsoleUser"}" -Region "{parameter "Region"}" ...`.

**Must be a Fixlet / SingleAction, NOT `SourcedFixletAction`** (Anti-patterns L560) - server-side `<CustomRelevance>` on a dynamic group yields 0 computers.

---

### `Existing Dashboards/fixlet_role_admin.ojo` (NEW dashboard)

**Analogs:** `fixlet_role_assigner.ojo` (split from) + `fixlet_console.ojo` tab pattern.

**Head boilerplate** (`fixlet_role_assigner.ojo` L10-35): `<meta http-equiv="X-UA-Compatible" content="IE=9">`, the CSS class set (`.panel .panelBody .tableGrid .btn .btnGreen .warn-row .error-row`), `<script language="javascript">`.

**Tab switch** (`fixlet_console.ojo` L322-332, or `fixlet_update_tracker.ojo` `switchTab` L1358-1367) - 07-RESEARCH.md Pattern 8 L519-528. For tabs `GroupRoleMap | RolePublication | Region | ReferenceDB`:
```javascript
function switchTab(tab){
  var ids = ["GroupRoleMap","RolePublication","Region","ReferenceDB"];
  var i, panel, btn;
  for(i=0;i<ids.length;i++){
    panel = document.getElementById("tab"+ids[i]);
    btn   = document.getElementById("tabBtn"+ids[i]);
    if(panel){ panel.style.display = (ids[i]===tab) ? "" : "none"; }
    if(btn){ btn.className = (ids[i]===tab) ? "tabBtn tabActive" : "tabBtn"; }
  }
}
```

**Lift verbatim from `fixlet_role_assigner.ojo`:** `btoa` polyfill (L59-72), `htmlEscape` (L83-89), `xmlEscape` (L98-105), `cdataStart/cdataEnd/xmlCDataSafe` (L107-109), `safeB64Encode` (L289-292), `chunkString` (L295-301), `buildChunkParams` + `CHUNK_SIZE=3000` (L304-313), `setStatus` (L92-95).

**Analysis read (Reference DB tab)** - `loadAnalysisView()` (`fixlet_role_assigner.ojo` L798-873): `GetRelevance('(name of computer of it as string & "|||" & value of it as string) of results whose (value of it != "") of bes property whose (name of it = "...")')`, split on `|||` then `, `, `htmlEscape` every value before `innerHTML`, `try/catch` -> "Analysis not imported yet" message (Pitfall 8 L692-699).

**GroupRoleMap write** (07-RESEARCH.md Pattern 8 L536-537): a SingleAction targeted at the root-server BES client running an embedded PS snippet that does `Invoke-SqliteCommand` against `AutomationState.db`. Build the SingleAction XML with the `buildAssignActionXml` element order from `fixlet_role_assigner.ojo` L528-550 (Title -> Relevance -> ActionScript -> Settings -> Target - Anti-patterns L561) and the embedded-PS `createfile`/`move` + `{`->`{{` escaping from `escapeActionScriptBraces` (`fixlet_dispatcher.ojo` L630-632).

**"Test Pattern" field:** a JS mirror of the PS `Resolve-Roles` matcher (exact NOCASE + `EndsWith('*')` prefix test) - keep the two in lockstep, unit-tested both sides.

---

### `Existing Dashboards/fixlet_role_assigner.ojo` (MODIFIED - D-23)

**Analog:** itself, `loadAnalysisView()` (L798-873). Add two columns to `#analysisBody`: read the new `map_source in r.db` / `map_region in r.db` properties via the same `GetRelevance` call shape, split, `htmlEscape`, append `<td>`. Demote the CSV path in the UI copy (keep the code). No structural change to `parseCsv`/`validateRows`/`deployNextRole`.

---

### `Existing Dashboards/fixlet_automation_monitor.ojo` (NEW dashboard, content-pipeline only)

**Analogs:** `fixlet_update_tracker.ojo` (closest - it is the OJO the content pipeline automates) + `fixlet_console.ojo` sub-tabs.

- Tab switch: `fixlet_update_tracker.ojo` `switchTab` (L1358) / `updateTabBadges` (L1370-1375) for tabs `Status | Content Queue | Repository Cache | Config`.
- Table render: `renderUpdatesTable` (`fixlet_update_tracker.ojo` L1194-1225) - `document.createElement("table")`, `t.className="tableGrid"`, `makeSortHeader`, insert rows.
- Data: `GetRelevance` on `Dereso SWD.bes` (or a new `AutomationState.bes` Analysis) properties for `SyncRun` / `ContentItem` / `ContentCache` counts, with an `EvaluateRelevance`/REST fallback (Pitfall 8). Show the Analysis `<last reported>` time next to counts (Pitfall 12 L726-730).
- Config tab: `PORTAL_CONFIG`-style block + a form that writes `PipelineConfig` via a root-server-targeted SingleAction (same mechanism as the role-admin GroupRoleMap write). **No Role tab** (D-24).

---

### `config/GroupRoleMap.json` + `config/PipelineConfig.defaults.json` (NEW seeds)

**Analog (partial):** `PORTAL_CONFIG` object literal (`fixlet_role_assigner.ojo` L40-53) for the shape of a hand-edited config block; `scripts/category_map_output.js` for a generated-JSON-in-repo precedent. `PipelineConfig` keys are enumerated in 07-RESEARCH.md Discretion Resolutions L147 and DESIGN.md L248-256. `GroupRoleMap` seed columns (`Pattern`, `Match_On`, `Role`, `Priority`, `Active`, `Notes`) from DESIGN.md L146-158; **rule content is deferred** (go-live blocker, not a phase blocker - 07-CONTEXT deferred L395-399) - ship synthetic rules for tests only.

---

### `tests/pester/*.Tests.ps1` (NEW - Pester 5) - NO ANALOG

No PowerShell test exists in the repo. Use Pester 5.7.1, v5 syntax, `Import-Module Pester -MinimumVersion 5.0` (co-installed 3.4.0 must be avoided). Files: `Import-AxoniousExport.Tests.ps1`, `GroupRoleMap.Tests.ps1`, `Publish-RoleSnapshot.Tests.ps1`, `Reconcile-LocalRoles.Tests.ps1`, `Initialize-RoleDb.Tests.ps1`, `Get-BigFixCredential.Tests.ps1`, `Invoke-ContentSync.Tests.ps1`, `Stage-Repository.Tests.ps1`. Seams to mock: `Invoke-SqliteCommand` (pure-logic) or real temp `.db` (upsert/migration), `Invoke-RestMethod`/`Invoke-WebRequest`, `-ConsoleUser` param. Full test->requirement map: 07-RESEARCH.md L962-978. Wave-0 fixture gaps: 07-RESEARCH.md L1002-1011.

---

### `tests/unit/role_admin.test.js` (NEW - Node assert)

**Analog:** `tests/unit/role_assigner.test.js` (exact) and `tests/unit/copier.test.js`.

Structure to copy (`role_assigner.test.js` L1-30, `update_tracker.test.js` tail):
- `"use strict"; var assert = require("assert");`
- Section 1: extracted function implementations copied **verbatim** from the `.ojo` with source line references in comments.
- `section(name)` / `expect(name, fn)` helpers, `passed`/`failures` counters.
- Footer: `console.log("Results: " + passed + " passed, " + failures + " failed")`, `process.exit(failures > 0 ? 1 : 0)`.
- Cover: `switchTab`, GroupRoleMap row validate, "Test Pattern" matcher (JS mirror of PS `Resolve-Roles`), base64-chunk chain, `PORTAL_CONFIG` shape.
- Runner: `node tests/unit/role_admin.test.js`; add to the full-suite chain alongside the existing 7 suites.

---

### `docs/automation-admin-guide.md` (NEW)

**Analog:** `docs/role-assigner-admin-guide.md` (heading skeleton, exact):
`# Title` / `## Overview` / `## Prerequisites` / `## Step 1 - Deploy ...` / `## Step 2 - ...` / `## Configuring ...` / `## Troubleshooting` / `## File Reference`. Also `docs/dispatcher-admin-guide.md` for the prefetch/repository half. Content per 07-RESEARCH.md L354-355: setup checklist, per-region phased rollout (D-26), task 787 redeploy (07-RESEARCH.md Runtime State L603), AKeyless secret/egress confirmation, Analysis-lag caveat.

---

## Shared Patterns

### CLM-safe SQLite access
**Source:** `Dashboard_4_samples/Sqlite-Helper.ps1` (`Invoke-SqliteCommand` L162-251, `ConvertTo-SqliteLiteral` L69-84)
**Apply to:** every PowerShell file this phase (both tiers)
- Dot-source once: `. "$PSScriptRoot\Sqlite-Helper.ps1"` (also brings `ConvertTo-SqliteLiteral` into scope).
- Parameterised: `-Parameters @{ key = $val }`, `@key` tokens in `-Sql`; values are string-coerced + single-quote-doubled.
- **WR-02:** at most ONE result-returning statement per call (L20-28, L220-223 throws). DDL/INSERT/UPDATE/DELETE combine freely.
- `UPDATE ...; SELECT changes() AS n` MUST be one call (`changes()` is connection-scoped; fresh `sqlite3.exe` per call) - `Initialize-RoleDb.ps1` L239-250.
- Non-ASCII read-back: `SELECT hex(Col) AS "Col__hex"` (L42-53).
- Zero `Add-Type` / `System.Data.SQLite` / `New-Object System.IO.StreamReader` (all CLM-blocked - Anti-patterns L557).

### D-12 upsert discipline
**Source:** `Dashboard_4_samples/Initialize-RoleDb.ps1` L234-257; `Existing Dashboards/fixlet_role_assigner.ojo` `buildAssignActionScript` L763-772
**Apply to:** `Reconcile-LocalRoles.ps1`, `Import-AxoniousExport.ps1` (UserRole/RefUser), any `Map` write
- `INSERT OR IGNORE` (create row, disturb nothing) then conditional `UPDATE ... WHERE ... AND Locked_by_Override = 0`.
- **Never `INSERT OR REPLACE`** on a table with state columns (it deletes+reinserts, destroying `Active`/`Locked_by_Override`/`Created_on`). `Initialize-RoleDb.ps1` L225 uses it on `Users` only (2 columns) - do not generalise.
- `INSERT OR IGNORE INTO Roles (Role)` for any snapshot role missing locally (D-15).

### PRAGMA-gated additive migration
**Source:** `Dashboard_4_samples/Initialize-RoleDb.ps1` L158-187
**Apply to:** `Initialize-RoleDb.ps1` (D-18 Map cols), `Initialize-AutomationDb.ps1` (any future column add)
```powershell
$cols = @(Invoke-SqliteCommand ... -Sql "PRAGMA table_info(<Table>)" | ForEach-Object { $_.name })
if ($cols -notcontains '<Col>') { Invoke-SqliteCommand ... -Sql "ALTER TABLE <Table> ADD COLUMN <Col> TEXT" | Out-Null }
```
Idempotent, row-preserving, logged `[MIGRATE]`/`[SKIP]`.

### ActionScript brace escaping for embedded PowerShell
**Source:** `Existing Dashboards/fixlet_dispatcher.ojo` `escapeActionScriptBraces` L630-632; `Init  Current User and UserRole DB.bes` (every `createfile` block)
**Apply to:** `RoleRef-Policy-<region>.bes`, the modified `Init...DB.bes`, dashboard SingleAction builders
- `String(s).replace(/\{/g, "{{")` and **nothing else** - only the opening brace is doubled; every closing `}` stays single (doubling `}` leaves stray trailing `}}`).
- Never touch intentional relevance substitutions: `{parameter "X"}`, `{name of current user}`, `{value of setting ...}`, `{computer id}`.
- Alternative: prefetch the `.ps1` as a file resource and skip escaping entirely (Pitfall 11 L718-724).

### Prefetch URL shape + Custom Repository path
**Source:** `Existing Dashboards/fixlet_dispatcher.ojo` `rewritePrefetchUrls()` L591-599, `extractPrefetchLines()` L606-620; `Init  Current User and UserRole DB.bes` L37-40
**Apply to:** `Publish-RoleSnapshot.ps1`, `Stage-Repository.ps1`, `RoleRef-Policy-<region>.bes`
- `prefetch <file> sha1:<hex> size:<n> http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/<subtree>/<file>` - match byte-for-byte.
- On-disk root from registry `HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server` -> `wwwRootFolder` (never hard-code `DataDirectory`).
- roleref subtree: `...\SoftwarePortal\roleref\`; content installers: `...\SoftwarePortal\<sha1-lowercase>\<file>`.

### BES-client directory parameter idioms
**Source:** `Dashboard_4_samples/Init  Current User and UserRole DB.bes` L43-47; `fixlet_role_assigner.ojo` L580-584
**Apply to:** `RoleRef-Policy-<region>.bes`, modified `Init...DB.bes`
```
parameter "SWPDir"="{(concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal")))}"
```
plus `RootDir`, `ECDir`, `TargetStore` (RoleAwareness.db), `SQLiteDir`. `action uses wow64 redirection {x64 of operating system}` before every `waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File ...`.

### OJO IE9 constraints
**Source:** every existing `.ojo`; `fixlet_console.ojo` L322, `fixlet_role_assigner.ojo` L10-11 / L59-72
**Apply to:** `fixlet_role_admin.ojo`, `fixlet_automation_monitor.ojo`, modified `fixlet_role_assigner.ojo`
- `var` only; function declarations only; no `let`/`const`/`=>`/template literals/`Array.forEach`.
- `<meta http-equiv="X-UA-Compatible" content="IE=9">`; `new ActiveXObject("Msxml2.DOMDocument.6.0")` with `setProperty("SelectionLanguage","XPath")`.
- `API.Get` / `API.Post` / `API.Put` for REST (dual-status `200 || 201`, always handle the failure branch); `GetRelevance` for Analysis reads; `EvaluateRelevance` for live session relevance.
- `htmlEscape` every external value before `innerHTML`.
- **Never save a `.ojo` from VS Code** (memory `ojo-file-safety`).

### REST API plural/singular convention
**Source:** `Existing Dashboards/fixlet_update_tracker.ojo` `copyNextItem` L1533-1613
**Apply to:** `Invoke-ContentSync.ps1`, `Publish-RoleSnapshot.ps1`, dashboard SingleAction POSTs
- List/create: `POST fixlets/custom/<site>` (**plural**) - BigFix infers Task vs Fixlet from the XML body.
- Get/update one: `GET|PUT <fixlet|task>/custom/<site>/<id>` (**singular**); `pathType = isTask ? 'task' : 'fixlet'`.
- SingleAction XML element order: Title -> Relevance -> ActionScript -> [SuccessCriteria] -> Settings -> ... -> Target -> [MIMEFieldSingleAction] (`<Target>` before `<Settings>` = 400).

### Structured run logging + audit trail (NFR-NEW)
**Source:** no direct code analog - `Initialize-RoleDb.ps1` `[TAG] message` + `Add-Content $logfile` (throughout) is the closest; 07-RESEARCH.md L354, L584, Pitfall 7
**Apply to:** every new root-server script
- Per-run JSON log (`ConvertTo-Json -Depth 6`) + a `SyncRun` row (Type = `Ingest|Publish|ContentSync|RepoStage`) + `Snapshot` row where relevant.
- `Write-EventLog -LogName Application -Source "DereseSoftwarePortal"` (IDs 8000-8099) on failure; source registered once by `Initialize-AutomationDb.ps1`.
- `-WhatIf` on every new script: emit the JSON log, make zero API calls / DB writes.
- **Never** log the AKeyless token or the operator password (contrast the Cyera analog which does - do not copy `0_Retrieve_AKeylessVal.ps1` L30).

---

## No Analog Found

| File | Role | Data flow | Reason |
|---|---|---|---|
| `scripts/Import-AxoniousExport.ps1` (streaming core only) | service / ETL | streaming CSV transform | No streaming-file parser anywhere in the repo. Use `Import-Csv \| ForEach-Object` per 07-RESEARCH.md Pattern 2 / Pitfalls 1 & 9. Upsert + batch + logging halves DO have analogs (listed above). |
| `tests/pester/*.Tests.ps1` | test | - | No PowerShell test precedent; Phases 1-6 were all OJO/Node. Pester 5 conventions from 07-RESEARCH.md Validation Architecture. |
| `config/GroupRoleMap.json`, `config/PipelineConfig.defaults.json` | config | static JSON | Closest is the `PORTAL_CONFIG` JS object literal and `category_map_output.js`; neither is a real match for a hand-edited seed file. Shape from DESIGN.md §"Database designs A". |
| `New-EventLog` / `Write-EventLog` wiring in `Initialize-AutomationDb.ps1` | config | - | No Event Log usage in the codebase today. Standard PS per 07-RESEARCH.md Pitfall 7. |

---

## Metadata

**Analog search scope:** `Dashboard_4_samples/` (all `.ps1`, `.bes`), `Existing Dashboards/` (all `.ojo`), `tests/unit/`, `docs/`, `scripts/`, `config/`, `bes/`, `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1`
**Files scanned in full or in targeted ranges:** `Initialize-RoleDb.ps1` (264L, full), `Sqlite-Helper.ps1` (253L, full), `Init  Current User and UserRole DB.bes` (707L, full), `Dereso SWD.bes` (20L, full), `0_Retrieve_AKeylessVal.ps1` (41L, full), `fixlet_role_assigner.ojo` (L1-120, 225-364, 440-600, 760-880), `fixlet_dispatcher.ojo` (L585-655), `fixlet_update_tracker.ojo` (L1146-1225, 1358-1387, 1499-1614), `fixlet_copier.ojo` (L783-842), `fixlet_console.ojo` (grep index), `role_assigner.test.js` (L1-70), `update_tracker.test.js` (tail), `copier.test.js` (head), `role-assigner-admin-guide.md` (heading index)
**Pattern extraction date:** 2026-08-29
**Project constraints carried into every assignment:** CLM-safe SQLite only (`Sqlite-Helper.ps1`, zero `Add-Type`); one result-returning SELECT per `Invoke-SqliteCommand` (WR-02); ActionScript `{`->`{{` (opening brace only) in `createfile` blocks; IE9-only OJO JS (`var`, `Msxml2.DOMDocument.6.0`, `API.Get/Post/Put`); D-12 upsert (never `INSERT OR REPLACE`, `Locked_by_Override = 0` guard); never save `.ojo` from VS Code; never log the AKeyless secret.
