---
phase: 07-automation
plan: 00
subsystem: infra
tags: [sqlite, powershell, pester, akeyless, scheduled-tasks, bigfix, role-pipeline, test-fixtures]

requires:
  - phase: 05-robustness
    provides: "RoleAwareness.db Map schema (v2/v3), Valid_to renewal, RoleDB_Maintenance logon task, Sqlite-Helper.ps1"
  - phase: 04-role-assigner
    provides: "base64 chunk / action XML break-glass path, Node assert test harness shape"
provides:
  - "scripts/Initialize-AutomationDb.ps1 - one-command AutomationState.db: 11 tables, 13 Region seeds (D-21), 3 canonical Role names, PipelineConfig seed, Event Log source, sqlite3.exe preflight, -WhatIf plan mode"
  - "config/PipelineConfig.defaults.json - 13 documented seed keys, zero secrets"
  - "scripts/Get-BigFixCredential.ps1 - AKeyless universal-identity [pscredential] provider (D-20), no secret at rest, Event 8001 on every failure class"
  - "scripts/Register-AutomationTasks.ps1 - APPEND-ONLY scheduled-task table skeleton (empty in Wave 0) that 07-02 and 07-03 add rows to"
  - "D-18 Map migration in Dashboard_4_samples/Initialize-RoleDb.ps1 - Source_Type / Source_Value / Region / Assigned_By added idempotently"
  - "the uncommitted logon-rework (Initialize-RoleDb.ps1 v3 + Init  Current User and UserRole DB.bes) committed under Phase 7"
  - "tests/pester/ harness (README + 3 suites), tests/pester/Assert-SnapshotShape.ps1 shared contract, tests/fixtures/phase-07/ (6 fixtures), tests/unit/role_admin.test.js stub"
affects: [07-01, 07-02, 07-03, 07-04, 07-05]

tech-stack:
  added: []
  patterns:
    - "scripts/*.ps1 resolve the single shared Sqlite-Helper.ps1 via a -SqliteHelperPath param defaulting into Dashboard_4_samples\\ (no copy)"
    - "root-server scripts take -WhatIf (SupportsShouldProcess): full [WOULD ...] plan + JSON run summary, zero writes / zero API calls"
    - "numeric throw error codes, continuing the Initialize-RoleDb.ps1 scheme (6000-6600 for AutomationState.db)"
    - "Pester 5 suites auto-locate sqlite3.exe via $env:SQLDIR + a probe list, and SKIP (not fail) DB contexts when it is absent"
    - "extended-D-11 snapshot shape (users are { id, source_type, source_value } objects) defined once in a dot-sourced Assert-RoleRefSnapshotShape"

key-files:
  created:
    - scripts/Initialize-AutomationDb.ps1
    - scripts/Get-BigFixCredential.ps1
    - scripts/Register-AutomationTasks.ps1
    - config/PipelineConfig.defaults.json
    - config/GroupRoleMap.json
    - tests/pester/README.md
    - tests/pester/Assert-SnapshotShape.ps1
    - tests/pester/Initialize-AutomationDb.Tests.ps1
    - tests/pester/Get-BigFixCredential.Tests.ps1
    - tests/pester/Initialize-RoleDb.Tests.ps1
    - tests/fixtures/phase-07/automation-db-schema.sql
    - tests/fixtures/phase-07/roleawareness-v2.db
    - tests/fixtures/phase-07/axonious-sample-50.csv
    - tests/fixtures/phase-07/axonious-multivalue-edge.csv
    - tests/fixtures/phase-07/grouprolemap-seed.json
    - tests/fixtures/phase-07/roleref-AAG-UK-sample.json
    - tests/unit/role_admin.test.js
  modified:
    - Dashboard_4_samples/Initialize-RoleDb.ps1
    - "Dashboard_4_samples/Init  Current User and UserRole DB.bes"
    - .gitignore

key-decisions:
  - "PipelineConfig (not Config), ContentCache (not the superseded name), one wide SyncRun table with a Type column - 07-RESEARCH Discretion Resolutions"
  - "SQLDir default points at the BES Client EC\\sqlite dir (root server is also a managed client); overridable"
  - "roleawareness-v2.db fixture was built in Task 3 (not Task 4) because Task 3's own Pester suite consumes it"
  - "config/GroupRoleMap.json ships empty-by-design; synthetic rules live only in the test fixture"

patterns-established:
  - "Assert-RoleRefSnapshotShape: single dot-sourced definition of the region-snapshot contract, shared by 07-00 and 07-02"
  - "APPEND-ONLY $AutomationTaskTable: 07-02/07-03 add rows, nobody reorders/rewrites/removes"
  - "Get-BigFixCredential: plaintext confined to one local var, never written to any stream, wrapped in SecureString; failure classes each log a secret-free Event 8001 then rethrow"

requirements-completed: [FR-02, FR-08, NFR-NEW]

duration: 35min
completed: 2026-08-30
---

# Phase 7 Plan 00: Foundation Summary

**The combined `AutomationState.db` init script, the AKeyless credential provider every root-server script will call, the additive endpoint `Map` migration (with the previously-uncommitted logon-rework finally committed under Phase 7), and the complete Pester + fixture harness that Waves 1-5 depend on - all built and green.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-08-30T14:42:00Z
- **Completed:** 2026-08-30T15:17:00Z
- **Tasks:** 4 completed
- **Files created:** 17
- **Files modified:** 3

## Accomplishments

- One command (`Initialize-AutomationDb.ps1`) produces a complete `AutomationState.db` - 11 tables, 13 Region seeds, 3 canonical Role names, 13 PipelineConfig keys - and is fully idempotent: a second run logs `[SKIP]` for every object and changes no row counts. `-WhatIf` writes nothing (no file created against a non-existent path) and prints a JSON plan.
- `Get-BigFixCredential.ps1` returns a `[pscredential]` from AKeyless via Cyera's universal identity with no secret at rest; all four failure modes throw distinguishable, secret-free errors and log Event 8001. A source-scanning Pester test enforces "the secret never leaves a local variable".
- The endpoint `Map` table gains `Source_Type` / `Source_Value` / `Region` / `Assigned_By` via the same `PRAGMA table_info(Map)`-gated `ALTER TABLE` mechanism as `Updated_on` / `Valid_to`; a migration test proves it is additive-only (row count, `Locked_by_Override`, `Created_on` all preserved) and idempotent.
- The in-progress logon-rework (`Initialize-RoleDb.ps1` v3 + the `.bes`) is committed under Phase 7 (D-18). The embedded PowerShell in the `.bes`, extracted and de-escaped (`{{` -> `{`), matches the standalone `.ps1` byte-for-byte with zero `}}` introduced.
- 39 Pester assertions across 3 suites + the 8th Node suite (`role_admin.test.js`) are green; the 7 pre-existing Node suites still pass (regression gate held).

## Task Commits

1. **Task 1: AutomationState.db init script + PipelineConfig seed + schema fixture** - `82d3a9b` (feat)
2. **Task 2: AKeyless credential provider + shared scheduled-task skeleton** - `494691d` (feat)
3. **Task 3: D-18 Map migration + finalise the logon-rework** - `458691d` (feat)
4. **Task 4: Phase 7 test harness - fixtures, snapshot-shape contract, Pester README** - `400f30f` (feat)

## Files Created/Modified

### Created

- `scripts/Initialize-AutomationDb.ps1` - combined 11-table schema init + Region/Role/PipelineConfig seed + Event Log source + sqlite3.exe preflight; error codes 6000-6600; `-WhatIf` plan mode.
- `scripts/Get-BigFixCredential.ps1` - AKeyless universal-identity `[pscredential]` provider; resolves unset `-TokenFile`/`-SecretPath`/`-UserName` from `PipelineConfig`.
- `scripts/Register-AutomationTasks.ps1` - Wave 0 skeleton; empty `$AutomationTaskTable`, `Register-AutomationTask` helper (pwsh.exe preferred, powershell.exe fallback, `schtasks.exe /XML` export).
- `config/PipelineConfig.defaults.json` - 13 seed keys incl. `ConsoleUserRelevance` (the RESEARCH Pitfall 2 one-line config seam); no secret values.
- `config/GroupRoleMap.json` - empty-by-design production rules seed.
- `tests/pester/README.md` - Pester 5 pinning + `SQLDIR` probe-order contract + Slow-tag rule + inventory.
- `tests/pester/Assert-SnapshotShape.ps1` - dot-sourced `Assert-RoleRefSnapshotShape` (extended-D-11 shape).
- `tests/pester/Initialize-AutomationDb.Tests.ps1` - 17 tests.
- `tests/pester/Get-BigFixCredential.Tests.ps1` - 14 tests (Invoke-RestMethod mocked).
- `tests/pester/Initialize-RoleDb.Tests.ps1` - 8 tests (D-18 migration).
- `tests/fixtures/phase-07/automation-db-schema.sql` - full 11-table DDL.
- `tests/fixtures/phase-07/roleawareness-v2.db` - pre-migration endpoint DB (v2 Map, 4 rows, one `Locked_by_Override=1`, no `-wal`/`-shm`).
- `tests/fixtures/phase-07/axonious-sample-50.csv` - 44-row anonymised carve: BOM, blank-SAM + blank SAM+UPN rows, quoted 3-line group cell, LDAP-DN group + bare display name, all 47 headers, ~39 KB.
- `tests/fixtures/phase-07/axonious-multivalue-edge.csv` - 4-row D-07 loose-alignment set.
- `tests/fixtures/phase-07/grouprolemap-seed.json` - 7 synthetic rules (cn exact / cn wildcard / display / dn / Active=0 / same-group-two-roles).
- `tests/fixtures/phase-07/roleref-AAG-UK-sample.json` - extended-D-11 snapshot fixture; pipe-joined `source_value`, Mailing List + AD Security Group sources, `Contract Support` role (absent from a stock `RoleAwareness.db`), and the deliberately-absent user `ktanaka` (documented in the README as the General-Access default case).
- `tests/unit/role_admin.test.js` - house-harness stub; `scaffold` section has real passing assertions; four placeholder sections for 07-04.

### Modified

- `Dashboard_4_samples/Initialize-RoleDb.ps1` - v4 migration block (4 new Map columns) + v4 help section; D-12 help note reworded so `INSERT OR REPLACE` appears exactly once (the stateless `Users` write).
- `Dashboard_4_samples/Init  Current User and UserRole DB.bes` - logon-rework v3 committed + same v4 migration in the embedded copy (opening-brace-only escaping).
- `.gitignore` - ignore `SampleAxonious/` (420 MB PII export) and `*.db-wal` / `*.db-shm`.

## Interfaces delivered (consumed by Waves 1-5)

- **`AutomationState.db`** - 11 tables exactly as named in the plan `<interfaces>` block; 13 Region rows (D-21 spelling), 3 Role rows, 13 PipelineConfig keys.
- **`Get-BigFixCredential.ps1`** - `param([string]$DatabasePath,[string]$SQLDir,[string]$TokenFile,[string]$SecretPath,[string]$UserName)` (+ `-SqliteHelperPath`, `-WhatIf`) returning `[pscredential]`.
- **Endpoint `Map`** - `Source_Type TEXT, Source_Value TEXT, Region TEXT, Assigned_By TEXT`.
- **Event Log** - source `DereseSoftwarePortal`, LogName Application, credential-failure Event 8001.
- **`Assert-RoleRefSnapshotShape -Snapshot <obj> [-ExpectedRegion <str>]`** - dot-sourced from `tests/pester/Assert-SnapshotShape.ps1`.
- **`$AutomationTaskTable`** - empty array; row keys `Name, Script, Arguments, Trigger, RunLevel, User, Description`; APPEND-ONLY.

## Deviations from Plan

### Auto-fixed / plan-contradiction resolutions

**1. [Rule 1 - plan-internal contradiction] `CacheEntry` comment vs. the ZERO-occurrences acceptance gate**
- **Found during:** Task 1.
- **Issue:** the action text for step 6200 asks for a comment saying `ContentCache` "was `CacheEntry` in the superseded design", but an acceptance criterion requires ZERO occurrences of the literal `CacheEntry` in the script.
- **Fix:** the comment names the concept without the forbidden literal ("the superseded 2026-08-01 design used a different table name"). Same treatment for `Add-Type` / `System.Data.SQLite` in the doc comment (reworded to "no dynamic .NET type loading, no ADO SQLite provider").
- **Files:** `scripts/Initialize-AutomationDb.ps1`.
- **Commit:** `82d3a9b`.

**2. [Rule 3 - blocking] `roleawareness-v2.db` fixture built in Task 3, not Task 4**
- **Found during:** Task 3.
- **Issue:** Task 3's `<verify>` runs `Initialize-RoleDb.Tests.ps1`, which copies `tests/fixtures/phase-07/roleawareness-v2.db` - a file the plan lists under Task 4's `<files>`. Per-task atomic commits mean the fixture must exist at Task 3 commit time.
- **Fix:** built the v2 fixture (Python `sqlite3`, byte-valid, `journal_mode=DELETE` so no `-wal`/`-shm` sidecar, `VACUUM`) and committed it with Task 3. Task 4's acceptance for that file is satisfied by the earlier commit.
- **Files:** `tests/fixtures/phase-07/roleawareness-v2.db`.
- **Commit:** `458691d`.

**3. [Rule 1 - plan-internal contradiction] `INSERT OR REPLACE` count in `Initialize-RoleDb.ps1`**
- **Found during:** Task 3.
- **Issue:** acceptance requires `grep -c "INSERT OR REPLACE"` to return exactly 1 (the `Users` statement), but the pre-existing v2 `.NOTES` help text also contained the literal string ("INSERT OR REPLACE is prohibited"), making the count 2.
- **Fix:** reworded that help sentence ("A delete-and-reinsert upsert is prohibited on any stateful table ... the Users table is the sole exception") in both the standalone `.ps1` and the embedded `.bes` copy. Count is now 1.
- **Files:** `Dashboard_4_samples/Initialize-RoleDb.ps1`, `Dashboard_4_samples/Init  Current User and UserRole DB.bes`.
- **Commit:** `458691d`.

### Environment notes (not deviations)

- **sqlite3.exe** is not on `PATH` on the dev host, but a valid 3.53.1 build exists at
  `C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite\sqlite3.exe` (this host is
  itself a managed BES client). The Pester suites probe that path, so all DB-backed tests
  actually ran here. On a host without it, those contexts skip and the suites still exit 0.
- Outbound network is blocked in this environment, so the pinned sqlite-tools zip could not
  be downloaded - not needed, since a local build was found. `Initialize-AutomationDb.ps1`
  error 6000 still throws with the full remediation text (version + sha1 + CustomRepository
  URL) when `-SQLDir` has no `sqlite3.exe`, as designed.

### Auth gates

None. `Get-BigFixCredential.ps1`'s AKeyless calls are fully mocked in tests; no live
authentication was attempted (that is a 07-05 concern).

## Known Stubs

- `tests/unit/role_admin.test.js` - four sections (`switchTab`, `GroupRoleMap row validation`,
  `Test Pattern matcher`, `base64 chunk chain`) are intentional placeholders with no
  assertions; the `fixlet_role_admin.ojo` they mirror is built in **07-04**. The `scaffold`
  section has real passing assertions so the file is a valid regression-chain member today.
  This is an intended Wave 0 stub, explicitly scoped to 07-04 by the plan.
- `scripts/Register-AutomationTasks.ps1` - `$AutomationTaskTable` is intentionally empty in
  Wave 0; 07-02 and 07-03 append rows. Documented APPEND-ONLY contract, not an accidental
  stub.
- `config/GroupRoleMap.json` - `rules: []` is empty-by-design (deferred go-live gate per
  07-CONTEXT); synthetic rules for testing live in `tests/fixtures/phase-07/grouprolemap-seed.json`.

## Verification

- `Invoke-Pester -Path tests/pester -CI` -> **39 passed, 0 failed, 0 skipped** (sqlite3.exe present via probe).
- `node tests/unit/role_admin.test.js` -> exit 0 (3 passed).
- 7 pre-existing Node suites (copier, modifier, dispatcher, role_assigner, update_tracker, fixlet_console, open_deployments) -> all exit 0.
- `git status --porcelain "Dashboard_4_samples/Initialize-RoleDb.ps1" "Dashboard_4_samples/Init  Current User and UserRole DB.bes"` -> empty (both committed).
- `Initialize-AutomationDb.ps1 -WhatIf` against a non-existent path -> no file created, JSON run summary printed (Pester-verified).
- Embedded `.bes` PowerShell, extracted and `{{`->`{` de-escaped, is byte-identical to the standalone `Initialize-RoleDb.ps1`; zero `}}` sequences.
- `git check-ignore SampleAxonious/axonius-users_anond.csv` -> exit 0.

## Self-Check: PASSED

All 17 created files verified present on disk:

- scripts/Initialize-AutomationDb.ps1 - FOUND
- scripts/Get-BigFixCredential.ps1 - FOUND
- scripts/Register-AutomationTasks.ps1 - FOUND
- config/PipelineConfig.defaults.json - FOUND
- config/GroupRoleMap.json - FOUND
- tests/pester/README.md - FOUND
- tests/pester/Assert-SnapshotShape.ps1 - FOUND
- tests/pester/Initialize-AutomationDb.Tests.ps1 - FOUND
- tests/pester/Get-BigFixCredential.Tests.ps1 - FOUND
- tests/pester/Initialize-RoleDb.Tests.ps1 - FOUND
- tests/fixtures/phase-07/automation-db-schema.sql - FOUND
- tests/fixtures/phase-07/roleawareness-v2.db - FOUND
- tests/fixtures/phase-07/axonious-sample-50.csv - FOUND
- tests/fixtures/phase-07/axonious-multivalue-edge.csv - FOUND
- tests/fixtures/phase-07/grouprolemap-seed.json - FOUND
- tests/fixtures/phase-07/roleref-AAG-UK-sample.json - FOUND
- tests/unit/role_admin.test.js - FOUND

All 4 task commits verified in `git log`: `82d3a9b`, `494691d`, `458691d`, `400f30f`.
