---
phase: 07
slug: automation
status: ready
nyquist_compliant: true
wave_0_complete: true
created: 2026-09-21
updated: 2026-09-21
supersedes: "2026-08-29 draft (Axonius reference-DB pipeline design, now retired)"
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `07-RESEARCH.md` § Validation Architecture (2026-09-21 rewrite for the
> Operator-Role-Group model).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in `assert`/`fs` (JS pure-function extraction tests) + Pester 5.7.1 (PowerShell) |
| **Config file** | None for Node (`node <file>.test.js` run directly). None for Pester beyond `tests/pester/README.md`'s documented `SQLDIR` env-var contract. |
| **Quick run command** | `node tests/unit/role_manager.test.js` |
| **Full suite command** | `node tests/unit/*.test.js && pwsh -c "Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI"` |
| **Estimated runtime** | ~30-60 seconds |

---

## Sampling Rate

- **After every task commit:** Run the one relevant `*.test.js` or `*.Tests.ps1` file (< 30s)
- **After every plan wave:** Full Node suite + full non-Slow Pester suite
- **Before `/gsd:verify-work`:** Full suite must be green, plus the live-environment spikes
  from Open Questions 2-3 below (not automatable — require the real BES root server) signed
  off as a `checkpoint:human-verify`
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-04 | 07-04 | 2 | D-09 (relevance) | T-07-04-* | `buildRoleGroupRelevance()` produces the exact "exactly one of N logged on" string, including the empty-list `"false"` special case and `"` escaping | unit | `node tests/unit/role_manager.test.js` | ✅ planned | ⬜ pending execution |
| 07-04 | 07-04 | 2 | D-10 (scope filter) | T-07-04-* | `buildRoleGroupRelevance()` correctly ANDs the `member of group` clause only when a scope group is supplied | unit | `node tests/unit/role_manager.test.js` | ✅ planned | ⬜ pending execution |
| 07-04 | 07-04 | 2 | D-07/Pattern 1 (Group XML) | T-07-04-* | `buildComputerGroupXml()` emits all schema elements in a parseable order; `Relevance` is CDATA-wrapped and `]]>`-safe | unit | `node tests/unit/role_manager.test.js` | ✅ planned | ⬜ pending execution |
| 07-04 | 07-04 | 2 | D-13/Pattern 3 (Action XML) | T-07-04-* | `SingleAction` element order (`Title→Relevance→ActionScript→Settings→Target`), `Reapply`/`ReapplyInterval` present (D-11), `IsOffer=false` | unit | `node tests/unit/role_manager.test.js` | ✅ planned | ⬜ pending execution |
| 07-03 | 07-03 | 1 | D-05/Pattern 5 (audit schema) | T-07-03-* | `RolePublishRun`/`RoleUsers` DDL is idempotent (`CREATE TABLE IF NOT EXISTS`); a second init run against an already-initialised DB makes no destructive changes | Pester | `Invoke-Pester tests/pester/Upsert-RolePublish.Tests.ps1` | ✅ planned | ⬜ pending execution |
| 07-02 | 07-02 | 1 | D-18/Pattern 6 (task 787 diff) | T-07-02-* | The corrected `.bes` no longer contains `Reconcile-LocalRoles.ps1` prefetch/copy/scheduled-task-action text, while the v4 Map migration block is untouched | Pester | `Invoke-Pester tests/pester/InitCurrentUserTask.Tests.ps1` | ✅ planned | ⬜ pending execution |
| 07-12 | 07-12 | 10 | D-04/D-12 (multi-role upsert, regression) | T-07-12-* | `Assign-RoleMapping.ps1`'s existing D-12 discipline still passes against a DB migrated by the corrected task-787 script; `UNIQUE(UserID, Role)` allows multiple roles per user | manual (production UAT) | 07-12's UAT checklist section D | ✅ planned | ⬜ pending execution |
| 07-10/07-11 | 07-10/07-11 | 8-9 | Regression | — | Existing dashboard unit suites' fate is decided, not left orphaned (D-15) — `role_admin.test.js`/`role_assigner.test.js` move to `tests/archive/unit/` as frozen snapshots, not deleted, not left in the default run | unit | full existing Node suite (archived suites excluded) | ✅ planned | ⬜ pending execution |

*Status: ⬜ pending execution · ✅ green · ❌ red · ⚠️ flaky. All 12 plans exist and passed `gsd-plan-checker` verification (2026-09-21, 0 blockers). "Pending execution" means `/gsd:execute-phase 07` has not yet run these tasks.*

---

## Wave 0 Requirements

All Wave 0 gaps identified during research are now assigned to a plan:

- [x] `tests/unit/role_manager.test.js` — assigned to plan 07-04, covers D-09/D-10 relevance
      builder + the Computer Group/Action XML builders (no prior coverage — brand-new dashboard)
- [x] `tests/pester/Upsert-RolePublish.Tests.ps1` — assigned to plan 07-03, covers the
      root-server `RolePublishRun`/`RoleUsers` audit table's DDL idempotency (D-05)
- [x] `tests/pester/InitCurrentUserTask.Tests.ps1` — assigned to plan 07-02, covers the task
      787 diff: confirms `Reconcile-LocalRoles.ps1` wiring is removed, v4 Map migration is
      intact (D-18)
- [x] `scripts/Assign-RoleMapping.ps1` automated coverage gap — resolved: plan 07-12's UAT
      checklist section D exercises D-12 live against a task-787-migrated endpoint; this is a
      manual-only verification (see below), not a Pester gap, since it requires a real endpoint
- [x] Fate of `tests/unit/role_admin.test.js` / `role_assigner.test.js` — decided in plan
      07-10/07-11: moved to `tests/archive/unit/` as frozen snapshots (not deleted, not left in
      the default run), alongside their archived `.ojo` subjects
- [x] Audit of live Axonius-pipeline artifacts on `gpbfs` — assigned to plan 07-01's Wave-1
      blocking spike (Check C) before any archiving proceeds

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|--------------------|
| Live `ComputerGroup` REST creation against the real root server | D-07 | The exact accepted element combination for `POST computergroups/{site}` has only been verified against official docs + one third-party working example, not this project's specific BigFix version | Hand-POST one throwaway automatic Computer Group against `gpbfs` (or the 9-computer lab), confirm it appears in the console and its relevance evaluates as expected, then delete it |
| Task 787 redeploy on an already-provisioned endpoint | D-18 | Requires a real endpoint with an existing pre-migration `RoleAwareness.db` | Redeploy task 787; confirm `RoleDB_Maintenance` reruns `Initialize-RoleDb.ps1` only (not the removed `Reconcile-LocalRoles.ps1` step) and the Map migration applies without data loss |
| End-to-end role publish + assignment on a pilot endpoint | D-01..D-13 | Requires a logged-on test user and the live fleet to observe the policy action actually fire | Add a test username to a role, Publish, log that user into a non-root endpoint, confirm the Computer Group admits it, the policy action runs, and `RoleAwareness.db` `Map` gets the correct row |
| Verify the live-fleet Publish flow actually behaves as the resolved create-new-then-stop-previous semantics (RESEARCH.md Open Question 1, resolved 2026-09-21, implemented in plan 07-08) | D-13 | The choice itself is resolved at plan time (not a design question anymore); only the live-endpoint behavior needs confirming | Covered by plan 07-12's UAT checklist section D — confirm exactly one Open action per role after a re-publish |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-09-21 (plan-checker verification passed, 0 blockers, all 12 plans)
