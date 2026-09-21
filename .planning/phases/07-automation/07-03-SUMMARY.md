---
phase: 07-automation
plan: 03
subsystem: database
tags: [sqlite, powershell, clm-safe, audit-log, sql-injection-defense]

requires:
  - phase: 07-automation
    provides: "Sqlite-Helper.ps1 (Invoke-SqliteCommand / ConvertTo-SqliteLiteral), Assign-RoleMapping.ps1 dot-source + -WhatIf convention"
provides:
  - "scripts/Upsert-RolePublish.ps1 — D-05 root-server audit-store initialiser + per-Publish snapshot writer"
  - "RolePublishRun/RoleUsers append-only schema (RolePublish.db) with the canonical current-membership query"
  - "tests/pester/Upsert-RolePublish.Tests.ps1 — 20-It Pester suite (DDL idempotency, injection defense, snapshot semantics)"
affects: [07-05, 07-06]

tech-stack:
  added: []
  patterns:
    - "Append-only audit table: every Publish event is a NEW RolePublishRun row + a full RoleUsers snapshot; never UPDATE/DELETE/INSERT OR REPLACE"
    - "Fully parameterized batched multi-row INSERT (400 rows/call) using per-row placeholder names (@u0..@uN) instead of raw string interpolation"
    - "-WhatIf performs zero sqlite3.exe invocations (not even a read) because opening a nonexistent DB path materialises an empty file as a side effect of connecting"
    - "PSObject.Properties.Name -contains check before touching an optional JSON payload property, guarding against Set-StrictMode -Version Latest's PropertyNotFoundStrict on ConvertFrom-Json output"

key-files:
  created:
    - scripts/Upsert-RolePublish.ps1
    - tests/pester/Upsert-RolePublish.Tests.ps1
  modified: []

key-decisions:
  - "-WhatIf validates the payload and prints prose [WHATIF] lines describing intended writes, but never calls Invoke-SqliteCommand at all (not even a schema probe) — the only way to guarantee a not-yet-existing -DatabasePath stays absent, since sqlite3.exe creates the file merely by opening it for any statement, read or write."
  - "Missing 'users' key and an empty JSON array ([]) are handled identically: PS 5.1's ConvertFrom-Json collapses [] to $null, so both cases fall through to the same 'legal empty list' path rather than being distinguished (the plan's Task 2 bad-payload list does not include a missing-users-key case, confirming this is intended)."
  - "Batching (400 rows/Invoke-SqliteCommand call, per Import-AxoniousExport.ps1 convention) is combined with full parameterization by generating per-row placeholder names (@u0 ... @u399) rather than following Import-AxoniousExport's raw ConvertTo-SqliteLiteral string-building path — the plan's acceptance criteria require zero interpolated PowerShell variables in any INSERT statement, which the raw-literal-building convention does not satisfy."
  - "Doc comments describing what the script AVOIDS (e.g. 'no dynamic type loading') were phrased to avoid literally containing the banned substrings ('Add-Type', 'INSERT OR REPLACE') themselves, since the plan's acceptance criteria are whole-file greps with no comment-awareness."

patterns-established:
  - "Root-server audit-store schema (RolePublishRun/RoleUsers) and its canonical MAX(RunID) membership query are now the stable contract 07-05 and 07-06 build against verbatim."

requirements-completed: [NFR-03, NFR-02, NFR-05]

duration: ~45min
completed: 2026-09-21
---

# Phase 07 Plan 03: Root-Server Audit Store (Upsert-RolePublish.ps1) Summary

**CLM-safe, fully-parameterized, append-only SQLite audit-store writer (RolePublishRun/RoleUsers) that records one immutable full-membership snapshot per role Publish event, with a 20-It Pester suite covering DDL idempotency, SQL-injection defense, and snapshot semantics.**

## Performance

- **Duration:** ~45 min
- **Tasks:** 2/2 completed
- **Files modified:** 2 (both new)

## Accomplishments

- `scripts/Upsert-RolePublish.ps1` — the single source of truth for the D-05 schema (`RolePublishRun`, `RoleUsers`, `idx_roleusers_run`, `idx_roleusers_role`) and its write semantics, matching the plan's `<interfaces>` parameter contract exactly (`-PayloadPath`, `-DatabasePath`, `-SQLDir`, `-SqliteHelperPath`, `-WhatIf`).
- Payload validation with distinct exit codes: `5401` (helper missing), `5402` (sqlite3.exe missing), `5410` (payload/JSON/role/published_by/users-type errors), `5411` (5000-entry sanity cap).
- Every write is fully parameterized via `Invoke-SqliteCommand -Parameters`; the `RoleUsers` batch insert uses per-row placeholder names (`@u0`..`@uN`) so the 400-row batching convention from `Import-AxoniousExport.ps1` and full parameterization co-exist — zero raw-interpolated SQL anywhere in the file.
- `tests/pester/Upsert-RolePublish.Tests.ps1` — 20 `It` blocks: 3 source-guarantee (no sqlite needed) + 17 DB-backed (skipped, not failed, when `sqlite3.exe` is unavailable), covering first-run schema/index creation, idempotent re-run, the canonical `MAX(RunID)` membership query, history preservation, multi-role independence (D-04), legal empty-user-list runs, the T-07-03-02 SQL-injection payload (`o'brien'); DROP TABLE RoleUsers;--`), username normalisation/dedup/ordinal-sort, `-WhatIf` zero-DB-access, and five bad-payload rejection cases.

## Task Commits

1. **Task 1: Write scripts/Upsert-RolePublish.ps1** - `f86db89` (feat)
2. **Task 2: Pester suite for the audit store** - `6476860` (test)

## Files Created/Modified

- `scripts/Upsert-RolePublish.ps1` - D-05 root-server audit-store initialiser + per-Publish snapshot writer (292 lines)
- `tests/pester/Upsert-RolePublish.Tests.ps1` - Pester 5 suite, 20 `It` blocks (276 lines)

## Decisions Made

- **`-WhatIf` touches the database zero times, not even for a read-only schema probe.** The plan's action block (step 6) describes `-WhatIf` as performing "the schema probe reads", but the hard acceptance criterion — "running with `-WhatIf` against a path that does not yet exist leaves no file on disk" — cannot coexist with that literal reading: `sqlite3.exe` materialises an (empty) database file as a side effect of opening a connection at all, even for a pure `SELECT`. I resolved the tension in favor of the testable acceptance criterion and `Assign-RoleMapping.ps1`'s established `-WhatIf` precedent (early-return, zero DB calls, prose `[WOULD]`/`[WHATIF]` messages), rather than literally probing `sqlite_master`.
- **Empty JSON array and missing `users` key are treated identically (both legal, `UserCount=0`).** PowerShell 5.1's `ConvertFrom-Json` collapses an empty JSON array `[]` to `$null` — it cannot be distinguished from a genuinely absent key at the object-property level. Since the plan's Task 2 bad-payload list never asks for "missing `users` key" to be rejected (only "`users` set to a string" is a rejection case), collapsing both to "legal empty list" satisfies every listed test case without needing raw-text JSON inspection.
- **`Set-StrictMode -Version Latest` guard on optional JSON properties.** A bare `$payload.role` throws `PropertyNotFoundStrict` under strict mode when the JSON payload lacks a `role` key at all (not just `null`) — confirmed by the pre-existing `PSObject.Properties.Name -contains` idiom in `Reconcile-LocalRoles.ps1` for the same reason. Adopted the identical guard for `role`, `published_by`, and `users` so the "missing role" / "missing published_by" bad-payload tests fail cleanly with exit `5410` instead of an unhandled exception.
- **Acceptance-criteria greps are whole-file, not comment-aware.** Doc comments describing what the script deliberately avoids were phrased to never contain the literal substrings `Add-Type` or `INSERT OR REPLACE` (e.g. "no dynamic type-loading helper", "no upsert-by-replace write"), since `grep -c 'Add-Type' scripts/Upsert-RolePublish.ps1` must return exactly `0` including comments.

## Deviations from Plan

None — plan executed as written, with the `-WhatIf` interpretation documented above as a designed resolution of an internal tension between the plan's prose and its own acceptance criteria (not a scope change).

## Issues Encountered

**PowerShell/Pester could not be executed in this sandboxed worktree-agent environment.** Every attempted invocation of `powershell.exe` or `pwsh` (in any form — inline `-Command`, `-File`, with or without arguments) was refused by this session's sandbox with a message about git-operation verification, regardless of the command's actual content. This means:
- The plan's automated verification step (`Invoke-Pester tests/pester/Upsert-RolePublish.Tests.ps1 -Output Detailed -CI`) was **not run** by this executor.
- The AST-parse acceptance check (`[System.Management.Automation.Language.Parser]::ParseFile(...)`) was **not run**.
- The full-estate regression check (`Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI`) was **not run**.

To compensate, I did the following by hand, without a PowerShell interpreter:
- Verified every grep-based acceptance criterion from the plan directly via the `grep`/`wc` tools (`Add-Type` → 0, `INSERT OR REPLACE` → 0, `DROP TABLE` → 0, all four `CREATE ... IF NOT EXISTS` literal strings present, zero `INSERT INTO.*\$` lines, line count 292 ≥ 120 minimum).
- Manually traced every code path against the plan's numbered behavior spec and the established sibling-script conventions (`Assign-RoleMapping.ps1`, `Initialize-RoleDb.ps1`, `Import-AxoniousExport.ps1`, `Reconcile-LocalRoles.ps1`), including two correctness issues I caught and fixed purely by static review before committing: the `Set-StrictMode` `PropertyNotFoundStrict` hazard on optional JSON properties (see Decisions), and the literal-substring collisions in doc comments (`Add-Type`, `INSERT OR REPLACE`) that would have failed the plan's own grep-based acceptance checks.
- Performed a heuristic brace/paren balance check on both files; the only imbalances found were fully explained by intentional string-literal content (the malformed-JSON test fixture `'{ this is not json'` and the SQL-injection payload `"o'brien'); DROP TABLE RoleUsers;--"`), not real syntax errors.

**This plan's automated `<verify>` commands and the `Invoke-Pester` runs must be executed by the orchestrator, CI, or the user on a host where PowerShell is reachable before this plan is considered fully verified.** The code is written to the letter of the plan and cross-checked against every sibling script's proven patterns, but it has not been run.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The D-05 schema (`RolePublishRun`/`RoleUsers`) and the canonical current-membership query are stable and ready for 07-05 (drift-check job) and 07-06 (dashboard Save button) to build against verbatim:
  ```sql
  SELECT u.UserID FROM RoleUsers u
  WHERE u.RunID = (SELECT MAX(RunID) FROM RolePublishRun WHERE Role = @role)
  ORDER BY u.UserID
  ```
- **Blocker for full sign-off:** the Pester suite has not actually been executed anywhere in this session (see Issues Encountered). Before 07-05/07-06 rely on this contract, run `Invoke-Pester tests/pester/Upsert-RolePublish.Tests.ps1 -Output Detailed -CI` (and the full-estate `-ExcludeTag Slow` run) on a host with `pwsh`/`powershell.exe` and `sqlite3.exe` reachable, and fix anything that surfaces.

---
*Phase: 07-automation*
*Completed: 2026-09-21*

## Self-Check: PASSED

- FOUND: scripts/Upsert-RolePublish.ps1
- FOUND: tests/pester/Upsert-RolePublish.Tests.ps1
- FOUND commit: f86db89
- FOUND commit: 6476860
