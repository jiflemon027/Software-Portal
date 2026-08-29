# Phase 7: End-to-End Automation — Research

**Researched:** 2026-08-29 (full rewrite — supersedes the stale 2026-08-01 file)
**Domain:** PowerShell 5.1/7.x automation pipelines on the BigFix root server · streaming ingest of a ~400 MB RFC-4180 CSV · CLM-safe SQLite via `sqlite3.exe` · per-region snapshot distribution through the BigFix Custom Repository · a per-region policy Fixlet (`.bes`) · an endpoint reconcile PowerShell script · AKeyless universal-identity credential retrieval · a new IE9-constrained OJO dashboard · Windows Scheduled Tasks
**Confidence:** HIGH for codebase-derived patterns · MEDIUM for BigFix runtime behaviours that need the production fleet (`name of current user` semantics, `127.0.0.1:52311` prefetch on non-root endpoints, live `GPC_Sub_Name` values) · these are explicitly flagged for 07-05

---

## Summary

Phase 7 is a **wiring and orchestration** phase, not a greenfield build. Every hard sub-problem
already has a proven analog in Phases 1–6: CLM-safe SQLite (`Sqlite-Helper.ps1`), the D-12
upsert discipline (`Initialize-RoleDb.ps1`), the prefetch-rewrite URL shape
(`fixlet_dispatcher.ojo`), base64-chunk + SingleAction XML + `GetRelevance`/`EvaluateRelevance`
(`fixlet_role_assigner.ojo`), the version-strip + supersede-stamp content loop
(`fixlet_update_tracker.ojo` / `fixlet_copier.ojo`), the `{`→`{{` ActionScript escaping rule,
and the `RoleDB_Maintenance` logon task (`Init  Current User and UserRole DB.bes`). The new
code is the glue between them plus one genuinely new component: a streaming ingest of the
Axonius export.

The **role pipeline** is now three decoupled loops with **no ComputerID anywhere**: (1) a daily
root-server ingest of the Axonius CSV into a combined `AutomationState.db`; (2) a daily publish
that emits one compact JSON snapshot **per published region** into the Custom Repository plus a
`.sha1` manifest, and keeps one **per-region policy Fixlet** in sync (its `<Relevance>` gates on
the endpoint's own `GPC_Sub_Name` client setting AND the `RoleAwareness.db` existence guard);
(3) an endpoint `Reconcile-LocalRoles.ps1` that reads the prefetched region snapshot, re-checks
the region, and D-12-upserts the **current console user's** roles into local `RoleAwareness.db`.
Roles follow the user and lapse by `Valid_to` age-out — there is no revoke path in v1.

The **content pipeline** (07-03) is unchanged in intent from the 2026-08-01 design:
`Invoke-ContentSync.ps1` (enumerate source sites → version-strip → diff → 4-step copy →
`X-Superseded-By` stamp) and `Stage-Repository.ps1` (parse prefetch lines → download →
`Get-FileHash -Algorithm SHA1` → place under `…\CustomRepository\SoftwarePortal\<sha1>\<file>`).

**Primary recommendation:** Reuse every existing pattern verbatim. Do not introduce new
libraries. For ingest, use `Import-Csv | ForEach-Object` streaming (RFC-4180-correct, CLM-safe,
bounded memory) with batched multi-row `INSERT` transactions built via the already-exported
`ConvertTo-SqliteLiteral` helper. For the per-region snapshot distribution, match the
`rewritePrefetchUrls()` output byte-for-byte and have `Publish-RoleSnapshot.ps1` re-`PUT` the
per-region policy Fixlet's prefetch line each run so its `sha1:`/`size:` stay valid.

---

<user_constraints>
## User Constraints (from CONTEXT.md — 2026-08-29 rewrite)

### Locked Decisions

**Architecture & data model**
- **D-01: One combined `AutomationState.db`** on the root server (not a separate `RoleReference.db`). One `Initialize-AutomationDb.ps1`; CLM-safe (`Sqlite-Helper.ps1`, zero `Add-Type`); migration-safe (`CREATE TABLE IF NOT EXISTS`, `PRAGMA table_info`-gated `ALTER TABLE`); same conventions as `Initialize-RoleDb.ps1` (`INTEGER PRIMARY KEY AUTOINCREMENT`, `datetime('now','localtime')`, partial indexes). Role tables (DDL in DESIGN.md §"Database designs A"): `Role`, `Region`, `GroupRoleMap`, `RefUser`, `UserRole`, `RolePublication`, `Snapshot`. Content tables (old D-05): `ContentItem`, `ContentCache` (was `CacheEntry`). Shared: one `SyncRun` with a `Type` column spanning `Ingest | Publish | ContentSync | RepoStage`; one `PipelineConfig` key/value table (DESIGN's `Config` seed keys merged in). Dropped: `RoleAssignment`.
- **D-02: No ComputerID in the role pipeline.** No user→computer resolution, no `Get-UserComputerMap.ps1`, no `<Target>` ComputerID lists, no `-CompID {computer id}`. Endpoints self-select by their own `GPC_Sub_Name` client setting.
- **D-03: `RoleAwareness.db` stays the endpoint source of truth.** Preserved unchanged: D-12 upsert (`INSERT OR IGNORE` + conditional `UPDATE`, **never** `INSERT OR REPLACE`), `Locked_by_Override = 0` guard, `Valid_to` renewal semantics, `UNIQUE(UserID, Role)`.
- **D-04: Username match key — lowercased `sAMAccountName` ↔ `name of current user`.** Ingest normalises to lowercased `sAMAccountName`; endpoint compares against BigFix client relevance `name of current user` (lowercased). No `explorer.exe`/`GetOwner()`. Residual mismatch surface: rows where `sAMAccountName` is blank and the coalesce falls back to UPN-localpart / `User Name` — keep `RefUser.Username_Src`; live spot-check in 07-05.

**Ingest — `Import-AxoniousExport.ps1` (root server, daily)**
- **D-05: Streaming CSV ingest.** Real export ~383–401 MB (`SampleAxonious/axonius-users_anond.csv`, anonymised; `axonious.db` = same as SQLite). Stream it; build the DB incrementally. 47 columns, BOM-prefixed, RFC-4180 quoted. Stale-file guard on `MaxExportAgeDays` (default 2) — **warn, do not abort.**
- **D-06: Username coalesce.** `sAMAccountName` → local-part of UPN → `Aggregated: User Name`, then `.ToLower()`. Priority order in `PipelineConfig.UsernameSourcePriority` (`sam,upn,username`). Store `RefUser.Username_Src` (`sam | upn | username`).
- **D-07: Multi-valued columns are loosely aligned — parse defensively, do not index-zip.** One cell holds a newline-delimited list; sub-lists across `Assigned Groups: *` columns have blank slots. Group values are LDAP DNs (`CN=BNX-M365-E3,OU=...,DC=office,DC=bzn`) or display names (`All Tenant Members`).
- **D-08: Entitlement resolution via `GroupRoleMap`.** Rule table (operator-authored): `Pattern` (exact NOCASE or `*`-suffix wildcard), `Match_On` (`cn | display | dn`), `Role`, `Priority` (advisory; all matches apply), `Active`. For each (user, role, source-group) write a `UserRole` row recording `Source_Type` (`AD Security Group | Mailing List | Azure AD Group | …`), `Source_Value` (CN / display name), `Source_System` (adapter), `Matched_Rule` (the `GRMID` that fired). `Source_Type` derived from `Assigned Groups: Group Type` + presence of `Assigned Groups: Email`.
- **D-09: Age-out marking, not deletion.** Any `UserRole` row not seen in the current run gets `Active = 0` (kept for audit). The snapshot emits only `Active = 1`. No explicit endpoint deactivation — an ex-member simply stops being renewed and their endpoint `Map` row lapses at `Valid_to`. This *is* the revoke mechanism.
- **D-10: Region is NOT resolved at ingest.** Reference data is global; the endpoint self-filters by its own `GPC_Sub_Name`. `RefUser.RegionID` is a reporting-only slot; v1 seeds `RolePublication` by hand.

**Publish — `Publish-RoleSnapshot.ps1` (root server, daily, after ingest)**
- **D-11: Per-region snapshot files — the only distribution mechanism.** No per-role base64 action payloads (scale: 40k endpoints global, ~10k in target BU, ~10k users). Per published region: `roleref-<region>-<date>.json` + `roleref-<region>-latest.json` pointer + `.sha1` manifest, written to `{DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\roleref\` (the path the Dispatcher's `rewritePrefetchUrls()` targets). Snapshot body: `{ run_id, region, built_on, validity_months, roles: [ { role, users: [...] } ] }` where `users` = DISTINCT `UserRole.UserID` WHERE `Active = 1` AND `(role, region)` is `Active` in `RolePublication`. `region` must equal exactly one `Region.GPC_Sub_Name`.
- **D-12: One per-region policy action, operator publishes regions one at a time.** `<Target>` = broad group / all clients with `RoleAwareness.db`. `<Relevance>` = the `RoleAwareness.db` existence guard **AND** `exists setting "GPC_Sub_Name" whose (value of it as string as lowercase = "<region-lowercased>") of client`. ActionScript: `prefetch` the current `roleref-<region>-latest.json` (SHA1 from the manifest) to `EC\SoftwarePortal\roleref\`, then run `Reconcile-LocalRoles.ps1`. Optional freshness gate (stamped "last snapshot date" client setting / file mtime vs now, 24 h tolerance) — **optional in v1, planner's call.**
- **D-13: `Snapshot` + `SyncRun` logging** for every ingest and publish run (D-18 JSON log + Windows Event Log on failure).

**Reconcile — `Reconcile-LocalRoles.ps1` (endpoint, NEW)**
- **D-14: Console user only in v1.** Detect the current console user via client relevance `name of current user` (lowercased). **No `names of logged on users` fan-out.** Per-session reconcile is deferred.
- **D-15: Re-check region, then D-12 upsert.** Read `EC\SoftwarePortal\roleref\roleref-<region>-latest.json`; abort if `snapshot.region` ≠ `value of setting "GPC_Sub_Name"`. If the console user is in the snapshot: for each of their roles, `INSERT OR IGNORE` + `UPDATE ... Valid_to = now + N months WHERE UserID=@u AND Role=@r AND Locked_by_Override = 0`. Also write new `Map` columns `Source_Type` / `Source_Value` (`|`-joined if >1 group) / `Region` (endpoint's own `GPC_Sub_Name`) / `Assigned_By = 'AxoniousSync'`, and `INSERT OR IGNORE INTO Roles` for any snapshot role missing locally.
- **D-16: Revoke — none.** No deactivation logic, no `EnableRevoke` flag in v1. Rows age out via `Valid_to` (D-09).
- **D-17: Old `Assign-RoleMapping.ps1` is kept** for the dashboard's manual-override / break-glass path only. `Reconcile-LocalRoles.ps1` is a separate new script.

**Endpoint `Map` migration + logon-rework coordination**
- **D-18: The uncommitted logon-rework is folded into Phase 7 Wave 0 (07-00).** Finalise and commit the in-progress `Initialize-RoleDb.ps1` v3 + `Init  Current User and UserRole DB.bes` changes **under Phase 7**. 07-00 also adds the additive `Map` migration (`PRAGMA table_info(Map)`-gated `ALTER TABLE`): `Source_Type TEXT`, `Source_Value TEXT`, `Region TEXT`, `Assigned_By TEXT`. No change to `UNIQUE(UserID, Role)`, `Active`, `Locked_by_Override`, `Valid_to`, or the D-12 upsert.
- **D-19: `RoleDB_Maintenance` logon task is extended, not replaced** — it also runs `Reconcile-LocalRoles.ps1`.

**Credential — AKeyless universal identity**
- **D-20: Reuse Cyera's existing universal identity.** No new identity, no plaintext, no DPAPI file. `Get-BigFixCredential.ps1` wraps `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1`: `.vault-token` → `POST api.akeyless.io/auth` (`universal_identity`) → `.token` → `POST .../get-secret-value` → `PSCredential`. `PipelineConfig.AKeylessTokenFile` = `…\BES Client\EC\Cyera\.vault-token`. `PipelineConfig.AKeylessSecretPath` = `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` (use as-is; operator corrects if wrong). Every root-server script calls it at runtime. **Removes the old DPAPI decision.**

**Region model**
- **D-21: Fixed 13-value `Region` seed list:** `UAP, MOT, APAC, APAC-MOT, APAC-M&A, AAG-DE, AAG-FR, AAG-UK, AAG-ES, AAG-BLX, AAG-PL, AAG-PT, GPC`. `Region.GPC_Sub_Name` must equal the endpoint client-setting value. Verify against live client settings in 07-05 (needs the production fleet — the MCP server is a 9-computer lab).

**Dashboards**
- **D-22: New `fixlet_role_admin.ojo`.** Tabs: GroupRoleMap (rules editor + "Test Pattern"), RolePublication ((role, region) pairs that are live), Region (publish picker over the fixed 13 seeds; one region at a time), Reference DB (read-only: last ingest time, per-role user counts, per-region breakdown). IE9 constraints + `API.Get/Post/Put` + tab-switch pattern as every existing OJO.
- **D-23: `fixlet_role_assigner.ojo` stays the break-glass tool.** CSV upload / preview / deploy kept working but demoted. Analysis view gains **Source** and **Region** columns (from the migrated `Map`, via a new/expanded `Dereso SWD.bes` property).
- **D-24: `fixlet_automation_monitor.ojo` is content-pipeline only.** Tabs: Status, Content Queue (review/approval), Repository Cache, Config (`PipelineConfig` + source-sites list, minus the GroupRoleMap editor which moves to `fixlet_role_admin.ojo`). No Role tab.

**Plan structure — 6 plans / 6 waves (D-25)**
| Plan | Wave | Title | Key deliverables |
|---|---|---|---|
| 07-00 | 0 | Foundation | Combined `AutomationState.db` schema + `Initialize-AutomationDb.ps1`; `Get-BigFixCredential.ps1`; `Region` seed (13); `GroupRoleMap` table; endpoint `Map` migration folded into `Initialize-RoleDb.ps1`; **finalise + commit the logon-rework** (D-18); test fixtures from `SampleAxonious` |
| 07-01 | 1 | Ingest | `Import-AxoniousExport.ps1` (streaming CSV → DB, DN/username coalesce, `GroupRoleMap` resolve, `Source_Type` derivation, age-out marking); `SyncRun` logging; unit tests |
| 07-02 | 2 | Publish + distribute + reconcile | `Publish-RoleSnapshot.ps1` (per-region JSON + `.sha1` manifest → Custom Repository); per-region policy fixlet `.bes` (single-region `GPC_Sub_Name` relevance + prefetch); `Reconcile-LocalRoles.ps1` (endpoint, console-user-only, D-12 upsert, wired into `RoleDB_Maintenance`); `Snapshot` logging; scheduled-task XML; unit tests |
| 07-03 | 3 | Content pipeline | `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`, scheduled tasks — **unchanged from old 07-02** |
| 07-04 | 4 | Dashboards | new `fixlet_role_admin.ojo`; `fixlet_role_assigner.ojo` Analysis + Source/Region; `fixlet_automation_monitor.ojo` content-only; `Dereso SWD.bes` Source/Region props |
| 07-05 | 5 | Integration + rollout | `-WhatIf` dry-run for the new scripts; SAM ↔ `name of current user` live spot-check; live `GPC_Sub_Name` value verification; per-region phased enablement; redeploy task 787; admin run-book; full regression gate |

Waves 1 and 3 can run in parallel after Wave 0. Wave 2 needs Wave 1. Wave 4 needs Waves 2 and 3. Wave 5 has a human-verify checkpoint.

- **D-26: Phased, per region.** Week 1 all new scripts `-WhatIf`; then role pipeline live for one pilot region; widen region-by-region; content pipeline live with auto-approve OFF; auto-approve enabled for low-risk categories last.

### Claude's Discretion (researched recommendations below in "Discretion Resolutions")

- Combined-DB internal naming where DESIGN.md and old D-05 disagree (`Config` vs `PipelineConfig`, `CacheEntry` vs `ContentCache`, unified `SyncRun` column set) — resolve to least-churn.
- Whether 07-02's policy action carries the optional freshness gate (D-12) in v1.
- Exact wave-level task subdivision inside 07-01.
- `Dereso SWD.bes` property names for the new Source/Region Analysis columns.

### Deferred Ideas (OUT OF SCOPE — do not research, do not plan)

- `GroupRoleMap` **rule content** (which CN/display patterns → which role) — operator supplies the first rule set. Not a phase blocker; a **go-live** blocker. Scripts are written/tested against `SampleAxonious` fixtures first.
- Per-session reconcile on multi-user hosts (v1 = console user only).
- Operator region form at scale (v1 hand-seeds `RefUser.RegionID` / `RolePublication`).
- Revoke automation / `EnableRevoke` (v1 = age-out only).
- Phase 8: Autonomous Dispatch. Multi-tenant / multi-BigFix. AD direct LDAP. Fixlet rollback. Self-Service catalog UI.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

REQUIREMENTS.md has no per-phase REQ-ID list for Phase 7. Coverage set = **all of FR-01…FR-10 at the automation layer + a new NFR (scheduled unattended operation with audit trail)**.

| ID | Description | Research support / which plan carries it |
|----|-------------|------------------------------------------|
| FR-01 | Fixlet copy from external sites | `Invoke-ContentSync.ps1` (07-03) replicates `fixlet_copier.ojo`'s `buildXml()` 4-step copy via `POST /api/fixlets/custom/<site>` (plural). Pattern verified in `fixlet_update_tracker.ojo` `copyNextItem` + `fixlet_copier.ojo`. |
| FR-02 | Role-based fixlet association | Automation layer: `GroupRoleMap` (07-00/07-01) + `UserRole` reference + per-region snapshot deliver role→user data; `Reconcile-LocalRoles.ps1` (07-02) writes it into `RoleAwareness.db` `Map`. |
| FR-03 | Role-based relevance modification | Unchanged — `fixlet_modifier.ojo` `buildRoleRelevance()` remains the mechanism; snapshot/reconcile only populate the DB it reads. No new relevance-generation code. |
| FR-04 | Role-based description update | Inherited from `fixlet_modifier.ojo` `Associated_Roles` MIME write; content pipeline (07-03) transfers it on copy (`fixlet_update_tracker.ojo` pattern). |
| FR-05 | Target group deployment | Dispatcher stays a human step. Content pipeline delivers to a "Ready" `ContentItem.stage` only. |
| FR-06 | Automatic offer creation | Dispatcher patterns reused for the human-confirmed deploy step; not automated in v1 (deferred to Phase 8). |
| FR-07 | Default deployment options | Dispatcher `PORTAL_CONFIG` defaults unchanged. |
| FR-08 | Automatic user registration on logon | `RoleDB_Maintenance` logon task (folded in + committed at 07-00, D-18) + `Reconcile-LocalRoles.ps1` wired into it (D-19). |
| FR-09 | Role-aware web report | Not modified in Phase 7. |
| FR-10 | Fixlet version update tracking | `Invoke-ContentSync.ps1` (07-03) automates `fixlet_update_tracker.ojo`'s scan → `stripVersion` → diff → copy → `X-Superseded-By` stamp loop. |
| NFR-NEW | Scheduled unattended operation with audit trail | `SyncRun` + `Snapshot` tables + per-run JSON logs + Windows Event Log (Source `DereseSoftwarePortal`, IDs 8000–8099) + `-WhatIf` dry-run on every new script. Scheduled Tasks run non-interactively as a service account. |
</phase_requirements>

---

## Discretion Resolutions

| Discretion item | Recommendation | Rationale |
|---|---|---|
| `Config` vs `PipelineConfig` | **`PipelineConfig`** (key `Key`/`Value`/`Description`). | CONTEXT D-01 says so explicitly ("DESIGN's `Config` seed keys merged into it"). DESIGN's `Config` is the loser. Merge all DESIGN seed keys (`AxoniousExportPath`, `MaxExportAgeDays`, `SnapshotOutputDir`, `SnapshotUrlBase`, `BESRootUrl`, `AKeylessTokenFile`, `AKeylessSecretPath`, `ValidityMonths`, `UsernameSourcePriority`, `SQLDir`, `AlertWebhook`) as `PipelineConfig` rows on init. |
| `CacheEntry` vs `ContentCache` | **`ContentCache`.** | CONTEXT D-01 states "`ContentCache` (was `CacheEntry`)". Least churn now = follow CONTEXT; the stale 07-RESEARCH's `CacheEntry` is dead. |
| Unified `SyncRun` column set | Use the **DESIGN.md `SyncRun` shape** (`RunID` TEXT PK, `Type`, `Started_on`, `Ended_on`, `Status`, `Rows_In`, `Users_Seen`, `Roles_Seen`, `Entitlements`, `Summary`, `Error_Count`) and widen `Type` CHECK to `Ingest | Publish | ContentSync | RepoStage`. Add nullable content-only columns (`Items_Discovered`, `Items_Copied`, `Items_Failed`) rather than a second table. | One table, one logging helper, one dashboard read. DESIGN's column names already match the `Initialize-RoleDb.ps1` house style. |
| 07-02 optional freshness gate in v1 | **Include a minimal version.** After a successful reconcile, `Reconcile-LocalRoles.ps1` writes client setting `roleref_<region>_applied` = `snapshot.built_on` (date). The policy Fixlet `<Relevance>` ORs in `(not exists setting "roleref_<region>_applied" of client) OR (now - (value of setting "roleref_<region>_applied" of client as time) > 1*day)`. | Without it, on a host where the console user never logs off, roles silently stop being renewed and expire at `Valid_to` (6 months) — a latent production bug. Cost is ~3 lines of relevance + one `setting` write. Flag the tradeoff to the user; if they want strict v1 minimalism, the fallback is "accept that only logon + a fresh policy-action version triggers reconcile". |
| 07-01 task subdivision | Split into 4 tasks: **(a)** CSV reader + header/BOM/column-map validation + stale-file guard; **(b)** per-row transform: username coalesce (D-06), multi-valued `Assigned Groups: *` defensive parse (D-07), `Source_Type` derivation (D-08); **(c)** `GroupRoleMap` matcher (exact NOCASE + `*`-suffix, `Match_On` cn/display/dn) + `UserRole` batched upsert; **(d)** age-out sweep (`Active=0` for rows whose `Last_RunID` ≠ this run) + `SyncRun` finalisation + JSON log + Event Log. Each task gets its own Pester file. | The streaming reader, the parser, and the matcher are independently testable against small fixtures; keeping them separate stops one 600-line script from being untestable. |
| `Dereso SWD.bes` new property names | **`map_source in r.db`** and **`map_region in r.db`**, each emitting `UserID || '\|' || Role || '\|' || <col>` rows (same tuple-split idiom as the existing `mapped_users in r.db` property). Keep the existing 4 properties untouched; add 2. | Matches the existing naming (`… in r.db`) and the existing `PT5M` evaluation period; the dashboard's Analysis-read code already knows how to split `%22`-tuple rows. |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Axonius CSV parse + entitlement resolution | Root server (`Import-AxoniousExport.ps1`) | — | File lives on the root server disk; no BigFix interaction needed for ingest. |
| `GroupRoleMap` rule storage + editing | `AutomationState.db` (root server) | `fixlet_role_admin.ojo` GroupRoleMap tab (writes via a SingleAction to the root-server BES client) | Config lives in the DB; the dashboard is the editor. |
| Reference DB (`RefUser` / `UserRole` / `RolePublication`) | Root server (PS scripts) | `fixlet_role_admin.ojo` Reference-DB tab (read-only via Analysis) | DB is on the root server; dashboard surfaces counts. |
| Per-region snapshot JSON + `.sha1` manifest | Root server file system (`…\CustomRepository\SoftwarePortal\roleref\`) | BigFix HTTP (`127.0.0.1:52311` prefetch URL) | Files placed directly on disk; served by the BES web root. |
| Per-region policy Fixlet lifecycle | BigFix REST API (`Publish-RoleSnapshot.ps1` re-`PUT`s it each run) | Operator (publishes / stops per region) | Prefetch `sha1:`/`size:` change daily → the Fixlet must be updated each publish. |
| Region gate | **Client/Fixlet relevance** (`<Relevance>` on the policy Fixlet) + re-check in `Reconcile-LocalRoles.ps1` | — | `settings … of client` is only available in client relevance, and defence-in-depth requires the second check. |
| Console-user detection | **Client relevance** `name of current user`, substituted into ActionScript as a parameter | `explorer.exe`/`GetOwner()` fallback in the logon-task invocation path (no BigFix relevance there) | The policy-action path has client relevance; the `RoleDB_Maintenance` scheduled-task path runs as SYSTEM with no relevance engine. |
| `RoleAwareness.db` `Map` writes | BES client (ActionScript → embedded `Reconcile-LocalRoles.ps1`) | — | Same tier as Phase 4 — the client runs the embedded PS script. |
| `AutomationState.db` reads for dashboards | BigFix Analysis (root server enrolled as a BES client) | OJO `EvaluateRelevance` / REST fallback | `GetRelevance` reads cached Analysis results; fallback covers "Analysis not yet reporting". |
| `AutomationState.db` writes | Root server (PS scripts; dashboard Config writes via a SingleAction to the root-server client) | — | Scripts run where the DB lives. |
| Content: fixlet discovery / copy / supersede stamp | BigFix REST API (`Invoke-ContentSync.ps1`) | — | `GET /api/fixlets/<type>/<site>`, `POST /api/fixlets/custom/<site>` (plural), `PUT /api/fixlet|task/custom/<site>/<id>` (singular). |
| Installer pre-staging + SHA1 verify | Root server file system (`Stage-Repository.ps1`) | — | `Get-FileHash -Algorithm SHA1`; no client involvement. |
| Credential retrieval | Root server (`Get-BigFixCredential.ps1` → AKeyless HTTPS) | — | Reads Cyera's `.vault-token`; returns a `PSCredential` in memory only. |
| Scheduled task registration | Root server (`Register-ScheduledTask` + exported XML) | `schtasks.exe /Create /XML` fallback | Programmatic registration; XML for the admin run-book. |

---

## Standard Stack

### Core

| Tool | Version | Purpose | Why standard here |
|------|---------|---------|-------------------|
| PowerShell (root-server scripts) | Prefer **`pwsh.exe` 7.6.3** (verified on host); PS 5.1 must also work | All ingest/publish/content orchestration | PS7 gives `Invoke-RestMethod -SkipCertificateCheck` for the BigFix self-signed cert. Keep scripts PS5.1-compatible in syntax (no ternary, no `??`) so they degrade gracefully. `[VERIFIED: bash pwsh --version]` |
| PowerShell (endpoint scripts) | **PS 5.1 only** | `Reconcile-LocalRoles.ps1`, `Initialize-RoleDb.ps1` | `#Requires -Version 5.1`; runs under Constrained Language Mode on hardened endpoints. `[VERIFIED: codebase Initialize-RoleDb.ps1 line 2]` |
| `Sqlite-Helper.ps1` | project (existing, unchanged) | CLM-safe SQLite for **every** script, both tiers | `sqlite3.exe` CLI via stdin pipe; injection-safe `@param` substitution; `PRAGMA busy_timeout=30000` auto-prepended; `__hex` non-ASCII read-back; WR-02 = one result-returning statement per call. Also **exports `ConvertTo-SqliteLiteral`** to callers (use it for batch INSERT building). `[VERIFIED: codebase Dashboard_4_samples/Sqlite-Helper.ps1]` |
| `sqlite3.exe` | 3.53.1 (`sqlite-tools-win-x64-3530100`, sha1 `184d4d0b75cd75c2118fb22a1727e9220f843b98`) | SQLite backend | Already prefetched to endpoints by `Init  Current User and UserRole DB.bes`. The **root server needs a local copy** at `PipelineConfig.SQLDir` — 07-00 must provision/verify it (see Environment Availability). `[VERIFIED: codebase Init  Current User and UserRole DB.bes prefetch block]` |
| Node.js + built-in `assert` | v24.15.0 (verified) | Unit tests for the new `fixlet_role_admin.ojo` pure JS functions | Every existing OJO test file uses `node tests/unit/<x>.test.js` with `assert`. `[VERIFIED: bash node --version; codebase tests/unit/*.test.js]` |
| **Pester** | **5.7.1 (installed) — use v5 syntax** | Unit tests for the new PowerShell scripts (ingest parser, GroupRoleMap matcher, snapshot builder, reconcile upsert) | Phase 7 is ~70% PowerShell; there is no existing PS test precedent because Phases 1–6 were OJO-JS. Pester 5 is already on the host. Pin `-MinimumVersion 5.0` in the test invocation to avoid the co-installed Pester 3.4.0. `[VERIFIED: bash Get-Module -ListAvailable Pester]` |
| BigFix REST API | HTTP at `:52311`, self-signed cert | Content pipeline + `Publish-RoleSnapshot.ps1` fixlet `PUT` | Only way for server-side PS to touch the BES object model. `[CITED: codebase fixlet_update_tracker.ojo, fixlet_copier.ojo]` |

### Supporting (all built-in — no installs)

| Tool | Purpose | Notes |
|------|---------|-------|
| `Import-Csv` | Streaming RFC-4180 ingest of the 400 MB export | Pipe to `ForEach-Object` and **do not collect** the results → memory stays bounded. Handles BOM, quoted fields, and **embedded newlines inside quotes** correctly (critical — see Pitfall 1). `[VERIFIED: behaviour is standard PS; RFC-4180 handling CITED: Microsoft docs]` |
| `Get-FileHash -Algorithm SHA1` | Prefetch-file + snapshot verification | Never hand-roll. `[VERIFIED: stale 07-RESEARCH, standard PS]` |
| `Invoke-RestMethod` / `Invoke-WebRequest` | BigFix REST; AKeyless HTTPS; snapshot download in `Stage-Repository.ps1` | PS7 `-SkipCertificateCheck` for BigFix. AKeyless is a real public CA cert — no bypass. `[CITED: G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1]` |
| `Register-ScheduledTask` + `New-ScheduledTask*` | Task registration | Also `schtasks.exe /Query /TN … /XML >` to export XML for the run-book. Pattern already in `Init  Current User and UserRole DB.bes` (`RoleDB_Maintenance`). `[VERIFIED: codebase]` |
| `Write-EventLog` / `New-EventLog` | Failure alerts, Event IDs 8000–8099, Source `DereseSoftwarePortal` | Register the source once in 07-00: `if (-not [System.Diagnostics.EventLog]::SourceExists("DereseSoftwarePortal")) { New-EventLog … }`. `[VERIFIED: stale 07-RESEARCH Pitfall 5]` |
| `ConvertTo-Json -Compress` / `ConvertFrom-Json` | Snapshot emit, REST bodies, JSON logs | `-Compress` for anything sent over HTTP or written as a snapshot; pretty for human log files. `[VERIFIED: stale 07-RESEARCH Pitfall 9]` |

### Alternatives Considered

| Instead of | Could use | Tradeoff / verdict |
|------------|-----------|--------------------|
| `Import-Csv \| ForEach-Object` streaming | `[System.IO.StreamReader]` + hand-written RFC-4180 state machine | Faster on 400 MB, but `New-Object System.IO.StreamReader` is **CLM-blocked** ("only core types are supported") and a hand-rolled parser must correctly handle quoted embedded newlines or it silently corrupts every multi-valued row. **Verdict: `Import-Csv` unless profiling on the real file shows an unacceptable runtime AND the root server is confirmed non-CLM.** `[VERIFIED: WebSearch — CLM type allow-list]` |
| `Import-Csv` | `switch -File $path { … }` (CLM-safe, streams, very fast) | `switch -File` reads **physical lines** — it breaks on quoted embedded newlines exactly like a naive `StreamReader` loop. Only safe if you first confirm the export has no in-quote newlines (the DESIGN says it does). **Verdict: rejected for the CSV; fine for the small `.sha1` manifests.** |
| Per-row `Invoke-SqliteCommand` INSERT | Batched multi-row `INSERT … VALUES (…),(…),…` inside `BEGIN;…COMMIT;`, built with `ConvertTo-SqliteLiteral` | Each `Invoke-SqliteCommand` spawns a fresh `sqlite3.exe` process — per-row = tens of thousands of spawns = minutes of overhead. **Verdict: batch 200–500 rows per call; non-result statements can be freely combined per WR-02.** `[VERIFIED: codebase Sqlite-Helper.ps1 WR-02 + exported ConvertTo-SqliteLiteral]` |
| BigFix `prefetch` of the snapshot | `Invoke-WebRequest` GET inside `Reconcile-LocalRoles.ps1` against the relay `…/Uploads/CustomRepository/SoftwarePortal/roleref/roleref-<region>-latest.json` | Sidesteps the daily-changing-`sha1:` problem and the `127.0.0.1` question entirely; always gets latest. Loses BigFix download throttling/caching (negligible for a small JSON). **Verdict: primary = match the proven `rewritePrefetchUrls()` shape + re-`PUT` the fixlet each publish; keep the HTTP-GET as a documented fallback if prefetch misbehaves on non-root endpoints in 07-05.** |
| Pester 5 for PS tests | Node `assert` harness shelling out to `pwsh` | The OJO precedent is Node, but PS scripts test far more naturally in Pester (mocking `Invoke-SqliteCommand`, `Invoke-RestMethod`). **Verdict: Pester 5 for `.ps1`, Node `assert` for `.ojo`.** |

**Installation:** none. No npm / pip / nuget / PSGallery installs. Every dependency is built-in, an existing project file, or already on the host.

---

## Package Legitimacy Audit

Phase 7 installs **zero external packages**. slopcheck not run — not applicable (no registry packages recommended).

| Component | Origin | Age / provenance | Disposition |
|-----------|--------|------------------|-------------|
| `Sqlite-Helper.ps1` | project file, in use since Phase 3 | verified in repo | Approved |
| `sqlite3.exe` 3.53.1 | BigFix prefetch, sha1 `184d4d0b75cd75c2118fb22a1727e9220f843b98` | pinned hash in existing `.bes` files | Approved |
| Pester 5.7.1 | already installed on host (`Get-Module -ListAvailable`) | Microsoft-signed module, widely used | Approved — pin `-MinimumVersion 5.0` |
| Node.js `assert` | Node core | built-in | Approved |
| AKeyless REST API | `api.akeyless.io` (public SaaS, real CA cert) | already trusted by the Cyera integration on this host | Approved — reuse, do not re-provision |

**Removed (SLOP):** none. **Flagged (SUS):** none.

---

## Architecture Patterns

### System architecture diagram

```
ROLE PIPELINE (no ComputerID anywhere)
=====================================

[Axonius export CSV  ~400 MB, BOM, RFC-4180, 47 cols]
        | (daily, path = PipelineConfig.AxoniousExportPath; stale-file guard = warn only)
        v
Import-Csv | ForEach-Object   ── streaming, bounded memory ──┐
        |                                                    |
        v  per row:                                          |
   username coalesce (sam -> upn-localpart -> User Name, .ToLower)   [RefUser.Username_Src]
   defensive multi-value parse of "Assigned Groups: *" (no index-zip)
   Source_Type = f(Group Type, Email present)
        |
        v  GroupRoleMap match (exact NOCASE | '*'-suffix; Match_On cn|display|dn; all matches apply)
        |
        v  batched INSERT (200-500 rows/txn, built via ConvertTo-SqliteLiteral)
[AutomationState.db]  RefUser, UserRole (one row per user x role x source-group), SyncRun(Type=Ingest)
        |
        v  age-out sweep: UserRole.Active = 0 where Last_RunID <> thisRun
        |
        v  Publish-RoleSnapshot.ps1  (daily, after ingest)
        |    for each (role,region) Active in RolePublication:
        |      users = DISTINCT UserRole.UserID WHERE Active=1
        |      write roleref-<region>-<date>.json  + roleref-<region>-latest.json + .sha1
        |      -> {DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\roleref\
        |    re-PUT the per-region policy Fixlet so its prefetch sha1:/size: match today's file
        |    write Snapshot + SyncRun(Type=Publish)
        v
[BES web root]  http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/roleref-<region>-latest.json
        |
        v  PER-REGION POLICY FIXLET (.bes, one per published region)
        |   <Relevance> = RoleAwareness.db existence guard
        |            AND  exists setting "GPC_Sub_Name" whose (value as string as lowercase = "<region>") of client
        |            AND  (freshness gate: setting roleref_<region>_applied missing OR older than 24h)   [recommended]
        |   ActionScript: prefetch the region json -> copy to EC\SoftwarePortal\roleref\
        |                 parameter "ConsoleUser" = "{name of current user as lowercase}"
        |                 run Reconcile-LocalRoles.ps1 -ConsoleUser ... -Region "{value of setting "GPC_Sub_Name" of client}"
        v
[Endpoint]  Reconcile-LocalRoles.ps1  (also invoked by RoleDB_Maintenance logon task, D-19)
        |   read roleref-<region>-latest.json ; ABORT if snapshot.region <> GPC_Sub_Name
        |   if -ConsoleUser absent (logon-task path): derive via explorer.exe GetOwner (== bare lc SAM)
        |   for each role of the console user in the snapshot:
        |      INSERT OR IGNORE INTO Roles (Role)
        |      INSERT OR IGNORE INTO Map (...)                              -- D-12 step 1
        |      UPDATE Map SET Active=1, Updated_on=now,
        |             Valid_to = now + ValidityMonths months,
        |             Source_Type=?, Source_Value=?, Region=?, Assigned_By='AxoniousSync'
        |       WHERE UserID=@u AND Role=@r AND Locked_by_Override = 0       -- D-12 step 2
        |   write client setting roleref_<region>_applied = snapshot.built_on
        v
[RoleAwareness.db Map]  <- read unchanged by fixlet_modifier.ojo / fixlet_console.ojo / SSA _dashboard.html


CONTENT PIPELINE (unchanged intent — 07-03)
===========================================

[BigFix source sites] --GET /api/fixlets/<type>/<site>--> Invoke-ContentSync.ps1
        stripVersion (/ v\d[\d.]+/g) -> diff vs portal site -> per-item 4-step copy
        --POST /api/fixlets/custom/Dereso Software Portal (plural)-->
        --PUT  /api/fixlet|task/custom/.../<id>  (singular; X-Superseded-By stamp)-->
[AutomationState.db] ContentItem (discovered->staged->categorized->ready->live), SyncRun(Type=ContentSync)
        | on success: Start-ScheduledTask RepoStage
        v
Stage-Repository.ps1  parse prefetch lines -> download original URL -> Get-FileHash SHA1
        -> {wwwRootFolder}\Uploads\CustomRepository\SoftwarePortal\<sha1>\<file>
[AutomationState.db] ContentCache, SyncRun(Type=RepoStage)


DASHBOARDS (07-04)
==================
fixlet_role_admin.ojo      -- GroupRoleMap | RolePublication | Region | Reference DB (read-only)
fixlet_role_assigner.ojo   -- break-glass CSV path + Analysis view (+ Source / Region columns)
fixlet_automation_monitor.ojo -- Status | Content Queue | Repository Cache | Config   (content only)
   all read AutomationState.db / RoleAwareness.db via Dereso SWD.bes Analysis (GetRelevance),
   REST/EvaluateRelevance fallback, IE9 JS only.
```

### Recommended file layout

```
scripts/                              # NEW — root-server automation
├── Initialize-AutomationDb.ps1       # 07-00  combined schema + PipelineConfig seed + EventLog source + sqlite3.exe check
├── Get-BigFixCredential.ps1          # 07-00  AKeyless universal-identity wrapper -> [PSCredential]
├── Import-AxoniousExport.ps1         # 07-01  streaming ingest
├── Publish-RoleSnapshot.ps1          # 07-02  per-region JSON + .sha1 + re-PUT policy fixlet
├── Invoke-ContentSync.ps1            # 07-03  (unchanged design)
├── Stage-Repository.ps1              # 07-03  (unchanged design)
└── Register-AutomationTasks.ps1      # 07-02/07-03  Register-ScheduledTask + XML export
endpoint/                             # NEW — deployed via .bes
└── Reconcile-LocalRoles.ps1          # 07-02  console-user D-12 upsert into RoleAwareness.db
Dashboard_4_samples/
├── Initialize-RoleDb.ps1             # 07-00  + Map migration (Source_Type/Source_Value/Region/Assigned_By); commit logon-rework
├── Init  Current User and UserRole DB.bes  # 07-00  + RoleDB_Maintenance also runs Reconcile-LocalRoles.ps1 (D-19); commit
├── Dereso SWD.bes                    # 07-04  + 2 properties (map_source, map_region)
└── Sqlite-Helper.ps1                 # unchanged
bes/
└── RoleRef-Policy-<region>.bes       # 07-02  per-region policy Fixlet template (region token substituted by Publish-RoleSnapshot.ps1)
Existing Dashboards/
├── fixlet_role_admin.ojo             # 07-04  NEW
├── fixlet_role_assigner.ojo          # 07-04  + Source/Region Analysis columns; demote CSV path
└── fixlet_automation_monitor.ojo     # 07-04  NEW (content-only, 4 tabs)
config/
├── PipelineConfig.defaults.json      # 07-00  seed values (documented, imported to DB on init)
├── task-*.xml                        # exported Scheduled Task XML for the run-book
tests/
├── fixtures/phase-07/                # 07-00  carved from SampleAxonious + synthetic edge cases
│   ├── axonious-sample-50.csv        #   50 users, BOM, quoted embedded newlines, blank SAM rows, DN + display-name groups
│   ├── axonious-multivalue-edge.csv  #   loosely-aligned Assigned Groups: * columns
│   ├── grouprolemap-seed.json        #   exact + wildcard + each Match_On
│   ├── roleref-AAG-UK-sample.json    #   snapshot shape for reconcile tests
│   └── automation-db-schema.sql      #   full DDL for an in-memory test DB
├── unit/role_admin.test.js           # 07-04  node assert — pure JS functions
├── pester/Import-AxoniousExport.Tests.ps1     # 07-01
├── pester/GroupRoleMap.Tests.ps1              # 07-01
├── pester/Publish-RoleSnapshot.Tests.ps1      # 07-02
├── pester/Reconcile-LocalRoles.Tests.ps1      # 07-02
└── integration/automation.integration.test.js # 07-05  BIGFIX-gated
docs/
└── automation-admin-guide.md         # 07-05  run-book (setup checklist, per-region rollout, task 787 redeploy)
```

### Pattern 1 — CLM-safe SQLite: dot-source + one-result rule + `changes()` co-location

```powershell
# [VERIFIED: codebase Dashboard_4_samples/Sqlite-Helper.ps1 + Initialize-RoleDb.ps1]
. "$PSScriptRoot\Sqlite-Helper.ps1"      # also exports ConvertTo-SqliteLiteral to this scope

# write (any number of non-result statements per call is fine)
Invoke-SqliteCommand -DatabasePath $Db -SQLDir $SQLDir -Sql @"
INSERT OR IGNORE INTO RefUser (UserID, SamAccount, Upn, Display_Name, Domain, Username_Src, Last_RunID)
VALUES (@u,@sam,@upn,@dn,@dom,@src,@run);
UPDATE RefUser SET Last_Seen = datetime('now','localtime'), Last_RunID = @run WHERE UserID = @u;
"@ -Parameters @{ u=$uid; sam=$sam; upn=$upn; dn=$dn; dom=$dom; src=$src; run=$runId } | Out-Null

# read (exactly ONE result-returning statement — WR-02)
$rows = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $SQLDir `
  -Sql "SELECT DISTINCT UserID FROM UserRole WHERE Role = @r AND Active = 1" -Parameters @{ r = $role }

# UPDATE + SELECT changes() MUST be one call (fresh sqlite3.exe process per call; changes() is
# connection-scoped) — copied verbatim from Initialize-RoleDb.ps1 line ~248
$res = Invoke-SqliteCommand -DatabasePath $Db -SQLDir $SQLDir -Sql @"
UPDATE Map SET Active=1, Updated_on=datetime('now','localtime'),
       Valid_to=datetime('now','localtime',@v),
       Source_Type=@st, Source_Value=@sv, Region=@rg, Assigned_By='AxoniousSync'
 WHERE UserID=@u AND Role=@r AND Locked_by_Override = 0;
SELECT changes() AS n
"@ -Parameters @{ v="+$ValidityMonths months"; st=$srcType; sv=$srcVal; rg=$region; u=$user; r=$role }
```

### Pattern 2 — batched multi-row INSERT for the 400 MB ingest

```powershell
# [VERIFIED: Sqlite-Helper.ps1 exports ConvertTo-SqliteLiteral; WR-02 allows unlimited non-result stmts]
$batch = New-Object System.Collections.ArrayList   # ArrayList is CLM-permitted (core type)
function Flush-Batch {
  if ($batch.Count -eq 0) { return }
  $values = ($batch | ForEach-Object { $_ }) -join ",`n"
  $sql = "BEGIN;`nINSERT OR IGNORE INTO UserRole (UserID,Role,Source_Type,Source_Value,Source_System,Matched_Rule,Last_RunID,Last_Seen) VALUES`n$values;`nCOMMIT;"
  Invoke-SqliteCommand -DatabasePath $Db -SQLDir $SQLDir -Sql $sql | Out-Null
  $batch.Clear()
}
Import-Csv -Path $csvPath | ForEach-Object {
  $row = $_
  # ... coalesce username, parse groups, resolve roles ...
  foreach ($m in $matches) {
    [void]$batch.Add("($(ConvertTo-SqliteLiteral $uid),$(ConvertTo-SqliteLiteral $m.Role),$(ConvertTo-SqliteLiteral $m.SrcType),$(ConvertTo-SqliteLiteral $m.SrcVal),$(ConvertTo-SqliteLiteral $m.SrcSys),$(ConvertTo-SqliteLiteral ([string]$m.GRMID)),$(ConvertTo-SqliteLiteral $runId),datetime('now','localtime'))")
    if ($batch.Count -ge 400) { Flush-Batch }
  }
}
Flush-Batch
```

Note: `Import-Csv` column access is by the **exact header string**, e.g. `$row.'Azure Ad: AD sAMAccountName'`, `$row.'Aggregated: Assigned Groups: Display Name'`.

### Pattern 3 — D-12 upsert discipline (endpoint, unchanged)

`INSERT OR IGNORE` to create the row without disturbing existing state, then a **conditional
`UPDATE` guarded by `Locked_by_Override = 0`**. Never `INSERT OR REPLACE` (it deletes + re-inserts,
destroying `Active` / `Locked_by_Override` / `Created_on`). Verbatim idiom in
`Initialize-RoleDb.ps1` and `fixlet_role_assigner.ojo`'s `buildAssignActionScript`.
`Reconcile-LocalRoles.ps1` also does `INSERT OR IGNORE INTO Roles (Role)` for any snapshot role
missing locally (new roles propagate without an init redeploy — D-15).

### Pattern 4 — per-region policy Fixlet `<Relevance>` (client relevance)

```
# DB-existence guard (verbatim from fixlet_role_assigner.ojo line 459 / Dereso SWD.bes <Relevance>)
(exists folder it whose (exists files "RoleAwareness.db" whose (exists sqlite database of it) of it)) of
  ((concatenation (if windows of operating system then "\" else "/") of
    ((item 0 of it;item 1 of it;item 2 of it) of
     ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal"))))
AND
# single-region gate (D-12)
(exists setting "GPC_Sub_Name" whose (value of it as string as lowercase = "aag-uk") of client)
AND
# freshness gate (recommended v1 — see Discretion Resolutions)
((not exists setting "roleref_aag-uk_applied" of client)
 OR (now - ((value of setting "roleref_aag-uk_applied" of client) as string as time) > 1 * day))
```

Multiple `<Relevance>` elements are ANDed by BigFix — but building one combined string is safer
than relying on a parser that only reads the first (`bigfix-relevance` skill §3). The region
literal is lower-cased and substituted by `Publish-RoleSnapshot.ps1` when it renders the
per-region `.bes` from the template.

### Pattern 5 — prefetch + copy in the policy Fixlet ActionScript

Match `rewritePrefetchUrls()` output byte-for-byte (`bigfix-relevance` skill §4):

```
prefetch roleref-aag-uk-latest.json sha1:<sha1-from-manifest> size:<bytes> http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/roleref-aag-uk-latest.json

// SWPDir / roleref dir  (client-relevance substitution — NOT touched by { -> {{ escaping)
parameter "SWPDir"="{(concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal")))}"
parameter "ConsoleUser"="{name of current user as lowercase}"
parameter "Region"="{value of setting "GPC_Sub_Name" of client as string}"

if {not exists folder ((parameter "SWPDir") & "\roleref")}
    runhidden cmd /c mkdir "{parameter "SWPDir"}\roleref"
endif
copy "__Download\roleref-aag-uk-latest.json" "{parameter "SWPDir"}\roleref\roleref-aag-uk-latest.json"

action uses wow64 redirection {x64 of operating system}
waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "{parameter "SWPDir"}\Reconcile-LocalRoles.ps1" -ConsoleUser "{parameter "ConsoleUser"}" -Region "{parameter "Region"}" -SnapshotDir "{parameter "SWPDir"}\roleref" -SQLDir "{parameter "SQLiteDir"}" -DatabasePath "{parameter "TargetStore"}"
```

Because `sha1:` and `size:` change every publish, **`Publish-RoleSnapshot.ps1` must re-`PUT`
the per-region policy Fixlet each run** with the fresh values (it holds the `.sha1` manifest it
just wrote). This is the single most important operational detail of 07-02.

### Pattern 6 — console-user detection, two paths

```powershell
# Reconcile-LocalRoles.ps1
param([string]$ConsoleUser, [string]$Region, [string]$SnapshotDir, [string]$SQLDir, [string]$DatabasePath)

if ([string]::IsNullOrWhiteSpace($ConsoleUser)) {
    # logon-task path: RoleDB_Maintenance runs as SYSTEM, no BigFix relevance engine.
    # Same query Initialize-RoleDb.ps1 already uses — operator has confirmed this equals
    # `name of current user` (bare lower-cased sAMAccountName).
    $ConsoleUser = (Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" |
        Invoke-CimMethod -MethodName GetOwner |
        Select-Object -ExpandProperty User -First 1)
    if ($ConsoleUser) { $ConsoleUser = $ConsoleUser.Split('\')[-1].ToLower() }
}
if (-not $ConsoleUser) { Write-Host "[SKIP] no console user"; return }
```

### Pattern 7 — AKeyless universal-identity wrapper

```powershell
# Get-BigFixCredential.ps1  [CITED: G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1]
param(
  [string]$TokenFile   = (Get-PipelineConfig 'AKeylessTokenFile'),   # ...\BES Client\EC\Cyera\.vault-token
  [string]$SecretPath  = (Get-PipelineConfig 'AKeylessSecretPath'),  # /gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator
  [string]$UserName    = (Get-PipelineConfig 'BESOperatorUser')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $TokenFile)) { throw "AKeyless token file missing: $TokenFile (Cyera rotator not run?)" }
$uid  = (Get-Content -Path $TokenFile).ToString().Trim()
$auth = Invoke-RestMethod -Method POST -Uri 'https://api.akeyless.io/auth' -ContentType 'application/json' `
        -Body (@{ 'access-type'='universal_identity'; 'uid-token'=$uid } | ConvertTo-Json)
if ([string]::IsNullOrEmpty($auth.token)) { throw 'AKeyless UID auth returned no token' }
$resp = Invoke-RestMethod -Method POST -Uri 'https://api.akeyless.io/get-secret-value' -ContentType 'application/json' `
        -Body (@{ names=@($SecretPath); token=$auth.token } | ConvertTo-Json)
$pw = $resp.$SecretPath
if ([string]::IsNullOrEmpty($pw)) { throw "AKeyless returned empty secret for $SecretPath" }
[pscredential]::new($UserName, (ConvertTo-SecureString $pw -AsPlainText -Force))
```

Failure modes to handle + log (Event 8000–8099): token file missing/stale (Cyera's rotator
runs ~2-hourly and is the **only** writer of `.vault-token` — RoleSync must only read it);
egress to `api.akeyless.io` blocked; wrong `SecretPath` → empty value; clock skew rejecting the
UID token. Never write `$pw` to disk, a log, or `PipelineConfig`.

### Pattern 8 — OJO IE9 constraints + tab switch (`fixlet_role_admin.ojo`)

```javascript
// [VERIFIED: codebase fixlet_console.ojo line 322, fixlet_role_assigner.ojo lines 40-110]
// var only; function declarations only; NO let/const/=>/`template`/Array.forEach
// Msxml2.DOMDocument.6.0 for XML; API.Get/API.Post/API.Put for REST
// GetRelevance() for Analysis reads; EvaluateRelevance() for live session relevance
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
// btoa polyfill, htmlEscape, xmlEscape, cdataStart/End, xmlCDataSafe, safeB64Encode,
// chunkString, CHUNK_SIZE=3000, buildChunkParams  -> lift verbatim from fixlet_role_assigner.ojo
```

Shared with `fixlet_role_assigner.ojo`: the base64-chunk chain, `loadGroups()` via
`EvaluateRelevance`, the Analysis read (`GetRelevance` on `Dereso SWD.bes` properties), the
SingleAction XML builder (for GroupRoleMap writes: a SingleAction targeted at the root-server
BES client that runs an embedded PS snippet doing `Invoke-SqliteCommand` against
`AutomationState.db`), and every XML/HTML-escaping helper.

### Pattern 9 — content pipeline (07-03, unchanged) — key idioms to port to PS

```powershell
function Strip-Version($name){ [regex]::Replace($name, ' v\d[\d.]+', '') }   # fixlet_update_tracker.ojo line 987
# plural vs singular: POST list = fixlets/custom/<site> ; GET/PUT one = fixlet|task/custom/<site>/<id>
$pathType = if ($item.IsTask) { 'task' } else { 'fixlet' }                    # bigfix-relevance skill §7 / stale Pitfall 1
# X-Superseded-By stamp: strip any existing MIMEField first (idempotent), then PUT   # fixlet_update_tracker.ojo buildSupersededXml
# prefetch parse (Stage-Repository.ps1):
$rx = [regex]'^(?:prefetch\s+)?(\S+)\s+sha1:([0-9a-fA-F]+)\s+size:(\d+)\s+(\S+)(?:\s+sha256:([0-9a-fA-F]+))?'
# on-disk target: {wwwRootFolder}\Uploads\CustomRepository\SoftwarePortal\<sha1-lowercase>\<file>
#   wwwRootFolder = (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server').wwwRootFolder
# task chaining: end Invoke-ContentSync.ps1 with Start-ScheduledTask -TaskName '<RepoStage task>'
```

### Anti-patterns to avoid

- **`INSERT OR REPLACE`** anywhere near `Map` / `UserRole` / `ContentItem` — destroys non-key state. (`Initialize-RoleDb.ps1` line 225 still uses it for the `Users` table only, where it is acceptable because `Users` has just `UserID`+`LastSeen`; do NOT copy that idiom to any table with state columns.)
- **Two result-returning statements in one `Invoke-SqliteCommand`** — WR-02 throws. Split reads.
- **`New-Object System.IO.StreamReader` / `[System.IO.File]::OpenText()`** — CLM-blocked. Use `Import-Csv` / `Get-Content -ReadCount` / `switch -File`.
- **Doubling `}`→`}}`** in embedded PowerShell — only `{`→`{{` (`bigfix-relevance` skill §2). `s.replace(/\{/g,"{{")` and nothing else.
- **Touching intentional `{...}` relevance substitutions** (`{parameter "X"}`, `{name of current user}`, `{value of setting …}`) with the brace-escape pass.
- **`SourcedFixletAction` for a dynamic group** — evaluates `<CustomRelevance>` server-side → 0 computers. Use a Fixlet/`SingleAction` (client-side relevance). The per-region policy action is a Fixlet, so this is naturally satisfied.
- **`<Target>` before `<Settings>`** in SingleAction XML → 400. Order: Title → Relevance → ActionScript → [SuccessCriteria] → Settings → … → Target → [MIMEFieldSingleAction].
- **`ConvertTo-Json` without `-Compress`** for REST bodies / snapshots — inserts newlines into long strings → 400.
- **Hard-coding the BES web root** — derive from `HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server` → `wwwRootFolder`.
- **Saving `.ojo` files from VS Code** while Claude has them open (`ojo-file-safety` memory) — a past incident overwrote one with error text.
- **Letting RoleSync rotate `.vault-token`** — only the Cyera rotator writes it.
- **`{id of computer}`** for a client ID — it's `{computer id}` (but D-02 means no computer id is used at all in the role pipeline).

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| RFC-4180 CSV parsing (quoted embedded newlines, BOM) | A `StreamReader` split-on-`\n` loop | `Import-Csv \| ForEach-Object` (no result collection) | The Axonius multi-valued cells contain literal newlines **inside quotes**; a line-based reader shreds every such row. `Import-Csv` is a correct RFC-4180 parser and streams. |
| SQLite access from PS | `sqlite3.exe` invocation / `System.Data.SQLite` + `Add-Type` | `Sqlite-Helper.ps1` (`Invoke-SqliteCommand`) | Injection-safe, busy-timeout, JSON mode, `__hex` decode, CLM-safe — solved. |
| SQL string escaping for batch INSERT | Manual quote doubling | `ConvertTo-SqliteLiteral` (exported by the helper) | Same escaping surface the parameterised path uses — one implementation. |
| SHA1 of a file | Hash loop | `Get-FileHash -Algorithm SHA1` | Built-in, correct. |
| Base64 + chunking for a SingleAction payload | New encoder | `safeB64Encode` + `chunkString` + `CHUNK_SIZE=3000` from `fixlet_role_assigner.ojo` | Byte-compatible with the endpoint reassembly already deployed. |
| Prefetch URL rewrite | New regex | `rewritePrefetchUrls()` from `fixlet_dispatcher.ojo` (and the on-disk path from `Invoke-PrefetchStage.ps1`) | Proven in Phase 3 UAT; the endpoint download manager already understands this exact URL shape. |
| Version compare in the content diff | Semver parser | `stripVersion` (`/ v\d[\d.]+/g`) + `extractVersion` from `fixlet_update_tracker.ojo` | Matches how the dashboard already keys products, so the pipeline and the dashboard agree. |
| GroupRoleMap wildcard match | Full glob engine | `EndsWith('*')` + `StartsWith(prefix)` NOCASE, plus exact NOCASE | Spec is `*`-suffix only (D-08). `Match_On` selects which field (`cn` extracted from `CN=…` in a DN / `display` / raw `dn`). |
| Scheduled Task XML | Hand-written XML | `Register-ScheduledTask` + `schtasks /Query …/XML` export | Task XML is version-sensitive; the `RoleDB_Maintenance` registration is the working template. |
| JSON log | String concat | `ConvertTo-Json -Depth 6` | Escaping + nesting handled. |
| Windows Event Log | ETW plumbing | `New-EventLog` once + `Write-EventLog` | Register source `DereseSoftwarePortal` in 07-00. |
| Credential storage | DPAPI file / plaintext `PipelineConfig` | `Get-BigFixCredential.ps1` → AKeyless (D-20) | No secret at rest; reuses an already-trusted identity. |
| Console-user identity | New WMI/session parsing | `{name of current user}` substitution (policy path) + the existing `explorer.exe`/`GetOwner` query (logon path) | Both already exist; operator has confirmed they produce the same bare lower-cased SAM. |

**Key insight:** the only genuinely new algorithm in Phase 7 is "stream a 400 MB CSV and resolve
entitlements without blowing memory". Everything else is an existing pattern moved to a new
trigger (a Scheduled Task instead of a button).

---

## Runtime State Inventory

Phase 7 renames the role datastore concept (`RoleReference.db` → combined `AutomationState.db`),
migrates the endpoint `Map` table, and changes a **published, live** BigFix task's behaviour.
A grep finds files; it does not find these.

| Category | Items found | Action required |
|----------|-------------|-----------------|
| **Stored data** | (1) Endpoint `RoleAwareness.db` on every managed client — `Map` table gains 4 columns (`Source_Type`, `Source_Value`, `Region`, `Assigned_By`). Existing rows are untouched; new columns are NULL until the next reconcile. (2) `AutomationState.db` on the root server does not exist yet — greenfield, created by `Initialize-AutomationDb.ps1`. (3) The old 2026-08-01 plan's `RoleAssignment` table concept is **dropped** — never built, nothing to migrate. | 07-00: add the `PRAGMA table_info(Map)`-gated `ALTER TABLE` block to `Initialize-RoleDb.ps1` (same mechanism as the existing `Updated_on`/`Valid_to` migration). **Code edit only** — no data migration; the reconcile back-fills the new columns for the console user over time (up to 24 h / next logon). |
| **Live service config** | **BigFix task 787** (`custom/Dereso Software Portal`, "Init  Current User and UserRole DB") — its **live Action1** still (a) wraps init in `if {not exists file (parameter "TargetStore")}` (the file-exists gate the repo already removed), (b) detects the user via `Get-CimInstance explorer.exe → GetOwner → Split('\')[-1].ToLower()` + `INSERT OR REPLACE INTO Users`, (c) registers `RoleDB_Maintenance` running the **old** `Initialize-RoleDb.ps1`. The repo copy is ahead of what is published. Also: the per-region policy Fixlets do not exist on the server yet. `RolePublication` seeding is hand-done (D-10). | 07-05: **redeploy task 787** (push the committed repo `.bes` up, replacing the live Action1) so the fleet runs the v3 script + the reconcile wiring. This is a real behavioural change (file-exists gate removed; `RoleDB_Maintenance` now also runs `Reconcile-LocalRoles.ps1`). API `PUT` via `POST/PUT /api/task/custom/...`. Manual/human-verify checkpoint. |
| **OS-registered state** | `RoleDB_Maintenance` Windows Scheduled Task on every endpoint (registered `-AtLogOn`, SYSTEM, runs `Initialize-RoleDb.ps1`). Its **action command line** hard-codes the script path + args — extending it to also run `Reconcile-LocalRoles.ps1` means the registration must be rewritten, not just the script. New root-server Scheduled Tasks for ingest / publish / content-sync / repo-stage do not exist yet. | 07-00/07-02: update `Init  Current User and UserRole DB.bes` so the `Scheduled_RoleDb_mnc.ps1` it writes registers a task that runs **both** scripts (or a small wrapper). Registration stays gated on "task doesn't already exist" — so 07-05 redeploy must **also** delete + re-register `RoleDB_Maintenance` on already-provisioned endpoints (add an `Unregister-ScheduledTask` before the guarded re-register, or bump a version marker). New root tasks: `Register-AutomationTasks.ps1` + exported XML. |
| **Secrets / env vars** | AKeyless: `.vault-token` at `…\BES Client\EC\Cyera\.vault-token` — **Cyera's**, reused as-is, not renamed, not re-provisioned. `PipelineConfig.AKeylessSecretPath` = `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` — **assumed correct; may not exist yet in AKeyless**. `BESOperatorUser` for the operator service account — not yet chosen. No `.env` files. | 07-00: seed the two AKeyless keys into `PipelineConfig`; `Get-BigFixCredential.ps1` fails loud if the secret path returns empty. 07-05: operator confirms/creates the AKeyless secret + the BigFix operator account with the right site/computer scope; confirm egress to `api.akeyless.io`. |
| **Build artifacts / installed packages** | `sqlite3.exe` is **not** on the root server at a known path yet (only prefetched to endpoints). `role_db/` is an untracked local scratch folder kept in sync with `Dashboard_4_samples/` — has its own test `RoleAwareness.db` (+ `-wal`). Uncommitted logon-rework is on branch `260813-fjc-fixlet-console` (working tree only). | 07-00: provision/verify `sqlite3.exe` at `PipelineConfig.SQLDir` on the root server (download the pinned zip from the BES `sqlite_util` CustomRepository URL, verify sha1 `184d4d0b…`, unzip); `Initialize-AutomationDb.ps1` exits with a clear error if absent. 07-00: **commit the logon-rework** under Phase 7 (D-18) before large new edits — copying just a `.db` without its `-wal` silently drops rows, so tests must checkpoint first. `role_db/` stays untracked. |

**Nothing found — verified:** No ChromaDB / Mem0 / Redis / n8n / Datadog / Tailscale / pm2 /
launchd state references the renamed concept — the role datastore has only ever been SQLite
files (`RoleAwareness.db` on endpoints, the to-be-created `AutomationState.db` on the root
server). No CI/CD pipeline touches this repo (single-dev, local git). No Docker.

---

## Common Pitfalls

### Pitfall 1 — quoted embedded newlines in the Axonius multi-valued cells
**What goes wrong:** a line-based reader (`StreamReader.ReadLine()`, `Get-Content`, `switch -File`)
splits one logical user record across dozens of physical lines, because
`"Aggregated: Assigned Groups: Display Name"` (and siblings) hold `"val1\nval2\nval3"` **inside
one quoted field**. Every downstream count is then wrong and roles are assigned to fragments.
**Why:** RFC-4180 allows `CR`/`LF` inside quotes; Axonius uses it heavily for list columns.
**Avoid:** `Import-Csv` (correct RFC-4180 parser, streams via the pipeline). If profiling forces
a `StreamReader`, the parser must be a quote-state machine, and it must be unit-tested against
`fixtures/phase-07/axonious-multivalue-edge.csv`.
**Warning signs:** `SyncRun.Rows_In` far exceeds the known user count; `UserRole` rows with a
`Source_Value` that is a fragment of a DN.

### Pitfall 2 — `name of current user` may not be the console user
**What goes wrong:** the BigFix client runs as SYSTEM; in some versions/configs
`name of current user` (client relevance) returns the client's own account or empty, not the
interactive user. D-04/D-14 assume it equals the console user's bare lower-cased SAM.
**Why:** "current user" ≠ "logged on user" in BigFix; the existing role relevance in
`fixlet_modifier.ojo` deliberately uses the plural `names of logged on users as lowercase`.
**Avoid:** 07-05 live spot-check on the production fleet (the 9-box lab is not
representative). If it returns SYSTEM/blank, switch the ActionScript substitution to
`name of logged on user` (singular) or `item 0 of (names of logged on users)`, and adjust the
reconcile accordingly. Keep this behind one config point so the switch is one line.
**Warning signs:** `Reconcile-LocalRoles.ps1` logs `[SKIP] no console user` on machines that
clearly have someone logged in; `Map` rows never gain `Assigned_By='AxoniousSync'`.

### Pitfall 3 — the policy Fixlet's prefetch `sha1:` goes stale every publish
**What goes wrong:** the snapshot file is regenerated daily with a new hash; the policy Fixlet's
`prefetch` line still names yesterday's `sha1:`/`size:` → the download fails and no endpoint
reconciles.
**Why:** BigFix verifies prefetch hashes; a fixed hash in a Fixlet cannot track a
daily-changing file.
**Avoid:** `Publish-RoleSnapshot.ps1` re-`PUT`s each published region's policy Fixlet every run
with the fresh `sha1:`/`size:` (and dated filename) from the `.sha1` manifest it just wrote.
Alternatively (documented fallback) drop BigFix prefetch and have `Reconcile-LocalRoles.ps1`
`Invoke-WebRequest` the `…latest.json` directly from the relay.
**Warning signs:** endpoint client logs show "download failed / hash mismatch" for
`roleref-*.json`; `Snapshot.Status='published'` but no `Map` changes anywhere.

### Pitfall 4 — `127.0.0.1:52311` prefetch URL on a non-root endpoint
**What goes wrong:** `rewritePrefetchUrls()` emits `http://127.0.0.1:52311/…`. On the root
server that is the web root; on a normal endpoint `127.0.0.1` is the endpoint itself.
**Why:** this pattern is proven for the Dispatcher (Phase 3 UAT) but that context stages files
on the **root server**; the per-region snapshot must reach **every endpoint**.
**Avoid:** verify in 07-05 whether the BES client's download manager special-cases this URL to
mean "fetch from my parent relay's server root" (it may — this is why the Dispatcher pattern
works fleet-wide). If not, use the relay-qualified URL
(`http://{relay}:52311/Uploads/CustomRepository/SoftwarePortal/roleref/…`) or the direct
`Invoke-WebRequest` fallback from Pitfall 3.
**Warning signs:** reconcile works only on the root server / relays, nowhere else.

### Pitfall 5 — `RoleDB_Maintenance` re-registration is gated on "not exists"
**What goes wrong:** `Init  Current User and UserRole DB.bes` only registers the task
`if {not (exists (scheduled tasks whose (name of it = "RoleDB_Maintenance")))}`. Every real
endpoint already has it → redeploying the updated `.bes` (D-19: also run `Reconcile-LocalRoles.ps1`)
does **not** update the task's command line.
**Why:** the guard was correct when the task never changed; D-19 changes it.
**Avoid:** in the updated `.bes`, `Unregister-ScheduledTask -TaskName RoleDB_Maintenance -Confirm:$false`
(ignore-not-found) immediately before the guarded re-register, or gate on a version marker file.
**Warning signs:** after 07-05 redeploy, logon still only runs `Initialize-RoleDb.ps1`, never
the reconcile.

### Pitfall 6 — per-row `sqlite3.exe` spawn on a 10k-user ingest
**What goes wrong:** one `Invoke-SqliteCommand` per `UserRole` row = tens of thousands of
process starts; the ingest takes many minutes and hammers the root server.
**Avoid:** Pattern 2 — batch 200–500 rows per `BEGIN;…COMMIT;` call via `ConvertTo-SqliteLiteral`.
**Warning signs:** ingest wall-clock in the tens of minutes; `sqlite3.exe` churn in Process
Monitor.

### Pitfall 7 — Event Log source not registered
**What goes wrong:** `Write-EventLog -Source "DereseSoftwarePortal"` throws "source is not
registered" on the first failure — so failures are also invisible.
**Avoid:** 07-00 `Initialize-AutomationDb.ps1`:
`if (-not [System.Diagnostics.EventLog]::SourceExists("DereseSoftwarePortal")) { New-EventLog -LogName Application -Source "DereseSoftwarePortal" }` (needs admin, once).
**Warning signs:** scheduled runs fail silently; nothing in Application log.

### Pitfall 8 — dashboard cannot open `AutomationState.db` directly
**What goes wrong:** an OJO dashboard runs in the console, not on the server; it can only make
BigFix API calls. The Reference-DB tab shows "no data".
**Avoid:** read via a `Dereso SWD.bes` Analysis property whose body is **client relevance** on
the root-server BES client (client relevance can read files), surfaced through `GetRelevance`.
Provide a REST/`EvaluateRelevance` fallback. Requires the root server to be an enrolled managed
client (standard, but confirm in 07-05).
**Warning signs:** Reference-DB tab empty while `SyncRun` clearly has rows on disk.

### Pitfall 9 — `Import-Csv` memory blow-up from accidental collection
**What goes wrong:** `$rows = Import-Csv big.csv` (or `Import-Csv … | Where-Object …` assigned to
a variable) materialises the whole 400 MB file as ~hundreds of MB of `PSCustomObject`s.
**Avoid:** keep it in a single pipeline: `Import-Csv … | ForEach-Object { … }` with no
assignment and no `Select-Object` buffering; flush SQLite batches inside the loop.
**Warning signs:** `powershell.exe` working set climbing past ~1 GB during ingest.

### Pitfall 10 — DN vs display-name detection in `GroupRoleMap`
**What goes wrong:** a rule with `Match_On='cn'` is tested against a raw display name
(`All Tenant Members`) or vice-versa, so nothing matches.
**Avoid:** derive all three views per group value up front — `dn` = the raw string;
`cn` = first `CN=` RDN if the string looks like a DN (`^CN=`), else the raw string;
`display` = the value from `Assigned Groups: Display Name` aligned to that group (best-effort
per D-07, not index-zipped). Match each active rule against the view named by its `Match_On`.
**Warning signs:** users with obviously-matching groups get zero roles; `SyncRun.Entitlements`
near zero on a real run.

### Pitfall 11 — brace escaping when embedding `Reconcile-LocalRoles.ps1` in the `.bes`
**What goes wrong:** the script's `if`/`foreach`/`try`/hashtable braces collide with
ActionScript `{...}` substitution; over-correcting by doubling `}` leaves stray `}}`.
**Avoid:** `s.replace(/\{/g, "{{")` and nothing else (`bigfix-relevance` skill §2); leave
`{parameter "X"}` / `{name of current user}` / `{value of setting …}` untouched. Or prefetch the
`.ps1` as a file resource and skip escaping entirely. Verify by extracting the script back out
of the `.bes` and running it, as the logon-rework work did.

### Pitfall 12 — `.beswrpt`/Analysis stale reads during rollout
**What goes wrong:** `Dereso SWD.bes` properties evaluate every 5 min; a freshly-reconciled
`Map` change isn't visible in the dashboard for minutes, and a redeployed Analysis re-baselines.
**Avoid:** document the lag in the run-book; in the dashboards show the Analysis
`<last reported>` time next to counts so operators aren't misled during per-region enablement.

---

## Code Examples

### `AutomationState.db` — role tables (from DESIGN.md §"Database designs A", house style preserved)

```sql
-- [CITED: .planning/quick/260828-fjc-role-reference-db/DESIGN.md]  CREATE TABLE IF NOT EXISTS throughout
CREATE TABLE IF NOT EXISTS Role (
  RoleID INTEGER PRIMARY KEY AUTOINCREMENT,
  Role TEXT NOT NULL UNIQUE COLLATE NOCASE,
  Description TEXT, Active INTEGER NOT NULL DEFAULT 1,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')));

CREATE TABLE IF NOT EXISTS Region (
  RegionID INTEGER PRIMARY KEY AUTOINCREMENT,
  GPC_Sub_Name TEXT NOT NULL UNIQUE COLLATE NOCASE,   -- must equal the endpoint client-setting value
  Description TEXT, Active INTEGER NOT NULL DEFAULT 1,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')));
-- seed: UAP, MOT, APAC, APAC-MOT, APAC-M&A, AAG-DE, AAG-FR, AAG-UK, AAG-ES, AAG-BLX, AAG-PL, AAG-PT, GPC

CREATE TABLE IF NOT EXISTS GroupRoleMap (
  GRMID INTEGER PRIMARY KEY AUTOINCREMENT,
  Pattern TEXT NOT NULL, Match_On TEXT NOT NULL DEFAULT 'cn',   -- cn | display | dn
  Role TEXT NOT NULL COLLATE NOCASE, Priority INTEGER NOT NULL DEFAULT 100,
  Active INTEGER NOT NULL DEFAULT 1, Notes TEXT, Created_by TEXT,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')), Updated_on TEXT);
CREATE INDEX IF NOT EXISTS idx_grm_active ON GroupRoleMap (Active, Role);

CREATE TABLE IF NOT EXISTS RefUser (
  RefUserID INTEGER PRIMARY KEY AUTOINCREMENT,
  UserID TEXT NOT NULL UNIQUE COLLATE NOCASE,          -- normalised lowercased match key
  SamAccount TEXT, Upn TEXT, Display_Name TEXT, Domain TEXT,
  Username_Src TEXT NOT NULL,                          -- sam | upn | username
  RegionID INTEGER REFERENCES Region(RegionID),        -- reporting only, operator-set later
  First_Seen TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_Seen  TEXT NOT NULL DEFAULT (datetime('now','localtime')), Last_RunID TEXT);

CREATE TABLE IF NOT EXISTS UserRole (
  URID INTEGER PRIMARY KEY AUTOINCREMENT,
  UserID TEXT NOT NULL COLLATE NOCASE, Role TEXT NOT NULL COLLATE NOCASE,
  Source_Type TEXT NOT NULL, Source_Value TEXT NOT NULL, Source_System TEXT,
  Matched_Rule INTEGER REFERENCES GroupRoleMap(GRMID),
  Active INTEGER NOT NULL DEFAULT 1,                   -- 0 = not in latest export (age-out; row kept)
  First_Seen TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  Last_Seen  TEXT NOT NULL DEFAULT (datetime('now','localtime')), Last_RunID TEXT,
  UNIQUE (UserID, Role, Source_Value));
CREATE INDEX IF NOT EXISTS idx_userrole_role ON UserRole (Role, Active);
CREATE INDEX IF NOT EXISTS idx_userrole_user ON UserRole (UserID, Active);

CREATE TABLE IF NOT EXISTS RolePublication (
  RPID INTEGER PRIMARY KEY AUTOINCREMENT,
  Role TEXT NOT NULL COLLATE NOCASE,
  RegionID INTEGER REFERENCES Region(RegionID),        -- NULL = all regions
  Active INTEGER NOT NULL DEFAULT 1, Created_by TEXT,
  Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  UNIQUE (Role, RegionID));

CREATE TABLE IF NOT EXISTS Snapshot (
  SnapshotID INTEGER PRIMARY KEY AUTOINCREMENT, RunID TEXT NOT NULL,
  Built_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
  File_Name TEXT NOT NULL, SHA1 TEXT NOT NULL, Size_Bytes INTEGER,
  Role_Count INTEGER, User_Count INTEGER, Region TEXT,
  Status TEXT NOT NULL DEFAULT 'built');               -- built | published | failed

CREATE TABLE IF NOT EXISTS SyncRun (
  RunID TEXT PRIMARY KEY, Type TEXT NOT NULL,          -- Ingest | Publish | ContentSync | RepoStage
  Started_on TEXT NOT NULL DEFAULT (datetime('now','localtime')), Ended_on TEXT,
  Status TEXT NOT NULL DEFAULT 'running',              -- running | success | partial | failed
  Rows_In INTEGER, Users_Seen INTEGER, Roles_Seen INTEGER, Entitlements INTEGER,
  Items_Discovered INTEGER, Items_Copied INTEGER, Items_Failed INTEGER,  -- content-only, nullable
  Summary TEXT, Error_Count INTEGER NOT NULL DEFAULT 0);

CREATE TABLE IF NOT EXISTS PipelineConfig (
  Key TEXT PRIMARY KEY, Value TEXT, Description TEXT);
```

### `AutomationState.db` — content tables (old D-05, names per D-01)

```sql
CREATE TABLE IF NOT EXISTS ContentItem (
  fixlet_id TEXT NOT NULL, source_site TEXT NOT NULL, fixlet_name TEXT NOT NULL,
  stage TEXT NOT NULL DEFAULT 'discovered',            -- discovered|staged|categorized|ready|live|rejected
  category TEXT, roles TEXT, is_task INTEGER NOT NULL DEFAULT 0,
  copied_at TEXT, dispatched_at TEXT,
  PRIMARY KEY (fixlet_id, source_site));

CREATE TABLE IF NOT EXISTS ContentCache (
  sha1 TEXT PRIMARY KEY, filename TEXT NOT NULL, original_url TEXT,
  staged_at TEXT, size_bytes INTEGER, verified INTEGER NOT NULL DEFAULT 0);
```

### Endpoint `Map` migration (add to the existing `PRAGMA table_info(Map)` block in `Initialize-RoleDb.ps1`)

```powershell
# [VERIFIED: codebase Initialize-RoleDb.ps1 lines 158-187 — identical mechanism to Updated_on/Valid_to]
$mapCols = @((Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "PRAGMA table_info(Map)") | ForEach-Object { $_.name })
foreach ($c in 'Source_Type','Source_Value','Region','Assigned_By') {
  if ($mapCols -notcontains $c) {
    Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql "ALTER TABLE Map ADD COLUMN $c TEXT" | Out-Null
    Add-Content -Path $logfile -Value "[MIGRATE] Map.$c column added"
  }
}
```

### Per-region snapshot JSON (derived — not a table)

```json
{ "run_id": "b1c2…", "region": "AAG-UK", "built_on": "2026-08-29T04:07:00Z",
  "validity_months": 6,
  "roles": [ { "role": "IT Operations", "users": ["jsmith","adavis"] },
             { "role": "General Access", "users": ["jsmith","adavis","bwong", "..."] } ] }
```
`users` = `SELECT DISTINCT ur.UserID FROM UserRole ur WHERE ur.Active=1 AND ur.Role=@role` filtered
to roles where `(role, region)` is `Active` in `RolePublication` (RegionID match OR RegionID NULL).

### Snapshot write + manifest (`switch -File` is safe here — tiny file, no quoted newlines)

```powershell
$json = $snapshot | ConvertTo-Json -Depth 6 -Compress
$dated  = Join-Path $roleRefDir "roleref-$region-$(Get-Date -Format yyyyMMdd).json"
$latest = Join-Path $roleRefDir "roleref-$region-latest.json"
[System.IO.File]::WriteAllText($dated, $json)          # if CLM permits; else Set-Content -Encoding UTF8 -NoNewline
Copy-Item $dated $latest -Force
$sha1 = (Get-FileHash -Algorithm SHA1 -Path $latest).Hash.ToLower()
Set-Content -Path "$latest.sha1" -Value "$sha1  $(Split-Path $latest -Leaf)" -Encoding ASCII
# then: PUT the per-region policy Fixlet with prefetch line "prefetch <leaf> sha1:$sha1 size:<len> http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/<leaf>"
```

### `Dereso SWD.bes` — 2 new properties (07-04)

```
<Property Name="map_source in r.db" ID="5" EvaluationPeriod="PT5M">
 (following text of first "%22" of tuple string item 0 of it, preceding text of first "%22" of tuple string item 1 of it)
 of ((((rows of statement "select UserID || ', ' || Role || ', ' || coalesce(Source_Value,'') from map where Active = 1" of it) as string))
 of sqlite database of file "RoleAwareness.db" of folder it)
 of ((concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it)
 of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal"))))
</Property>
<!-- map_region in r.db: identical, "coalesce(Region,'')" -->
```

---

## State of the Art

| Old approach (2026-08-01 Phase 7) | Current approach (2026-08-29 rewrite) | Impact |
|---|---|---|
| Daily Axonius export → resolve users to BigFix ComputerIDs (`POST /api/query` for logged-on users) → per-role `SingleAction` with `<Target>` ComputerID lists | Reference DB → per-region snapshot JSON in the Custom Repository → one per-region policy Fixlet gated on `GPC_Sub_Name` → endpoint reconcile | Role follows the **user**, not the machine. No `Get-UserComputerMap.ps1`, no matrix, no per-role actions. 24 h propagation is acceptable. |
| `RoleReference.db` (separate) | One combined `AutomationState.db` (role + content) | One init script, one logging table, one dashboard read path. |
| `BESOperatorPasswordEncrypted` via DPAPI `ConvertFrom-SecureString` | `Get-BigFixCredential.ps1` → AKeyless universal identity, reusing Cyera's `.vault-token` | No secret at rest; the DPAPI decision is dead. |
| Endpoint user detection: `explorer.exe`/`GetOwner()` (bare SAM) | Client relevance `name of current user` (lower-cased), with the `explorer.exe` query only as the logon-task-path fallback | One join key end-to-end; **pending 07-05 confirmation that `name of current user` really is the console user on the production fleet.** |
| One `fixlet_automation_monitor.ojo` with a Role tab + GroupRoleMap editor | `fixlet_role_admin.ojo` (role config) + `fixlet_automation_monitor.ojo` (content only) + `fixlet_role_assigner.ojo` demoted to break-glass | Clear separation; the monitor no longer touches role data. |
| 5 plans (Wave 0–4) | 6 plans (Wave 0–5); old `07-02/03/04` renumber (none executed) | Publish+distribute+reconcile is its own wave; rollout is its own wave with a human-verify checkpoint. |

**Deprecated / do not carry forward from the stale files:** `Parse-AxoniousExport.ps1`,
`Get-UserComputerMap.ps1`, `Invoke-RoleSync.ps1`, the `RoleAssignment` table, `CacheEntry`,
`Set-BESCredential.ps1` / DPAPI, `Dereso SWD Automation.bes`, D-01 (fixed CSV column names
`username,AD_Groups,Mailing_Groups`), D-04 (`POST /api/query` user→computer), the 5-plan shape,
and every "per-role `SingleAction`" reference in the old 07-RESEARCH Patterns 4–5 & Pitfall 8.

---

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|-------|---------|---------------|
| A1 | `name of current user` (client relevance) returns the interactive console user's bare lower-cased sAMAccountName, equal to the ingest match key | D-04/D-14, Pitfall 2 | The whole reconcile assigns nothing (or assigns to SYSTEM). Mitigation: 07-05 live spot-check; one-line switch to `names of logged on users`. **Operator asserted this; not verified in-session — the 9-box MCP lab can't confirm it representatively.** |
| A2 | The BES client download manager resolves `http://127.0.0.1:52311/Uploads/CustomRepository/...` to the parent relay's server root on **every** endpoint, not just the root server | Pattern 5, Pitfall 4 | Per-region snapshot never reaches endpoints. Mitigation: relay-qualified URL or `Invoke-WebRequest` fallback; 07-05 verifies. The Dispatcher uses this shape and passed Phase 3 UAT, but that staged files on the root server. |
| A3 | The BigFix root server is an enrolled managed BES client (so a `Dereso SWD.bes` Analysis can read `AutomationState.db` and dashboards can `GetRelevance` it) | Pitfall 8, dashboards | Reference-DB tab + monitor Status tab have no data source; fall back to REST reads of JSON log files in a web-served path. |
| A4 | `AKeylessSecretPath = /gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` exists (or will be created) and the reused Cyera universal identity is authorised to read it | D-20, Pattern 7, Runtime State | Every root-server script fails at credential fetch. Mitigation: `Get-BigFixCredential.ps1` throws loud; 07-05 operator confirms/creates the secret + operator account scope. |
| A5 | `pwsh.exe` 7.x is present on the production BES root server (verified only on the dev host) | Standard Stack | `-SkipCertificateCheck` unavailable → fall back to a PS5.1 `ServicePointManager` cert callback (which is `Add-Type`-ish and messy) or install PS7. |
| A6 | The BigFix REST API returns `{ "result": [...] }` JSON for `POST /api/query` and standard XML for `GET /api/fixlets/...` | content pipeline | Response-parsing code needs adjustment. Low risk — matches every existing OJO call. |
| A7 | `Import-Csv` on PS 5.1 completes the 400 MB export in an operationally acceptable time (single-digit minutes) | Standard Stack, Pitfall 1/9 | If too slow, need a tested quote-state-machine `StreamReader` parser (and confirmation the root server is non-CLM). Profile against the real file in 07-01. |
| A8 | `Import-Csv` reads a BOM-prefixed UTF-8 file correctly on PS 5.1 without an explicit `-Encoding` | Pattern 2 | Garbled first header (`"Aggregated: Adapter Connections"`), so `$row.'Aggregated: Adapter Connections'` is `$null`. Mitigation: strip the BOM from the first line, or pass `-Encoding UTF8`, and assert the column map in task (a) of 07-01. |
| A9 | A single region's snapshot (largest role ≈ "General Access" ≈ ~10k users) is small enough to prefetch/GET cheaply per endpoint (~100–300 KB compressed JSON) | D-11, distribution | If a role list is far larger, revisit compression / per-role file split. Bounded by ~10k users per DESIGN. |
| A10 | `wwwRootFolder` registry value + `\Uploads\CustomRepository\SoftwarePortal` resolves to the same directory as DESIGN's `{DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal` | Pattern 9, D-11 | Snapshot written where nothing serves it. Mitigation: `Publish-RoleSnapshot.ps1` derives the path from the registry (as `Invoke-PrefetchStage.ps1` does), not from a hard-coded `DataDirectory`; `SnapshotOutputDir` in `PipelineConfig` is an override, not the default. |

---

## Open Questions

1. **`name of current user` semantics on the production fleet** — see A1. *Recommendation:* make it a blocking item in 07-05 before any region goes live; wire the substitution behind `PipelineConfig`-style one-liner so `names of logged on users` is a drop-in.
2. **Does `Publish-RoleSnapshot.ps1` edit the policy Fixlet, or does the operator?** *Recommendation:* the script re-`PUT`s the prefetch line every run (Pitfall 3); the operator only toggles the policy action on/off per region via `fixlet_role_admin.ojo` Region tab. Confirm the operator is comfortable with a script that mutates a published Fixlet daily.
3. **Freshness gate in v1** — Claude's discretion; recommended **include minimal** (Discretion Resolutions + Pattern 4). Confirm with the user; it is the only thing standing between "console user never logs off" and "roles silently expire in 6 months".
4. **Region seed vs live `GPC_Sub_Name` values** — the fixed 13-value list is operator-supplied but unverified against the fleet (client settings aren't exposed to session relevance without an Analysis). *Recommendation:* 07-05 adds a temporary `GPC_Sub_Name` retrieved property to spot-check spelling/case before enabling each region.
5. **`GroupRoleMap` first rule set** — explicitly deferred (go-live blocker, not a phase blocker). *Recommendation:* 07-01 ships a `grouprolemap-seed.json` with synthetic rules for tests + a helper query (`SELECT Source_Value, COUNT(*) FROM UserRole GROUP BY 1 ORDER BY 2 DESC`) so the operator can author real rules from the export's group frequency.
6. **PS7 on the root server** (A5) — confirm in 07-00's environment checklist.

---

## Environment Availability

| Dependency | Required by | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Node.js + `assert` | `fixlet_role_admin.ojo` unit tests | ✓ (dev host) | v24.15.0 | — |
| Pester | new `.ps1` unit tests | ✓ (dev host) | 5.7.1 (also 3.4.0 — pin `-MinimumVersion 5.0`) | Node `assert` harness shelling to `pwsh` |
| `pwsh.exe` (PS7) | root-server scripts (`-SkipCertificateCheck`) | ✓ dev host / ✗ production unconfirmed | 7.6.3 dev | PS5.1 + `ServicePointManager` cert callback, or install PS7 (A5) |
| PowerShell 5.1 | endpoint scripts | ✓ (Windows built-in) | 5.1 | — |
| `sqlite3.exe` on the **root server** | every root script via `Sqlite-Helper.ps1` | ✗ (only prefetched to endpoints) | needs 3.53.1 / sha1 `184d4d0b…` | 07-00 downloads the pinned zip from the BES `sqlite_util` CustomRepository URL, verifies sha1, unzips to `PipelineConfig.SQLDir`; init script errors clearly if absent |
| BigFix REST API `:52311` | content pipeline, `Publish-RoleSnapshot.ps1` fixlet PUT, dashboards | ✓ via MCP lab (9 boxes) / production = `gpbfs.esm-technology.com` | — | `-WhatIf` dry-run; BIGFIX-gated integration tests |
| AKeyless `api.akeyless.io` egress | `Get-BigFixCredential.ps1` | ? (Cyera integration on this host uses it — assume yes) | — | none — hard dependency; 07-05 confirms egress + secret path |
| Windows Scheduled Task cmdlets | task registration | ✓ | Windows 11 / Server | `schtasks.exe /Create /XML` |
| `SampleAxonious/axonius-users_anond.csv` + `axonious.db` | 07-00/07-01 fixtures + 07-01 profiling | ✓ | 420 MB CSV / 421 MB db, 47 cols, BOM, RFC-4180 | — |
| Production fleet (`gpbfs`, ~40k) | A1, A2, A4, region values | ✗ (MCP server is a 9-box lab) | — | **no fallback** — 07-05 items are genuinely blocked until run against production |

**Missing with no fallback:** AKeyless egress + the real secret path (A4); production-fleet
verification of A1/A2 and the region values. All are 07-05 concerns and are already scoped
there.
**Missing with fallback:** `sqlite3.exe` on the root server (07-00 provisions it); PS7 on the
root server (PS5.1 path); BigFix API in CI (`-WhatIf` + BIGFIX-gated tests).

---

## Validation Architecture

`workflow.nyquist_validation` is not `false` in `config.json` → this section is included.
Two test stacks: **Pester 5** for PowerShell, **Node `assert`** for the one new OJO.

### Test framework

| Property | PowerShell scripts | OJO dashboard |
|----------|--------------------|----------------|
| Framework | Pester 5.7.1 | Node.js built-in `assert` |
| Config file | none — `Invoke-Pester -Path tests/pester -Output Detailed` (pin `-MinimumVersion 5.0` on `Import-Module Pester`) | none — `node tests/unit/role_admin.test.js` |
| Quick run | `Invoke-Pester tests/pester/<one>.Tests.ps1` | `node tests/unit/role_admin.test.js` |
| Full suite | `node tests/unit/copier.test.js && … && node tests/unit/role_admin.test.js && pwsh -c "Invoke-Pester -Path tests/pester -CI"` | (same, combined) |

### Phase requirement → test map

| Req / decision | Behaviour under test | Type | Command | Exists? |
|---|---|---|---|---|
| D-05 / Pitfall 1 | `Import-Csv` streaming parses quoted embedded newlines; multi-value cells not index-zipped | Pester (fixture) | `Invoke-Pester tests/pester/Import-AxoniousExport.Tests.ps1` | ❌ Wave 0/1 |
| D-06 | username coalesce sam→upn-localpart→UserName, `.ToLower()`, `Username_Src` recorded | Pester | same | ❌ |
| D-08 / Pitfall 10 | `GroupRoleMap` exact NOCASE + `*`-suffix; `Match_On` cn/display/dn; all matches apply | Pester | `Invoke-Pester tests/pester/GroupRoleMap.Tests.ps1` | ❌ |
| D-09 | age-out sets `Active=0` for rows whose `Last_RunID` ≠ this run; row retained | Pester | `Import-AxoniousExport.Tests.ps1` | ❌ |
| D-11 | snapshot = DISTINCT `Active=1` users, filtered by `RolePublication`; `region` = one `GPC_Sub_Name`; `.sha1` matches file | Pester | `Invoke-Pester tests/pester/Publish-RoleSnapshot.Tests.ps1` | ❌ |
| D-12 (relevance) | region-gate + DB-guard + freshness string builds and is syntactically valid | Node assert (string builder) | `node tests/unit/role_admin.test.js` (or a Pester string test) | ❌ |
| D-12 (upsert) / D-03 | `INSERT OR IGNORE` + guarded `UPDATE`; `Locked_by_Override=1` row never modified; never `INSERT OR REPLACE`; new `Map` cols written; `INSERT OR IGNORE INTO Roles` for unknown role | Pester (temp `RoleAwareness.db`) | `Invoke-Pester tests/pester/Reconcile-LocalRoles.Tests.ps1` | ❌ |
| D-15 | reconcile ABORTS when `snapshot.region` ≠ `-Region` | Pester | same | ❌ |
| D-18 (Map migration) | `PRAGMA table_info`-gated `ALTER TABLE` adds 4 cols, idempotent, preserves rows | Pester (migrate a v2 fixture db) | `Invoke-Pester tests/pester/Initialize-RoleDb.Tests.ps1` | ❌ |
| D-20 | `Get-BigFixCredential.ps1` returns `[PSCredential]`; throws on missing token / empty secret; never logs the secret | Pester (mock `Invoke-RestMethod`) | `Invoke-Pester tests/pester/Get-BigFixCredential.Tests.ps1` | ❌ |
| FR-10 / D-09-content | `Strip-Version` = `fixlet_update_tracker.ojo` `stripVersion`; plural/singular REST path from `is_task` | Pester + Node parity | `Invoke-Pester tests/pester/Invoke-ContentSync.Tests.ps1` | ❌ |
| D-10-content | prefetch-line regex extracts sha1/size/url/sha256; on-disk path = `<wwwRootFolder>\Uploads\CustomRepository\SoftwarePortal\<sha1>\<file>` | Pester | `Invoke-Pester tests/pester/Stage-Repository.Tests.ps1` | ❌ |
| NFR-NEW | `-WhatIf` on every new script emits a JSON log + makes **zero** API calls / DB writes | Pester (assert mocks not invoked) | per-script `.Tests.ps1` | ❌ |
| D-22 | `fixlet_role_admin.ojo` pure fns: `switchTab`, GroupRoleMap row validate, "Test Pattern" matcher (JS mirror of the PS matcher), base64-chunk | Node assert | `node tests/unit/role_admin.test.js` | ❌ |
| Regression | all 7 existing OJO unit suites still green | Node assert | existing full suite | ✓ |

### Seams (where to cut for testability)

- `Invoke-SqliteCommand` — mock in Pester for pure-logic tests; use a real temp `.db` + real `sqlite3.exe` for upsert/migration tests (fast enough).
- `Invoke-RestMethod` / `Invoke-WebRequest` — mock for `Get-BigFixCredential`, `Publish-RoleSnapshot` (fixlet PUT), `Invoke-ContentSync`.
- Console-user detection in `Reconcile-LocalRoles.ps1` — `-ConsoleUser` param is the seam; tests pass it explicitly, never exercise the `explorer.exe` branch in CI.
- Snapshot builder — a pure function `Build-RegionSnapshot -Rows $userRoleRows -Publication $pub -Region $r` returning the PSObject, separate from file IO.
- GroupRoleMap matcher — pure function `Resolve-Roles -GroupViews @{cn=…;display=…;dn=…} -Rules $rows`.

### Fixture strategy

- Carve `axonious-sample-50.csv` from `SampleAxonious` (first N rows via `Import-Csv | Select -First 50 | Export-Csv`, then hand-add: a BOM, a row with blank SAM, a row with a quoted 3-line group cell, a DN group + a display-name group). Keep it < 50 KB so it lives in git.
- `axonious.db` / the full CSV stay **out of git** (420 MB) — used only for local 07-01 profiling (A7) and a `[Category=Slow]` Pester test skipped in CI.
- `roleref-AAG-UK-sample.json` — hand-written to the D-11 shape for reconcile tests.
- A v2-schema `RoleAwareness.db` fixture (Map without the 4 new cols) for the migration test — checkpoint the `-wal` before copying (logon-rework lesson).
- What needs the **production fleet** (cannot be faked): A1 (`name of current user`), A2 (`127.0.0.1` prefetch reach), live `GPC_Sub_Name` values, task 787 redeploy. All in 07-05, behind a `checkpoint:human-verify`.

### Sampling rate

- **Per task commit:** the one relevant `.Tests.ps1` or `node …/role_admin.test.js` (< 30 s).
- **Per wave merge:** full Pester run + all 8 Node suites.
- **Phase gate:** full suite green + the 07-05 human-verify checklist signed off before `/gsd:verify-work`.

### Wave 0 gaps (must exist before implementation)

- [ ] `tests/pester/` directory + a `PesterConfig` note pinning v5
- [ ] `tests/fixtures/phase-07/axonious-sample-50.csv`, `axonious-multivalue-edge.csv`
- [ ] `tests/fixtures/phase-07/grouprolemap-seed.json`
- [ ] `tests/fixtures/phase-07/roleref-AAG-UK-sample.json`
- [ ] `tests/fixtures/phase-07/automation-db-schema.sql` (full DDL for an in-memory test DB)
- [ ] `tests/fixtures/phase-07/roleawareness-v2.db` (pre-migration, `-wal` checkpointed)
- [ ] `tests/unit/role_admin.test.js` (stub + first assertions)
- [ ] confirm `sqlite3.exe` reachable from the test runner (`PesterConfig`/env var `SQLDIR`)

---

## Security Domain

`gates.security_gate = true` → included.

### Applicable ASVS categories

| ASVS category | Applies | Standard control for this phase |
|---|---|---|
| V2 Authentication | yes | BigFix operator credential fetched at runtime from AKeyless universal identity (`Get-BigFixCredential.ps1`); never at rest. `.vault-token` is Cyera's, read-only. |
| V3 Session Management | no | Batch scripts; no sessions. |
| V4 Access Control | yes | The BigFix operator account behind the AKeyless secret must be scoped to only the Dereso site + the target computer groups. GroupRoleMap edits go through a BigFix Console operator (SingleAction) or local admin on the root server — both existing trust boundaries. |
| V5 Input Validation | yes | Axonius CSV: assert the 47-column header before processing; every value goes through `ConvertTo-SqliteLiteral` (single-quote doubling) — the whole injection surface, verified sufficient in prior phases. Snapshot `region` must match a `Region.GPC_Sub_Name` row before a file is written. |
| V6 Cryptography | no | SHA1 here is BigFix file-integrity (prefetch manifest), not a security hash — a pre-existing BigFix spec requirement, not a choice. AKeyless TLS is a real CA cert (no bypass). |
| V7 Errors & Logging | yes | Per-run JSON log + `SyncRun`/`Snapshot` rows + Event Log 8000–8099 on failure = the NFR-NEW audit trail. Logs must never contain the operator password or the AKeyless token. |

### Known threat patterns for this stack

| Pattern | STRIDE | Standard mitigation |
|---|---|---|
| SQL injection via an Axonius group / display name / username field | Tampering | `Invoke-SqliteCommand` `@param` / `ConvertTo-SqliteLiteral`; no string-built SQL except the batch-INSERT path, which also uses `ConvertTo-SqliteLiteral` per value. |
| Stale Axonius export re-processed → roles retained past entitlement | Elevation of Privilege | `MaxExportAgeDays` check (warn) + `Valid_to` age-out is the backstop (an ex-member stops being renewed). Document that a *silently* stale export just slows revocation, never grants. |
| Malicious / swapped snapshot JSON in the Custom Repository | Tampering | `.sha1` manifest; the policy Fixlet's `prefetch` verifies the hash; `Reconcile-LocalRoles.ps1` also re-checks `snapshot.region`. Write access to `…\CustomRepository\` = local admin on the root server (existing boundary). |
| Malicious prefetch URL in a copied source fixlet (content pipeline) replacing an installer | Tampering | `Stage-Repository.ps1` verifies `Get-FileHash -Algorithm SHA1` against the prefetch line's `sha1:` before placing the file; mismatch = discard + log. |
| Unauthorized `GroupRoleMap` edit → role escalation for a whole group | Elevation of Privilege | Edits require a BigFix Console operator action or root-server local admin; `Created_by` / `Updated_on` recorded; the Reference-DB tab surfaces per-role counts so a spike is visible. |
| AKeyless token exfiltration from a log / transcript | Info Disclosure | `Get-BigFixCredential.ps1` never `Write-Host`s the token or secret (unlike the Cyera reference script, which logs the fetched value — **do not copy that line**); no `Start-Transcript` in the wrapper. |
| Reconcile assigns roles to the wrong user (identity confusion) | Spoofing / EoP | Single documented join key (lower-cased SAM ↔ `name of current user`); `Username_Src` flags coalesce fallbacks for review; `Locked_by_Override=1` rows are never touched; 07-05 live spot-check. |
| Policy Fixlet mutated daily by a script (supply-chain-ish on your own content) | Tampering | `Publish-RoleSnapshot.ps1` runs as the same scoped operator; the only field it changes is the `prefetch` line's `sha1:`/`size:`/leaf; log a diff each run. |

---

## Sources

### Primary (HIGH confidence — read directly this session)
- `.planning/phases/07-automation/07-CONTEXT.md` (2026-08-29 rewrite) — D-01…D-26, discretion, deferred.
- `.planning/quick/260828-fjc-role-reference-db/DESIGN.md` — full schema DDL, per-region snapshot shape, `Config` seed keys, AKeyless design, Axonius findings, plan map, environment/task-787 notes.
- `.planning/REQUIREMENTS.md` — FR-01…FR-10, NFR-01…05.
- `Dashboard_4_samples/Sqlite-Helper.ps1` — `Invoke-SqliteCommand`, WR-02, `ConvertTo-SqliteLiteral` (exported), `__hex` decode, `PRAGMA busy_timeout`.
- `Dashboard_4_samples/Initialize-RoleDb.ps1` — schema, D-12 upsert, `PRAGMA table_info(Map)` migration block, `UPDATE`+`SELECT changes()` co-location, error codes 5100–5400, `INSERT OR REPLACE` on `Users` only.
- `Dashboard_4_samples/Init  Current User and UserRole DB.bes` — prefetch block form, `SWPDir`/`SQLiteDir`/`TargetStore` param idioms, `createfile until _EOF_`, `RoleDB_Maintenance` registration gated on "not exists", `action uses wow64 redirection`.
- `Dashboard_4_samples/Dereso SWD.bes` — Analysis property format, tuple `%22`-split idiom, DB-existence `<Relevance>` guard, `PT5M`.
- `Existing Dashboards/fixlet_dispatcher.ojo` — `rewritePrefetchUrls()` (lines 591–599), `extractPrefetchLines()`, `PREFETCH_STAGE_SCRIPT`, `wwwRootFolder` registry derivation, `escapeActionScriptBraces` = `/\{/g,"{{"`, staging SingleAction.
- `Existing Dashboards/fixlet_role_assigner.ojo` — `PORTAL_CONFIG` (lines 40–53), btoa polyfill, `safeB64Encode`/`chunkString`/`CHUNK_SIZE=3000`, `buildAssignActionXml`/`buildAssignActionScript`, `loadAnalysisView` `GetRelevance`, DB-existence relevance (line 459).
- `Existing Dashboards/fixlet_modifier.ojo` — `buildRoleRelevance()` (lines 574–607, uses `names of logged on users as lowercase`), `Associated_Roles` MIME read/write.
- `Existing Dashboards/fixlet_update_tracker.ojo` — `stripVersion` (987) / `extractVersion` (992), `CATEGORY_MAP`, `sourceSites`, `scanNextSite`, `buildSupersededXml` / `X-Superseded-By`.
- `Existing Dashboards/fixlet_console.ojo` — `switchTab` / `switchSubTab` (322–344) tab pattern.
- `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1` — exact AKeyless call sequence (`.vault-token` → `POST /auth` universal_identity → `POST /get-secret-value` → `$resp.$path`), `EC\Cyera\.vault-token` path, failure handling (and the `Write-Host $pwPlain` line **not** to copy).
- `.claude/skills/bigfix-relevance/SKILL.md` — three relevance dialects, `{`→`{{` asymmetric escaping, SingleAction element order, `SourcedFixletAction` vs `SingleAction`, MIME-field carry, prefetch URL + `wwwRootFolder`, `""` quote escaping, `{computer id}` not `{id of computer}`, `.ojo` save safety.
- `G:/Gits/bigfix_skills/skills/jf-bigfix-client-relevance/` — `name of current user` is a string but "client runs as SYSTEM — use logged on users for interactive user"; `is contained by set of` membership; `settings … of client` only in client relevance.
- Project memory: `bigfix-prefetch-url-rewrite`, `bigfix-role-relevance-schema`, `role-awareness-logon-rework-status`, `role-reference-db-redesign`, `sqlite-helper-pattern`, `bigfix-actionscript-curly-brace-escaping`, `bigfix-actionhistory-db-internals` (`-wal` copy caveat), `ojo-file-safety`.
- `SampleAxonious/axonius-users_anond.csv` header — 47 columns, BOM, RFC-4180 confirmed by `head`.
- `bash` — `pwsh 7.6.3`, `node v24.15.0`, `Pester 5.7.1 + 3.4.0`, branch `260813-fjc-fixlet-console`, `scripts/` has only `generate_category_map.js`.

### Secondary (MEDIUM — verified against an authoritative source)
- Microsoft `Import-Csv` docs — RFC-4180 quoted-field + embedded-newline handling; pipeline streaming behaviour.
- Prior `07-RESEARCH.md` (2026-08-01) — content-pipeline patterns (Patterns 6, 9, 10, 11; Pitfalls 1, 3, 5), reused; **role-pipeline sections discarded**.

### Tertiary (LOW — flagged in Assumptions Log)
- WebSearch: PowerShell CLM type allow-list ("only core types are supported") — supports rejecting `StreamReader`; not verified against this project's exact CLM policy.
- WebSearch: `StreamReader` ~120× less memory than `Get-Content` — informs the `Import-Csv` vs `StreamReader` tradeoff only.
- BigFix REST response shapes (`POST /api/query` → `{result:[…]}`), `127.0.0.1:52311` client-side URL resolution, `name of current user` == console user — all training-data / operator-assertion; 07-05 verifies.

---

## Metadata

**Confidence breakdown**
- Standard stack & existing patterns (SQLite helper, D-12 upsert, prefetch rewrite, OJO IE9, ActionScript escaping, content-pipeline idioms): **HIGH** — read from source this session.
- Combined-DB schema & discretion resolutions: **HIGH** — DDL is from DESIGN.md; naming is dictated by CONTEXT D-01.
- Ingest approach (`Import-Csv` streaming + batched INSERT): **MEDIUM-HIGH** — standard PS, but runtime on the real 400 MB file (A7) and BOM behaviour (A8) need a 07-01 profiling pass.
- Per-region distribution (policy Fixlet prefetch, `127.0.0.1` reach, daily re-PUT): **MEDIUM** — the URL shape is proven for the Dispatcher but in a root-server-only context; fleet-wide reach (A2) and the stale-hash handling (Pitfall 3) need 07-05.
- Endpoint reconcile / `name of current user` (A1): **MEDIUM-LOW** — operator asserts it; the codebase's own role relevance uses the plural `logged on users` instead. Single biggest verification item.
- Content pipeline (07-03): **HIGH** — unchanged, patterns proven in Phase 6.

**Research date:** 2026-08-29
**Valid until:** ~2026-09-28 for the codebase-derived material (stable); the BigFix-runtime assumptions (A1, A2, A4) should be closed in 07-05 regardless of date.
