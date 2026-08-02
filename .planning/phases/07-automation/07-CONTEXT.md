---
phase: 07-automation
created: 2026-08-01
status: ready-for-planning
---

# Phase 7: End-to-End Automation — Context

**Gathered:** 2026-08-01
**Status:** Ready for planning

---

<domain>
## Phase Boundary

Phase 7 transforms the Software Portal from a collection of admin-driven dashboards into a
largely automated pipeline. Every tool built in Phases 1–6 was designed with automation as
the end state; this phase wires them together.

The three core loops:

1. **Role Pipeline** — Daily Axonious export → derive role entitlements → resolve users to
   BigFix computer IDs → deploy RoleAwareness DB assignments automatically.

2. **Content Pipeline** — Scheduled scan of source BigFix sites → copy new/updated fixlets
   with category + role metadata transfer → pre-stage installer downloads in the BigFix
   Custom Repository so the Dispatcher's prefetch rewrite can be honoured offline.

3. **Automation Dashboard** — A new `.ojo` dashboard that surfaces pipeline status, provides
   manual trigger controls, runs a review/approval queue for new content, and exposes the
   group-to-role mapping configuration.

**What stays manual:** Final deployment of an offer action via the Dispatcher. Automation
gets content to "Ready" state; human admin confirms deployment to end users. (Fully
autonomous dispatch can be added in Phase 8 if desired.)

**What runs where:** All orchestration scripts run on the **BigFix root server** as Windows
Scheduled Tasks, using the same BigFix REST API patterns already proven in the dashboards.
No new infrastructure required.

</domain>

---

<decisions>
## Implementation Decisions

### D-01: Axonious Export Format
The Axonious daily export is a CSV (or Excel/CSV conversion) with at minimum these columns:
- `username` — SAM account name; must be lowercased before comparing to BigFix `names of
  logged on users as lowercase`
- `AD_Groups` — pipe-separated or comma-separated list of Active Directory group memberships
- `Mailing_Groups` — pipe-separated or comma-separated list of mail group memberships

Both group columns are checked for role entitlement. A `GroupRoleMap` config table
(see D-03) determines which groups yield which roles.

### D-02: Username Case Normalization
BigFix session relevance returns logged-on usernames via
`names of logged on users of bes computers` already lowercased when queried as lowercase.
All Axonious usernames MUST be `.ToLower()` before any comparison or storage.

### D-03: Group-to-Role Mapping Config
A `GroupRoleMap.json` file on the root server (or a SQLite table in the automation DB —
see D-05) maps group name patterns to role names. Example:

```json
{
  "IT-All":          "IT Operations",
  "IT-Dev*":         "IT Operations",
  "Finance-*":       "Finance",
  "HR-*":            "HR",
  "MAIL-Finance*":   "Finance"
}
```

Pattern support: exact match and simple wildcard (`*` suffix). Case-insensitive.
This is the single configuration point for role entitlement rules. Admins edit it via
the Automation Dashboard Config tab (D-17) — not by touching the file directly.

### D-04: User→Computer Resolution
For each user in the Axonious export, the pipeline must find which BigFix-managed computers
they have recently logged onto. Method:

1. Call BigFix REST API to evaluate session relevance:
   ```
   (id of it as string & "|" & (names of logged on users of it as lowercase) joined by ",")
   of bes computers whose (exists logged on user of it)
   ```
2. Parse the result: build a map `username → [computer_ids]`.
3. Cross-reference with Axonious usernames (lowercased) to get target computer IDs per user.

This is the same approach the Role Assigner dashboard uses, but executed server-side in
PowerShell rather than requiring a manually-uploaded CSV. The `RoleAwareness.db` `Users`
table (maintained by the logon scheduled task from Phase 5) provides a secondary
cross-reference for users who are not currently logged on.

### D-05: Automation State DB
A new SQLite database at a configurable path on the root server (e.g.,
`C:\BESData\SoftwarePortal\AutomationState.db`). Schema:

**Tables:**
- `SyncRun` — log of each pipeline run (id, type, started_at, ended_at, status, summary)
- `RoleAssignment` — record of each role→user→computer assignment deployed
  (run_id, username, computer_id, role, action_id, deployed_at)
- `ContentItem` — state machine for each fixlet in the pipeline
  (fixlet_id, fixlet_name, stage [discovered/staged/categorized/ready/live/rejected],
  source_site, category, roles, copied_at, dispatched_at)
- `CacheEntry` — state of each repository file
  (sha1, filename, original_url, staged_at, size_bytes, verified)
- `GroupRoleMap` — authoritative group→role mapping (group_pattern, role, priority, active)
- `PipelineConfig` — key-value config store (key, value, description)

### D-06: Role Pipeline — Orchestrator Script
`scripts/Invoke-RoleSync.ps1` — the master orchestrator for the role pipeline:

1. Read Axonious export from configured input path.
2. Parse `AD_Groups` + `Mailing_Groups` → apply `GroupRoleMap` → produce `{user: [roles]}` map.
3. Evaluate BigFix session relevance → produce `{user: [computer_ids]}` map.
4. Cross-join: for each (user, role, computer_id) triple not already in `RoleAssignment`
   table, create an assignment record.
5. Batch by role: one `API.Post("actions")` call per role (same approach as Role Assigner
   dashboard) targeting only new/changed assignments.
6. Log results to `SyncRun` + `RoleAssignment` tables.

Uses `Sqlite-Helper.ps1` (Invoke-SqliteCommand) — same CLM-safe pattern as Phase 3+.

### D-07: Role Pipeline — Computer-User Query
`scripts/Get-UserComputerMap.ps1` — standalone script (called by D-06):

Queries BigFix REST API:
```
POST /api/query
Body: {"type":"session","relevance":"(id of it as string, names of logged on users of it as lowercase joined by \",\") of bes computers whose (exists logged on users of it)"}
```

Falls back to reading the `Users` table in `RoleAwareness.db` on accessible clients via
the Dereso SWD Analysis results (if direct relevance query is insufficient for recently
logged-off users). LastSeen threshold is configurable (default: 90 days).

### D-08: Role Pipeline — Scheduled Task
A Windows Scheduled Task on the BES root server:
- Name: `Dereso\SoftwarePortal-RoleSync`
- Trigger: Daily, at a configurable time after the Axonious export is deposited
  (default: 06:00 — assumes export is placed overnight)
- Script: `pwsh.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "scripts/Invoke-RoleSync.ps1"`
- Runs as: Local service account with BigFix operator permissions
- On failure: write to Windows Event Log + update `SyncRun` with status = "failed"

### D-09: Content Pipeline — Scan and Copy
`scripts/Invoke-ContentSync.ps1` — orchestrates fixlet discovery and import:

1. Calls BigFix REST API to enumerate all source sites configured in `PipelineConfig`
   (same `PORTAL_CONFIG.sourceSites` names used by the Update Tracker dashboard).
2. For each source fixlet, applies version-stripping (same `/ v\d[\d.]+/g` regex as the
   Update Tracker) to compute the product key.
3. Compares against portal fixlets to identify updates and new arrivals.
4. New items go to `ContentItem.stage = 'discovered'` in the automation DB.
5. Items in the auto-approve list (configured in `PipelineConfig`) advance directly to
   `stage = 'staged'` and are copied immediately.
6. Items requiring review stay at `discovered` and appear in the Automation Dashboard's
   review queue (D-15).
7. For approved items: calls `POST /api/custom-site/<site>/fixlet` (same pattern as
   fixlet_copier.ojo), transfers `<Category>` and `Associated_Roles` MIME field.
8. On successful copy: calls `PUT` to stamp `X-Superseded-By` on the old fixlet
   (same as Update Tracker).
9. For new arrivals: applies CATEGORY_MAP lookup (same embedded map as Update Tracker),
   leaves roles blank, sets stage to `discovered` for admin review.

### D-10: Content Pipeline — Repository Caching
`scripts/Stage-Repository.ps1` — ensures installer files are present in the BigFix Custom
Repository so the Dispatcher's `rewritePrefetchUrls()` can be honoured:

1. Queries all portal fixlets via BigFix REST API.
2. For each fixlet, parses all action scripts to extract `prefetch` lines:
   `prefetch <file> sha1:<sha1> size:<n> <url>`
3. For each (sha1, filename, url) triple:
   a. Check if `C:\...\Uploads\CustomRepository\SoftwarePortal\{sha1}\{filename}` exists.
   b. If missing: download from `<url>`, verify SHA1, move to target path.
   c. Record result in `CacheEntry` table.
4. Reports: files already cached, newly downloaded, download failures.

**Target path on BES root server:**
`{BES_ROOT}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\{sha1}\{filename}`

where `{BES_ROOT}` is read from registry
`HKLM:\SOFTWARE\BigFix\EnterpriseServer\GlobalSettings` → `DataDirectory`.

**Why this matters:** The Dispatcher's `rewritePrefetchUrls()` already rewrites `prefetch`
lines to point at `http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/{sha1}/{file}`.
If those files aren't staged, client downloads will 404. This script closes that gap.

### D-11: Content Pipeline — Scheduled Tasks
Two scheduled tasks:

| Task | Name | Trigger | Script |
|------|------|---------|--------|
| Fixlet Sync | `Dereso\SoftwarePortal-ContentSync` | Weekly (configurable) | `Invoke-ContentSync.ps1` |
| Repo Cache | `Dereso\SoftwarePortal-RepoStage` | After ContentSync + manual trigger | `Stage-Repository.ps1` |

ContentSync triggers RepoStage on completion via `-OnSuccess` chaining or a
"trigger on task completion" dependency in Task Scheduler.

### D-12: End-User Experience — Offer Catalogue
End users receive role-aware offers via BigFix Self Service (or equivalent client UI).
The role-awareness relevance generated by the Modifier dashboard ensures:
- Offers are only relevant to endpoints where the logged-on user has the appropriate role
  in `RoleAwareness.db`.
- Users see only the software they are entitled to.

The automation pipeline ensures these offers are kept current:
- New software → discovered → (reviewed) → staged → Modifier adds roles → Dispatcher
  deploys offer.
- Updated software → old offer stamped superseded → new offer deployed with same roles.

**Admin touchpoint:** The Dispatcher dashboard remains the human-confirmation step before
an offer goes live. The automation pipeline delivers content to "Ready" state; an admin
clicks "Deploy" in the Dispatcher. (Future Phase 8 option: fully automatic dispatch for
a configurable subset of categories/roles.)

### D-13: Automation Dashboard — Overview
A new BigFix dashboard: `Existing Dashboards/fixlet_automation_monitor.ojo`

Tabs:
1. **Status** — last run times, success/failure for each pipeline, counts of items at
   each stage.
2. **Role Pipeline** — current Axonious sync state, users/roles pending, last run summary,
   "Run Now" trigger button.
3. **Content Queue** — items at each stage (discovered/staged/categorized/ready/live),
   with the ability to approve, reject, or force-push individual items.
4. **Repository Cache** — list of cached files, missing files (download failures), total
   cache size, "Refresh Cache" trigger button.
5. **Config** — GroupRoleMap editor (add/edit/delete rows), PipelineConfig key-value editor,
   source sites list (synced with Update Tracker's `PORTAL_CONFIG.sourceSites`).

### D-14: Automation Dashboard — Status Tab
Reads from `AutomationState.db` via `GetRelevance` querying the Analysis that
surfaces automation state. Falls back to direct REST API call to query DB if Analysis
not available.

Displays:
- Last RoleSync: timestamp, status, # users processed, # actions deployed
- Last ContentSync: timestamp, status, # fixlets discovered/copied/failed
- Last RepoStage: timestamp, status, # files cached/missing

Each row has a "View Log" expand to show the `SyncRun` summary text.

### D-15: Automation Dashboard — Content Queue (Review/Approval)
The key human interface for content governance:

- **Discovered** tab: new products and updates not yet approved for import.
  Admin can: Approve (→ staged), Reject (never import), or Approve All.
- **Staged** tab: imported but not yet role-categorized. Admin uses Modifier dashboard
  to add roles, then marks "Ready" here.
- **Ready** tab: categorized, roles assigned, waiting for Dispatcher. Admin clicks
  "Open in Dispatcher" which deep-links to the Dispatcher with the fixlet pre-selected.
- **Live** tab: dispatched; shows offer action ID + expiry date.
- **Rejected** tab: items the admin excluded, with the ability to un-reject.

### D-16: Automation Dashboard — Repository Cache Tab
Shows:
- Table: Filename | SHA1 | Size | Staged Date | Source URL | Status (OK / Missing / Failed)
- Summary: N files cached, N missing, N failed downloads, total size
- "Stage Missing" button: triggers `Stage-Repository.ps1` for uncached files only
- "Verify All" button: re-checks SHA1 of all staged files

### D-17: Automation Dashboard — Config Tab
GroupRoleMap editor:
- Table of (Group Pattern, Role, Priority, Active) rows
- Add/Edit/Delete rows
- Save writes to `GroupRoleMap` table in `AutomationState.db`
- "Test Pattern" field: enter a group string, see which role(s) it matches

PipelineConfig editor:
- Key-value grid: AxoniousExportPath, SourceSites, BESRootPath, AutoApproveCategories,
  UserLastSeenThresholdDays, ContentSyncSchedule, RoleSyncSchedule

### D-18: Script Output / Error Reporting
All automation scripts write structured JSON to a `{script}-{datestamp}.json` log file
alongside their output. Format:
```json
{
  "run_id": "...",
  "started_at": "...",
  "ended_at": "...",
  "status": "success|partial|failed",
  "counts": { "processed": N, "succeeded": N, "failed": N },
  "errors": [ { "item": "...", "message": "..." } ]
}
```

On failure, write to Windows Event Log (Application, Source: `DereseSoftwarePortal`,
Event ID range: 8000–8099).

### D-19: Existing Tool Reuse Map

| Existing Tool | Role in Phase 7 Automation |
|---|---|
| `fixlet_copier.ojo` | Copy pattern reused verbatim by `Invoke-ContentSync.ps1` (same API calls) |
| `fixlet_modifier.ojo` | Manual categorization step for items in "Staged" queue; role relevance build pattern reused in content pipeline to auto-apply roles where known |
| `fixlet_dispatcher.ojo` | Remains the human deploy step; prefetch rewrite already in place |
| `fixlet_role_assigner.ojo` | Action XML build pattern (base64 chunk, parallel arrays) reused by `Invoke-RoleSync.ps1` |
| `fixlet_update_tracker.ojo` | Scan + version-strip + category-map logic reused by `Invoke-ContentSync.ps1`; becomes the manual fallback / preview tool |
| `Sqlite-Helper.ps1` | Used by all new PowerShell scripts for `AutomationState.db` access |
| `Initialize-RoleDb.ps1` | Schema reference; DB init step prerequisite (unchanged) |
| `Dereso SWD.bes` | Analysis surfacing `mapped_users in r.db` — read by Automation Dashboard for role pipeline status |
| `RoleAwareness_Report.beswrpt` | Complements automation; not modified in Phase 7 |

### D-20: Phased Automation Rollout
To ensure administrator and end-user acceptance:

**Week 1 — Dry-run mode:** All pipeline scripts run with `-WhatIf` flag (log what they
would do, make no API calls). Admins review logs before enabling live mode.

**Week 2 — Role pipeline live, content manual:** `Invoke-RoleSync.ps1` runs live.
Content sync stays manual (admin uses Update Tracker dashboard).

**Week 3 — Content pipeline live (auto-approve OFF):** `Invoke-ContentSync.ps1` runs and
populates the review queue. Admin approves each item before it copies.

**Week 4 — Auto-approve enabled for selected categories:** Admin configures
`AutoApproveCategories` in PipelineConfig; low-risk categories (e.g., "Productivity")
copy without review. High-risk categories (e.g., "Security", "System") remain in queue.

</decisions>

---

<canonical_refs>
## Canonical References

**Downstream planning agents MUST read these before writing any plan.**

### Existing Dashboards (patterns to reuse)
- `Existing Dashboards/fixlet_copier.ojo` — REST API copy pattern
- `Existing Dashboards/fixlet_modifier.ojo` — role relevance build, MIME field write, PORTAL_CONFIG
- `Existing Dashboards/fixlet_dispatcher.ojo` — `rewritePrefetchUrls()` (lines 388–398), `buildDeployXml()`, SingleAction XML structure
- `Existing Dashboards/fixlet_role_assigner.ojo` — base64 chunk encoding, `buildAssignActionXml`, per-role action dispatch
- `Existing Dashboards/fixlet_update_tracker.ojo` — version strip regex, CATEGORY_MAP, scan loop, supersede stamp

### Server-side Scripts (patterns to reuse)
- `Dashboard_4_samples/Sqlite-Helper.ps1` — `Invoke-SqliteCommand` — CLM-safe SQLite access
- `Dashboard_4_samples/Initialize-RoleDb.ps1` — DB schema, upsert pattern, error codes 5100–5400

### Configuration Sources
- `Dashboard_4_samples/software_categorized.csv` — category lookup source for CATEGORY_MAP
- `Dashboard_4_samples/role_targeting.csv` — role assignment CSV format (user, Computer_ID, role)

### BigFix Analysis
- `Dashboard_4_samples/Dereso SWD.bes` — Analysis properties: `mapped_users in r.db`, `users in r.db`, `recent users`

### Phase Context Docs
- `.planning/phases/03-dispatcher-rapid-deployment/03-CONTEXT.md` — prefetch rewrite decision chain
- `.planning/phases/04-role-assigner/04-CONTEXT.md` — base64 chunk encoding, action XML format
- `.planning/phases/05-robustness/05-CONTEXT.md` — logon scheduled task, `UpdateUserOnLogon`
- `.planning/phases/06-update-tracker/06-CONTEXT.md` — scan loop, version strip, category transfer, supersede stamp

</canonical_refs>

---

<code_context>
## Existing Code Insights

### Prefetch URL Pattern (Dispatcher)
`rewritePrefetchUrls()` in `fixlet_dispatcher.ojo` lines 388–398:
- Rewrites `prefetch <file> sha1:<sha1> size:<n> <url>` to `http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/<sha1>/<filename>`
- Original line preserved as ActionScript comment
- Applied at deploy time; assumes files are already staged on root server
- `Stage-Repository.ps1` (D-10) is the companion that does the actual staging

### BigFix REST API — Relevance Evaluation
Used by `Get-UserComputerMap.ps1` (D-07):
- Endpoint: `POST https://<server>:52311/api/query`
- Body: `{"type":"session","relevance":"<expr>"}`
- Auth: Basic (same operator credentials used by dashboards)
- Returns: array of result strings

### Existing Action XML Structure (Role Assigner reference)
`buildAssignActionXml()` in `fixlet_role_assigner.ojo` encodes user/computer pairs as:
- JSON `{computers:[id1,...], users:["u1",...]}` (parallel arrays)
- Base64-encoded, chunked into ~3000-char segments
- Stored as `parameter "chunk0"`, `chunk1`, etc. in ActionScript
- `Invoke-RoleSync.ps1` replicates this encoding in PowerShell

### Version Strip Regex
From `fixlet_update_tracker.ojo` (same as Phase 7 content pipeline):
```js
/ v\d[\d.]+/g
```
Applied to fixlet name to extract product key for version-independent matching.

### IE9 Compatibility (dashboard only)
New `fixlet_automation_monitor.ojo` must follow same IE9 constraints as all existing OJOs:
- `language="javascript"`, `var` only, no arrow functions, no template literals
- `Msxml2.DOMDocument.6.0` for XML, `selectSingleNode()` / `selectNodes()`
- `API.Get()` / `API.Post()` / `API.Put()` for REST calls

### SQLite Helper Pattern
All new PowerShell scripts use `Invoke-SqliteCommand` from `Sqlite-Helper.ps1`:
```powershell
. "$PSScriptRoot\..\Dashboard_4_samples\Sqlite-Helper.ps1"
Invoke-SqliteCommand -Database $DbPath -Query "INSERT INTO ..." -Parameters @{...}
```
CLM-safe: no `Add-Type`, no DLL loading, uses sqlite3.exe from the prefetched tool package.

</code_context>

---

<specifics>
## Specific Implementation Notes

### Axonious Group Column Parsing
Both `AD_Groups` and `Mailing_Groups` may use different delimiters (pipe `|`, semicolon `;`,
or comma `,`). The parser should normalize: split on `[|;,]`, trim whitespace, deduplicate.

### User Last-Seen Fallback
If a user appears in Axonious but has no current BigFix session relevance hit (i.e., is not
currently logged on), check the `Users.LastSeen` in `RoleAwareness.db` via the Analysis.
If `LastSeen` is within the configured threshold (default 90 days), use the computer(s)
associated with that user in the `Map` table. This handles users who log on infrequently.

### Repository Path Detection
Do not hardcode the BES root path. Read from:
`(Get-ItemProperty "HKLM:\SOFTWARE\BigFix\EnterpriseServer\GlobalSettings").DataDirectory`
Then construct: `{DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\`

### Content Auto-Approve Logic
`AutoApproveCategories` in PipelineConfig is a semicolon-separated list of category names
(e.g., `"Productivity;Browsers;PDF Tools"`). Any fixlet whose CATEGORY_MAP lookup or
existing portal category matches one of these is auto-approved into the copy pipeline
without admin review. All others go to the discovery queue.

### SHA1 Verification
`Stage-Repository.ps1` computes SHA1 with `Get-FileHash -Algorithm SHA1` and compares
to the `sha1:` token from the prefetch line before moving to the target path. Mismatch
= download failure; retry once, then log as failed.

### Admin Notification
On any pipeline run that ends with `status = "failed"` or `partial` (i.e., any errors),
write a Windows Event Log entry and optionally call a configurable webhook URL (Slack,
Teams, or generic HTTP POST) with a JSON payload summarizing the failure. Webhook config
in `PipelineConfig` key `AlertWebhook` (empty = disabled).

</specifics>

---

<deferred>
## Deferred / Future Phases

- **Phase 8: Autonomous Dispatch** — Fully automatic dispatch of "Ready" fixlets as offer
  actions, triggered by the content pipeline reaching `stage = 'ready'`. Requires a more
  mature governance model; deferred until Phase 7 automation is stable.

- **Revoke Automation** — Automated role revocation when a user leaves a group in Axonious.
  Currently the pipeline only adds/updates; removal requires admin review (via Role Assigner
  revoke UI). Deferred because false-positive removals (e.g., temporary group change) would
  remove entitlements unexpectedly.

- **Multi-tenant / Multi-BigFix** — Supporting more than one BigFix instance from the same
  Axonious export. Out of scope for Phase 7.

- **AD Direct Integration** — Reading AD group membership directly via LDAP rather than via
  the Axonious intermediary. Deferred; Axonious export is the agreed data source.

- **Fixlet Rollback** — Reverting to a previous version and removing the `X-Superseded-By`
  stamp. Noted in Phase 6 context; still out of scope.

- **Self-Service Catalog UI** — A custom end-user web UI (separate from BigFix Self Service)
  showing available software offers. Future phase if BigFix Self Service proves insufficient.

</deferred>

---

## Proposed Plan Structure

| Plan | Wave | Title | Key Deliverables |
|------|------|-------|-----------------|
| 07-00 | 0 | Foundation — Automation State DB + Config | `AutomationState.db` schema script, `GroupRoleMap.json` template, `PipelineConfig` defaults, test fixtures |
| 07-01 | 1 | Role Pipeline — Axonious Ingestion + Assignment | `Parse-AxoniousExport.ps1`, `Get-UserComputerMap.ps1`, `Invoke-RoleSync.ps1`, Windows Scheduled Task XML |
| 07-02 | 2 | Content Pipeline — Sync + Repository Staging | `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`, Scheduled Task XML, SHA1 verification |
| 07-03 | 3 | Automation Dashboard | `fixlet_automation_monitor.ojo` — Status, Role Pipeline, Content Queue, Cache, Config tabs |
| 07-04 | 4 | Integration + Phased Rollout | End-to-end test fixtures, WhatIf dry-run mode, rollout checklist, admin run-book, regression gate (all 6 unit suites) |

---

*Phase: 7-automation*
*Context gathered: 2026-08-01*
