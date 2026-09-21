---
phase: 07
slug: automation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-21
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
| TBD | TBD | 0 | D-09 (relevance) | — | `buildRoleGroupRelevance()` produces the exact "exactly one of N logged on" string, including the empty-list `"false"` special case and `"` escaping | unit | `node tests/unit/role_manager.test.js` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0 | D-10 (scope filter) | — | `buildRoleGroupRelevance()` correctly ANDs the `member of group` clause only when a scope group is supplied | unit | `node tests/unit/role_manager.test.js` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0 | D-07/Pattern 1 (Group XML) | — | `buildComputerGroupXml()` emits all schema elements in a parseable order; `Relevance` is CDATA-wrapped and `]]>`-safe | unit | `node tests/unit/role_manager.test.js` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0 | D-13/Pattern 3 (Action XML) | — | `SingleAction` element order (`Title→Relevance→ActionScript→Settings→Target`), `Reapply`/`ReapplyInterval` present (D-11), `IsOffer=false` | unit | `node tests/unit/role_manager.test.js` | ❌ W0 | ⬜ pending |
| TBD | TBD | 0 | D-05/Pattern 5 (audit schema) | — | `RoleUsers` DDL is idempotent (`CREATE TABLE IF NOT EXISTS`); a second init run against an already-initialised DB makes no destructive changes | Pester | `Invoke-Pester tests/pester/Initialize-RoleUsersDb.Tests.ps1` (new) | ❌ W0 | ⬜ pending |
| TBD | TBD | 0 | D-18/Pattern 6 (task 787 diff) | — | The corrected `.bes` no longer contains `Reconcile-LocalRoles.ps1` prefetch/copy/scheduled-task-action text, while the v4 Map migration block is untouched | Pester | `Invoke-Pester tests/pester/InitCurrentUserTask.Tests.ps1` (new) | ❌ W0 | ⬜ pending |
| TBD | TBD | 0 | D-04/D-12 (multi-role upsert, regression) | — | `Assign-RoleMapping.ps1`'s existing D-12 discipline still passes against a DB migrated by the corrected task-787 script; `UNIQUE(UserID, Role)` allows multiple roles per user | Pester | reuse/extend `tests/fixtures/phase-07/roleawareness-v2.db` smoke test | ⚠️ W0 — confirm automated Pester coverage exists beyond the manual `Assign-RoleMapping_test.ps1` wrapper | ⬜ pending |
| TBD | TBD | — | Regression | — | Existing dashboard unit suites still pass while their `.ojo` subjects are archived (D-15) | unit | full existing Node suite | ✓ existing — plan must decide fate of `role_admin.test.js`/`role_assigner.test.js` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky. Task IDs filled in once PLAN.md files exist.*

---

## Wave 0 Requirements

- [ ] `tests/unit/role_manager.test.js` — new file, covers D-09/D-10 relevance builder + the
      Computer Group/Action XML builders (no existing coverage — brand-new dashboard)
- [ ] `tests/pester/Initialize-RoleUsersDb.Tests.ps1` — new file, covers the root-server
      `RoleUsers` audit table's DDL idempotency (D-05)
- [ ] `tests/pester/InitCurrentUserTask.Tests.ps1` — new file, covers the task 787 diff: confirm
      `Reconcile-LocalRoles.ps1` wiring is removed, v4 Map migration is intact (D-18)
- [ ] Confirm whether `scripts/Assign-RoleMapping.ps1` has any existing **automated** (Pester)
      regression coverage beyond the manual `Assign-RoleMapping_test.ps1` smoke wrapper — if
      not, add one before relying on D-12 behavior surviving the task-787 redeploy
- [ ] Decide and document the fate of `tests/unit/role_admin.test.js` / `role_assigner.test.js`
      when their `.ojo` subjects move to `archive/` (delete together, or retain as frozen
      snapshots)
- [ ] Audit whether anything from the paused Axonius pipeline is actually live on `gpbfs`
      before archiving source scripts (STATE.md indicates the 07-05 production checkpoint
      never ran, but this must be verified, not assumed)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|--------------------|
| Live `ComputerGroup` REST creation against the real root server | D-07 | The exact accepted element combination for `POST computergroups/{site}` has only been verified against official docs + one third-party working example, not this project's specific BigFix version | Hand-POST one throwaway automatic Computer Group against `gpbfs` (or the 9-computer lab), confirm it appears in the console and its relevance evaluates as expected, then delete it |
| Task 787 redeploy on an already-provisioned endpoint | D-18 | Requires a real endpoint with an existing pre-migration `RoleAwareness.db` | Redeploy task 787; confirm `RoleDB_Maintenance` reruns `Initialize-RoleDb.ps1` only (not the removed `Reconcile-LocalRoles.ps1` step) and the Map migration applies without data loss |
| End-to-end role publish + assignment on a pilot endpoint | D-01..D-13 | Requires a logged-on test user and the live fleet to observe the policy action actually fire | Add a test username to a role, Publish, log that user into a non-root endpoint, confirm the Computer Group admits it, the policy action runs, and `RoleAwareness.db` `Map` gets the correct row |
| Whether stop-and-recreate vs. create-once is the right redeploy semantics for the per-role policy action (Open Question 1 from RESEARCH.md) | D-13 | Design question with audit-trail and BES-object-accumulation trade-offs not resolvable by a test | Resolve during planning/discuss-phase before Wave 2 implementation |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
