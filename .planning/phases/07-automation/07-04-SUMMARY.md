---
phase: 07-automation
plan: 04
subsystem: ui
tags: [bigfix, ojo-dashboard, ie9, analysis-property, singleaction, base64-chunk, grogroup-role-map, content-pipeline, node-assert]

requires:
  - phase: 07-automation
    provides: "AutomationState.db schema (GroupRoleMap / RolePublication / Region / RefUser / UserRole / SyncRun / ContentItem / ContentCache / PipelineConfig); scripts/AxoniousParse.psm1 Resolve-Roles matcher; D-18 Map migration (Source_Type/Source_Value/Region/Assigned_By)"
  - phase: 07-automation
    provides: "07-02 snapshot/region model + Reconcile-LocalRoles.ps1 provenance writes; 07-03 ContentItem stage lifecycle (discovered->staged->categorized->ready->live|rejected) + ContentCache verified flag + SyncRun Type values"
  - phase: 04-role-assigner
    provides: "fixlet_role_assigner.ojo base64 chunk chain, SingleAction XML builder, loadAnalysisView GetRelevance pattern, Node assert harness shape"
provides:
  - "Existing Dashboards/fixlet_role_admin.ojo - four-tab console (GroupRoleMap rule authoring + Test Pattern matcher, RolePublication scope, Region one-at-a-time publish picker, read-only Reference DB health)"
  - "Existing Dashboards/fixlet_automation_monitor.ojo - content-pipeline-only four-tab console (Status, Content Queue approve/reject, Repository Cache, PipelineConfig editor) with zero role controls (D-24)"
  - "Dashboard_4_samples/Dereso SWD.bes - map_source in r.db (ID 5) + map_region in r.db (ID 6) Analysis properties over the migrated Map columns"
  - "Existing Dashboards/fixlet_role_assigner.ojo - Analysis view gains Source + Region columns, Analysis last-reported time, CSV panel relabelled BREAK-GLASS; break-glass code path byte-identical"
  - "tests/unit/role_admin.test.js (38 assertions), tests/unit/automation_monitor.test.js (22 assertions, new 9th Node suite), tests/unit/role_assigner.test.js (+6 for mergeAnalysisRows)"
affects: [07-05]

tech-stack:
  added: []
  patterns:
    - "JS matcher mirror: deriveViews + matchesRule + resolveRolesJs reproduce AxoniousParse.psm1 Get-GroupViews/Resolve-Roles exactly; parity is asserted on both sides (Node + Pester)"
    - "Dashboard write path: SingleAction targeted at the root-server BES client (Title>Relevance>ActionScript>Settings>Target), JSON payload -> safeB64Encode -> chunkString(3000) -> createfile of a brace-escaped embedded PowerShell upsert against AutomationState.db"
    - "escapeActionScriptBraces doubles the opening brace only; embedded PowerShell written clean with every closing brace space-separated / on its own line so the escaped output contains zero '}}'"
    - "Analysis-not-reporting-yet degradation: getRelevanceSafe wraps GetRelevance -> [] and every tab renders an explicit empty state + the Analysis last-reported time (Pitfall 8 / Pitfall 12)"
    - "Region picker reads the 13 seeded rows from the Region table, never a hard-coded JS array"

key-files:
  created:
    - Existing Dashboards/fixlet_role_admin.ojo
    - Existing Dashboards/fixlet_automation_monitor.ojo
    - tests/unit/automation_monitor.test.js
  modified:
    - Dashboard_4_samples/Dereso SWD.bes
    - Existing Dashboards/fixlet_role_assigner.ojo
    - tests/unit/role_assigner.test.js
    - tests/unit/role_admin.test.js
    - .planning/phases/07-automation/07-VALIDATION.md

key-decisions:
  - "Dereso SWD.bes new properties use a genuine 3-item tuple split (following text of first %22 of item 0, tuple string item 1, preceding text of first %22 of item 2) rather than the 2-item idiom copied verbatim in 07-RESEARCH L863-871 - the plan <interfaces> block specifies a 3-item tuple UserID/Role/Extra and a 2-item split would fold Role and Source into one field"
  - "Both new dashboards reference AutomationState.db Analysis property names (grouprolemap in a.db, contentitem_rows in a.db, ...) that are NOT created in this plan - Task 2/3 <files> list only the .ojo + test files. Publishing those property bodies is a 07-05 step; until then the dashboards render an explicit 'Analysis not reporting yet' state. The map_source/map_region properties on RoleAwareness.db (Task 1) ARE created and wired."
  - "fixlet_automation_monitor.ojo duplicates the fixlet_role_admin.ojo SingleAction transport (buildConfigWriteActionXml + escapeActionScriptBraces + embedded-PS chunk chain) rather than importing it - .ojo files cannot require across files; the plan explicitly permits 'import or duplicate'"
  - "D-24 (no role controls on the monitor) enforced by keeping the literal strings GroupRoleMap / RolePublication out of fixlet_automation_monitor.ojo entirely, including comments (grep -ci returns 0)"

patterns-established:
  - "matchesRule/resolveRolesJs <-> Resolve-Roles parity, unit-tested both sides (T-07-04-04 mitigation)"
  - "SingleAction-to-root-server-BES-client config write with base64-chunked brace-escaped embedded PowerShell (T-07-04-03 mitigation)"
  - "every externally-sourced value (group DN, user name, file name, URL, rule field) passes through the lifted htmlEscape before innerHTML; asserted with a <script> payload in both new suites (T-07-04-02)"
  - "every data-bearing tab shows the Analysis last-reported time beside its counts (T-07-04-06 / Pitfall 12)"

requirements-completed: [FR-02, NFR-NEW]

duration: 70min
completed: 2026-08-30
---

# Phase 7 Plan 04: Dashboards Summary

**The pipeline Waves 1-3 built is now operable from the BigFix console: a new `fixlet_role_admin.ojo` lets an operator author and test `GroupRoleMap` rules (with a JS Test Pattern matcher provably equivalent to `Resolve-Roles`), see and set publication scope, and publish one region at a time from the seeded 13-value list; a new content-pipeline-only `fixlet_automation_monitor.ojo` gates content copies through explicit approval and surfaces discarded installer hash mismatches, with zero role controls anywhere on it; `fixlet_role_assigner.ojo` gains Source and Region columns that degrade to an em dash when the Analysis has not re-reported and its CSV path is relabelled break-glass while remaining byte-identical; and `Dereso SWD.bes` gains the two `coalesce`-guarded Analysis properties that feed the migrated Map columns.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-08-30T17:53:00Z
- **Completed:** 2026-08-30T19:03:00Z
- **Tasks:** 3 completed
- **Files created:** 3
- **Files modified:** 5

## Accomplishments

- **`fixlet_role_admin.ojo`** (new, 4 tabs). `switchTab` over GroupRoleMap / RolePublication / Region / ReferenceDB. The **Test Pattern** field derives the three group views (`deriveViews` = `Get-GroupViews`, incl. backslash-escaped-comma RDN parsing) and runs `matchesRule` / `resolveRolesJs` - a line-for-line mirror of `AxoniousParse.psm1 Resolve-Roles` (Active=0 never fires, `Match_On` defaults to `cn` and must be `cn|display|dn`, trailing-`*` = ordinal prefix else ordinal equality, ALL matches apply, Priority orders only). `validateRuleRow` blocks blank Pattern / blank Role / bad `Match_On` / a mid-string asterisk and warns on a duplicate `Pattern+Match_On+Role`. Writes go through a SingleAction targeted at the root-server BES client (element order Title→Relevance→ActionScript→Settings→Target) carrying a base64-chunked (`CHUNK_SIZE` 3000) brace-escaped embedded PowerShell upsert against `AutomationState.db`. The Region tab reads the 13 seeded rows from the `Region` table (never a JS array) and publishes one region per explicit `confirm()` that names the region (D-12). The Reference DB tab is read-only: last `Ingest` `SyncRun`, per-role user counts, `RefUser`-by-`Username_Src`, each beside the Analysis last-reported time.
- **`fixlet_automation_monitor.ojo`** (new, 4 tabs, content-pipeline ONLY). Status shows the most recent `SyncRun` per `Type` with a colour-coded status cell and a View Log expander. Content Queue renders `ContentItem` rows with per-stage badge counts (`badgeCounts`); `queueRowModel` marks only `discovered`/`staged`/`categorized` rows actionable (Approve→`ready`, Reject→`rejected`+reason), `live` rows are read-only history with no controls; multi-select approve takes one confirmation. Repository Cache highlights `verified = 0` rows in the error style and counts them prominently (`countUnverified`) as a supply-chain signal, with an unverified-only filter. Config renders every `PipelineConfig` key with its Description as helper text, flags `AKeylessSecretPath` / `AKeylessTokenFile` as PATH-ONLY (never a secret, no password field), and writes through the same SingleAction transport as the role-admin dashboard. `grep -ci "grouprolemap"` and `grep -ci "rolepublication"` both return 0.
- **`Dereso SWD.bes`** gains `map_source in r.db` (ID 5) and `map_region in r.db` (ID 6), `EvaluationPeriod="PT5M"`, SQL `select UserID || ', ' || Role || ', ' || coalesce(Source_Value,'')` / `coalesce(Region,'')` so pre-migration NULL rows still return a well-formed 3-item tuple. The four pre-existing properties and the top-level `<Relevance>` guard are byte-identical; all six Property IDs are unique; the file parses as XML.
- **`fixlet_role_assigner.ojo`** `loadAnalysisView()` now merges the two new properties as Source + Region columns via the pure `mergeAnalysisRows` (mapped_users is the spine; the new properties can never add or drop a row; a missing cell renders as `—`), shows the Analysis last-reported time (`loadAnalysisAge`, Pitfall 12), and the CSV upload panel is retitled **BREAK-GLASS / MANUAL OVERRIDE** with a note pointing at `fixlet_role_admin.ojo`. `parseCsv`, `validateRows`, `buildAssignActionXml`, `buildAssignActionScript` are byte-identical (md5 verified).
- **Tests.** `role_admin.test.js` 3 stub sections replaced → **38 assertions** (switchTab ×4 ids + unknown-id; `validateRuleRow` ×7; matcher ×12 distinct semantics ≥ the 8 Pester `GroupRoleMap` cases; `deriveViews` ×4; base64 chunk chain; `htmlEscape`). `automation_monitor.test.js` new → **22 assertions** (switchTab; `badgeCounts` mixed+empty; `queueRowModel` actionable/read-only incl. no-Approve-on-`live`; `cacheRowModel`+`countUnverified`; `buildPipelineConfigOps`+base64 round-trip; `htmlEscape`). `role_assigner.test.js` **33 → 39** (mergeAnalysisRows: em-dash fallback, null/`[]` parity, htmlEscape neutralisation, malformed-entry skip). **All 9 Node suites green; full Pester run 224 passed / 0 failed** (this plan changed no PowerShell).

## Task Commits

1. **Task 1: Dereso SWD.bes map_source/map_region props + assigner Source/Region columns** - `d21d638` (feat)
2. **Task 2: build fixlet_role_admin.ojo (GroupRoleMap, RolePublication, Region, Reference DB)** - `8aeaefd` (feat)
3. **Task 3: build content-pipeline-only fixlet_automation_monitor.ojo** - `9c2bed9` (feat)

**Plan metadata:** _this commit_ (docs: complete plan)

## Files Created/Modified

### Created
- `Existing Dashboards/fixlet_role_admin.ojo` - four-tab role-administration console; contains `switchTab`, `matchesRule`, `resolveRolesJs`, `validateRuleRow`, `safeB64Encode`, `chunkString`, `htmlEscape`, `AutomationState.db`, `Msxml2.DOMDocument.6.0`, `<meta ... content="IE=9">`; zero `=>` / ` let ` / ` const ` / `Array.prototype.forEach` / backtick / `}}`; `grep -c "APAC-M&A"` = 0.
- `Existing Dashboards/fixlet_automation_monitor.ojo` - four-tab content-pipeline monitor; contains `switchTab`, `ContentItem`, `ContentCache`, `PipelineConfig`, `<meta ... content="IE=9">`; `grep -ci "grouprolemap"` = `grep -ci "rolepublication"` = 0; zero `=>` / ` let ` / ` const ` / backtick / `}}`.
- `tests/unit/automation_monitor.test.js` - 9th Node suite, 22 assertions.

### Modified
- `Dashboard_4_samples/Dereso SWD.bes` - +2 Analysis properties (IDs 5, 6); 4 existing untouched; XML valid; IDs unique.
- `Existing Dashboards/fixlet_role_assigner.ojo` - `mergeAnalysisRows` + `getRelevanceSafe` + `loadAnalysisAge` added; `loadAnalysisView` renders 5 columns; analysis panel thead gains Source + Region + an `#analysisAge` line; CSV panel relabelled break-glass. Break-glass functions byte-identical.
- `tests/unit/role_assigner.test.js` - +`mergeAnalysisRows` section (6 assertions), 33 → 39.
- `tests/unit/role_admin.test.js` - 4 stub sections → real assertions (38 total).
- `.planning/phases/07-automation/07-VALIDATION.md` - full-suite note 8 → 9 Node suites.

## Interfaces delivered (consumed by 07-05)

- **`Dereso SWD.bes` properties** `map_source in r.db` (ID 5) / `map_region in r.db` (ID 6) - 3-item tuple `UserID, Role, coalesce(Source_Value|Region,'')`, `PT5M`.
- **`fixlet_role_admin.ojo`** - reads Analysis properties `grouprolemap in a.db`, `rolepublication in a.db`, `region in a.db`, `syncrun_ingest_latest in a.db`, `roleuser_counts in a.db`, `refuser_src_counts in a.db` (names in `PORTAL_CONFIG.props`); writes via SingleAction running `Upsert-GroupRoleMap.ps1` (createfile'd) against `AutomationState.db`.
- **`fixlet_automation_monitor.ojo`** - reads `syncrun_latest_by_type in a.db`, `contentitem_rows in a.db`, `contentcache_rows in a.db`, `pipelineconfig_rows in a.db`, `content_source_sites in a.db`; writes via SingleAction running `Set-PipelineConfig.ps1`.
- **Field separator** for all `... in a.db` Analysis rows: `\x1F` (`PORTAL_CONFIG.fieldSep`).

## Deviations from Plan

### Auto-fixed / plan-reconciliation

**1. [Rule 1 - the verbatim RESEARCH example would not separate the columns] `Dereso SWD.bes` new properties use a real 3-item tuple split**
- **Found during:** Task 1.
- **Issue:** 07-RESEARCH.md L863-871 shows the new property body copied verbatim from the ID-3 `mapped_users` idiom, which does a **2-item** split `(following text of first "%22" of tuple string item 0 of it, preceding text of first "%22" of tuple string item 1 of it)`. The plan `<interfaces>` block, however, specifies "3-item tuple UserID, Role, coalesce(Source_Value,'')". A 2-item split against a 3-column `||`-concatenated SQL result folds `Role` and the extra column into one field.
- **Fix:** used `(following text of first "%22" of tuple string item 0 of it, tuple string item 1 of it, preceding text of first "%22" of tuple string item 2 of it)` - the first item strips its leading quote, the last strips its trailing quote, the middle item is taken clean. Everything else (SQL body shape, `EvaluationPeriod="PT5M"`, the `EC\SoftwarePortal` path concat) is identical to the ID-3 analog.
- **Files:** `Dashboard_4_samples/Dereso SWD.bes`.
- **Commit:** `d21d638`.
- **Note:** live console rendering of this relevance is a 07-05 human-verify item (the plan's `<verification>` says so explicitly).

**2. [Rule 3 - .ojo files cannot import across files] the monitor duplicates the role-admin SingleAction transport**
- **Found during:** Task 3.
- **Issue:** Task 3 read_first says "reuse its config-write SingleAction builder rather than writing a second one", but a `.ojo` dashboard is a self-contained document - there is no `require`/`include`.
- **Fix:** `buildConfigWriteActionXml`, `buildRootServerRelevance`, `escapeActionScriptBraces` and the base64-chunk + embedded-PowerShell transport are copied into `fixlet_automation_monitor.ojo`. The plan action text explicitly allows this ("import **or duplicate** that builder").
- **Files:** `Existing Dashboards/fixlet_automation_monitor.ojo`.
- **Commit:** `9c2bed9`.

### Not deviations

- **Two pre-existing backticks in `fixlet_role_assigner.ojo`** (a `` `size` `` in a JS comment on ~L294 and a PowerShell `` `n `` newline escape inside a double-quoted JS string on ~L706) are untouched and are **not** JS backtick template literals - the acceptance criterion "zero occurrences of ... a backtick template literal" holds. This plan's edits introduced zero backticks.
- **AutomationState.db Analysis property names referenced by the two new dashboards are not published in this plan** - Task 2/3 `<files>` list only the `.ojo` + test files, and the plan's data-access text calls for "an `EvaluateRelevance` or REST fallback and a clear 'Analysis not reporting yet' state". See Known Stubs.

### Auth gates

None. The dashboards post to the BigFix REST API through the console's own authenticated `API.Post` binding (same as `fixlet_role_assigner.ojo`); no separate credential is entered. Live operator-credentialed POST is exercised in 07-05.

## Known Stubs

- **`fixlet_role_admin.ojo` / `fixlet_automation_monitor.ojo` Analysis reads.** Both dashboards call `GetRelevance` on `... in a.db` Analysis property names that describe `AutomationState.db` content but are **not created in this plan** (only `map_source`/`map_region` on `RoleAwareness.db` were added, Task 1). Every read goes through `getRelevanceSafe` → `[]` and every tab renders an explicit "Analysis not reporting yet" / "(not reporting yet)" empty state plus the Analysis last-reported line. Publishing the `AutomationState.db` Analysis property bodies (client relevance reading the DB on the root-server BES client, Pitfall 8) is a **07-05** step; the property names and the `\x1F` row contract are fixed here in `PORTAL_CONFIG.props`. This is an intended cross-wave boundary, not an accidental stub - the plan scoped Tasks 2/3 to the `.ojo` + test files only.
- **The SingleAction write path (`Upsert-GroupRoleMap.ps1` / `Set-PipelineConfig.ps1`) is createfile'd inline and not live-verified.** The XML element order, base64 chunk chain and brace escaping are unit-tested / grep-verified (zero `}}`); a live console POST + on-root-server DB write is a 07-05 human-verify item (the plan's `<verification>` says "Live console rendering is NOT verified here").

## Threat Flags

None. No new network endpoint, auth path or trust boundary beyond the plan's `<threat_model>`. The SingleAction config-write path is new surface but is explicitly covered by T-07-04-01 / T-07-04-03; `htmlEscape` on every externally-sourced value covers T-07-04-02 and is asserted with a `<script>` payload in both new suites; the Analysis last-reported line on every data-bearing tab covers T-07-04-06.

## Verification

- `node tests/unit/role_admin.test.js` → **38 passed, 0 failed**, exit 0.
- `node tests/unit/automation_monitor.test.js` → **22 passed, 0 failed**, exit 0.
- `node tests/unit/role_assigner.test.js` → **39 passed, 0 failed**, exit 0.
- All 9 Node unit suites (`automation_monitor`, `copier`, `dispatcher`, `fixlet_console`, `modifier`, `open_deployments`, `role_admin`, `role_assigner`, `update_tracker`) → exit 0.
- `pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0; Invoke-Pester -Path tests/pester -ExcludeTagFilter Slow -CI"` → **224 passed, 0 failed, 1 not-run (Slow)** (regression gate held; this plan changed no PowerShell).
- `Dashboard_4_samples/Dereso SWD.bes` parses as XML (`xml.dom.minidom`); Property IDs `1 2 3 4 5 6`, no duplicates; both new bodies contain `coalesce` and `EvaluationPeriod="PT5M"`; `map_source in r.db` / `map_region in r.db` name count = 1 each.
- `fixlet_role_admin.ojo` and `fixlet_automation_monitor.ojo` parse as XML; both contain `<meta http-equiv="X-UA-Compatible" content="IE=9">`; both have zero `=>`, ` let `, ` const `, backtick, `}}`; `role_admin` contains `Msxml2.DOMDocument.6.0` and `AutomationState.db`; `grep -c "APAC-M&A" role_admin` = 0; `grep -ci "grouprolemap"` and `grep -ci "rolepublication"` on `automation_monitor` = 0.
- `fixlet_role_assigner.ojo`: `md5sum` of `parseCsv`, `validateRows`, `buildAssignActionXml`, `buildAssignActionScript` unchanged vs `HEAD`; `grep -c "map_region in r.db"` = 2; zero `=>` / ` let ` / ` const `.
- Node-evaluated `buildRuleUpsertActionScript(...)` and `buildConfigWriteActionScript(...)` outputs contain zero `}}`; the generated SingleAction XML has `<Title>` before `<Relevance>` before `<ActionScript>` before `<Settings>` before `<Target>`.
- Live BigFix console rendering (IE9 webview, `GetRelevance` against real Analysis data, operator-credentialed `API.Post`, the `.bes` property relevance actually evaluating on the root-server client) is **NOT** exercised here - it is a 07-05 human-verify item.

## Self-Check: PASSED

Created files verified present on disk:
- `Existing Dashboards/fixlet_role_admin.ojo` - FOUND
- `Existing Dashboards/fixlet_automation_monitor.ojo` - FOUND
- `tests/unit/automation_monitor.test.js` - FOUND

Task commits verified in `git log`: `d21d638`, `8aeaefd`, `9c2bed9`.
