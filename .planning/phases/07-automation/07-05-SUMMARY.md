---
phase: 07-automation
plan: 05
subsystem: automation
tags: [powershell, sqlite, bigfix-relevance, computergroup, rest-api, pester, scheduled-task, drift-detection]

# Dependency graph
requires:
  - phase: 07-automation (plan 07-01)
    provides: "Production-confirmed six-element <ComputerGroup> REST body shape and A2 client-relevance verdict (07-SPIKE-FINDINGS.md Check A/B)"
  - phase: 07-automation (plan 07-03)
    provides: "scripts/Upsert-RolePublish.ps1 -- D-05 RolePublish.db audit store (RolePublishRun/RoleUsers schema) and the canonical MAX(RunID) membership query"
  - phase: 07-automation (plan 07-04)
    provides: "fixlet_role_manager.ojo's buildRoleGroupRelevance/buildComputerGroupXml (the exact relevance form and six-element XML body this plan's PowerShell twin must reproduce byte-for-byte)"
provides:
  - "scripts/RoleGroupRelevance.psm1: New-RoleGroupRelevance (pure D-09/D-10 relevance builder) + Get-CurrentRoleUsers (D-05 current-membership reader), importable by Pester"
  - "tests/fixtures/phase-07/role-group-relevance.golden.txt: the hand-authored 3-line cross-language relevance contract plan 07-06 also asserts against"
  - "scripts/Sync-RoleGroups.ps1: the D-06 root-server drift-check driver (GET-compare-PUT per role, never creates a group, -WhatIf safe)"
  - "scripts/Register-AutomationTasks.ps1: DeresoRoleGroupSync row + -RolePublishDbPath parameter + 'Daily@04:00' trigger spec"
  - "config/task-DeresoRoleGroupSync.xml: hand-authored Task Scheduler 1.2 run-book for 07-12's root-server install"
affects: ["07-06 (Node-side golden-file assertion in role_manager.test.js)", "07-12 (live root-server task registration + AKeyless secret confirmation)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cross-language golden fixture: a hand-authored .txt file, never generated from either implementation's own output, is the single shared expectation both the PowerShell and JS relevance builders are unit-tested against"
    - "Global-scope function promotion for module/dot-source interop: when a psm1 function (imported via Import-Module, whose parent scope is always the session's global scope) must call a helper the caller only dot-sourced into its own local script scope, promote that one entry-point function to global scope once via Set-Item function:\\global:<Name> -Value (Get-Item function:\\<Name>).ScriptBlock -WhatIf:$false -- the promoted function's own internal helper calls keep resolving correctly because a ScriptBlock's command lookups follow its original lexical definition context, not its invocation scope"
    - "Pester Mock + nested `& script.ps1` invocation: Mock DOES propagate into a script invoked via the call operator from inside an It block, but mutable state referenced inside the Mock's scriptblock must use plain lexically-closed-over variables (or Pester's own `Should -Invoke -ParameterFilter` call counting) -- `$script:`-qualified variables set in BeforeEach do not reliably resolve inside a Mock body once invoked from deep inside that nested script call"

key-files:
  created:
    - scripts/RoleGroupRelevance.psm1
    - scripts/Sync-RoleGroups.ps1
    - tests/pester/Sync-RoleGroups.Tests.ps1
    - tests/fixtures/phase-07/role-group-relevance.golden.txt
    - config/task-DeresoRoleGroupSync.xml
  modified:
    - scripts/Register-AutomationTasks.ps1
    - tests/pester/Get-BigFixCredential.Tests.ps1
    - tests/pester/Stage-Repository.Tests.ps1

key-decisions:
  - "Assumption A2 HELD for client relevance (the only dialect this phase's Computer Group SearchComponentRelevance ever uses) -- 07-SPIKE-FINDINGS.md Check A/B and 07-04-SUMMARY.md agree, no deviation form was needed. New-RoleGroupRelevance is authored directly against RESEARCH Pattern 2 / the live fixlet_role_manager.ojo source."
  - "New-RoleGroupRelevance preserves first-seen INSERTION ORDER, not an ordinal sort -- corrects this plan's own prose (\"trim + ToLowerInvariant + de-duplicate + ordinal sort\") against the actual shipped 07-04 dashboard behavior, which de-duplicates but never sorts. Verified directly against fixlet_role_manager.ojo's buildRoleGroupRelevance source and tests/unit/role_manager.test.js's pinned assertions; the two languages must agree exactly, and the dashboard is the load-bearing half of that contract."
  - "BESRootUrl resolution for Sync-RoleGroups.ps1 never references AutomationState.db by name (would fail the script's own no-AutomationState.db-literal acceptance guard) -- instead it makes one best-effort PipelineConfig lookup against its own -DatabasePath (RolePublish.db, which carries no such table, so this is normally a harmless no-op) and falls back to https://localhost:52311, the correct default for a job that always runs as SYSTEM on the BES root server itself."
  - "Sync-RoleGroups.ps1 never POSTs to computergroups/custom (plural) -- a role with no matching group is logged [MISSING] and skipped; group creation stays the dashboard's D-13 Publish responsibility."

patterns-established:
  - "D-06 periodic drift-check job pattern: root-server PowerShell scheduled task, GET-compare-PUT per item, per-item try/catch with a dedicated Windows Event id, exits non-zero only when every item failed, -WhatIf performs every read and zero writes."

requirements-completed: [NFR-02, NFR-05]

# Metrics
duration: ~50min
completed: 2026-09-22
---

# Phase 07 Plan 05: D-06 Periodic Drift-Check Job Summary

**Root-server `Sync-RoleGroups.ps1` daily drift-check (04:00, after the 03:00 content-pipeline window) that rebuilds each role's Computer Group relevance from the `RolePublish.db` D-05 audit store and re-PUTs only when the live relevance has drifted -- powered by a hand-authored PowerShell/JavaScript cross-language golden fixture that pins the exact relevance string both `New-RoleGroupRelevance` and the dashboard's `buildRoleGroupRelevance` must emit.**

## Performance

- **Duration:** ~50 min
- **Completed:** 2026-09-22T20:40:26Z
- **Tasks:** 3/3
- **Files modified:** 8 (5 created, 3 modified)

## Accomplishments

- `scripts/RoleGroupRelevance.psm1` -- pure PowerShell twin of `fixlet_role_manager.ojo`'s `buildRoleGroupRelevance` (07-04). Confirmed Assumption A2 held for client relevance, so no reduced/fallback relevance form was needed; `New-RoleGroupRelevance` is byte-identical to the dashboard's JS, including its actual (non-sorting) de-duplication behavior. `Get-CurrentRoleUsers` runs the canonical `MAX(RunID)` membership query against `RolePublish.db` via a caller-injected `Invoke-SqliteCommand` seam.
- `tests/fixtures/phase-07/role-group-relevance.golden.txt` -- the 3-line, LF-terminated, hand-authored cross-language contract (alice/bob no-scope; alice/bob + scope group 12345/"Dereso Software Portal"; the literal word `false`) both this plan's Pester suite and 07-06's Node suite assert against.
- `scripts/Sync-RoleGroups.ps1` -- the D-06 driver: for every role in `RolePublish.db`, finds its Computer Group by title (GET `computergroups/custom/<site>`, never POST), compares live vs. expected relevance (CDATA/whitespace-normalized, no case folding), and PUTs a freshly-built six-element `<ComputerGroup>` document only on drift. Per-role failures are caught, logged `[FAIL]`, written to Event 8050, and never abort the run; the run itself exits non-zero only when every role failed. Refuses to run against a database that isn't a `RolePublish.db` audit store (distinct exit code, never a silent zero-role no-op). `-WhatIf` performs every GET/compare and issues zero PUT calls.
- `tests/pester/Sync-RoleGroups.Tests.ps1` -- 32 passing tests: golden-file conformance, `New-RoleGroupRelevance` edge cases, `Get-CurrentRoleUsers` query semantics, source guarantees (no `Add-Type`, no POST to the plural group endpoint, `SupportsShouldProcess`, no `AutomationState.db` reference), the wrong-database guard, four mocked-REST scenarios (`[OK]`/`[DRIFT-FIXED]`/`[MISSING]`/`[FAIL]`-with-continuation), and the `-WhatIf` contract.
- `scripts/Register-AutomationTasks.ps1` -- new `-RolePublishDbPath` parameter (identical default literal to `Sync-RoleGroups.ps1`'s own `-DatabasePath` default) and the `DeresoRoleGroupSync` APPEND-ONLY table row, wired to `-RolePublishDbPath` (never the shared `-DatabasePath` the other four rows use). `New-TriggerFromSpec` gained a `'Daily@04:00'` branch, purely additive -- the four pre-existing rows and switch branches are byte-unchanged (diff is additions only, confirmed via `git diff` showing zero removed/modified lines).
- `config/task-DeresoRoleGroupSync.xml` -- hand-authored Task Scheduler 1.2 XML modelled on `task-DeresoRoleIngest.xml`, with a `04:00:00` `<CalendarTrigger>` and the exact argument string the table row builds.
- Full-estate regression: **317 Pester passed / 0 failed / 1 pre-existing unrelated NotRun**, all 10 Node unit suites green.

## Task Commits

Each task was committed atomically:

1. **Task 1: RoleGroupRelevance.psm1 + the cross-language golden fixture** - `3cfc926` (feat)
2. **Task 2: Sync-RoleGroups.ps1 driver + Pester suite** - `efad59a` (feat)
3. **Task 3: Register the DeresoRoleGroupSync scheduled task against RolePublish.db** - `0f68f7d` (feat)

**Plan metadata:** (this commit) `docs: complete 07-05 plan`

## Files Created/Modified

- `scripts/RoleGroupRelevance.psm1` - Pure `New-RoleGroupRelevance` (D-09/D-10 relevance builder) + `Get-CurrentRoleUsers` (D-05 canonical membership query), exported alphabetically
- `tests/fixtures/phase-07/role-group-relevance.golden.txt` - 3-line hand-authored cross-language relevance contract
- `scripts/Sync-RoleGroups.ps1` - D-06 drift-check driver: GET-compare-PUT per role, never creates a group, per-role failure isolation, `-WhatIf` safe
- `tests/pester/Sync-RoleGroups.Tests.ps1` - 32-test Pester suite covering both scripts
- `scripts/Register-AutomationTasks.ps1` - `-RolePublishDbPath` parameter, `DeresoRoleGroupSync` row, `'Daily@04:00'` trigger spec (additive only)
- `config/task-DeresoRoleGroupSync.xml` - Task Scheduler 1.2 run-book for the daily drift check
- `tests/pester/Get-BigFixCredential.Tests.ps1` - fixed a hard-coded "4 task(s) selected" assertion broken by this plan's table append
- `tests/pester/Stage-Repository.Tests.ps1` - same fix, second occurrence

## Decisions Made

- **Assumption A2 held for client relevance** (07-SPIKE-FINDINGS.md Check A/B, 07-04-SUMMARY.md) -- `New-RoleGroupRelevance` is authored directly against RESEARCH Pattern 2 / the live `fixlet_role_manager.ojo` source with no fallback form.
- **Insertion order, not ordinal sort** -- this plan's own action-block prose described the required de-duplication as "trim + ToLowerInvariant + de-duplicate + ordinal sort," but the actual shipped `buildRoleGroupRelevance` (07-04) and its pinned `tests/unit/role_manager.test.js` assertions do NOT sort, only de-duplicate while preserving first-seen order. Since the two languages must agree byte-for-byte and the dashboard is the already-tested, already-shipped half of the contract, `New-RoleGroupRelevance` was built to match the dashboard's actual behavior rather than the plan's prose. Documented here per the plan's own Step-1 discrepancy-resolution instruction ("if the two documents disagree... the discrepancy goes in the summary" -- extended here to a plan-prose-vs-shipped-code disagreement of the same shape).
- **BESRootUrl resolution avoids any `AutomationState.db` literal** -- `Sync-RoleGroups.ps1`'s own acceptance criteria forbid that substring anywhere in the file (even in comments), so the PipelineConfig lookup for `BESRootUrl` is attempted against the script's own `-DatabasePath` (RolePublish.db) rather than a second hardcoded database path; since RolePublish.db carries no PipelineConfig table this is normally a harmless no-op and the script falls back to `https://localhost:52311`, which is in fact the correct default for a job that always runs locally as SYSTEM on the BES root server.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `New-RoleGroupRelevance` matched to actual dashboard behavior (insertion order) instead of the plan's "ordinal sort" prose**
- **Found during:** Task 1, before writing the golden fixture
- **Issue:** The plan's action block explicitly says the module must reproduce "same trim + ToLowerInvariant + de-duplicate + ordinal sort," but `fixlet_role_manager.ojo`'s `buildRoleGroupRelevance` (07-04, already shipped and pinned by `tests/unit/role_manager.test.js`) only de-duplicates -- it never sorts.
- **Fix:** Built `New-RoleGroupRelevance` to preserve first-seen insertion order, matching the dashboard exactly. Golden fixture line 1 (`alice;bob`) happens to already be alphabetical, so this did not surface as a fixture mismatch -- caught by direct source comparison against the `.ojo` file instead.
- **Files modified:** `scripts/RoleGroupRelevance.psm1`
- **Verification:** `tests/pester/Sync-RoleGroups.Tests.ps1`'s "preserves first-seen insertion order rather than sorting" test (`New-RoleGroupRelevance -UserName @('bob','alice')` produces `("bob";"alice")`, not the sorted order).
- **Committed in:** `3cfc926` (Task 1 commit)

**2. [Rule 1 - Bug] `Get-CurrentRoleUsers` returned `$null` instead of an empty array for an unpublished role**
- **Found during:** Task 2's own Pester suite (`returns an empty array (not $null) for a role that has never been published`)
- **Issue:** `return [string[]]@()` unrolls the empty array onto the pipeline, emitting zero objects; the caller's `$x = Get-CurrentRoleUsers ...` then collapses to `$null`, violating the module's own documented "never `$null`" contract.
- **Fix:** Wrapped the return with the unary comma operator (`return ,$result`), the same idiom `Dashboard_4_samples/Sqlite-Helper.ps1`'s own `Invoke-SqliteCommand` already uses for exactly this reason.
- **Files modified:** `scripts/RoleGroupRelevance.psm1`
- **Verification:** The Pester test above now passes; re-ran the full `Sync-RoleGroups.Tests.ps1` suite.
- **Committed in:** `efad59a` (Task 2 commit)

**3. [Rule 1 - Bug] `Get-CurrentRoleUsers` could not see `Invoke-SqliteCommand` when the module was loaded via `Import-Module` from a caller that had only dot-sourced `Sqlite-Helper.ps1` into its own local scope**
- **Found during:** Task 2 smoke-testing `Sync-RoleGroups.ps1` end-to-end before writing the Pester suite
- **Issue:** A module imported via `Import-Module` always gets a module-scope whose parent is the session's global scope, never the importing script's local scope -- so a helper function the caller dot-sourced locally (as the plan's own `Get-CurrentRoleUsers` design requires, "dot-sources nothing itself") is invisible from inside the module, producing `The term 'Invoke-SqliteCommand' is not recognized...`. No existing script in this codebase had a psm1 function call `Invoke-SqliteCommand` before (`SnapshotBuild.psm1`/`AxoniousParse.psm1` are both fully pure), so there was no established precedent to follow.
- **Fix:** After dot-sourcing `Sqlite-Helper.ps1`, promote `Invoke-SqliteCommand` to global scope once (`Set-Item function:\global:Invoke-SqliteCommand -Value (Get-Item function:\Invoke-SqliteCommand).ScriptBlock -WhatIf:$false`) before `Import-Module`-ing `RoleGroupRelevance.psm1`. Confirmed empirically (isolated repro + fix, then applied to the real script and the test file's own `BeforeAll`) that the promoted function's internal calls to its own private helpers (`ConvertTo-SqliteLiteral`, etc.) keep resolving correctly, since a PowerShell `ScriptBlock`'s command lookups follow its original lexical definition context, not wherever the `CommandInfo` item was later placed.
- **Files modified:** `scripts/Sync-RoleGroups.ps1`, `tests/pester/Sync-RoleGroups.Tests.ps1` (same fix needed in the test file's own `BeforeAll` to call `Get-CurrentRoleUsers` directly)
- **Verification:** Manual smoke test before the fix reproduced the error; after the fix, the same smoke test and the full Pester suite pass.
- **Committed in:** `efad59a` (Task 2 commit)

**4. [Rule 1 - Bug] Two pre-existing Pester tests hard-coded "4 task(s) selected" against `$AutomationTaskTable`'s `-WhatIf` output**
- **Found during:** Task 3's full-estate regression run
- **Issue:** `tests/pester/Get-BigFixCredential.Tests.ps1` and `tests/pester/Stage-Repository.Tests.ps1` each asserted the literal string `'4 task(s) selected'` -- an unavoidable break once this task's `DeresoRoleGroupSync` row became the table's 5th entry.
- **Fix:** Both tests now recompute the expected count from the table itself (`([regex]::Matches($script:regSrc, "(?m)^\s*Name\s*=\s*'[^']+'")).Count`) rather than hard-coding a number, so a future plan's append will not require editing these tests again. The existing per-name assertions (all four 07-03-era row names present) were left untouched since they remain true.
- **Files modified:** `tests/pester/Get-BigFixCredential.Tests.ps1`, `tests/pester/Stage-Repository.Tests.ps1`
- **Verification:** Full-estate regression (`Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI`) went from 1 failure to 0 failures after this fix; 317 passed / 0 failed / 1 pre-existing unrelated NotRun.
- **Committed in:** `0f68f7d` (Task 3 commit)

---

**Total deviations:** 4 auto-fixed (4 bugs, all Rule 1)
**Impact on plan:** All four fixes were necessary for correctness (three) or to keep the pre-existing test estate green after an intentional, plan-mandated table append (one). No scope creep -- nothing outside `scripts/RoleGroupRelevance.psm1`, `scripts/Sync-RoleGroups.ps1`, and the two directly-broken sibling test files was touched.

## Issues Encountered

None beyond the deviations documented above. This session had a working PowerShell 7.6.6 / Windows PowerShell 5.1 / Pester 5.7.1 / sqlite3.exe 3.53.1 toolchain available, unlike 07-03's executor session -- every acceptance criterion and the full `<verification>` block were actually run, not just statically reasoned about.

## Known Stubs

None. `Sync-RoleGroups.ps1` is a complete, runnable driver; its only untested-against-a-live-server surface is the real BES REST API itself, which is inherent to this plan's scope (mocked in Pester, confirmed via 07-01's live spike for the underlying `<ComputerGroup>` XML shape) and is explicitly a 07-12 checkpoint item, not a gap in this plan.

## User Setup Required

**None required to complete this plan's tasks** -- no live REST calls were made against a BES server in this session; all REST behavior is proven via Pester mocks against the pinned XML shapes 07-01's live spike already confirmed.

The plan's frontmatter records one **future** (07-12-scoped) `user_setup` item, carried forward here for visibility: the daily drift-check job needs a working AKeyless credential path at runtime (`Get-BigFixCredential.ps1`, unmodified by this plan). Before `07-12` installs `config/task-DeresoRoleGroupSync.xml` on the live root server, confirm:
- The AKeyless secret exists at `PipelineConfig.AKeylessSecretPath` (`/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator`, already seeded in `config/PipelineConfig.defaults.json`).
- `PipelineConfig.BESOperatorUser` is set to the service-account username on the root server (currently seeded blank).

## Next Phase Readiness

- `tests/fixtures/phase-07/role-group-relevance.golden.txt` is stable and ready for 07-06's Node-side assertion from `tests/unit/role_manager.test.js` against the same three lines.
- `scripts/RoleGroupRelevance.psm1`'s `New-RoleGroupRelevance`/`Get-CurrentRoleUsers` and `scripts/Sync-RoleGroups.ps1` are fully built, tested, and require no further wiring from 07-06/07-07/07-08 (they operate independently of the dashboard's on-demand Publish flow, per D-06).
- `config/task-DeresoRoleGroupSync.xml` is ready for 07-12 to install on the live root server; no code changes anticipated, only the operational AKeyless/credential confirmation noted above.
- No blockers.

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: `scripts/RoleGroupRelevance.psm1`
- FOUND: `tests/fixtures/phase-07/role-group-relevance.golden.txt`
- FOUND: `scripts/Sync-RoleGroups.ps1`
- FOUND: `tests/pester/Sync-RoleGroups.Tests.ps1`
- FOUND: `config/task-DeresoRoleGroupSync.xml`
- FOUND: `scripts/Register-AutomationTasks.ps1`
- FOUND: `tests/pester/Get-BigFixCredential.Tests.ps1`
- FOUND: `tests/pester/Stage-Repository.Tests.ps1`
- FOUND commit: `3cfc926` (Task 1)
- FOUND commit: `efad59a` (Task 2)
- FOUND commit: `0f68f7d` (Task 3)
