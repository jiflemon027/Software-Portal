---
phase: 02-modifier
fixed_at: 2026-06-14T12:30:00Z
review_path: .planning/phases/02-modifier/02-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-06-14T12:30:00Z
**Source review:** .planning/phases/02-modifier/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (3 Critical + 5 Warning)
- Fixed: 8
- Skipped: 0

## Fixed Issues

### CR-01: Wrong regex in buildUpdateXml — old Associated_Roles MIME field never stripped

**Files modified:** `Existing Dashboards/fixlet_modifier.ojo`
**Commit:** 71b60a9
**Applied fix:** Changed the regex from `Associated_Role-` (hyphen) to `Associated_Roles\s*<\/Name>` (explicit plural + closing Name tag). The old pattern never matched any real MIME field, causing duplicate `Associated_Roles` fields to accumulate on every save. The new pattern correctly strips the existing field before re-writing it, and uses an explicit `</Name>` close to prevent over-matching.

---

### CR-02: Broken HTML table — Roles row TDs orphaned outside any tr

**Files modified:** `Existing Dashboards/fixlet_modifier.ojo`
**Commit:** dd803f5
**Applied fix:** Removed the spurious empty `<tr>` on line 734 (which immediately preceded the Category `<tr>`). Wrapped the Roles label and `roleFieldTable` in their own proper `<tr>...</tr>` pair. Both Category and Roles rows now have correct table structure that IE's HTML parser can render.

---

### CR-03: XSS — unescaped fixlet field data assigned to innerHTML

**Files modified:** `Existing Dashboards/fixlet_modifier.ojo`
**Commit:** f25971c
**Applied fix:** Added `htmlEscape()` function (escapes `&`, `<`, `>`, `"`) immediately after the `getPageSize()` function. Applied `htmlEscape()` to all four table cell innerHTML assignments in `renderPage()` (name, category, id, siteName, roleCount). Changed `setStatus()` from `el.innerHTML = msg` to `el.innerText = msg` to prevent HTML injection in the status bar.

---

### WR-01: closePreview() has no UI trigger — preview panel cannot be closed

**Files modified:** `Existing Dashboards/fixlet_modifier.ojo`
**Commit:** c660ddf
**Applied fix:** Added a "Close" button inside the `#xmlPreviewPanel` header div: `<button class="btn" style="float:right; margin-bottom:4px;" onclick="closePreview()">Close</button>`. The button is inline with the "XML Preview" label and floats right.

---

### WR-02: addNode() is dead code — defined but never called

**Files modified:** `Existing Dashboards/fixlet_modifier.ojo`
**Commit:** 31e18b9
**Applied fix:** Removed the entire `addNode()` function (8 lines). No callers existed anywhere in the file; `buildUpdateXml()` uses the MSXML DOM API directly.

---

### WR-03: catSel.value = "" is a silent no-op in IE when no blank option exists

**Files modified:** `Existing Dashboards/fixlet_modifier.ojo`
**Commit:** f03eec1
**Applied fix:** Added a blank placeholder option as the first entry in `loadCategoryOptions()` (before the real category loop): `blank.value = ""`, `blank.text = "-- Select category --"`. Now when `parseSourceFields()` sets `catSel.value = ""` for a fixlet with no category, the dropdown correctly shows the placeholder rather than silently retaining the first real category.

---

### WR-04: assertNotEmpty defined but never called — dead test utility

**Files modified:** `tests/integration/modifier.integration.test.js`
**Commit:** 789ff78
**Applied fix:** Removed the `assertNotEmpty()` function entirely (6 lines). It was never called in any of the six test functions and added no coverage.

---

### WR-05: bodyBuffer declared inside one conditional block, read inside a separate identical block

**Files modified:** `tests/integration/modifier.integration.test.js`
**Commit:** 789ff78
**Applied fix:** Replaced `req.write(bodyBuffer)` in the second `if (method === "PUT" && bodyXml)` block with `req.write(Buffer.from(bodyXml, "utf8"))`. The `bodyBuffer` variable in the first block is still used for `Content-Length` (correct), but the second block now re-derives the buffer inline rather than depending on a cross-block variable. This eliminates the fragile split-state dependency.

---

_Fixed: 2026-06-14T12:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
