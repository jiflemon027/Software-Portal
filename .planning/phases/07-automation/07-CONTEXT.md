---
phase: 07-automation
created: 2026-08-01
updated: 2026-08-29
status: ready-for-planning
supersedes: "2026-08-01 role-pipeline decisions (old D-01/D-03..D-08, D-13..D-17 role parts)"
---

# Phase 7: End-to-End Automation — Context

**Gathered:** 2026-08-01
**Rewritten:** 2026-08-29 — role pipeline redesigned per `.planning/quick/260828-fjc-role-reference-db/DESIGN.md`
**Status:** Ready for planning

> **This is a rewrite-in-place.** The 2026-08-01 version modelled the role pipeline as
> *daily Axonious export → resolve users to BigFix ComputerIDs → per-ComputerID SingleActions*.
> That is **rejected**: it hard-links a user's role to specific machines. The role pipeline
> below follows the *user* to whatever endpoint they log into, with no ComputerID anywhere.
> The **content pipeline** (old D-09/D-10/D-11/D-16, §Content Pipeline below) is unchanged.

---

<domain>
## Phase Boundary

Phase 7 wires the Phases 1–6 tools into automated pipelines that run unattended on the
BigFix **root server** as Windows Scheduled Tasks, with human review only at governance
gates. Three decoupled loops plus monitoring:

1. **Role pipeline** — daily Axonious export → a reference database on the root server →
   per-region snapshot files in the BigFix Custom Repository → per-region policy action →
   endpoint reconcile that upserts the *logged-on user's* roles into local `RoleAwareness.db`.
   **No user→ComputerID matrix. No per-role/per-computer actions.** Up to a 24 h propagation
   delay is acceptable.

2. **Content pipeline** — scheduled scan of source sites → copy new/updated fixlets with
   category + role MIME transfer → pre-stage installer downloads in the Custom Repository so
   the Dispatcher's prefetch rewrite is honoured. **Unchanged from the 2026-08-01 design.**

3. **Reconcile loop (endpoint)** — a new `Reconcile-LocalRoles.ps1`, run both by the
   per-region policy action and by the existing `RoleDB_Maintenance` logon task.

**Monitoring:** `fixlet_automation_monitor.ojo` (content pipeline only) + a new
`fixlet_role_admin.ojo` for role config and reference-DB visibility.

**What stays manual:** final deployment of an offer action via the Dispatcher; the
`fixlet_role_assigner.ojo` CSV upload path (demoted to a break-glass manual-override tool).

**What runs where:** all orchestration on the BES root server; endpoint work via the
existing `RoleAwareness.db` / `RoleDB_Maintenance` mechanism. No new infrastructure.

</domain>

---

<decisions>
## Implementation Decisions

### Architecture & Data Model

- **D-01: One combined `AutomationState.db`.** Both pipelines share a single SQLite DB on
  the root server (not a separate `RoleReference.db`). One `Initialize-AutomationDb.ps1`
  init script; CLM-safe (`Sqlite-Helper.ps1`, zero `Add-Type`); migration-safe
  (`CREATE TABLE IF NOT EXISTS`, `PRAGMA table_info`-gated `ALTER TABLE`), same conventions
  as `Initialize-RoleDb.ps1` (`INTEGER PRIMARY KEY AUTOINCREMENT`,
  `datetime('now','localtime')`, partial indexes).

  **Role tables** (schema DDL: DESIGN.md §"Database designs A"): `Role`, `Region`,
  `GroupRoleMap`, `RefUser`, `UserRole`, `RolePublication`, `Snapshot`.
  **Content tables** (old D-05): `ContentItem`, `ContentCache` (was `CacheEntry`).
  **Shared:** one `SyncRun` table with a `Type` column spanning `Ingest` | `Publish` |
  `ContentSync` | `RepoStage`; one `PipelineConfig` key/value table (DESIGN's `Config` seed
  keys merged into it).
  **Dropped:** `RoleAssignment` — the age-out model keeps no per-user/per-computer
  assignment records on the root server.

- **D-02: No ComputerID in the role pipeline.** No user→computer resolution, no
  `Get-UserComputerMap.ps1`, no `<Target>` ComputerID lists, no `-CompID {computer id}`
  matching. Endpoints self-select by their own `GPC_Sub_Name` client setting (see D-11).

- **D-03: `RoleAwareness.db` stays the endpoint source of truth** that every downstream
  consumer reads (`fixlet_modifier.ojo`, `fixlet_console.ojo`, SSA `_dashboard.html` §1).
  Preserved unchanged: D-12 upsert discipline (`INSERT OR IGNORE` + conditional `UPDATE`,
  **never** `INSERT OR REPLACE`), the `Locked_by_Override = 0` guard, `Valid_to` renewal
  semantics, `UNIQUE(UserID, Role)`.

- **D-04: Username match key — lowercased `sAMAccountName` ↔ `name of current user`.**
  Ingest normalises to lowercased `sAMAccountName`; the endpoint compares against BigFix
  client relevance `name of current user` (lowercased). The operator confirms these align —
  **no `explorer.exe` / `GetOwner()` step.** This closes the previous #1 risk. Residual
  mismatch surface: rows where `sAMAccountName` is blank and the coalesce falls back to
  UPN-localpart / `User Name` — keep `RefUser.Username_Src` so those are reportable; live
  spot-check in 07-05.

### Ingest Loop — `Import-AxoniousExport.ps1` (root server, daily)

- **D-05: Streaming CSV ingest.** The real export is ~383–401 MB (`SampleAxonious/
  axonius-users_anond.csv`, anonymised; `axonious.db` = same as SQLite). Stream it; build
  the DB incrementally — never load whole. 47 columns, BOM-prefixed, RFC-4180 quoted.
  Stale-file guard on `MaxExportAgeDays` (default 2) — **warn, do not abort.**

- **D-06: Username coalesce.** `sAMAccountName` → local-part of UPN → `Aggregated: User Name`,
  then `.ToLower()`. Priority order in `PipelineConfig.UsernameSourcePriority` (`sam,upn,username`).
  Store `RefUser.Username_Src` (`sam` | `upn` | `username`) for match-failure diagnosis.

- **D-07: Multi-valued columns are loosely aligned — parse defensively, do not index-zip.**
  One cell holds a newline-delimited list; sub-lists across `Assigned Groups: *` columns
  have blank slots. Group values are LDAP DNs (`CN=BNX-M365-E3,OU=...,DC=office,DC=bzn`) or
  display names (`All Tenant Members`).

- **D-08: Entitlement resolution via `GroupRoleMap`.** Rule table (operator-authored):
  `Pattern` (exact NOCASE or `*`-suffix wildcard), `Match_On` (`cn` | `display` | `dn`),
  `Role`, `Priority` (advisory; all matches apply), `Active`. For each (user, role,
  source-group) write a `UserRole` row recording `Source_Type` (`AD Security Group` |
  `Mailing List` | `Azure AD Group` | …), `Source_Value` (the CN / display name),
  `Source_System` (adapter: `active_directory_adapter` | `azure_ad_adapter` | …), and
  `Matched_Rule` (the `GRMID` that fired). `Source_Type` derived from `Assigned Groups:
  Group Type` + presence of `Assigned Groups: Email`.

- **D-09: Age-out marking, not deletion.** Any `UserRole` row not seen in the current run
  gets `Active = 0` (row kept for audit). The snapshot emits only `Active = 1`. There is
  **no explicit endpoint deactivation** — an ex-member simply stops being renewed and their
  endpoint `Map` row lapses at `Valid_to`. This *is* the revoke mechanism (see D-16).

- **D-10: Region is NOT resolved at ingest.** The reference data is global; the endpoint
  self-filters by its own `GPC_Sub_Name`. `RefUser.RegionID` is a reporting-only slot the
  (later) operator region form populates; v1 seeds `RolePublication` by hand.

### Publish Loop — `Publish-RoleSnapshot.ps1` (root server, daily, after ingest)

- **D-11: Per-region snapshot files — the only distribution mechanism.** No per-role base64
  action payloads (scale: 40k endpoints global, ~10k in the target BU, ~10k users, most in
  an effectively-everyone "General Access" role). Per published region:
  `roleref-<region>-<date>.json` + `roleref-<region>-latest.json` pointer + `.sha1`
  manifest, written to
  `{DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\roleref\` — the same
  path the Dispatcher's `rewritePrefetchUrls()` already targets. Snapshot body:
  `{ run_id, region, built_on, validity_months, roles: [ { role, users: [...] } ] }` where
  `users` = DISTINCT `UserRole.UserID` WHERE `Active = 1` AND `(role, region)` is `Active`
  in `RolePublication`. `region` must equal exactly one `Region.GPC_Sub_Name`.

- **D-12: One per-region policy action, operator publishes regions one at a time.**
  `<Target>` = broad group / all clients with `RoleAwareness.db`. `<Relevance>` = the
  `RoleAwareness.db` existence guard **AND** a single-region gate:
  `exists setting "GPC_Sub_Name" whose (value of it as string as lowercase =
  "<region-lowercased>") of client`. ActionScript: `prefetch` the current
  `roleref-<region>-latest.json` (SHA1 from the manifest) to `EC\SoftwarePortal\roleref\`,
  then run `Reconcile-LocalRoles.ps1`. Optional freshness gate (stamped "last snapshot
  date" client setting / file mtime vs now, 24 h tolerance) so it reapplies ~daily even
  where nobody logs off — **optional in v1, planner's call whether to include.**

- **D-13: `Snapshot` + `SyncRun` logging** for every ingest and publish run (D-18 JSON log
  + Windows Event Log on failure).

### Reconcile Loop — `Reconcile-LocalRoles.ps1` (endpoint, NEW)

- **D-14: Console user only in v1.** Detect the current console user via client relevance
  `name of current user` (lowercased). **No `names of logged on users` fan-out** — a shared
  host gets roles for whoever is at the console when the action / logon task runs.
  Per-session reconcile is deferred.

- **D-15: Re-check region, then D-12 upsert.** Read
  `EC\SoftwarePortal\roleref\roleref-<region>-latest.json`; abort if `snapshot.region` ≠
  `value of setting "GPC_Sub_Name"`. If the console user is in the snapshot: for each of
  their roles, `INSERT OR IGNORE` + `UPDATE ... Valid_to = now + N months WHERE UserID=@u
  AND Role=@r AND Locked_by_Override = 0`. Also write the new `Map` columns
  `Source_Type` / `Source_Value` (`|`-joined if >1 group) / `Region` (endpoint's own
  `GPC_Sub_Name`) / `Assigned_By = 'AxoniousSync'`, and `INSERT OR IGNORE INTO Roles` for
  any snapshot role missing locally (new roles propagate without an init redeploy).

- **D-16: Revoke — none.** No deactivation logic, no `EnableRevoke` flag in v1. Rows age
  out via `Valid_to` (D-09).

- **D-17: Old `Assign-RoleMapping.ps1` is kept** for the dashboard's manual-override /
  break-glass path only. `Reconcile-LocalRoles.ps1` is a separate new script.

### Endpoint `Map` Migration + Logon-Rework Coordination

- **D-18: The uncommitted logon-rework is folded into Phase 7 Wave 0 (07-00).** The
  in-progress `Initialize-RoleDb.ps1` v3 + `Init  Current User and UserRole DB.bes` changes
  on this branch (see memory `role-awareness-logon-rework-status`) are finalised and
  committed **under Phase 7** — not as a separate pre-phase commit. 07-00 also adds the
  additive `Map` migration (`PRAGMA table_info(Map)`-gated `ALTER TABLE`, same mechanism as
  the existing `Updated_on` / `Valid_to` migration): `Source_Type TEXT`, `Source_Value
  TEXT`, `Region TEXT`, `Assigned_By TEXT`. No change to `UNIQUE(UserID, Role)`, `Active`,
  `Locked_by_Override`, `Valid_to`, or the D-12 upsert.

- **D-19: `RoleDB_Maintenance` logon task is extended, not replaced** — it also runs
  `Reconcile-LocalRoles.ps1` so a fresh login reconciles immediately without waiting for the
  next policy pass.

### Credential — AKeyless Universal Identity

- **D-20: Reuse Cyera's existing universal identity.** No new identity, no plaintext, no
  DPAPI file. `Get-BigFixCredential.ps1` wraps the pattern from
  `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1`: `.vault-token` file → `POST api.akeyless.io/
  auth` (`universal_identity`) → `.token` → `POST .../get-secret-value` → `PSCredential`.
  `PipelineConfig.AKeylessTokenFile` = `…\BES Client\EC\Cyera\.vault-token` (Cyera's).
  `PipelineConfig.AKeylessSecretPath` = `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator`
  (use as-is; operator corrects if wrong). Every root-server script calls it at runtime.
  **This removes the old D-05 `BESOperatorPasswordEncrypted` / DPAPI decision.**

### Region Model

- **D-21: Fixed 13-value `Region` seed list** (operator-supplied 2026-08-29, no fleet
  sweep): `UAP, MOT, APAC, APAC-MOT, APAC-M&A, AAG-DE, AAG-FR, AAG-UK, AAG-ES, AAG-BLX,
  AAG-PL, AAG-PT, GPC`. `Region.GPC_Sub_Name` must equal the endpoint client-setting value.
  Verify against live client settings in 07-05 (needs the production fleet — the
  MCP-connected server is a 9-computer lab).

### Dashboards

- **D-22: New `fixlet_role_admin.ojo`.** Tabs: **GroupRoleMap** (rules editor + "Test
  Pattern" field, from old D-17), **RolePublication** (which `(role, region)` pairs are
  live — drives the publish scope), **Region** (publish picker over the fixed 13-value
  seed; operator publishes one region at a time), **Reference DB** (read-only: last ingest
  time, per-role user counts, per-region breakdown). IE9 constraints + `API.Get/Post/Put`
  + tab-switch pattern as every existing OJO.

- **D-23: `fixlet_role_assigner.ojo` stays the break-glass tool.** CSV upload / preview /
  deploy path kept working but demoted (no longer primary). Analysis view gains **Source**
  and **Region** columns (from the migrated `Map`, via a new/expanded `Dereso SWD.bes`
  property).

- **D-24: `fixlet_automation_monitor.ojo` is content-pipeline only.** Tabs: Status,
  Content Queue (review/approval — old D-15), Repository Cache (old D-16), Config
  (`PipelineConfig` + source-sites list — old D-17 minus the GroupRoleMap editor, which
  moves to `fixlet_role_admin.ojo`). No Role tab here.

### Plan Structure — 6 plans / 6 waves

- **D-25:** The 2026-08-01 5-plan shape is re-cut. Existing `07-02/07-03/07-04` renumber.
  None are executed, so renumbering is clean.

  | Plan | Wave | Title | Key deliverables |
  |---|---|---|---|
  | 07-00 | 0 | Foundation | Combined `AutomationState.db` schema (role + content) + `Initialize-AutomationDb.ps1`; `Get-BigFixCredential.ps1`; `Region` seed (13); `GroupRoleMap` table; endpoint `Map` migration folded into `Initialize-RoleDb.ps1`; **finalise + commit the logon-rework** (D-18); test fixtures from `SampleAxonious` |
  | 07-01 | 1 | Ingest | `Import-AxoniousExport.ps1` (streaming CSV → DB, DN/username coalesce, `GroupRoleMap` resolve, `Source_Type` derivation, age-out marking); `SyncRun` logging; unit tests |
  | 07-02 | 2 | Publish + distribute + reconcile | `Publish-RoleSnapshot.ps1` (per-region JSON + `.sha1` manifest → Custom Repository); per-region policy fixlet `.bes` (single-region `GPC_Sub_Name` relevance + prefetch); `Reconcile-LocalRoles.ps1` (endpoint, console-user-only, D-12 upsert, wired into `RoleDB_Maintenance`); `Snapshot` logging; scheduled-task XML; unit tests |
  | 07-03 | 3 | Content pipeline | `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`, scheduled tasks — **unchanged from old 07-02** (old D-09/D-10/D-11/D-16) |
  | 07-04 | 4 | Dashboards | new `fixlet_role_admin.ojo`; `fixlet_role_assigner.ojo` Analysis + Source/Region; `fixlet_automation_monitor.ojo` content-only; `Dereso SWD.bes` Source/Region props |
  | 07-05 | 5 | Integration + rollout | `-WhatIf` dry-run for the new scripts; SAM ↔ `name of current user` live spot-check; live `GPC_Sub_Name` value verification; per-region phased enablement; redeploy task 787 to the fleet; admin run-book; full regression gate (all unit suites) |

  Waves 1 and 3 can run in parallel after Wave 0 (no file overlap). Wave 2 needs Wave 1.
  Wave 4 needs Waves 2 and 3. Wave 5 has a human-verify checkpoint.

### Rollout (unchanged intent — old D-20, per region now)

- **D-26: Phased, per region.** Week 1 all new scripts `-WhatIf`; then role pipeline live
  for one pilot region; widen region-by-region; content pipeline live with auto-approve OFF;
  auto-approve enabled for low-risk categories last.

### Claude's Discretion

- Combined-DB internal naming where DESIGN.md and old D-05 disagree (`Config` vs
  `PipelineConfig`, `CacheEntry` vs `ContentCache`, unified `SyncRun` column set) — resolve
  to the least-churn option and note it in the plan.
- Whether 07-02's policy action carries the optional freshness gate (D-12) in v1.
- Exact wave-level task subdivision inside 07-01 (the streaming-ingest plan is heavy).
- `Dereso SWD.bes` property names for the new Source/Region Analysis columns.

</decisions>

---

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The authoritative role-side design
- `.planning/quick/260828-fjc-role-reference-db/DESIGN.md` — **MUST read first.** Full
  current-functionality baseline, all schema DDL (§"Database designs"), per-region snapshot
  JSON shape, `Config` seed keys, AKeyless design, resolved-decisions table, Axonius export
  findings, the "Phase 7 rewrite — plan map" table, and the environment / task-787 notes.

### Existing Dashboards (patterns to reuse)
- `Existing Dashboards/fixlet_role_assigner.ojo` — CSV parse / `validateRows` / base64 chunk
  / `buildAssignActionXml` / `buildAssignActionScript` / Analysis read view; the break-glass
  path baseline and the file `fixlet_role_admin.ojo` is split out from
- `Existing Dashboards/fixlet_dispatcher.ojo` — `rewritePrefetchUrls()` (lines ~388–398):
  the `http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/...` target the
  per-region snapshot prefetch must match
- `Existing Dashboards/fixlet_modifier.ojo` — role relevance build, MIME field write,
  `PORTAL_CONFIG`, IE9 tab-switch pattern
- `Existing Dashboards/fixlet_update_tracker.ojo` — version-strip regex `/ v\d[\d.]+/g`,
  `CATEGORY_MAP`, scan loop, supersede stamp (content pipeline — unchanged)
- `Existing Dashboards/fixlet_copier.ojo` — REST API copy pattern (content pipeline)

### Server-side + endpoint scripts (patterns to reuse / extend)
- `Dashboard_4_samples/Initialize-RoleDb.ps1` — schema conventions, two-step upsert, error
  codes, `PRAGMA table_info` migration; **the endpoint `Map` migration (D-18) is added here**
- `Dashboard_4_samples/Sqlite-Helper.ps1` — `Invoke-SqliteCommand`, CLM-safe; WR-02: ONE
  result-returning SELECT per call
- `Dashboard_4_samples/Init  Current User and UserRole DB.bes` — `RoleDB_Maintenance` logon
  task + endpoint DB init; `Reconcile-LocalRoles.ps1` wires in here (D-19)
- `Dashboard_4_samples/Dereso SWD.bes` — Analysis properties; gains Source/Region (D-23)
- `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1` — AKeyless universal-identity pattern;
  `…\BES Client\EC\Cyera\.vault-token` is the identity reused (D-20)

### Test-fixture source
- `SampleAxonious/axonius-users_anond.csv` (~401 MB, anonymised, 47 cols, BOM, RFC-4180) +
  `SampleAxonious/axonius.db` — the full export; carve small fixtures from it for 07-00/07-01

### Prior phase context
- `.planning/phases/04-role-assigner/04-CONTEXT.md` — base64 chunk / action XML (break-glass)
- `.planning/phases/05-robustness/05-CONTEXT.md` — logon scheduled task, `Valid_to` renewal
- `.planning/phases/06-update-tracker/06-CONTEXT.md` — scan loop, version strip, category
  transfer, supersede stamp (content pipeline unchanged)
- `.planning/phases/03-dispatcher-rapid-deployment/03-CONTEXT.md` — prefetch rewrite chain

### Memory (point-in-time; verify against code)
- `role-reference-db-redesign` — the redesign summary this rewrite implements
- `role-awareness-logon-rework-status` — the uncommitted logon-rework folded into 07-00
- `bigfix-role-relevance-schema` — `RoleAwareness.db` schema + role relevance pattern
- `bigfix-actionscript-curly-brace-escaping` — `{` → `{{` in `createfile` blocks
- `sqlite-helper-pattern` — `Invoke-SqliteCommand` via `sqlite3.exe`
- `bigfix-prefetch-url-rewrite` — Dispatcher `rewritePrefetchUrls()` URL shape
- `ojo-file-safety` — never save `.ojo` files from within VS Code

### Local BigFix skills
- `G:\Gits\bigfix_skills\skills\` — `jf-bigfix-dashboards`, `jf-bigfix-client-relevance`,
  `jf-bigfix-session-relevance`, `jf-bigfix-actionscript`, `jf-bigfix-parameterized-fixlets`,
  `jf-bigfix-mcp`, `jf-bigfix-api-powershell`, `jf-bigfix-log-analysis`

</canonical_refs>

---

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Initialize-RoleDb.ps1` migration block** — the `PRAGMA table_info(Map)` guarded
  `ALTER TABLE` pattern (used for `Updated_on` / `Valid_to`) is copied verbatim for the four
  new `Map` columns (D-18).
- **`Sqlite-Helper.ps1` / `Invoke-SqliteCommand`** — all root-server scripts use it;
  parameterised (`@{key=val}`), CLM-safe, one SELECT per call.
- **`fixlet_role_assigner.ojo` base64 chunk + Analysis-read code** — lifted into the
  break-glass path and the new `fixlet_role_admin.ojo` Reference-DB tab.
- **`rewritePrefetchUrls()` target path** — the snapshot publisher writes to exactly the
  `Uploads/CustomRepository/SoftwarePortal/roleref/` subtree so the same 127.0.0.1 rewrite
  serves it.
- **`RoleDB_Maintenance` logon task** — already deployed; extended to also run reconcile.

### Established Patterns
- **CLM-safe SQLite only** — `sqlite3.exe` + `Sqlite-Helper.ps1`, zero `Add-Type` / no
  `System.Data.SQLite.dll`.
- **D-12 upsert discipline** — `INSERT OR IGNORE` + conditional `UPDATE`, never
  `INSERT OR REPLACE`; `Locked_by_Override = 0` guard everywhere.
- **ActionScript `{` → `{{`** in `createfile` blocks (double the OPENING brace only).
- **IE9-only OJO JS** — `var` only, no arrow functions / template literals;
  `Msxml2.DOMDocument.6.0`; `API.Get/Post/Put`.
- **D-18 structured JSON log** per script run + Windows Event Log (Source
  `DereseSoftwarePortal`, IDs 8000–8099) on failure.

### Integration Points
- Endpoint `RoleAwareness.db` `Map` ← `Reconcile-LocalRoles.ps1` (policy action + logon task)
- Root `AutomationState.db` ← all root-server scripts; read by dashboards via a
  `Dereso SWD.bes` Analysis / REST query
- Custom Repository `…/SoftwarePortal/roleref/` ← `Publish-RoleSnapshot.ps1`; ← prefetch by
  the per-region policy action
- `name of current user` (client relevance) ↔ lowercased `sAMAccountName` (ingest) — the
  only user-identity join in the whole role pipeline

</code_context>

---

<specifics>
## Specific Ideas

- **"Break the link between the task and the CSV file"** — the CSV *was* the input contract;
  the reference DB replaces it. CSV path survives only as break-glass.
- **"Break the hardlink between users and computer IDs"** — role follows the *user*; a 24 h
  propagation delay is fine; no precomputed user→ComputerID matrix.
- **Operator publishes one region at a time** — the Region tab drives a single-value
  `GPC_Sub_Name` relevance gate; multiple live regions = multiple concurrent per-region
  policy actions.
- **Defence-in-depth region scoping** — checked in the action `<Relevance>` *and* re-checked
  in the endpoint reconcile against `snapshot.region`.
- **The MCP-connected BigFix server is a 9-computer lab, not production `gpbfs` (40k).**
  `GPC_Sub_Name` value verification + the SAM ↔ `name of current user` spot-check need the
  production fleet → 07-05. Task 787's live Action1 still uses the old file-exists gate +
  `explorer.exe/GetOwner`; the switch to `name of current user` is a real behavioural change
  from what's published — redeploy is a 07-05 step.

</specifics>

---

<deferred>
## Deferred Ideas

- **`GroupRoleMap` rule content** — which CN / display-name patterns map to which role. The
  matcher and authoring UI are designed; the operator must supply the first rule set (or a
  starter derived from the real export's group frequency). **This is the one gate on a live
  ingest run** — scripts can be written and tested against `SampleAxonious` fixtures before
  it lands. Not a phase blocker; a go-live blocker.
- **Per-session reconcile on multi-user hosts** — v1 is console-user only. Fan-out over
  `names of logged on users` deferred.
- **Operator region form at scale** — populating `RefUser.RegionID` and `RolePublication`
  via a form rather than hand-seeding. v1 seeds by hand.
- **Revoke automation / `EnableRevoke`** — endpoint role deactivation on group loss. v1 is
  age-out only.
- **Phase 8: Autonomous Dispatch** — fully automatic dispatch of "Ready" fixlets as offer
  actions.
- **Multi-tenant / multi-BigFix** — more than one BigFix instance from one Axonius export.
- **AD direct LDAP integration** — reading group membership directly, bypassing Axonius.
- **Fixlet rollback** — reverting a version + removing `X-Superseded-By`.
- **Self-Service catalog UI** — a custom end-user web UI separate from BigFix Self Service.

</deferred>

---

*Phase: 7-automation*
*Context gathered: 2026-08-01 · rewritten 2026-08-29*
