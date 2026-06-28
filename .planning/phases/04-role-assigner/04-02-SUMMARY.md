---
phase: 04-role-assigner
plan: "02"
subsystem: unit-tests
tags: [csv-parsing, validation, base64-chunking, xml-generation, portal-config, wave-2]
dependency_graph:
  requires:
    - tests/fixtures/phase-04/ — four CSV fixtures from Wave 1 (04-01)
    - tests/unit/role_assigner.test.js — stub file from Wave 1 (04-01)
  provides:
    - tests/unit/role_assigner.test.js — 31 real correctness assertions (all 9 sections)
  affects:
    - Wave 3 (04-03): implementations from this file copied verbatim into fixlet_role_assigner.ojo
tech_stack:
  added: []
  patterns:
    - Node.js Buffer.from().toString('base64') for safeB64Encode (test-only path; OJO uses btoa)
    - RESEARCH.md Pattern 1 (B64 chunking), Pattern 5 (CSV parsing/validation)
    - xmlEscape/xmlCDataSafe verbatim from dispatcher.test.js canonical pattern
    - D-09 action naming: Dereso_[Role] Assign_[suffix]
    - D-19 PORTAL_CONFIG: roles/actionNamePrefix/targetGroups
key_files:
  created: []
  modified:
    - tests/unit/role_assigner.test.js
decisions:
  - "safeB64Encode uses Buffer.from().toString('base64') for Node.js path — btoa(unescape(encodeURIComponent())) is the browser path used in the OJO (Wave 3)"
  - "buildChunkParams uses CRLF line separator matching RESEARCH.md Pattern 1 specification"
  - "buildAssignActionXml parameter renamed from 'chunkParams' to 'actionScript' per plan interfaces spec"
  - "cdataStart/cdataEnd helpers added to avoid literal CDATA end sequence in source JS"
metrics:
  duration: "3m 14s"
  completed: "2026-06-28"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 1
---

# Phase 4 Plan 02: Pure JS Function Implementations (Wave 2) Summary

Wave 2 replaces all 9 stub function implementations in `tests/unit/role_assigner.test.js` with real, tested correctness assertions. All pure-JS functions are now proven in isolation — Wave 3 copies these implementations verbatim into `fixlet_role_assigner.ojo`.

## What Was Built

### Function Implementations (Task 1)

| Function | Implementation | Key Notes |
|----------|---------------|-----------|
| `parseCsv(text)` | CRLF/LF normalization, case-insensitive headers, empty-line skip | Returns `{error}` on bad header, `{rows}` on success |
| `validateRows(rows, allowedRoles)` | BLOCK: unknown role, blank user, blank Computer_ID; WARN: duplicate key | Per D-15 validation rules |
| `safeB64Encode(str)` | `Buffer.from(str, 'utf8').toString('base64')` | Node.js path; OJO uses `btoa(unescape(encodeURIComponent()))` |
| `chunkString(s, size)` | Simple slice loop; empty string returns `[]` | CHUNK_SIZE = 3000 |
| `buildChunkParams(b64)` | Parameter lines + chunkCount last; CRLF separator | B64 alphabet only in values |

### Function Implementations (Task 2)

| Function | Implementation | Key Notes |
|----------|---------------|-----------|
| `xmlEscape(s)` | Verbatim from dispatcher.test.js — `&`, `<`, `>`, `"`, `'` | Canonical pattern |
| `xmlCDataSafe(s)` | Verbatim from dispatcher.test.js — replaces `]]>` | Canonical pattern |
| `buildAssignActionXml(...)` | Full SingleAction XML with Title/Relevance/ActionScript/Target | D-09 naming, D-02 explicit ComputerID targeting |
| `PORTAL_CONFIG` | Exact D-19 values: 3 roles, actionNamePrefix, 4 targetGroups | IT Operations/Finance/HR |

### Assertion Coverage

| Section | Function | Assertions |
|---------|---------|------------|
| 1 | `parseCsv` | 5 (single row fields, wrong header, sample.csv=4 rows, CRLF=LF, case-insensitive) |
| 2 | `validateRows` | 4 (valid=empty, unknown role blocks, blank fields block, duplicate warns) |
| 3 | `safeB64Encode` | 2 (non-empty B64 string, round-trip decode) |
| 4 | `chunkString` | 3 (exact segments, empty string, shorter-than-size) |
| 5 | `buildChunkParams` | 4 (chunk0 first line, chunkCount=1, chunkCount=3 for 6001-char, B64 alphabet) |
| 6 | `xmlEscape` | 3 (all 5 chars, safe string unchanged, empty string) |
| 7 | `xmlCDataSafe` | 2 (replaces ]]>, unchanged without) |
| 8 | `buildAssignActionXml` | 5 (D-09 title, 2x ComputerID, Relevance element, ActionScript MIMEType, XML-special char escape) |
| 9 | `PORTAL_CONFIG` | 3 (roles deep-equal, actionNamePrefix, targetGroups non-empty + contains All Workstations) |
| **Total** | | **31 assertions** |

## Verification Results

- `node tests/unit/role_assigner.test.js` — **31 passed, 0 failed** (exit 0)
- `node tests/unit/dispatcher.test.js` — **22 passed, 0 failed** (exit 0) — regression gate clean
- D-09 naming convention verified: title contains `Dereso_IT Operations Assign_TestSuffix`
- D-15 validation verified: unknown role blocks, blank user blocks, blank Computer_ID blocks, duplicate warns
- D-19 PORTAL_CONFIG verified: `roles` deep-equals `['IT Operations', 'Finance', 'HR']`, `actionNamePrefix === 'Dereso'`

## Commits

| Hash | Message |
|------|---------|
| 4a30610 | feat(04-02): implement parseCsv, validateRows, safeB64Encode, chunkString, buildChunkParams |
| 490611b | feat(04-02): implement xmlEscape, xmlCDataSafe, buildAssignActionXml, PORTAL_CONFIG |

## Deviations from Plan

None — plan executed exactly as written.

- The plan's task interfaces spec used `actionScript` as the third parameter name for `buildAssignActionXml` — the stub used `chunkParams`. The implementation follows the interfaces spec (Wave 3 passes the full action script string, not pre-built chunk params, to this XML builder).
- `cdataStart()`/`cdataEnd()` helper functions were added (not called out explicitly in the plan) — these are standard practice to avoid a literal CDATA end marker in source JS (required for safe embedding in HTML/JS files within BigFix `.ojo` format).

## Known Stubs

None. All 9 function implementations and their test assertions are real. The header comment in the file ("Wave 1 stubs") is historical documentation only and accurately describes the original Wave 1 state.

The following remain as Wave 3/4 work (not stubs in the Wave 2 context):
- `tests/integration/role_assigner.integration.test.js` — test2_postMinimalSingleAction and test3_parseActionId (Wave 4)

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. This plan modifies a test file with pure-JS in-memory functions only. T-4-02 mitigation verified: `validateRows()` whitelist check confirmed by test asserting unknown role blocks, and `xmlEscape()` applied to title in `buildAssignActionXml()` confirmed by test asserting `&` in role is escaped.

## Self-Check: PASSED

- [x] `tests/unit/role_assigner.test.js` — exists, 31 passed, 0 failed (exit 0)
- [x] `tests/unit/dispatcher.test.js` — regression gate, 22 passed, 0 failed (exit 0)
- [x] Commit 4a30610 — verified in git log
- [x] Commit 490611b — verified in git log
