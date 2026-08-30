---
phase: 07-automation
plan: 02
subsystem: infra
tags: [powershell, sqlite, pester, bigfix, snapshot, prefetch, policy-fixlet, scheduled-tasks, role-pipeline, clm-safe]

requires:
  - phase: 07-automation
    provides: "AutomationState.db 11-table schema (Region/RolePublication/UserRole/Snapshot/SyncRun/PipelineConfig), Sqlite-Helper.ps1 + ConvertTo-SqliteLiteral, Get-BigFixCredential.ps1, Register-AutomationTasks.ps1 append-only $AutomationTaskTable, Assert-SnapshotShape.ps1, D-18 Map migration + logon-rework, phase-07 fixtures (automation-db-schema.sql, roleawareness-v2.db, roleref-AAG-UK-sample.json)"
  - phase: 07-automation
    provides: "RefUser / UserRole (Active=1, with D-08 Source_Type/Source_Value provenance) / SyncRun rows written by Import-AxoniousExport.ps1"
provides:
  - "scripts/SnapshotBuild.psm1 - pure Build-RegionSnapshot (extended-D-11 shape: users are { id, source_type, source_value } objects, pipe-joined provenance, ordinal-sorted, empty roles array not null), New-PrefetchLine (rewritePrefetchUrls() byte-shape), New-RoleRefRelevance (DB guard AND region gate AND | true-coalesced freshness gate, -IncludeFreshnessGate toggle), Format-RoleRefFixletXml"
  - "scripts/Publish-RoleSnapshot.ps1 - per published region: registry-derived roleref output dir (wwwRootFolder), ConvertTo-Json -Compress body, dated + latest + .sha1 manifest, Snapshot + SyncRun rows; Invoke-RoleRefFixletLifecycle: render template + POST (plural, first publish, id recorded in PipelineConfig.RoleRefFixletId_<rgn>) or PUT (singular); non-2xx -> Snapshot.Status='failed' + Event 8020 + SyncRun.Error_Count++ without aborting other regions; -WhatIf / -SkipFixletPut"
  - "bes/RoleRef-Policy-template.bes - per-region policy Fixlet (NOT SourcedFixletAction); __REGION_LC__ / __PREFETCH_LINE__ / __RECONCILE_PREFETCH__ tokens; combined 3-clause <Relevance>; ActionScript prefetches snapshot + Reconcile-LocalRoles.ps1 as file resources (no createfile, no brace escaping), wow64 redirection before waithidden"
  - "scripts/Reconcile-LocalRoles.ps1 - CLM-safe endpoint reconcile: console-user seam + GetOwner fallback (logon-task path only), region re-check against snapshot.region (the body field), D-12 guarded upsert writing Source_Type/Source_Value/Region/Assigned_By, INSERT OR IGNORE INTO Roles for unknown roles, General-Access no-match = clean success, freshness stamp (client-setting registry key + sidecar), no revoke path"
  - "RoleDB_Maintenance rewired (D-19): two sequential actions (Initialize-RoleDb + Reconcile-LocalRoles); Unregister-ScheduledTask before the not-exists guard so a redeploy adopts the new command line (Pitfall 5)"
  - "scripts/Register-AutomationTasks.ps1 - DeresoRoleIngest + DeresoRolePublish rows appended to the shared table; config/task-DeresoRoleIngest.xml + config/task-DeresoRolePublish.xml run-book exports"
affects: [07-03, 07-04, 07-05]

tech-stack:
  added: []
  patterns:
    - "Pure snapshot/relevance/prefetch/render seam in a .psm1 imported by the publisher AND by Pester (Format-RoleRefFixletXml replaces the <Relevance> CDATA wholesale via New-RoleRefRelevance so -IncludeFreshnessGate toggles per run with no template edit)"
    - "Ordinal (culture-invariant) sort of users + pipe-joins so two runs over identical data emit byte-identical JSON; built_on is a -BuiltOn parameter, not Get-Date, to keep Build-RegionSnapshot pure/deterministic"
    - "-WhatIf writes the snapshot to a throwaway temp dir purely to compute an honest size + sha1, then deletes it - never touches the published roleref tree or the DB"
    - "Policy-Fixlet lifecycle: POST plural fixlets/custom/<site> on first publish (id -> PipelineConfig.RoleRefFixletId_<rgn>), PUT singular fixlet/custom/<site>/<id> after; a failed region sets Snapshot.Status='failed' + Event 8020 and continues"
    - "Endpoint script shipped as a PREFETCHED FILE RESOURCE (RESEARCH Pitfall 11) - zero createfile, zero brace-escaping surface in the .bes and the policy template"
    - "Freshness stamp written as a BES client 'manual setting' registry key roleref_<region-lc>_applied (value + effective date) + a sidecar JSON; failure warns, never fails the reconcile"

key-files:
  created:
    - scripts/SnapshotBuild.psm1
    - scripts/Publish-RoleSnapshot.ps1
    - scripts/Reconcile-LocalRoles.ps1
    - bes/RoleRef-Policy-template.bes
    - config/task-DeresoRoleIngest.xml
    - config/task-DeresoRolePublish.xml
    - tests/pester/Publish-RoleSnapshot.Tests.ps1
    - tests/pester/RoleRefPolicyBes.Tests.ps1
    - tests/pester/Reconcile-LocalRoles.Tests.ps1
  modified:
    - scripts/Register-AutomationTasks.ps1
    - "Dashboard_4_samples/Init  Current User and UserRole DB.bes"
    - tests/pester/Get-BigFixCredential.Tests.ps1

key-decisions:
  - "New-RoleRefRelevance pulled into the Task 1 commit (plan places it in Task 2) so scripts/SnapshotBuild.psm1 is a self-contained module - avoids a second edit to a freshly-created file across atomic commits. Task 2 added Format-RoleRefFixletXml to the same module as planned."
  - "Format-RoleRefFixletXml replaces the whole <Relevance> CDATA with New-RoleRefRelevance output rather than doing __REGION_LC__ token substitution on inline relevance, so 07-05 can flip -IncludeFreshnessGate per region with no template edit. The template still carries the inline 3-clause relevance (with tokens) for readability + the roleref___REGION_LC___applied acceptance marker."
  - "Freshness gate uses `((... as string as time) > 1 * day) | true` - the `| true` coalesces a malformed/unparseable stored stamp to 'needs refresh' so the relevance can never error out."
  - "Unregister-ScheduledTask before the re-register uses -ErrorAction SilentlyContinue, not try/catch (plan wording), because a try { } catch { } inside the ActionScript would add `{{` brace-escaping to a heredoc that currently has none. Same ignore-not-found outcome."
  - ".bes `parameter \"Region\"` is guarded: `if (exists setting \"GPC_Sub_Name\" whose (exists value of it) of client) then (...) else \"\"` - a bare substitution would error the whole action on a host where the setting is unset; blank -> Reconcile-LocalRoles.ps1's registry fallback."
  - "config/task-*.xml hand-authored as valid Task Scheduler 1.2 XML rather than generated by running Register-AutomationTasks.ps1 (which registers real scheduled tasks). 07-05 regenerates them on the real root server."
  - "DeresoRolePublish uses the helper's Daily 3am trigger (same as ingest); 'after ingest' sequencing is deferred to the 07-05 run-book (trigger offset or task chaining)."

patterns-established:
  - "SnapshotBuild.psm1 is the single pure seam: Build-RegionSnapshot / New-PrefetchLine / New-RoleRefRelevance / Format-RoleRefFixletXml - no file I/O, no DB, no REST"
  - "Assert-RoleRefSnapshotShape (07-00) is dot-sourced by the publisher suite AND by Reconcile-LocalRoles.ps1 (when the file is present) so publisher and endpoint validate the same contract"
  - "Get-Rows / Get-DbRows flatten Sqlite-Helper's (return ,$rows) wrapper - never rely on @(Invoke-SqliteCommand ...) for a count (carried from 07-01)"
  - "Single -WhatIf write gate (Invoke-DbWrite) + explicit -WhatIf:$false on the JSON run log so the dry-run audit still writes"

requirements-completed: [FR-02, FR-03, FR-08, NFR-NEW]

duration: 95min
completed: 2026-08-30
---

# Phase 7 Plan 02: Publish + Distribute + Reconcile Summary

**The reference DB is now something endpoints consume: `Publish-RoleSnapshot.ps1` emits one compact `ConvertTo-Json -Compress` snapshot per published region into the registry-derived Custom Repository `roleref` subtree with a `.sha1` manifest, re-PUTs each region's policy Fixlet every run so its `prefetch sha1:` never goes stale, and `Reconcile-LocalRoles.ps1` upserts the console user's roles into the endpoint's `RoleAwareness.db` Map with the region checked twice and the D-12 `Locked_by_Override = 0` discipline preserved exactly - provenance (`Source_Type` / `Source_Value`, pipe-joined) copied straight from the snapshot, a user absent from the snapshot a clean General-Access success, and no revoke path.**

## Performance

- **Duration:** ~95 min
- **Started:** 2026-08-30T16:20:00Z
- **Completed:** 2026-08-30T17:55:00Z
- **Tasks:** 4 completed
- **Files created:** 9
- **Files modified:** 3

## Accomplishments

- **`Build-RegionSnapshot`** projects `UserRole` + `RolePublication` rows into the extended-D-11 shape: `users` are `{ id, source_type, source_value }` OBJECTS (never bare ids), `source_value` / `source_type` pipe-joined and de-duplicated across granting groups, everything ordinal-sorted, `roles` an empty array (not `null`) when nothing is published, `built_on` an injectable parameter so two runs over identical data emit byte-identical JSON. `General Access` is never synthesised.
- **`Publish-RoleSnapshot.ps1`** resolves the output dir from `wwwRootFolder` (never a hard-coded path), validates `-Region` against the `Region` seed (unknown region = hard abort, zero files), loads data with WR-02-compliant one-SELECT-per-call, writes `roleref-<region-lc>-<yyyyMMdd>.json` + `-latest.json` + `-latest.json.sha1` (`<sha1>  <leaf>`, ASCII), records `Snapshot` + `SyncRun` rows, and under `-WhatIf` writes nothing under `roleref` and no DB row (it hashes into a temp dir it then deletes).
- **Policy-Fixlet lifecycle** re-renders `bes/RoleRef-Policy-template.bes` every publish and POSTs (plural `fixlets/custom/<site>`, first publish, id recorded in `PipelineConfig.RoleRefFixletId_<rgn>`) or PUTs (singular `fixlet/custom/<site>/<id>`); a non-2xx sets that region's `Snapshot.Status='failed'`, raises Event 8020, bumps `SyncRun.Error_Count`, and continues to the next region. PS7 `-SkipCertificateCheck` with a 5.1 trust-all fallback, no `Add-Type`.
- **`bes/RoleRef-Policy-template.bes`** is a plain Fixlet (0 `SourcedFixletAction`, 0 `createfile`, 0 `}}`) whose combined `<Relevance>` is the `RoleAwareness.db` existence guard **AND** the single-region `GPC_Sub_Name` gate **AND** the `| true`-coalesced freshness gate. `Reconcile-LocalRoles.ps1` arrives as a prefetched file resource, so there is no brace-escaping surface anywhere in the template.
- **`Reconcile-LocalRoles.ps1`** (CLM-safe, PS 5.1) re-checks `snapshot.region` (the body field, not the file name) and ABORTS on mismatch / missing / invalid-JSON / no-`roles`-array; for each matched role it does `INSERT OR IGNORE INTO Roles` (unknown roles propagate without an init redeploy), `INSERT OR IGNORE INTO Map`, then ONE guarded `UPDATE Map ... Locked_by_Override = 0` + co-located `SELECT changes()`, writing `Source_Type` / `Source_Value` / `Region` / `Assigned_By='AxoniousSync'` verbatim from the matched snapshot user object. A console user in no role block gets `[OK]`, zero rows, the freshness stamp, exit 0 - no warning, no Event Log.
- **`RoleDB_Maintenance` rewired (D-19)**: two sequential actions (`Initialize-RoleDb.ps1` then `Reconcile-LocalRoles.ps1`); an `Unregister-ScheduledTask` (ignore not-found) runs before the `not (exists (scheduled tasks ...))` guard so an already-provisioned endpoint adopts the new two-action command line on redeploy.
- **190 tests green** (170 Pester incl. 46 new across the three 07-02 suites + all 8 Node suites; 1 Slow-tagged Pester test not-run).

## Task Commits

Each task was committed atomically:

1. **Task 1: Build-RegionSnapshot + Publish-RoleSnapshot.ps1 - per-region JSON, latest pointer, .sha1 manifest, Snapshot/SyncRun logging** - `d18fbec` (feat)
2. **Task 2: per-region policy Fixlet template + the daily re-PUT that keeps its prefetch sha1 fresh** - `15798ed` (feat)
3. **Task 3: Reconcile-LocalRoles.ps1 - endpoint console-user D-12 upsert with region re-check + freshness stamp** - `2122c27` (feat)
4. **Task 4: wire the reconcile into RoleDB_Maintenance (D-19) + register the root-server ingest/publish scheduled tasks** - `322bd8a` (feat)

**Plan metadata:** _this commit_ (docs: complete plan)

## Files Created/Modified

### Created

- `scripts/SnapshotBuild.psm1` - pure `Build-RegionSnapshot` / `New-PrefetchLine` / `New-RoleRefRelevance` / `Format-RoleRefFixletXml`. Zero `Invoke-SqliteCommand` / `Invoke-RestMethod` / `Set-Content` / `Get-FileHash`.
- `scripts/Publish-RoleSnapshot.ps1` - the publisher + `Invoke-RoleRefFixletLifecycle`. Error codes 6800-6830. Params `-DatabasePath -SQLDir -Region -OutputDir -RunId -LogDir -SkipFixletPut -SqliteHelperPath -SnapshotModulePath -Credential -BESSite -TemplatePath` + `-WhatIf`.
- `scripts/Reconcile-LocalRoles.ps1` - CLM-safe endpoint reconcile. Params `-ConsoleUser -Region -SnapshotDir -SQLDir -DatabasePath -ValidityMonths -SqliteHelperPath -SnapshotShapePath -StampRegistryPath` + `-WhatIf`.
- `bes/RoleRef-Policy-template.bes` - per-region policy Fixlet template.
- `config/task-DeresoRoleIngest.xml`, `config/task-DeresoRolePublish.xml` - Task Scheduler 1.2 run-book exports (07-05 regenerates on the root server).
- `tests/pester/Publish-RoleSnapshot.Tests.ps1` (19), `tests/pester/RoleRefPolicyBes.Tests.ps1` (13), `tests/pester/Reconcile-LocalRoles.Tests.ps1` (27) - 59 assertions total, all dot-sourcing `Assert-SnapshotShape.ps1` where a snapshot is involved.

### Modified

- `scripts/Register-AutomationTasks.ps1` - APPENDED `DeresoRoleIngest` (`Import-AxoniousExport.ps1`, Daily, SYSTEM/Highest) and `DeresoRolePublish` (`Publish-RoleSnapshot.ps1`, Daily) rows to the shared `$AutomationTaskTable`. Helper untouched.
- `Dashboard_4_samples/Init  Current User and UserRole DB.bes` - added the `Reconcile-LocalRoles.ps1` prefetch item (pinned sha1 `49ebb985...`, size 14675) + copy + `roleref` mkdir + `parameter "Region"` (guarded); `RoleDB_Maintenance` now registers two sequential actions; `Unregister-ScheduledTask` before the re-register guard. Zero `}}`; the `_EO3_` heredoc gained no `{` braces.
- `tests/pester/Get-BigFixCredential.Tests.ps1` - the `Register-AutomationTasks.ps1` Describe updated from the Wave 0 empty-table skeleton to the Wave 2 two-row state (runs under `-WhatIf` with `Register-ScheduledTask` mocked).

## Decisions Made

See the `key-decisions` frontmatter block. Highlights: `New-RoleRefRelevance` landed in the Task 1 commit (module kept self-contained); `Format-RoleRefFixletXml` swaps the whole `<Relevance>` CDATA so the freshness gate is a per-run toggle; the freshness relevance is `| true`-coalesced so a bad stamp never errors it; the `.bes` `Unregister` uses `-ErrorAction SilentlyContinue` (not `try/catch`) to keep the heredoc brace-escape-free; config XMLs are hand-authored run-book references.

## Deviations from Plan

### Auto-fixed / plan-reconciliation

**1. [Rule 3 - avoid re-editing a fresh file across commits] `New-RoleRefRelevance` implemented in Task 1, not Task 2**
- **Found during:** Task 1.
- **Issue:** the plan places `New-RoleRefRelevance` in Task 2, but Task 2's only other module change is `Format-RoleRefFixletXml`, and splitting one small pure module across two commits with a second edit to a just-created file adds churn for no benefit.
- **Fix:** wrote `New-RoleRefRelevance` in the Task 1 `SnapshotBuild.psm1`. Task 2 added `Format-RoleRefFixletXml` to the same module exactly as planned. Task 1 acceptance ("exports `Build-RegionSnapshot` and `New-PrefetchLine`", zero forbidden tokens) is still satisfied.
- **Files:** `scripts/SnapshotBuild.psm1`.
- **Committed in:** `d18fbec`.

**2. [Rule 1 - test broken by this task's change] `Get-BigFixCredential.Tests.ps1` Wave 0 skeleton assertions**
- **Found during:** Task 4 (full-folder regression run).
- **Issue:** 07-00's `Describe 'Register-AutomationTasks.ps1 - Wave 0 skeleton'` asserts `$AutomationTaskTable = @( )` and "0 task(s) selected". Task 4 appends two rows per the plan's explicit APPEND-ONLY contract, so both assertions now fail.
- **Fix:** updated that `Describe` to the Wave 2 state - asserts the two role rows are present, 07-03's rows are not, and runs the script under `-WhatIf` with `Register-ScheduledTask` mocked ("2 task(s) selected", "[WOULD REGISTER]", zero real registrations).
- **Files:** `tests/pester/Get-BigFixCredential.Tests.ps1`.
- **Committed in:** `322bd8a`.

**3. [Rule 3 - blocking / correctness] `.bes` `parameter "Region"` guarded against an unset client setting**
- **Found during:** Task 4.
- **Issue:** a bare `{value of setting "GPC_Sub_Name" of client as string}` substitution errors the entire ActionScript on any endpoint where `GPC_Sub_Name` is not set.
- **Fix:** `{if (exists setting "GPC_Sub_Name" whose (exists value of it) of client) then (value of setting "GPC_Sub_Name" of client as string) else ""}`. Blank -> `Reconcile-LocalRoles.ps1` reads the setting from the local BES client registry.
- **Files:** `Dashboard_4_samples/Init  Current User and UserRole DB.bes`.
- **Committed in:** `322bd8a`.

**4. [Rule 3 - avoid new brace-escaping surface] `Unregister-ScheduledTask` uses `-ErrorAction SilentlyContinue`, not `try/catch`**
- **Found during:** Task 4.
- **Issue:** the plan says "wrapped in a try/catch that ignores 'not found'". A `try { } catch { }` inside the ActionScript / the `_EO3_` heredoc would introduce `{{` brace-escaping into a block that today has none, re-opening the exact risk class RESEARCH Pitfall 11 removes.
- **Fix:** `waithidden powershell.exe -Command "Unregister-ScheduledTask -TaskName 'RoleDB_Maintenance' -Confirm:$false -ErrorAction SilentlyContinue"` - same ignore-not-found behaviour, zero braces.
- **Files:** `Dashboard_4_samples/Init  Current User and UserRole DB.bes`.
- **Committed in:** `322bd8a`.

**5. [Rule 3 - no precedent] Freshness stamp mechanism chosen + documented**
- **Found during:** Task 3.
- **Issue:** the plan says "if no precedent exists, invoke BESClient.exe setting syntax and document the exact call". No existing endpoint script writes a client setting, and there is no supported `BESClient.exe` CLI to set one out-of-band.
- **Fix:** `Set-RoleRefStamp` writes the BES client "manual setting" registry key `HKLM:\SOFTWARE\Wow6432Node\BigFix\EnterpriseClient\Settings\Client\roleref_<region-lc>_applied` with `value` (= `snapshot.built_on`) and `effective date` (RFC-1123-style, `+0000`), plus a sidecar `roleref_<region-lc>_applied.json`. `-StampRegistryPath` overrides the root (tests point it at `HKCU:`). A failure logs `[WARN]` and does NOT fail the reconcile. **07-05 must verify the client actually picks this key up on the production fleet** (it typically applies after the next client restart / gather).
- **Files:** `scripts/Reconcile-LocalRoles.ps1`.
- **Committed in:** `2122c27`.

**6. [Rule 3 - dev-host safety] config task XMLs hand-authored**
- **Found during:** Task 4.
- **Issue:** the plan's generator path is `Register-AutomationTasks.ps1` -> `schtasks /Query /XML`, which registers real scheduled tasks on the host running it.
- **Fix:** hand-authored valid Task Scheduler 1.2 XML for both tasks (`powershell.exe`, the exact arg line, Daily 3am, SYSTEM/Highest, `ExecutionTimeLimit PT0S`) with a header comment naming `Register-AutomationTasks.ps1` as the authoritative generator. Both parse as `[xml]`. 07-05 regenerates on the root server.
- **Files:** `config/task-DeresoRoleIngest.xml`, `config/task-DeresoRolePublish.xml`.
- **Committed in:** `322bd8a`.

---

**Total deviations:** 6 (1 commit-hygiene, 1 broken-test fix, 4 correctness/safety). No scope creep - every deliverable, interface and must-have in the plan is present.

## Issues Encountered

- **Empty-array JSON under PowerShell 5.1.** `[pscustomobject]@{ roles = @() } | ConvertTo-Json` renders `""` on 5.1 and `[]` on pwsh 7. The publisher (assumption A2: root server prefers pwsh 7) and CI (pwsh 7.5.1) both render `[]`, and the empty-roles test asserts the compressed JSON matches `"roles":\s*\[\s*\]`. If the root server ever runs the publisher under 5.1 this needs a shim - flagged for 07-05.
- **`.bes` prefetch sha1/size for `Reconcile-LocalRoles.ps1` are pinned** (`49ebb985c069910d4cdca166ed0ac140da5dec43` / 14675). If `scripts/Reconcile-LocalRoles.ps1` changes in a later plan, both the `.bes` prefetch item and the CustomRepository staged copy must be re-pinned - 07-05 staging step. (The policy Fixlet's own script prefetch line is computed dynamically by `Invoke-RoleRefFixletLifecycle`, so only the `.bes` is static.)
- **`schtasks.exe` under `$ErrorActionPreference='Stop'`** in the Register-AutomationTasks helper: the "normal run" Pester test mocks `Register-ScheduledTask`, `schtasks.exe` and `Set-Content` so the helper's post-register export cannot throw on the mock-empty task.

## User Setup Required

None new. Carried to 07-05 (all pre-existing): the AKeyless operator secret + `BESOperatorUser` for the live policy-Fixlet PUT; verifying the `roleref_<region>_applied` client-setting registry key is honoured on the production fleet; the `name of current user` <-> lowercased sAMAccountName live spot-check; re-pinning the `.bes` `Reconcile-LocalRoles.ps1` prefetch hash after CustomRepository staging; sequencing `DeresoRolePublish` after `DeresoRoleIngest`.

## Threat Surface

No new trust boundaries beyond the plan's `<threat_model>`. Mitigations verified:

- **T-07-02-03 (reconcile overwriting a manual override)** - every `UPDATE Map` carries `Locked_by_Override = 0`; no delete-and-reinsert; no row deletion. Proven by a Pester assertion that an `adavis` / `Business Operations` row with `Locked_by_Override = 1` is byte-identical before and after a reconcile that matches `adavis`.
- **T-07-02-04 (role/group value injected into ActionScript)** - `Reconcile-LocalRoles.ps1` ships as a prefetched file resource; the ActionScript carries only `{name of current user}`, `{value of setting "GPC_Sub_Name"}` and fixed paths. Zero `createfile`, zero `}}`.
- **T-07-02-05 (SQL injection via a snapshot string)** - every value crosses into SQL through `@param` substitution (`ConvertTo-SqliteLiteral`); no interpolated SQL.
- **T-07-02-01 (snapshot tampering)** - `.sha1` manifest + the prefetch hash pin + the reconcile's `snapshot.region` re-check.
- **T-07-02-06 (a script mutating published content daily)** - the lifecycle logs the prefetch sha1/size/leaf diff every run; a failed PUT -> `Snapshot.Status='failed'` + Event 8020, never silent.
- **T-07-02-SC (package installs)** - zero external packages; `Get-FileHash` / `Invoke-RestMethod` / `Register-ScheduledTask` / `ConvertFrom-Json` are built-ins.

## Verification

- `Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI` -> **170 passed, 0 failed, 1 not-run (Slow)**.
- All 8 Node unit suites -> exit 0 (regression gate held; this plan touches no JS).
- `bes/RoleRef-Policy-template.bes` and `Dashboard_4_samples/Init  Current User and UserRole DB.bes` both parse as `[xml]`; `grep -c "}}"` = 0 for both; template `grep -c "SourcedFixletAction"` = 0, `grep -c "createfile"` = 0.
- `scripts/SnapshotBuild.psm1` - zero `Invoke-SqliteCommand` / `Invoke-RestMethod` / `Set-Content` / `Get-FileHash`.
- `grep -v '^#' scripts/Reconcile-LocalRoles.ps1 | grep -cE "INSERT OR REPLACE|DELETE FROM|Add-Type|System\.Data\.SQLite"` -> 0.
- `Publish-RoleSnapshot.ps1 -WhatIf -SkipFixletPut` against a seeded temp DB writes no file under the output dir and no `Snapshot` row (Pester-verified).
- Live BigFix behaviour (prefetch reach on a non-root endpoint, `name of current user` semantics, real `GPC_Sub_Name` values, client honouring the freshness-stamp registry key, live operator-credentialed Fixlet PUT) is explicitly NOT verified here - those are the blocking 07-05 human-verify items.

## Self-Check: PASSED

All 10 created files verified present on disk (`scripts/SnapshotBuild.psm1`, `scripts/Publish-RoleSnapshot.ps1`, `scripts/Reconcile-LocalRoles.ps1`, `bes/RoleRef-Policy-template.bes`, `config/task-DeresoRoleIngest.xml`, `config/task-DeresoRolePublish.xml`, `tests/pester/Publish-RoleSnapshot.Tests.ps1`, `tests/pester/RoleRefPolicyBes.Tests.ps1`, `tests/pester/Reconcile-LocalRoles.Tests.ps1`, this SUMMARY).

All 4 task commits verified in `git log`: `d18fbec`, `15798ed`, `2122c27`, `322bd8a`.
