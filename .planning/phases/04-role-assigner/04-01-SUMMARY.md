---
phase: 04-role-assigner
plan: "01"
subsystem: test-infrastructure
tags: [csv-fixtures, unit-tests, integration-tests, wave-1]
dependency_graph:
  requires: []
  provides:
    - tests/fixtures/phase-04/ — four CSV fixtures for all validation cases
    - tests/unit/role_assigner.test.js — 9-section unit test stub file (exits 0)
    - tests/integration/role_assigner.integration.test.js — env-var gated integration skeleton
  affects:
    - Wave 2 implementations must satisfy the stubs defined here
tech_stack:
  added: []
  patterns:
    - Node.js built-in assert/fs/path (no external packages)
    - dispatcher.test.js infrastructure pattern (expect/section/summary footer)
    - dispatcher.integration.test.js env-guard + apiRequest pattern
key_files:
  created:
    - tests/fixtures/phase-04/sample.csv
    - tests/fixtures/phase-04/invalid-unknown-role.csv
    - tests/fixtures/phase-04/invalid-blank-fields.csv
    - tests/fixtures/phase-04/duplicate-rows.csv
    - tests/unit/role_assigner.test.js
    - tests/integration/role_assigner.integration.test.js
  modified: []
decisions:
  - "Wave 1 stubs return sensible no-op values (not throw) so node exits 0 cleanly"
  - "PORTAL_CONFIG stub has empty targetGroups/roles arrays; Wave 3 populates from .ojo"
  - "safeB64Encode stub returns empty string; Wave 2 uses Buffer.from().toString('base64') for Node"
  - "Integration test tests 2-3 additionally gate on TEST_COMPUTER_ID optional env var"
metrics:
  duration: "2m 23s"
  completed: "2026-06-28"
  tasks_completed: 3
  tasks_total: 3
  files_created: 6
  files_modified: 0
---

# Phase 4 Plan 01: Test Infrastructure (Wave 1) Summary

Wave 1 test infrastructure for the Role Assigner dashboard: four CSV fixture files covering all D-15 validation cases, a unit test stub file for all 9 testable functions, and an env-var-gated integration test skeleton.

## What Was Built

### CSV Fixtures (`tests/fixtures/phase-04/`)

| File | Purpose | Key Content |
|------|---------|-------------|
| `sample.csv` | Valid 3-role CSV | 4 rows: IT Operations (x2), Finance, HR |
| `invalid-unknown-role.csv` | BLOCK: unknown role | Row 2 has `SuperAdmin` (not in PORTAL_CONFIG.roles) |
| `invalid-blank-fields.csv` | BLOCK: blank fields | Row 2 blank user, row 3 blank Computer_ID |
| `duplicate-rows.csv` | WARN: duplicate rows | Rows 2+3 identical (same user/Computer_ID/role) |

All files use `user,Computer_ID,role` header (D-10: `computer` renamed to `Computer_ID`).

### Unit Test Stubs (`tests/unit/role_assigner.test.js`)

9 section blocks, 12 stub assertions — all exit 0. Wave 2 replaces stubs with correctness assertions.

| Section | Function | Stub Asserts |
|---------|---------|--------------|
| 1 | `parseCsv` | Returns object with `rows` property; fixture file exists |
| 2 | `validateRows` | Returns object with `errors` and `warnings` properties |
| 3 | `safeB64Encode / encodeMatrix` | Returns a string |
| 4 | `chunkString` | Returns an array |
| 5 | `buildChunkParams` | Returns a string |
| 6 | `xmlEscape` | Returns a string |
| 7 | `xmlCDataSafe` | Returns a string |
| 8 | `buildAssignActionXml` | Returns a string |
| 9 | `PORTAL_CONFIG` | roles is array, actionNamePrefix is 'Dereso', targetGroups is array |

Infrastructure copied verbatim from `dispatcher.test.js`: `expect(label, fn)`, `section(name)`, summary footer.

### Integration Test Skeleton (`tests/integration/role_assigner.integration.test.js`)

Exits 0 with SKIP message when env vars absent. Five async test stubs wired via Promise chain:

| Test | Status |
|------|--------|
| Test 1: API connectivity (GET /api/sites) | Non-stub — fires real API call |
| Test 2: POST minimal SingleAction | Stub (TODO Wave 4); skips if TEST_COMPUTER_ID absent |
| Test 3: parseActionId on response | Stub (TODO Wave 4); skips if TEST_COMPUTER_ID absent |
| Test 4: Input guard — empty csvRows | Passes synchronously |
| Test 5: API error handling | Non-stub — fires real API call |

`apiRequest` helper copied verbatim from `dispatcher.integration.test.js`.

## Verification Results

- `node tests/unit/role_assigner.test.js` — 12 passed, 0 failed (exit 0)
- `node tests/integration/role_assigner.integration.test.js` — SKIP (exit 0, env vars absent)
- All 4 fixture files present with `user,Computer_ID,role` header

## Commits

| Hash | Message |
|------|---------|
| 6dc8d94 | feat(04-01): create CSV test fixtures for all 4 validation cases |
| 6d67f1e | feat(04-01): add role_assigner.test.js with stubs for 9 function groups |
| 46fc9cc | feat(04-01): add role_assigner.integration.test.js skeleton (env-var gated) |

## Deviations from Plan

None — plan executed exactly as written.

- CSV fixtures use LF line endings (git autocrlf converts to CRLF on checkout per project .gitattributes/core.autocrlf — Windows convention is preserved in the working copy)
- Integration test includes all 5 stubs; tests 2-3 use dual-gate (env vars + TEST_COMPUTER_ID)

## Known Stubs

The following Wave 1 stubs are intentional — Wave 2 replaces function bodies with real implementations and correctness assertions:

| File | Stub | Wave |
|------|------|------|
| `tests/unit/role_assigner.test.js` | All 9 function implementations | Wave 2 |
| `tests/unit/role_assigner.test.js` | PORTAL_CONFIG empty arrays | Wave 3 |
| `tests/integration/role_assigner.integration.test.js` | test2_postMinimalSingleAction body | Wave 4 |
| `tests/integration/role_assigner.integration.test.js` | test3_parseActionId body | Wave 4 |

These stubs are intentional and expected per the Wave 1 design. They do not prevent plan 04-01's goal (test infrastructure baseline) from being achieved.

## Self-Check: PASSED

- [x] `tests/fixtures/phase-04/sample.csv` — exists, header verified
- [x] `tests/fixtures/phase-04/invalid-unknown-role.csv` — exists, SuperAdmin content verified
- [x] `tests/fixtures/phase-04/invalid-blank-fields.csv` — exists, blank fields verified
- [x] `tests/fixtures/phase-04/duplicate-rows.csv` — exists, duplicate rows verified
- [x] `tests/unit/role_assigner.test.js` — exists, exits 0 (12 passed)
- [x] `tests/integration/role_assigner.integration.test.js` — exists, exits 0 (SKIP mode)
- [x] Commit 6dc8d94 — verified in git log
- [x] Commit 6d67f1e — verified in git log
- [x] Commit 46fc9cc — verified in git log
