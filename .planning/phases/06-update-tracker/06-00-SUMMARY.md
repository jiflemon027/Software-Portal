---
phase: 06-update-tracker
plan: "00"
subsystem: update-tracker-infrastructure
tags: [wave-0, fixtures, test-stubs, category-map, csv-generator]
dependency_graph:
  requires: []
  provides:
    - scripts/generate_category_map.js (CATEGORY_MAP build-time generator)
    - tests/fixtures/phase-06/ (4 XML fixtures for buildCopyXml and buildSupersededXml)
    - tests/unit/update_tracker.test.js (test scaffold for Wave 1)
    - tests/integration/update_tracker.integration.test.js (integration skeleton for Wave 3)
  affects:
    - Wave 1 (06-01) — unit test stub provides section scaffold to fill
    - Wave 2 (06-02) — fixture contracts define expected buildCopyXml output
    - Wave 3 (06-03) — integration skeleton provides runner infrastructure
tech_stack:
  added:
    - scripts/generate_category_map.js (Node.js build tool, no external deps)
  patterns:
    - CSV → JS object build-time compilation (no runtime file I/O in dashboard)
    - BES XML fixture structure matching modifier/copier conventions
    - test stub exit-0 pattern (section headings + summary footer, no assertions yet)
key_files:
  created:
    - scripts/generate_category_map.js
    - tests/fixtures/phase-06/portal-fixlet-with-roles.xml
    - tests/fixtures/phase-06/source-fixlet-new-version.xml
    - tests/fixtures/phase-06/expected-copy-output.xml
    - tests/fixtures/phase-06/expected-superseded-output.xml
    - tests/unit/update_tracker.test.js
    - tests/integration/update_tracker.integration.test.js
  modified: []
decisions:
  - "MIMEField blocks placed BEFORE Domain in all fixtures (matching insertBefore(domainNode) pattern from modifier.ojo)"
  - "Use / v\\d[\\d.]+/g (one-or-more) not / v\\d[\\d.]*/g (zero-or-more) to preserve product-family labels like AWS CLI v2"
  - "Col[4] (Shortlist Category) used for CATEGORY_MAP, not col[3] (Specific Category) per D-18"
metrics:
  duration: "~20 minutes"
  completed: "2026-07-08"
  tasks_completed: 3
  tasks_total: 3
  files_created: 7
---

# Phase 6 Plan 00: Wave 0 Infrastructure Summary

## One-Liner

CSV-to-JS category map generator + 4 BES XML fixtures defining buildCopyXml/buildSupersededXml contracts + unit/integration test stubs with section scaffolding.

## What Was Built

### Task 1: scripts/generate_category_map.js (commit 7d9cb98)

Build-time Node.js script that reads `Dashboard_4_samples/software_categorized.csv` (798 data rows) and prints `var CATEGORY_MAP = {...};` to stdout for embedding in the dashboard.

Key implementation choices:
- Regex `/ v\d[\d.]+/g` (one-or-more) preserves `AWS Command Line Interface v2` family label
- Col[4] (Shortlist Category) used as map value, not col[3] (Specific Category)
- Only built-in `fs` and `path` modules — no npm dependencies
- `\r` stripping handles Windows line endings before splitting on `\n`

Verified: `var CATEGORY_MAP = {` on first line; `};` on last non-empty line; no `v26.01` in any key; `AWS Command Line Interface v2 - Windows (x64)` key preserved.

### Task 2: 4 XML Test Fixtures (commit 11d933d)

All in `tests/fixtures/phase-06/`:

| File | Purpose | Key Properties |
|------|---------|----------------|
| `portal-fixlet-with-roles.xml` | Input: old portal fixlet | Title v26.01, Category=File Management & Archiving, Associated_Roles=IT Support|General Access **before Domain** |
| `source-fixlet-new-version.xml` | Input: newer source fixlet | Title v26.02, Category=Utilities (different from portal), no Associated_Roles |
| `expected-copy-output.xml` | Contract for buildCopyXml | Title v26.02 (source), Category=File Management & Archiving (portal wins D-16), Associated_Roles before Domain (D-17) |
| `expected-superseded-output.xml` | Contract for buildSupersededXml | Title v26.01 (unchanged), X-Superseded-By=99999 **before Domain** (D-08) |

Design note: source-fixlet-new-version.xml intentionally uses `Category=Utilities` so integration tests can assert the portal category wins over the source category (D-16).

### Task 3: Test File Stubs (commit 0bc69d9)

**tests/unit/update_tracker.test.js:**
- Section headings for all 6 functions: stripVersion, extractVersion, compareVersions, lookupCategory, buildScanResults, PORTAL_CONFIG
- Exits 0 with `Results: 0 passed, 0 failed`
- Wave 1 fills in function implementations and assertions

**tests/integration/update_tracker.integration.test.js:**
- SKIP guard fires when BIGFIX_URL/USER/TOKEN not set (exits 0 immediately)
- apiRequest helper supports GET, POST, and PUT (extended from modifier pattern)
- Optional env vars declared (TEST_SOURCE_SITE_TYPE, TEST_SOURCE_SITE_NAME, etc.)
- Full test runner infrastructure copied from modifier.integration.test.js
- Empty testPromises array — summary fires immediately with 0/0/0
- Wave 3 fills in Section 5 test scenarios

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 7d9cb98 | feat(06-00): create scripts/generate_category_map.js |
| 2 | 11d933d | feat(06-00): create 4 XML test fixtures for buildCopyXml and buildSupersededXml |
| 3 | 0bc69d9 | feat(06-00): create unit and integration test stubs for update_tracker |

## Verification Results

| Check | Command | Result |
|-------|---------|--------|
| Category map generator | `node scripts/generate_category_map.js | head -3` | `var CATEGORY_MAP = {` — PASS |
| All 4 fixtures exist | `ls tests/fixtures/phase-06/` | 4 files listed — PASS |
| Unit test stub | `node tests/unit/update_tracker.test.js` | `Results: 0 passed, 0 failed` — PASS |
| Integration test stub | `node tests/integration/update_tracker.integration.test.js` | SKIP guard fires — PASS |

## Wave 0 Requirements Closed

All 7 VALIDATION.md Wave 0 Requirements are met:
- [x] `tests/unit/update_tracker.test.js` — section stubs for FR-10 pure functions
- [x] `tests/integration/update_tracker.integration.test.js` — SKIP mode + runner infrastructure
- [x] `tests/fixtures/phase-06/portal-fixlet-with-roles.xml`
- [x] `tests/fixtures/phase-06/source-fixlet-new-version.xml`
- [x] `tests/fixtures/phase-06/expected-copy-output.xml`
- [x] `tests/fixtures/phase-06/expected-superseded-output.xml`
- [x] `scripts/generate_category_map.js`

## Deviations from Plan

None — plan executed exactly as written.

The only structural decision made was placing MIMEField blocks BEFORE Domain in all fixtures (consistent with the plan's explicit instruction and with the `insertBefore(domainNode)` pattern from modifier.ojo). PATTERNS.md showed the analog fixture with Domain before MIMEField; the PLAN.md's explicit "MIMEField before Domain" instruction took precedence.

## Known Stubs

The unit and integration test files are intentional stubs with no assertions:
- `tests/unit/update_tracker.test.js` — Wave 1 (06-01) fills in function implementations and assertions
- `tests/integration/update_tracker.integration.test.js` — Wave 3 (06-03) fills in Section 5 test scenarios

These are not incomplete stubs that prevent the plan goal — the goal of Wave 0 is specifically to create the infrastructure scaffold for subsequent waves.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. The script reads a local developer-controlled CSV file and outputs to stdout. The test files have no runtime side effects. No new threat surface beyond what the threat model documented.

## Self-Check: PASSED

All 7 created files found on disk. All 3 task commits verified in git log.
