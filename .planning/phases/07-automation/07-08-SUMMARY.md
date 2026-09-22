---
phase: 07-automation
plan: 08
subsystem: ui
tags: [bigfix, ojo, relevance, actionscript, bes-xml, singleaction, computergroup, singleaction-stop, ie9]

# Dependency graph
requires:
  - phase: 07-automation (plan 07-04)
    provides: "buildRoleGroupRelevance/buildComputerGroupXml/buildRolePolicyActionXml/findBesObjectIdByTitle pure builders, and tests/unit/role_manager.test.js's baseline"
  - phase: 07-automation (plan 07-06)
    provides: "roleState/getRoleUsers/roleSlug/roleBySlug, the Publish-button DOM skeleton (publishRole_<slug>), and the D-13-over-D-07 resolution that Save owns the one RolePublish.db write -- this plan must not add a second write"
  - phase: 07-automation (plan 07-07)
    provides: "ensureRoleTask(role, onDone) -- callback contract {taskId, taskFields, actionScript, relevance} -- consumed directly by deployRolePolicyAction without re-fetch/re-parse; the 'Stage endpoint script on root server' live-console prerequisite"
provides:
  - "ensureRoleGroup(role, onDone) / parseComputerGroupId(body): per-role Computer Group find-or-create (POST computergroups/custom/ plural on create, PUT computergroup/custom/ singular on update), relevance regenerated from the CURRENT username list on every call"
  - "deployRolePolicyAction(role, groupId, taskResult, onDone): POSTs the SingleAction policy action built by buildRolePolicyActionXml against the role's group, consuming ensureRoleTask's already-substituted relevance/actionScript directly"
  - "findOpenActionIdsByTitle(title) / stopPreviousRoleActions(role, exceptActionId, onDone): stops every OTHER Open action matching the role's exact title after the new one is live; failures surface as leftoverIds warnings, never as a Publish failure"
  - "publishRole(role): the D-13 step-two orchestration wired to the Publish button (replacing the 07-06 stub) -- sequential Group -> Task -> Action -> Stop callbacks, each step's outcome in publishState[role].stepStatus and surfaced inline with its own [n/4 Name] label; refuses to run while roleState[role].dirty"
  - "publishState: per-role {groupId, taskId, actionId, lastPublishedOn, lastError, stepStatus} -- the shape plan 07-09's Analysis tab compares against roleState for intended-vs-actual"
affects: ["07-09 (Analysis tab reads publishState for intended-vs-actual comparison)", "07-12 (production checkpoint: the 07-07 'Stage endpoint script' button must be clicked live before any role's policy action can succeed end-to-end)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Nested-callback nested-orchestration for a multi-step REST sequence (IE9: no Promises/async-await) -- publishRole nests ensureRoleGroup -> ensureRoleTask -> deployRolePolicyAction -> stopPreviousRoleActions, with a per-step failure handler that stops the chain, records publishState[role].stepStatus, and tells the operator exactly which downstream objects are now stale vs. current. Reusable template for any future multi-step BES-object orchestration in this codebase."
    - "Fan-out/fan-in over a variable-length array with a pending-counter closure (stopPreviousRoleActions) -- the first pattern in this codebase to stop an unbounded set of REST calls (0..N Open actions) and wait for all of them via a shared pending-- counter closure rather than a fixed 2-3 step sequential chain."

key-files:
  created: []
  modified:
    - "Existing Dashboards/fixlet_role_manager.ojo"
    - "tests/unit/role_manager.test.js"

key-decisions:
  - "Individual step functions (ensureRoleGroup) write their OWN resultEl/errEl feedback per the plan's explicit Task 1 action text, while deployRolePolicyAction/stopPreviousRoleActions stay pure orchestration (onDone-only, no direct DOM writes) -- publishRole is the single place that formats the final [n/4 Name]-prefixed message for every step, including re-formatting/overwriting whatever ensureRoleGroup/ensureRoleTask already wrote with richer context (e.g. \"Task and action are unchanged\"). This keeps one consistent, centrally-owned contract for the operator-facing message while still satisfying Task 1's standalone-function acceptance criteria."
  - "stopPreviousRoleActions's onDone(err, stoppedIds[], leftoverIds[]) always passes err=null -- a per-id stop failure is recorded in leftoverIds and surfaced as a WARNING in the final summary line, never as a Publish failure, per the plan's explicit 'a failure to stop one is recorded but does not fail the Publish' instruction and RESEARCH Pitfall 7's create-then-stop-old ordering (the new action is already live; the stale one is idempotent)."
  - "publishRole's dirty-state guard checks the literal expression roleState[role].dirty (not a locally-cached st.dirty reference) specifically so the guard is provably present via source-level grep/test, matching this plan's own acceptance criterion wording."

requirements-completed: [FR-02, FR-03, NFR-02, NFR-03]

# Metrics
duration: ~12min
completed: 2026-09-22
---

# Phase 07 Plan 08: Per-Role Publish (Group/Task/Action/Stop, Four-Step Status) Summary

**The per-role Publish button now runs Group find-or-create -> Task refresh -> policy-action deploy -> previous-action stop as one sequential, per-role-isolated flow, with each step's success or failure surfaced separately via a `[n/4 Name]` label and recorded in `publishState[role]` for 07-09's Analysis tab.**

## Performance

- **Duration:** ~12 min (commit-to-commit; session including context loading was longer)
- **Started:** 2026-09-22T21:34:17Z
- **Completed:** 2026-09-22T21:44:15Z
- **Tasks:** 3/3
- **Files modified:** 2

## Accomplishments

- `ensureRoleGroup(role, onDone)` + `parseComputerGroupId(body)` + `publishState` — per-role Computer Group find-or-create: `POST computergroups/custom/<site>` (plural) on first Publish, `PUT computergroup/custom/<site>/<id>` (singular) thereafter, with the "exactly one of N logged on" relevance (`buildRoleGroupRelevance`, 07-04) regenerated from the CURRENT username list on every call — never a stale copy. A zero-username role gets a distinct "0 users — group will match no computers" note in the step status instead of looking like a bug (T-07-08-01, the empty-list guard already built in 07-04, exercised end-to-end here).
- `deployRolePolicyAction(role, groupId, taskResult, onDone)` — POSTs the `SingleAction` policy action built by `buildRolePolicyActionXml` (07-04: `Target` after `Settings`, `Reapply`/`P1D`/`IsOffer=false`, `DSP_RoleManager_Role` MIME field) against the role's group, consuming `ensureRoleTask`'s (07-07) already-`__ROLE__`/`__ASSIGNED_BY__`-substituted `relevance`/`actionScript` directly — no re-fetch/re-parse of the Task.
- `findOpenActionIdsByTitle(title)` (plural session-relevance variant of `findBesObjectIdByTitle`) + `stopPreviousRoleActions(role, exceptActionId, onDone)` — stops every **other** Open action whose title matches this role's exact title (never a prefix/substring match, T-07-08-06) after the new action is already live (create-then-stop ordering, RESEARCH Pitfall 7 — a mid-sequence failure leaves two idempotent actions, never zero). A per-id stop failure is recorded as a `leftoverIds` warning and never fails the overall Publish.
- `publishRole(role)` — replaces the 07-06 Publish-button stub. Sequential nested callbacks (IE9: no Promises/async-await) run Group → Task → Action → Stop; a `roleState[role].dirty` guard refuses to run against unsaved edits (NFR-03 — the audit store must record what is about to go live before anything deploys); each step's outcome lands in `publishState[role].stepStatus` and the role's own `resultEl`/`errEl` with its own `[1/4 Group]`/`[2/4 Task]`/`[3/4 Action]`/`[4/4 Stop]` label; a full success writes one summary line (`"Published <role>: group <gid>, task <tid>, action <aid>, stopped <n> previous action(s)."`) and sets `publishState[role].lastPublishedOn`. Per-role isolation is enforced throughout — every function here reads/writes only `roleState[role]`/`publishState[role]` and every REST call carries a title derived from that one role.
- `tests/unit/role_manager.test.js` grew 87 → 106 assertions: source-level proof that `publishRole` calls the four step functions in the documented order with all four `[n/4 Name]` labels in ascending order (spot-check confirmed a swapped `ensureRoleTask`/`deployRolePolicyAction` call order fails the suite, then restored — byte-identical to HEAD via `git diff --stat`); `buildRolePolicyActionXml` exercised against a realistic `taskResult` derived from the real `ASSIGN_ROLE_TEMPLATE`; the T-07-08-01 empty-list guard exercised end-to-end through `buildComputerGroupXml` (CDATA body is exactly `false`, no `"logged on users"` clause, a supplied scope group cannot override it — spot-check confirmed mutating the test file's own guard copy to return `"true"` fails 8 assertions, then restored, confirmed byte-identical via `diff`); source-level invariants for the new endpoints/labels/dirty-guard.
- **Full estate:** all 10 Node suites green (`role_manager.test.js`: 106/106); `Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI` (run via `pwsh`, Pester 5.7.1 — the environment's default `powershell.exe` only carries Pester 3.4.0) reports 317 passed / 0 failed / 1 pre-existing unrelated NotRun, matching the 07-07 baseline exactly (no PowerShell files touched). `fixlet_role_manager.ojo` still casts cleanly to `[xml]`; zero occurrences of `SourcedFixletAction`, `Promise`, `alert(` anywhere in the file.

## Task Commits

Each task was committed atomically:

1. **Task 1: Computer Group find-or-create** - `0dc4545` (feat)
2. **Task 2: Policy action deploy, previous-action stop, and Publish orchestration** - `84c2b63` (feat)
3. **Task 3: Publish-flow unit coverage** - `3f19192` (test)

**Plan metadata:** (this commit) `docs: complete 07-08 plan`

## Files Created/Modified

- `Existing Dashboards/fixlet_role_manager.ojo` - `publishState`/`ensurePublishState`/`parseComputerGroupId`/`ensureRoleGroup` (Task 1, ~108 lines); `deployRolePolicyAction`/`findOpenActionIdsByTitle`/`stopPreviousRoleActions`/`publishRole`/`onPublishRoleClick` (Task 2, ~212 lines) inserted between `ensureRoleTask` (07-07) and the Roles Tab section; the Publish button (`onPublishRoleClick`) now calls `publishRole` instead of being unwired; the Roles-tab intro text updated to describe Publish as a working step rather than "wired in a later plan"
- `tests/unit/role_manager.test.js` - 19 new assertions (87 → 106): call-ordering + label-ordering source-level proof, realistic-`taskResult` `buildRolePolicyActionXml` coverage, T-07-08-01 empty-list end-to-end coverage, source-level invariants for the new Publish code

## Decisions Made

See `key-decisions` in frontmatter. Summary:
- `ensureRoleGroup` writes its own step-scoped DOM feedback (per the plan's explicit Task 1 text) while `deployRolePolicyAction`/`stopPreviousRoleActions` stay pure onDone-only orchestration; `publishRole` centrally owns the final `[n/4 Name]`-labeled message for every step.
- `stopPreviousRoleActions` never fails the overall Publish on a per-id stop failure — leftover ids surface as a warning in the final summary line instead (RESEARCH Pitfall 7: the new action is already live, the stale one is idempotent).
- The dirty-state guard uses the literal `roleState[role].dirty` expression so its presence is provable by source-level grep, matching the plan's own acceptance wording.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Test-authoring bug, caught before commit] `alert(` and `async `/`await ` literal false-positives from my own new comments**
- **Found during:** Task 2, running the pre-existing source-level "no alert(/no arrow/no const-let/no oninput" test after adding `publishRole`.
- **Issue:** My first draft of `publishRole`'s doc comment used the English phrases "No alert() anywhere" and "no Promises, no async/await" — the literal substrings `alert(` and `Promise` inside a *comment* tripped the pre-existing whole-file regex test (`/\balert\s*\(/`) and would have tripped Task 3's new `Promise`/`async `/`await ` source-level checks had I not caught it first.
- **Fix:** Reworded the comments to avoid the literal trigger substrings ("No popup dialogs anywhere"; "IE9 predates the newer JS asynchronous-flow keywords") while keeping the same meaning. No functional code changed.
- **Files modified:** `Existing Dashboards/fixlet_role_manager.ojo`
- **Verification:** `node tests/unit/role_manager.test.js` — the pre-existing source-level assertion continued to pass; the new Task 3 scoped Promise/async/await assertion (added afterward) passes cleanly against the reworded comments.
- **Committed in:** `84c2b63` (Task 2 — caught and fixed before that commit was made, not a separate fix-up commit)

**2. [Rule 1 - Test bug, caught during Task 3's own spot-checks] CRLF-unaware source-slice markers**
- **Found during:** Task 3, running the required spot-checks (Task 3 acceptance criteria explicitly require confirming the new tests actually catch regressions).
- **Issue:** `Existing Dashboards/fixlet_role_manager.ojo` uses `\r\n` line endings throughout. Two of my first-draft `extractSourceSlice` end-markers embedded a literal `"\n\n// =="`-style boundary (assuming bare LF), which does not occur verbatim in a CRLF file (the actual bytes are `\r\n\r\n// ==`) — this made two Task 3 assertions throw "end marker not found" errors even against the correct, unmodified source, independent of any real bug.
- **Fix:** Replaced both markers with a plain, newline-agnostic anchor (`"// ROLES TAB"`, the unique next section header), which is robust regardless of line-ending convention.
- **Files modified:** `tests/unit/role_manager.test.js`
- **Verification:** `node tests/unit/role_manager.test.js` — 106/106 green after the fix; re-ran the ordering spot-check (swap `ensureRoleTask`/`deployRolePolicyAction`) and confirmed only the intended ordering assertion fails, not a marker-lookup error.
- **Committed in:** `3f19192` (Task 3 — found and fixed before that commit was made)

---

**Total deviations:** 2 auto-fixed (both Rule 1, both caught and corrected during this plan's own verification before any commit landed — neither reached a committed state as a defect).
**Impact on plan:** Both were self-inflicted authoring slips in this plan's own new comments/tests, not plan-text bugs or scope changes. No impact on the shipped functionality; both are documented here per the deviation-tracking convention this codebase's prior plan summaries (07-06, 07-07) established.

## Issues Encountered

- **Acceptance-criteria greps stricter than the pre-existing baseline can literally satisfy** (same category of caveat 07-06/07-07 documented, not "fixed" since fixing either would mean editing out-of-scope code from earlier plans):
  - The plan's Task 3 text says `"actions"` (the create-action endpoint) should appear exactly once in the whole file. It already appears twice before this plan (07-06's Save action, 07-07's Stage-endpoint-script action) plus once more from this plan's own `deployRolePolicyAction` — three total. The Task 3 test instead makes a **scoped** assertion: `deployRolePolicyAction`'s own function body contains exactly one `"actions"` occurrence (this plan's own new code is correct in isolation; the whole-file count reflects unrelated pre-existing calls).
  - The plan's Task 2 text says a whole-file `grep -c 'Promise\|async \|await '` should return 0. Two pre-existing `xml.async = false;` lines (the MSXML `ActiveXObject.async` DOM *property*, not the ES6 keyword) already exist in `parseXml` (07-04) and `parseCreatedId` (07-07), both out of this plan's scope. The Task 3 test instead scopes this check to this plan's own new code (`publishState` through `onPublishRoleClick`), where the count is genuinely zero.
- No live BigFix console verification was performed this session — consistent with this project's established pattern (07-01's live spike, the planned 07-12 production checkpoint). All new code is covered by the Node unit suite (106/106) and the `[xml]` cast check.

## Known Stubs

None introduced by this plan. The Analysis tab's own "read-only current role assignments" content (D-16) remains the pre-existing placeholder text ("built in plan 07-08" — inaccurate now, since this plan built Publish, not the Analysis view; that placeholder text is unchanged here as it is out of this plan's scope and is 07-09's stated deliverable per the roadmap).

## User Setup Required

None - no external service configuration required. As carried forward from 07-07's own note: the "Stage endpoint script on root server" button (07-07) must be clicked at least once against a real root server before any role's Publish can succeed end-to-end in a live console — this remains a 07-12 production-checkpoint concern, not something resolvable by this plan's automated tests.

## Next Phase Readiness

- `publishState[role]` — `{groupId, taskId, actionId, lastPublishedOn, lastError, stepStatus: {group, task, action, stop}}` — is populated by every Publish and is the exact shape plan 07-09's Analysis tab needs to compare "intended" (`roleState[role].users`) against "actual" (what `publishState` recorded as successfully deployed).
- No blockers. `fixlet_role_manager.ojo` has not yet been exercised end-to-end in a live BigFix console this session (same deferred-to-07-12 pattern as every prior plan in this phase) — Publish's first live run will additionally require the 07-07 "Stage endpoint script" button to have been clicked once against the real root server.

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: `Existing Dashboards/fixlet_role_manager.ojo`
- FOUND: `tests/unit/role_manager.test.js`
- FOUND: `.planning/phases/07-automation/07-08-SUMMARY.md`
- FOUND commit: `0dc4545` (Task 1)
- FOUND commit: `84c2b63` (Task 2)
- FOUND commit: `3f19192` (Task 3)
