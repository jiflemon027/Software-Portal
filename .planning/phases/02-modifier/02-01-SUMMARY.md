---
phase: 02-modifier
plan: "01"
subsystem: modifier-dashboard
tags: [bigfix, javascript, bug-fix, dead-code, config-block, portal-config]
dependency_graph:
  requires: []
  provides:
    - fixlet_modifier.ojo (fixed, cleaned, PORTAL_CONFIG wired)
  affects:
    - tests/unit/modifier.test.js (plan 02-02 will test against this fixed file)
tech_stack:
  added: []
  patterns:
    - PORTAL_CONFIG inline config block pattern (admin-editable const at top of JS)
    - loadCategoryOptions() dynamic select population from config array
key_files:
  created: []
  modified:
    - Existing Dashboards/fixlet_modifier.ojo
decisions:
  - Use Write (full rewrite) to handle non-ASCII characters in original file comments that blocked Edit tool
  - EvaluateRelevance count = 2 (not 1 as plan expected) because loadAllFixlets() legitimately uses it alongside loadSitenames()
metrics:
  duration: "13 minutes"
  completed: "2026-06-14"
  tasks_completed: 2
  files_modified: 1
---

# Phase 2 Plan 01: Modifier Bug Fix + PORTAL_CONFIG Summary

**One-liner:** Fixed duplicate-var and stale-cleanedXml bugs in buildUpdateXml(), stripped all dead functions and diagnostic alerts, and added PORTAL_CONFIG block to externalize roles and categories from hardcoded JS to admin-editable config.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Fix buildUpdateXml() bugs, remove dead code, strip alert() diagnostics | a0c7cc7 |
| 2 | Add PORTAL_CONFIG block, refactor loadRoleValues(), add loadCategoryOptions() | a0c7cc7 |

Note: Tasks 1 and 2 were committed together because the non-ASCII characters in the original file's comment delimiters required a complete file rewrite (Write tool) rather than incremental edits. Both tasks are fully implemented and verified.

## What Was Built

### Task 1: Bug Fixes and Dead Code Removal

**Bug Fix 1 — Duplicate `var fixletNode`:**
In `buildUpdateXml()`, the second identical `var fixletNode = origDoc.getElementsByTagName("Fixlet")[0]` and its guard were deleted. Only the first pair at the top of the logic remains. `var fixletNode` now appears exactly once.

**Bug Fix 2 — Stale `cleanedXml` redeclaration:**
Deleted the 4-line block beginning with `var cleanedXml = String(sourceXml).replace(` (the second declaration) along with the placeholder comment `// ... (load into origDoc, update title, category, relevance as before) ...`. The correct `cleanedXml` from the top of the function remains. The MIME-field writing DOM operations that followed remain intact.

**Dead Code — `_renumberRoleRows()` deleted:**
This function labelled rows "Associated-Role-N" (old format). The active `renumberRoleRows()` (no underscore, labels "Role N") remains; it is called by `removeRoleRow()`.

**Dead Code — `addCategoryRow()` deleted:**
This function was never called from the active HTML (which calls `addRoleRow()`). Deleted entirely.

**Dead Code — `_previewXml()` deleted:**
This function was never called from the active HTML (which calls `previewXml()`). Active `previewXml()` remains.

**Diagnostic Alert Strip:**
Removed all four commented-out `//alert(...)` diagnostic blocks from `buildUpdateXml()` and the dead commented-out return statement (`// return '<?xml version...`).

**testREST() Fix:**
Replaced `alert("API OK")` with `setStatus("API OK")` and `alert("FAIL: " + e + " status=" + s)` with `setStatus("FAIL: " + e + " status=" + s)`. No more modal popups from the Test REST button.

### Task 2: PORTAL_CONFIG Block and Category Wiring

**PORTAL_CONFIG block inserted at top of JS (before all var declarations):**
```javascript
var PORTAL_CONFIG = {
  roles: ["General Access", "IT Developer", "IT Support",
          "DB Developer", "DB Administrator", "Payments Processor", "Marketer"],
  categories: ["Coding Tools", "Database Tools", "Drivers", "Graphics & Design",
               "Messengers", "Office Applications", "Office Tools",
               "Virtualization & Remote Access", "Web Browsers"]
};
```

**`loadRoleValues()` refactored:**
Old body used `EvaluateRelevance` to return its own literal arguments (unnecessary overhead). New body: `roleValues = PORTAL_CONFIG.roles.slice();`

**`loadCategoryOptions()` added:**
New function clears `editCategory` select and populates it dynamically from `PORTAL_CONFIG.categories[]`, appending "Other (specify below)" as the last option with value `__other__`.

**`initDashboard()` updated:**
Added `loadCategoryOptions()` call after `loadRoleValues()`.

**HTML `editCategory` select emptied:**
Removed all 10 hardcoded `<option>` elements. Select element retains its `id`, `class`, and `onchange` attributes. Options are now built at runtime by `loadCategoryOptions()`.

## Verification Results

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `var fixletNode` count | 1 | 1 | PASS |
| `_previewXml` count | 0 | 0 | PASS |
| `_renumberRoleRows` count | 0 | 0 | PASS |
| `addCategoryRow` count | 0 | 0 | PASS |
| `var cleanedXml = String(sourceXml)` count | 0 | 0 | PASS |
| `var PORTAL_CONFIG` count | 1 | 1 | PASS |
| `PORTAL_CONFIG.roles.slice` count | 1 | 1 | PASS |
| `loadCategoryOptions` count | 2 | 2 | PASS |
| `Coding Tools` in HTML options | 0 | 0 | PASS |
| `alert()` in testREST() | 0 | 0 | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Non-ASCII characters in file prevented Edit tool from matching lines**
- **Found during:** Task 1 (during `_previewXml` deletion)
- **Issue:** The original file used UTF-8-encoded em-dash decorators in section-separator comments (e.g., `// -- Section --` encoded as mojibake `// Ã¢â€â‚¬Ã¢â€â‚¬`). The Edit tool cannot represent these bytes in its `old_string` parameter, causing match failures when trying to delete lines that contained them.
- **Fix:** Used the Write tool for a complete file rewrite with clean ASCII comment delimiters (`// -- Section --`), preserving all functional JS unchanged.
- **Files modified:** `Existing Dashboards/fixlet_modifier.ojo`
- **Commit:** a0c7cc7

**2. [Rule 1 - Bug] Accidental deletion of `var fixletNode` declaration during diagnostic comment removal**
- **Found during:** Task 1 (while using node script to remove lines)
- **Issue:** When removing the diagnostic comment block (lines 532-538), line 539 (`var fixletNode = ...`) was also removed due to an off-by-one in the node script.
- **Fix:** Immediately restored the `var fixletNode` line using Edit tool before continuing.
- **Commit:** Included in final rewrite a0c7cc7

### Plan Verification Discrepancy

The plan's verify criteria states: `grep -c "EvaluateRelevance" "Existing Dashboards/fixlet_modifier.ojo" -- expect 1 (only loadSitenames() still uses it)`

**Actual result: 2 occurrences** — `loadSitenames()` (line 129) and `loadAllFixlets()` (line 181). Both uses are correct and necessary:
- `loadSitenames()`: Queries BigFix for custom site names to populate the site filter dropdown
- `loadAllFixlets()`: Queries BigFix for all fixlets with their role MIME data

The plan's comment that "only loadSitenames() still uses it" was incorrect — it overlooked that `loadAllFixlets()` also uses EvaluateRelevance, which was always the case in the original file. The plan's intent was to remove the unnecessary use in `loadRoleValues()` (which called `EvaluateRelevance` just to return its own literal arguments). That removal is complete and correct. The 2 remaining uses are legitimate.

## Known Stubs

None. All functions are fully implemented.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced. All changes are to existing BigFix dashboard JavaScript — no new trust boundaries.

## Self-Check: PASSED

- [x] `Existing Dashboards/fixlet_modifier.ojo` — exists and modified
- [x] Commit a0c7cc7 exists
- [x] All 10 verification grep checks pass
- [x] No untracked files after commit
