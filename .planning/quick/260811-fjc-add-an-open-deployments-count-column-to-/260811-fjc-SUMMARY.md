---
phase: quick/260811-fjc
plan: 01
subsystem: ui
tags: [bigfix-relevance, ojo-dashboard, javascript, es5, sorting]

requires: []
provides:
  - "Open Deployments count column (sortable) in fixlet_dispatcher.ojo and fixlet_modifier.ojo"
  - "buildOpenDeploymentMap / loadOpenDeploymentCounts helper pair, duplicated verbatim across both dashboards"
  - "Numeric sort comparator for the openDeployments column in both files"
affects: [fixlet_dispatcher.ojo, fixlet_modifier.ojo]

tech-stack:
  added: []
  patterns:
    - "JS-side hash-map join instead of correlated subquery inside a relevance `whose (...)` clause (avoids the `it`-rebinding self-comparison tautology)"
    - "Single extra bulk EvaluateRelevance() call per grid load, joined client-side — O(1) in fixlet count"

key-files:
  created:
    - tests/unit/open_deployments.test.js
  modified:
    - Existing Dashboards/fixlet_dispatcher.ojo
    - Existing Dashboards/fixlet_modifier.ojo

key-decisions:
  - "Rejected correlated-subquery approach (appending count to the existing ||| tuple) per plan's design_decision — it silently produces a uniform server-wide count due to `it` rebinding inside `whose`"
  - "Used a fixed, non-interpolated relevance literal for the open-actions query, eliminating relevance-injection surface entirely"
  - "Reused existing #cc6600 orange/bold styling convention (already used by checkExistingDeployment) for counts > 0"
  - "In fixlet_modifier.ojo, extended the existing `id` numeric-sort branch (`col === \"id\" || col === \"openDeployments\"`) rather than adding a duplicate branch"

patterns-established:
  - "Shared small helpers (buildOpenDeploymentMap, loadOpenDeploymentCounts) are duplicated byte-identical across dashboard files and test file, per existing codebase convention (htmlEscape, xmlEscape, makeSortHeader)"

requirements-completed: [QUICK-260811-fjc]

duration: ~25min (Tasks 1-3 only; Task 4 pending human verification)
completed: 2026-08-11
---

# Quick Task 260811-fjc: Open Deployments Count Column Summary

**Sortable "Open Deployments" count column added to both fixlet grids via one extra bulk relevance query per grid load, joined to rows in JavaScript by exact fixlet name — avoiding the correlated-subquery self-comparison bug identified in the plan's design_decision.**

## Performance

- **Duration:** ~25 min (Tasks 1-3)
- **Started:** 2026-08-11T15:00:00Z (approx)
- **Completed:** 2026-08-11T15:27:37Z
- **Tasks:** 3 of 4 automated tasks complete; Task 4 is a blocking human-verify checkpoint, not yet run
- **Files modified:** 3 (2 `.ojo` dashboards + 1 test file)

## Status: Tasks 1-3 COMPLETE — Task 4 AWAITING HUMAN VERIFICATION IN THE BIGFIX CONSOLE

This plan has a mandatory blocking checkpoint (`type="checkpoint:human-verify" gate="blocking"`)
as Task 4. Per the plan and per this run's constraints, that checkpoint was **not**
simulated or auto-approved. All automatable work (Tasks 1-3) is complete, committed,
and green. Execution is paused here awaiting a human to verify both dashboards in an
actual BigFix console — something with no CLI/Node equivalent in this repo.

## Accomplishments

- Added `buildOpenDeploymentMap()` (pure counting logic) and `loadOpenDeploymentCounts()`
  (relevance wrapper) to both `fixlet_dispatcher.ojo` and `fixlet_modifier.ojo`, byte-identical
  across both files
- Added a rightmost "Open Deployments" grid column to both dashboards (6th column in
  dispatcher, 7th in modifier), populated via one extra `EvaluateRelevance()` call per
  grid load and joined to fixlet rows in JS by exact name match — same match-by-Title
  rule already used by the dispatcher's `checkExistingDeployment()`
- Added numeric sort support for the new column in both files (dispatcher: new branch;
  modifier: extended the existing `id` numeric branch)
- Counts greater than zero render in the existing orange/bold (#cc6600) style; a failed
  query renders "—" (em dash) rather than a misleading 0
- Created `tests/unit/open_deployments.test.js` — 20 assertions covering the counting
  logic, the numeric comparator (including the "10 sorts after 9" and dash/empty-as-0
  cases), structural parity across both `.ojo` files, the forbidden correlated-subquery
  form (absent from both), and byte-identical helper bodies across both dashboards
- No regressions: `dispatcher.test.js` and `modifier.test.js` both still pass

## Task Commits

Each task was committed atomically, directly to `master` (no worktree isolation for
this run, per this repo's existing convention):

1. **Task 1: Unit-test the counting logic and the numeric comparator** - `0b14890` (test)
2. **Task 2: Wire the Open Deployments column into fixlet_dispatcher.ojo** - `019c79c` (feat)
3. **Task 3: Wire the same column into fixlet_modifier.ojo** - `7065ede` (feat)

Task 4 (checkpoint) has no commit — it is a verification-only step with no file changes.

_Note: SUMMARY.md, STATE.md, and PLAN.md are intentionally NOT committed by this
executor run — the orchestrator handles the docs commit after this returns._

## Files Created/Modified

- `tests/unit/open_deployments.test.js` - New Node unit test: buildOpenDeploymentMap,
  compareOpenDeployments, plus structural parity assertions against both `.ojo` files
- `Existing Dashboards/fixlet_dispatcher.ojo` - Added openDeploymentCounts global,
  buildOpenDeploymentMap/loadOpenDeploymentCounts helpers, 6th grid column (header +
  body cell), numeric sort branch. Existing fixlet tuple relevance string, Roles/
  roleValue logic, search filter field list, and deploy/staging code untouched.
- `Existing Dashboards/fixlet_modifier.ojo` - Identical change: openDeploymentCounts
  global, verbatim helper pair, 7th grid column (header + body cell), extended the
  existing `id` numeric-sort branch to also cover `openDeployments`. Existing fixlet
  tuple relevance string, Roles/roleValue column, site filter, `filterAndRender()`
  search field list, and bulk-edit/PUT code paths untouched.

## Decisions Made

- Followed the plan's `design_decision` verbatim: rejected the correlated-subquery
  approach and implemented the JS-side hash-map join instead
- Worded the explanatory comment in both `.ojo` files to describe the `it`-rebinding
  bug without literally containing the forbidden `name of it = name of it` substring
  (the test asserts that substring is absent, and the comment itself would have
  tripped that assertion verbatim — reworded to "comparing the action's own name
  field against itself" instead)

## Deviations from Plan

None — plan executed exactly as written for Tasks 1-3. One self-correction during
execution (not a deviation from the *plan*, but from my own first draft): my initial
draft of the explanatory comment in Task 2 accidentally embedded the literal forbidden
string `name of it = name of it` inside a code comment while describing the bug it
warns against. This tripped the file's own forbidden-form assertion. Caught immediately
by running the test suite before committing; reworded the comment to describe the bug
without quoting the exact tautological expression, then re-verified all 14 (at that
point) assertions passed before committing Task 2.

## Issues Encountered

None beyond the self-correction above, which was resolved within Task 2 before that
task's commit (no separate fix commit needed — caught pre-commit).

## User Setup Required

None for Tasks 1-3 (pure code changes, no external service configuration).

**Task 4 requires the developer to verify in the live BigFix console** — see
"Checkpoint: Task 4" below for the full verification script.

## Next Phase Readiness

Tasks 1-3 are code-complete, tested, and committed. The plan cannot be marked fully
complete until a human performs the BigFix console verification in Task 4 below and
replies "approved" (or reports defects for a follow-up fix-and-re-verify cycle).

---

## CHECKPOINT: Task 4 — Verify both grids in the BigFix console

**Type:** human-verify
**Gate:** blocking
**Status:** awaiting human verification in the BigFix console — not simulated or auto-approved

### What was built

An "Open Deployments" column, last in the grid, in both the Dereso Fixlet Dispatcher
and Dereso Fixlet Modifier dashboards. It is populated by one extra bulk
session-relevance query per grid load
(`(name of it) of bes actions whose (state of it = "Open")`) joined to rows in
JavaScript by exact fixlet name. Counts greater than zero render in the same orange
bold already used by the dispatcher's existing-deployment indicator. The header sorts
numerically.

### How to verify

1. Import both `.ojo` files into the BigFix console and open the Dispatcher dashboard.
   Confirm the grid loads and shows an "Open Deployments" column as the rightmost
   column.
2. Pick a fixlet you know has at least one open action. Confirm its grid count is
   greater than zero and orange/bold.
3. Select that same fixlet. Confirm the detail panel's existing "N open action(s)
   already exist for this fixlet" line reports the SAME number as the grid cell. A
   mismatch means the name-matching drifted.
4. CRITICAL regression check: confirm different fixlets show DIFFERENT counts. If
   every row shows the same number, the correlated-subquery bug described in the
   plan's design_decision section has been reintroduced — reject and fix.
5. Click the "Open Deployments" header. Confirm sorting is numeric: a row with 10
   must sort after a row with 9 ascending, not before it. Click again and confirm the
   order reverses.
6. Confirm fixlets with no open actions show 0 (plain, not orange).
7. Open the Modifier dashboard, click Load Fixlets, and repeat steps 1, 4, 5 and 6
   there. Confirm the existing Roles column is unchanged.
8. Confirm grid load time is not noticeably slower than before — there should be
   exactly two relevance round-trips, not one per row.

### Resume signal

Type "approved" or describe what rendered incorrectly.

---
*Plan: quick/260811-fjc*
*Tasks 1-3 completed: 2026-08-11*
*Task 4: pending human verification*

## Self-Check: PASSED

- FOUND: tests/unit/open_deployments.test.js
- FOUND: Existing Dashboards/fixlet_dispatcher.ojo
- FOUND: Existing Dashboards/fixlet_modifier.ojo
- FOUND: .planning/quick/260811-fjc-add-an-open-deployments-count-column-to-/260811-fjc-SUMMARY.md
- FOUND commit: 0b14890 (Task 1)
- FOUND commit: 019c79c (Task 2)
- FOUND commit: 7065ede (Task 3)
