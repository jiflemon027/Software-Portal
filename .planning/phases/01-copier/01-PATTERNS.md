---
document_type: patterns
phase: 1
phase_name: Copier Foundation
created: 2026-06-11
---

# Phase 1: Copier Foundation — Pattern Map

**Mapped:** 2026-06-11
**Files analyzed:** 6 (test fixtures x3, test runner, admin guide, architecture doc, API guide)
**Analogs found:** 6 / 6

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tests/fixtures/phase-01/valid-minimal.ojo` | config | file-I/O | `Existing Dashboards/fixlet_copier.ojo` (BES/Fixlet XML structure) | exact |
| `tests/fixtures/phase-01/valid-with-script.ojo` | config | file-I/O | `Existing Dashboards/fixlet_copier.ojo` (BES/Fixlet XML structure) | exact |
| `tests/fixtures/phase-01/invalid-missing-title.ojo` | config | file-I/O | `Existing Dashboards/fixlet_copier.ojo` (BES/Fixlet XML structure, negative case) | exact |
| `tests/unit/copier.test.js` | test | request-response | `Existing Dashboards/fixlet_modifier.ojo` (same JS helper functions: `xmlEscape`, `getNodeText`, `parseSourceFields`) | role-match |
| `tests/integration/copier.integration.test.js` | test | request-response | `Existing Dashboards/fixlet_copier.ojo` (`API.Get`/`API.Post` call patterns, `createFixlet`, `parseCreatedId`) | exact |
| `docs/admin-guide.md` | utility | — | `Existing Dashboards/fixlet_copier.ojo` (inline `instrBody` ol instructions, lines 817–823) | role-match |
| `docs/architecture.md` | utility | — | `Existing Dashboards/fixlet_copier.ojo` (global state, function call graph, BigFix API paths) | role-match |
| `docs/api-integration-guide.md` | utility | — | `Existing Dashboards/fixlet_copier.ojo` (`API.Get`/`API.Post` calls, path construction, status codes) | exact |

---

## Pattern Assignments

### `tests/fixtures/phase-01/valid-minimal.ojo` (config, file-I/O)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` — `buildXml()` output shape

**BES Fixlet XML skeleton** (copier.ojo lines 673–770):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:noNamespaceSchemaLocation="BES.xsd">
  <Fixlet>
    <Title>Sample Minimal Fixlet</Title>
    <Description><![CDATA[Minimal test fixture.]]></Description>
    <Relevance>true</Relevance>
    <Category></Category>
    <Source>Internal</Source>
    <SourceID></SourceID>
    <SourceReleaseDate>2026-06-11</SourceReleaseDate>
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
      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">
        // placeholder
      </ActionScript>
    </DefaultAction>
  </Fixlet>
</BES>
```

**Notes for planner:** The `buildKnownGoodDefaultAction()` function (copier.ojo lines 606–619) defines the canonical `DefaultAction` XML block. All fixture files must match this structure exactly.

---

### `tests/fixtures/phase-01/valid-with-script.ojo` (config, file-I/O)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` — `parseActions()` and `buildActionInsertion()` (lines 505–646)

**Key field the copier reads** (lines 512–554):
```javascript
// parseActions() expects DefaultAction and/or Action elements
// Each must have an ActionScript child node with text content
var defaults = xml.getElementsByTagName("DefaultAction");
var actions  = xml.getElementsByTagName("Action");
// entry.script = scriptNode[0].text
```

**Fixture must include a real ActionScript block:**
```xml
<DefaultAction ID="Action1">
  <Description>
    <PreLink>Click </PreLink><Link>here</Link>
    <PostLink> to deploy this action.</PostLink>
  </Description>
  <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">
wait msiexec.exe /i "{pathname of regapp "installer.msi"}" /qn
</ActionScript>
</DefaultAction>
```

**Notes for planner:** Also include a multi-action variant with one `DefaultAction` + one `Action` to exercise the `cloneMode = "all"` path in `buildActionInsertion()` (lines 621–646).

---

### `tests/fixtures/phase-01/invalid-missing-title.ojo` (config, file-I/O)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` — `parseSourceFields()` guard for empty `<Title>` (line 677)

**What the copier does with a missing title** (lines 677, 784):
```javascript
// buildXml(): title is taken unconditionally from DOM element
xml += '<Title>' + xmlEscape(document.getElementById("targetTitle").value) + '</Title>';

// createFixlet(): no explicit title-present guard — title will be empty string
// Negative test must assert that an empty/missing Title is caught or produces known bad state
```

**Fixture:** A BES document where `<Title>` is entirely absent or empty. Validates that test assertions can detect the gap.

---

### `tests/unit/copier.test.js` (test, request-response)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` (JavaScript functions) +
`Existing Dashboards/fixlet_modifier.ojo` (same shared utility functions)

**Functions to unit-test** — extracted from copier.ojo:

**1. `xmlEscape(s)` — string escaping** (copier.ojo lines 577–584, modifier.ojo lines 518–525):
```javascript
function xmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;")
    .replace(/'/g,"&apos;");
}
```
Test cases: `&`, `<`, `>`, `"`, `'`, combined string, empty string, non-string input.

**2. `xmlCDataSafe(s)` — CDATA escaping** (copier.ojo line 588):
```javascript
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }
```
Test cases: string containing `]]>`, string without it, empty string.

**3. `buildRelevanceXml(text)` — multi-line relevance builder** (copier.ojo lines 648–658):
```javascript
function buildRelevanceXml(text){
  var lines = String(text).split(/\r?\n/);
  var out = "";
  for(var i=0;i<lines.length;i++){
    if(String(lines[i]).replace(/^\s+|\s+$/g,"")!==""){
      out += "<Relevance>" + xmlEscape(lines[i]) + "</Relevance>";
    }
  }
  if(out===""){ out = "<Relevance>true</Relevance>"; }
  return out;
}
```
Test cases: single line, two lines, empty input (must default to `<Relevance>true</Relevance>`), whitespace-only lines (must be skipped).

**4. `parseCreatedId(body)` — response ID extraction** (copier.ojo lines 365–405):
```javascript
// Tries ActiveXObject XML parse first, then regex fallbacks:
m = /fixlet\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
m = /task\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
m = /\bID=["']?(\d+)["']?/i.exec(body);
```
Test cases: XML body with `<Fixlet ID="123">`, XML body with `Resource` URL, body with URL path only, body with `ID=456`, empty body (must return `""`). **Note:** `ActiveXObject` is IE-only — unit tests must mock/skip that branch and test only the regex fallbacks, or run in IE-compatible environment.

**5. `getNodeText(xml, tag)` / `getAllNodeText(xml, tag)` — XML node readers** (copier.ojo lines 489–503):
```javascript
function getNodeText(xml, tag){
  var n=xml.getElementsByTagName(tag);
  if(n.length>0){ return n[0].text || ""; }
  return "";
}
function getAllNodeText(xml, tag){
  var n=xml.getElementsByTagName(tag);
  var out="";
  for(var i=0;i<n.length;i++){
    if(i>0){ out+="\r\n"; }
    out += (n[i].text || "");
  }
  return out;
}
```
Test cases: tag present once, tag absent (must return `""`), multiple tags (getAllNodeText joins with `\r\n`).

**6. `applySortToCurrentItems()` — sort logic** (copier.ojo lines 76–93):
```javascript
// Numeric sort for col === "id"
na = parseInt(String(a[col] || ""), 10) || 0;
nb = parseInt(String(b[col] || ""), 10) || 0;
// String sort for name/category/siteName
va = String(a[col] || "").toLowerCase();
```
Test cases: sort by `id` ascending/descending (numeric), sort by `name` ascending/descending (lexicographic), mixed-type id values.

**Test file pattern** (copy from modifier.ojo's initDashboard wrapper style for error guard):
```javascript
// copier.ojo line 970 (inline init):
// <script>initDashboard();</script>
// modifier.ojo lines 811-815 (guarded init):
try {
  initDashboard();
} catch(ex){
  alert("Init error: " + (ex.message || ex.description || String(ex)));
}
```
Unit tests should wrap each function call in try/catch and assert on thrown errors for invalid inputs.

---

### `tests/integration/copier.integration.test.js` (test, request-response)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` — `API.Get`, `API.Post`, `createFixlet`, `selectFixlet`

**API.Get pattern** (copier.ojo lines 147–151, 428–440):
```javascript
// Test REST connectivity:
API.Get("sites", function(e,s,b){
  if(s==200){ /* success */ }
  else{ /* failure: check e and s */ }
});

// Load a specific fixlet:
var path = "fixlet/" + encodeURIComponent(siteType) + "/" +
           encodeURIComponent(siteName) + "/" +
           encodeURIComponent(id);
API.Get(path, function(e,s,b){
  if(s==200){ sourceXml = b; }
  else { alert("Load failed: " + e + " status=" + s + " path=" + path); }
});
```

**API.Post pattern** (copier.ojo lines 790–808):
```javascript
path = "fixlets/custom/" + encodeURIComponent(site);
API.Post(path, xml, function(e,s,b){
  if(s==200||s==201){
    newId = parseCreatedId(b);
    // assert newId is non-empty string
    // assert fixlet now appears in site via subsequent API.Get
  } else {
    // assert status code and error message captured
  }
});
```

**Integration test scenarios to cover:**
1. `API.Get("sites")` returns HTTP 200 (connectivity check)
2. Load a known test fixlet from source site → assert `sourceXml` non-empty, `targetTitle` populated
3. `createFixlet()` with valid fixture → assert HTTP 201/200, `newId` non-empty, fixlet appears in `Dereso Software Portal`
4. `createFixlet()` with empty `targetSite` → assert guard fires before API call (`alert("Enter a target custom site.")`)
5. `createFixlet()` with no source selected → assert guard fires (`alert("Select a source Fixlet first.")`)
6. `createFixlet()` with no actions in source → assert guard fires (`alert("No actions available.")`)
7. BigFix API error (simulate 500) → assert error message displayed in status bar

**Environment variables required** (from RESEARCH.md):
```
BIGFIX_URL   — base URL of test BigFix instance
BIGFIX_USER  — admin username
BIGFIX_TOKEN — admin password or API token
```

---

### `docs/admin-guide.md` (utility, documentation)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` — inline how-to instructions (lines 817–823)

**Existing inline instructions** (lines 817–823 of copier.ojo, the `instrBody` `<ol>`):
```html
<ol>
  <li><b>Load Fixlets</b> — Click Load Fixlets to retrieve all fixlets visible in your console.
      Use the Sites list to narrow by site (Ctrl+click for multiple)
      and the Search box to filter by name, ID, category, or severity.</li>
  <li><b>Select a source fixlet</b> — Click the radio button on any row.
      The fixlet's XML, title, category, and actions are loaded automatically.</li>
  <li><b>Review &amp; edit</b> — Adjust the Title and Category fields as needed.
      Select the action script you want to clone from the action list,
      and edit the ActionScript if required.</li>
  <li><b>Choose a clone mode</b> — Single Action creates one DefaultAction from the selected
      script. Full Copy preserves all actions, promoting the selected one to DefaultAction.</li>
  <li><b>Choose a target site</b> — Select the custom site the new fixlet will be created in.</li>
  <li><b>Clone</b> — Click Clone Selected Fixlet. The new fixlet ID will be shown in the
      status bar on success.</li>
</ol>
```

**Admin guide must expand on each step**, adding:
- Pre-requisites section: "Dereso Software Portal" custom site must exist; BigFix admin auth required
- Screenshots/diagrams of each panel (Filter, Table, Edit, Actions)
- Troubleshooting: "Test REST" button usage, common HTTP error codes (401, 404, 500) and remediation
- Clone mode comparison table (Single Action vs Full Copy)
- Success indicators: status bar message + new Fixlet ID display

---

### `docs/architecture.md` (utility, documentation)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` — global state variables (lines 42–56), function call graph, data flow

**Global state to document** (copier.ojo lines 42–56):
```javascript
var currentItems = [];       // filtered/sorted fixlet list for current page
var currentItem = null;      // the one selected fixlet object
var sourceXml = "";          // raw XML of selected fixlet from API
var parsedActions = [];      // array of {kind, xml, script, title} from parseActions()
var selectedActionIndex = 0; // which action is active in the editor
var lastCreatedId = "";      // ID returned by BigFix after POST
var lastCreatedSite = "";    // site used in the last create
var currentPage = 0;         // pagination cursor
var allItems = [];           // full unfiltered fixlet list from EvaluateRelevance
var searchTimer = null;      // debounce timer handle for search input
var sourceMimeFields = [];   // MIME fields extracted from selected fixlet
var sortColumn = "";         // active sort column name
var sortAsc = true;          // sort direction
var selectedItemIndex = -1;  // index within currentItems of selected row
```

**Data flow to document:**
1. `initDashboard()` → `loadSitenames()` (EvaluateRelevance fills site dropdowns)
2. "Load Fixlets" button → `loadAllFixlets()` (EvaluateRelevance fills `allItems`) → `filterAndRender()`
3. User clicks radio → `selectFixlet(i)` → `API.Get(path)` → `parseSourceFields(b)` + `parseActions(b)`
4. User clicks "Clone" → `createFixlet()` → validates guards → `buildXml()` → `API.Post(path, xml)` → `parseCreatedId(b)` → `updateCreatedInfo()`
5. `buildXml()` internal flow: collects form fields → `buildActionInsertion()` → assembles BES/Fixlet XML string

**BigFix API surface to document:**
```
GET  fixlet/{siteType}/{siteName}/{id}        — fetch fixlet XML
GET  sites                                    — connectivity test
POST fixlets/custom/{siteName}                — create new fixlet in custom site
```

**Authentication:** Handled transparently by BigFix console's `API` object (no explicit auth code in dashboard). Admin must be logged into BigFix console.

**XML building strategy** (copier.ojo lines 586–588, 660–668):
```javascript
// CDATA content (Description, ActionScript):
function cdataStart(){ return '<!' + '[CDATA['; }  // split to avoid XML parser issues
function cdataEnd(){ return ']]' + '>'; }
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }

// Escaped content (Title, Category, etc.):
function addNode(xml, tag, value, useCdata){ ... }
```

---

### `docs/api-integration-guide.md` (utility, documentation)

**Analog:** `Existing Dashboards/fixlet_copier.ojo` — all `API.*` call sites

**API object (BigFix console built-in)** — three methods used:
```javascript
API.Get(relativePath, callback(errorMsg, statusCode, responseBody))
API.Post(relativePath, bodyXml, callback(errorMsg, statusCode, responseBody))
// (modifier.ojo also uses:)
API.Put(relativePath, bodyXml, callback(errorMsg, statusCode, responseBody))
```

**Endpoint reference extracted from copier.ojo:**

| Method | Path | Purpose | Success Codes |
|--------|------|---------|---------------|
| `GET`  | `sites` | Test API connectivity | 200 |
| `GET`  | `fixlet/{siteType}/{siteName}/{id}` | Fetch source fixlet XML | 200 |
| `POST` | `fixlets/custom/{siteName}` | Create fixlet in custom site | 200, 201 |

**Path construction pattern** (copier.ojo lines 426–427, 790):
```javascript
// GET a specific fixlet:
var path = "fixlet/" + encodeURIComponent(currentItem.siteType) + "/" +
           encodeURIComponent(currentItem.siteName) + "/" +
           encodeURIComponent(currentItem.id);

// POST to create:
path = "fixlets/custom/" + encodeURIComponent(site);
```

**Response handling pattern** (copier.ojo lines 792–807):
```javascript
API.Post(path, xml, function(e, s, b){
  if(s == 200 || s == 201){
    // success: b contains response XML with new fixlet ID
    newId = parseCreatedId(b);
  } else {
    // failure: e = error description, s = HTTP status, b = response body
    alert("Failed: status=" + s + " error=" + e + " path=" + path + " response=" + b);
    setStatus("Failed via " + path + " status=" + s);
  }
});
```

**Response ID parsing** (copier.ojo lines 365–405) — three fallback strategies:
```javascript
// 1. Parse XML response body (Msxml2.DOMDocument.6.0 — IE/ActiveX only)
nodes = xml.getElementsByTagName("Fixlet");
txt = nodes[0].getAttribute("ID");            // try ID attribute
txt = nodes[0].getAttribute("Resource");      // try Resource URL

// 2. URL path regex fallbacks (plain string, no DOM required):
m = /fixlet\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
m = /task\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);

// 3. Attribute regex:
m = /\bID=["']?(\d+)["']?/i.exec(body);

// Returns "" if all strategies fail — caller should handle empty string
```

**EvaluateRelevance pattern** (copier.ojo lines 154, 192) — fetches data from BigFix relevance engine:
```javascript
// Returns array of strings; each element is one result row
var rel  = '(name of it & "|||" & "External") of bes sites';
var data = EvaluateRelevance(rel);
// Split on delimiter:
p = String(data[i]).split("|||");
```
The `|||` delimiter is the project convention for multi-field relevance results. All relevance queries use this pattern.

---

## Shared Patterns

### BigFix API Call Pattern
**Source:** `Existing Dashboards/fixlet_copier.ojo`, lines 428–440 and 792–808
**Apply to:** All integration tests; API Integration Guide
```javascript
API.Get(path, function(e, s, b){
  if(s == 200){
    // success path
  } else {
    alert("Load failed: " + e + " status=" + s + " path=" + path);
    setStatus("Load failed: " + e + " status=" + s);
  }
});
```

### Input Guard Pattern
**Source:** `Existing Dashboards/fixlet_copier.ojo`, lines 783–787
**Apply to:** All integration test negative cases
```javascript
if(sourceXml === ""){ alert("Select a source Fixlet first."); return; }
if(site === "")      { alert("Enter a target custom site."); return; }
if(parsedActions.length === 0){ alert("No actions available."); return; }
```
Every mutating operation checks preconditions and returns early. Tests must verify these guards trigger before any API call is made.

### Status Bar Feedback Pattern
**Source:** `Existing Dashboards/fixlet_copier.ojo`, lines 117–119
**Apply to:** All integration tests (assert status bar text after each operation)
```javascript
function setStatus(msg){
  var el = document.getElementById("status");
  if(el){ el.innerHTML = msg; }
}
```

### XML Safety Pattern (CDATA + entity escaping)
**Source:** `Existing Dashboards/fixlet_copier.ojo`, lines 577–588 (shared verbatim in modifier.ojo lines 518–529)
**Apply to:** All unit tests for XML-building functions; Architecture Doc
```javascript
function xmlEscape(s){ ... }          // entity-escape attribute/text content
function cdataStart(){ return '<!' + '[CDATA['; }  // split string avoids parser eating it
function cdataEnd(){   return ']]' + '>'; }
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }
```

### EvaluateRelevance Delimiter Convention
**Source:** `Existing Dashboards/fixlet_copier.ojo`, line 192; `fixlet_modifier.ojo`, lines 131–136
**Apply to:** Architecture Doc; any future relevance queries in tests
```javascript
// Multi-field rows separated by "|||"
var rel = '(field1 & "|||" & field2 & "|||" & field3) of bes fixlets';
var data = EvaluateRelevance(rel);
p = String(data[i]).split("|||");
// p[0] = field1, p[1] = field2, p[2] = field3
```

---

## No Analog Found

All deliverables for Phase 1 have close analogs in the two existing `.ojo` files. No files lack a pattern source.

---

## Metadata

**Analog search scope:** `Existing Dashboards/` (2 files)
**Files scanned:** 2 (`fixlet_copier.ojo`, `fixlet_modifier.ojo`)
**Pattern extraction date:** 2026-06-11
