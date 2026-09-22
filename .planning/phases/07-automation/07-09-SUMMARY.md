---
phase: 07-automation
plan: 09
subsystem: ui
tags: [bigfix, ojo, relevance, analysis, reconciliation, xss, ie9]

# Dependency graph
requires:
  - phase: 07-automation (plan 07-04)
    provides: "PORTAL_CONFIG.props (mappedUsers/mapSource/mapRegion/knownUsers), getRelevanceSafe, htmlEscape, findBesObjectIdByTitle, the two-tab (Roles/Analysis) IE9 shell"
  - phase: 07-automation (plan 07-06)
    provides: "roleState[role] = { users: [...], scopeGroupId, scopeSiteName, dirty, lastSavedRunId } -- the CONFIGURED side of this plan's reconciliation"
  - phase: 07-automation (plan 07-08)
    provides: "publishState[role] shape documented as the next interface, though this plan's Analysis tab ended up comparing roleState (configured) against live Analysis data (actual) directly rather than against publishState -- see Decisions Made"
provides:
  - "mergeAnalysisRows(mappedData, sourceData, regionData) -- pure row-merge lifted near-verbatim from fixlet_role_assigner.ojo (mapped_users is the spine; missing Source/Region cell = em dash)"
  - "reconcileIntentVsActual(roleState, analysisRows) -- pure, no-mutation comparison of each role's configured username list against what actually landed on the fleet; returns { configuredNotMapped: [{role,user}], mappedNotConfigured: [{role,user,computer}] }, case/whitespace-insensitive"
  - "loadAnalysisView()/loadAnalysisAge() -- Computer/User/Role/Source/Region (reporting only)/Configured? table reading mapped_users/map_source/map_region in r.db via GetRelevance (never EvaluateRelevance), degrading to an explicit 'Analysis not reporting yet' message when all three properties are empty, plus the two reconciliation panels underneath"
  - "the Analysis tab is fully read-only -- zero API.Post/API.Put/API.Delete calls anywhere in that section"
affects: ["07-10 (archives fixlet_role_admin.ojo/fixlet_role_assigner.ojo -- this plan's Analysis tab is the reason the retired files' own Analysis views are now safe to remove)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Reconciliation-by-normalised-key over two independently-sourced collections (roleState configured lists vs. mergeAnalysisRows fleet data) without ever mutating either input -- first use of this pattern in the codebase; reusable for any future 'intent vs. actual' comparison."

key-files:
  created: []
  modified:
    - "Existing Dashboards/fixlet_role_manager.ojo"
    - "tests/unit/role_manager.test.js"

key-decisions:
  - "reconcileIntentVsActual compares roleState[role].users (the CURRENT in-memory configured list) against live Analysis data directly, not against publishState (07-08's per-Publish record). The plan's own objective and acceptance criteria specify comparing 'the roles' configured username lists against those live mappings' -- roleState is that list. publishState records what was deployed at last-Publish-time, which is a different (and for this plan's stated purpose, less relevant) comparison; nothing in the plan's <interfaces> or acceptance criteria names publishState as an input to reconcileIntentVsActual."
  - "Reconciliation panels use two small tableGrid tables (Role/Username and Role/Username/Computer) with .warn-row / .dim row classes, rendered via textContent-safe .innerText assignments (the 07-06-established alternative to htmlEscape+innerHTML for pure text nodes) rather than a bulleted list -- keeps the visual language consistent with every other table in this dashboard."
  - "The main Computer/User/Role/Source/Region/Configured? table keeps the pre-existing htmlEscape+innerHTML convention per the plan's explicit 'each through htmlEscape' instruction, rather than switching to the newer .innerText pattern -- the two conventions now coexist intentionally in this file (main table vs. reconciliation panels), both XSS-safe by construction."
  - "Analysis-not-reporting-yet detection fires only when ALL THREE GetRelevance reads return zero rows (per the plan's literal wording), distinct from the pre-existing 'No reporting computers' empty-table message, which still covers the case where mapped_users is empty but a newer property somehow isn't (an unlikely but structurally possible ordering, since mapped_users is the merge spine)."

requirements-completed: [FR-02, FR-03, NFR-03, NFR-04]

# Metrics
duration: ~20min
completed: 2026-09-22
---

# Phase 07 Plan 09: Analysis Tab (Live Mappings + Intended-vs-Actual Reconciliation) Summary

**The Analysis tab now shows a live Computer/User/Role/Source/Region/Configured? table read from `Dereso SWD.bes` via `GetRelevance`, plus two reconciliation panels that name every configured username never seen on the fleet and every fleet mapping not in a role's configured list -- the exact typo-catching purpose D-16 exists for.**

## Performance

- **Duration:** ~20 min (commit-to-commit ~6 min; session including context loading, source reading across four files, and a full Pester run was longer)
- **Started:** 2026-09-22T21:44:15Z (picked up immediately after 07-08)
- **Completed:** 2026-09-22T21:59:20Z
- **Tasks:** 2/2
- **Files modified:** 2

## Accomplishments

- `mergeAnalysisRows(mappedData, sourceData, regionData)` -- lifted near-verbatim from `fixlet_role_assigner.ojo` (the file this dashboard's Analysis tab supersedes, due for archiving in 07-10) into the PURE BUILDERS section. `mapped_users` is the spine; a `map_source`/`map_region` cell absent for a given computer+user+role key renders as an em dash rather than dropping the row.
- `reconcileIntentVsActual(roleState, analysisRows)` -- pure, mutates neither argument. Compares each role's `roleState[role].users` (the admin-configured list) against `mergeAnalysisRows`' output (what the fleet actually reports), case- and whitespace-insensitively (the generator lower-cases usernames; an admin typing them in may not). Returns `configuredNotMapped` (the typo/never-logged-on case D-16 exists to catch) and `mappedNotConfigured` (legacy rows that age out naturally per D-17 -- rendered as informational, never as errors).
- `loadAnalysisView()`/`loadAnalysisAge()` -- reads `mapped_users`/`map_source`/`map_region in r.db` via `GetRelevance` (through the pre-existing `getRelevanceSafe` wrapper, never `EvaluateRelevance` -- SKILL.md S1, these are remote client Analysis values, resolved via `PORTAL_CONFIG.props.*` so the config block stays the single place to change property names), renders the six-column table with a `.warn-row` on every "Configured? No" row, a Refresh button, a row count, the last-reported-age line, and degrades to an explicit "Analysis not reporting yet -- import Dashboard_4_samples/Dereso SWD.bes..." message (never a silently empty table) when all three properties have reported nothing. Region is labelled "Region (reporting only)" per D-08 -- read-only, never a targeting input.
- Two reconciliation panels render beneath the table: "Configured but never mapped" (`.warn-row` table, typo/never-logged-on explanation) and "Mapped but not configured" (`.dim` table, D-17 age-out explanation); both empty renders "Configuration and fleet state agree."
- `switchTab('Analysis')` and `initDashboard()` (once, after `loadKnownUsers()`) both call `loadAnalysisView()`. The whole Analysis tab section is grep-confirmed to contain zero `API.Post(`/`API.Put(`/`API.Delete(` calls (D-16's read-only guarantee, T-07-09-02).
- `tests/unit/role_manager.test.js` grew 106 -> 127 assertions: the six pre-existing `mergeAnalysisRows` assertions ported verbatim from `tests/unit/role_assigner.test.js` (spine/em-dash/tuple-decode/multi-row/malformed-input/htmlEscape-survival), seven new `reconcileIntentVsActual` assertions (alice/bob, carol-with-computer, case/whitespace-insensitivity -- spot-check-confirmed load-bearing by breaking `norm()`'s `.toLowerCase()` and observing exactly that one assertion fail, then restoring, `git diff` confirming byte-identical to HEAD -- empty-list, D-04 dual-role, no-mutation, and a full-vs-missing-fixture comparison), plus source-level invariants for the new function names, column headings, reconciliation strings, `switchTab`/`initDashboard` wiring order, and the established zero-`alert(`/`=>`/`const `/`let `/`Promise`/`SourcedFixletAction`/`oninput` whole-file checks.
- **Full estate:** all 10 Node suites green (`role_manager.test.js`: 127/127); `Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI` (via `pwsh`, Pester 5.7.1) reports 317 passed / 0 failed / 1 pre-existing unrelated NotRun, matching the 07-08 baseline exactly (no PowerShell files touched). `fixlet_role_manager.ojo` still casts cleanly to `[xml]` (verified via `pwsh`) and its extracted `<script>` body still parses as valid JS (verified via `new Function()`); zero occurrences of `alert(`, `=>`, `const `, `let ` (word-boundary), `SourcedFixletAction` anywhere in the file.

## Task Commits

Each task was committed atomically:

1. **Task 1: Analysis tab -- live mappings and intended-vs-actual reconciliation** - `f86391a` (feat)
2. **Task 2: Analysis-tab unit coverage** - `f7344df` (test)

**Plan metadata:** (this commit) `docs: complete 07-09 plan`

## Files Created/Modified

- `Existing Dashboards/fixlet_role_manager.ojo` -- `mergeAnalysisRows`/`reconcileIntentVsActual` added to the PURE BUILDERS section (Task 1, ~150 lines); a new ANALYSIS TAB section (`loadAnalysisAge`/`isUserConfiguredInRole`/`appendAnalysisCell`/`renderReconciliation`/`loadAnalysisView`, ~245 lines) inserted after the SAVE section; `switchTab`/`initDashboard` updated to call `loadAnalysisView()`; the `tabAnalysis` HTML panel replaced the plan-07-08 placeholder with the six-column table, Refresh button, row-count/age lines, not-reporting notice and reconciliation container.
- `tests/unit/role_manager.test.js` -- 21 new assertions (106 -> 127): ported `mergeAnalysisRows` coverage, new `reconcileIntentVsActual` coverage, source-level invariants for the Analysis tab.

## Decisions Made

See `key-decisions` in frontmatter. Summary:
- `reconcileIntentVsActual` compares `roleState` (current configured lists) against live Analysis data, not `publishState` (07-08's per-Publish record) -- matches the plan's own literal wording ("the roles' configured username lists against those live mappings"), and no interface/acceptance text named `publishState` as an input here.
- Reconciliation panels use small `.tableGrid` tables with `.warn-row`/`.dim` row classes and `.innerText` text assignment (07-06's established XSS-safe alternative to `htmlEscape`+`innerHTML`), while the main six-column table keeps the pre-existing `htmlEscape`+`innerHTML` convention per the plan's explicit instruction -- both patterns are XSS-safe by construction and now coexist intentionally.
- The "Analysis not reporting yet" degradation fires only when all three `GetRelevance` reads are empty, distinct from the pre-existing "No reporting computers" empty-table message for the (structurally unlikely, since `mapped_users` is the merge spine) case where only `mapped_users` is empty.

## Deviations from Plan

None - plan executed exactly as written. Both tasks matched their `<action>`/`<acceptance_criteria>` blocks; no Rule 1-4 fixes were needed.

## Issues Encountered

None.

## Known Stubs

None. The Analysis tab reads live `GetRelevance` data end-to-end; there is no hardcoded/mock data path.

## User Setup Required

None - no external service configuration required. As carried forward from 07-07/07-08: the "Stage endpoint script on root server" button must still be clicked once against a real root server, and `Dashboard_4_samples/Dereso SWD.bes` must be imported and given time to evaluate, before the Analysis tab will show anything other than its "not reporting yet" degradation on a fresh environment -- both remain 07-12 production-checkpoint concerns.

## Next Phase Readiness

- `fixlet_role_manager.ojo` is feature-complete after this plan: Roles tab (edit/Save/Publish, 07-06/07-07/07-08) plus Analysis tab (this plan) cover the full D-14 consolidation scope. A reviewer preparing 07-10 (archive `fixlet_role_admin.ojo`/`fixlet_role_assigner.ojo`) should confirm no remaining external reference to either retired file's Analysis view survives outside this dashboard -- `mergeAnalysisRows`/the Analysis property reads are now fully duplicated here.
- No blockers. No live BigFix console verification was performed this session -- consistent with this project's established pattern (07-01's live spike, the planned 07-12 production checkpoint). All new code is covered by the Node unit suite (127/127) and the `[xml]`/JS-syntax checks.

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: `Existing Dashboards/fixlet_role_manager.ojo`
- FOUND: `tests/unit/role_manager.test.js`
- FOUND: `.planning/phases/07-automation/07-09-SUMMARY.md`
- FOUND commit: `f86391a` (Task 1)
- FOUND commit: `f7344df` (Task 2)
