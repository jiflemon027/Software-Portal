---
phase: 07-automation
plan: 04
subsystem: ui
tags: [bigfix, ojo, relevance, actionscript, bes-xml, computergroup, singleaction, ie9]

# Dependency graph
requires:
  - phase: 07-automation (plan 07-01)
    provides: "Production-confirmed six-element <ComputerGroup> REST body shape (07-SPIKE-FINDINGS.md Check A)"
  - phase: 07-automation (plan 07-02)
    provides: "Task 787 D-18 Map schema migration (Source_Type/Source_Value/Region/Assigned_By columns), so Assign-RoleMapping.ps1's UPDATE will find those columns on real endpoints"
provides:
  - "Existing Dashboards/fixlet_role_manager.ojo: two-tab (Roles/Analysis) IE9 OJO shell, PORTAL_CONFIG, shared XML/relevance helpers"
  - "buildRoleGroupRelevance(usernames, scopeGroupId, scopeSiteName) -- D-09/D-10 'exactly one of N logged on' relevance builder with a hard empty-list->\"false\" guard"
  - "buildComputerGroupXml(title, domain, relevance) -- Pattern 1 six-element <ComputerGroup> BES-XML builder"
  - "buildRolePolicyTaskXml(templateFields, role, assignedBy) -- Pattern 3 step 1 from-scratch <BES><Task> builder"
  - "buildRolePolicyActionXml(title, relevance, actionScript, groupId, siteName) -- Pattern 3 steps 2-3 SingleAction builder (Settings-before-Target, Reapply/P1D/IsOffer=false)"
  - "findBesObjectIdByTitle(kind, siteName, title) -- session-relevance find-or-create lookup for computergroup/fixlet/action"
  - "tests/unit/role_manager.test.js -- 30 Node-native assertions pinning every builder's exact output string/order"
affects: ["07-06 (Roles tab UI + Save)", "07-07 (per-role Publish flow)", "07-08 (Analysis tab)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Interface-first plan: pure builders + unit suite land before any UI/REST wiring, so 07-06/07-07/07-08 consume a fixed, already-tested contract"
    - "create-new-then-stop-previous policy-action redeploy (recorded here, implemented in 07-07): POST new action first, then stop the old one by title/MIME match, so a mid-sequence failure leaves two idempotent actions rather than zero"

key-files:
  created:
    - "Existing Dashboards/fixlet_role_manager.ojo"
    - "tests/unit/role_manager.test.js"
  modified: []

key-decisions:
  - "Six-element <ComputerGroup> body (Title/Domain/JoinByIntersection/IsDynamic/EvaluateOnClient/SearchComponentRelevance) used as-is -- 07-01's spike confirmed the POST succeeds and round-trips; no reduced-form deviation was needed."
  - "buildRolePolicyTaskXml's Task <Title> is always PORTAL_CONFIG.taskTitlePrefix + role (not the raw template's __ROLE__-bearing title) so findBesObjectIdByTitle can locate the exact same Task on every subsequent Publish."
  - "__ROLE__/__ASSIGNED_BY__ substitution was extended to every <Relevance> element too (not just title/description/postLink/actionScript as literally listed in the plan) -- defensive no-op today since the current bes/Assign-RoleMapping.bes template carries no tokens in its Relevance bodies, but protects against a future template edit leaking a placeholder."
  - "buildRolePolicyActionXml's DSP_RoleManager_Role MIME value is derived by stripping PORTAL_CONFIG.actionTitlePrefix off the supplied title (the function's fixed interface signature carries no separate role parameter) -- correct as long as 07-07 builds titles as actionTitlePrefix + role, which is the documented D-13 convention."

patterns-established:
  - "Pure builder + Node unit-suite pairing for every new BigFix XML/relevance generator function in this dashboard family, extending the role_assigner.test.js/dispatcher.test.js convention"

requirements-completed: [FR-02, FR-03, NFR-05]

# Metrics
duration: ~35min
completed: 2026-09-22
---

# Phase 07 Plan 04: Dereso Role Manager Generator Interface Summary

**New `fixlet_role_manager.ojo` IE9 dashboard shell plus five pure BigFix XML/relevance builder functions (Computer Group, per-role Task, policy SingleAction, find-by-title) pinned by a 30-assertion Node unit suite -- the fixed contract plans 07-06/07-07/07-08 build the UI and REST wiring on top of.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-22T20:06:40Z
- **Tasks:** 3/3
- **Files modified:** 2 (both new)

## Accomplishments

- `Existing Dashboards/fixlet_role_manager.ojo` created as a loadable, XML-valid, two-tab (Roles/Analysis) IE9 dashboard shell with `PORTAL_CONFIG` (D-03 role list, D-10 scope groups, D-07 root-server ComputerID, D-16 Analysis property names) and every shared helper (`htmlEscape`, `xmlEscape`, CDATA helpers, `parseXml`/`parseActionId`, `escapeActionScriptBraces`, `getRelevanceSafe`, `setStatus`, `switchTab`) lifted byte-equivalent from the existing dashboard family.
- Five pure generator functions added and unit-pinned: `buildRoleGroupRelevance` (D-09/D-10, with the T-07-04-01 empty-username-list -> `"false"` guard, the single highest-impact bug this generator could ship), `buildComputerGroupXml` (Pattern 1, six-element body matching 07-01's live-confirmed shape), `buildRolePolicyTaskXml` (Pattern 3 step 1, from-scratch `<BES><Task>` build, never mutates fetched XML), `buildRolePolicyActionXml` (Pattern 3 steps 2-3, D-11, `SingleAction` only, `Target` after `Settings`, `Reapply`/`P1D`/`IsOffer=false`), and `findBesObjectIdByTitle` (session-relevance find-by-title for all three BES object kinds).
- `tests/unit/role_manager.test.js` created with 30 assertions covering every builder's exact output string, element ordering, escaping, and the dashboard's own IE9/no-`alert()`/no-`SourcedFixletAction` source-level constraints. Spot-checked that flipping the empty-list guard from `"false"` to `"true"` fails 5 assertions (confirms the guard is load-bearing), then restored.
- Full regression: all 10 `tests/unit/*.test.js` suites (including the new one) exit 0.

## Task Commits

Each task was committed atomically:

1. **Task 1: OJO shell, PORTAL_CONFIG and shared helpers** - `b03a88d` (feat)
2. **Task 2: Pure relevance and BES-XML builders** - `cbff752` (feat)
3. **Task 3: Node unit suite tests/unit/role_manager.test.js** - `017321e` (test)

**Plan metadata:** (this commit) `docs: complete 07-04 plan`

## Files Created/Modified

- `Existing Dashboards/fixlet_role_manager.ojo` - New D-14 "Dereso Role Manager" dashboard: IE9 shell, config, shared helpers, and the five pure BigFix XML/relevance builders (478 lines)
- `tests/unit/role_manager.test.js` - 30-assertion Node suite pinning every builder's output (482 lines)

## Decisions Made

- Six-element `<ComputerGroup>` body used as-is per 07-01's live spike confirmation (no reduced-form deviation).
- Task `<Title>` is always `PORTAL_CONFIG.taskTitlePrefix + role`, overriding whatever title the template itself carries, so the find-by-title lookup used on every Publish stays stable.
- `__ROLE__`/`__ASSIGNED_BY__` substitution extended defensively to `<Relevance>` elements too, beyond the four locations the plan text named -- harmless no-op against the current template, protects a future template edit.
- `buildRolePolicyActionXml`'s `DSP_RoleManager_Role` MIME value is derived from the fixed `title` parameter (prefix-stripped) since the function's locked interface signature has no separate `role` parameter.

## Deviations from Plan

**1. [Rule 1 - Bug] `__ROLE__` substitution was missing from `<Relevance>` elements in `buildRolePolicyTaskXml`**
- **Found during:** Task 2 verification (manual sanity check with a synthetic `templateFields.relevances` entry containing `__ROLE__`)
- **Issue:** The plan text enumerated substitution targets as "title, description, actionDescription.postLink and actionScript" -- `relevances` array elements were not substituted, so a `__ROLE__` token in a `<Relevance>` body would have survived into the emitted XML unchanged.
- **Fix:** Applied the same `sub()` (global `__ROLE__`/`__ASSIGNED_BY__` replace) to each `relevances[i]` before CDATA-wrapping it. Confirmed a no-op against the real `bes/Assign-RoleMapping.bes` template (neither of its two `<Relevance>` bodies carries a token today).
- **Files modified:** `Existing Dashboards/fixlet_role_manager.ojo`
- **Verification:** Manual Node sanity check (both before and after the fix) plus `tests/unit/role_manager.test.js`'s "__ROLE__ is fully substituted (zero occurrences remain)" assertion, which now covers a two-relevance fixture.
- **Committed in:** `cbff752` (Task 2 commit -- caught and fixed before that commit was made, so no separate fix commit was needed)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary for correctness against the plan's own "global replace" intent; caught during Task 2's own verification before committing, so it required no follow-up commit. No scope creep.

## Issues Encountered

None beyond the deviation above.

## Known Stubs

- `Existing Dashboards/fixlet_role_manager.ojo`'s `tabRoles` and `tabAnalysis` panels currently render only a one-line placeholder (`<span class="dim">...built in plan 07-06/07-07/07-08.</span>`) -- intentional per this plan's interface-first scope. `initDashboard()` makes no REST/Analysis calls yet. Both are resolved by plans 07-06 (Roles tab + Save/Publish), 07-07 (per-role Publish flow), and 07-08 (Analysis tab).

## User Setup Required

None - no external service configuration required. No live BigFix console verification was needed for this plan (no REST calls exist yet in the dashboard); the dashboard's XML validity, IE9 constraints, and every builder's output are fully covered by the Node unit suite and `[xml]` cast checks run in this session.

## Next Phase Readiness

- Plans 07-06/07-07/07-08 can call `buildRoleGroupRelevance`, `buildComputerGroupXml`, `buildRolePolicyTaskXml`, `buildRolePolicyActionXml`, and `findBesObjectIdByTitle` directly by their fixed signatures without further codebase exploration.
- No blockers. The dashboard has not yet been opened in a live BigFix console (no UI content to verify yet) -- that verification lands naturally once 07-06 adds real tab content.

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: `Existing Dashboards/fixlet_role_manager.ojo`
- FOUND: `tests/unit/role_manager.test.js`
- FOUND: `.planning/phases/07-automation/07-04-SUMMARY.md`
- FOUND commit: `b03a88d` (Task 1)
- FOUND commit: `cbff752` (Task 2)
- FOUND commit: `017321e` (Task 3)
