# Phase 3: Dispatcher (Rapid Deployment) — Pattern Map

**Mapped:** 2026-06-14
**Files analyzed:** 7 (1 dashboard, 2 test files, 4 fixture files)
**Analogs found:** 7 / 7

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Existing Dashboards/fixlet_dispatcher.ojo` | dashboard (controller + view) | request-response (GET + POST) | `Existing Dashboards/fixlet_modifier.ojo` | exact (same scaffold, same CSS, same BigFix Wizard XML structure; add POST path) |
| `tests/unit/dispatcher.test.js` | test | batch | `tests/unit/modifier.test.js` | exact (same runner pattern, same section/expect infrastructure) |
| `tests/integration/dispatcher.integration.test.js` | test | request-response | `tests/integration/modifier.integration.test.js` | exact (same apiRequest helper, same env-guard, same runAsyncTest chain; swap PUT → POST) |
| `tests/fixtures/phase-03/valid-fixlet-with-actions.ojo` | fixture | — | `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` | role-match (same BES/Fixlet XML skeleton; add multiple Action elements) |
| `tests/fixtures/phase-03/valid-fixlet-single-action.ojo` | fixture | — | `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` | role-match (same skeleton; single DefaultAction only) |
| `tests/fixtures/phase-03/sample-action-response.xml` | fixture | — | `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` | partial-match (BESAPI response XML, not BES fixlet XML — no exact analog; use RESEARCH.md Pattern 3) |

---

## Pattern Assignments

### `Existing Dashboards/fixlet_dispatcher.ojo` (dashboard, request-response)

**Analog:** `Existing Dashboards/fixlet_modifier.ojo`

**BigFix Wizard XML scaffold** (modifier.ojo lines 1–11):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES>
  <Wizard>
    <Title>Dereso Fixlet Dispatcher</Title>
    <UIHooks LaunchType="Document" RequiresAuthoring="false" Menu="Dashboards"></UIHooks>
    <DefaultPage>main</DefaultPage>
    <Page Name="main" DocType="HTML">
      <Title>Dereso Fixlet Dispatcher</Title>
      <Head><![CDATA[
<meta http-equiv="X-UA-Compatible" content="IE=9">
```
Change `Title` and `<Title>` to `Dereso Fixlet Dispatcher`. All other XML wrapper elements are identical.

**CSS classes to copy verbatim** (modifier.ojo lines 13–34):
```css
body { font-family: Arial; font-size: 11px; background: #f3f3f3; margin: 0; padding: 0; }
.page { padding: 16px; }
h1 { color: #2a5d9f; font-size: 24px; margin: 0 0 18px 0; font-weight: bold; }
.panel { background: #ffffff; border: 1px solid #d7dbe0; margin-bottom: 14px; }
.panelBody { padding: 12px; }
.rowTable { width: 100%; border-collapse: collapse; }
.rowTable td { padding: 6px 8px; vertical-align: middle; border: none; }
.lbl { font-weight: bold; color: #333333; white-space: nowrap; }
input[type=text], textarea { font-family: Arial; font-size: 11px; border: 1px solid #c8c8c8; padding: 4px 6px; }
.txt { width: 260px; }
.txtWide { width: 340px; }
.btn { font-family: Arial; font-size: 11px; padding: 6px 14px; border: 1px solid #b3b3b3; background: #f7f7f7; cursor: pointer; }
.btnGreen { font-family: Arial; font-size: 11px; padding: 8px 18px; border: 1px solid #237241; background: #33a05a; color: #ffffff; font-weight: bold; cursor: pointer; }
.tableGrid { width: 100%; border-collapse: collapse; background: #ffffff; }
.tableGrid td, .tableGrid th { border: 1px solid #d7dbe0; padding: 6px 8px; vertical-align: middle; }
.tableGrid th { background: #f4f6f8; color: #2a5d9f; text-align: left; }
.small { color: #666666; font-size: 10px; }
.right { text-align: right; }
.divider { border-top: 1px solid #e1e1e1; margin: 10px 0; }
```
Copy verbatim. The dispatcher uses all of these unchanged.

**PORTAL_CONFIG block pattern** (modifier.ojo lines 37–64):
```javascript
// ==========================================================================
// PORTAL CONFIGURATION -- Edit this block to update roles and categories.
// Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  roles: [ ... ],
  categories: [ ... ]
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```
Replace content with:
```javascript
var PORTAL_CONFIG = {
  defaultExpirationDays: 7,
  targetGroups: [
    "All Workstations",
    "IT Department",
    "Finance Department",
    "All Servers"
  ]
};
```
Keep the exact delimiter comment format — `admins edit only this block`.

**Module-level state variables** (modifier.ojo lines 66–76):
```javascript
var currentItems      = [];
var currentItem       = null;
var sourceXml         = "";
var selectedItemIndex = -1;
var currentPage       = 0;
var allItems          = [];
var searchTimer       = null;
var sortColumn        = "";
var sortAsc           = true;
```
Dispatcher adds:
```javascript
var parsedActions     = [];
var selectedActionId  = "";
```
Remove `var roleValues = []` (not needed).

**getPageSize() — page size selector** (modifier.ojo lines 79–83):
```javascript
function getPageSize(){
  var sel = document.getElementById("pageSizeSelect");
  var val = sel ? sel.value : "50";
  if(val === "all"){ return currentItems.length || 1; }
  return parseInt(val, 10) || 50;
}
```
Copy verbatim — dispatcher includes the page-size selector (D per Claude's discretion, modifier already has it).

**htmlEscape() — XSS guard for DOM rendering** (modifier.ojo lines 85–92):
```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}
```
Copy verbatim. Apply to all fields written via `.innerHTML` in the fixlet table.

**setStatus() helper** (modifier.ojo lines 94–98):
```javascript
function setStatus(msg){
  var el = document.getElementById("status");
  if(el){ el.innerText = msg; }
}
```
Copy verbatim.

**clearTable() / addHeader() pattern** (modifier.ojo lines 100–115):
```javascript
function clearTable(){
  var t = document.getElementById("fixletTable");
  while(t.rows.length > 0){ t.deleteRow(0); }
}

function addHeader(){
  var t = document.getElementById("fixletTable");
  var r = t.insertRow(-1);
  r.insertCell(-1).innerHTML = "<b>Select</b>";
  r.insertCell(-1).innerHTML = makeSortHeader("name",     "Fixlet Name");
  r.insertCell(-1).innerHTML = makeSortHeader("category", "Category");
  r.insertCell(-1).innerHTML = makeSortHeader("roles",    "Roles");
  r.insertCell(-1).innerHTML = makeSortHeader("siteName", "Site");
}
```
Change columns from modifier's [Name, Category, ID, Site, Roles] to dispatcher's [Name, Category, Roles, Site] per D-05.

**initDashboard() pattern** (modifier.ojo lines 117–125):
```javascript
function initDashboard(){
  clearTable();
  addHeader();
  setStatus("Ready.");
  loadAllFixlets();   // dispatcher auto-loads portal fixlets on init
}
```
Dispatcher: remove `loadSitenames()` (no site filter — portal site is fixed), remove `loadRoleValues()` and `loadCategoryOptions()`.

**EvaluateRelevance — load all fixlets from portal site** (modifier.ojo lines 185–213, adapted for dispatcher D-04/D-05):
```javascript
function loadAllFixlets(){
  var rel =
    '(id of it as string' +
    ' & "|||" & name of it' +
    ' & "|||" & name of (site of it)' +
    ' & "|||" & (if exists category of it then category of it as string else "")' +
    ' & "|||" & (if exists mime fields whose (name of it = "Associated_Roles") of it' +
    '   then concatenation of values of mime fields whose (name of it = "Associated_Roles") of it' +
    '   else ""))' +
    ' of bes fixlets whose (name of (site of it) = "Dereso Software Portal"' +
    '   and fixlet flag of it)';

  var data = EvaluateRelevance(rel);
  allItems = [];
  for(var i = 0; i < data.length; i++){
    var p = String(data[i]).split("|||");
    allItems.push({
      id:        p[0],
      name:      p[1],
      siteName:  p[2],
      category:  p[3],
      roleValue: p[4] || ""
    });
  }
  setStatus("Loaded " + allItems.length + " fixlets.");
  filterAndRender();
}
```
Key difference from modifier: `bes fixlets whose (name of (site of it) = "Dereso Software Portal" and fixlet flag of it)` scope — portal site only, no custom site flag filter. No severity column. Roles column from MIME field.

**filterAndRender() + debounced search** (modifier.ojo lines 250–287):
```javascript
function filterAndRender(){
  var search   = String(document.getElementById("searchText").value).toLowerCase();
  var rawTerms = search === "" ? [] : search.split(/\s+/);
  var terms = [];
  var i, t, item, fields, match;

  for(t = 0; t < rawTerms.length; t++){
    if(rawTerms[t] !== ""){ terms.push(rawTerms[t]); }
  }

  currentItems = [];
  for(i = 0; i < allItems.length; i++){
    item = allItems[i];
    // dispatcher: no siteFilter dropdown
    if(terms.length > 0){
      fields = [item.name, item.category, item.roleValue, item.siteName].join(" ").toLowerCase();
      match = true;
      for(t = 0; t < terms.length; t++){
        if(fields.indexOf(terms[t]) < 0){ match = false; break; }
      }
      if(!match){ continue; }
    }
    currentItems.push(item);
  }
  setStatus("Showing " + currentItems.length + " of " + allItems.length + " fixlets.");
  applySortToCurrentItems();
  renderPage(0);
}

function onSearchInput(){
  clearTimeout(searchTimer);
  searchTimer = setTimeout(filterAndRender, 300);
}
```
Remove the `siteFilter` branch (dispatcher has no site filter — portal site is fixed).

**renderPage() and updatePagination()** (modifier.ojo lines 290–336):
```javascript
function renderPage(page){
  var pageSize = getPageSize();
  var start    = page * pageSize;
  var end      = Math.min(start + pageSize, currentItems.length);
  var t        = document.getElementById("fixletTable");
  var i, item, r;

  currentPage = page;
  clearTable();
  addHeader();

  for(i = start; i < end; i++){
    item = currentItems[i];
    r    = t.insertRow(-1);
    r.insertCell(-1).innerHTML = '<input type="radio" name="fixSel" onclick="selectFixlet(' + i + ')">';
    r.insertCell(-1).innerHTML = htmlEscape(item.name);
    r.insertCell(-1).innerHTML = htmlEscape(item.category);
    r.insertCell(-1).innerHTML = htmlEscape(item.roleValue || "&mdash;");
    r.insertCell(-1).innerHTML = htmlEscape(item.siteName);
  }

  updatePagination();
}
```
Dispatcher columns: Name, Category, Roles (shows "—" if empty per D-05), Site. No ID column.

**updatePagination()** (modifier.ojo lines 315–336): Copy verbatim — identical pattern.

**makeSortHeader() / applySortToCurrentItems() / sortBy()** (modifier.ojo lines 338–368): Copy verbatim.

**selectFixlet() — API.Get on selection** (modifier.ojo lines 370–389):
```javascript
function selectFixlet(i){
  selectedItemIndex = i;
  currentItem       = currentItems[i];
  var path = "fixlet/custom/" +
    encodeURIComponent(currentItem.siteName) + "/" +
    encodeURIComponent(currentItem.id);

  API.Get(path, function(e, s, b){
    if(s === 200){
      sourceXml = b;
      parseDetailPanel(b);   // dispatcher: replaces parseSourceFields
      setStatus("Loaded: " + currentItem.name);
    } else {
      alert("Load failed: " + e + " status=" + s + " path=" + path);
      setStatus("Load failed: status=" + s);
    }
  });
}
```
API.Get path pattern is identical to modifier. Replace `parseSourceFields(b)` with `parseDetailPanel(b)` which populates the dispatcher detail panel (name, category, roles, action count, action dropdown).

**MIME field read — Associated_Roles** (modifier.ojo lines 421–438):
```javascript
var mimeNodes = xml.getElementsByTagName("MIMEField");
var m, nameNode, valueNode, mName, rolesValue = "";

for(m = 0; m < mimeNodes.length; m++){
  nameNode = mimeNodes[m].selectSingleNode("Name");
  mName    = nameNode ? String(nameNode.text || "").replace(/^\s+|\s+$/g, "") : "";
  if(mName === "Associated_Roles"){
    valueNode  = mimeNodes[m].selectSingleNode("Value");
    rolesValue = valueNode ? String(valueNode.text || "") : "";
    break;
  }
}
var existingRoles = rolesValue !== "" ? rolesValue.split("|").filter(function(r){ return r !== ""; }) : [];
```
Copy verbatim for read-only display in the detail panel (D-07). No write/update of MIME fields in dispatcher.

**XML helper functions** (modifier.ojo lines 543–560):
```javascript
function getNodeText(xml, tag){
  var n = xml.getElementsByTagName(tag);
  if(n.length > 0){ return n[0].text || ""; }
  return "";
}

function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function cdataStart(){ return '<!' + '[CDATA['; }
function cdataEnd(){   return ']]' + '>'; }
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }
```
Copy verbatim. Used by `buildDeployXml()` and detail panel rendering.

**API.Post pattern** (copier.ojo lines 790–808):
```javascript
API.Post(path, xml, function(e, s, b){
  if(s === 200 || s === 201){
    var bodyText = "";
    if(typeof b !== "undefined" && b !== null){ bodyText = String(b); }
    var newId = parseCreatedId(bodyText);
    // ... success handling
    setStatus("Created via " + path + (newId !== "" ? (" ID=" + newId) : ""));
  } else {
    alert("Failed: status=" + s + " error=" + e + " path=" + path + " response=" + b);
    setStatus("Failed via " + path + " status=" + s);
  }
});
```
For dispatcher: `path = "actions"`, `parseCreatedId` → `parseActionId`, success shows deployment ID in banner + "Deploy Another" button (D-11), failure shows error inline below Deploy button.

**parseActions() — action dropdown from fixlet XML** (copier.ojo lines 505–555, adapted):
```javascript
function parseActions(xmlText){
  var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
  xml.async = false;
  xml.loadXML(xmlText);
  parsedActions   = [];
  selectedActionId = "";

  var defaults = xml.getElementsByTagName("DefaultAction");
  var actions  = xml.getElementsByTagName("Action");
  var i, node, idAttr;

  for(i = 0; i < defaults.length; i++){
    node   = defaults[i];
    idAttr = node.getAttribute("ID") || "Action1";
    parsedActions.push({ id: idAttr, label: "Default Action (" + idAttr + ")" });
  }
  for(i = 0; i < actions.length; i++){
    node   = actions[i];
    idAttr = node.getAttribute("ID") || ("Action" + (i + 1));
    parsedActions.push({ id: idAttr, label: idAttr });
  }
  renderActionDropdown();
}
```
Key difference from copier: populates a `<select>` dropdown (not radio buttons), and stores `{ id, label }` not `{ kind, xml, script, title }`. The action ID string (e.g., `"Action1"`) is what goes in the `<SourceFixlet><Action>` element.

**HTML scaffold — filter panel** (modifier.ojo lines 683–700):
```html
<div class="panel">
  <div class="panelBody">
    <table class="rowTable">
      <tr>
        <td class="lbl">Search:</td>
        <td><input id="searchText" class="txtWide" value="" oninput="onSearchInput()"></td>
        <td class="right">
          <button class="btn" onclick="loadAllFixlets()">Load Fixlets</button>
        </td>
      </tr>
    </table>
  </div>
</div>
```
Dispatcher: remove the `siteFilter` select (no site filter). Keep Search + Load Fixlets button. Keep `testREST()` button optional.

**HTML scaffold — table panel with page size selector** (modifier.ojo lines 703–722):
```html
<div class="panel">
  <div class="panelBody">
    <table style="width:100%; margin-bottom:8px;"><tr>
      <td><div id="status">Ready.</div></td>
      <td class="right">
        <span class="small">Show:&nbsp;
          <select id="pageSizeSelect" onchange="renderPage(0)" style="font-family:Arial; font-size:11px;">
            <option value="all">All</option>
            <option value="10">10</option>
            <option value="25">25</option>
            <option value="50" selected="selected">50</option>
            <option value="100">100</option>
          </select>&nbsp;rows
        </span>
      </td>
    </tr></table>
    <table id="fixletTable" class="tableGrid"></table>
    <div id="paginationControls" style="margin-top:8px; text-align:center;"></div>
  </div>
</div>
```
Copy verbatim (page-size selector included per Claude's discretion decision).

**HTML scaffold — init script at bottom** (modifier.ojo lines 780–787):
```html
<script>
try {
  initDashboard();
} catch(ex){
  alert("Init error: " + (ex.message || ex.description || String(ex)));
}
</script>
```
Copy verbatim.

---

### `tests/unit/dispatcher.test.js` (test, batch)

**Analog:** `tests/unit/modifier.test.js`

**File header and module setup** (modifier.test.js lines 1–26):
```javascript
/**
 * dispatcher.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_dispatcher.ojo
 *
 * Functions covered:
 *   1. xmlEscape(s)
 *   2. xmlCDataSafe(s)
 *   3. buildTargetRelevance(groupName)
 *   4. buildExpirationElement(days)
 *   5. parseActionId(body)           -- regex-fallback path only
 *   6. PORTAL_CONFIG validation      -- structural assertion
 *
 * Running: node tests/unit/dispatcher.test.js
 * Requirements: Node.js built-in `assert` module only.
 */
"use strict";
var assert = require("assert");
```

**Test runner infrastructure** (modifier.test.js lines 130–146): Copy verbatim:
```javascript
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

**Summary footer** (modifier.test.js lines 297–307): Copy verbatim:
```javascript
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

**xmlEscape / xmlCDataSafe tests** (modifier.test.js lines 152–203): Copy verbatim — functions are identical across all dashboards.

**PORTAL_CONFIG structural tests** (modifier.test.js lines 269–291 — adapted):
```javascript
section("PORTAL_CONFIG");

expect("PORTAL_CONFIG.defaultExpirationDays is a positive integer", function(){
  assert.strictEqual(typeof PORTAL_CONFIG.defaultExpirationDays, "number");
  assert.ok(PORTAL_CONFIG.defaultExpirationDays > 0);
  assert.strictEqual(PORTAL_CONFIG.defaultExpirationDays, Math.floor(PORTAL_CONFIG.defaultExpirationDays));
});
expect("PORTAL_CONFIG.targetGroups is a non-empty array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.targetGroups));
  assert.ok(PORTAL_CONFIG.targetGroups.length > 0);
});
expect("all PORTAL_CONFIG.targetGroups entries are non-empty strings", function(){
  PORTAL_CONFIG.targetGroups.forEach(function(g){
    assert.strictEqual(typeof g, "string");
    assert.ok(g.length > 0);
  });
});
```
Change from modifier's `roles`/`categories` properties to dispatcher's `defaultExpirationDays`/`targetGroups`. Pattern: `Array.isArray()` + length check + forEach type check.

**New function tests for dispatcher-specific helpers:**
```javascript
// buildTargetRelevance tests
section("buildTargetRelevance");

expect("standard group name produces member-of relevance", function(){
  var result = buildTargetRelevance("All Workstations");
  assert.ok(result.indexOf("member of bes computer group") !== -1);
  assert.ok(result.indexOf("All Workstations") !== -1);
});
expect("empty group name returns 'true' fallback", function(){
  assert.strictEqual(buildTargetRelevance(""), "true");
  assert.strictEqual(buildTargetRelevance("   "), "true");
});
expect("group name with single quote is escaped", function(){
  var result = buildTargetRelevance("IT Dep't");
  assert.ok(result.indexOf("IT Dep\\'t") !== -1 || result.indexOf("IT Dep''t") !== -1,
    "Single quote must be escaped in relevance string");
});

// buildExpirationElement tests
section("buildExpirationElement");

expect("7 days produces P7D duration element", function(){
  var result = buildExpirationElement(7);
  assert.ok(result.indexOf("P7D") !== -1);
  assert.ok(result.indexOf("HasEndTime") !== -1);
});
expect("1 day produces P1D", function(){
  assert.ok(buildExpirationElement(1).indexOf("P1D") !== -1);
});

// parseActionId tests
section("parseActionId");

expect("extracts ID from /api/action/N URL pattern", function(){
  assert.strictEqual(parseActionId('<Action Resource="/api/action/9876"/>'), "9876");
});
expect("extracts ID from <ID>N</ID> element", function(){
  assert.strictEqual(parseActionId('<ID>42</ID>'), "42");
});
expect("returns empty string for empty body", function(){
  assert.strictEqual(parseActionId(""), "");
  assert.strictEqual(parseActionId(null), "");
});
```

---

### `tests/integration/dispatcher.integration.test.js` (test, request-response)

**Analog:** `tests/integration/modifier.integration.test.js`

**File header and environment guard** (modifier.integration.test.js lines 1–43):
```javascript
/**
 * Integration tests for fixlet_dispatcher.ojo — BigFix REST API POST patterns.
 *
 * WARNING: Run against a STAGING BigFix instance only. Test creates a real
 * offer-type action deployment. Do not run against production.
 *
 * Required environment variables:
 *   BIGFIX_URL   — Base URL of the BigFix REST API
 *   BIGFIX_USER  — BigFix admin username
 *   BIGFIX_TOKEN — BigFix admin password (Basic auth credential)
 *
 * Optional:
 *   TEST_SOURCE_SITE_NAME  — Site name (default: "Dereso Software Portal")
 *   TEST_SOURCE_FIXLET_ID  — Fixlet ID for round-trip POST test
 *   TEST_TARGET_GROUP      — Target group name for the POST (default: "All Workstations")
 */
"use strict";

var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: BIGFIX_URL, BIGFIX_USER, and BIGFIX_TOKEN must all be set to run integration tests.");
  process.exit(0);
}
```

**apiRequest() helper** (modifier.integration.test.js lines 65–108 — adapted for POST):
```javascript
var https = require("https");
var fs    = require("fs");
var path  = require("path");

function apiRequest(method, relativePath, bodyXml, callback) {
  var parsed = new URL(BIGFIX_URL);
  var authHeader = "Basic " + Buffer.from(BIGFIX_USER + ":" + BIGFIX_TOKEN).toString("base64");
  var apiPath = "/api/" + relativePath;

  var requestOptions = {
    hostname: parsed.hostname,
    port:     parsed.port || 52311,
    path:     apiPath,
    method:   method,
    headers:  {
      "Authorization": authHeader,
      "Accept":        "application/xml"
    },
    rejectUnauthorized: true
  };

  if ((method === "PUT" || method === "POST") && bodyXml) {
    var bodyBuffer = Buffer.from(bodyXml, "utf8");
    requestOptions.headers["Content-Type"]   = "application/xml";
    requestOptions.headers["Content-Length"] = bodyBuffer.length;
  }

  var req = https.request(requestOptions, function(res) {
    var chunks = [];
    res.on("data", function(chunk) { chunks.push(chunk); });
    res.on("end", function() {
      var responseBody = Buffer.concat(chunks).toString("utf8");
      callback(null, res.statusCode, responseBody);
    });
  });

  req.on("error", function(err) {
    callback(err.message || String(err), null, null);
  });

  if ((method === "PUT" || method === "POST") && bodyXml) {
    req.write(Buffer.from(bodyXml, "utf8"));
  }

  req.end();
}
```
Key change from modifier: add `"POST"` to the `method === "PUT"` body-write conditions.

**Test runner infrastructure** (modifier.integration.test.js lines 132–195): Copy verbatim — `runTest`, `runAsyncTest`, `skipTest`, `assert`, `assertEqual` are identical.

**Integration test scenarios — structure to mirror:**
```
Test 1: API connectivity       → GET /api/sites → assert 200
Test 2: Load source fixlet     → GET fixlet/custom/<site>/<id> → assert 200 + <BES
Test 3: POST round-trip        → POST actions with buildDeployXml fixture → assert 200|201 + elapsed < 5000ms
Test 4: Input guard — no fixlet selected → synchronous, no network
Test 5: Input guard — empty target group → synchronous, assert buildTargetRelevance("") = "true"
Test 6: API error handling     → GET non-existent fixlet → assert non-200 status surfaced
```

**Async test chain** (modifier.integration.test.js lines 375–395):
```javascript
runAsyncTest("Test 1: API connectivity", test1_apiConnectivity)
  .then(function(){ return runAsyncTest("Test 2: Load source fixlet", test2_loadSourceFixlet); })
  .then(function(){ return runAsyncTest("Test 3: POST round-trip (happy path + NFR-01 timing)", test3_postActionHappyPath); })
  .then(function(){ return runAsyncTest("Test 6: API error handling", test6_apiErrorHandling); })
  .then(function(){
    // print summary and exit
    process.exit(failed > 0 ? 1 : 0);
  });
```
Same Promise chain pattern. Replace `test3_putFixletHappyPath` with `test3_postActionHappyPath` (uses `apiRequest("POST", "actions", fixtureXml, cb)`). Timing assertion: `elapsed < 5000` (NFR-01 for dispatcher; modifier used 30000ms for PUT).

---

### `tests/fixtures/phase-03/valid-fixlet-with-actions.ojo` (fixture)

**Analog:** `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo`

**Base structure** (valid-fixlet-with-roles.ojo lines 1–29):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>Sample Fixlet — With Multiple Actions</Title>
    <Description><![CDATA[Phase 3 test fixture: fixlet with multiple actions for action parse tests.]]></Description>
    <Relevance>true</Relevance>
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
      ...
    </DefaultAction>
    <Action ID="Action2">
      ...
    </Action>
  </Fixlet>
</BES>
```
Key addition: include both a `<DefaultAction ID="Action1">` and an `<Action ID="Action2">` element so `parseActions()` returns a two-item array — needed to test the action dropdown population logic.

### `tests/fixtures/phase-03/valid-fixlet-single-action.ojo` (fixture)

**Analog:** `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo`

Same base structure, but only a single `<DefaultAction ID="Action1">` element. Tests the single-action path where `parsedActions.length === 1`.

### `tests/fixtures/phase-03/sample-action-response.xml` (fixture)

**No exact analog** — use RESEARCH.md Pattern 3 structure:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="BESAPI.xsd">
  <Action Resource="https://bigfix.example.com:52311/api/action/9876" LastModified="2026-06-14T12:00:00+00:00">
    <Name>Sample Offer Action</Name>
    <ID>9876</ID>
  </Action>
</BESAPI>
```
This fixture is read as a plain string in the `parseActionId()` unit tests (regex-fallback path — no ActiveXObject). The `<ID>` and `Resource` attribute provide two test vectors.

---

## Shared Patterns

### BigFix Wizard XML Wrapper
**Source:** `Existing Dashboards/fixlet_modifier.ojo` lines 1–11 and 678–792
**Apply to:** `fixlet_dispatcher.ojo`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES>
  <Wizard>
    <Title>...</Title>
    <UIHooks LaunchType="Document" RequiresAuthoring="false" Menu="Dashboards"></UIHooks>
    <DefaultPage>main</DefaultPage>
    <Page Name="main" DocType="HTML">
      <Title>...</Title>
      <Head><![CDATA[ ... JS + CSS ... ]]></Head>
      <HTML><![CDATA[ ... HTML ... ]]></HTML>
    </Page>
  </Wizard>
</BES>
```

### XML Escape + CDATA Helpers
**Source:** `Existing Dashboards/fixlet_modifier.ojo` lines 549–560
**Apply to:** `fixlet_dispatcher.ojo` (runtime), `dispatcher.test.js` (test copy)
```javascript
function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
function cdataStart(){ return '<!' + '[CDATA['; }
function cdataEnd(){   return ']]' + '>'; }
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }
```

### htmlEscape (XSS guard)
**Source:** `Existing Dashboards/fixlet_modifier.ojo` lines 85–92
**Apply to:** All `innerHTML` assignments in `renderPage()` in `fixlet_dispatcher.ojo`
```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}
```

### API.Get path construction
**Source:** `Existing Dashboards/fixlet_modifier.ojo` lines 373–376
**Apply to:** `selectFixlet()` in `fixlet_dispatcher.ojo`
```javascript
var path = "fixlet/custom/" +
  encodeURIComponent(currentItem.siteName) + "/" +
  encodeURIComponent(currentItem.id);
API.Get(path, function(e, s, b){ ... });
```
Path is always `fixlet/custom/...` for portal site fixlets (custom site type).

### ActiveXObject XML parse block
**Source:** `Existing Dashboards/fixlet_modifier.ojo` lines 393–396
**Apply to:** `parseDetailPanel()` and `buildDeployXml()` in `fixlet_dispatcher.ojo`
```javascript
var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
xml.async = false;
xml.loadXML(xmlText);
```
Always wrap in `try/catch` — IE-only, throws in Node.js tests (the `try/catch` silent-fail pattern is the established norm, confirmed in copier.ojo lines 368–395).

### apiRequest() Node.js integration helper
**Source:** `tests/integration/modifier.integration.test.js` lines 65–108
**Apply to:** `dispatcher.integration.test.js`
Copy the function verbatim, adding `"POST"` alongside `"PUT"` in the body-write conditions (lines 84 and 103).

### Environment guard
**Source:** `tests/integration/modifier.integration.test.js` lines 36–43
**Apply to:** `dispatcher.integration.test.js`
```javascript
if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: ...");
  process.exit(0);
}
```
Copy verbatim — same skip-gracefully pattern when env vars are absent.

### Test runner (runTest / runAsyncTest / skipTest)
**Source:** `tests/integration/modifier.integration.test.js` lines 132–195
**Apply to:** `dispatcher.integration.test.js`
Copy verbatim — the Promise-based `runAsyncTest` and synchronous `runTest` infrastructure is project-standard and unchanged.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `tests/fixtures/phase-03/sample-action-response.xml` | fixture | — | No BESAPI action response XML exists in the codebase — all prior fixtures are BES Fixlet XML. Use RESEARCH.md Pattern 3 for the exact element structure. |

---

## Key Differences from modifier.ojo (What to Strip/Add)

| Strip from modifier scaffold | Add for dispatcher |
|------------------------------|---------------------|
| `loadSitenames()` + `siteFilter` dropdown | `parsedActions[]` + `selectedActionId` state vars |
| `loadRoleValues()` + `loadCategoryOptions()` | `parseActions(xmlText)` — action dropdown population |
| `buildRoleRelevance()` (complex SQL relevance) | `buildTargetRelevance(groupName)` — group relevance builder |
| `buildUpdateXml()` (PUT body builder) | `buildDeployXml()` — SourcedFixletAction POST body builder |
| `saveFixlet()` → `API.Put(...)` | `deployFixlet()` → `API.Post("actions", xml, cb)` |
| Role row management UI (addRoleRow, removeRoleRow, makeRoleDropdown) | Action dropdown (`<select id="actionSelect">`) |
| Category editor (`editCategory` select + `editCategoryOther` input) | Detail panel: name, category (read-only), roles (read-only), action count, action dropdown |
| XML preview panel + previewXml() | Live preview panel (auto-updates on form change) — D-10 |
| Alert-based success/failure (modifier lines 669–674) | Success banner + "Deploy Another" button; error inline below Deploy button — D-11 |

---

## Metadata

**Analog search scope:** `Existing Dashboards/`, `tests/unit/`, `tests/integration/`, `tests/fixtures/`
**Files read:** 6 (fixlet_modifier.ojo, fixlet_copier.ojo, modifier.test.js, modifier.integration.test.js, valid-fixlet-with-roles.ojo, copier.test.js header)
**Pattern extraction date:** 2026-06-14
