# Phase 2: Modifier (Role-Based Categorization) — Research

**Researched:** 2026-06-14
**Domain:** BigFix dashboard JavaScript — bug fixing, config block extraction, unit + integration testing
**Confidence:** HIGH (all findings are from direct codebase inspection, no external package dependencies)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Fix bugs + cleanup as part of Phase 2. Do **not** test-as-is and flag in review.
- Fix Bug 1: duplicate `var fixletNode` declaration inside `buildUpdateXml()` (lines 567 & 570)
- Fix Bug 2: `cleanedXml` redeclared inside `buildUpdateXml()` (lines 547 & 600) — second declaration shadows the first, potentially using stale XML when writing MIME fields
- Remove dead code: `_previewXml()` and `_renumberRoleRows()` functions (prefixed with `_`, never called)
- Strip commented-out `alert()` diagnostic calls throughout

**D-02:** Fix scope = bugs + cleanup only (not a full rewrite). Deliver a clean, production-ready `.ojo` file.

**D-03:** Add unit tests for pure JS functions — same pattern as `tests/unit/copier.test.js` from Phase 1.
- Target functions: `buildRoleRelevance()`, `buildUpdateXml()`, `getRolesFromEditor()`, `xmlEscape()`, `xmlCDataSafe()`, `getEffectiveCategory()`
- Tests live in `tests/unit/modifier.test.js`

**D-04:** FR-04 is **deferred to Phase 3**. The `Associated_Roles` MIME field is the sufficient role record for Phase 2. No description field modification is needed in this phase.

**D-05:** `RoleAwareness.db` already exists on client machines. Phase 2 just documents it — path, schema dependency, and fallback behavior (`|False` when DB missing).

**D-06:** Integration tests cover **API round-trip only**: build updated fixlet XML → PUT to BigFix API → verify 200/201 response. Do **not** test live DB evaluation on clients.

**D-07:** Move roles and categories into a clearly marked **inline JSON config block at the top of the `.ojo` JS**, structured as a JSON string constant (e.g., `var PORTAL_CONFIG = { roles: [...], categories: [...] };`). Admins edit this one block only.

**D-08:** Both roles **and** categories go into the same config block.

### Claude's Discretion

- JSON config block naming and exact structure (e.g., `PORTAL_CONFIG` vs `DERESO_CONFIG`) — pick the clearest name
- Whether to add a comment header above the config block explaining how to update it
- Unit test file structure (mocha, jest, or follow exact Phase 1 pattern)

### Deferred Ideas (OUT OF SCOPE)

- **FR-04 — Description/DefaultActionScript update (→ Phase 3):** Add a role-context block to `DefaultActionScript` and a DIV at the top of fixlet descriptions showing session relevance.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FR-02 | Role-Based Fixlet Association — define roles, associate with fixlets, persist as MIME field | `Associated_Roles` MIME field pattern already in modifier.ojo; `getRolesFromEditor()` collects roles; `buildUpdateXml()` writes them |
| FR-03 | Role-Based Relevance Modification — generate syntactically correct role-check relevance | `buildRoleRelevance()` generates full RoleAwareness.db query; relevance injection pattern is `selectNodes("//Relevance[contains(., 'RoleAwareness.db')]")` + remove + insertBefore Category |
| FR-04 | Role-Based Description Update (DEFERRED to Phase 3) | Acknowledged — out of scope for Phase 2 |

</phase_requirements>

---

## Summary

Phase 2 is a bug-fix-and-test phase for the existing `fixlet_modifier.ojo` BigFix dashboard. The file is already functional — it loads fixlets, manages a role editor UI, and saves role associations via the BigFix REST API. The goals are: (1) fix two concrete variable-shadowing bugs in `buildUpdateXml()`, (2) remove dead code and diagnostic alerts, (3) externalize the hardcoded role and category lists into a top-of-file config block for admin maintainability, (4) write unit tests for the 6 pure JS functions, (5) write integration tests following the copier pattern, and (6) document RoleAwareness.db.

The test infrastructure is completely established by Phase 1: Node.js built-in `assert` module only, no external packages, isolation-by-copy-paste pattern for unit tests, env-var-gated async tests for integration. This phase follows that pattern exactly — no new test framework decisions are needed.

The most important correctness insight is that the `cleanedXml` bug in `buildUpdateXml()` is real and subtle: the first `cleanedXml` strips `Associated_Role-` prefixed MIME fields and loads them into `origDoc`; the second declaration (line ~600) re-strips from the original `sourceXml` and is then discarded without ever being reloaded into `origDoc`. The second block also contains placeholder comments that were never completed. The correct fix is: (a) keep the first `cleanedXml` and `origDoc.loadXML(cleanedXml)` at the top, (b) delete the second `var cleanedXml = String(sourceXml).replace(...)` block entirely, and (c) keep the MIME-field writing logic that follows it (roles collection and DOM insertion) but anchored to the already-clean `origDoc`.

**Primary recommendation:** Fix bugs first (in order: duplicate `fixletNode`, stale `cleanedXml` block, dead functions, debug alerts), then add the config block, then write tests against the fixed file.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Role association UI (editor table, dropdowns) | Browser / Client (BigFix IE9 dashboard) | — | All UI runs inside BigFix console IE9 webview; no server-side rendering |
| Role persistence (MIME field write) | BigFix API / Backend | Browser initiates PUT | `buildUpdateXml()` constructs XML; `API.Put()` sends to BigFix REST; BigFix server persists |
| Role relevance generation | Browser / Client (pure JS) | — | `buildRoleRelevance()` is a string-builder; executes client-side before the PUT |
| RoleAwareness.db query evaluation | BigFix Client (endpoint) | — | Relevance embedded in fixlet; evaluated on each managed endpoint at policy application time |
| Fixlet list loading | Browser / Client + BigFix API | — | `EvaluateRelevance()` for list data; `API.Get()` for individual fixlet XML |
| Config block (roles + categories) | Browser / Client (inline JS constant) | — | Lives at top of .ojo JS; parsed at dashboard load time |

---

## Standard Stack

### Core

No external packages. Phase 2 uses:

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Node.js built-in `assert` | Bundled with Node.js | Unit test assertions | Phase 1 established this pattern; zero install friction; works offline |
| Node.js built-in `https` | Bundled with Node.js | Integration test HTTP calls | Same as copier integration tests |
| Node.js built-in `fs`, `path` | Bundled with Node.js | Fixture loading in integration tests | Same as copier integration tests |
| `Msxml2.DOMDocument.6.0` (ActiveXObject) | BigFix console IE9 | XML parsing inside .ojo | Required by BigFix console environment; not testable in Node.js — use mock pattern |

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo and copier.test.js]

### No Packages to Install

Phase 2 installs zero npm packages. Test runner is `node tests/unit/modifier.test.js` and `node tests/integration/modifier.integration.test.js`, matching Phase 1.

---

## Package Legitimacy Audit

**No external packages are installed in Phase 2.** This section is not applicable.

Packages removed due to slopcheck: none
Packages flagged as suspicious: none

---

## Architecture Patterns

### System Architecture Diagram

```
Admin Browser (BigFix Console IE9)
  |
  |--- EvaluateRelevance("names of bes custom sites") --> BigFix Server
  |                                                          |
  |<-- site name list ----------------------------------------
  |
  |--- EvaluateRelevance(loadAllFixlets rel) --> BigFix Server
  |                                                  |
  |<-- fixlet list with Associated_Roles MIME data ---
  |
  |--- API.Get("fixlet/custom/<site>/<id>") --> BigFix REST API
  |                                                 |
  |<-- full fixlet XML (sourceXml) -----------------
  |
  [User edits roles in UI table]
  |
  |--- buildRoleRelevance() --> generates Relevance string (pure JS)
  |--- buildUpdateXml()     --> strips old MIME fields, injects new relevance + MIME, returns XML
  |
  |--- API.Put("fixlet/custom/<site>/<id>", updatedXml) --> BigFix REST API
                                                               |
                                                           BigFix persists updated fixlet
                                                               |
                                               At endpoint evaluation time:
                                               Relevance → RoleAwareness.db SQLite query
                                               → true/false for this user
```

### Recommended Project Structure

```
Existing Dashboards/
  fixlet_modifier.ojo          # Fixed, cleaned, config-block added

tests/
  unit/
    modifier.test.js           # NEW: 6-function unit test file
  integration/
    modifier.integration.test.js  # NEW: PUT round-trip integration tests
  fixtures/
    phase-01/                  # Existing (used by copier tests)
    phase-02/                  # NEW: modifier-specific XML fixtures
      valid-fixlet-no-roles.ojo    # Fixlet with no Associated_Roles MIME field
      valid-fixlet-with-roles.ojo  # Fixlet with existing Associated_Roles MIME field
```

### Pattern 1: Isolation Unit Testing (copy-paste extraction)

**What:** Copy the pure JS function verbatim from the .ojo into the top of the test file. No import/require of the .ojo file.

**When to use:** Any function that runs in the IE9 BigFix console environment but can be exercised as pure string/logic in Node.js.

**Example (from copier.test.js — the established pattern):**
```javascript
// Source: tests/unit/copier.test.js lines 31-38
function xmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;")
    .replace(/'/g,"&apos;");
}
```

### Pattern 2: DOM Mock for IE9 ActiveXObject functions

**What:** Create a `makeXmlMock(tagMap)` helper that returns a minimal object satisfying the `.getElementsByTagName(tag)` → `[{text: value}]` interface used by `getNodeText()`.

**When to use:** Any function that calls `xml.getElementsByTagName()` or `xml.selectSingleNode()`.

**Example (from copier.test.js lines 165-172):**
```javascript
// Source: tests/unit/copier.test.js lines 165-172
function makeXmlMock(tagMap){
  return {
    getElementsByTagName: function(tag){
      var texts = tagMap[tag] || [];
      return texts.map(function(t){ return { text: t }; });
    }
  };
}
```

For `buildUpdateXml()`, the function uses `ActiveXObject("Msxml2.DOMDocument.6.0")` which cannot be mocked purely. See "Don't Hand-Roll" section — `buildUpdateXml()` must be tested via a simpler extracted helper, not directly.

### Pattern 3: DOM Table Mock for getRolesFromEditor() and buildRoleRelevance()

**What:** Both functions traverse `document.getElementById("roleFieldTable").rows[i].cells[1].getElementsByTagName("select")[0].value`. In the test file, create a `makeRoleTableMock(roleValues)` that returns a minimal table mock.

**When to use:** `getRolesFromEditor()` and `buildRoleRelevance()` tests.

**Example:**
```javascript
// Source: derived from modifier.ojo getRolesFromEditor() structure (lines 179-191)
function makeRoleTableMock(roleValues) {
  return {
    rows: roleValues.map(function(v) {
      return {
        cells: [
          null,
          {
            getElementsByTagName: function(tag) {
              if (tag === "select") return [{ value: v }];
              return [];
            }
          }
        ]
      };
    })
  };
}
```

### Pattern 4: Config Block Structure

**What:** A `var PORTAL_CONFIG = {...}` constant at the top of the .ojo JS, before all function definitions. Admins edit only this block.

**When to use:** Phase 2 moves hardcoded role and category lists here.

**Recommended structure:**
```javascript
// ==========================================================================
// PORTAL CONFIGURATION — Edit this block to update roles and categories.
// Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  roles: [
    "General Access",
    "IT Developer",
    "IT Support",
    "DB Developer",
    "DB Administrator",
    "Payments Processor",
    "Marketer"
  ],
  categories: [
    "Coding Tools",
    "Database Tools",
    "Drivers",
    "Graphics & Design",
    "Messengers",
    "Office Applications",
    "Office Tools",
    "Virtualization & Remote Access",
    "Web Browsers"
  ]
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```

This replaces:
- The hardcoded role string in `loadRoleValues()` (line 119)
- The hardcoded `<option>` values in the HTML `<select id="editCategory">` block (lines 762-771)

Both `loadRoleValues()` and the category dropdown HTML must be updated to read from `PORTAL_CONFIG` at runtime. For the category `<select>`, options should be built dynamically via `initDashboard()` → `loadCategoryOptions()`.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo]

### Pattern 5: Integration Test Structure (from copier.integration.test.js)

**What:** Env-var guard at top (skip with exit 0 if vars missing), `apiRequest()` helper mirroring `API.Put`, async tests via Promise chain, sync guard tests, summary footer.

**For modifier:** The primary integration test is a PUT round-trip:
1. `API.Get` fixlet XML (or use a fixture)
2. Simulate `buildUpdateXml()` output (or extract the logic)
3. `API.Put` the updated XML
4. Assert HTTP 200 or 201

[VERIFIED: direct codebase inspection of copier.integration.test.js]

### Anti-Patterns to Avoid

- **Testing `buildUpdateXml()` directly in Node.js:** This function instantiates `ActiveXObject("Msxml2.DOMDocument.6.0")` — it cannot run in Node.js. Do not attempt to call it in unit tests. Instead: extract and test the individual helpers it calls (`xmlEscape`, `xmlCDataSafe`, `buildRoleRelevance`, `getRolesFromEditor`, `getEffectiveCategory`).
- **Calling `document.getElementById()` in unit tests:** The UI-dependent functions (`getRolesFromEditor`, `getEffectiveCategory`, `buildRoleRelevance`) call `document.getElementById()`. Supply DOM-table mocks rather than trying to load a real DOM.
- **Using the second `cleanedXml` block to re-clean:** After the bug fix, there is only one `cleanedXml` value (at the top of `buildUpdateXml()`), which is loaded into `origDoc`. The subsequent MIME-field writing operates on `origDoc` only.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Test assertions | Custom equality checker | Node.js `assert.strictEqual` / `assert.deepStrictEqual` | Already established in Phase 1; zero dependency |
| HTTP client for integration tests | Custom XMLHttpRequest | Node.js `https` module | Same as copier integration tests; already working |
| ActiveXObject XML parsing in unit tests | Trying to polyfill MSXML in Node.js | DOM mock pattern (makeXmlMock) | MSXML is IE-only; mock is simpler and sufficient |
| BigFix Relevance syntax | Custom syntax | Copy the existing `buildRoleRelevance()` string verbatim | The existing relevance is correct — don't alter the SQL query or DB path |

**Key insight:** The modifier functions are self-contained string-builders. The testing challenge is entirely about DOM environment isolation — solved cleanly by the established mock pattern from Phase 1.

---

## Common Pitfalls

### Pitfall 1: The `cleanedXml` Double-Declaration Bug (line ~600)

**What goes wrong:** `buildUpdateXml()` declares `cleanedXml` twice. The first declaration (line ~547) strips `Associated_Role-` prefixed MIME fields and loads the result into `origDoc`. The second declaration (line ~600) re-strips from `sourceXml` using a slightly different regex (`Associated_Role` without the hyphen). But `origDoc` was already loaded from the first `cleanedXml` — the second `cleanedXml` is a local variable that shadows the first and is then discarded. The net effect is that the DOM continues to operate on `origDoc` loaded from the first clean pass, which is actually the intended behavior. However, the second block also contains the comment `// ... (load into origDoc, update title, category, relevance as before) ...` — meaning the original developer intended to redo those steps but never did. The correct fix is to delete the second `var cleanedXml` declaration and the placeholder comment, keeping the MIME-writing DOM operations that follow.

**Why it happens:** Copy-paste residue during a refactor of the MIME-field-removal strategy.

**How to avoid:** Only one `cleanedXml` / `origDoc.loadXML()` call should exist in `buildUpdateXml()`. After the fix, the function flow is:
1. Strip `Associated_Role-` patterns from `sourceXml` → `cleanedXml`
2. `origDoc.loadXML(cleanedXml)` — one load, at the top
3. Update title, category, relevance nodes on `origDoc`
4. Write new `Associated_Roles` MIME field on `origDoc`
5. Return `origDoc.documentElement.xml`

**Warning signs:** Any second `var cleanedXml` or second `origDoc.loadXML()` call in the function body.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 547 and 600]

### Pitfall 2: The `fixletNode` Duplicate Declaration (lines 567 and 570)

**What goes wrong:** `var fixletNode` is declared twice in strict succession inside `buildUpdateXml()`:
```javascript
var fixletNode = origDoc.getElementsByTagName("Fixlet")[0];    // line 567
if(!fixletNode){ alert("Could not find Fixlet node."); return ""; }

var fixletNode = origDoc.getElementsByTagName("Fixlet")[0];    // line 570 — duplicate
if(!fixletNode){ alert("Could not find Fixlet node."); return ""; }
```
Both lines call `getElementsByTagName("Fixlet")[0]` — the second is a pure duplicate with no effect. In strict mode JS this would throw a `SyntaxError: Identifier 'fixletNode' has already been declared` in modern engines (though not IE9's JScript, which silently ignores duplicate `var`).

**How to fix:** Delete lines 570-571 entirely. Keep lines 567-568.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 567-571]

### Pitfall 3: MIME Field Regex Pattern Mismatch

**What goes wrong:** The first `cleanedXml` strip (line 547) uses the regex `/<MIMEField>\s*<Name>\s*Associated_Role-[\s\S]*?<\/MIMEField>/gi` — note the hyphen after `Role`. The second strip (line 600) uses `/<MIMEField>\s*<Name>\s*Associated_Role[\s\S]*?<\/MIMEField>/gi` — no hyphen.

The intended MIME field name is `Associated_Roles` (underscore, no hyphen). The old format was `Associated-Role-N` (with hyphens). The regex difference means:
- First regex strips old `Associated_Role-*` MIME fields (the old multi-field format)
- Second regex would strip any `Associated_Role*` MIME fields (including the new `Associated_Roles`)

After the fix (deleting the second `cleanedXml`), the only strip is the first one, which targets the old format only. This is correct: the new `Associated_Roles` field is written fresh each time by the DOM insertion code.

**How to avoid:** After the fix, verify that `cleanedXml` regex targets only `Associated_Role-` (with hyphen, old format). The new `Associated_Roles` field is not stripped because it doesn't exist until `buildUpdateXml()` writes it.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 547-548 and 600-601]

### Pitfall 4: `getEffectiveCategory()` Calls `document.getElementById()`

**What goes wrong:** `getEffectiveCategory()` calls `document.getElementById("editCategory")` and `document.getElementById("editCategoryOther")`. In unit tests there is no DOM. Testing requires a DOM mock.

**How to avoid:** Extract and test `getEffectiveCategory()` by supplying a mock `document` object in the test file:
```javascript
// In test file — mock document for getEffectiveCategory tests
var mockDocument = {
  getElementById: function(id) { return mockElements[id] || null; }
};
var mockElements = {};

function getEffectiveCategoryTestable(catSel, catOtherVal) {
  // parameterized version for unit tests — avoids DOM entirely
  if (catSel === "__other__") { return String(catOtherVal || ""); }
  return catSel;
}
```
Alternatively: create a local test-only version of `getEffectiveCategory` that accepts parameters instead of reading from DOM. This is cleaner than mocking `document`.

**Warning signs:** Any unit test that directly calls the DOM-bound version of `getEffectiveCategory` without a mock will throw `ReferenceError: document is not defined`.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 168-174]

### Pitfall 5: `buildRoleRelevance()` Is DOM-Dependent

**What goes wrong:** `buildRoleRelevance()` calls `document.getElementById("roleFieldTable")` and traverses `t.rows[i].cells[1].getElementsByTagName("select")[0].value`. Same problem as `getEffectiveCategory`.

**How to avoid:** Use `makeRoleTableMock(roleValues)` as described in Architecture Patterns. Extract the pure logic: given an array of role strings, produce the relevance output. The test version:
```javascript
// Parameterized version for unit tests
function buildRoleRelevanceFromArray(roles) {
  if (roles.length === 0) { return ""; }
  var roleSet = '"' + roles.join('";"') + '"';
  return '(number of (elements of intersection of (set of (' + roleSet + '); it) of ...) > 0)|False';
}
```
Or: supply a table mock and call the original function with the mock injected via `document`.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 484-509]

### Pitfall 6: `getRolesFromEditor()` Returns Empty Array When Table Is Empty

**What goes wrong:** If the admin saves with no roles assigned, `getRolesFromEditor()` returns `[]`. `buildUpdateXml()` then writes `<Value></Value>` to the MIME field (empty string from `roles.join("|")`). This is correct behavior but should be tested explicitly.

**How to avoid:** Include a test case: empty table → `getRolesFromEditor()` returns `[]` → `roles.join("|")` === `""`.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 179-191 and 606-616]

### Pitfall 7: `_previewXml()` and `_renumberRoleRows()` Are Dead Code

**What goes wrong:** Both functions are prefixed with `_` and never called. `previewXml()` (without underscore) is the active function. `renumberRoleRows()` (without underscore) is the active function. The dead versions can be deleted safely — but deleting the wrong one (the active version) would break the UI.

**How to avoid:** Confirm which version is called before deleting:
- `onclick="previewXml()"` in HTML (line ~793) → keep `previewXml()`, delete `_previewXml()`
- `removeRoleRow()` calls `renumberRoleRows()` (line 466) → keep `renumberRoleRows()`, delete `_renumberRoleRows()`

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 462-481 and 631-651]

### Pitfall 8: `testREST()` Contains a Live `alert()` Call

**What goes wrong:** `testREST()` at line 90-92 calls `alert("API OK")` and `alert("FAIL: " + ...)`. Per D-01, diagnostic alerts are stripped. However `testREST()` is a utility function (triggered by "Test REST" button) — the alert here is the intended UX, not a diagnostic. Decision required: keep `testREST()` as-is, or replace alert with `setStatus()`.

**Recommendation (Claude's Discretion):** Replace `alert("API OK")` with `setStatus("API OK")` and `alert("FAIL: ...")` with `setStatus("FAIL: ...")` in `testREST()`. The `saveFixlet()` function's `alert("Saved successfully...")` is also a UX-intended alert and should be kept. The commented-out `//alert(...)` diagnostic lines in `buildUpdateXml()` should be stripped entirely.

[VERIFIED: direct codebase inspection of fixlet_modifier.ojo lines 88-93 and 550-565 and 621-624]

---

## Code Examples

### The `buildRoleRelevance()` Output (verified)

For roles `["IT Developer", "DB Administrator"]`, `buildRoleRelevance()` produces:

```
(number of (elements of intersection of (set of ("IT Developer";"DB Administrator"); it) of (set of((rows of statement ("select r.role from roles r join map m on m.role = r.id join users u on u.id = m.user where (unixepoch() - unixepoch(u.LastSeen)) / (60 * 60 * 24) < 30  and userid ='" & name of logged on user & "'") of it) of  (sqlite database of file "RoleAwareness.db"  of folder ( concatenation (if (windows of   operating system) then "\" else "/") of (item 0 of it;   item 1 of it; item 2 of it) of ( pathname of parent   folder of parent folder of client folder of site "actionsite",   "EC", "SoftwarePortal" ))) as string))) > 0)|False
```

Key elements [VERIFIED: modifier.ojo lines 484-509]:
- `set of ("role1";"role2")` — semicolon-separated quoted role names
- SQL query: join `roles`, `map`, `users` tables; filter by `LastSeen` within 30 days; filter by `userid = name of logged on user`
- DB path: `sqlite database of file "RoleAwareness.db" of folder (...)` using `client folder of site "actionsite"` parent navigation
- Fallback: `|False` — if DB file is missing, evaluation returns False

For zero roles, returns `""` — which `buildUpdateXml()` treats as "no role relevance to inject".

### The `PORTAL_CONFIG` Block (to be inserted)

```javascript
// Source: decision D-07/D-08 — externalize roles and categories
// ==========================================================================
// PORTAL CONFIGURATION
// Edit the lists below to add or remove roles and categories.
// Do not modify any function definitions below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  roles: [
    "General Access",
    "IT Developer",
    "IT Support",
    "DB Developer",
    "DB Administrator",
    "Payments Processor",
    "Marketer"
  ],
  categories: [
    "Coding Tools",
    "Database Tools",
    "Drivers",
    "Graphics & Design",
    "Messengers",
    "Office Applications",
    "Office Tools",
    "Virtualization & Remote Access",
    "Web Browsers"
  ]
};
// ==========================================================================
```

`loadRoleValues()` changes from (current):
```javascript
var rel = '(it) of ("General Access";"IT Developer";...)';
var data = EvaluateRelevance(rel);
```

To:
```javascript
roleValues = PORTAL_CONFIG.roles.slice();
```
(No EvaluateRelevance needed — roles come from the config constant, not from a BigFix relevance query. The old implementation ran a relevance that returned its own literal arguments, which was unnecessary overhead.)

The category `<select>` HTML is replaced with an empty `<select id="editCategory">` that is populated dynamically in a new `loadCategoryOptions()` function called from `initDashboard()`.

[VERIFIED: direct codebase inspection of modifier.ojo lines 119-125 and 761-771]

### Fixture Structure for Phase 2

Phase 2 needs a fixture representing a fixlet that already has `Associated_Roles` set (to test that `buildUpdateXml()` correctly replaces the old MIME field). Based on `valid-minimal.ojo` pattern:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES>
  <Fixlet>
    <Title>Sample Role-Modified Fixlet</Title>
    <Relevance>true</Relevance>
    <Category>Office Tools</Category>
    <Domain>BESC</Domain>
    <MIMEField>
      <Name>Associated_Roles</Name>
      <Value>IT Developer|DB Administrator</Value>
    </MIMEField>
    <DefaultAction ID="Action1">
      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">// placeholder</ActionScript>
    </DefaultAction>
  </Fixlet>
</BES>
```

And one with existing role-awareness relevance (to test the removal step):

```xml
<Relevance>(number of (...RoleAwareness.db...) > 0)|False</Relevance>
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Associated-Role-N` multi-MIME fields (hyphen, numbered) | Single `Associated_Roles` field (pipe-separated) | Already migrated in modifier.ojo | First `cleanedXml` regex strips old hyphen format; new code writes single field |
| Hardcoded roles in relevance expression | Roles in `PORTAL_CONFIG.roles[]` | Phase 2 adds this | Admins can update role list without modifying JS logic |
| Hardcoded category `<option>` elements in HTML | Category options built from `PORTAL_CONFIG.categories[]` | Phase 2 adds this | Keeps config co-located with role list |

**Deprecated/outdated:**
- `_previewXml()`: Replaced by `previewXml()` (the non-prefixed version). Delete.
- `_renumberRoleRows()`: Labels rows as "Associated-Role-N" (old format). Replace by `renumberRoleRows()` (labels as "Role N"). Delete.
- `addCategoryRow()`: Appears to be an older variant of `addRoleRow()` that uses a different label format ("Associated-Role-N"). This function is present but not called from the active UI (which uses `addRoleRow()`). Dead code — delete it.

[VERIFIED: direct codebase inspection of modifier.ojo lines 412-427 (addCategoryRow), 429-446 (addRoleRow)]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `addCategoryRow()` is dead code (not called from any onclick or function) | State of the Art | If called, removing it breaks the UI. Verify with grep before deletion. |
| A2 | `loadRoleValues()` using `EvaluateRelevance` is safe to replace with direct config read | Code Examples | If BigFix relevance returns different values than the hardcoded string, behavior changes. But the existing relevance is `(it) of ("literal";"literal"...)` — it returns its own arguments — so direct read is equivalent. |
| A3 | Integration test should use `API.Put` (not `API.Post`) for modifier | Integration Pattern | Modifier updates existing fixlets via PUT; if the API uses different verbs, the test would fail. The `saveFixlet()` function confirms PUT. [VERIFIED from modifier.ojo line 675] |

---

## Open Questions

1. **`testREST()` alert calls — keep or replace?**
   - What we know: D-01 says strip diagnostic alerts. `testREST()` alerts are functional UX (test button feedback).
   - What's unclear: Whether "strip alert() calls" includes button-triggered test feedback.
   - Recommendation: Replace with `setStatus()` calls — consistent with the rest of the dashboard UX. No functional difference for admins.

2. **`saveFixlet()` success alert — keep?**
   - What we know: `alert("Saved successfully.\nFixlet ID: ...")` at line 688 is user-facing UX, not diagnostic.
   - Recommendation: Keep it. It is not a debugging artifact; it confirms a write operation to the admin.

3. **Category options: build dynamically vs. render in HTML with JS update?**
   - Recommendation: Build dynamically in `loadCategoryOptions()` called from `initDashboard()`. Simpler than maintaining two sources of truth. The `__other__` option should always be appended last.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | Unit + integration tests | Assumed ✓ (used in Phase 1) | — | None — required for test execution |
| BigFix REST API instance | Integration tests | Conditional | — | Tests skip gracefully when BIGFIX_URL not set (same as copier pattern) |
| RoleAwareness.db on endpoints | Relevance evaluation | Exists per D-05 | — | `|False` fallback in generated relevance |

Step 2.6: No new external tools required. Phase 2 uses the same environment as Phase 1.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Node.js built-in `assert` (no external framework) |
| Config file | None — tests are standalone scripts |
| Quick run command | `node tests/unit/modifier.test.js` |
| Full suite command | `node tests/unit/modifier.test.js && node tests/unit/copier.test.js` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FR-02 | `getRolesFromEditor()` collects non-empty, deduplicated role values | unit | `node tests/unit/modifier.test.js` | ❌ Wave 0 |
| FR-02 | `buildUpdateXml()` writes `Associated_Roles` MIME field with pipe-joined roles | integration (via PUT round-trip) | `node tests/integration/modifier.integration.test.js` | ❌ Wave 0 |
| FR-03 | `buildRoleRelevance()` produces syntactically correct relevance for 1, 2, N roles | unit | `node tests/unit/modifier.test.js` | ❌ Wave 0 |
| FR-03 | `buildRoleRelevance()` returns `""` for zero roles | unit | `node tests/unit/modifier.test.js` | ❌ Wave 0 |
| FR-03 | Generated relevance contains `|False` fallback | unit | `node tests/unit/modifier.test.js` | ❌ Wave 0 |
| FR-03 | Relevance contains correct SQL and DB path | unit | `node tests/unit/modifier.test.js` | ❌ Wave 0 |
| NFR-05 | `PORTAL_CONFIG` block exists and is parseable (roles + categories arrays non-empty) | unit | `node tests/unit/modifier.test.js` | ❌ Wave 0 |
| D-01 | No duplicate `var fixletNode` (static analysis) | manual | Review modifier.ojo | — |

### Sampling Rate

- **Per task commit:** `node tests/unit/modifier.test.js`
- **Per wave merge:** `node tests/unit/modifier.test.js && node tests/unit/copier.test.js`
- **Phase gate:** Both unit suites green; integration test skips gracefully without live BigFix

### Wave 0 Gaps

- [ ] `tests/unit/modifier.test.js` — covers FR-02, FR-03, NFR-05 function-level behaviors
- [ ] `tests/integration/modifier.integration.test.js` — covers FR-02 PUT round-trip
- [ ] `tests/fixtures/phase-02/valid-fixlet-no-roles.ojo` — fixture for integration test
- [ ] `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` — fixture with existing roles/relevance

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | BigFix handles all auth via console session |
| V3 Session Management | No | BigFix manages sessions |
| V4 Access Control | Yes — indirectly | Generated relevance enforces role-based access; fallback to `\|False` prevents unintended access |
| V5 Input Validation | Yes | Role values come from a closed dropdown (not free-form input); category uses `__other__` free-form but is stored as display text only, not executed |
| V6 Cryptography | No | No crypto in this phase |

### Known Threat Patterns for BigFix Dashboard JS

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| XSS via fixlet title in DOM innerHTML | Tampering | `xmlEscape()` applied to all string values before XML construction; category `__other__` value goes through `xmlEscape()` in `buildUpdateXml()` via `catNodes[0].text = getEffectiveCategory()` (MSXML text property auto-escapes) |
| SQL injection in role names | Tampering | Role names come from closed dropdown (PORTAL_CONFIG.roles array); free-form entry not possible |
| Relevance injection via role name | Tampering | Role names are embedded as quoted strings inside the Relevance expression (`'"' + roles.join('";"') + '"'`); a role name containing `"` would break the syntax. Mitigated by: roles come from admin-controlled config, not end-user input |
| Stale MIME field data after failed PUT | Tampering/Denial | `saveFixlet()` only updates in-memory `allItems` cache on success (status 200/201); on failure, local cache remains unchanged |
| Fixlet write to wrong site | Tampering | PUT path constructed from `currentItem.siteName` loaded from BigFix API; admin cannot spoof a different site without modifying the loaded data |

---

## Sources

### Primary (HIGH confidence)
- `Existing Dashboards/fixlet_modifier.ojo` — complete dashboard source, inspected directly. All function signatures, line numbers, and bug locations verified.
- `tests/unit/copier.test.js` — Phase 1 unit test pattern (Node.js assert, copy-paste extraction, mock pattern), inspected directly.
- `tests/integration/copier.integration.test.js` — Phase 1 integration test pattern, inspected directly.
- `tests/fixtures/phase-01/*.ojo` — fixture format and structure, inspected directly.
- `.planning/phases/02-modifier/02-CONTEXT.md` — all locked decisions from discuss-phase.
- `.planning/config.json` — workflow settings: no nyquist_validation key (treated as enabled), security_gate: true.

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` — FR-02, FR-03, FR-04, NFR-05 requirements used to map test coverage.
- `.planning/phases/01-copier/01-02-PLAN.md` — detailed spec of Phase 1 test structure used to infer Phase 2 equivalents.

### Tertiary (LOW confidence)
- None — all claims are verified from direct codebase inspection.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — confirmed Node.js built-ins only, zero external packages, same as Phase 1
- Architecture: HIGH — all patterns verified directly from modifier.ojo and copier.test.js source
- Pitfalls: HIGH — bugs verified at exact line numbers in modifier.ojo
- Test patterns: HIGH — exact pattern files read and analyzed

**Research date:** 2026-06-14
**Valid until:** This research is tied to specific line numbers in modifier.ojo. Valid until any significant restructuring of modifier.ojo. Stable for the duration of Phase 2 execution.
