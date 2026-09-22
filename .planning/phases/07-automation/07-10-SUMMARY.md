---
phase: 07-automation
plan: 10
subsystem: testing
tags: [git-mv, archive, axonius, teardown, pester, node]

# Dependency graph
requires:
  - phase: 07-automation (plan 07-01)
    provides: "Check C production-verified confirmation that no live Axonius-era scheduled task, RoleRef* fixlet or computer group exists on gpbfs -- the ground truth this plan's archival decision depends on"
  - phase: 07-automation (plan 07-09)
    provides: "fixlet_role_manager.ojo's Analysis tab, which fully duplicates the Analysis views of both files archived here, clearing the reviewer flag from 07-09-SUMMARY.md"
provides:
  - "Every retired Axonius reference-DB pipeline artefact (2 dashboards, 5 scripts/modules, 1 .bes template, 3 config files, 9 test suites incl. the shared Assert-SnapshotShape.ps1 helper) moved to archive/ subfolders via git mv, history intact"
  - "tests/archive/README.md -- the frozen/not-maintained/excluded-from-default-run record required before 07-11 and 07-12 can proceed"
  - "Confirmation (re-run of 07-01 Check C's LIVE ARTEFACTS TO REMOVE question): none found -- nothing for 07-12's checkpoint to stop"
affects: ["07-11 (strips the now-dead Import-AxoniousExport.ps1/Publish-RoleSnapshot.ps1/Reconcile-LocalRoles.ps1 references out of Invoke-WhatIfAudit.ps1's $Scripts table and WhatIfAudit.Tests.ps1's assertions -- this plan surfaced exactly which references are dead and left them untouched on purpose)", "07-12 (production checkpoint reads this summary's LIVE ARTEFACTS TO REMOVE section, which is empty)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Re-basing a moved Pester/Node test suite one directory deeper: every $PSScriptRoot/__dirname repo-root computation gains one additional '..' segment, and every explicit reference to a co-moved subject/fixture/cross-suite-helper is repointed at its new archive/ path in the same pass"

key-files:
  created:
    - "tests/archive/README.md"
  modified:
    - "Existing Dashboards/archive/fixlet_role_admin.ojo (moved, untouched)"
    - "Existing Dashboards/archive/fixlet_role_assigner.ojo (moved, untouched)"
    - "scripts/archive/{Import-AxoniousExport.ps1,Publish-RoleSnapshot.ps1,Reconcile-LocalRoles.ps1,AxoniousParse.psm1,SnapshotBuild.psm1} (moved, untouched)"
    - "bes/archive/RoleRef-Policy-template.bes (moved, untouched)"
    - "config/archive/{GroupRoleMap.json,task-DeresoRoleIngest.xml,task-DeresoRolePublish.xml} (moved, untouched)"
    - "tests/archive/unit/{role_admin,role_assigner}.test.js (moved + re-based)"
    - "tests/archive/pester/{AxoniousParse,GroupRoleMap,Import-AxoniousExport,Publish-RoleSnapshot,Reconcile-LocalRoles,RoleRefPolicyBes}.Tests.ps1 (moved + re-based)"
    - "tests/archive/pester/Assert-SnapshotShape.ps1 (moved, untouched -- dot-sourced helper, not a suite)"

key-decisions:
  - "Both .psm1 modules (AxoniousParse.psm1, SnapshotBuild.psm1) moved along with their drivers per the plan's own instruction, after a repo-wide grep confirmed zero live importers -- scripts/RoleGroupRelevance.psm1 only follows SnapshotBuild.psm1's naming/structure convention in a comment, it does not Import-Module it, and scripts/Invoke-WhatIfAudit.ps1's one SnapshotBuild.psm1 reference is a -SnapshotModulePath argument value passed to the now-archived Publish-RoleSnapshot.ps1 itself, not a direct import of the module by Invoke-WhatIfAudit.ps1's own code."
  - "scripts/Invoke-WhatIfAudit.ps1 and tests/pester/WhatIfAudit.Tests.ps1 left untouched per the plan's explicit instruction and acceptance criteria, even though this predictably breaks WhatIfAudit.Tests.ps1 (Audited script missing: scripts\\Import-AxoniousExport.ps1) -- 07-11's own plan text/threat-model (T-07-11-01) names this exact fix as its own scope, one wave later."
  - "Two pre-existing archived-suite test failures (RoleRefPolicyBes.Tests.ps1's policy-Fixlet lifecycle tests) were left as recorded failures, not fixed -- Publish-RoleSnapshot.ps1's own internal $PSScriptRoot-relative default for the template path no longer resolves after the script itself moved one directory deeper into scripts/archive/, and the plan explicitly designates archived-script internal defaults as out of scope ('a failure is acceptable and must simply be recorded; these are not gated'). Fixing it would mean editing a frozen/not-maintained archived script's own logic, which contradicts the archive's stated purpose."
  - "The plan's acceptance-criteria text asserting `ls tests/unit/*.test.js | wc -l` should return 7 does not match the actual, correct post-move count of 8 -- the plan's own explicit 'do not move' list for tests/unit names exactly 8 files (automation_monitor, copier, dispatcher, fixlet_console, modifier, open_deployments, role_manager, update_tracker), and 8 is what remains. The arithmetic in the acceptance-criteria prose (9 originals - 2 archived + role_manager) miscounts; the true pre-move baseline was 10 unit suites (per 07-09-SUMMARY's 'all 10 Node suites green'), and 10 - 2 = 8, matching both the do-not-move list and the observed count. Documented here rather than silently 'fixed' since the do-not-move list is unambiguous and correct."

requirements-completed: [NFR-05]

# Metrics
duration: ~25min
completed: 2026-09-22
---

# Phase 07 Plan 10: Archive the Retired Axonius Reference-DB Pipeline (D-15) Summary

**Every retired Axonius-era dashboard, script, `.bes` template, config file and test suite (20 files total) moved into `archive/` subfolders via `git mv` with full history intact, plus a new `tests/archive/README.md` recording what/why/where -- clearing the way for 07-11's live-reference cleanup and 07-12's production checkpoint.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-09-22T23:10:00Z (approx, after context loading)
- **Completed:** 2026-09-22T23:36:51Z
- **Tasks:** 1/1
- **Files modified:** 21 (20 moved + 1 new)

## Accomplishments

- **Dashboards → `Existing Dashboards/archive/`:** `fixlet_role_admin.ojo`, `fixlet_role_assigner.ojo` -- the pre-existing `.fxf`/`.html` files already in that folder are untouched.
- **Scripts/modules → `scripts/archive/`:** `Import-AxoniousExport.ps1`, `Publish-RoleSnapshot.ps1`, `Reconcile-LocalRoles.ps1`, `AxoniousParse.psm1`, `SnapshotBuild.psm1`. Both `.psm1` files confirmed to have zero live importers before moving (see key-decisions).
- **BES template → `bes/archive/`:** `RoleRef-Policy-template.bes`.
- **Config → `config/archive/`:** `GroupRoleMap.json`, `task-DeresoRoleIngest.xml`, `task-DeresoRolePublish.xml`.
- **Tests → `tests/archive/unit/` and `tests/archive/pester/`:** `role_admin.test.js`, `role_assigner.test.js`; `AxoniousParse.Tests.ps1`, `GroupRoleMap.Tests.ps1`, `Import-AxoniousExport.Tests.ps1`, `Publish-RoleSnapshot.Tests.ps1`, `Reconcile-LocalRoles.Tests.ps1`, `RoleRefPolicyBes.Tests.ps1`, `Assert-SnapshotShape.ps1` (dot-sourced helper). Every suite's repo-root computation gained one additional `..` segment, and every reference to a co-moved subject/cross-suite-helper (script/module/`.bes`/config path) was re-pointed at its new `archive/` location in the same pass.
- `tests/archive/README.md` created: states what was archived and when (2026-09-21, the Phase 7 Operator-Role-Group rewrite), that these are frozen historical snapshots excluded from the default `Invoke-Pester -Path tests/pester` and `node tests/unit/*.test.js` runs, a full subject-relocation table, that fixtures still resolve from the live `tests/fixtures/phase-07/`, and that they are not maintained.
- Git status confirms every move landed as a rename (`R`/`RM`), not a delete+add pair -- `git log` shows `(100%)` similarity for all 20 files including the re-based ones.

## LIVE ARTEFACTS TO REMOVE

**None.** Re-confirming 07-01's Check C (`07-SPIKE-FINDINGS.md`): the production spike against `gpbfs` on 2026-09-21 found no `DeresoRoleIngest`/`DeresoRolePublish` scheduled tasks and zero `RoleRef*`-matching fixlets or computer groups. There is nothing live on the root server for plan 07-12's checkpoint to stop.

## Per-suite archived-run outcomes

Each archived suite was run once after re-basing (Node suites via `node`, Pester suites via `pwsh`/Pester 5.7.1 with `$env:SQLDIR` set):

| Suite | Outcome |
|---|---|
| `tests/archive/unit/role_admin.test.js` | **PASS** -- 38/38 |
| `tests/archive/unit/role_assigner.test.js` | **PASS** -- 39/39 |
| `tests/archive/pester/AxoniousParse.Tests.ps1` | **PASS** |
| `tests/archive/pester/GroupRoleMap.Tests.ps1` | **PASS** |
| `tests/archive/pester/Import-AxoniousExport.Tests.ps1` | **PASS** (1 test skipped -- the `-Tag Slow` full-export test, correctly skipped in the absence of the gitignored `SampleAxonious/` directory, same as pre-move baseline) |
| `tests/archive/pester/Publish-RoleSnapshot.Tests.ps1` | **PASS** |
| `tests/archive/pester/Reconcile-LocalRoles.Tests.ps1` | **PASS** (including the re-pointed `config/archive/task-DeresoRole{Ingest,Publish}.xml` existence/XML-parse assertions) |
| `tests/archive/pester/RoleRefPolicyBes.Tests.ps1` | **PARTIAL FAIL** -- 21/23 pass; 2 fail (see below) |

Combined archive-folder run: **129 passed, 2 failed, 1 skipped** out of 132 discovered tests across the 6 archived Pester files.

**The 2 `RoleRefPolicyBes.Tests.ps1` failures** (`policy-Fixlet lifecycle` describe block, "first publish POSTs..." and "a non-2xx PUT/POST sets Snapshot.Status = failed..."): both throw `RuntimeException: policy-Fixlet template not found at: G:\Gits\Software Portal\scripts\bes\RoleRef-Policy-template.bes`. Root cause: `Publish-RoleSnapshot.ps1` itself (now at `scripts/archive/Publish-RoleSnapshot.ps1`) resolves its own default template path relative to its own `$PSScriptRoot` with a single `..` segment, which correctly reached `bes\RoleRef-Policy-template.bes` when the script lived directly in `scripts\`, but now resolves to the wrong `scripts\bes\...` after the script itself moved one directory deeper. The two failing tests call the script without an explicit template-path override, so they hit this stale internal default. Per the plan's own text ("a frozen snapshot that cannot locate its own subject is worthless -- ... a failure is acceptable and must simply be recorded; these are not gated"), this is recorded, not fixed -- fixing it would mean editing the internal logic of an archived, explicitly not-maintained script, which is out of this plan's scope (moves files, does not edit code) and contrary to the archive's own stated purpose.

## Modules left in place because live code still imports them

**None.** Both `.psm1` files named in the plan's discretionary note (`AxoniousParse.psm1`, `SnapshotBuild.psm1`) were confirmed to have zero live importers via a repo-wide grep before moving -- see key-decisions for the two near-misses (`RoleGroupRelevance.psm1`'s convention-only comment, `Invoke-WhatIfAudit.ps1`'s pass-through argument value to the now-archived `Publish-RoleSnapshot.ps1`) that were checked and ruled out as real imports.

## Regression check (live estate, unaffected by this plan except the one documented/deferred break)

- **All 8 live Node unit suites green** (`automation_monitor`, `copier`, `dispatcher`, `fixlet_console`, `modifier`, `open_deployments`, `role_manager` [127/127], `update_tracker`) -- matches the plan's exact "do not move" list.
- **Live Pester estate** (`Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI`, `pwsh`/Pester 5.7.1): 8/9 suite files green (`Get-BigFixCredential`, `InitCurrentUserTask`, `Initialize-AutomationDb`, `Initialize-RoleDb`, `Invoke-ContentSync`, `Stage-Repository`, `Sync-RoleGroups`, `Upsert-RolePublish`). **`WhatIfAudit.Tests.ps1` fails** (`Container failed: 1`, 21 tests cascaded to failure) with `RuntimeException: Audited script missing: G:\Gits\Software Portal\scripts\Import-AxoniousExport.ps1` -- `scripts/Invoke-WhatIfAudit.ps1`'s `$Scripts` table still names the three now-archived scripts (`Import-AxoniousExport.ps1`, `Publish-RoleSnapshot.ps1`, `Reconcile-LocalRoles.ps1`) by their old `scripts\` path. This is the exact, single, plan-anticipated regression: the plan's acceptance criteria explicitly forbid touching `scripts/Invoke-WhatIfAudit.ps1`/`tests/pester/WhatIfAudit.Tests.ps1` in this plan, and 07-11's own plan text/threat-model (T-07-11-01) names removing these three dead rows as its own first-class scope, one wave later. No other live suite is affected.

## Task Commits

Each task was committed atomically:

1. **Task 1: Move the retired artefacts into archive/ subfolders** - `9fd2e9a` (feat)
2. **Task 1 fix (Rule 1 - Bug):** `51cb750` (fix) - corrects a staging bug in commit `9fd2e9a` itself; see Deviations below.

**Plan metadata:** `93a5788` (docs: complete 07-10 plan)

## Files Created/Modified

See `key-files` in frontmatter for the full moved-file list. New file: `tests/archive/README.md`.

## Decisions Made

See `key-decisions` in frontmatter. Summary:
- Both `.psm1` modules moved after confirming zero live importers.
- `Invoke-WhatIfAudit.ps1`/`WhatIfAudit.Tests.ps1` deliberately left untouched (07-11's job), accepting the one predictable regression.
- The two `RoleRefPolicyBes.Tests.ps1` failures (stale internal script default) recorded, not fixed, per the plan's explicit "failures are acceptable, just record them" instruction.
- The plan's own "returns 7" acceptance-criteria text is an arithmetic miscount against its own "do not move" list; the correct, observed, and verified count is 8.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed a self-introduced git-staging bug that committed pre-rebase file content**
- **Found during:** Task 1, immediately after the first commit -- a post-commit `git diff HEAD` sanity check (not required by the plan, done as extra diligence) showed 8 already-`git mv`d files still differed from the working tree.
- **Issue:** The staging command used to commit Task 1 passed both old (pre-move) and new (post-move) pathspecs for every file in one `git add` invocation. `git add` aborted the entire invocation with `fatal: pathspec ... did not match any files` on the very first (now-nonexistent) old pathspec, silently staging nothing from that command. Only the earlier `git mv` calls' original (pre-rebase-edit) staged content made it into commit `9fd2e9a` for 8 files (`tests/archive/unit/{role_admin,role_assigner}.test.js` and 6 `tests/archive/pester/*.Tests.ps1` files) -- the re-based repo-root/subject paths I had already edited and verified on disk were never actually committed.
- **Fix:** Re-staged exactly the 8 affected files (by their correct post-move paths only) and created a new `fix(07-10):` commit `51cb750` with the already-correct, already-tested working-tree content. Verified with `git diff HEAD --stat` across every archive/ path afterward: zero remaining difference between HEAD and the working tree.
- **Files modified:** `tests/archive/unit/role_admin.test.js`, `tests/archive/unit/role_assigner.test.js`, `tests/archive/pester/{AxoniousParse,GroupRoleMap,Import-AxoniousExport,Publish-RoleSnapshot,Reconcile-LocalRoles,RoleRefPolicyBes}.Tests.ps1`
- **Verification:** `git diff HEAD --stat -- tests/archive scripts/archive bes/archive config/archive "Existing Dashboards/archive"` returns empty; all per-suite outcomes reported above were captured by running the on-disk (correct) files both before and after this fix, so no test result in this summary needed revision.
- **Committed in:** `51cb750`

---

**Total deviations:** 1 auto-fixed (1 self-caught bug in this plan's own execution)
**Impact on plan:** No impact on the plan's actual deliverable -- the working-tree content was correct throughout and every verification/test outcome recorded above reflects the correct, re-based files. Only git history needed the follow-up commit.

Two further items are documented above as expected/accepted outcomes, not deviations requiring correction:
1. The `WhatIfAudit.Tests.ps1` regression is explicitly anticipated and scoped to 07-11 by the plan itself (not an unplanned discovery).
2. The `RoleRefPolicyBes.Tests.ps1` partial failure is explicitly permitted by the plan's own verification instructions ("a failure is acceptable and must simply be recorded; these are not gated").

Neither required a code fix under Rules 1-3 (both are out-of-scope-for-this-task by the plan's own explicit text), and neither rises to a Rule 4 architectural question (both already have a named owner: 07-11, or "acceptable by design").

## Issues Encountered

None beyond the two items above (both anticipated by the plan, not incidents).

## Known Stubs

None. This plan performs file moves and path re-basing only; no new functionality, dashboards, or data paths were introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 07-11 (strip dead references from live code + rewrite admin docs) can proceed immediately: this summary names exactly which `Invoke-WhatIfAudit.ps1` references are now dead (`Import-AxoniousExport.ps1`, `Publish-RoleSnapshot.ps1`, `Reconcile-LocalRoles.ps1`) and confirms `WhatIfAudit.Tests.ps1`'s current failure mode, matching 07-11-PLAN.md's own read-first list and threat-model entry T-07-11-01 exactly.
- 07-12 (production checkpoint) has its `LIVE ARTEFACTS TO REMOVE` answer: none. Nothing to stop on `gpbfs`.
- No blockers. The one live-suite regression (`WhatIfAudit.Tests.ps1`) and the one archived-suite partial failure (`RoleRefPolicyBes.Tests.ps1`) are both documented, both expected, and both have a clear owner (07-11, or "frozen by design" respectively) -- neither blocks 07-11 from starting.

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: `Existing Dashboards/archive/fixlet_role_admin.ojo`
- FOUND: `Existing Dashboards/archive/fixlet_role_assigner.ojo`
- FOUND: `scripts/archive/Import-AxoniousExport.ps1`
- FOUND: `scripts/archive/SnapshotBuild.psm1`
- FOUND: `bes/archive/RoleRef-Policy-template.bes`
- FOUND: `config/archive/GroupRoleMap.json`
- FOUND: `tests/archive/unit/role_admin.test.js`
- FOUND: `tests/archive/pester/RoleRefPolicyBes.Tests.ps1`
- FOUND: `tests/archive/README.md`
- FOUND commit: `9fd2e9a` (Task 1)
- FOUND commit: `51cb750` (Task 1 fix -- Rule 1 bug)
- VERIFIED: `git diff HEAD --stat` across all archive/ paths returns empty (working tree matches HEAD exactly)
