---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-08-30T18:55:00.000Z"
progress:
  total_phases: 7
  completed_phases: 5
  total_plans: 25
  completed_plans: 23
  percent: 92
---

# Project State — Software Portal

## Current Status

**Project Phase:** Phase 7 (End-to-End Automation) — EXECUTING — Wave 3 complete  
**Status:** Executing Phase 07 — 4/6 plans done (07-00 Foundation, 07-01 Ingest, 07-02 Publish+distribute+reconcile, 07-03 Content pipeline)
**Last Updated:** 2026-08-30

## Completed

- ✅ Project context captured in PROJECT.md
- ✅ Requirements extracted and documented (7 FR, 5 NFR)
- ✅ Roadmap planned with 3-phase MVP
- ✅ Workflow configuration set
- ✅ Planning directory structure initialized
- ✅ **Phase 1 context captured** (01-CONTEXT.md, 01-DISCUSSION-LOG.md)
- ✅ **Phase 1 planned** — 4 plans in 2 waves, verification passed (6/6 requirements covered)
- ✅ **Phase 1 executed** — 4/4 plans complete, 43 unit tests green, 10/13 verified (3 require BigFix console)
- ✅ **Phase 1 code review** — 2 critical, 5 warning (advisory, non-blocking)
- ✅ **Phase 2 context captured** (02-CONTEXT.md, 02-DISCUSSION-LOG.md) — 4 gray areas discussed
- ✅ **Phase 2 planned** — 3 plans in 2 waves, verification passed (FR-02, FR-03, FR-04 deferred covered)
- ✅ **Phase 2 executed** — 3/3 plans complete, 75 unit tests green, code review fixes applied (3 critical, 5 warning resolved)
- ✅ **Phase 2 verified** — 9/10 automated checks passed; 1 human UAT item pending (BigFix console smoke test)

## Completed (continued)

- ✅ **Phase 4 executed** — 4/4 plans complete, 128 unit tests green, 9/9 automated verification passed
- ✅ **Phase 4 code review** — 4 critical, 5 warning (CR-01/CR-02/CR-04 fix recommended before production)
- ✅ **Phase 7 context captured** (07-CONTEXT.md) — 20 decisions D-01 through D-20
- ✅ **Phase 7 researched** (07-RESEARCH.md) — 12 architecture patterns, 10 pitfalls, security domain, package legitimacy audit
- ✅ **Phase 7 pattern-mapped** (07-PATTERNS.md) — 21 deliverables, 17/21 analogs found
- ✅ **Phase 7 validation strategy** (07-VALIDATION.md) — per-task verification map, Wave 0 gaps identified
- ✅ **Phase 7 planned** — 6 plans in 6 waves (Wave 0–5), all FR-01–FR-10 + NFR-01–NFR-05 covered
- ✅ **Phase 7 Wave 0 executed** (07-00) — 4/4 tasks: `Initialize-AutomationDb.ps1` (11-table schema + 13 Region + 3 Role + 13 PipelineConfig seeds + Event Log source + `-WhatIf`), `Get-BigFixCredential.ps1` (AKeyless universal identity, no secret at rest), `Register-AutomationTasks.ps1` skeleton, D-18 `Map` migration + logon-rework committed, Pester harness + 6 fixtures + `Assert-SnapshotShape.ps1` + `role_admin.test.js`. 39 Pester + 8 Node suites green.
- ✅ **Phase 7 Wave 1 executed** (07-01) — 4/4 tasks: `Import-AxoniousExport.ps1` (single unassigned `Import-Csv | ForEach-Object` streaming ingest, 11-column header/BOM validation → error 6700, stale-file guard warn-not-abort → Event 8010, `GroupRoleMap` matcher loaded once, batched `INSERT OR IGNORE` + guarded `UPDATE` via `ConvertTo-SqliteLiteral` at 400 rows/txn, age-out sweep marking `Active=0` with a `MaxAgeOutFraction` mass-revoke brake → Event 8012, `SyncRun(Type='Ingest')` + per-run JSON log, `-WhatIf` zero writes, `-ReportGroupFrequency` operator CSV) + `AxoniousParse.psm1` pure module (`Resolve-UserName`/`Get-GroupViews`/`Get-SourceType`/`Resolve-Roles` + `Get-GroupRows` D-07 seam). 111 Pester + 8 Node suites green.
- ✅ **Phase 7 Wave 3 executed** (07-03) — 3/3 tasks: `ContentSyncCore.psm1` pure module (`Get-StrippedName`/`Get-ExtractedVersion`/`Compare-FixletVersion`/`Get-FixletPathType`/`New-SupersededXml`/`Read-PrefetchLine` — every `stripVersion` case in `update_tracker.test.js` ported one-for-one); `Invoke-ContentSync.ps1` (`POST /api/query` \x1F-tuple scan ported from `scanNextSite`, version diff keyed on `Get-StrippedName`, D-12 `INSERT OR IGNORE` + guarded `UPDATE` writing `discovered` ContentItems, 4-step copy over `stage='ready'` only — GET portal → GET source singular → POST `fixlets/custom` plural → PUT `fixlet|task/custom/<id>` singular — with category + `Associated_Roles` MIME transfer + idempotent `X-Superseded-By` stamp, per-item partial-failure `stage='rejected'` + Event 8030, `Start-ScheduledTask DeresoRepoStage` chain, `SyncRun(Type='ContentSync')` + JSON log, `-WhatIf` zero writes); `Stage-Repository.ps1` (per `live` ContentItem: GET action script, `Read-PrefetchLine`, download from the ORIGINAL url, `Get-FileHash -Algorithm SHA1` + byte-length verify, place a match at `<wwwRootFolder>\Uploads\CustomRepository\SoftwarePortal\<sha1-lc>\<file>`, discard any mismatch → `ContentCache verified=0` + note + Event 8040, sha1 dedupe, `MaxStageFileMB`/`MaxItems` guards, `SyncRun(Type='RepoStage')` + JSON log, `-WhatIf` zero I/O); `DeresoContentSync` (Weekly) + `DeresoRepoStage` (OnDemand) rows appended + run-book task XMLs; 5 additive AutomationState.db columns via idempotent PRAGMA-gated ALTER (shared init untouched). 224 Pester + 8 Node suites green.
- ✅ **Phase 7 Wave 2 executed** (07-02) — 4/4 tasks: `SnapshotBuild.psm1` pure seam (`Build-RegionSnapshot` extended-D-11 objects + pipe-joined provenance + byte-identical JSON, `New-PrefetchLine`, `New-RoleRefRelevance` `| true`-coalesced freshness gate, `Format-RoleRefFixletXml`); `Publish-RoleSnapshot.ps1` (registry-derived roleref dir, dated + latest + `.sha1`, `Snapshot`/`SyncRun` rows, `-WhatIf` writes nothing; `Invoke-RoleRefFixletLifecycle` POST-plural-then-PUT-singular, non-2xx → `Status='failed'` + Event 8020 without aborting other regions); `bes/RoleRef-Policy-template.bes` (plain Fixlet, 3-clause `<Relevance>`, prefetched file resources, zero createfile/`}}`); `Reconcile-LocalRoles.ps1` (CLM-safe, region re-check vs `snapshot.region`, guarded D-12 upsert writing the 4 provenance cols, unknown-role `INSERT OR IGNORE INTO Roles`, General-Access no-match = clean success, freshness stamp via BES client "manual setting" registry key); `RoleDB_Maintenance` rewired to two sequential actions + `Unregister-ScheduledTask` before the re-register guard (Pitfall 5); `DeresoRoleIngest` + `DeresoRolePublish` rows appended + run-book task XMLs. 170 Pester + 8 Node suites green.

## In Progress

- Phase 7: End-to-End Automation — 4/6 plans executed (07-00, 07-01, 07-02, 07-03 done). Wave 4 (dashboards) is next; it requires Waves 2 and 3, both now complete.

## Next Steps

- Execute Wave 4 (07-04-PLAN.md: dashboards) — new `fixlet_role_admin.ojo`, `fixlet_role_assigner.ojo` Analysis Source/Region, `fixlet_automation_monitor.ojo` content-only (reads `ContentItem` / `ContentCache` from 07-03), `Dereso SWD.bes` Source/Region props. Its "Test Pattern" JS matcher must mirror `Resolve-Roles` exactly.
- Wave 5 (07-05-PLAN.md: integration + rollout) has a blocking human-verify checkpoint; carries the A7 production-host profiling pass, the GroupRoleMap go-live rule-authoring gate, the `-WhatIf` dry-runs for the new root-server scripts, and live BigFix verification of the content pipeline (`POST /api/query` shape, operator-credentialed POST/PUT, `wwwRootFolder` path).
- Wave 5 (07-05-PLAN.md: integration + rollout) has a blocking human-verify checkpoint; carries the A7 production-host profiling pass and the GroupRoleMap go-live rule-authoring gate

## Phase Status

| Phase | Title | Status | Plans | Verified |
|-------|-------|--------|-------|----------|
| 1 | Copier Foundation | ✅ Complete | 4/4 | ✅ 10/13 (3 need console) |
| 2 | Modifier (Roles) | ✅ Complete | 3/3 | ✅ 9/10 (1 needs console) |
| 3 | Dispatcher (Deploy) | ✅ Complete | 3/3 | ✅ 8/8 UAT passed |
| 4 | Role Assigner | ✅ Complete | 4/4 | ✅ 9/9 auto + 5/5 UAT passed |
| 5 | Robustness | ✅ Complete | 1/1 | FR-08 + FR-09 delivered; smoke test requires live Web Reports |
| 6 | Fixlet Update Tracker | 📋 Planned | 0/4 | Ready to execute |
| 7 | End-to-End Automation | Executing | 4/6 | 07-00 + 07-01 + 07-02 + 07-03: 224 Pester + 8 Node suites green |

## Key Decisions Made

1. **3-Phase MVP Structure** — Copier, Modifier, Dispatcher as separate but integrated phases
2. **BigFix Dashboard XML** — All UIs implemented as BigFix native dashboards (not external web app)
3. **Role-Based Relevance** — Role access control enforced via generated Relevance rules
4. **Automatic Offers** — Dispatcher auto-creates 'offer' style deployments with derived category
5. **1-Month Timeline** — MVP completion target: 4 weeks
6. **No External RBAC** — Roles managed within BigFix (not synced with AD/other systems)

### Phase 7 Specific Decisions (2026-08-29 rewrite — role pipeline follows the user, not the machine)

- **AutomationState.db** — one combined SQLite DB on the BES root server, 11 tables: Role, Region, GroupRoleMap, RefUser, UserRole, RolePublication, Snapshot, SyncRun, PipelineConfig, ContentItem, ContentCache (D-01). Names resolved: PipelineConfig (not Config), ContentCache (not the superseded name), one wide SyncRun with a Type column. `RoleAssignment` / DPAPI credential storage are **dropped**.
- **No ComputerID in the role pipeline (D-02)** — endpoints self-select by their own `GPC_Sub_Name` client setting; per-region snapshot JSON in the Custom Repository is the only distribution mechanism.
- **Credential (D-20)** — `Get-BigFixCredential.ps1` fetches the BigFix operator password from AKeyless using Cyera's existing universal identity at runtime; no secret at rest, no DPAPI file.
- **Region seed (D-21)** — fixed 13 values: UAP, MOT, APAC, APAC-MOT, APAC-M&A, AAG-DE, AAG-FR, AAG-UK, AAG-ES, AAG-BLX, AAG-PL, AAG-PT, GPC.
- **Endpoint Map migration (D-18)** — additive `Source_Type`/`Source_Value`/`Region`/`Assigned_By` columns via `PRAGMA table_info(Map)`-gated ALTER; folded into `Initialize-RoleDb.ps1`; logon-rework committed under Phase 7.
- **Snapshot shape (D-11 amendment)** — `users` entries are objects `{ id, source_type, source_value }` (pipe-joined source_value when >1 group). "General Access" is never enumerated; an absent user is the normal default.
- **GroupRoleMap.json** — ships empty-by-design; rule content is a deferred go-live gate, not a phase blocker.
- **6 plans / 6 waves (D-25)** — 07-00 Foundation, 07-01 Ingest, 07-02 Publish+distribute+reconcile, 07-03 Content pipeline, 07-04 Dashboards, 07-05 Integration+rollout.
- **07-00 outcomes** — `PipelineConfig` seeded with 13 keys incl. `ConsoleUserRelevance` (RESEARCH Pitfall 2 config seam); `$AutomationTaskTable` is APPEND-ONLY (07-02/07-03 add rows); `Assert-RoleRefSnapshotShape` is the single shared snapshot-shape contract.
- **07-01 outcomes** — pure transforms live in `scripts/AxoniousParse.psm1` (5 exports incl. the `Get-GroupRows` D-07 splitter seam) so Pester can test them without running the driver; `Get-DbRows` flattens Sqlite-Helper's `return ,$rows` wrapper (the `@(...)` idiom miscounts multi-row results); `Source_Value` on a `UserRole` row is the matched view value; `MaxAgeOutFraction` (default `0.5`) is read from `PipelineConfig` when present but NOT added to `PipelineConfig.defaults.json` (the 07-00 "exactly 13 keys" test), so an operator opts into a non-default brake by adding the key; the age-out sweep runs only after a clean full read.

### Phase 3 Specific Decisions (Plans 03-01 and 03-02)

- **PORTAL_CONFIG.targetGroups:** Four standard groups — All Workstations, IT Department, Finance Department, All Servers
- **PORTAL_CONFIG.defaultExpirationDays:** 7 (P7D ISO 8601 duration for SourcedFixletAction XML)
- **buildTargetRelevance fallback:** Empty/whitespace group name returns `"true"` (all computers)
- **parseActionId regex paths:** Three fallback regexes in order: /api/action/N URL, ID= attribute, `<ID>N</ID>` element
- **No <Target> element in SourcedFixletAction:** Group targeting via Relevance element only (RESEARCH.md A1, Pitfall 1)
- **Atomic Task 1+2 implementation:** Both scaffold and deploy logic written in one Write operation to avoid half-functional intermediate state
- **renderActionDropdown() sets selectedActionId="":** No auto-selection per D-08; deploy guard blocks until admin chooses
- **Test count:** 23 tests (plan minimum was 20+)
- **Last session:** 2026-08-30 — completed 07-03-PLAN.md (Wave 3 Content pipeline: `Invoke-ContentSync.ps1` + `Stage-Repository.ps1` + `ContentSyncCore.psm1` + 2 scheduled tasks). Stopped at: Wave 3 complete. Resume file: None.

### Phase 7 Wave 2 (07-02) Decisions

- **`SnapshotBuild.psm1` is the single pure seam** (`Build-RegionSnapshot` / `New-PrefetchLine` / `New-RoleRefRelevance` / `Format-RoleRefFixletXml`) — no file I/O, no DB, no REST; imported by the publisher AND by Pester. `New-RoleRefRelevance` landed in the Task 1 commit (plan places it in Task 2) to keep the module self-contained.
- **`built_on` is a `-BuiltOn` parameter of `Build-RegionSnapshot`, not `Get-Date`** — keeps the function pure so two runs over identical data emit byte-identical JSON (asserted). `users` are ordinal-sorted; `source_value`/`source_type` distinct + pipe-joined across granting groups.
- **`Format-RoleRefFixletXml` replaces the whole `<Relevance>` CDATA** with `New-RoleRefRelevance` output (not `__REGION_LC__` token substitution on inline text) so 07-05 can flip `-IncludeFreshnessGate` per region with no template edit. The freshness gate is `((… as string as time) > 1*day) | true`-coalesced so a malformed stamp can never error the relevance.
- **Policy Fixlet lifecycle:** POST plural `fixlets/custom/<site>` on first publish (id → `PipelineConfig.RoleRefFixletId_<rgn>`), PUT singular `fixlet/custom/<site>/<id>` after; a non-2xx sets that region's `Snapshot.Status='failed'` + Event 8020 + `SyncRun.Error_Count++` and continues. PS7 `-SkipCertificateCheck` with a 5.1 trust-all fallback, no `Add-Type`.
- **`Reconcile-LocalRoles.ps1` freshness stamp** = BES client "manual setting" registry key `roleref_<region-lc>_applied` (`value` + `effective date`) + a sidecar JSON (no prior endpoint-script precedent; `-StampRegistryPath` overridable). **07-05 must verify the client honours this key on the production fleet.**
- **`.bes` `Unregister-ScheduledTask` uses `-ErrorAction SilentlyContinue`, not `try/catch`** — a `try { } catch { }` in the ActionScript would add `{{` brace-escaping to a heredoc that has none. `parameter "Region"` is `exists setting … then … else ""`-guarded.
- **`config/task-*.xml` hand-authored** as Task Scheduler 1.2 XML (running `Register-AutomationTasks.ps1` registers real tasks); 07-05 regenerates on the root server. `DeresoRolePublish` shares the helper's Daily 3am trigger with ingest — "after ingest" sequencing deferred to the 07-05 run-book.

### Phase 7 Performance Metrics

| Plan | Duration | Tasks | Files | Result |
|------|----------|-------|-------|--------|
| 07-00 | ~35 min | 4 | 20 | 39 Pester + 8 Node green |
| 07-01 | ~130 min | 4 | 5 | 111 Pester + 8 Node green |
| 07-02 | ~95 min | 4 | 12 | 170 Pester + 8 Node green |
| 07-03 | ~115 min | 3 | 11 | 224 Pester + 8 Node green |

### Phase 1 Specific Decisions

- **Use existing copier.ojo as-is** — Complete, tested implementation
- **Standalone copier in Phase 1** — No integration with Phase 2/3 needed yet
- **Testing:** Both unit and integration tests required
- **Documentation:** Admin guide, architecture doc, API reference
- **Delivery:** Raw .ojo file + comprehensive docs

## Risks & Assumptions

### Phase 7 Assumptions (from RESEARCH.md)

- **A1:** BigFix root server is enrolled as a managed BES client — required for Analysis approach to read AutomationState.db from dashboard
- **A2:** pwsh.exe (PS7) is installed on BigFix root server — required for -SkipCertificateCheck on Invoke-RestMethod
- **A3:** BigFix REST API returns `{"result":[...]}` JSON from POST /api/query — assumed based on standard BigFix API
- **A5:** sqlite3.exe must be placed at configured SQLDir path on root server before pipeline scripts can run

### General Assumptions

- BigFix API access available and stable
- "Dereso Software Portal" custom site exists in target BigFix instance
- BigFix admin can run ActionScript and Relevance
- Test fixlets available for integration testing

### Risks

- BigFix API rate limits during development
- Role relevance logic complexity may exceed 1-week estimate
- Deployment safety validation might require additional testing

## Configuration

**Workflow Settings:** `config.json`

- Auto-commit: ON
- Code review: Required
- Regression testing: Enabled
- Security gate: Enabled

## Communication Log

- **2026-06-11**: Project initialized with 3-phase roadmap, 1-month timeline
- **2026-08-01**: Phase 7 planned — 5 plans, 5 waves, all 15 requirements assigned

**Planned Phase:** 07 (End-to-End Automation) — 6 plans — 2026-08-29T20:59:35.973Z
