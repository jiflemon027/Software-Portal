# Phase 6: Fixlet Update Tracker — Pattern Map

**Mapped:** 2026-07-08
**Files analyzed:** 8 (new files to create)
**Analogs found:** 7 / 8 (`scripts/generate_category_map.js` has no codebase analog)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Existing Dashboards/fixlet_update_tracker.ojo` | dashboard (controller + component) | event-driven + request-response | `fixlet_modifier.ojo` (primary) + `fixlet_copier.ojo` + `fixlet_role_assigner.ojo` + `fixlet_dispatcher.ojo` | composite-exact |
| `scripts/generate_category_map.js` | utility | transform (batch) | none | no analog |
| `tests/unit/update_tracker.test.js` | test (unit) | — | `tests/unit/modifier.test.js` | exact |
| `tests/integration/update_tracker.integration.test.js` | test (integration) | request-response | `tests/integration/modifier.integration.test.js` | exact |
| `tests/fixtures/phase-06/portal-fixlet-with-roles.xml` | fixture | — | `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` | exact |
| `tests/fixtures/phase-06/source-fixlet-new-version.xml` | fixture | — | `tests/fixtures/phase-02/valid-fixlet-no-roles.ojo` | exact |
| `tests/fixtures/phase-06/expected-copy-output.xml` | fixture | — | `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` | role-match |
| `tests/fixtures/phase-06/expected-superseded-output.xml` | fixture | — | `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` | role-match |

---

## Pattern Assignments

### `Existing Dashboards/fixlet_update_tracker.ojo` (dashboard, event-driven + request-response)

**Analogs (composite):**
- `Existing Dashboards/fixlet_modifier.ojo` — PORTAL_CONFIG, htmlEscape, xmlEscape, MIME field read/write, buildUpdateXml, API.Put, makeSortHeader, setStatus
- `Existing Dashboards/fixlet_copier.ojo` — parseCreatedId, API.Post (create fixlet), API.Get (source fixlet path with siteType)
- `Existing Dashboards/fixlet_role_assigner.ojo` — deployNextRole sequential batch callback pattern
- `Existing Dashboards/fixlet_dispatcher.ojo` — portal fixlet relevance query (includes Associated_Roles), setStatus

---

#### OJO file header and IE9 shim (lines 1–11 of any dashboard)

Copy verbatim from `fixlet_modifier.ojo` lines 1–11:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES>
  <Wizard>
    <Title>Dereso Fixlet Update Tracker</Title>
    <UIHooks LaunchType="Document" RequiresAuthoring="false" Menu="Dashboards"></UIHooks>
    <DefaultPage>main</DefaultPage>

    <Page Name="main" DocType="HTML">
      <Title>Dereso Fixlet Update Tracker</Title>
      <Head><![CDATA[
<meta http-equiv="X-UA-Compatible" content="IE=9">
```

Substitute `Title` and `Page/Title` values for Phase 6. Everything else — `LaunchType`, `RequiresAuthoring`, `Menu`, `DocType`, `Head` CDATA opening — is copied verbatim.

---

#### CSS block (lines 12–34 of any dashboard)

Copy verbatim from `fixlet_modifier.ojo` lines 12–34 (all four dashboards share this identical CSS):

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
.btn { font-family: Arial; font-size: 11px; padding: 6px 14px; border: 1px solid #b3b3b3; background: #f7f7f7; cursor: pointer; }
.btnGreen { font-family: Arial; font-size: 11px; padding: 8px 18px; border: 1px solid #237241; background: #33a05a; color: #ffffff; font-weight: bold; cursor: pointer; }
.tableGrid { width: 100%; border-collapse: collapse; background: #ffffff; }
.tableGrid td, .tableGrid th { border: 1px solid #d7dbe0; padding: 6px 8px; vertical-align: middle; }
.tableGrid th { background: #f4f6f8; color: #2a5d9f; text-align: left; }
.small { color: #666666; font-size: 10px; }
.right { text-align: right; }
.divider { border-top: 1px solid #e1e1e1; margin: 10px 0; }
```

Phase 6 adds tab-specific CSS (`tabBtn`, `tabActive`, `tabPanel`) as new classes after this block.

---

#### PORTAL_CONFIG block — source: `fixlet_modifier.ojo` lines 36–64

```javascript
// ==========================================================================
// PORTAL CONFIGURATION -- Edit this block to update roles and categories.
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
    ...
  ]
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```

Phase 6 **adds** a `sourceSites` array as the first key before `roles`:

```javascript
var PORTAL_CONFIG = {
  sourceSites: [
    "BigFix Software Installer Library for Windows"
    // Add additional source site names here
  ],
  roles: [ ... ],       // unchanged from modifier.ojo
  categories: [ ... ]   // updated to match CATEGORY_MAP values
};
```

**Decision D-05:** `sourceSites` is the only new key. All other keys are copied verbatim from `fixlet_modifier.ojo`.

---

#### Global state variables — source: `fixlet_modifier.ojo` lines 66–76

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

Phase 6 adds scan-specific state after these:

```javascript
var portalItems       = [];   // loaded once per scan
var scanSourceResults = [];   // accumulated across all source sites
var scanSiteIndex     = 0;    // current site index during per-site scan loop
var updateRows        = [];   // results of buildScanResults().updates
var arrivalRows       = [];   // results of buildScanResults().arrivals
```

---

#### HTML escape — source: `fixlet_modifier.ojo` lines 86–92, also `fixlet_dispatcher.ojo` lines 69–75

```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}
```

Copy verbatim. Applied to every fixlet name, site name, category, or role string inserted into `.innerHTML`.

---

#### setStatus — source: `fixlet_dispatcher.ojo` lines 77–81

```javascript
function setStatus(msg){
  var el = document.getElementById("status");
  if(el){ el.innerText = msg; }
}
```

Copy verbatim. Phase 6 calls this during scan progress (D-02).

---

#### xmlEscape + CDATA helpers — source: `fixlet_modifier.ojo` lines 551–562

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

Copy verbatim. Applied to values inserted into BES XML strings in `buildCopyXml` and `buildSupersededXml`.

---

#### EvaluateRelevance — portal fixlet query — source: `fixlet_dispatcher.ojo` lines 117–147

```javascript
function loadAllFixlets(){
  var rel =
    '(id of it as string' +
    ' & "|||" & name of it' +
    ' & "|||" & name of (site of it)' +
    ' & "|||" & (if exists category of it then category of it as string else "")' +
    ' & "|||" & (if exists mime fields whose (name of it = "Associated_Roles") of it' +
    '   then concatenation of values of mime fields whose (name of it = "Associated_Roles") of it' +
    '   else "")' +
    ' & "|||" & (if fixlet flag of it then "fixlet" else "task"))' +
    ' of bes fixlets whose (name of (site of it) = "Dereso Software Portal"' +
    '   and (fixlet flag of it or task flag of it))';

  var data = EvaluateRelevance(rel);
  var i, p;

  allItems = [];
  for(i = 0; i < data.length; i++){
    p = String(data[i]).split("|||");   // <-- always wrap data[i] in String()
    allItems.push({
      id:        p[0],
      name:      p[1],
      siteName:  p[2],
      category:  p[3],
      roleValue: p[4] || "",
      itemType:  p[5] || "fixlet"
    });
  }
}
```

Phase 6 uses this as `loadPortalFixlets()` — identical query, result stored in `portalItems[]` instead of `allItems[]`. The 6-field `|||`-separated tuple and `String(data[i]).split("|||")` pattern must be copied exactly.

---

#### MIME field read — source: `fixlet_modifier.ojo` lines 423–435

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
```

Phase 6 adapts this into `readMimeField(xmlDoc, fieldName)` — replace the hardcoded `"Associated_Roles"` with the `fieldName` parameter. **Critical:** `selectSingleNode` requires `origDoc.setProperty("SelectionLanguage", "XPath")` to be called first on the parent DOM document.

---

#### buildUpdateXml (string-strip + MSXML ActiveX pattern) — source: `fixlet_modifier.ojo` lines 566–625

```javascript
function buildUpdateXml(){
  // Strip Associated_Roles MIME field from raw XML string before DOM parsing.
  // More reliable than MSXML removeChild on elements with child nodes.
  var cleanedXml = ("" + sourceXml).replace(
    /<MIMEField>\s*<Name>\s*Associated_Roles\s*<\/Name>[\s\S]*?<\/MIMEField>/gi, "");

  var origDoc = new ActiveXObject("Msxml2.DOMDocument.6.0");
  origDoc.async            = false;
  origDoc.validateOnParse  = false;
  origDoc.resolveExternals = false;
  origDoc.setProperty("SelectionLanguage", "XPath");   // <-- required for selectSingleNode
  origDoc.loadXML(cleanedXml);

  var fixletNode = origDoc.getElementsByTagName("Fixlet")[0] || origDoc.getElementsByTagName("Task")[0];
  if(!fixletNode){ alert("Could not find Fixlet or Task node."); return ""; }

  // Update category
  var catNodes = origDoc.getElementsByTagName("Category");
  if(catNodes.length > 0){ catNodes[0].text = getEffectiveCategory(); }

  // Write Associated_Roles MIME field before <Domain>
  var newMime  = origDoc.createElement("MIMEField");
  var nameEl   = origDoc.createElement("Name");
  var valueEl  = origDoc.createElement("Value");
  nameEl.text  = "Associated_Roles";
  valueEl.text = roles.join("|");
  newMime.appendChild(nameEl);
  newMime.appendChild(valueEl);
  var domainNode = fixletNode.selectSingleNode("Domain");
  if(domainNode){ fixletNode.insertBefore(newMime, domainNode); }
  else           { fixletNode.appendChild(newMime); }

  var finalXml = '<?xml version="1.0" encoding="UTF-8"?>\r\n' + origDoc.documentElement.xml;
  return finalXml;
}
```

Phase 6 splits this into two functions:
- `buildCopyXml(sourceXml, category, rolesValue)` — strips `Associated_Roles`, sets `<Category>`, adds new `Associated_Roles` MIME field
- `buildSupersededXml(oldPortalXml, newFixletId)` — strips `X-Superseded-By`, adds new `X-Superseded-By` MIME field

Both use the identical ActiveX setup block (lines 574–579 above): `async=false`, `validateOnParse=false`, `resolveExternals=false`, `setProperty("SelectionLanguage","XPath")`.

---

#### API.Put — source: `fixlet_modifier.ojo` lines 652–674

```javascript
var path = (currentItem.itemType === "task" ? "task" : "fixlet") + "/custom/" +
  encodeURIComponent(currentItem.siteName) + "/" +
  encodeURIComponent(currentItem.id);

API.Put(path, xml, function(e, s, b){
  if(s === 200 || s === 201){
    // success branch
    setStatus("Saved Fixlet ID " + currentItem.id + " ...");
  } else {
    alert("Save failed: status=" + s + "\nerror=" + e);
  }
});
```

Phase 6 `X-Superseded-By` PUT path pattern:

```javascript
var putPath = "fixlet/custom/" + encodeURIComponent("Dereso Software Portal") +
              "/" + encodeURIComponent(oldFixletId);
API.Put(putPath, supersededXml, function(e4, s4, b4) {
  var putOk = (s4 === 200 || s4 === 201);   // always check both 200 and 201 (Pitfall 6)
  // ...
});
```

---

#### API.Post (create fixlet) — source: `fixlet_copier.ojo` lines 780–808

```javascript
path = "fixlets/custom/" + encodeURIComponent(site);   // <-- "fixlets" plural (Pitfall 2)

API.Post(path, xml, function(e,s,b){
  if(s==200||s==201){
    bodyText = "";
    if(typeof b !== "undefined" && b !== null){ bodyText = String(b); }
    newId = parseCreatedId(bodyText);
    // success handling
  } else {
    alert("Failed: status=" + s + " error=" + e + " path=" + path + " response=" + b);
  }
});
```

Phase 6 uses: `"fixlets/custom/" + encodeURIComponent("Dereso Software Portal")` as the POST path. The `parseCreatedId()` call is reused verbatim.

---

#### parseCreatedId — source: `fixlet_copier.ojo` lines 365–405

```javascript
function parseCreatedId(body){
  var xml, nodes, txt, m;
  if(!body){ return ""; }
  try{
    xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
    xml.async = false;
    xml.loadXML(body);
    nodes = xml.getElementsByTagName("Fixlet");
    if(nodes.length>0){
      txt = nodes[0].getAttribute("ID");
      if(txt && txt !== ""){ return txt; }
      txt = nodes[0].getAttribute("Resource");
      if(txt && txt !== ""){
        m = /\/([^\/]+)$/.exec(txt);
        if(m && m[1]){ return m[1]; }
      }
    }
    nodes = xml.getElementsByTagName("Task");
    if(nodes.length>0){
      txt = nodes[0].getAttribute("ID");
      if(txt && txt !== ""){ return txt; }
      txt = nodes[0].getAttribute("Resource");
      if(txt && txt !== ""){
        m = /\/([^\/]+)$/.exec(txt);
        if(m && m[1]){ return m[1]; }
      }
    }
  } catch(ex) {}
  m = /fixlet\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
  if(m && m[1]){ return m[1]; }
  m = /task\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
  if(m && m[1]){ return m[1]; }
  m = /\bID=["']?(\d+)["']?/i.exec(body);
  if(m && m[1]){ return m[1]; }
  return "";
}
```

Copy verbatim into Phase 6 dashboard. Do not rewrite — it handles all response shapes from BigFix.

---

#### API.Get (source fixlet by siteType) — source: `fixlet_copier.ojo` lines 423–434

```javascript
function selectFixlet(i){
  currentItem = currentItems[i];
  var path = "fixlet/" + encodeURIComponent(currentItem.siteType) + "/" +
             encodeURIComponent(currentItem.siteName) + "/" +
             encodeURIComponent(currentItem.id);

  API.Get(path, function(e,s,b){
    if(s==200){
      sourceXml = b;
      // ...
    }
  });
}
```

Phase 6 uses this pattern for Step 2 of `copyNextItem`: GET source fixlet using `item.sourceSiteType` and `item.sourceSiteName` captured at scan time.

---

#### deployNextRole sequential batch callback — source: `fixlet_role_assigner.ojo` lines 467–528

```javascript
function deployNextRole(rolesArray, index, rolesMap, suffix, dbExistenceRelevance, progressEl, errEl){
  if(index >= rolesArray.length){
    setStatus("All roles deployed.");
    // ... completion handling
    return;
  }

  var role = rolesArray[index];

  if(progressEl){
    var progMsg = document.createElement("div");
    progMsg.innerText = "Deploying role " + (index + 1) + " of " + rolesArray.length + ": " + role + "...";
    progressEl.appendChild(progMsg);
  }

  // ... build xml ...

  API.Post("actions", xml, function(e, s, b){
    if(s === 200 || s === 201){
      // success branch
      deployNextRole(rolesArray, index + 1, rolesMap, ...);  // <-- recurse
    } else {
      // error branch — does NOT recurse (stops on error for role_assigner)
      setStatus("Deploy failed for role: " + role);
    }
  });
}
```

Phase 6 adapts this into `copyNextItem(items, index, results, onAllDone)`. Key differences:
- **Always recurse** even on error (partial failure model from D-12): call `copyNextItem(items, index + 1, results, onAllDone)` in the error branch too, not just in the success branch.
- **4 nested callbacks** per item (GET portal → GET source → POST copy → PUT supersede), matching RESEARCH.md Pattern 9 exactly.
- `onAllDone(results)` is called instead of accessing a module-level completion handler.

The recursion-at-tail-of-callback pattern (calling `copyNextItem` as the last statement in each success AND error branch) is the critical structural insight from `deployNextRole`.

---

#### makeSortHeader + sortBy — source: `fixlet_modifier.ojo` lines 341–370

```javascript
function makeSortHeader(col, label){
  var indicator = sortColumn === col ? (sortAsc ? " &#9650;" : " &#9660;") : "";
  return '<b style="cursor:pointer;" onclick="sortBy(\'' + col + '\')">' + label + indicator + '</b>';
}

function applySortToCurrentItems(){
  if(sortColumn === ""){ return; }
  var col = sortColumn;
  var asc = sortAsc;
  currentItems.sort(function(a, b){
    var va, vb, na, nb;
    if(col === "id" || col === "roleCount"){
      na = parseInt(String(a[col] || ""), 10) || 0;
      nb = parseInt(String(b[col] || ""), 10) || 0;
      return asc ? na - nb : nb - na;
    }
    va = String(a[col] || "").toLowerCase();
    vb = String(b[col] || "").toLowerCase();
    if(va < vb){ return asc ? -1 : 1; }
    if(va > vb){ return asc ? 1 : -1; }
    return 0;
  });
}

function sortBy(col){
  if(sortColumn === col){ sortAsc = !sortAsc; }
  else { sortColumn = col; sortAsc = true; }
  applySortToCurrentItems();
  renderPage(0);
}
```

Copy verbatim. Phase 6 has two tables (Updates and New Arrivals) each with separate `sortColumn`/`sortAsc` state — either use two global pairs (`updatesSortColumn`, `arrivalsSortColumn`) or parameterize the sort state into the render function.

---

### `scripts/generate_category_map.js` (utility, batch transform)

**Analog:** None in codebase. `scripts/` directory is empty. This is a net-new Node.js dev script.

**Pattern source:** RESEARCH.md Pattern 3 (verified from reading `Dashboard_4_samples/software_categorized.csv`).

Key implementation facts (from RESEARCH.md):
- CSV path: `Dashboard_4_samples/software_categorized.csv` (799 lines, 1 header + 798 data rows)
- Column indices (0-based): `0=No, 1=Software Installer name, 2=Description, 3=Specific Category, 4=Shortlist Category`
- Use column 4 (`Shortlist Category`) per D-18 — not column 3
- Version strip regex applied to column 1 before building lookup key: `rawName.replace(/ v\d[\d.]+/g, "").trim()`
- Simple `split(",")` is sufficient — no quoted fields with internal commas in this CSV (A2)
- Output: `console.log("var CATEGORY_MAP = " + JSON.stringify(map, null, 2) + ";")`

Invocation: `node scripts/generate_category_map.js` (output copied into `fixlet_update_tracker.ojo`)

---

### `tests/unit/update_tracker.test.js` (test/unit)

**Analog:** `tests/unit/modifier.test.js`

**Test file structure** (copy framework verbatim, lines 1–147 of `modifier.test.js`):

```javascript
/**
 * update_tracker.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_update_tracker.ojo
 * ...
 * Running: node tests/unit/update_tracker.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 */
"use strict";

var assert = require("assert");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from fixlet_update_tracker.ojo)
// ---------------------------------------------------------------------------

// ... function definitions here ...

// ---------------------------------------------------------------------------
// 2. TEST INFRASTRUCTURE
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// 3. TEST BLOCKS
// ---------------------------------------------------------------------------

section("stripVersion");
// ... tests ...

section("extractVersion");
// ... tests ...

section("compareVersions");
// ... tests ...

section("buildScanResults");
// ... tests ...

section("lookupCategory");
// ... tests ...

section("PORTAL_CONFIG");
// structural assertions copied from modifier.test.js lines 270-291

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

**Summary footer** (lines 297–307 of `modifier.test.js`): copy verbatim — identical in all unit test files.

**PORTAL_CONFIG structural assertion** (lines 269–291 of `modifier.test.js`): copy verbatim, update to also assert `PORTAL_CONFIG.sourceSites` is a non-empty array.

**Functions to extract and test** (from RESEARCH.md Validation Architecture):
- `stripVersion(name)` — 4 cases from RESEARCH.md Pattern 2 table
- `extractVersion(name)` — same 4 cases
- `compareVersions(a, b)` — numeric segments, 9 vs 10 edge case
- `buildScanResults(portalItems, sourceItems)` — update match, new arrival
- `lookupCategory(productKey, portalCategory)` — CSV fallback, portal category wins

---

### `tests/integration/update_tracker.integration.test.js` (test/integration, request-response)

**Analog:** `tests/integration/modifier.integration.test.js`

**Section 1 (Environment guard)** — copy verbatim from `modifier.integration.test.js` lines 36–43:

```javascript
var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: BIGFIX_URL, BIGFIX_USER, and BIGFIX_TOKEN must all be set to run integration tests.");
  process.exit(0);
}
```

**Section 2 (apiRequest helper)** — copy verbatim from `modifier.integration.test.js` lines 49–108. Phase 6 needs `GET`, `POST`, and `PUT` support. The `modifier.integration.test.js` version supports `PUT`; the `copier.integration.test.js` version handles `POST` body:

```javascript
// From copier.integration.test.js (adds POST body support)
if ((method === "PUT" || method === "POST") && bodyXml) {
  var bodyBuffer = Buffer.from(bodyXml, "utf8");
  requestOptions.headers["Content-Type"]   = "application/xml";
  requestOptions.headers["Content-Length"] = bodyBuffer.length;
}
// and in req.write:
if ((method === "PUT" || method === "POST") && bodyXml) {
  req.write(Buffer.from(bodyXml, "utf8"));
}
```

**Section 4 (test runner)** — copy verbatim from `modifier.integration.test.js` lines 132–195:
- `assert()`, `assertEqual()`, `runTest()`, `skipTest()`, `runAsyncTest()` — identical in all integration tests

**Section 6 (summary footer)** — copy verbatim from `modifier.integration.test.js` lines 359–393.

**Optional env vars for Phase 6** (extend from modifier pattern):
```javascript
// From modifier.integration.test.js lines 17-20 pattern, extended for Phase 6:
var TEST_SOURCE_SITE_TYPE = process.env.TEST_SOURCE_SITE_TYPE || "external";
var TEST_SOURCE_SITE_NAME = process.env.TEST_SOURCE_SITE_NAME || "";
var TEST_SOURCE_FIXLET_ID = process.env.TEST_SOURCE_FIXLET_ID || "";
var TEST_PORTAL_FIXLET_ID = process.env.TEST_PORTAL_FIXLET_ID || "";
var TEST_TARGET_SITE      = process.env.TEST_TARGET_SITE      || "Dereso Software Portal";
```

---

### `tests/fixtures/phase-06/portal-fixlet-with-roles.xml` (fixture)

**Analog:** `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo`

**Structure to copy** (all 29 lines of `valid-fixlet-with-roles.ojo`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>7-Zip (MSI) v26.01 - Windows (x64)</Title>
    <Description><![CDATA[Phase 6 test fixture: old portal fixlet with category and role associations.]]></Description>
    <Relevance>true</Relevance>
    <Category>File Management &amp; Archiving</Category>
    <Source>Internal</Source>
    <SourceID></SourceID>
    <SourceReleaseDate>2026-01-01</SourceReleaseDate>
    <SourceSeverity></SourceSeverity>
    <CVENames></CVENames>
    <SANSID></SANSID>
    <Domain>BESC</Domain>
    <MIMEField>
      <Name>Associated_Roles</Name>
      <Value>IT Support|General Access</Value>
    </MIMEField>
    <DefaultAction ID="Action1">
      <Description>
        <PreLink>Click </PreLink><Link>here</Link><PostLink> to deploy.</PostLink>
      </Description>
      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">// placeholder</ActionScript>
    </DefaultAction>
  </Fixlet>
</BES>
```

**Key differences from phase-02 analog:**
- Title must contain a version token (` v26.01`) so `stripVersion` and `extractVersion` have something to test against
- `<Category>` must be non-empty (for D-16 category-from-portal-fixlet path)
- `Associated_Roles` must have pipe-separated values (for D-17 roles-from-MIME path)
- Extension is `.xml` not `.ojo` (matches RESEARCH.md file list)

---

### `tests/fixtures/phase-06/source-fixlet-new-version.xml` (fixture)

**Analog:** `tests/fixtures/phase-02/valid-fixlet-no-roles.ojo`

**Structure:** Same BES XML skeleton without `<MIMEField>` block, but with a **newer version** in the title:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>7-Zip (MSI) v26.02 - Windows (x64)</Title>
    <!-- v26.02 is newer than portal v26.01 — this triggers the update path -->
    <Description><![CDATA[Phase 6 test fixture: source fixlet with newer version. Used to test buildCopyXml() and copyNextItem() step 2.]]></Description>
    <Relevance>true</Relevance>
    <Category>Utilities</Category>
    <!-- Category differs from portal fixlet to verify that portal category wins per D-16 -->
    <Source>Internal</Source>
    <SourceID></SourceID>
    <SourceReleaseDate>2026-06-01</SourceReleaseDate>
    <SourceSeverity></SourceSeverity>
    <CVENames></CVENames>
    <SANSID></SANSID>
    <Domain>BESC</Domain>
    <DefaultAction ID="Action1">
      <Description>
        <PreLink>Click </PreLink><Link>here</Link><PostLink> to deploy.</PostLink>
      </Description>
      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">// source action script</ActionScript>
    </DefaultAction>
  </Fixlet>
</BES>
```

**Critical design choice:** Give the source fixlet a **different** `<Category>` value (`"Utilities"`) so integration tests can assert that the copy output uses the portal fixlet's category (`"File Management & Archiving"`) not the source's (D-16).

---

### `tests/fixtures/phase-06/expected-copy-output.xml` (fixture)

**Analog:** `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo`

This fixture represents what `buildCopyXml(sourceXml, "File Management & Archiving", "IT Support|General Access")` should produce. Key assertions:
- `<Title>7-Zip (MSI) v26.02 - Windows (x64)</Title>` (source title, not portal title)
- `<Category>File Management &amp; Archiving</Category>` (portal category, not source category — D-16)
- `<MIMEField><Name>Associated_Roles</Name><Value>IT Support|General Access</Value></MIMEField>` (transferred from portal fixlet — D-17)
- No `X-Superseded-By` field (not added at copy time — added in next step)
- `<ActionScript>` contains the source action script (verbatim from source fixlet)

Structure mirrors `valid-fixlet-with-roles.ojo` exactly but with source fixlet's title and action.

---

### `tests/fixtures/phase-06/expected-superseded-output.xml` (fixture)

**Analog:** `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` extended with second MIMEField

This fixture represents what `buildSupersededXml(oldPortalXml, "99999")` should produce. Key assertions:
- Retains the original portal fixlet title (`7-Zip (MSI) v26.01 - Windows (x64)`)
- Retains existing `<MIMEField>Associated_Roles</MIMEField>` unchanged
- Adds new `<MIMEField><Name>X-Superseded-By</Name><Value>99999</Value></MIMEField>` (D-08)
- The new `X-Superseded-By` field appears **before `<Domain>`** (matching the `insertBefore(domainNode)` pattern from modifier.ojo line 618–619)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES ...>
  <Fixlet>
    <Title>7-Zip (MSI) v26.01 - Windows (x64)</Title>
    ...
    <MIMEField>
      <Name>Associated_Roles</Name>
      <Value>IT Support|General Access</Value>
    </MIMEField>
    <MIMEField>
      <Name>X-Superseded-By</Name>
      <Value>99999</Value>
    </MIMEField>
    <Domain>BESC</Domain>
    ...
  </Fixlet>
</BES>
```

---

## Shared Patterns

### HTML Escaping (XSS prevention)
**Source:** `fixlet_modifier.ojo` lines 86–92 / `fixlet_dispatcher.ojo` lines 69–75
**Apply to:** All places in `fixlet_update_tracker.ojo` where fixlet names, category strings, site names, or role values are inserted into `.innerHTML`

```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}
```

### XML Escaping (injection prevention)
**Source:** `fixlet_modifier.ojo` lines 551–558
**Apply to:** All values inserted into BES XML strings inside `buildCopyXml` and `buildSupersededXml`

```javascript
function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
```

### Status Bar Update
**Source:** `fixlet_dispatcher.ojo` lines 77–81
**Apply to:** Scan start, per-site scan progress, copy progress, error states in `fixlet_update_tracker.ojo`

```javascript
function setStatus(msg){
  var el = document.getElementById("status");
  if(el){ el.innerText = msg; }
}
```

### MSXML DOM ActiveX Setup Block
**Source:** `fixlet_modifier.ojo` lines 574–579
**Apply to:** Every function in `fixlet_update_tracker.ojo` that creates an MSXML DOM (buildCopyXml, buildSupersededXml, parseCreatedId)

```javascript
var origDoc = new ActiveXObject("Msxml2.DOMDocument.6.0");
origDoc.async            = false;
origDoc.validateOnParse  = false;
origDoc.resolveExternals = false;
origDoc.setProperty("SelectionLanguage", "XPath");
origDoc.loadXML(cleanedXml);
```

**Required:** `setProperty("SelectionLanguage", "XPath")` must appear before any `selectSingleNode` call (Pitfall 4).

### API Status Check (200 or 201)
**Source:** `fixlet_modifier.ojo` line 660, `fixlet_copier.ojo` line 793
**Apply to:** All `API.Post` and `API.Put` success checks in `fixlet_update_tracker.ojo`

```javascript
if(s === 200 || s === 201){  // always check both (Pitfall 6)
  // success
}
```

### Node.js Test Runner Framework
**Source:** `tests/unit/modifier.test.js` lines 130–146
**Apply to:** `tests/unit/update_tracker.test.js`

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
function section(name){ console.log("\n--- Testing " + name + " ---"); }
```

### Integration Test apiRequest Helper
**Source:** `tests/integration/modifier.integration.test.js` lines 65–108
**Apply to:** `tests/integration/update_tracker.integration.test.js` (extend to support POST)

Handles: auth header, `Content-Type: application/xml`, `Content-Length`, `rejectUnauthorized: true`, chunk-based response body assembly.

### BES XML Fixture Skeleton
**Source:** `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` lines 1–29
**Apply to:** All four `tests/fixtures/phase-06/*.xml` files

```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>...</Title>
    <Description><![CDATA[...]]></Description>
    <Relevance>true</Relevance>
    <Category>...</Category>
    <Source>Internal</Source>
    <SourceID></SourceID>
    <SourceReleaseDate>YYYY-MM-DD</SourceReleaseDate>
    <SourceSeverity></SourceSeverity>
    <CVENames></CVENames>
    <SANSID></SANSID>
    <Domain>BESC</Domain>
    <!-- MIMEField blocks go here, before <Domain> is wrong — they go BEFORE Domain per modifier.ojo line 618 -->
    <DefaultAction ID="Action1">...</DefaultAction>
  </Fixlet>
</BES>
```

**Note on MIMEField placement:** Insert MIMEField blocks **before** `<Domain>BESC</Domain>` — this matches the `insertBefore(domainNode)` pattern in `fixlet_modifier.ojo` line 619.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scripts/generate_category_map.js` | utility | batch transform | `scripts/` directory is empty; no existing Node.js build scripts in the project. Planner should use RESEARCH.md Pattern 3 as the implementation template. |

---

## IE9 Compatibility Constraints (apply to all code in `fixlet_update_tracker.ojo`)

These constraints are verified from all 4 existing dashboards and documented in CONTEXT.md:

| Forbidden | Use Instead | Source |
|-----------|-------------|--------|
| `let`, `const` | `var` | All dashboards |
| Arrow functions `() =>` | Named functions `function foo(){}` | All dashboards |
| Template literals `` `${x}` `` | String concatenation `"..." + x` | All dashboards |
| `Array.from()` | `for` loop | All dashboards |
| `fetch()` | `API.Get` / `API.Post` / `API.Put` | All dashboards |
| `querySelector()` | `getElementById()` / `getElementsByTagName()` / `selectSingleNode()` | All dashboards |
| `data[i].split("|||")` (without `String()`) | `String(data[i]).split("|||")` | `fixlet_dispatcher.ojo` line 135 |

---

## Metadata

**Analog search scope:** `Existing Dashboards/`, `tests/unit/`, `tests/integration/`, `tests/fixtures/`
**Files scanned:** 4 dashboards, 2 unit tests, 2 integration tests, 7 fixture files
**Pattern extraction date:** 2026-07-08
