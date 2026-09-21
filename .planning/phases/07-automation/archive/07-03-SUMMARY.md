---
phase: 07-automation
plan: 03
subsystem: infra
tags: [powershell, pester, bigfix, rest-api, prefetch, sha1, content-pipeline, scheduled-tasks, sqlite]

requires:
  - phase: 07-automation
    provides: "AutomationState.db (ContentItem / ContentCache / SyncRun-with-Type schema), Initialize-AutomationDb.ps1, Get-BigFixCredential.ps1, Register-AutomationTasks.ps1 APPEND-ONLY $AutomationTaskTable + Register-AutomationTask helper, Sqlite-Helper.ps1 + ConvertTo-SqliteLiteral, phase-07 automation-db-schema.sql fixture"
  - phase: 06-update-tracker
    provides: "fixlet_update_tracker.ojo stripVersion/extractVersion/compareVersions, scanNextSite scan loop, buildSupersededXml, CATEGORY_MAP, PORTAL_CONFIG.sourceSites; tests/unit/update_tracker.test.js parity assertions"
  - phase: 03-dispatcher-rapid-deployment
    provides: "fixlet_dispatcher.ojo extractPrefetchLines()/rewritePrefetchUrls(), wwwRootFolder registry derivation, CustomRepository/SoftwarePortal/<sha1>/<file> on-disk shape"
provides:
  - "scripts/ContentSyncCore.psm1 - pure module: Get-StrippedName / Get-ExtractedVersion / Compare-FixletVersion / Get-FixletPathType / New-SupersededXml / Read-PrefetchLine (no REST/DB/file I/O)"
  - "scripts/Invoke-ContentSync.ps1 - POST /api/query source-site scan (\\x1F tuple), version diff keyed on Get-StrippedName, D-12 INSERT OR IGNORE + guarded UPDATE writing 'discovered' ContentItems, 4-step copy (GET portal -> GET source -> POST fixlets/custom plural -> PUT fixlet|task/custom singular) with category + Associated_Roles MIME transfer + idempotent X-Superseded-By stamp, per-item partial-failure model, Start-ScheduledTask chain to DeresoRepoStage, SyncRun Type=ContentSync + JSON log, -WhatIf zero writes"
  - "scripts/Stage-Repository.ps1 - per live ContentItem: GET action script, Read-PrefetchLine every line, download from the ORIGINAL url, Get-FileHash SHA1 + byte-length verify, place a match at <wwwRootFolder>\\Uploads\\CustomRepository\\SoftwarePortal\\<sha1-lc>\\<file>, discard any mismatch (ContentCache verified=0 + note + Event 8040), sha1 dedupe, MaxStageFileMB + MaxItems guards, SyncRun Type=RepoStage + JSON log, -WhatIf zero I/O"
  - "scripts/Register-AutomationTasks.ps1 - DeresoContentSync (Weekly) + DeresoRepoStage (OnDemand) rows appended to the shared table"
  - "config/task-DeresoContentSync.xml + config/task-DeresoRepoStage.xml - Task Scheduler 1.2 run-book exports"
  - "additive AutomationState.db columns via idempotent PRAGMA-gated ALTER: ContentItem.discovery_kind / .portal_fixlet_id / .reject_reason / .repo_staged_at, ContentCache.note"
affects: [07-04, 07-05]

tech-stack:
  added: []
  patterns:
    - "dot-source-safe root-server script: all logic in functions + a guarded `if ($MyInvocation.InvocationName -ne '.') { Start-<X> @args }` entrypoint, so Pester can dot-source, Mock Invoke-RestMethod / Invoke-WebRequest, and call the internals directly"
    - "pure parity module (ContentSyncCore.psm1) imported by the driver AND by Pester - the version-strip/extract regexes and the supersede-stamp idempotence are unit-testable with no BigFix server; every stripVersion case in tests/unit/update_tracker.test.js is ported one-for-one"
    - "self-owned additive schema: a script ensures its own AutomationState.db columns exist via PRAGMA table_info-gated ALTER (D-18 Map-migration mechanism) rather than editing the shared Initialize-AutomationDb.ps1"
    - "single -WhatIf write gate (Invoke-CsWrite / Invoke-RsWrite) - reads (POST /api/query, GET) still run under -WhatIf, every mutation is suppressed"
    - "New-SupersededXml strip-first order: regex-remove every existing X-Superseded-By MIMEField, then insert exactly one before <Domain> - two applications are byte-identical (Pester-asserted)"

key-files:
  created:
    - scripts/ContentSyncCore.psm1
    - scripts/Invoke-ContentSync.ps1
    - scripts/Stage-Repository.ps1
    - config/task-DeresoContentSync.xml
    - config/task-DeresoRepoStage.xml
    - tests/pester/Invoke-ContentSync.Tests.ps1
    - tests/pester/Stage-Repository.Tests.ps1
  modified:
    - scripts/Register-AutomationTasks.ps1
    - tests/pester/Get-BigFixCredential.Tests.ps1
    - tests/pester/Reconcile-LocalRoles.Tests.ps1
    - .gitignore

key-decisions:
  - "Scan mechanism = POST /api/query with the session-relevance \\x1F tuple ported from fixlet_update_tracker.ojo scanNextSite; the response is normalised from either the { result: [...] } JSON shape (RESEARCH A6) or a <BESAPI>...<Answer> XML shape"
  - "ContentItem gained discovery_kind ('update'|'new'), portal_fixlet_id, reject_reason, repo_staged_at and ContentCache gained note, all nullable TEXT, added by idempotent PRAGMA-gated ALTER inside the two scripts - the shared Initialize-AutomationDb.ps1 and the schema fixture are untouched (D-18 mechanism)"
  - "New-SupersededXml / Get-FixletPathType / the 4-step copy engine landed in the Task 1 commit and Read-PrefetchLine was already there too; Tasks 2/3 add their test coverage. Keeps ContentSyncCore.psm1 + Invoke-ContentSync.ps1 self-contained across atomic commits (same call as 07-02's New-RoleRefRelevance)"
  - "ContentSourceSites and MaxStageFileMB are seeded into PipelineConfig at first run via INSERT OR IGNORE, NOT added to config/PipelineConfig.defaults.json (the 07-00 'exactly 13 keys' test) - same opt-in pattern as 07-01's MaxAgeOutFraction"
  - "config/task-*.xml hand-authored as Task Scheduler 1.2 XML (running Register-AutomationTasks.ps1 registers real tasks on the host); 07-05 regenerates on the root server - carries 07-02's precedent"
  - "New portal object XML is built FROM SCRATCH (copier.ojo pattern), never by mutating fetched Task XML (memory bigfix-task-to-fixlet-post); the module uses [regex]/string ops, not Msxml2.DOMDocument.6.0 or an [xml] round-trip that would break the byte-identical stamp guarantee"

patterns-established:
  - "ContentSyncCore.psm1 is the single pure seam for the content pipeline - Get-StrippedName uses exactly ' v\\d[\\d.]+' (fixlet_update_tracker.ojo L987) so the pipeline and the dashboard key products identically"
  - "guarded-main dot-source pattern for Pester-testing REST-calling root-server scripts without a live server"
  - "APPEND-ONLY $AutomationTaskTable now has all four rows (07-02 role x2, 07-03 content x2); no plan reorders/rewrites another plan's row"

requirements-completed: [FR-01, FR-04, FR-05, FR-10, NFR-NEW]

duration: 115min
completed: 2026-08-30
---

# Phase 7 Plan 03: Content Pipeline Summary

**The `fixlet_update_tracker.ojo` scan+copy loop and the Dispatcher's prefetch-staging step are now two scheduled server-side scripts: `Invoke-ContentSync.ps1` scans the configured source sites for newer/added product fixlets and records `discovered` ContentItems keyed exactly like the dashboard, copies operator-approved (`stage='ready'`) items into the portal site with their category and `Associated_Roles` intact while stamping the superseded fixlet with exactly one idempotent `X-Superseded-By`, and `Stage-Repository.ps1` downloads every copied fixlet's prefetch installer from its original URL, SHA1- and byte-length-verifies it, and places it where the Dispatcher's `rewritePrefetchUrls()` output resolves - a hash mismatch is always discarded, never staged.**

## Performance

- **Duration:** ~115 min
- **Started:** 2026-08-30T16:55:00Z
- **Completed:** 2026-08-30T18:50:00Z
- **Tasks:** 3 completed
- **Files created:** 7
- **Files modified:** 4

## Accomplishments

- **`ContentSyncCore.psm1`** - six pure functions, zero REST/DB/file I/O. `Get-StrippedName` reproduces every `stripVersion` case in `tests/unit/update_tracker.test.js` byte-for-byte (the 'v2' product-family label in "AWS CLI v2" is preserved; only the long token is stripped); `Compare-FixletVersion` orders `1.2` before `1.10` numerically; `New-SupersededXml` is byte-identical on a second application; `Read-PrefetchLine` has regex parity with `fixlet_dispatcher.ojo extractPrefetchLines` including the optional `sha256:` suffix and lower-cases the sha1.
- **`Invoke-ContentSync.ps1`** - `POST /api/query` scan of each source site (relevance ported from `scanNextSite`), version diff keyed on `Get-StrippedName`, D-12 `INSERT OR IGNORE` + guarded `UPDATE` writing `discovered` ContentItems (a row already past `discovered` is never downgraded; no `INSERT OR REPLACE`), then the 4-step copy over `stage='ready'` rows only (`-AutoApprove` OFF by default per D-26): GET the superseded portal XML, GET the source XML (SINGULAR path via `Get-FixletPathType`), `POST` a from-scratch portal object to `fixlets/custom/<site>` (PLURAL), `PUT` the superseded item back with `New-SupersededXml`. A failed step rejects that one item (`stage='rejected'` + reason + `Items_Failed++` + Event 8030) and the run continues; on a clean run it chains `Start-ScheduledTask -TaskName 'DeresoRepoStage'`.
- **`Stage-Repository.ps1`** - for each `live` ContentItem not yet staged: GET the new portal fixlet's action script, `Read-PrefetchLine` every line, skip any sha1 already cached `verified=1` (dedupe), enforce `MaxStageFileMB` (default 4096) and `-MaxItems`, download from the **original** URL, `Get-FileHash -Algorithm SHA1` **and** byte-length check against the prefetch line; a match lands at `<StagingRoot>\<sha1-lowercase>\<filename>` (StagingRoot from `wwwRootFolder`), a mismatch deletes the temp file, writes `ContentCache verified=0` with an expected/actual note, raises Event 8040, and continues.
- **Both content scheduled tasks** appended to the shared `$AutomationTaskTable` (`DeresoContentSync` Weekly, `DeresoRepoStage` OnDemand) with hand-authored `config/task-*.xml` run-book exports; the two 07-02 role rows and the APPEND-ONLY header are byte-identical.
- **224 Pester tests pass** (0 fail, 1 Slow not-run) - 54 new across the two 07-03 suites - and all 8 Node unit suites still exit 0 (`update_tracker.test.js`, the JS half of the strip/extract parity pair, unchanged).

## Task Commits

1. **Task 1: ContentSyncCore pure module + Invoke-ContentSync scan/diff** - `81e9270` (feat)
2. **Task 2: copy-engine + New-SupersededXml coverage** - `137de16` (test)
3. **Task 3: Stage-Repository.ps1 + content scheduled tasks** - `847a735` (feat)
   - follow-up `bc10cfa` (fix) - keep the `INSERT OR REPLACE` literal out of a code comment (acceptance gate)
   - follow-up `1035269` (test) - update the 07-02 `Reconcile-LocalRoles.Tests.ps1` Register-AutomationTasks Describe to the 4-row state

**Plan metadata:** _this commit_ (docs: complete plan)

## Files Created/Modified

### Created
- `scripts/ContentSyncCore.psm1` - the pure content-pipeline seam. `grep -v '^#' | grep -cE "Invoke-RestMethod|Invoke-SqliteCommand|Set-Content|Write-Host"` = 0.
- `scripts/Invoke-ContentSync.ps1` - scan + diff + 4-step copy + supersede stamp + staging-task chain. Error codes 6900-6919; Event 8030. `grep -v '^#' | grep -c "INSERT OR REPLACE"` = 0; `grep -c "Msxml2"` = 0.
- `scripts/Stage-Repository.ps1` - prefetch parse + download + SHA1/size verify + Custom Repository placement + ContentCache rows. Error codes 6910/6920; Event 8040. `grep -v '^#' | grep -c "127.0.0.1"` = 0; contains `wwwRootFolder` + `Get-FileHash`.
- `config/task-DeresoContentSync.xml`, `config/task-DeresoRepoStage.xml` - Task Scheduler 1.2 exports; both parse as `[xml]`.
- `tests/pester/Invoke-ContentSync.Tests.ps1` - 40 tests (5 `stripVersion` JS cases ported one-for-one, `Compare-FixletVersion` ordering, `Get-FixletPathType`, `New-SupersededXml` idempotence, mocked scan/diff, mocked 4-step copy incl. plural POST / singular fixlet|task PUT / 400-then-continue / category+roles carry / `-AutoApprove` gate / `-WhatIf`).
- `tests/pester/Stage-Repository.Tests.ps1` - 14 tests (`Read-PrefetchLine` incl. `sha256:`, exact staged path, SHA1 mismatch + size mismatch discard, dedupe = zero re-download, `MaxStageFileMB` skip, `-WhatIf`, 4-row task table, config XML parse).

### Modified
- `scripts/Register-AutomationTasks.ps1` - APPENDED `DeresoContentSync` + `DeresoRepoStage`; helper, header comment and the 07-02 role rows untouched.
- `tests/pester/Get-BigFixCredential.Tests.ps1` - Register-AutomationTasks Describe from the Wave 2 two-row state to the Wave 3 four-row state.
- `tests/pester/Reconcile-LocalRoles.Tests.ps1` - same update to its 07-02 Register-AutomationTasks Describe ("once per task" 2 -> 4; 07-03 rows now asserted present, not absent).
- `.gitignore` - ignore the Pester `-CI` `testResults.xml` artifact.

## Interfaces delivered (consumed by 07-04 / 07-05)

- **`ContentItem`** lifecycle `discovered -> staged -> categorized -> ready -> live | rejected`; new columns `discovery_kind` (`update`|`new`), `portal_fixlet_id`, `reject_reason`, `repo_staged_at`.
- **`ContentCache`** rows keyed by `sha1`: `filename`, `original_url`, `staged_at`, `size_bytes`, `verified` (0|1), `note` (expected/actual on a discard).
- **`SyncRun`** rows of `Type` `ContentSync` / `RepoStage` + per-run JSON logs under `<repo>\logs`.
- **Scheduled task names** `DeresoContentSync`, `DeresoRepoStage`.
- **`ContentSyncCore.psm1`** exports: `Get-StrippedName`, `Get-ExtractedVersion`, `Compare-FixletVersion`, `Get-FixletPathType`, `New-SupersededXml`, `Read-PrefetchLine`.

## Deviations from Plan

### Auto-fixed / plan-reconciliation

**1. [Rule 3 - avoid re-editing a fresh file across atomic commits] `New-SupersededXml` + `Get-FixletPathType` + the 4-step copy engine + `Read-PrefetchLine` landed in the Task 1 commit**
- **Found during:** Task 1.
- **Issue:** the plan places `New-SupersededXml` and the copy engine in Task 2 and `Read-PrefetchLine` in Task 3, but all six pure functions belong in one module and the copy engine is one contiguous block in `Invoke-ContentSync.ps1`. Splitting them across commits means re-editing a just-created file for no benefit.
- **Fix:** wrote the complete `ContentSyncCore.psm1` and `Invoke-ContentSync.ps1` (scan + copy engine) in the Task 1 commit `81e9270`. Task 2 (`137de16`) added the `New-SupersededXml` idempotence + copy-engine Pester coverage; Task 3 (`847a735`) added `Read-PrefetchLine` + `Stage-Repository.ps1` coverage. Same call as 07-02's `New-RoleRefRelevance`.
- **Files:** `scripts/ContentSyncCore.psm1`, `scripts/Invoke-ContentSync.ps1`.

**2. [Rule 3 - schema lacks columns required for the documented behaviour] five additive AutomationState.db columns**
- **Found during:** Task 1 (ContentItem) and Task 3 (ContentCache).
- **Issue:** `ContentItem` (from 07-00) has no column to (a) distinguish an update from a new arrival for the 07-04 Content Queue, (b) hand `Stage-Repository.ps1` the new portal fixlet id, (c) record a rejection reason, (d) mark an item repo-staged; `ContentCache` has no field to record the expected/actual hash on a discard.
- **Fix:** each script ensures its own columns via an idempotent `PRAGMA table_info`-gated `ALTER TABLE` (the D-18 `Map`-migration mechanism) at first non-`-WhatIf` run: `ContentItem.discovery_kind`, `.portal_fixlet_id`, `.reject_reason`, `.repo_staged_at`; `ContentCache.note`. All nullable `TEXT`. The shared `Initialize-AutomationDb.ps1` and `tests/fixtures/phase-07/automation-db-schema.sql` are **not** touched (07-00's exact-table-list test still passes).
- **Files:** `scripts/Invoke-ContentSync.ps1`, `scripts/Stage-Repository.ps1`.

**3. [Rule 1 - test broken by this task's change] two 07-02 suites hard-coded a two-row `$AutomationTaskTable`**
- **Found during:** Task 3 full-suite regression.
- **Issue:** `tests/pester/Get-BigFixCredential.Tests.ps1` and `tests/pester/Reconcile-LocalRoles.Tests.ps1` asserted the table held exactly `DeresoRoleIngest` + `DeresoRolePublish`, that `DeresoContentSync`/`DeresoRepoStage` were **absent**, and "a normal run invokes Register-ScheduledTask once per task (2)". The APPEND-ONLY contract this plan honours makes it four.
- **Fix:** updated both Describes to the Wave 3 four-row state - still asserting one `$AutomationTaskTable` definition, the two 07-02 role rows + their `Script` values, and the APPEND-ONLY header comment intact; "once per task" is now 4.
- **Files:** `tests/pester/Get-BigFixCredential.Tests.ps1`, `tests/pester/Reconcile-LocalRoles.Tests.ps1`.
- **Commits:** `847a735`, `1035269`.

**4. [Rule 3 - portability] dropped `-WhatIf:$false` from `Write-EventLog`**
- **Found during:** Task 3 (Stage-Repository Pester run on pwsh 7.6).
- **Issue:** `Publish-RoleSnapshot.ps1`'s event-log helper calls `Write-EventLog ... -WhatIf:$false`. On pwsh 7.x `Write-EventLog` has no `-WhatIf` parameter and raises a binding error (noisy even though the `try/catch` swallows it).
- **Fix:** removed `-WhatIf:$false` from both `Write-ContentSyncEvent` and `Write-RepoStageEvent`; the `try/catch` already guards an unregistered source. (5.1 keeps the parameter; the behaviour difference under `-WhatIf` on an error path is negligible.)
- **Files:** `scripts/Invoke-ContentSync.ps1`, `scripts/Stage-Repository.ps1`.

**5. [Rule 3 - acceptance gate] reworded a comment containing the literal `INSERT OR REPLACE`**
- **Found during:** post-Task-3 acceptance-gate check.
- **Issue:** the acceptance gate is `grep -v '^#' scripts/Invoke-ContentSync.ps1 | grep -c "INSERT OR REPLACE"` = 0, but `grep -v '^#'` only strips column-0 `#`, not the indented D-12 discipline comment that named the anti-pattern.
- **Fix:** reworded to "a delete-and-reinsert upsert is never used" (same technique 07-00 used for `CacheEntry`). Commit `bc10cfa`.
- **Files:** `scripts/Invoke-ContentSync.ps1`.

### Not deviations
- **`ContentSourceSites` and `MaxStageFileMB`** are seeded into `PipelineConfig` at first run via `INSERT OR IGNORE`, **not** added to `config/PipelineConfig.defaults.json` (07-00's "exactly 13 keys" test). Same opt-in pattern as 07-01's `MaxAgeOutFraction`.
- **`-AutoApprove` OFF by default** and the copy engine gating on `stage='ready'` are the D-26 rollout design, not a stub.

### Auth gates
None. `Get-BigFixCredential.ps1` is never invoked in the test path (every suite passes a dummy `[pscredential]` and mocks `Invoke-RestMethod` / `Invoke-WebRequest`). Live AKeyless + operator-credentialed POST/PUT is a 07-05 concern.

## Known Stubs
None. The scan, diff, 4-step copy, supersede stamp, prefetch download/verify/place, dedupe, guards, task chaining and `-WhatIf` paths are all wired and Pester-covered. No hardcoded empty returns, no placeholder text, no unwired data source.

## Threat Surface
No new trust boundaries beyond the plan's `<threat_model>`. Mitigations implemented + tested:
- **T-07-03-01** (swapped installer) - `Get-FileHash -Algorithm SHA1` AND byte-length checked before placement; any mismatch deletes the temp file, writes `ContentCache verified=0` + note, raises Event 8040, continues. Pester: a mismatched hash and a mismatched size each leave zero files under `StagingRoot`.
- **T-07-03-02** (untrusted relevance/ActionScript) - copy gated on `stage='ready'` (operator-set), `-AutoApprove` OFF (D-26); source sites are the fixed `PipelineConfig.ContentSourceSites` list.
- **T-07-03-03** (runaway download) - `MaxStageFileMB` (4096) + `-MaxItems` + sha1 dedupe; exceeding a limit skips + logs. Pester: an oversize file triggers zero `Invoke-WebRequest`.
- **T-07-03-04** (non-idempotent stamp) - `New-SupersededXml` strips every existing `X-Superseded-By` first; Pester asserts two applications are byte-identical and a stale value is replaced not duplicated. New portal objects built from scratch, no `Msxml2`, no `[xml]` round-trip.
- **T-07-03-05** (repudiation) - `ContentItem` (`stage`/`copied_at`/`category`/`roles`/`portal_fixlet_id`), `ContentCache` (`sha1`/`original_url`/`staged_at`/`verified`), `SyncRun` rows + per-run JSON logs.
- **T-07-03-07** (one bad item aborts the run) - per-item `try/catch` -> `stage='rejected'` + reason + Event 8030; `SyncRun.Status` becomes `partial`. Pester: a mocked 400 on the first item still lets the second item copy.
- **T-07-03-SC** (package installs) - zero external packages; `Invoke-RestMethod` / `Invoke-WebRequest` / `Get-FileHash` / `Register-ScheduledTask` are built-ins.

## Verification
- `Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI` -> **224 passed, 0 failed, 1 not-run (Slow)**.
- All 8 Node unit suites -> exit 0 (`update_tracker.test.js` in particular; this plan touches no JS).
- `node tests/unit/update_tracker.test.js` -> 31 passed.
- Acceptance greps: `ContentSyncCore.psm1` forbidden-cmdlet count 0; `Invoke-ContentSync.ps1` `INSERT OR REPLACE` count 0, `Msxml2` count 0; `Stage-Repository.ps1` `127.0.0.1` count 0, contains `wwwRootFolder` + `Get-FileHash`; `$AutomationTaskTable` = single definition, four rows.
- Both `config/task-*.xml` parse as `[xml]` (Pester).
- Live BigFix behaviour (real `POST /api/query` response shape, operator-credentialed POST/PUT, prefetch download from a real vendor URL, the on-disk `wwwRootFolder` path on the production root server) is NOT exercised here - carried to the 07-05 `-WhatIf` dry-run + rollout.

## Self-Check: PASSED

All 8 created files verified present on disk (`scripts/ContentSyncCore.psm1`, `scripts/Invoke-ContentSync.ps1`, `scripts/Stage-Repository.ps1`, `config/task-DeresoContentSync.xml`, `config/task-DeresoRepoStage.xml`, `tests/pester/Invoke-ContentSync.Tests.ps1`, `tests/pester/Stage-Repository.Tests.ps1`, this SUMMARY).

All 5 task/fix commits verified in `git log`: `81e9270`, `137de16`, `847a735`, `bc10cfa`, `1035269`.
