---
phase: 06-update-tracker
reviewed: 2026-07-09T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - Existing Dashboards/fixlet_update_tracker.ojo
  - scripts/generate_category_map.js
  - tests/unit/update_tracker.test.js
  - tests/integration/update_tracker.integration.test.js
  - tests/fixtures/phase-06/portal-fixlet-with-roles.xml
  - tests/fixtures/phase-06/source-fixlet-new-version.xml
  - tests/fixtures/phase-06/expected-copy-output.xml
  - tests/fixtures/phase-06/expected-superseded-output.xml
  - scripts/category_map_output.js
findings:
  critical: 4
  warning: 5
  info: 0
  total: 9
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-07-09
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

The primary dashboard file (`fixlet_update_tracker.ojo`) implements a two-tab scan engine with copy and supersede workflows. Pure-logic functions are IE9-safe and well-structured. XSS mitigations via `htmlEscape` are consistently applied to all dynamic DOM writes in data cells. The BigFix REST API call chain in `copyNextItem` correctly handles both 200 and 201 status codes and recurses on failure per D-12.

Four blockers were found: a Task-type API path bug inherited from the same class of defect fixed in the dispatcher; silent data corruption when `parseCreatedId` returns an empty string; a pervasive CATEGORY_MAP vs PORTAL_CONFIG.categories name mismatch that will silently write wrong category values to portal fixlets for the majority of products; and a Cancel button that leaves the entire tab UI hidden with no recovery path short of re-scanning.

## Critical Issues

### CR-01: Portal Tasks use wrong REST path — copyNextItem hardcodes `fixlet/custom/` for GET and PUT

**File:** `Existing Dashboards/fixlet_update_tracker.ojo:1108-1115, 1469-1470, 1505-1506`

**Issue:** `loadPortalFixlets` queries `bes fixlets whose (... and (fixlet flag of it or task flag of it))` capturing both fixlets and tasks, but the 4-field result only stores `{id, name, category, roles}` — no type indicator. `copyNextItem` then unconditionally builds the portal GET path as `fixlet/custom/...` (line 1469) and PUT path as `fixlet/custom/...` (line 1505). If the portal item is a Task, both calls return 404 and the item silently fails with the misleading message "GET portal fixlet failed: status=404". The git log shows the identical defect was fixed in `fixlet_dispatcher.ojo` (`fix(dispatcher): support Task type`); this file was not updated with the same fix.

**Fix:** Capture the item type in `loadPortalFixlets` and pass it through to `copyNextItem`:

```javascript
// loadPortalFixlets — add type field (5th pipe segment)
var rel =
  '(id of it as string' +
  ' & "|||" & name of it' +
  ' & "|||" & (if exists category of it then category of it as string else "")' +
  ' & "|||" & (if exists mime fields whose (name of it = "Associated_Roles") of it ...' +
  ' & "|||" & (if task flag of it then "task" else "fixlet"))' +
  ' of bes fixlets whose (...';
// parse: items.push({ id:p[0], name:p[1], category:p[2]||"", roles:p[3]||"", itemType:p[4]||"fixlet" });

// copyNextItem — use itemType to select path
var pathType = item.portalItemType || "fixlet";
var portalGetPath = pathType + "/custom/" + encodeURIComponent("Dereso Software Portal") +
                    "/" + encodeURIComponent(item.portalId);
// same for putPath
```

---

### CR-02: Empty `newId` from `parseCreatedId` not guarded — X-Superseded-By gets blank value, corrupting the portal fixlet

**File:** `Existing Dashboards/fixlet_update_tracker.ojo:1501-1504`

**Issue:** After a successful POST (200/201), `parseCreatedId(b3)` is called to extract the new fixlet ID. If the response body has an unexpected format, `parseCreatedId` returns `""` (line 939, the silent catch block returns empty string and all regex fallbacks can also fail). The code then immediately calls `buildSupersededXml(portalXml, newId)` with `newId = ""`. `buildSupersededXml` does `valueEl.text = String("")`, so the old portal fixlet is PUT with `<Value></Value>` for `X-Superseded-By`. The callback then reports `ok: true` (if the PUT returns 200/201) — the admin sees "OK" but the supersede marker is meaningless. The new copy exists in the portal with no link back from the old fixlet.

**Fix:** Guard against empty `newId` before proceeding to Step 4:

```javascript
var newId = parseCreatedId(b3);
if (!newId) {
  results.push({ ok: false, name: item.sourceName,
                 error: "POST succeeded but could not extract new fixlet ID from response" });
  copyNextItem(items, index + 1, results, onAllDone);
  return;
}
// proceed to Step 4
var supersededXml = buildSupersededXml(portalXml, newId);
```

---

### CR-03: CATEGORY_MAP category names do not match PORTAL_CONFIG.categories — preview panel defaults to wrong category; arrivals get invalid categories written to XML

**File:** `Existing Dashboards/fixlet_update_tracker.ojo:55-71, 77-864, 1552, 1588`

**Issue:** `PORTAL_CONFIG.categories` (line 55-71) lists 13 category names. `CATEGORY_MAP` (lines 77-864) uses an entirely different taxonomy — "Developer Tools", "Communication & Conferencing", "Database & Data Tools", "Web Browser" (singular), "Containers & DevOps", "Cloud & File Sync", "Network Tools", "Video & Screen Recording", "Productivity & Organization" — none of which appear in `PORTAL_CONFIG.categories`. The only partial overlap is the 8 categories that happen to match both lists ("File Management & Archiving", "Graphics & Image Editing", etc.).

Consequences:
1. **Preview panel (updates)**: `lookupCategory(item.productKey, item.portalCategory)` returns e.g. "Developer Tools". The loop at line 1588 checks `lookupCategory(...) === cat` against `PORTAL_CONFIG.categories` entries. No match → no `selected` attribute → browser defaults to the first `<option>`, which is "Coding Tools". The admin sees "Coding Tools" pre-selected for Git, VS Code, Node.js, Python, etc.
2. **New arrivals (onCopyArrival)**: `arrival.copyCategory = arrival.suggestedCategory` (line 1552) sets the category directly from CATEGORY_MAP without any validation. `buildCopyXml` writes `<Category>Developer Tools</Category>` (or similar) into the portal copy. This value does not exist in the portal's configured category list and will cause classification inconsistencies.

The comment at line 69 explicitly states "Categories must match CATEGORY_MAP values for consistent display" but the values do not match.

**Fix (two parts):**

Part A — align `PORTAL_CONFIG.categories` with the values actually used in `CATEGORY_MAP`:
```javascript
categories: [
  "Cloud & File Sync",
  "Communication & Conferencing",
  "Containers & DevOps",
  "Database & Data Tools",
  "Developer Tools",
  "File Management & Archiving",
  "Graphics & Image Editing",
  "Java Runtime & JDK",
  "Media & Entertainment",
  "Network Tools",
  "Office Suite & Writing",
  "PDF & Document Management",
  "Productivity & Organization",
  "Remote Access & Virtualization",
  "Security & Privacy",
  "System Utilities & Monitoring",
  "Video & Screen Recording",
  "Web Browser"
]
```

Part B — in `generate_category_map.js`, add a post-generation validation step that cross-checks all emitted category values against the portal config list and errors if any are not present.

---

### CR-04: Cancel button in preview panel does not restore tab visibility — UI is broken after Cancel

**File:** `Existing Dashboards/fixlet_update_tracker.ojo:1607-1611` (HTML at line 1751)

**Issue:** `showPreviewPanel` hides both tab panels (lines 1610-1611):
```javascript
if (tabUpdatesEl)  { tabUpdatesEl.style.display  = "none"; }
if (tabArrivalsEl) { tabArrivalsEl.style.display = "none"; }
```

The Cancel button (line 1751 of the HTML block) only hides `previewPanel`:
```html
<button class="btn" onclick="document.getElementById('previewPanel').style.display='none';">Cancel</button>
```

After Cancel is clicked: `previewPanel` is hidden, but `tabUpdates` and `tabArrivals` remain `display:none`. The user sees the scan panel and tab bar buttons but both tab content areas are invisible. The only recovery is to re-scan from scratch.

Note: `onConfirmCopy` does restore `tabUpdates` but not `tabArrivals` — a secondary omission in the confirm path.

**Fix:** Replace the inline onclick with a dedicated cancel handler:
```javascript
function onCancelCopy() {
  var panel = document.getElementById("previewPanel");
  if (panel) { panel.style.display = "none"; }
  var tabUpdatesEl  = document.getElementById("tabUpdates");
  var tabArrivalsEl = document.getElementById("tabArrivals");
  if (tabUpdatesEl)  { tabUpdatesEl.style.display  = ""; }
  if (tabArrivalsEl) { tabArrivalsEl.style.display = "none"; }  // stays hidden unless user switches tab
  switchTab("updates");  // restore active tab
}
```
And in HTML: `onclick="onCancelCopy()"`. Also fix `onConfirmCopy` to call `switchTab("updates")` rather than manually toggling the display.

---

## Warnings

### WR-01: Duplicate `id="chkAll"` — static HTML and dynamically-built table header both emit the same ID

**File:** `Existing Dashboards/fixlet_update_tracker.ojo` (HTML at line 1735; JS at line 1207)

**Issue:** The static markup has `<input type="checkbox" id="chkAll" onclick="toggleSelectAll(this)">` (line 1735). `renderUpdatesTable` also sets `chkAllCell.innerHTML = '<input type="checkbox" id="chkAll" onclick="toggleSelectAll(this)">'` (line 1207). IE9 requires unique IDs; duplicate IDs cause `getElementById` to return only the first match. The static element at line 1735 is present in the DOM even before a scan is run, so `getElementById("chkAll")` may not find the dynamically-created table header checkbox.

**Fix:** Remove the static `<label><input type="checkbox" id="chkAll"> Select All</label>` from the HTML markup (it is redundant with the table header checkbox). The table header checkbox alone suffices.

---

### WR-02: `buildCopyXml` silently skips category if source fixlet has no `<Category>` element

**File:** `Existing Dashboards/fixlet_update_tracker.ojo:1398-1399`

**Issue:**
```javascript
var catNodes = origDoc.getElementsByTagName("Category");
if (catNodes.length > 0) { catNodes[0].text = category; }
```
If the source fixlet has no `<Category>` element (e.g., an older or non-conforming fixlet), the override is silently skipped. The portal copy would have no `<Category>` element, making it invisible in category-filtered views.

**Fix:** Create the element if it doesn't exist:
```javascript
var catNodes = origDoc.getElementsByTagName("Category");
var catNode;
if (catNodes.length > 0) {
  catNode = catNodes[0];
} else {
  catNode = origDoc.createElement("Category");
  // Insert after <Relevance> — find it and insert after
  var relNodes = fixletNode.getElementsByTagName("Relevance");
  var refNode = relNodes.length > 0 ? relNodes[relNodes.length - 1].nextSibling : null;
  fixletNode.insertBefore(catNode, refNode || fixletNode.firstChild);
}
catNode.text = category;
```

---

### WR-03: `makeSortHeader` does not `htmlEscape` the `label` parameter

**File:** `Existing Dashboards/fixlet_update_tracker.ojo:943-945`

**Issue:**
```javascript
return '<b style="cursor:pointer;" onclick="sortBy(\'' + col + '\')">' + label + indicator + '</b>';
```
`label` is concatenated directly into the HTML string that is written to `innerHTML`. Currently all callers pass hardcoded string literals (lines 1209-1213), so there is no live XSS risk, but the function offers no protection if a future caller passes a dynamic value.

**Fix:**
```javascript
return '<b style="cursor:pointer;" onclick="sortBy(\'' + col + '\')">' + htmlEscape(label) + indicator + '</b>';
```

---

### WR-04: `generate_category_map.js` has no error handling around the CSV file read

**File:** `scripts/generate_category_map.js:27`

**Issue:**
```javascript
var lines = fs.readFileSync(csvPath, "utf8").replace(/\r/g, "").split("\n");
```
If `Dashboard_4_samples/software_categorized.csv` is absent or unreadable, Node.js throws an unhandled exception with a raw stack trace. A clear error message would be more helpful to the operator.

**Fix:**
```javascript
var rawCsv;
try {
  rawCsv = fs.readFileSync(csvPath, "utf8");
} catch (e) {
  console.error("ERROR: Cannot read CSV at " + csvPath + " — " + e.message);
  process.exit(1);
}
var lines = rawCsv.replace(/\r/g, "").split("\n");
```

---

### WR-05: `|||` field separator in EvaluateRelevance results is fragile

**File:** `Existing Dashboards/fixlet_update_tracker.ojo:1101-1115, 1152-1165`

**Issue:** Both `loadPortalFixlets` and the `scanNextSite` relevance concatenate fields using `"|||"` as a separator and then split on `"|||"`. If any field value (fixlet name, category string, role value) ever contains the literal string `|||`, the split produces extra array slots and all subsequent field assignments (`p[0]`, `p[1]`, etc.) are offset or garbled. Role values in particular use `|` as a delimiter already; `|||` is one character away.

**Fix:** Use a separator sequence that cannot appear in BigFix field values, or use BigFix `concatenation "…" of` on a multi-value expression that returns one row per record. A safe separator for the 4-field case is the ASCII unit separator `"\x1F"`:
```javascript
' & "\x1F" & name of it ...'
// and split on "\x1F"
p = String(data[i]).split("\x1F");
```

---

_Reviewed: 2026-07-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
