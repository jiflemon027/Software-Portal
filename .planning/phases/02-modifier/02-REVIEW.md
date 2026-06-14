---
phase: 02-modifier
reviewed: 2026-06-14T12:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - Existing Dashboards/fixlet_modifier.ojo
  - tests/unit/modifier.test.js
  - tests/integration/modifier.integration.test.js
  - tests/fixtures/phase-02/valid-fixlet-no-roles.ojo
  - tests/fixtures/phase-02/valid-fixlet-with-roles.ojo
findings:
  critical: 3
  warning: 5
  info: 5
  total: 13
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-06-14T12:00:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Five files were reviewed: the primary dashboard implementation (`fixlet_modifier.ojo`), unit tests, integration tests, and two XML fixtures. The implementation is a BigFix IE9-hosted dashboard (ActiveXObject DOM, EvaluateRelevance, API.Put/Get).

Three blockers were found. The most severe is a data-corruption bug in `buildUpdateXml()` where the regex that strips the old `Associated_Roles` MIME field before re-writing it uses the wrong field name pattern (`Associated_Role-` with a hyphen instead of `Associated_Roles` with an `s`), guaranteeing duplicate MIME fields accumulate on every save. The second blocker is broken HTML table structure in the role editor panel that orphans the "Roles" row in IE's parser. The third is an XSS vector: unescaped fixlet names and site names from BigFix are injected directly as `innerHTML` in the table and in the status bar.

Five warnings cover: a `closePreview()` function with no trigger in the UI, dead code (`addNode`, `assertNotEmpty`), a category-blank-value edge case, a `bodyBuffer` scoping pattern in the integration test, and the `catSel.value = ""` silent no-op.

---

## Critical Issues

### CR-01: `buildUpdateXml` regex uses wrong field name — old `Associated_Roles` MIME field is never stripped

**File:** `Existing Dashboards/fixlet_modifier.ojo:565-566`
**Issue:** The regex intended to remove the existing `Associated_Roles` MIME field before writing a fresh one matches `Associated_Role-` (hyphen suffix) instead of `Associated_Roles` (letter `s`). No existing fixlet will ever have a field named `Associated_Role-*`, so the old field is never removed. On each save, `buildUpdateXml()` appends a new `Associated_Roles` node after the old one. After two saves, the fixlet contains two `Associated_Roles` MIME fields. After N saves, N fields. `parseSourceFields()` only reads the first match, so the displayed roles may diverge from what was last saved. The BigFix relevance injector `selectNodes("//Relevance[contains(., 'RoleAwareness.db')]")` removes all matching relevance nodes correctly; it is only the MIME field that accumulates.

```javascript
// CURRENT (broken) — line 565-566
var cleanedXml = ("" + sourceXml).replace(
  /<MIMEField>\s*<Name>\s*Associated_Role-[\s\S]*?<\/MIMEField>/gi, "");

// FIX — match the actual field name (Associated_Roles, no hyphen, plural s)
var cleanedXml = ("" + sourceXml).replace(
  /<MIMEField>\s*<Name>\s*Associated_Roles\s*<\/Name>[\s\S]*?<\/MIMEField>/gi, "");
```

The regex should also close the `<Name>` tag explicitly so it does not accidentally match unrelated MIME fields whose names merely start with `Associated_Roles`.

---

### CR-02: Broken HTML table structure — "Roles" row TDs are orphaned outside any `<tr>`

**File:** `Existing Dashboards/fixlet_modifier.ojo:734-751`
**Issue:** Line 734 opens a `<tr>` that is immediately followed by another `<tr>` on line 735 (the Category row). IE's HTML parser implicitly closes the first empty `<tr>` before the second one opens. The Category row then closes with `</tr>` at line 744. The "Roles" label and `roleFieldTable` container (lines 746-750) are `<td>` elements with no enclosing `<tr>` — they appear between the `</tr>` on line 744 and the `</tr>` on line 751. IE discards or misplaces orphaned `<td>` elements, meaning the role editor section does not render. The "Add Role" button and `roleFieldTable` are invisible or mispositioned.

```html
<!-- CURRENT (broken) lines 733-751 -->
        </tr>
        <tr>         <!-- empty tr, immediately superseded -->
        <tr>
          <td class="lbl">Category:</td>
          <td>...</td>
        </tr>

          <td class="lbl" ...>Roles:</td>   <!-- orphaned td -->
          <td>...</td>
        </tr>                              <!-- unmatched closing tr -->

<!-- FIX -->
        </tr>
        <tr>
          <td class="lbl">Category:</td>
          <td>...</td>
        </tr>
        <tr>
          <td class="lbl" style="vertical-align:top; padding-top:8px;">Roles:</td>
          <td>
            <table id="roleFieldTable" class="roleTable"></table>
            <button class="btn" style="margin-top:6px;" onclick="addRoleRow('')">+ Add Role</button>
          </td>
        </tr>
```

---

### CR-03: XSS — unescaped fixlet field data assigned to `innerHTML`

**File:** `Existing Dashboards/fixlet_modifier.ojo:292-295, 88, 665`
**Issue:** `renderPage()` writes fixlet name, category, id, and site name directly into table cells via `innerHTML` without HTML-escaping. These values come from `EvaluateRelevance()` which returns BigFix server data. If any fixlet name or site name contains `<`, `>`, `"`, or `<script>`, it executes in the dashboard's IE context. Additionally, `setStatus()` uses `innerHTML` and is called with `currentItem.siteName` at line 665. In a BigFix environment the attack requires a fixlet name or site name containing HTML — possible via the BigFix admin console — but the context (a privileged admin dashboard) makes this a meaningful risk.

```javascript
// CURRENT (lines 292-295) — unescaped
r.insertCell(-1).innerHTML = item.name;
r.insertCell(-1).innerHTML = item.category;
r.insertCell(-1).innerHTML = item.id;
r.insertCell(-1).innerHTML = item.siteName;

// FIX — escape before assignment
function htmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

r.insertCell(-1).innerHTML = htmlEscape(item.name);
r.insertCell(-1).innerHTML = htmlEscape(item.category);
r.insertCell(-1).innerHTML = htmlEscape(item.id);
r.insertCell(-1).innerHTML = htmlEscape(item.siteName);

// Also fix setStatus (line 88): use innerText instead of innerHTML,
// or escape msg before assignment.
function setStatus(msg){
  var el = document.getElementById("status");
  if(el){ el.innerText = msg; }   // innerText does not parse HTML
}
```

---

## Warnings

### WR-01: `closePreview()` is defined but has no UI trigger — XML preview panel cannot be closed

**File:** `Existing Dashboards/fixlet_modifier.ojo:631-634, 769-774`
**Issue:** `closePreview()` correctly sets `xmlPreviewPanel` to `display:none`, but no button in the HTML calls it. Once the preview panel opens (via "Preview XML"), it stays open with no affordance to dismiss it. This is a functional usability defect.

**Fix:** Add a close button inside the preview panel:
```html
<!-- Inside #xmlPreviewPanel panelBody, after the small label -->
<button class="btn" style="float:right;" onclick="closePreview()">Close</button>
```

---

### WR-02: `addNode()` is dead code — defined but never called

**File:** `Existing Dashboards/fixlet_modifier.ojo:549-556`
**Issue:** `addNode()` constructs XML tag strings with CDATA or entity-escaped content. It is defined and never called anywhere in the file. `buildUpdateXml()` uses the MSXML DOM API directly (`createElement`, `.text =`). This function is an unreachable code path.

**Fix:** Remove the `addNode` function entirely (lines 549-556).

---

### WR-03: `catSel.value = ""` is a silent no-op in IE when no blank option exists

**File:** `Existing Dashboards/fixlet_modifier.ojo:402`
**Issue:** When a fixlet's `<Category>` element is empty (no category set), `parseSourceFields()` reaches the `else if(!catFound)` branch and sets `catSel.value = ""`. Because `loadCategoryOptions()` never adds a blank `value=""` option, this assignment has no effect in IE — the dropdown retains whatever is currently selected (typically the first category, "Coding Tools"). If the user saves without noticing, the fixlet gains an incorrect category. The bug is silent: no warning is shown and no blank/placeholder state is communicated.

**Fix:** Add a blank placeholder option as the first entry in `loadCategoryOptions()`:
```javascript
function loadCategoryOptions(){
  var sel = document.getElementById("editCategory");
  if(!sel){ return; }
  sel.innerHTML = "";
  // Add blank placeholder first
  var blank = document.createElement("option");
  blank.value = "";
  blank.text  = "-- Select category --";
  sel.appendChild(blank);
  // ... rest of function unchanged
}
```
Then `catSel.value = ""` will correctly select this placeholder.

---

### WR-04: `assertNotEmpty` defined but never called — dead test utility

**File:** `tests/integration/modifier.integration.test.js:152-156`
**Issue:** `assertNotEmpty` is defined at line 152 and never used in any of the six test functions. It contributes no coverage and misleads future readers into thinking it is exercised.

**Fix:** Remove the `assertNotEmpty` function, or add at least one call (e.g., in `test2_loadSourceFixlet` to assert the response body is non-empty).

---

### WR-05: `bodyBuffer` declared inside one conditional block, read inside a separate identical block

**File:** `tests/integration/modifier.integration.test.js:84-105`
**Issue:** `bodyBuffer` is declared with `var` inside the first `if (method === "PUT" && bodyXml)` block (line 85) and written to the request inside a second identical `if` block (line 103-105). While `var` hoisting means this works at runtime, the split creates a subtle correctness dependency: if the two conditions ever diverge (e.g., `bodyXml` is truthy in one check but falsy in the other due to mutation), `bodyBuffer` would be `undefined` when `req.write(bodyBuffer)` executes, causing a silent empty body. The two blocks should be merged.

**Fix:**
```javascript
if (method === "PUT" && bodyXml) {
  var bodyBuffer = Buffer.from(bodyXml, "utf8");
  requestOptions.headers["Content-Type"]   = "application/xml";
  requestOptions.headers["Content-Length"] = bodyBuffer.length;
}

var req = https.request(requestOptions, function(res) { /* ... */ });
req.on("error", function(err) { callback(err.message || String(err), null, null); });

if (method === "PUT" && bodyXml) {
  req.write(Buffer.from(bodyXml, "utf8"));  // re-derive, no split state
}
req.end();
```

---

## Info

### IN-01: Inconsistent indentation mix (tabs vs spaces) in `fixlet_modifier.ojo`

**File:** `Existing Dashboards/fixlet_modifier.ojo` (throughout)
**Issue:** The file uses spaces in the outer JS block (lines 35-673) and tabs in the HTML block (lines 675+) and in some inner functions (`parseSourceFields`, `saveFixlet` callback). This inconsistency extends into mixed indentation within individual functions (e.g., `parseSourceFields` at lines 385-425 uses tabs while the wrapping function body uses spaces).

**Fix:** Normalize to spaces (matching the majority of the file) throughout.

---

### IN-02: `buildRoleRelevance` does not escape role names — would break on a role containing a double-quote

**File:** `Existing Dashboards/fixlet_modifier.ojo:514`
**Issue:** Role names from `PORTAL_CONFIG.roles` are interpolated into a BigFix relevance string with double-quote delimiters: `'"' + roles.join('";"') + '"'`. A role name containing `"` would produce malformed relevance syntax. In the current deployment the 7 role names contain no quotes, so this is dormant. If `PORTAL_CONFIG` is ever edited to add a role with a quote in its name, the injected relevance will fail silently (the relevance evaluates to `False`).

**Fix:** Strip or escape double-quotes in role names before injection:
```javascript
var roleSet = '"' + roles.map(function(r){ return r.replace(/"/g, ''); }).join('";"') + '"';
```

---

### IN-03: Unit tests do not cover `xmlEscape` order-of-operations edge case

**File:** `tests/unit/modifier.test.js:152-181`
**Issue:** `xmlEscape` replaces `&` first, then `<`, `>`, etc. This is the correct order (replacing `&` first prevents double-escaping). The test suite verifies each character individually and all five together in one string, but does not test that `&` in a string like `"&lt;"` is correctly escaped to `"&amp;lt;"` rather than being processed as an already-escaped entity. This edge case is currently passing by construction (the function is correct), but there is no test proving the order-dependency.

**Fix (optional):** Add one test:
```javascript
expect("already-escaped entity is not double-processed", function(){
  assert.strictEqual(xmlEscape("&lt;"), "&amp;lt;");
});
```

---

### IN-04: `valid-fixlet-no-roles.ojo` fixture does not include a `MIMEField` section — the "first association" path in `buildUpdateXml` is untested at integration level

**File:** `tests/fixtures/phase-02/valid-fixlet-no-roles.ojo`
**Issue:** The integration test (test 3) uses only `valid-fixlet-with-roles.ojo`. The `valid-fixlet-no-roles.ojo` fixture is never used by any test in the integration suite. The "no existing MIME field" path (where `buildUpdateXml` must create `Associated_Roles` from scratch without a prior value to strip) is not exercised.

**Fix:** Add an integration test (or a second PUT scenario within test 3) that uses `valid-fixlet-no-roles.ojo` as the fixture body and verifies the response is 200/201.

---

### IN-05: `testREST()` function exposed as a UI button — should be removed from production dashboard

**File:** `Existing Dashboards/fixlet_modifier.ojo:119-124, 691`
**Issue:** The "Test REST" button at line 691 calls `testREST()` which makes a live `GET /api/sites` call and shows "API OK" or "FAIL" in the status bar. This is a diagnostic artifact useful during development but exposed in the production dashboard. It provides no user value and consumes an API call unnecessarily.

**Fix:** Remove the `testREST()` function (lines 119-124) and the corresponding HTML button (line 691).

---

_Reviewed: 2026-06-14T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
