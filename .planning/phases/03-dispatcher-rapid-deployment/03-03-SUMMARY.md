---
phase: 03-dispatcher-rapid-deployment
plan: "03"
subsystem: tests-and-docs
tags: [dispatcher, integration-test, bigfix, post, sourcefixletaction, admin-guide, regression-gate]
dependency_graph:
  requires:
    - tests/unit/dispatcher.test.js (plan 03-01)
    - Existing Dashboards/fixlet_dispatcher.ojo (plan 03-02)
    - tests/integration/modifier.integration.test.js (pattern source)
  provides:
    - tests/integration/dispatcher.integration.test.js
    - docs/dispatcher-admin-guide.md
  affects:
    - regression gate (all three unit suites confirmed green)
tech_stack:
  added: []
  patterns:
    - 6-section integration test structure (mirroring modifier.integration.test.js exactly)
    - apiRequest() extended for POST body-write (PUT || POST condition)
    - SourcedFixletAction XML built inline in test3 (no file read)
    - buildTargetRelevance() ported to integration test Section 3 for Test 5 assertion
    - Regression gate pattern (all three unit suites in sequence)
key_files:
  created:
    - tests/integration/dispatcher.integration.test.js
    - docs/dispatcher-admin-guide.md
  modified: []
decisions:
  - "Integration test builds SourcedFixletAction XML inline in test3 rather than reading from a fixture file — keeps the test self-contained and avoids dependency on the fixture for the live POST round-trip"
  - "Admin guide uses POST /api/actions terminology throughout (not /fixlet-deployments) per D-13 from 03-CONTEXT.md"
  - "Regression gate order: dispatcher -> modifier -> copier (most-recently-added first)"
metrics:
  duration: "8 minutes"
  completed: "2026-06-15"
  tasks_completed: 2
  files_created: 2
  files_modified: 0
---

# Phase 03 Plan 03: Integration Tests + Admin Guide Summary

**One-liner:** Dispatcher integration test with 6-section POST round-trip structure (NFR-01 timing, skip-mode env guard), dispatcher admin guide (7 sections, PORTAL_CONFIG docs), and full regression gate confirming 98 unit tests green across all three phases.

## What Was Built

### Task 1: Dispatcher Integration Test

`tests/integration/dispatcher.integration.test.js` — 421 lines, 6 clearly-labelled sections mirroring `modifier.integration.test.js` exactly.

**Section 1 — Environment guard:** Verbatim copy. Exits 0 with "SKIP: ..." message if any of BIGFIX_URL, BIGFIX_USER, BIGFIX_TOKEN are absent.

**Section 2 — apiRequest() helper:** Copied from modifier, with the key change: body-write conditions updated from `method === "PUT"` to `(method === "PUT" || method === "POST")` in both the header-setting block and the `req.write()` block. This enables the POST /api/actions round-trip.

**Section 3 — Utility functions:** `buildTargetRelevance(groupName)` ported verbatim from `fixlet_dispatcher.ojo`. No ActiveXObject-dependent functions included (Node.js compatible only).

**Section 4 — Test runner:** Verbatim copy — `passed`, `failed`, `skipped`, `failures[]`, `assert()`, `assertEqual()`, `runTest()`, `runAsyncTest()`, `skipTest()`.

**Section 5 — Test scenarios (6 tests):**

- **Test 1** `test1_apiConnectivity`: GET /api/sites → assert 200. Verbatim from modifier.
- **Test 2** `test2_loadSourceFixlet`: GET fixlet/custom/site/id → assert 200 + `<BES`. Skips if TEST_SOURCE_SITE_NAME or TEST_SOURCE_FIXLET_ID absent. Verbatim from modifier.
- **Test 3** `test3_postActionHappyPath`: Builds SourcedFixletAction XML inline (no file read). Uses TEST_SOURCE_SITE_NAME (default "Dereso Software Portal"), TEST_SOURCE_FIXLET_ID (required; skips if absent), TEST_TARGET_GROUP (default "All Workstations"). XML includes `<IsOffer>true</IsOffer>`, `<EndDateTimeLocalOffset>P7D</EndDateTimeLocalOffset>`, `<Relevance>` group targeting (no `<Target>` element per RESEARCH.md A1). Timing assertion: `elapsed < 5000` (NFR-01).
- **Test 4** `test4_guardNoFixletSelected`: Synchronous. Inline guard: `sourceXml === "" ? "" : "WOULD_BUILD"` asserts `""`. No network.
- **Test 5** `test5_guardEmptyTargetGroup`: Synchronous. Calls `buildTargetRelevance("")` and asserts `strictEqual` result `=== "true"`.
- **Test 6** `test6_apiErrorHandling`: GET non-existent fixlet → assert non-200. Verbatim from modifier.

**Section 6 — Run chain:** Sync tests 4, 5 first (`runTest()`). Async chain: test1 → test2 → test3 → test6. Print summary and `process.exit(failed > 0 ? 1 : 0)`. `.catch()` handles unexpected errors.

### Task 2: Admin Guide + Regression Gate

`docs/dispatcher-admin-guide.md` — 175 lines, 7 sections following the same structure and tone as `docs/admin-guide.md` (Phase 1 copier guide).

**Sections:**
1. **Overview** — Dashboard purpose; Phase 3 of the Software Portal suite (Copier → Modifier → Dispatcher); creates `SourcedFixletAction` offer-type deployments via `POST /api/actions`.
2. **Prerequisites** — BigFix admin credentials, "Dereso Software Portal" site required, fixlets should have categories, target computer groups must exist before using the dispatcher.
3. **Configuring the Dashboard** — PORTAL_CONFIG block with code example; table documenting `defaultExpirationDays` (integer, ISO 8601 P{N}D duration, overrideable per deploy) and `targetGroups` (array of strings, case-sensitive group names, "Other" free-text fallback available).
4. **Using the Dispatcher** — 7-step workflow: open, find fixlet, select fixlet, choose action, set target group, review live preview, deploy.
5. **Deployment Parameters** — Table mapping offer fields to their sources (title from fixlet name, description as-is, category auto-derived, type always "offer", action admin-selected, target group admin-selected, expiry from PORTAL_CONFIG).
6. **Troubleshooting** — 7-row table covering: no fixlets shown, deploy 404, 0 relevant computers (group name mismatch — case-sensitive), offer not in self-service app, three input-guard errors.
7. **Related Dashboards** — One sentence each for Copier, Modifier, Dispatcher.

**Regression gate results:**
```
node tests/unit/dispatcher.test.js   → 23 passed, 0 failed
node tests/unit/modifier.test.js     → 30 passed, 0 failed
node tests/unit/copier.test.js       → 45 passed, 0 failed
Total: 98 tests, 0 failures — REGRESSION GATE: ALL PASSED
```

## Verification Result

All success criteria met:

- `node tests/integration/dispatcher.integration.test.js` exits 0 in skip mode ✓
- apiRequest() handles both POST and PUT body-write conditions ✓
- test3_postActionHappyPath constructs inline XML with `IsOffer>true`, `P7D`, group relevance ✓
- Timing assertion is `elapsed < 5000ms` (NFR-01) ✓
- test5_guardEmptyTargetGroup asserts `buildTargetRelevance("") === "true"` ✓
- docs/dispatcher-admin-guide.md exists with PORTAL_CONFIG docs and troubleshooting ✓
- Regression gate: 23 + 30 + 45 = 98 unit tests, all pass ✓
- No new npm/pip packages introduced ✓

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1 | 8cc8dd6 | tests/integration/dispatcher.integration.test.js |
| Task 2 | 0be4d2f | docs/dispatcher-admin-guide.md |

## Deviations from Plan

None. Plan executed exactly as written.

- Integration test built inline XML in test3 as specified (not from file) ✓
- Admin guide uses "POST /api/actions" terminology, not "/fixlet-deployments" ✓
- All acceptance criteria for both tasks satisfied without modification

## Known Stubs

None. Integration test connects to a real BigFix instance when env vars are set, or skips gracefully. Admin guide references real dashboard functions and real API endpoints. No hardcoded placeholder data flows to any output.

## Threat Surface Scan

No new threat surface introduced beyond what the plan's `<threat_model>` covers.

| Threat ID | Status | Implementation |
|-----------|--------|----------------|
| T-03-03-01 | Mitigated | BIGFIX_TOKEN never echoed to stdout; used only in Basic auth header string |
| T-03-03-02 | Mitigated | File header warns "staging only — do not run against production"; test3 skips if TEST_SOURCE_FIXLET_ID absent |
| T-03-03-03 | Accepted | TEST_TARGET_GROUP defaults to "All Workstations"; test runs only when admin explicitly sets all three required env vars |
| T-03-03-SC | Accepted | Zero new dependencies; no package install commands |

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| tests/integration/dispatcher.integration.test.js exists | FOUND |
| File size 421 lines (>250 lines per must_haves) | PASSED |
| exits 0 in skip mode (no env vars) | PASSED |
| "SKIP:" message present | PASSED |
| apiRequest() handles PUT \|\| POST body-write | PASSED |
| test3_postActionHappyPath has "IsOffer>true" | PASSED |
| test3_postActionHappyPath has "P7D" | PASSED |
| elapsed < 5000 timing assertion | PASSED |
| buildTargetRelevance("") === "true" in test5 | PASSED |
| FR-04 deferred note references Phase 4 | PASSED |
| 6 clearly labelled sections | PASSED |
| docs/dispatcher-admin-guide.md exists | FOUND |
| Admin guide >= 7 sections | PASSED (7 sections) |
| PORTAL_CONFIG section documents both keys | PASSED |
| Troubleshooting has "0 relevant computers" symptom | PASSED |
| Admin guide uses "POST /api/actions" terminology | PASSED |
| Regression gate: dispatcher 23/0 | PASSED |
| Regression gate: modifier 30/0 | PASSED |
| Regression gate: copier 45/0 | PASSED |
| Commit 8cc8dd6 exists | FOUND |
| Commit 0be4d2f exists | FOUND |
