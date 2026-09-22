---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-09-22T20:42:52.213Z"
progress:
  total_phases: 7
  completed_phases: 5
  total_plans: 31
  completed_plans: 23
  percent: 74
---

# Project State — Software Portal

## Current Status

**Project Phase:** Phase 7 (End-to-End Automation) — EXECUTING — Wave 3 of 10 complete, starting Wave 4 (replanned 2026-09-21 for the Operator-Role-Group model)  
**Status:** Executing Phase 07 — Wave 3 (07-05) complete
**Last Updated:** 2026-09-22

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
- ✅ **Phase 7 Wave 4 executed** (07-04) — 3/3 tasks: `Dereso SWD.bes` `map_source in r.db` (ID 5) + `map_region in r.db` (ID 6) Analysis properties (3-item tuple, `coalesce`-guarded, PT5M; 4 existing props byte-identical); `fixlet_role_assigner.ojo` Analysis view gains Source + Region columns via pure `mergeAnalysisRows` (mapped_users is the spine, missing cell = em dash), Analysis last-reported line, CSV panel relabelled BREAK-GLASS (break-glass functions md5-identical); NEW `fixlet_role_admin.ojo` — 4 tabs (GroupRoleMap rule editor + Test Pattern `matchesRule`/`resolveRolesJs` mirroring `AxoniousParse.psm1 Resolve-Roles` exactly, RolePublication scope, Region one-at-a-time publish picker reading the 13 seeded rows, read-only Reference DB health), writes via SingleAction→root-server BES client (Title>Relevance>ActionScript>Settings>Target) carrying a base64-chunked brace-escaped embedded PowerShell upsert (zero `}}`); NEW content-pipeline-only `fixlet_automation_monitor.ojo` — 4 tabs (Status, Content Queue approve/reject with `live` rows read-only, Repository Cache `verified=0` error-styled + counted, PipelineConfig editor with AKeyless keys PATH-ONLY), zero role controls (`grep -ci grouprolemap|rolepublication` = 0). role_admin.test.js 38 assertions, automation_monitor.test.js new 9th suite 22 assertions, role_assigner.test.js 33→39. **All 9 Node suites green + full Pester 224 passed / 0 failed** (no PowerShell changed). AutomationState.db Analysis property bodies are a 07-05 step (dashboards degrade to "Analysis not reporting yet").
- ✅ **Phase 7 Wave 2 executed** (07-02, pre-rewrite/retired) — 4/4 tasks: `SnapshotBuild.psm1` pure seam (`Build-RegionSnapshot` extended-D-11 objects + pipe-joined provenance + byte-identical JSON, `New-PrefetchLine`, `New-RoleRefRelevance` `| true`-coalesced freshness gate, `Format-RoleRefFixletXml`); `Publish-RoleSnapshot.ps1` (registry-derived roleref dir, dated + latest + `.sha1`, `Snapshot`/`SyncRun` rows, `-WhatIf` writes nothing; `Invoke-RoleRefFixletLifecycle` POST-plural-then-PUT-singular, non-2xx → `Status='failed'` + Event 8020 without aborting other regions); `bes/RoleRef-Policy-template.bes` (plain Fixlet, 3-clause `<Relevance>`, prefetched file resources, zero createfile/`}}`); `Reconcile-LocalRoles.ps1` (CLM-safe, region re-check vs `snapshot.region`, guarded D-12 upsert writing the 4 provenance cols, unknown-role `INSERT OR IGNORE INTO Roles`, General-Access no-match = clean success, freshness stamp via BES client "manual setting" registry key); `RoleDB_Maintenance` rewired to two sequential actions + `Unregister-ScheduledTask` before the re-register guard (Pitfall 5); `DeresoRoleIngest` + `DeresoRolePublish` rows appended + run-book task XMLs. 170 Pester + 8 Node suites green. **Retired 2026-09-21** along with the rest of the Axonius reference-DB pipeline — see 07-CONTEXT.md rationale; `Reconcile-LocalRoles.ps1`'s wiring in task 787 is what the new-model 07-02 below strips back out.
- ✅ **Phase 7 Wave 1 executed** (07-02, new 12-plan/Operator-Role-Group model) — 2/2 tasks, 2026-09-21: stripped the retired `Reconcile-LocalRoles.ps1` prefetch/copy/scheduled-task wiring out of task 787's `Dashboard_4_samples/Init  Current User and UserRole DB.bes` (D-18 hard prerequisite), collapsed `RoleDB_Maintenance` to a single-action `-Action @($actionInit)` registration, kept the v4 `Map` migration (`Source_Type`/`Source_Value`/`Region`/`Assigned_By` ALTER) and the `Unregister-ScheduledTask` pre-guard intact; added `tests/pester/InitCurrentUserTask.Tests.ps1` (20 tests) locking the diff shape; fixed a stale `tests/pester/Reconcile-LocalRoles.Tests.ps1` assertion that contradicted the corrected shape (Rule 3). Commits `17d4733`/`6d0e3a7`/`b29dd7e`. Clears the D-18 schema blocker for `scripts/Assign-RoleMapping.ps1`; the live task 787 redeploy itself is plan 07-12's checkpoint. Two unrelated pre-existing bugs found during the full-estate regression run (`Upsert-RolePublish.ps1` `RoleUsers` DDL gap, `Import-AxoniousExport.ps1` tag-scoping `NotRun`) logged to `.planning/phases/07-automation/deferred-items.md` for a future follow-up plan, not fixed here (out of scope).

- ✅ **Phase 7 Wave 1 executed** (07-03, root-server audit store) — 2/2 tasks, 2026-09-21: `scripts/Upsert-RolePublish.ps1` (D-05 append-only `RolePublishRun`/`RoleUsers` schema + per-Publish snapshot writer, fully parameterized, CLM-safe) + `tests/pester/Upsert-RolePublish.Tests.ps1` (20 tests). Commits `f86db89`/`6476860`, merged to main `aad5e4a`. **Bug found + fixed 2026-09-21** (`2247a91`): PS 5.1's `ConvertFrom-Json` collapses a single-element JSON array to a bare scalar, so the `users` field validation wrongly rejected every single-user Publish with exit 5410 before the schema was ever created — the root cause of the `RoleUsers` DDL gap logged in `deferred-items.md`. Fixed via a raw-JSON-text fallback check; also fixed the source-guarantees test's comment-stripping (didn't handle `<# #>` block comments). Full-estate regression: 285 passed / 0 failed / 1 NotRun (pre-existing, unrelated).
- ✅ **Phase 7 Wave 1 executed** (07-01, ground-truth spike) — 2/2 tasks, 2026-09-22: `07-SPIKE-RUNBOOK.ps1` (Task 1, `b255f7b`) + production-run blocking checkpoint (Task 2, run by the user against live `gpbfs`). Results: six-element `<ComputerGroup>` body accepted, no live Axonius-era artefacts on `gpbfs`, `sqlite3.exe` 3.53.1 present. **Correction applied** (`79f6bb4`): the findings file's original Check B verdict (PASS) was wrong — two runbook bugs (an `Invoke-WebRequest` byte[]→`[string]` cast that silently produced an unreadable byte-value dump instead of decoded text, and a pass-condition regex too narrow to catch BES's generic `<Error>` element) masked a real query failure (`logged on users` is undefined in session relevance, client-relevance-only). Both bugs fixed in the runbook; findings corrected in place. Confirmed no impact on 07-04 (which only ever uses this expression as client relevance). See `07-01-SUMMARY.md`.
- ✅ **Phase 7 Wave 1 complete** — all three plans (07-01, 07-02, 07-03) done as of 2026-09-22.
- ✅ **Phase 7 Wave 2 executed** (07-04, `fixlet_role_manager.ojo` interface-first build, D-14) — 3/3 tasks, 2026-09-22: `Existing Dashboards/fixlet_role_manager.ojo` created — two-tab (Roles/Analysis) IE9 OJO shell, `PORTAL_CONFIG` (D-03 roles, D-10 scope groups, D-07 rootServerComputerId, D-16 Analysis props), every shared helper lifted byte-equivalent from `fixlet_dispatcher.ojo`/`fixlet_role_admin.ojo`/`fixlet_role_assigner.ojo`; five pure builders added — `buildRoleGroupRelevance` (D-09/D-10, T-07-04-01 empty-list→`"false"` guard), `buildComputerGroupXml` (Pattern 1, six-element body per 07-01's live spike), `buildRolePolicyTaskXml` (Pattern 3 step 1, from-scratch `<BES><Task>` build, `__ROLE__`/`__ASSIGNED_BY__` substitution extended to `<Relevance>` elements too as a Rule-1 fix), `buildRolePolicyActionXml` (Pattern 3 steps 2-3, D-11, `SingleAction` only, `Target` after `Settings`, `Reapply`/`P1D`/`IsOffer=false`), `findBesObjectIdByTitle` (session-relevance find-by-title). `tests/unit/role_manager.test.js` — 30 assertions, spot-checked the empty-list guard is load-bearing. All 10 `tests/unit/*.test.js` suites green (no PowerShell/Pester touched). Commits `b03a88d`/`cbff752`/`017321e`. No live BigFix console verification needed yet (no REST calls exist in the dashboard — tab content lands in 07-06/07-07/07-08). See `07-04-SUMMARY.md`.
- ✅ **Phase 7 Wave 3 executed** (07-05, D-06 periodic drift-check job) — 3/3 tasks, 2026-09-22: `scripts/RoleGroupRelevance.psm1` — pure `New-RoleGroupRelevance` (byte-identical twin of `fixlet_role_manager.ojo`'s `buildRoleGroupRelevance`; Assumption A2 held for client relevance per `07-SPIKE-FINDINGS.md`, no deviation form needed; corrected the plan's "ordinal sort" prose to match the dashboard's actual insertion-order-preserving de-dup) + `Get-CurrentRoleUsers` (canonical `MAX(RunID)` query against `RolePublish.db`). `tests/fixtures/phase-07/role-group-relevance.golden.txt` — 3-line hand-authored cross-language contract (07-06 also asserts against it from the Node side). `scripts/Sync-RoleGroups.ps1` — the D-06 driver: GET-compare-PUT per role, never creates a group (D-13 stays the dashboard's job), per-role `[OK]`/`[DRIFT-FIXED]`/`[MISSING]`/`[FAIL]` + Event 8050, refuses a non-`RolePublish.db` database with a distinct exit code, `-WhatIf` zero PUTs. `tests/pester/Sync-RoleGroups.Tests.ps1` — 32 passing tests (mocked REST via Pester `Mock`, no live server needed). `scripts/Register-AutomationTasks.ps1` gains `-RolePublishDbPath` + the `DeresoRoleGroupSync` row (Daily@04:00, one hour after the content pipeline) + `config/task-DeresoRoleGroupSync.xml` run-book — purely additive, the four pre-existing rows/branches are byte-unchanged. Fixed two pre-existing Pester tests that hard-coded "4 task(s) selected" (now recomputed from the table). **Full estate: 317 Pester passed / 0 failed / 1 pre-existing unrelated NotRun, all 10 Node suites green.** Commits `3cfc926`/`efad59a`/`0f68f7d`. See `07-05-SUMMARY.md`.

## In Progress

- **2026-09-21 SUPERSEDES the 2026-09-09 pause/rework note below.** The role-assignment rework was decided: Phase 7 was rewritten to the Operator-Role-Group model (12 plans, 10 waves — see `07-CONTEXT.md` D-01..D-25 and the ROADMAP.md rewrite note). The old-model 07-05 blocking checkpoint referenced below no longer applies; the pre-rewrite work (07-00..07-04 old numbering) is retired, not resumed.
- Phase 7 (new model): Wave 1 (07-01/07-02/07-03), Wave 2 (07-04), and Wave 3 (07-05) are complete — see Completed bullets above. Starting Wave 4 (`07-06`, Node-side golden-file assertion + Roles tab UI).
- (Historical, superseded 2026-09-21 — kept for record) Phase 7 old-model: 5/6 plans executed. 07-05 Tasks 1–3 committed (`23b22aa`, `286e6de`, `2b05502`); estate green (245 Pester excl. Slow, 9 Node suites, 6 integration suites in skip mode, `Invoke-WhatIfAudit.ps1` PASS ×8 + negative control). Paused at the 07-05 blocking `human-verify` checkpoint (Task 4) for the role-assignment rework decision above. Handoff: `.planning/HANDOFF.json` + `.planning/phases/07-automation/.continue-here.md` (both reference the retired old-model plan structure).

### Pending Todos (2026-09-09, superseded — see 2026-09-21 note above)

- `260909-rework-role-assignment-approach.md` — **resolved**: role-assignment model reworked 2026-09-21 (Operator-Role-Group, 12 plans).
- `260909-phase-07-05-production-fleet-verification.md` (`resolves_phase: 07`) — old-model checklist, superseded by the new `07-12-PLAN.md` (Wave 10 production verification).

### Pending Follow-up (2026-09-21)

- `.planning/phases/07-automation/deferred-items.md` — two pre-existing, unrelated bugs found during 07-02's full-estate regression run: `Upsert-RolePublish.ps1` `RoleUsers` table DDL gap (11 Pester failures), `Import-AxoniousExport.ps1` tag-scoping `NotRun` under `-ExcludeTag Slow`. Neither is in-scope for 07-02; needs a follow-up plan.

## Next Steps

1. Continue executing Phase 7's new 12-plan/10-wave structure per `ROADMAP.md` — Wave 4 = `07-06` (Node-side golden-file assertion against `tests/fixtures/phase-07/role-group-relevance.golden.txt` + the Roles tab UI/Save flow), blocked on Wave 3 (07-05) completion, which is now done.
2. Investigate and fix the `Upsert-RolePublish.ps1` `RoleUsers` DDL gap logged in `deferred-items.md` (blocks a fully green `-ExcludeTag Slow` estate) — still outstanding, unrelated to 07-05.
3. Before 07-12 installs `config/task-DeresoRoleGroupSync.xml` on the live root server: confirm the AKeyless secret exists at `PipelineConfig.AKeylessSecretPath` and set `PipelineConfig.BESOperatorUser` (currently seeded blank).
4. Resume with `/gsd:resume-work` or `/gsd:execute-phase 7`.

## Phase Status

| Phase | Title | Status | Plans | Verified |
|-------|-------|--------|-------|----------|
| 1 | Copier Foundation | ✅ Complete | 4/4 | ✅ 10/13 (3 need console) |
| 2 | Modifier (Roles) | ✅ Complete | 3/3 | ✅ 9/10 (1 needs console) |
| 3 | Dispatcher (Deploy) | ✅ Complete | 3/3 | ✅ 8/8 UAT passed |
| 4 | Role Assigner | ✅ Complete | 4/4 | ✅ 9/9 auto + 5/5 UAT passed |
| 5 | Robustness | ✅ Complete | 1/1 | FR-08 + FR-09 delivered; smoke test requires live Web Reports |
| 6 | Fixlet Update Tracker | 📋 Planned | 0/4 | Ready to execute |
| 7 | End-to-End Automation | Executing | 5/12 (replanned 2026-09-21) | 07-01/07-02/07-03/07-04/07-05 complete (this update); old-model 07-00..07-04 retired — see In Progress notes |

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
- **Last session:** 2026-09-22T20:42:52.200Z

### Phase 7 Wave 2 (07-02) Decisions

- **`SnapshotBuild.psm1` is the single pure seam** (`Build-RegionSnapshot` / `New-PrefetchLine` / `New-RoleRefRelevance` / `Format-RoleRefFixletXml`) — no file I/O, no DB, no REST; imported by the publisher AND by Pester. `New-RoleRefRelevance` landed in the Task 1 commit (plan places it in Task 2) to keep the module self-contained.
- **`built_on` is a `-BuiltOn` parameter of `Build-RegionSnapshot`, not `Get-Date`** — keeps the function pure so two runs over identical data emit byte-identical JSON (asserted). `users` are ordinal-sorted; `source_value`/`source_type` distinct + pipe-joined across granting groups.
- **`Format-RoleRefFixletXml` replaces the whole `<Relevance>` CDATA** with `New-RoleRefRelevance` output (not `__REGION_LC__` token substitution on inline text) so 07-05 can flip `-IncludeFreshnessGate` per region with no template edit. The freshness gate is `((… as string as time) > 1*day) | true`-coalesced so a malformed stamp can never error the relevance.
- **Policy Fixlet lifecycle:** POST plural `fixlets/custom/<site>` on first publish (id → `PipelineConfig.RoleRefFixletId_<rgn>`), PUT singular `fixlet/custom/<site>/<id>` after; a non-2xx sets that region's `Snapshot.Status='failed'` + Event 8020 + `SyncRun.Error_Count++` and continues. PS7 `-SkipCertificateCheck` with a 5.1 trust-all fallback, no `Add-Type`.
- **`Reconcile-LocalRoles.ps1` freshness stamp** = BES client "manual setting" registry key `roleref_<region-lc>_applied` (`value` + `effective date`) + a sidecar JSON (no prior endpoint-script precedent; `-StampRegistryPath` overridable). **07-05 must verify the client honours this key on the production fleet.**
- **`.bes` `Unregister-ScheduledTask` uses `-ErrorAction SilentlyContinue`, not `try/catch`** — a `try { } catch { }` in the ActionScript would add `{{` brace-escaping to a heredoc that has none. `parameter "Region"` is `exists setting … then … else ""`-guarded.
- **`config/task-*.xml` hand-authored** as Task Scheduler 1.2 XML (running `Register-AutomationTasks.ps1` registers real tasks); 07-05 regenerates on the root server. `DeresoRolePublish` shares the helper's Daily 3am trigger with ingest — "after ingest" sequencing deferred to the 07-05 run-book.

### Phase 7 Wave 2 (07-04) Decisions

- **Six-element `<ComputerGroup>` body used as-is** — 07-01's spike confirmed the POST succeeds and round-trips; no reduced-form deviation was needed (unlike the discretion the plan left open for this).
- **`buildRolePolicyTaskXml`'s Task `<Title>` is always `PORTAL_CONFIG.taskTitlePrefix + role`**, not the raw template title — keeps `findBesObjectIdByTitle` able to locate the same Task on every subsequent Publish.
- **`__ROLE__`/`__ASSIGNED_BY__` substitution extended to `<Relevance>` elements** (Rule 1 fix, found during Task 2's own verification before committing) — the plan text only named title/description/postLink/actionScript; a synthetic test fixture with a token in a `<Relevance>` body would have leaked it unsubstituted otherwise. No-op against the real `bes/Assign-RoleMapping.bes` template today.
- **`buildRolePolicyActionXml`'s `DSP_RoleManager_Role` MIME value is derived by stripping `PORTAL_CONFIG.actionTitlePrefix` off the fixed `title` parameter** — the interface signature has no separate `role` parameter; correct as long as 07-07 builds titles as `actionTitlePrefix + role` (the documented D-13 convention).

### Phase 7 Wave 3 (07-05) Decisions

- **`New-RoleGroupRelevance` preserves first-seen insertion order, not an ordinal sort** — corrects the plan's own "ordinal sort" prose against the actual shipped `fixlet_role_manager.ojo` `buildRoleGroupRelevance` (07-04), which de-duplicates but never sorts; the two languages must stay byte-identical, and the dashboard is the already-tested half of that contract.
- **`Sync-RoleGroups.ps1`'s `-BESRootUrl` fallback never references `AutomationState.db` by name** (its own acceptance guard forbids that literal anywhere in the file) — it makes one best-effort `PipelineConfig` lookup against its own `-DatabasePath` (`RolePublish.db`, which carries no such table) and falls back to `https://localhost:52311`, the correct default for a job that always runs as SYSTEM on the BES root server itself.
- **Cross-scope fix for a `psm1` function calling a caller-dot-sourced helper**: promoting the dot-sourced `Invoke-SqliteCommand` to global scope (`Set-Item function:\global:Invoke-SqliteCommand -Value (Get-Item function:\Invoke-SqliteCommand).ScriptBlock -WhatIf:$false`) immediately after dot-sourcing it, before `Import-Module`-ing `RoleGroupRelevance.psm1` — a new pattern this codebase had not needed before (`SnapshotBuild.psm1`/`AxoniousParse.psm1` are both fully pure). Documented in `07-05-SUMMARY.md` for reuse by any future `psm1` module that needs DB access via an injected helper.

### Phase 7 Performance Metrics (pre-rewrite/retired old-model plans)

| Plan | Duration | Tasks | Files | Result |
|------|----------|-------|-------|--------|
| 07-00 | ~35 min | 4 | 20 | 39 Pester + 8 Node green |
| 07-01 | ~130 min | 4 | 5 | 111 Pester + 8 Node green |
| 07-02 | ~95 min | 4 | 12 | 170 Pester + 8 Node green |
| 07-03 | ~115 min | 3 | 11 | 224 Pester + 8 Node green |
| 07-04 | ~70 min | 3 | 8 | 224 Pester + 9 Node green |

### Phase 7 Performance Metrics (new 12-plan Operator-Role-Group model, replanned 2026-09-21)

| Plan | Duration | Tasks | Files | Result |
|------|----------|-------|-------|--------|
| 07-02 | ~7 min | 2 | 3 | 20/20 InitCurrentUserTask.Tests.ps1 green; D-18 schema blocker cleared |
| 07-03 | (see 07-03-SUMMARY.md) | 2 | 2 | 20/20 Upsert-RolePublish.Tests.ps1 green; D-05 audit store built |
| 07-01 (spike) | (see 07-01-SUMMARY.md) | 2 | 2 | Production spike verified; six-element ComputerGroup body confirmed |
| 07-04 | ~35 min | 3 | 2 | 30/30 role_manager.test.js green; all 10 Node suites green |
| 07-05 | ~50 min | 3 | 8 | 32/32 Sync-RoleGroups.Tests.ps1 green; full estate 317 Pester passed / 0 failed / 1 pre-existing NotRun; all 10 Node suites green |

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

**Planned Phase:** 07 (End-to-End Automation) — 12 plans — 2026-09-21T18:25:12.762Z
