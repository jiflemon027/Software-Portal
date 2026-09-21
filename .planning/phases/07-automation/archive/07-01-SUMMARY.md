---
phase: 07-automation
plan: 01
subsystem: infra
tags: [powershell, sqlite, pester, csv-streaming, axonius, role-pipeline, import-csv, grouprolemap, age-out]

requires:
  - phase: 07-automation
    provides: "AutomationState.db 11-table schema (RefUser/UserRole/SyncRun/GroupRoleMap/PipelineConfig), Sqlite-Helper.ps1 + ConvertTo-SqliteLiteral, Event Log source DereseSoftwarePortal, Pester harness + phase-07 fixtures (axonious-sample-50.csv, axonious-multivalue-edge.csv, grouprolemap-seed.json, automation-db-schema.sql)"
provides:
  - "scripts/Import-AxoniousExport.ps1 - daily streaming ingest of the Axonius CSV into AutomationState.db: single unassigned Import-Csv | ForEach-Object pipeline (bounded memory), 11-column header/BOM validation (error 6700), stale-file guard (warn, Event 8010), GroupRoleMap resolution loaded once, batched INSERT OR IGNORE + guarded UPDATE via ConvertTo-SqliteLiteral at 400 rows/txn, age-out sweep (Active=0, never delete) with a MaxAgeOutFraction mass-revoke brake (Event 8012), SyncRun(Type='Ingest') + per-run JSON log, -WhatIf zero-writes, -ReportGroupFrequency operator CSV"
  - "scripts/AxoniousParse.psm1 - pure side-effect-free transforms: Resolve-UserName (D-06 coalesce), Get-GroupViews (dn/cn/display, escaped-comma-aware CN=), Get-SourceType (D-08 label), Resolve-Roles (GroupRoleMap matcher, all-matches-apply), Get-GroupRows (D-07 defensive multi-value combine test seam)"
  - "RefUser / UserRole / SyncRun rows in AutomationState.db - the only place the external world enters the role pipeline"
  - "tests/pester/Import-AxoniousExport.Tests.ps1, AxoniousParse.Tests.ps1, GroupRoleMap.Tests.ps1 - 74 new assertions"
affects: [07-02, 07-04, 07-05]

tech-stack:
  added: []
  patterns:
    - "Streaming ingest: one unassigned Import-Csv | ForEach-Object pipeline; no Select/Where/Sort/Group inside it; sentinel comments (# >>> INGEST LOOP START/END) bound the region a source-guarantee test greps"
    - "Batched CLM-safe writes: ArrayList batch -> one BEGIN; multi-row INSERT OR IGNORE ...VALUES; per-key guarded UPDATE; COMMIT per -BatchSize; every CSV value wrapped in ConvertTo-SqliteLiteral (Sql-Str/Sql-Int); First_Seen never updated; no INSERT OR REPLACE"
    - "Get-DbRows / script:Q flatten Sqlite-Helper's (return ,$rows) wrapper so multi-row .Count is correct"
    - "Single -WhatIf write gate (Invoke-DbWrite + flush/sweep guards); JSON log + New-Item forced with -WhatIf:$false so the dry-run audit log still writes"
    - "Pure transforms in a .psm1 imported by the driver AND by Pester; InModuleScope not needed because the D-07 splitter is exported as Get-GroupRows"
    - "Mass-revoke brake: read wouldAge/activeTotal BEFORE the sweep UPDATE (WR-02 separate calls); UPDATE ... Active=0; SELECT changes() co-located in one call (changes() is connection-scoped)"

key-files:
  created:
    - scripts/Import-AxoniousExport.ps1
    - scripts/AxoniousParse.psm1
    - tests/pester/Import-AxoniousExport.Tests.ps1
    - tests/pester/AxoniousParse.Tests.ps1
    - tests/pester/GroupRoleMap.Tests.ps1
  modified: []

key-decisions:
  - "Source_Value on a UserRole row = the matched view value (cn / display / dn text that fired the rule), so the T-07-01-01 injection payload is stored verbatim and is queryable"
  - "MaxAgeOutFraction (default 0.5) is read from PipelineConfig when present but NOT seeded into config/PipelineConfig.defaults.json - the 07-00 'exactly 13 keys' test forbids a 14th; operators opt into a non-default brake by adding the key"
  - "AxoniousParse.psm1 exports a 5th function Get-GroupRows as the D-07 splitter test seam (plan Task 2 explicitly permits an exported helper); the 4 named functions remain the public contract"
  - "Get-SourceType also maps literal 'azure'/'mailing' Group Type values (Rule 2) - the real export uses those literal strings and Source_Type feeds downstream reporting"
  - "Age-out sweep runs only after a clean full read (inside try, after the final flush) - a partially-read export never ages out the world"

patterns-established:
  - "Sentinel-comment-bounded ingest loop so a Pester source test can assert no buffering cmdlets inside it"
  - "Sql-Str / Sql-Int literal builders wrapping ConvertTo-SqliteLiteral for the batched-INSERT path (the entire injection surface)"
  - "Flatten the Sqlite-Helper (return ,$rows) wrapper at the call site (Get-DbRows / script:Q) - never rely on @(Invoke-SqliteCommand ...) for a count"

requirements-completed: [FR-02, NFR-NEW]

duration: 130min
completed: 2026-08-30
---

# Phase 7 Plan 01: Ingest Summary

**`Import-AxoniousExport.ps1` streams the ~400 MB Axonius CSV into `AutomationState.db` with a single unassigned `Import-Csv` pipeline - coalescing each user to one lowercased match key, defensively parsing the loosely-aligned multi-value group columns without index-zip, resolving entitlements through the `GroupRoleMap` rule table with all-matches-apply semantics, batching escaped `INSERT OR IGNORE` + guarded `UPDATE` at 400 rows/txn, and marking departed members `Active = 0` behind a `MaxAgeOutFraction` mass-revoke brake - all fully auditable via `SyncRun` + a per-run JSON log + Event Log, with `-WhatIf` making zero writes.**

## Performance

- **Duration:** ~130 min
- **Started:** 2026-08-30T11:20:00Z
- **Completed:** 2026-08-30T13:10:00Z
- **Tasks:** 4 completed
- **Files created:** 5

## Accomplishments

- **The only genuinely new algorithm in Phase 7 is built and green:** stream a 400 MB RFC-4180 CSV (BOM, quoted embedded newlines) and resolve entitlements without materialising the file. `Rows_In` is asserted to equal the `Import-Csv` record count (44), not the physical line count (516) - the Pitfall 1 guard.
- **`scripts/AxoniousParse.psm1`** - four pure contract functions plus `Get-GroupRows`, the D-07 defensive combine that iterates the longest of the five loosely-aligned `Assigned Groups: *` arrays with bounds-checked sibling reads (no index-zip, no dropped index, no throw on a 3/2/4 ragged shape or a blank middle slot).
- **GroupRoleMap matcher** with exact NOCASE + `*`-suffix-only wildcard, `Match_On` cn/display/dn view selection, `Active=0` never fires, ALL matching rules apply (two rules on one group -> two `UserRole` rows with distinct `Matched_Rule`), `Priority` orders only. Loaded once via the single `FROM GroupRoleMap` query; Event 8011 when empty.
- **Batched CLM-safe upsert** - `ArrayList` batches flushed at `-BatchSize` (400) as one `BEGIN; INSERT OR IGNORE ...VALUES(...),(...); per-key guarded UPDATE; COMMIT` per table; every CSV value escaped by `ConvertTo-SqliteLiteral`; `First_Seen` never updated; no `INSERT OR REPLACE`. The `'); DROP TABLE UserRole;--` payload is stored verbatim in `Source_Value` and the table survives.
- **Age-out + audit trail (NFR-NEW)** - departed members get `Active = 0` (row kept); a `MaxAgeOutFraction` (default 0.5) brake refuses a sweep that would deactivate more than half of active entitlements, sets `Status='partial'`, raises Event 8012. Every run leaves one `SyncRun` row (populated `Ended_on` + human-readable `Summary`), a JSON log (counts only - a test proves no fixture username appears in it), and an Application event in 8010-8099 on failure. `-WhatIf` writes the JSON log and makes zero DB writes including the `SyncRun` insert and the sweep. `-ReportGroupFrequency` emits the ranked `Source_Value,Source_Type,UserCount` CSV that unblocks GroupRoleMap authoring.
- **111 Pester assertions** across 6 suites (74 new) + all 8 Node suites green (regression gate held - this plan touches no JS).

## Task Commits

Each task was committed atomically:

1. **Task 1: streaming CSV reader + header/BOM validation + stale guard** - `e4268aa` (feat)
2. **Task 2: pure per-row transform module + wire coalesce/group-parse into ingest** - `60027ea` (feat)
3. **Task 3: GroupRoleMap matcher + batched RefUser/UserRole upsert** - `f7a1263` (feat)
4. **Task 4: age-out sweep + MaxAgeOutFraction brake + run finalisation + group report** - `ff1c90a` (feat)

**Plan metadata:** _this commit_ (docs: complete plan)

## Files Created/Modified

### Created

- `scripts/Import-AxoniousExport.ps1` - the streaming ingest driver. Params `-DatabasePath -SQLDir -SqliteHelperPath -ExportPath -RunId -BatchSize -LogDir -WhatIf -ReportGroupFrequency`. Error codes 6700 (missing required column) / 6710 (no export path) / 6720 (header, no data rows); Event IDs 8010/8011/8012/8013.
- `scripts/AxoniousParse.psm1` - `Resolve-UserName`, `Get-GroupViews`, `Get-SourceType`, `Resolve-Roles`, `Get-GroupRows` (+ internal `Split-AxMultiValue`, `Get-AxAt`). Zero I/O, zero DB, zero host output.
- `tests/pester/Import-AxoniousExport.Tests.ps1` - source guarantees + runtime (44-record Pitfall 1 assertion, 6700 abort, stale warn-and-complete, batched upsert, two-rules-one-group, SQL injection, First_Seen preserved, age-out marks-not-deletes, returning-user re-activation, fraction brake, SyncRun/JSON audit trail with no-PII assertion, `-WhatIf` no-sweep, `-ReportGroupFrequency` shape/ranking, Slow-tagged A7 profile).
- `tests/pester/AxoniousParse.Tests.ps1` - 26 assertions for the pure functions incl. the 3/2/4 ragged shape, blank-middle alignment, escaped-comma CN=, custom `-Priority` reversal, real-fixture blank-SAM -> `Username_Src = upn`.
- `tests/pester/GroupRoleMap.Tests.ps1` - 15 assertions vs `grouprolemap-seed.json` (all 8 D-08 semantics).

### Modified (plan metadata only)

- `.planning/STATE.md`, `.planning/ROADMAP.md` - position + plan progress.

## Decisions Made

- **`Source_Value` = matched view value.** `Resolve-Roles` returns `Matched_View`; the driver stores it as `UserRole.Source_Value`. This makes the provenance queryable and lets the injection test assert the literal payload round-trips.
- **`MaxAgeOutFraction` not seeded into `PipelineConfig.defaults.json`.** The 07-00 `Initialize-AutomationDb.Tests.ps1` asserts exactly 13 config keys; adding a 14th breaks that regression gate. The script reads the key when an operator adds it, otherwise defaults to `0.5` internally.
- **5th module export `Get-GroupRows`.** The plan's Task 2 explicitly sanctions testing the D-07 splitter "via the module or an exported helper"; the four named functions remain the documented public contract.
- **Freshness/`Import-Csv`-twice for the header.** The header is read with a separate `Import-Csv | Select-Object -First 1 | ForEach-Object` pipeline (Select-Object here is not "inside the ingest loop") so the file is streamed twice - bounded memory each pass, per the plan's explicit instruction to validate the header via `Import-Csv`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Flatten the Sqlite-Helper `(return ,$rows)` wrapper**
- **Found during:** Task 3 (rules load produced only 1 rule; entitlements = 0).
- **Issue:** `Sqlite-Helper.ps1` returns its row set as `return @(, $rows)` to stop single-row unrolling. `$x = @(Invoke-SqliteCommand ...)` then yields a **1-element array wrapping the row array**, so `$rules.Count` was 1 and the matcher only ever saw the first rule.
- **Fix:** `Get-DbRows` (script) and `script:Q` (tests) pipe the result through `ForEach-Object { $_ }` before `@(...)`, giving a correctly-counted flat array.
- **Files modified:** `scripts/Import-AxoniousExport.ps1`, `tests/pester/Import-AxoniousExport.Tests.ps1`
- **Verification:** smoke run went from 0 -> 43 entitlements; the two-rules-one-group test then counted 2 rows.
- **Committed in:** `f7a1263` (Task 3 commit)

**2. [Rule 3 - Blocking] `-WhatIf` suppressed the JSON audit log**
- **Found during:** Task 1 (`$json.WhatIf` property not found - the file was never written).
- **Issue:** `[CmdletBinding(SupportsShouldProcess=$true)]` propagates `$WhatIfPreference` into `Set-Content` / `New-Item`, so under `-WhatIf` the JSON log and its directory were only "what-if"-printed. NFR-NEW requires the JSON log **under `-WhatIf`**.
- **Fix:** `-WhatIf:$false` on the log `Set-Content`, the log-dir `New-Item`, and the `-ReportGroupFrequency` `Export-Csv` (same idiom `Initialize-AutomationDb.ps1` uses for `Add-Content`).
- **Files modified:** `scripts/Import-AxoniousExport.ps1`
- **Verification:** the `-WhatIf` test asserts the JSON log exists with `WhatIf=true` and `SyncRun` COUNT = 0.
- **Committed in:** `e4268aa` (Task 1), extended in `ff1c90a` (Task 4)

**3. [Rule 3 - Blocking] `-ReportGroupFrequency` tripped the missing-export abort**
- **Found during:** Task 4 (report mode threw `6710`).
- **Issue:** the `-ExportPath` requirement check ran before the report-mode early return.
- **Fix:** wrapped the `-ExportPath` resolution/validation in `if (-not $ReportGroupFrequency) { ... }`; report mode reads only the DB.
- **Files modified:** `scripts/Import-AxoniousExport.ps1`
- **Verification:** the `-ReportGroupFrequency` test produces the ranked CSV against a DB with no export configured.
- **Committed in:** `ff1c90a` (Task 4 commit)

**4. [Rule 2 - Missing critical] `Get-SourceType` literal `azure` / `mailing` branches**
- **Found during:** Task 2.
- **Issue:** the plan enumerated only `security` / `distribution` / `unified|microsoft 365` branches, but the real export's `Group Type` column carries the literal strings `Azure AD Group` and `Mailing List`; without a branch they fell through to `Unknown`, degrading downstream `Source_Type` reporting.
- **Fix:** added `mailing -> 'Mailing List'` and folded `azure` into the `unified|microsoft 365` -> `'Azure AD Group'` branch. Never returns null (column is `NOT NULL`).
- **Files modified:** `scripts/AxoniousParse.psm1`
- **Verification:** `Get-SourceType` tests cover each branch + Email-wins + blank -> `Unknown`.
- **Committed in:** `60027ea` (Task 2 commit)

**5. [Rule 3 - Blocking] Docstring literals flagged by the acceptance greps**
- **Found during:** Task 1 & Task 2 (`grep -v '^#' | grep -cE "...Add-Type..."` returned 2).
- **Issue:** `grep -v '^#'` keeps `<# ... #>` block-comment body lines; the `.DESCRIPTION` text literally named `Add-Type`, `System.IO.StreamReader`, `Invoke-SqliteCommand`, `Write-Host` as things the code avoids, which the "returns 0" gates then tripped on.
- **Fix:** reworded the docstrings to describe the constraint without the literal tokens.
- **Files modified:** `scripts/Import-AxoniousExport.ps1`, `scripts/AxoniousParse.psm1`
- **Verification:** all four acceptance greps return the required counts.
- **Committed in:** `e4268aa` (Task 1), `60027ea` (Task 2)

**6. [Rule 1 - Bug] `.Count` on a scalar under StrictMode Latest**
- **Found during:** Task 2 (`Get-GroupRows` threw "property 'Count' cannot be found").
- **Issue:** `Split-AxMultiValue` returning a 1-element result unrolled to a bare string on assignment; `$n.Count` then threw under `Set-StrictMode -Version Latest` on PS 7.6.
- **Fix:** wrap every splitter result at the call site: `$n = @(Split-AxMultiValue ...)`.
- **Files modified:** `scripts/AxoniousParse.psm1`
- **Verification:** the 3/2/4, zero-groups and blank-middle `Get-GroupRows` tests pass.
- **Committed in:** `60027ea` (Task 2 commit)

---

**Total deviations:** 6 auto-fixed (4 blocking, 1 missing-critical, 1 bug). One plan-vs-regression-gate reconciliation (`MaxAgeOutFraction` not seeded - documented under Decisions).
**Impact on plan:** all fixes necessary for correctness / the audit-trail contract / passing the acceptance gates. No scope creep - every deliverable and interface in the plan is present.

## Issues Encountered

- **A7 (RESEARCH assumption) - `Import-Csv` runtime on the real 401 MB export.** A profiling run was started on the dev host against `SampleAxonious/axonius-users_anond.csv` (420,745,184 bytes). `Import-Csv` streaming had **not completed after ~25 min** wall-clock and was still running when this plan closed. Memory stayed bounded (the pipeline is never assigned; no working-set climb was observed). This confirms RESEARCH A7's concern that `Import-Csv` may be operationally slow for the full file. The `-Tag Slow` Pester test (`tests/pester/Import-AxoniousExport.Tests.ps1`, skipped in CI and when the file is absent) is wired for a production-host profiling pass; the decision on whether a CLM-safe quote-state-machine reader is needed is carried to **07-05** (already scoped there, and the root server's CLM status is a 07-05 item). Batch size (`-BatchSize`, default 400) is the tuning knob if `sqlite3.exe` spawn overhead dominates.
- **`ORDER BY Started_on DESC` flakiness.** `datetime('now','localtime')` has 1-second resolution; two runs in the same second made a `SyncRun` status assertion order-dependent (passed alone, failed in the full suite). Fixed by giving the brake test explicit `-RunId`s and querying `WHERE RunID=...`.

## User Setup Required

None - no external service configuration. The GroupRoleMap **rule content** remains a deferred go-live gate (07-CONTEXT Deferred Ideas): the matcher and `-ReportGroupFrequency` authoring aid are built, but a live ingest that produces real entitlements needs the operator's first rule set (07-05 run-book).

## Next Phase Readiness

- **07-02 (Publish + distribute + reconcile)** is unblocked: it reads the `RefUser` / `UserRole` (`Active = 1`) / `SyncRun` rows this plan writes. `Resolve-Roles` in `AxoniousParse.psm1` is the reference semantics that 07-04's "Test Pattern" JS matcher must mirror exactly.
- **07-03 (Content pipeline)** has no file overlap and can run in parallel.
- **Carried to 07-05:** the A7 production-host profiling pass; the GroupRoleMap first-rule-set authoring gate (use `-ReportGroupFrequency`); the SAM <-> `name of current user` live spot-check.

## Self-Check: PASSED

Files verified present on disk:
- `scripts/Import-AxoniousExport.ps1` - FOUND
- `scripts/AxoniousParse.psm1` - FOUND
- `tests/pester/Import-AxoniousExport.Tests.ps1` - FOUND
- `tests/pester/AxoniousParse.Tests.ps1` - FOUND
- `tests/pester/GroupRoleMap.Tests.ps1` - FOUND

Commits verified in `git log`: `e4268aa`, `60027ea`, `f7a1263`, `ff1c90a`.

Test gate: `Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI` -> **111 passed, 0 failed, 1 not-run (Slow)**. All 8 Node unit suites -> exit 0.

---
*Phase: 07-automation*
*Completed: 2026-08-30*
