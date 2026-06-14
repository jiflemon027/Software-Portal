# Phase 2: Modifier (Role-Based Categorization) — Pattern Map

**Mapped:** 2026-06-14
**Files analyzed:** 5 (1 modified, 4 new)
**Analogs found:** 5 / 5

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Existing Dashboards/fixlet_modifier.ojo` | utility (BigFix dashboard) | request-response (BigFix REST PUT) | `Existing Dashboards/fixlet_copier.ojo` | exact |
| `tests/unit/modifier.test.js` | test | transform (pure function assertions) | `tests/unit/copier.test.js` | exact |
| `tests/integration/modifier.integration.test.js` | test | request-response (BigFix REST API) | `tests/integration/copier.integration.test.js` | exact |
| `tests/fixtures/phase-02/valid-fixlet-no-roles.ojo` | config (test fixture) | — | `tests/fixtures/phase-01/valid-minimal.ojo` | role-match |
| `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` | config (test fixture) | — | `tests/fixtures/phase-01/valid-minimal.ojo` | role-match |

---

## Pattern Assignments

### `Existing Dashboards/fixlet_modifier.ojo` (utility, request-response)

**Analog:** `Existing Dashboards/fixlet_copier.ojo`

This file is being fixed and extended, not rewritten. The patterns below describe what to copy into the file for the new `PORTAL_CONFIG` block and the `loadCategoryOptions()` function, and what specific bugs to fix.

**Config block pattern — insert at top of `<script>` block, before all function definitions:**

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

**`loadRoleValues()` fix — current (lines 118–125) uses `EvaluateRelevance`; replace body with config read:**

Current (modifier.ojo lines 118–125):
```javascript
function loadRoleValues(){
  var rel  = '(it) of ("General Access";"IT Developer";...)';
  var data = EvaluateRelevance(rel);
  roleValues = [];
  for(var i = 0; i < data.length; i++){
    roleValues.push(String(data[i]));
  }
}
```

Replacement pattern (reads from config, no EvaluateRelevance call needed):
```javascript
function loadRoleValues(){
  roleValues = PORTAL_CONFIG.roles.slice();
}
```

**`loadCategoryOptions()` — new function, called from `initDashboard()`; builds `<select>` options dynamically:**

```javascript
function loadCategoryOptions(){
  var sel = document.getElementById("editCategory");
  if(!sel){ return; }
  sel.innerHTML = "";
  var cats = PORTAL_CONFIG.categories;
  for(var i = 0; i < cats.length; i++){
    var opt = document.createElement("option");
    opt.value = cats[i];
    opt.text  = cats[i];
    sel.appendChild(opt);
  }
  var other = document.createElement("option");
  other.value = "__other__";
  other.text  = "Other (specify below)";
  sel.appendChild(other);
}
```

**Bug fix 1 — duplicate `var fixletNode` (modifier.ojo lines 567–571); delete lines 570–571:**

Current (lines 567–571):
```javascript
var fixletNode = origDoc.getElementsByTagName("Fixlet")[0];    // line 567 — KEEP
if(!fixletNode){ alert("Could not find Fixlet node."); return ""; }

var fixletNode = origDoc.getElementsByTagName("Fixlet")[0];    // line 570 — DELETE
if(!fixletNode){ alert("Could not find Fixlet node."); return ""; }
```

After fix: only lines 567–568 remain.

**Bug fix 2 — stale `cleanedXml` redeclaration (modifier.ojo lines 599–603); delete this block:**

Current (lines 599–603):
```javascript
var cleanedXml = String(sourceXml).replace(
  /<MIMEField>\s*<Name>\s*Associated_Role[\s\S]*?<\/MIMEField>/gi, "");

// ... (load into origDoc, update title, category, relevance as before) ...
```

Delete these 4 lines entirely. The valid `cleanedXml` is already established at lines 547–548. The MIME-writing DOM operations at lines 605–616 follow directly after without re-loading.

**Dead code removal — delete these function bodies in their entirety:**
- `_previewXml()` (lines 640–651) — superseded by `previewXml()` (line 631)
- `_renumberRoleRows()` — superseded by `renumberRoleRows()` (the unhyphenated version)
- `addCategoryRow()` (lines 412–427) — not called from any onclick or active code path

**Commented alert removal — strip lines matching:**
```
//alert(...)
```
in `buildUpdateXml()` (lines 550–552, 562–565, 621–624, 626–627).

**UX alerts to keep (not diagnostic):**
- `alert("Saved successfully...")` in `saveFixlet()` — keep, it is user confirmation
- `alert("Select a source Fixlet first.")` in `previewXml()` — keep

**`testREST()` alert replacement — replace `alert(...)` calls with `setStatus(...)`:**

Current (lines 88–93):
```javascript
function testREST(){
  API.Get("sites", function(ok, body, status){
    if(ok){ alert("API OK"); }
    else  { alert("FAIL: " + status); }
  });
}
```

Pattern (from `setStatus` usage throughout the file):
```javascript
function testREST(){
  API.Get("sites", function(ok, body, status){
    if(ok){ setStatus("API OK"); }
    else  { setStatus("FAIL: " + status); }
  });
}
```

---

### `tests/unit/modifier.test.js` (test, transform)

**Analog:** `tests/unit/copier.test.js`

Copy the entire file structure from `tests/unit/copier.test.js`. The modifier test file follows the identical shape.

**File header pattern** (copier.test.js lines 1–24):
```javascript
/**
 * modifier.test.js
 *
 * Unit tests for the 6 pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_modifier.ojo
 *
 * Functions covered:
 *   1. xmlEscape(s)
 *   2. xmlCDataSafe(s)
 *   3. buildRoleRelevance(roles)         -- parameterized version (array input)
 *   4. getRolesFromEditor(tableEl)       -- parameterized version (table element input)
 *   5. getEffectiveCategory(selVal, otherVal) -- parameterized version
 *   6. PORTAL_CONFIG validation          -- structural assertion on config block
 *
 * Running: node tests/unit/modifier.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 */

"use strict";

var assert = require("assert");
```

**Section 1 — extracted function implementations pattern** (copier.test.js lines 27–149):

Copy verbatim from modifier.ojo. For DOM-dependent functions, use parameterized test variants instead of calling the DOM-bound original:

```javascript
// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from fixlet_modifier.ojo)
// ---------------------------------------------------------------------------

// Lines 518-525: XML entity escaping
function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// Line 529: CDATA sequence escaping
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }
```

For `buildRoleRelevance()` — parameterized version avoids the DOM dependency:
```javascript
// Parameterized test version of buildRoleRelevance() from modifier.ojo lines 484-509.
// Accepts a roles array instead of reading from the DOM table.
function buildRoleRelevanceFromArray(roles){
  if(roles.length === 0){ return ""; }
  var roleSet = '"' + roles.join('";"') + '"';
  return '(number of (elements of intersection of (set of (' + roleSet + '); it) of' +
    ' (set of((rows of statement' +
    ' ("select r.role from roles r join map m on m.role = r.id join users u on u.id = m.user' +
    ' where (unixepoch() - unixepoch(u.LastSeen)) / (60 * 60 * 24) < 30 ' +
    ' and userid =\'" & name of logged on user & "\'") of it) of ' +
    ' (sqlite database of file "RoleAwareness.db" ' +
    ' of folder ( concatenation (if (windows of ' +
    '  operating system) then "\\" else "/") of (item 0 of it; ' +
    '  item 1 of it; item 2 of it) of ( pathname of parent ' +
    '  folder of parent folder of client folder of site "actionsite", ' +
    '  "EC", "SoftwarePortal" ))) as string))) > 0)|False';
}
```

For `getEffectiveCategory()` — parameterized version:
```javascript
// Parameterized test version of getEffectiveCategory() from modifier.ojo lines 168-174.
// Accepts selection value and other value directly instead of reading from DOM.
function getEffectiveCategoryFromParams(selVal, otherVal){
  if(selVal === "__other__"){ return String(otherVal || ""); }
  return selVal;
}
```

For `getRolesFromEditor()` — use makeRoleTableMock + call original signature:
```javascript
// Parameterized version: accepts a roles array, mirrors getRolesFromEditor() logic
// from modifier.ojo lines 179-191, without DOM dependency.
function getRolesFromArray(roleValues){
  var roles = [];
  for(var i = 0; i < roleValues.length; i++){
    var val = String(roleValues[i] || "");
    if(val !== "" && roles.indexOf(val) < 0){ roles.push(val); }
  }
  return roles;
}
```

**Section 2 — test infrastructure pattern** (copier.test.js lines 153–191):

```javascript
// ---------------------------------------------------------------------------
// 2. TEST INFRASTRUCTURE
// ---------------------------------------------------------------------------

/**
 * makeRoleTableMock(roleValues)
 * Returns a minimal mock of the IE DOM roleFieldTable element.
 * Used by tests that exercise the DOM-bound getRolesFromEditor() shape.
 */
function makeRoleTableMock(roleValues){
  return {
    rows: roleValues.map(function(v){
      return {
        cells: [
          null,
          {
            getElementsByTagName: function(tag){
              if(tag === "select"){ return [{ value: v }]; }
              return [];
            }
          }
        ]
      };
    })
  };
}

var passed   = 0;
var failures = 0;

function expect(label, fn){
  try{
    fn();
    passed++;
  } catch(e){
    failures++;
    console.error("  FAIL: " + label);
    console.error("        " + (e.message || String(e)));
  }
}

function section(name){
  console.log("\n--- Testing " + name + " ---");
}
```

**Section 4 — summary footer pattern** (copier.test.js lines 466–479):

```javascript
// ---------------------------------------------------------------------------
// 4. SUMMARY FOOTER
// ---------------------------------------------------------------------------

console.log("\n========================================");
console.log("Results: " + passed + " passed, " + failures + " failed");
console.log("========================================");

if(failures > 0){
  console.error("\nOne or more tests failed.");
  process.exit(1);
} else {
  console.log("\nAll tests passed.");
  process.exit(0);
}
```

**Test blocks to implement** (modelled on copier.test.js section 3 structure):

| Block | Function | Key cases |
|-------|----------|-----------|
| 3.1 | `xmlEscape` | `&`, `<`, `>`, `"`, `'`, all-five combined, empty, non-string coercion |
| 3.2 | `xmlCDataSafe` | `]]>` replaced, no occurrence unchanged, multiple occurrences, empty |
| 3.3 | `buildRoleRelevanceFromArray` | zero roles → `""`, one role contains role name, two roles semicolon-joined, result contains `\|False`, result contains SQL and DB path |
| 3.4 | `getRolesFromArray` | empty array → `[]`, one value → `["val"]`, duplicates deduplicated, empty string entries skipped |
| 3.5 | `getEffectiveCategoryFromParams` | normal value returned, `"__other__"` + other value returns other value, `"__other__"` with empty other returns `""` |
| 3.6 | `PORTAL_CONFIG` validation | `PORTAL_CONFIG.roles` is non-empty array, `PORTAL_CONFIG.categories` is non-empty array, both contain only strings |

`PORTAL_CONFIG` test block (structural — tests the config block is parseable and valid):
```javascript
section("PORTAL_CONFIG");

// PORTAL_CONFIG block — copy verbatim from modifier.ojo after the bug-fix pass
var PORTAL_CONFIG = {
  roles: [ /* copy from modifier.ojo */ ],
  categories: [ /* copy from modifier.ojo */ ]
};

expect("PORTAL_CONFIG.roles is a non-empty array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.roles));
  assert.ok(PORTAL_CONFIG.roles.length > 0);
});
expect("PORTAL_CONFIG.categories is a non-empty array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.categories));
  assert.ok(PORTAL_CONFIG.categories.length > 0);
});
expect("all roles are non-empty strings", function(){
  PORTAL_CONFIG.roles.forEach(function(r){
    assert.strictEqual(typeof r, "string");
    assert.ok(r.length > 0);
  });
});
expect("all categories are non-empty strings", function(){
  PORTAL_CONFIG.categories.forEach(function(c){
    assert.strictEqual(typeof c, "string");
    assert.ok(c.length > 0);
  });
});
```

---

### `tests/integration/modifier.integration.test.js` (test, request-response)

**Analog:** `tests/integration/copier.integration.test.js`

Copy the full structure from `copier.integration.test.js`. Key differences from copier: use PUT (not POST), load a phase-02 fixture, test role MIME field round-trip.

**Section 1 — environment guard pattern** (copier.integration.test.js lines 29–40):
```javascript
"use strict";

var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: BIGFIX_URL, BIGFIX_USER, and BIGFIX_TOKEN must all be set to run integration tests.");
  process.exit(0);
}
```

**Section 2 — `apiRequest()` helper pattern** (copier.integration.test.js lines 63–106):

Copy verbatim. For the modifier, the primary call uses `"PUT"` not `"POST"`. Update the conditional body-send block:
```javascript
// Modifier uses PUT for updates — change POST check to PUT:
if (method === "PUT" && bodyXml) {
  var bodyBuffer = Buffer.from(bodyXml, "utf8");
  requestOptions.headers["Content-Type"]   = "application/xml";
  requestOptions.headers["Content-Length"] = bodyBuffer.length;
}
// ...
if (method === "PUT" && bodyXml) {
  req.write(bodyBuffer);
}
```

**Section 4 — test runner pattern** (copier.integration.test.js lines 174–243):

Copy verbatim. Same `runTest`, `runAsyncTest`, `skipTest`, `assert`, `assertEqual`, `assertNotEmpty` helpers.

**Integration test scenarios for modifier:**

```javascript
/**
 * Test 1: API connectivity
 * Same as copier — GET /api/sites, assert 200.
 */

/**
 * Test 2: Load source fixlet (GET round-trip)
 * Requires TEST_SOURCE_SITE_TYPE, TEST_SOURCE_SITE_NAME, TEST_SOURCE_FIXLET_ID.
 * Asserts: 200, body contains <BES, body contains Associated_Roles or no MIME field.
 * Mirrors copier integration test 2 shape.
 */
function test2_loadSourceFixlet(done) {
  // ... same shape as copier test 2 ...
  // assert responseBody contains "<BES" and "<Title>"
}

/**
 * Test 3: PUT round-trip — update fixlet with roles (NFR-01 timing)
 * Uses fixture: tests/fixtures/phase-02/valid-fixlet-with-roles.ojo
 * Requires TEST_TARGET_SITE, TEST_TARGET_FIXLET_ID (fixlet must exist).
 * Asserts: HTTP 200 or 201, elapsed < 30000ms.
 * Mirrors copier integration test 3 shape — change POST to PUT, change fixture path.
 */
function test3_putFixletHappyPath(done) {
  var targetSite     = process.env.TEST_TARGET_SITE      || "Dereso Software Portal";
  var targetFixletId = process.env.TEST_TARGET_FIXLET_ID || "";

  if(!targetFixletId){
    var skipErr = new Error("TEST_TARGET_FIXLET_ID not set");
    skipErr.isSkip = true;
    return done(skipErr);
  }

  var fixturePath = path.join(__dirname, "..", "fixtures", "phase-02", "valid-fixlet-with-roles.ojo");
  var fixtureXml  = fs.readFileSync(fixturePath, "utf8");

  var relativePath = "fixlet/custom/" + encodeURIComponent(targetSite) + "/" +
                     encodeURIComponent(targetFixletId);
  var start = Date.now();

  apiRequest("PUT", relativePath, fixtureXml, function(errorMsg, statusCode, responseBody){
    var elapsed = Date.now() - start;
    try {
      if(errorMsg){ throw new Error("Network error: " + errorMsg); }
      assert(statusCode === 200 || statusCode === 201,
             "PUT status should be 200 or 201, got " + statusCode);
      assert(elapsed < 30000,
             "NFR-01: elapsed " + elapsed + "ms must be < 30000ms");
      console.log("        PUT round-trip OK (elapsed: " + elapsed + "ms)");
      done(null);
    } catch(ex){ done(ex); }
  });
}

/**
 * Tests 4, 5 (sync guard tests):
 * Same shape as copier tests 4, 5, 6 — extract and test pre-save guard logic.
 * For modifier: guard "no fixlet selected" and "no site loaded".
 */

/**
 * Test 6: API error handling
 * Same as copier test 7 — GET non-existent fixlet, assert non-200.
 */
```

**Section 6 — run-all pattern** (copier.integration.test.js lines 428–466):

```javascript
// Run synchronous guard tests first (no network required)
console.log("[ Synchronous guard tests — no BigFix connectivity required ]");
runTest("Test 4: ...", test4_guardNoFixlet);
runTest("Test 5: ...", test5_guardNoSite);
console.log("");

// Run async tests sequentially
console.log("[ Async API tests — require live BigFix instance ]");
runAsyncTest("Test 1: API connectivity", test1_apiConnectivity)
  .then(function(){ return runAsyncTest("Test 2: Load source fixlet", test2_loadSourceFixlet); })
  .then(function(){ return runAsyncTest("Test 3: PUT round-trip (happy path + NFR-01)", test3_putFixletHappyPath); })
  .then(function(){ return runAsyncTest("Test 6: API error handling", test6_apiErrorHandling); })
  .then(function(){
    console.log("\nResults: " + passed + " passed, " + failed + " failed, " + skipped + " skipped");
    process.exit(failed > 0 ? 1 : 0);
  });
```

---

### `tests/fixtures/phase-02/valid-fixlet-no-roles.ojo` (config/fixture)

**Analog:** `tests/fixtures/phase-01/valid-minimal.ojo`

Copy the structure from `valid-minimal.ojo` (lines 1–24). This fixture has no `Associated_Roles` MIME field and no role-awareness `<Relevance>` — used to test the "first association" path through `buildUpdateXml()`.

**Pattern** (from `tests/fixtures/phase-01/valid-minimal.ojo` lines 1–24):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>Sample Fixlet — No Roles</Title>
    <Description><![CDATA[Phase 2 test fixture: fixlet with no role associations.]]></Description>
    <Relevance>true</Relevance>
    <Category>Office Tools</Category>
    <Source>Internal</Source>
    <SourceID></SourceID>
    <SourceReleaseDate>2026-06-14</SourceReleaseDate>
    <SourceSeverity></SourceSeverity>
    <CVENames></CVENames>
    <SANSID></SANSID>
    <Domain>BESC</Domain>
    <DefaultAction ID="Action1">
      <Description>
        <PreLink>Click </PreLink>
        <Link>here</Link>
        <PostLink> to deploy this action.</PostLink>
      </Description>
      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">// placeholder action script</ActionScript>
    </DefaultAction>
  </Fixlet>
</BES>
```

---

### `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` (config/fixture)

**Analog:** `tests/fixtures/phase-01/valid-minimal.ojo`

Same structure as the no-roles fixture above, but includes:
1. An existing `Associated_Roles` MIME field (to test that `buildUpdateXml()` strips and replaces it)
2. An existing role-awareness `<Relevance>` node (to test the removal step in `buildUpdateXml()`)

**Pattern:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>Sample Fixlet — With Roles</Title>
    <Description><![CDATA[Phase 2 test fixture: fixlet with existing role associations.]]></Description>
    <Relevance>true</Relevance>
    <Relevance>(number of (elements of intersection of (set of ("IT Developer";"DB Administrator"); it) of (set of((rows of statement ("select r.role from roles r join map m on m.role = r.id join users u on u.id = m.user where (unixepoch() - unixepoch(u.LastSeen)) / (60 * 60 * 24) &lt; 30  and userid ='" &amp; name of logged on user &amp; "'") of it) of  (sqlite database of file "RoleAwareness.db"  of folder ( concatenation (if (windows of   operating system) then "\" else "/") of (item 0 of it;   item 1 of it; item 2 of it) of ( pathname of parent   folder of parent folder of client folder of site "actionsite",   "EC", "SoftwarePortal" ))) as string))) &gt; 0)|False</Relevance>
    <Category>Office Tools</Category>
    <Source>Internal</Source>
    <SourceID></SourceID>
    <SourceReleaseDate>2026-06-14</SourceReleaseDate>
    <SourceSeverity></SourceSeverity>
    <CVENames></CVENames>
    <SANSID></SANSID>
    <Domain>BESC</Domain>
    <MIMEField>
      <Name>Associated_Roles</Name>
      <Value>IT Developer|DB Administrator</Value>
    </MIMEField>
    <DefaultAction ID="Action1">
      <Description>
        <PreLink>Click </PreLink>
        <Link>here</Link>
        <PostLink> to deploy this action.</PostLink>
      </Description>
      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">// placeholder action script</ActionScript>
    </DefaultAction>
  </Fixlet>
</BES>
```

---

## Shared Patterns

### Test file structure (applies to both test files)

**Source:** `tests/unit/copier.test.js` (all sections)

All test files in this project use the same 4-section structure:

```
Section 1: Extracted function implementations (verbatim or parameterized copies)
Section 2: Test infrastructure (makeXmlMock / makeRoleTableMock, expect(), section())
Section 3: Test blocks (one per function)
Section 4: Summary footer (passed/failed count, process.exit)
```

No test framework (mocha/jest) — `node tests/unit/modifier.test.js` runs the file directly.

### Environment guard for integration tests

**Source:** `tests/integration/copier.integration.test.js` lines 29–40

Apply to `modifier.integration.test.js`. Guard exits with code 0 (not 1) when env vars are missing — this is a deliberate skip, not a failure.

### DOM isolation via parameterized functions

**Source:** `tests/unit/copier.test.js` (established pattern); extended by RESEARCH.md patterns 3 and 4

Apply to all modifier unit tests for DOM-dependent functions. Do not attempt to call `document.getElementById()` in Node.js tests. Use:
- `makeRoleTableMock(roleValues)` for `getRolesFromEditor()` / `buildRoleRelevance()` tests
- Parameterized function variants (`buildRoleRelevanceFromArray`, `getEffectiveCategoryFromParams`) for cleaner test code

### `apiRequest()` helper

**Source:** `tests/integration/copier.integration.test.js` lines 63–106

Copy verbatim into `modifier.integration.test.js`. Only change: update the method guard from `"POST"` to `"PUT"` in both the header-setting block and the `req.write()` block.

### `.ojo` file fixture structure

**Source:** `tests/fixtures/phase-01/valid-minimal.ojo` lines 1–24

All fixture files in this project are complete BES XML documents with `<?xml version="1.0"?>`, `<BES>` root with xsi namespace declaration, and a single `<Fixlet>` child containing all required fields through `<Domain>` before `<DefaultAction>`. MIME fields are inserted between `<Domain>` and `<DefaultAction>`.

---

## No Analog Found

All 5 files have close analogs. No entries in this section.

---

## Metadata

**Analog search scope:** `tests/unit/`, `tests/integration/`, `tests/fixtures/`, `Existing Dashboards/`
**Files scanned:** 6 (copier.test.js, copier.integration.test.js, fixlet_copier.ojo, fixlet_modifier.ojo, valid-minimal.ojo, valid-with-script.ojo)
**Pattern extraction date:** 2026-06-14
