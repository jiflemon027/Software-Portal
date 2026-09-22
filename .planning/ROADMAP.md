---
document_type: roadmap
version: 1.0
created: 2026-06-11
status: active
---

# Roadmap — Software Portal v1.0

## Milestone 1: MVP (1 month)

### Phase 1: Copier Foundation

**Goal:** Test, document, and deliver the Copier dashboard so admins can import fixlets from external sources into Dereso Software Portal.

**Requirements:** FR-01 (Fixlet Copy), NFR-01 through NFR-05

**Plans:** 4 plans

Plans:

- [x] 01-01-PLAN.md — BES Fixlet XML test fixtures (valid-minimal, valid-with-script, invalid-missing-title)
- [x] 01-02-PLAN.md — Unit tests for 6 pure JS functions from fixlet_copier.ojo
- [x] 01-03-PLAN.md — Integration tests for BigFix REST API call patterns (7 scenarios)
- [x] 01-04-PLAN.md — Documentation: admin guide, architecture doc, API integration guide

**Deliverables:**

- BigFix dashboard XML for copier interface (existing: Existing Dashboards/fixlet_copier.ojo)
- Test fixtures (tests/fixtures/phase-01/)
- Unit tests (tests/unit/copier.test.js)
- Integration tests (tests/integration/copier.integration.test.js)
- Admin User Guide (docs/admin-guide.md)
- Architecture Document (docs/architecture.md)
- API Integration Guide (docs/api-integration-guide.md)

**Success Criteria:**

- Copier dashboard loads without errors
- Can successfully import test fixlets from external source
- Metadata preserved during import
- Admin receives clear success/error messages

**Estimated Effort:** 1 week
**Dependencies:** None

---

### Phase 2: Modifier (Role-Based Categorization)

**Goal:** Fix, clean, test, and deliver the Modifier dashboard so admins can associate fixlets with user roles, inject role-awareness relevance, and update categories. FR-04 (description update) is deferred to Phase 3.

**Requirements:** FR-02, FR-03, FR-04 (FR-04 deferred to Phase 3 per D-04)

**Plans:** 3 plans

Plans:

- [x] 02-01-PLAN.md — Fix modifier.ojo bugs (duplicate fixletNode, stale cleanedXml), remove dead code, add PORTAL_CONFIG block, wire loadRoleValues() + loadCategoryOptions()
- [x] 02-02-PLAN.md — Test fixtures: tests/fixtures/phase-02/ (no-roles + with-roles BES XML)
- [x] 02-03-PLAN.md — Unit tests (6 functions) + integration tests (PUT round-trip, env-var gated)

**Deliverables:**

- Fixed BigFix dashboard XML: Existing Dashboards/fixlet_modifier.ojo
- Test fixtures: tests/fixtures/phase-02/
- Unit tests: tests/unit/modifier.test.js
- Integration tests: tests/integration/modifier.integration.test.js

**Success Criteria:**

- Modifier dashboard loads without JS errors
- PORTAL_CONFIG block lets admin update roles/categories without touching logic code
- node tests/unit/modifier.test.js exits 0
- node tests/integration/modifier.integration.test.js exits 0 (skip mode without BigFix)
- No duplicate var fixletNode, no stale cleanedXml, no dead functions

**Estimated Effort:** 1.5 weeks
**Dependencies:** Phase 1 (requires fixlets in Dereso portal)

---

### Phase 3: Dispatcher (Rapid Deployment)

**Goal:** Implement the Dispatcher dashboard for rapid, confident deployment of role-aware fixlets to target groups via POST /api/actions with offer-type SourcedFixletAction XML.

**Requirements:** FR-05, FR-06, FR-07 (Target deployment, automatic offers, default options), NFR-01 through NFR-05

**Plans:** 3 plans

Plans:

- [x] 03-01-PLAN.md — Phase-03 test fixtures (valid-fixlet-with-actions.ojo, valid-fixlet-single-action.ojo, sample-action-response.xml) + dispatcher unit tests (buildTargetRelevance, buildExpirationElement, parseActionId, PORTAL_CONFIG)
- [x] 03-02-PLAN.md — fixlet_dispatcher.ojo: scaffold from modifier, PORTAL_CONFIG (defaultExpirationDays + targetGroups), fixlet list (Name/Category/Roles/Site), detail panel, action dropdown, deployment form, buildDeployXml (SourcedFixletAction + IsOffer), API.Post("actions")
- [x] 03-03-PLAN.md — dispatcher.integration.test.js (POST round-trip, NFR-01 timing) + docs/dispatcher-admin-guide.md + regression gate (all 3 unit suites)

**Deliverables:**

- BigFix dashboard XML: Existing Dashboards/fixlet_dispatcher.ojo
- Test fixtures: tests/fixtures/phase-03/
- Unit tests: tests/unit/dispatcher.test.js
- Integration tests: tests/integration/dispatcher.integration.test.js
- Admin guide: docs/dispatcher-admin-guide.md

**Success Criteria:**

- Dispatcher dashboard loads and displays all fixlets from Dereso Software Portal with Name/Category/Roles/Site columns
- Admin can select fixlet, action, target group (from PORTAL_CONFIG list or free-text), and expiration
- Offer automatically created with category and description from selected fixlet (FR-06)
- API.Post("actions") fires SourcedFixletAction XML; success banner shows deployment ID (D-11)
- node tests/unit/dispatcher.test.js exits 0
- node tests/integration/dispatcher.integration.test.js exits 0 in skip mode
- Regression gate: dispatcher + modifier + copier unit tests all pass

**Estimated Effort:** 1.5 weeks
**Dependencies:** Phase 1 & 2 (requires categorized fixlets)

---

## Quality Gates (All Phases)

- ✅ **Code Review**: All code reviewed for correctness, security, maintainability
- ✅ **Testing**: Unit + integration tests for each phase
- ✅ **Performance**: Operations complete within NFR-01 targets
- ✅ **Security**: Admin auth, audit logging, no credential exposure
- ✅ **Documentation**: Inline code comments, user guide, API docs

---

## Milestone 2: Role Awareness

### Phase 4: Role Assigner Dashboard

**Goal:** Build the Role Assigner dashboard (ojo) that allows BigFix admins to manage the RoleAwareness.db role-to-user mapping database on clients — assigning and importing roles via CSV — and surface current assignment state from the BigFix Analysis.

**Requirements:** FR-02 (Role association — extended to user-level), FR-03 (Role-based relevance — enabled by DB-backed assignments)

**Canonical artifacts (prototype):**

- `Dashboard_4_samples/Initialize-RoleDb.ps1` — DB schema (Roles, Users, Map, Overrides tables)
- `Dashboard_4_samples/Dereso SWD.bes` — BigFix Analysis (reads RoleAwareness.db properties from clients)
- `Dashboard_4_samples/role_targeting.csv` — import format prototype (user, computer, role)

**Plans:** 4 plans

Plans:

- [x] 04-01-PLAN.md — CSV fixtures (4 files in tests/fixtures/phase-04/) + role_assigner.test.js stubs + integration test skeleton
- [x] 04-02-PLAN.md — Pure JS utility functions with full unit tests: parseCsv, validateRows, safeB64Encode, chunkString, buildChunkParams, buildAssignActionXml, xmlEscape, PORTAL_CONFIG
- [x] 04-03-PLAN.md — fixlet_role_assigner.ojo: PORTAL_CONFIG, CSV upload/preview/validation, deployAll (one action per role), buildAssignActionScript (embedded PowerShell upsert), Analysis read-only view
- [x] 04-04-PLAN.md — Dereso SWD.bes description finalisation + integration test completion + regression gate (all 4 unit suites)

**Deliverables:**

- BigFix dashboard XML: Existing Dashboards/fixlet_role_assigner.ojo
- Finalised Analysis: Dashboard_4_samples/Dereso SWD.bes
- Test fixtures: tests/fixtures/phase-04/
- Unit tests: tests/unit/role_assigner.test.js
- Integration tests: tests/integration/role_assigner.integration.test.js

**Success Criteria:**

- Role Assigner dashboard loads and shows group selector + CSV upload section
- Admin uploads CSV; preview table shows User/Computer_ID/Role with validation errors highlighted
- Deploy button fires one API.Post("actions") per unique role; success banner shows action ID per role
- Analysis view table populated from mapped_users in r.db via GetRelevance
- node tests/unit/role_assigner.test.js exits 0 (30+ assertions)
- node tests/integration/role_assigner.integration.test.js exits 0 in skip mode
- Regression gate: all 4 unit suites pass

**Estimated Effort:** TBD
**Dependencies:** Phase 2 (Modifier — role names used here must match modifier's PORTAL_CONFIG role list)

---

## Milestone 3: Hardening

### Phase 5: Robustness & Configuration

**Goal:** Harden the Role Awareness system so the Users table stays current without admin intervention, and make the system resilient to common operational scenarios (endpoint rebuild, DB corruption, user churn).

**Requirements:** FR-08 (Automatic User Registration on Logon)

**Plans:** TBD — to be planned via `/gsd-plan-phase 5`

**Deliverables:**

- [x] `Dashboard_4_samples/Init  Current User and UserRole DB.bes` — logon scheduled task (`RoleDB_Maintenance`) deployed alongside DB initialisation (FR-08)
- [x] Admin guide: `docs/role-assigner-admin-guide.md` — covers init task, scheduled task, Role Assigner dashboard
- [x] `Dashboard_4_samples/RoleAwareness_Report.beswrpt` — Web Report: all role-aware fixlets + scoped actions, fixlet-grouped DataTables view (FR-09)
- [x] Valid_to renewal on logon — `Initialize-RoleDb.ps1` v3 extends active, non-overridden `Map` rows to `now + ValidityMonths` on every `RoleDB_Maintenance` run
- [x] Redeploy-safe schema migration — the init task's script-write + `Initialize-RoleDb.ps1` run is unconditional (previously gated on `RoleAwareness.db` not existing, so redeploying to an already-initialised endpoint was a no-op); re-running/redeploying the task now always migrates an existing DB to the current schema in place, preserving `Map`/`Users`/`Roles` data. Scheduled task registration remains separately gated on "doesn't already exist"
- [ ] Configurable role list and validity defaults documented
- [ ] Guidance on re-initialisation after endpoint rebuild

**Phase 5 Feature: Automatic User Registration (FR-08) — COMPLETE**

The init task now registers a Windows Scheduled Task on every managed endpoint it deploys to.
This superseded an earlier `Dereso\UpdateUserOnLogon` design (a dedicated lightweight logon
script) in favor of reusing `Initialize-RoleDb.ps1` itself, rerun on every logon — every step
in it is already idempotent, so a rerun on an initialised endpoint just walks through and
skips everything except the current-user upsert and the Valid_to renewal, both meant to run
every time:

| Item | Detail |
|------|--------|
| Task name | `RoleDB_Maintenance` |
| Trigger | At logon (any user) |
| Runs as | SYSTEM |
| Script | `Initialize-RoleDb.ps1` (same file the init task itself runs — no separate logon script) |
| User detection | `Win32_Process (explorer.exe) → GetOwner`, one-shot (no retry/poll loop) |
| On first logon | `INSERT OR REPLACE INTO Users (UserID, LastSeen)` |
| On repeat logon | Same upsert, refreshes `LastSeen` |
| Valid_to renewal | Every logon, extends this user's `Active=1, Locked_by_Override=0` `Map` rows to `now + ValidityMonths` (default 6); `Locked_by_Override=1` rows are never touched |
| Idempotent | Yes — registration is skipped once `RoleDB_Maintenance` already exists (relevance-gated, not `/F`-forced; a path change after client reinstall requires removing the task before redeploying) |

**Success Criteria:**

- Init task writes `Scheduled_RoleDb_mnc.ps1` and registers `RoleDB_Maintenance` on each endpoint
- Task fires at each user logon, updates `Users.LastSeen`, and renews `Valid_to` on that user's active mappings without admin action
- `Users` table is populated before the Role Assigner runs its first import
- Re-running/redeploying the init action is safe and self-healing: it always rewrites the
  scripts and reruns `Initialize-RoleDb.ps1`, which migrates an existing `RoleAwareness.db` to
  the current schema without touching existing rows — not just a first-run-only initialiser

**Estimated Effort:** Partially complete — FR-08 implemented, including Valid_to renewal. Remaining: configurable role list/validity defaults doc, re-initialisation guidance.
**Dependencies:** Phase 4 (Role Assigner — DB schema must exist)

---

### Phase 6: Fixlet Update Tracker

**Goal:** Build the Fixlet Update Tracker dashboard (`fixlet_update_tracker.ojo`) that scans configurable source sites for newer versions of portal fixlets, enables admin-driven batch copy with automatic category/role transfer, stamps superseded fixlets, and surfaces net-new products in a "New Arrivals" tab.

**Requirements:** FR-10 (Fixlet Version Update Tracking), NFR-01 through NFR-05

**Plans:** 4 plans

Plans:

- [x] 06-00-PLAN.md — Wave 0: CATEGORY_MAP generator script + 4 XML test fixtures + unit/integration test stubs
- [x] 06-01-PLAN.md — Wave 1: Pure JS functions (stripVersion, extractVersion, compareVersions, lookupCategory, buildScanResults) + full unit test suite (20+ assertions) + generate and stage CATEGORY_MAP
- [x] 06-02-PLAN.md — Wave 2: fixlet_update_tracker.ojo (OJO scaffold, PORTAL_CONFIG+CATEGORY_MAP, scan engine, two-tab table UI, preview panel, copy engine with 4-step sequential callback, results panel)
- [x] 06-03-PLAN.md — Wave 3: Integration tests (fixture structure assertions + BIGFIX-gated API round-trips) + full regression gate (all 5 unit suites)

**Deliverables:**

- BigFix dashboard XML: Existing Dashboards/fixlet_update_tracker.ojo
- Build script: scripts/generate_category_map.js
- Test fixtures: tests/fixtures/phase-06/
- Unit tests: tests/unit/update_tracker.test.js
- Integration tests: tests/integration/update_tracker.integration.test.js

**Success Criteria:**

- `node tests/unit/update_tracker.test.js` exits 0 (31 assertions)
- `node tests/integration/update_tracker.integration.test.js` exits 0 in skip mode (6 GROUP A fixture assertions pass, 2 GROUP B API tests skip)
- `node scripts/generate_category_map.js` runs without error and produces valid JS
- Regression gate: all 5 unit suites pass (161 total assertions: copier 45, modifier 30, dispatcher 22, role_assigner 33, update_tracker 31)
- `fixlet_update_tracker.ojo` contains `PORTAL_CONFIG.sourceSites`, `CATEGORY_MAP`, `copyNextItem`, `buildCopyXml`, `buildSupersededXml`, `scanNextSite`, `renderUpdatesTable`, `renderArrivalsTable`, `switchTab`

**Estimated Effort:** TBD
**Dependencies:** Phases 1–5 complete; `Dashboard_4_samples/software_categorized.csv` present for CATEGORY_MAP generation

---

## Milestone 4: Automation

### Phase 7: End-to-End Automation

**Goal:** Replace manual role assignment with the Operator-Role-Group model — an admin
maintains a flat username list per role in a new dashboard (`fixlet_role_manager.ojo`);
publishing a role (re)generates that role's automatic Computer Group ("exactly one of the
role's usernames logged on") and (re)deploys a policy action that upserts `RoleAwareness.db`
via the already-built `Assign-RoleMapping.ps1`/`.bes`. Also wires the content pipeline
(scheduled fixlet copy + repository pre-staging), unchanged since 2026-08-01.

> **Rewritten 2026-09-21.** The Axonius ingest → reference DB → per-region snapshot →
> endpoint reconcile pipeline described below (07-00 through 07-04, all real, tested,
> committed work) is **retired** — never run against production, found too heavy to
> operate. See `.planning/phases/07-automation/07-CONTEXT.md` for the full rationale and
> the new decisions (D-01..D-18). The completed-work history is kept for the record;
> the Plans list below is being replanned from scratch against the new model.

**Requirements:** FR-02, FR-03, FR-08, NFR-02, NFR-03, NFR-05 (no new FR/NFR IDs — FR-01/FR-10's content pipeline is unchanged and out of scope for this rewrite; FR-05/FR-06/FR-07's Dispatcher stays manual).

**Plans:** 12 plans in 10 waves (replanned 2026-09-21 for the Operator-Role-Group model; revised after plan-check 2026-09-21)

Plans:
**Wave 1**

- [x] 07-01-PLAN.md — Wave 1: live ComputerGroup REST spike + `set of (...)` relevance probe + gpbfs audit for retired-pipeline leftovers and `sqlite3.exe` (blocking checkpoint) — ✅ built + production-verified 2026-09-22. Six-element `<ComputerGroup>` body accepted, no live Axonius-era artefacts on gpbfs, sqlite3.exe 3.53.1 present. Corrected a false-PASS in the original findings (Check B) caused by two runbook bugs (byte[]→string cast, narrow error-match regex), both fixed; the real Check B failure (`logged on users` undefined via session relevance) doesn't affect 07-04, which only ever uses this expression as client relevance.
- [x] 07-02-PLAN.md — Wave 1: task 787 D-18 fix — strip the retired `Reconcile-LocalRoles.ps1` wiring, keep the v4 `Map` migration, lock it with `InitCurrentUserTask.Tests.ps1` — ✅ built 2026-09-21
- [x] 07-03-PLAN.md — Wave 1: root-server audit store — `Upsert-RolePublish.ps1` (`RolePublishRun`/`RoleUsers` DDL + parameterized snapshot write) + Pester — ✅ built 2026-09-21, DDL/users-array bug found + fixed 2026-09-21 (`2247a91`)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 07-04-PLAN.md — Wave 2: `fixlet_role_manager.ojo` foundation — OJO shell, `PORTAL_CONFIG`, shared helpers, and the pure relevance/ComputerGroup/Task/SingleAction builders + `role_manager.test.js` — ✅ built 2026-09-22, 30/30 assertions green, all 10 Node suites green

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 07-05-PLAN.md — Wave 3: D-06 drift check — `RoleGroupRelevance.psm1` + `Sync-RoleGroups.ps1` + cross-language golden fixture + `DeresoRoleGroupSync` daily task against `RolePublish.db` — ✅ built 2026-09-22, 32/32 Sync-RoleGroups.Tests.ps1 assertions green, full estate 317 Pester passed / 0 failed / 1 pre-existing NotRun, all 10 Node suites green

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 07-06-PLAN.md — Wave 4: Roles tab — username editor, D-02 autocomplete, D-10 scope filter, and D-13 Save via a root-server-targeted audit-write SingleAction

**Wave 5** *(blocked on Wave 4 completion)*

- [ ] 07-07-PLAN.md — Wave 5: Publish prerequisites — SHA1-pinned endpoint-script staging into the Custom Repository + per-role Task find-or-create

**Wave 6** *(blocked on Wave 5 completion)*

- [ ] 07-08-PLAN.md — Wave 6: per-role Publish — Computer Group find-or-create, Task refresh, policy action deploy, previous-action stop, four-step status reporting

**Wave 7** *(blocked on Wave 6 completion)*

- [ ] 07-09-PLAN.md — Wave 7: D-16 Analysis tab — live `RoleAwareness.db` mappings plus configured-vs-actual reconciliation

**Wave 8** *(blocked on Wave 7 completion)*

- [ ] 07-10-PLAN.md — Wave 8: D-15 archival move — `git mv` the retired dashboards/scripts/config/tests into `archive/`, re-base the frozen suites, write `tests/archive/README.md`

**Wave 9** *(blocked on Wave 8 completion)*

- [ ] 07-11-PLAN.md — Wave 9: dead-reference strip + docs — remove the dead task-table/`PipelineConfig`/`-WhatIf` audit rows, fix the live suites, rewrite the admin guides

**Wave 10** *(blocked on Wave 9 completion)*

- [ ] 07-12-PLAN.md — Wave 10: production verification — UAT checklist plus blocking checkpoints for the 787 redeploy and the end-to-end pilot mapping

Plans (pre-rewrite history — retired 2026-09-21, archived per 07-CONTEXT.md D-15):

- [x] ~~07-00-PLAN.md — Wave 0 Foundation: combined `AutomationState.db` schema + `Get-BigFixCredential.ps1` (AKeyless) + endpoint `Map` migration + logon-rework commit + Phase 7 test fixtures and Pester harness~~ — ✅ built 2026-08-30, retired 2026-09-21
- [x] ~~07-01-PLAN.md — Wave 1 Ingest: `Import-AxoniousExport.ps1` streaming CSV → RefUser/UserRole, username coalesce, GroupRoleMap matcher, age-out marking, SyncRun logging~~ — ✅ built 2026-08-30, retired 2026-09-21
- [x] ~~07-02-PLAN.md — Wave 2 Publish + distribute + reconcile: `Publish-RoleSnapshot.ps1` per-region JSON + `.sha1` + daily policy-Fixlet re-PUT, `RoleRef-Policy-template.bes`, `Reconcile-LocalRoles.ps1`, `RoleDB_Maintenance` rewiring, scheduled tasks~~ — ✅ built 2026-08-30, retired 2026-09-21
- [x] ~~07-03-PLAN.md — Wave 3 Content pipeline: `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`, `ContentSyncCore.psm1`, scheduled tasks~~ — ✅ built 2026-08-30, **content pipeline logic itself is unchanged and stays live** (only the Wave label/plan is retired, not the deliverable)
- [x] ~~07-04-PLAN.md — Wave 4 Dashboards: `fixlet_role_admin.ojo` (GroupRoleMap/Region/Reference-DB), `fixlet_automation_monitor.ojo`, assigner Source/Region columns~~ — ✅ built 2026-08-30; `fixlet_role_admin.ojo` retired (replaced by `fixlet_role_manager.ojo`), `fixlet_automation_monitor.ojo` (content-only) stays live
- [ ] ~~07-05-PLAN.md — Wave 5 Integration + rollout: production-fleet verification and pilot-region sign-off~~ — paused 2026-09-09, superseded by the rewrite; no production verification of the old pipeline will happen

**Deliverables (new model — see `07-CONTEXT.md` for full detail):**

- `Existing Dashboards/fixlet_role_manager.ojo` — new consolidated dashboard (replaces `fixlet_role_assigner.ojo` + `fixlet_role_admin.ojo`, both archived)
- Computer Group + policy-action generator (per-role "exactly one of N logged on" relevance, built from `bes/Assign-RoleMapping.bes`)
- Root-server `RoleUsers` SQLite audit table + a root-server-targeted write action (reusing `fixlet_dispatcher.ojo`'s `stageOnRootServer` pattern)
- Task 787 (`Init Current User and UserRole DB`) redeployed with the D-18 `Map` schema migration (hard prerequisite)
- `scripts/Assign-RoleMapping.ps1` / `bes/Assign-RoleMapping.bes` — already built 2026-09-11, reused as-is
- Content pipeline deliverables from 07-03/07-04 (`Invoke-ContentSync.ps1`, `Stage-Repository.ps1`, `fixlet_automation_monitor.ojo`) — unchanged, stay live
- `docs/automation-admin-guide.md` — updated for the new model

**Success Criteria:**

- An admin can add/remove a username from a role in `fixlet_role_manager.ojo` and Publish that one role without touching any other role's live Computer Group/action
- A role's Computer Group admits a device only when exactly one of that role's usernames is the logged-on user; the policy action upserts `RoleAwareness.db` `Map` via the existing D-12 discipline, honouring `Locked_by_Override = 1`
- A user holding multiple roles gets all of them mapped correctly; two different-role users sharing a machine both map independently
- Content sync (unchanged) still detects new/updated fixlets, transfers category + `Associated_Roles`, stamps `X-Superseded-By` idempotently, and stages SHA1-verified installers
- Task 787 redeployed with the D-18 schema fix; `Assign-RoleMapping.ps1` succeeds against a real endpoint

**Estimated Effort:** 11 plans across 8 waves; 2 blocking human-verify checkpoints (07-01 spike, 07-11 production UAT)
**Dependencies:** Phases 1–6 complete; `scripts/Assign-RoleMapping.ps1`/`bes/Assign-RoleMapping.bes` (built 2026-09-11); `sqlite3.exe` provisioned on the BES root server; task 787 schema fix

---

## Timeline

| Phase | Duration | Start | End | Owner |
|-------|----------|-------|-----|-------|
| Phase 1: Copier | 1 week | Week 1 | Week 1 | TBD |
| Phase 2: Modifier | 1.5 weeks | Week 2 | Week 3 | TBD |
| Phase 3: Dispatcher | 1.5 weeks | Week 3 | Week 4 | TBD |
| Testing & Review | 0.5 weeks | Week 4 | Week 4 | TBD |
| **MVP Complete** | — | — | **End Week 4** | — |
| Phase 4: Role Assigner | 2 weeks | Week 5 | Week 6 | TBD |
| Phase 5: Robustness | 1 week | Week 7 | Week 7 | TBD |
| Phase 6: Update Tracker | 1.5 weeks | Week 8 | Week 9 | TBD |
| Phase 7: Automation | 3–4 weeks | Week 10 | Week 13 | TBD |
| **v1.0 Full Release** | — | — | **End Week 13** | — |

---

## Success Metrics

- ✅ All 3 dashboards built and UAT verified
- ✅ < 5 min per complete workflow (copy → modify → deploy)
- ✅ Zero critical issues in code review
- ✅ Admin guide covers all dashboards
- ✅ Dynamic group targeting confirmed working (member of group &lt;id&gt; of site)

---

## Notes

- BigFix instance must be accessible throughout development and testing
- Role list must be finalized before Phase 2 begins
- Default deployment options require sign-off from ops team before Phase 3 deploy
- Consider feature flags for gradual rollout to production
