---
phase: 06-update-tracker
verified: 2026-07-09T00:00:00Z
status: gaps_found
score: 9/13 must-haves verified
overrides_applied: 0
re_verification: false
gaps:
  - truth: "Two-step copy flow has functional Cancel path that restores tab visibility (D-11)"
    status: failed
    reason: "showPreviewPanel hides both tab panels (tabUpdates, tabArrivals); Cancel button uses a bare inline onclick that only hides previewPanel, leaving both tab content areas invisible. No onCancelCopy function exists. After Cancel, the admin cannot access the scan results without re-scanning from scratch."
    artifacts:
      - path: "Existing Dashboards/fixlet_update_tracker.ojo"
        issue: "Line 1752: onclick hides previewPanel only; lines 1610-1611 show that showPreviewPanel hides both tab panels. No restoring function defined. Confirmed by code review CR-04."
    missing:
      - "Add onCancelCopy() function that hides previewPanel and calls switchTab('updates') to restore both tab panels"
      - "Replace inline Cancel onclick with onclick=\"onCancelCopy()\""

  - truth: "Category pre-filled from portal fixlet element; CSV fallback selects matching option in dropdown (D-16)"
    status: failed
    reason: "PORTAL_CONFIG.categories (13 entries: 'Coding Tools', 'Database Tools', 'Web Browsers', etc.) and CATEGORY_MAP values (18 unique values: 'Developer Tools', 'Database & Data Tools', 'Web Browser', 'Cloud & File Sync', etc.) use different taxonomies. Only 8 of 18 CATEGORY_MAP values appear in PORTAL_CONFIG.categories. For the majority of CATEGORY_MAP products (Developer Tools, Database & Data Tools, Web Browser, Cloud & File Sync, Communication & Conferencing, Containers & DevOps, Network Tools, Video & Screen Recording, Productivity & Organization), the preview panel category dropdown defaults to 'Coding Tools' (the first option) rather than the correct CATEGORY_MAP-derived category. A comment in the code (line 69) explicitly states 'Categories must match CATEGORY_MAP values for consistent display' but the values do not match. Confirmed by code review CR-03."
    artifacts:
      - path: "Existing Dashboards/fixlet_update_tracker.ojo"
        issue: "PORTAL_CONFIG.categories (lines 55-71) has 13 items; CATEGORY_MAP embeds 18 unique category values. 10 CATEGORY_MAP values have no match in PORTAL_CONFIG.categories."
    missing:
      - "Align PORTAL_CONFIG.categories to include all 18 CATEGORY_MAP values (e.g., replace 'Coding Tools' with 'Developer Tools', 'Database Tools' with 'Database & Data Tools', 'Web Browsers' with 'Web Browser', add 'Cloud & File Sync', 'Communication & Conferencing', 'Containers & DevOps', 'Network Tools', 'Video & Screen Recording', 'Productivity & Organization')"
      - "Remove 'Drivers' from PORTAL_CONFIG.categories if it does not appear in CATEGORY_MAP"

  - truth: "New Arrivals tab suggested categories match portal taxonomy (D-09)"
    status: failed
    reason: "Same root cause as CR-03: arrival.suggestedCategory comes from CATEGORY_MAP values (e.g., 'Developer Tools', 'Database & Data Tools', 'Web Browser'). These values are written directly to <Category> in the portal copy via buildCopyXml. They do not match the portal's configured category taxonomy in PORTAL_CONFIG.categories ('Coding Tools', 'Database Tools', 'Web Browsers'). Net-new products would be imported with category values that are inconsistent with the portal's taxonomy. Confirmed by code review CR-03."
    artifacts:
      - path: "Existing Dashboards/fixlet_update_tracker.ojo"
        issue: "onCopyArrival (line 1552) sets arrival.copyCategory = arrival.suggestedCategory directly from CATEGORY_MAP without mapping to PORTAL_CONFIG.categories values."
    missing:
      - "Fix is the same as the CR-03 taxonomy alignment fix above — once PORTAL_CONFIG.categories matches CATEGORY_MAP, this path becomes consistent"

  - truth: "Batch copy-with-supersede works for all portal item types including Task-type items (D-08)"
    status: failed
    reason: "loadPortalFixlets query includes Task-type items via 'fixlet flag of it or task flag of it' but the 4-field result stores only {id, name, category, roles} with no itemType field. copyNextItem hardcodes 'fixlet/custom/' for both the GET portal path (step 1, line 1469) and the PUT supersede path (step 4, line 1505). Portal Task-type items will fail step 1 with HTTP 404, and the error message 'GET portal fixlet failed: status=404' will mislead the admin. The identical defect was fixed in fixlet_dispatcher.ojo (commit b97fd8e 'fix(dispatcher): support Task type') but was not applied here. Confirmed by code review CR-01."
    artifacts:
      - path: "Existing Dashboards/fixlet_update_tracker.ojo"
        issue: "loadPortalFixlets (lines 1100-1118) has no 5th field for item type. copyNextItem (lines 1469, 1505) hardcodes 'fixlet/custom/' for GET and PUT paths."
    missing:
      - "Add 5th pipe segment to loadPortalFixlets relevance: '& \"|||\" & (if task flag of it then \"task\" else \"fixlet\")'"
      - "Parse itemType: p[4] || 'fixlet' in the result push"
      - "In copyNextItem: var pathType = item.portalItemType || 'fixlet'; use pathType in GET and PUT paths"
human_verification:
  - test: "Import fixlet_update_tracker.ojo into BigFix Console"
    expected: "Dashboard appears under Dashboards menu; loads without JavaScript errors in Internet Explorer 9 compatibility mode"
    why_human: "OJO XML import and BigFix Console rendering cannot be verified without a live BigFix Console environment"
  - test: "Run 'Scan for Updates' button after import"
    expected: "Status bar shows 'Scanning site 1 of 1: BigFix Software Installer Library for Windows...' during scan; tab badges update after scan completes; updates table and arrivals table populate with rows"
    why_human: "EvaluateRelevance calls only execute inside the BigFix Console runtime; cannot be tested by grep or Node.js"
  - test: "Select update rows with checkboxes and click 'Copy Selected'"
    expected: "Preview panel appears showing From/To/Category dropdown/Roles field per selected item; tab panels are hidden while preview is open"
    why_human: "DOM manipulation (tab hiding, preview panel rendering) requires the IE9 BigFix Console runtime"
  - test: "Click Cancel in the preview panel (AFTER the CR-04 gap is fixed)"
    expected: "Preview panel hides; Updates tab content returns to visible; admin can re-select items without re-scanning"
    why_human: "Requires live BigFix Console to verify DOM state restoration"
  - test: "Confirm a copy and verify results with a real source fixlet"
    expected: "Results panel shows OK for each item; new fixlet appears in Dereso Software Portal site; old portal fixlet has X-Superseded-By MIME field set to the new fixlet ID"
    why_human: "4-step API callback (GET portal, GET source, POST copy, PUT supersede) requires live BigFix REST API; validates CR-02 edge case under real conditions"
---

# Phase 6: Fixlet Update Tracker Verification Report

**Phase Goal:** Deliver Fixlet Update Tracker dashboard (FR-10) — a BigFix admin dashboard that scans source sites for newer fixlet versions and allows batch copy-with-supersede to the portal site, with a New Arrivals tab for net-new products.
**Verified:** 2026-07-09
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

The phase produced all structural deliverables: a complete 1771-line OJO dashboard, 786-entry embedded CATEGORY_MAP, working test suites, and fixture files. All test commands pass. However, the code review (06-REVIEW.md, status: issues_found, 4 critical findings) identified bugs that are observable in the codebase and confirmed below. Three of four critical review findings directly break FR-10 acceptance criteria and are classified as gaps.

### Observable Truths

Truths derived from FR-10 acceptance criteria. ROADMAP success criteria are verified separately in "Behavioral Spot-Checks".

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Admin triggers scan via "Scan for Updates" button; no auto-scan on load (D-01) | VERIFIED | `startScan()` bound to `onclick="startScan()"` on button; no DOMContentLoaded or onload call |
| 2 | Live status shows per-site scan progress (D-02) | VERIFIED | `setStatus()` called inside `scanNextSite()`; `setTimeout(scanNextSite, 0)` yields between sites |
| 3 | Comparison table renders with checkbox, portal name, source name, site, category, roles columns (D-14) | VERIFIED | `renderUpdatesTable()` and `renderUpdateRow()` produce correct 6-column layout with htmlEscape on all values |
| 4 | Version matching uses `/ v\d[\d.]+/g` strip regex (D-04) | VERIFIED | `function stripVersion(name)` at line 982 uses exact regex; confirmed in unit test with 31 passing assertions |
| 5 | All newer versions shown; all source site matches without deduplication (D-06, D-07) | VERIFIED | `buildScanResults()` pushes every compareVersions > 0 match into updates[]; no dedup step |
| 6 | Two-step copy flow completes — checkboxes, Copy Selected, preview panel, Confirm; Cancel restores UI (D-11) | FAILED | Forward path (Confirm) works. Cancel button (line 1752) only hides previewPanel but does NOT restore tabUpdates/tabArrivals visibility. `showPreviewPanel` hides both at lines 1610-1611. `onCancelCopy` function does not exist. See gap 1. |
| 7 | Category pre-filled from portal fixlet element; CSV fallback selects matching dropdown option (D-16) | FAILED | `lookupCategory()` returns CATEGORY_MAP values (e.g., "Developer Tools") that do not match any PORTAL_CONFIG.categories entry (which has "Coding Tools"). For 10/18 CATEGORY_MAP category values, the dropdown defaults to "Coding Tools" (first option). Line 69 comment acknowledges the requirement but the values are mismatched. See gap 2. |
| 8 | Roles pre-filled from Associated_Roles MIME field; blank if absent (D-17) | VERIFIED | `loadPortalFixlets()` captures roles as 4th pipe segment; `showPreviewPanel()` pre-fills `previewRoles_N` input from `item.portalRoles` |
| 9 | Batch copy handles partial failures per item (D-12) | VERIFIED | `copyNextItem()` always calls `copyNextItem(items, index+1, results, onAllDone)` in both success and error branches; results.push records ok/error |
| 10 | Old portal fixlet stamped with X-Superseded-By after successful copy, for all item types (D-08) | FAILED | `buildSupersededXml()` and PUT logic are correctly coded, but `loadPortalFixlets()` includes Tasks in query without storing type; `copyNextItem` hardcodes `fixlet/custom/` for GET and PUT. Task-type portal items fail at step 1 with 404. Also: `parseCreatedId(b3)` result not guarded against empty string before step 4 (CR-02). See gap 4. |
| 11 | New Arrivals tab shows suggested categories from CSV lookup that match portal taxonomy (D-09) | FAILED | `suggestedCategory` from CATEGORY_MAP uses different taxonomy (e.g., "Developer Tools") than PORTAL_CONFIG.categories ("Coding Tools"). Category values written to portal copies via `buildCopyXml(b1, arrival.copyCategory, "")` are inconsistent with the portal's category scheme. See gap 3. |
| 12 | Source site list configured in PORTAL_CONFIG.sourceSites array (D-05) | VERIFIED | `PORTAL_CONFIG.sourceSites: ["BigFix Software Installer Library for Windows"]` at lines 41-45 |
| 13 | CSV shortlist categories embedded as CATEGORY_MAP constant at build time (D-18) | VERIFIED | 786-entry `var CATEGORY_MAP = {...}` block embedded at lines 77-864; generated by `scripts/generate_category_map.js` from `software_categorized.csv` |

**Score: 9/13 truths verified**

### Deferred Items

None. All gaps are in the current phase's scope and affect currently verifiable FR-10 acceptance criteria.

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Existing Dashboards/fixlet_update_tracker.ojo` | Complete BigFix dashboard (OJO XML) | VERIFIED | 1771 lines; valid BES/Wizard/Page/Head/HTML structure confirmed |
| `scripts/generate_category_map.js` | CSV-to-JS build script | VERIFIED | Reads `software_categorized.csv`, strips version with `/ v\d[\d.]+/g`, outputs valid `var CATEGORY_MAP = {...};` |
| `scripts/category_map_output.js` | Generated CATEGORY_MAP output | VERIFIED | 786 unique version-stripped keys; `var CATEGORY_MAP =` present |
| `tests/fixtures/phase-06/portal-fixlet-with-roles.xml` | Input portal fixlet fixture | VERIFIED | Contains v26.01, Associated_Roles, File Management & Archiving; MIMEField before Domain |
| `tests/fixtures/phase-06/source-fixlet-new-version.xml` | Input source fixlet fixture | VERIFIED | Contains v26.02, Category=Utilities, no Associated_Roles |
| `tests/fixtures/phase-06/expected-copy-output.xml` | buildCopyXml contract fixture | VERIFIED | v26.02 title, File Management category, IT Support roles, MIMEField before Domain |
| `tests/fixtures/phase-06/expected-superseded-output.xml` | buildSupersededXml contract fixture | VERIFIED | v26.01 title, X-Superseded-By=99999 before Domain |
| `tests/unit/update_tracker.test.js` | Unit test suite with 20+ assertions | VERIFIED | 31 assertions; 7 sections; exits 0 (confirmed by actual run) |
| `tests/integration/update_tracker.integration.test.js` | Integration test with fixture assertions + BIGFIX-gated tests | VERIFIED | 6 GROUP A always-run, 2 GROUP B skipped; exits 0 (confirmed by actual run) |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `scanNextSite()` | IE9 repaint (D-02) | `setTimeout(scanNextSite, 0)` | VERIFIED | Line 1168 confirms `setTimeout(scanNextSite, 0)` between site iterations |
| `copyNextItem()` | BigFix REST API (4 steps) | GET portal, GET source, POST copy, PUT supersede | VERIFIED (Fixlet type only) | 4-level nesting confirmed (lines 1472-1520); always recurses. Breaks for Task-type items (CR-01) |
| `buildCopyXml()` | `buildSupersededXml()` | `parseCreatedId(b3)` → new ID passed to supersede | VERIFIED (structure) | parseCreatedId call at line 1501; no null-guard before line 1504 (CR-02 edge case) |
| `PORTAL_CONFIG.sourceSites` | `scanNextSite()` iteration | `PORTAL_CONFIG.sourceSites[scanSiteIndex]` | VERIFIED | Lines 1141-1145 iterate over array |
| `loadPortalFixlets()` | EvaluateRelevance | 4-field `|||` tuple relevance query | VERIFIED (4 fields only) | Query present at lines 1101-1109; no 5th field for item type (CR-01 root cause) |
| `showPreviewPanel()` | Tab visibility | hides tabUpdates and tabArrivals | VERIFIED (show path) | Lines 1610-1611 hide tabs; Cancel button does NOT restore them (CR-04) |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `renderUpdatesTable()` | `updateRows[]` | `processScanResults()` → `buildScanResults(portalItems, scanSourceResults)` | Conditional — depends on EvaluateRelevance runtime | WIRED (cannot verify without BigFix runtime) |
| `showPreviewPanel()` | `selectedRows[i].portalCategory` | `loadPortalFixlets()` 3rd pipe segment | Yes (from portal fixlet Category element) | WIRED for primary path; fallback to CATEGORY_MAP produces mismatched taxonomy |
| `renderResultsPanel()` | `results[]` | `copyNextItem()` callback chain | Conditional — depends on API.Get/Post/Put | WIRED |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Unit test suite exits 0 with 31 assertions | `node tests/unit/update_tracker.test.js` | `Results: 31 passed, 0 failed` | PASS |
| Integration test exits 0 with 6 GROUP A passing, 2 GROUP B skipped | `node tests/integration/update_tracker.integration.test.js` | `Results: 6 passed, 0 failed, 2 skipped` | PASS |
| generate_category_map.js produces valid JS | `node scripts/generate_category_map.js \| head -1` | `var CATEGORY_MAP = {` | PASS |
| generate_category_map.js last line is `};` | `node scripts/generate_category_map.js \| tail -1` | `};` | PASS |
| Regression gate — all 5 unit suites | `node tests/unit/copier.test.js && node tests/unit/modifier.test.js && ...` | `ALL UNIT SUITES PASSED` (45+30+22+33+31 = 161 total) | PASS |
| IE9 compliance (no let/const/=>/backtick) | node -e check on OJO file | All 4 checks: false | PASS |
| OJO XML structure complete | node -e structure check | All 11 structural elements: FOUND | PASS |
| CATEGORY_MAP taxonomy mismatch (CR-03) | Compare PORTAL_CONFIG.categories vs CATEGORY_MAP unique values | 10/18 CATEGORY_MAP values absent from PORTAL_CONFIG.categories | FAIL |
| Cancel button restores tab visibility (CR-04) | Code search for onCancelCopy function | `onCancelCopy`: NOT FOUND; bare inline onclick confirmed at OJO char 83274 | FAIL |
| Task-type path in copyNextItem (CR-01) | Code search for item type capture in loadPortalFixlets | No 5th field in push; hardcoded `fixlet/custom/` at lines 1469 and 1505 | FAIL |

---

## Probe Execution

No probe scripts defined for this phase. Step 7c: SKIPPED (no `scripts/*/tests/probe-*.sh` files exist).

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| FR-10 | 06-00, 06-01, 06-02, 06-03 | Fixlet Version Update Tracking | PARTIAL | 9/13 acceptance criteria met; D-11 Cancel, D-16 fallback, D-08 Tasks, D-09 taxonomy all broken |
| NFR-01 | 06-03 | Performance: fixlet copy < 30s | UNCERTAIN | Timing assertion present in integration test (`Date.now`, `30000`, BIGFIX-gated). Cannot verify without live BigFix. |
| NFR-02 | 06-02, 06-03 | Reliability: atomic ops, error recovery | PARTIAL | D-12 partial failure model implemented (always recurse). CR-02: empty parseCreatedId result not guarded before buildSupersededXml; blank X-Superseded-By written on POST success with unrecognized response format. |
| NFR-03 | 06-02 | Security: admin auth, XSS mitigation | VERIFIED | BigFix Console handles auth before dashboard loads. `htmlEscape()` applied to all dynamic DOM insertions in renderUpdateRow, renderArrivalsTable, renderResultsPanel, showPreviewPanel. `xmlEscape()` available; MSXML DOM .text assignment auto-escapes for BES XML. |
| NFR-04 | 06-02 | Usability: BigFix UI conventions, < 5 min | PARTIAL | CSS matches BigFix panel conventions. CR-04: Cancel button breaks two-step flow; after Cancel, both tab panels are invisible and recovery requires a full re-scan, breaking the < 5 min target. |
| NFR-05 | 06-00, 06-01 | Maintainability: modular, testable, configurable | VERIFIED | 31-assertion unit test suite, integration fixtures, PORTAL_CONFIG externalizes roles/categories/sites, generate_category_map.js is a documented build script. |

---

## Anti-Patterns Found

| File | Location | Pattern | Severity | Impact |
|------|----------|---------|----------|--------|
| `Existing Dashboards/fixlet_update_tracker.ojo` | Line 1752 (HTML block) | Cancel button does not restore tab visibility hidden by showPreviewPanel | BLOCKER | After Cancel, admin cannot see scan results without re-running a full scan (CR-04) |
| `Existing Dashboards/fixlet_update_tracker.ojo` | Line 69 (comment), lines 55-71 (categories), lines 77-864 (CATEGORY_MAP) | PORTAL_CONFIG.categories taxonomy (13 items) does not match CATEGORY_MAP taxonomy (18 unique values; 10 absent from PORTAL_CONFIG.categories) | BLOCKER | Preview panel category dropdown pre-selects "Coding Tools" for Git, VS Code, Python, Docker, Firefox, etc. (D-16 fallback broken); portal copies get inconsistent categories (D-09 broken) |
| `Existing Dashboards/fixlet_update_tracker.ojo` | Lines 1101-1118 (loadPortalFixlets) and lines 1469, 1505 (copyNextItem) | Task-type items included in portal query but copyNextItem hardcodes `fixlet/custom/` REST path | BLOCKER | Task-type portal items always fail at step 1 GET with HTTP 404; identical defect was fixed in fixlet_dispatcher.ojo (commit b97fd8e) |
| `Existing Dashboards/fixlet_update_tracker.ojo` | Line 1501 (copyNextItem step 3/4 boundary) | `parseCreatedId(b3)` result not checked for empty string before step 4 | WARNING | If parseCreatedId returns "" (unexpected POST response format), buildSupersededXml writes blank X-Superseded-By value; result reported as ok:true |
| `Existing Dashboards/fixlet_update_tracker.ojo` | Lines 1735, 1207 | Duplicate `id="chkAll"` — static HTML and dynamically-built table header both emit the same element ID | WARNING | IE9's getElementById returns only the first match; the static element may shadow the table header checkbox, breaking toggleSelectAll for the dynamic table |
| `Existing Dashboards/fixlet_update_tracker.ojo` | Line 945 (makeSortHeader) | `label` parameter concatenated into innerHTML without htmlEscape | WARNING | Low risk now (all callers use string literals); unguarded for future dynamic label callers |
| `scripts/generate_category_map.js` | Line 27 | `fs.readFileSync` called without try/catch; raw stack trace if CSV is absent | WARNING | Developer UX issue; script exits non-zero with no actionable error message |

No `TBD`, `FIXME`, or `XXX` debt markers found in any phase-6 modified files.

---

## Human Verification Required

### 1. BigFix Console import and load

**Test:** Import `Existing Dashboards/fixlet_update_tracker.ojo` into a BigFix Console via `File > Import`. Open the dashboard from the Dashboards menu.
**Expected:** Dashboard loads without JavaScript errors; "Dereso Fixlet Update Tracker" title visible; tab bar shows "Updates" (active) and "New Arrivals".
**Why human:** OJO XML import and IE9 BigFix Console rendering require a live BigFix Console installation.

### 2. Scan produces populated tables

**Test:** Click "Scan for Updates". Observe status bar during scan.
**Expected:** Status changes to "Scanning site 1 of 1: BigFix Software Installer Library for Windows... (0 fixlets found so far)"; scan completes with "Scan complete. N updates, M new arrivals."; badge counts appear on tab buttons.
**Why human:** EvaluateRelevance calls execute only inside the BigFix Console runtime; cannot be tested outside it.

### 3. End-to-end copy for a Fixlet-type item (requires BIGFIX env vars)

**Test:** With BIGFIX_URL/USER/TOKEN set, run `node tests/integration/update_tracker.integration.test.js`. Then separately: in the dashboard, select a Fixlet-type update row, click "Copy Selected", verify preview panel, click "Confirm & Copy All".
**Expected:** Integration GROUP B tests pass (< 30s per GET, HTTP 200). In dashboard: results panel shows "OK: [product name] → new ID [N]"; old portal fixlet has `X-Superseded-By` MIME field set to N; new fixlet appears in "Dereso Software Portal" site.
**Why human:** Write operations to BigFix require a staging environment; POST/PUT calls cannot be verified by grep; validates CR-02 edge case under real conditions.

### 4. New Arrivals copy (post gap-fix: taxonomy alignment)

**Test:** After CR-03 taxonomy alignment fix, click "Copy" on a New Arrivals row.
**Expected:** New fixlet created in "Dereso Software Portal" with a category that matches one of the portal's configured categories; no "Developer Tools" or "Database & Data Tools" category values appear in portal.
**Why human:** Requires live BigFix REST API to verify the POST result.

---

## Gaps Summary

Three gaps block goal achievement. All originate from the code review (06-REVIEW.md) findings that were documented but not resolved before verification.

**Root cause 1 — CATEGORY_MAP taxonomy mismatch (CR-03)**
The `PORTAL_CONFIG.categories` array was populated with different category names than the `CATEGORY_MAP` values produced by `generate_category_map.js`. There are 8 overlapping categories out of 18 distinct CATEGORY_MAP values; 10 CATEGORY_MAP values are absent from the dropdown options. This breaks the D-16 CSV fallback path and the D-09 New Arrivals suggested-category guarantee. Fix: align the two category lists by updating PORTAL_CONFIG.categories.

**Root cause 2 — Task-type portal items not handled (CR-01)**
`loadPortalFixlets` queries both fixlets and tasks but does not store the item type. `copyNextItem` hardcodes `fixlet/custom/` for both the GET and PUT REST paths. Tasks in the portal will fail step 1 with HTTP 404. Fix: add a 5th `itemType` pipe segment to the relevance query and use it in the API path construction — the identical fix was already applied in `fixlet_dispatcher.ojo`.

**Root cause 3 — Cancel button does not restore tab visibility (CR-04)**
`showPreviewPanel` hides both tab content panels, but the Cancel button uses a bare inline onclick that only hides the preview panel. The admin's only recovery is to re-scan. Fix: add `onCancelCopy()` function and wire the Cancel button to it.

**One warning — empty newId not guarded (CR-02)**
After a successful POST (step 3), `parseCreatedId` is called but the result is not checked before being passed to `buildSupersededXml`. A blank `X-Superseded-By` value is written if BigFix returns an unexpected response format. Fix: add an `if (!newId) { ... }` guard and push an error result before recursing.

---

_Verified: 2026-07-09_
_Verifier: Claude (gsd-verifier)_
