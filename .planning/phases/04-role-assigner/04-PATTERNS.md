# Phase 4: Role Assigner Dashboard — Pattern Map

**Mapped:** 2026-06-27
**Files analyzed:** 7 (1 new .ojo, 1 modified .bes, 3 new test files, 4 new fixture CSVs)
**Analogs found:** 7 / 7

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Existing Dashboards/fixlet_role_assigner.ojo` | dashboard (controller + view) | request-response + CRUD | `Existing Dashboards/fixlet_dispatcher.ojo` | exact |
| `Dashboard_4_samples/Dereso SWD.bes` | config/data (Analysis) | CRUD (read) | `Dashboard_4_samples/Init  Current User and UserRole DB.bes` | role-match |
| `tests/unit/role_assigner.test.js` | test | batch (pure-JS unit) | `tests/unit/dispatcher.test.js` | exact |
| `tests/integration/role_assigner.integration.test.js` | test | request-response | `tests/integration/dispatcher.integration.test.js` | exact |
| `tests/fixtures/phase-04/sample.csv` | fixture | — | `Dashboard_4_samples/role_targeting.csv` | exact |
| `tests/fixtures/phase-04/invalid-unknown-role.csv` | fixture | — | `tests/fixtures/phase-03/sample-action-response.xml` | partial (fixture pattern) |
| `tests/fixtures/phase-04/duplicate-rows.csv` | fixture | — | `Dashboard_4_samples/role_targeting.csv` | exact |

---

## Pattern Assignments

### `Existing Dashboards/fixlet_role_assigner.ojo` (dashboard, request-response + CRUD)

**Analog:** `Existing Dashboards/fixlet_dispatcher.ojo`

**OJO outer shell pattern** (lines 1-11, 807-968):
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
Change: set `<Title>` to `Dereso Role Assigner`. Keep `RequiresAuthoring="false"` and `Menu="Dashboards"` verbatim.

**CSS pattern** (lines 13-32):
```css
body { font-family: Arial; font-size: 11px; background: #f3f3f3; margin: 0; padding: 0; }
.page { padding: 16px; }
h1 { color: #2a5d9f; font-size: 24px; margin: 0 0 18px 0; font-weight: bold; }
.panel { background: #ffffff; border: 1px solid #d7dbe0; margin-bottom: 14px; }
.panelBody { padding: 12px; }
.rowTable { width: 100%; border-collapse: collapse; }
.rowTable td { padding: 6px 8px; vertical-align: middle; border: none; }
.lbl { font-weight: bold; color: #333333; white-space: nowrap; }
.btn { font-family: Arial; font-size: 11px; padding: 6px 14px; border: 1px solid #b3b3b3; background: #f7f7f7; cursor: pointer; }
.btnGreen { font-family: Arial; font-size: 11px; padding: 8px 18px; border: 1px solid #237241; background: #33a05a; color: #ffffff; font-weight: bold; cursor: pointer; }
.tableGrid { width: 100%; border-collapse: collapse; background: #ffffff; }
.tableGrid td, .tableGrid th { border: 1px solid #d7dbe0; padding: 6px 8px; vertical-align: middle; }
.tableGrid th { background: #f4f6f8; color: #2a5d9f; text-align: left; }
.small { color: #666666; font-size: 10px; }
```
Copy verbatim. Add Phase 4 additions: `.warn { color: #996600; }`, `.error-row { background: #fff0f0; }`, `.warn-row { background: #fffbe6; }`.

**PORTAL_CONFIG pattern** (lines 38-43 of dispatcher vs D-19):
```javascript
// ==========================================================================
// PORTAL CONFIGURATION -- Edit this block to change roles and target groups.
// Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
    targetGroups: [
        'All Workstations',
        'IT Department',
        'Finance Department',
        'All Servers'
    ],
    roles: [
        'IT Operations',
        'Finance',
        'HR'
        // Update this list when management changes role definitions.
        // Must match PORTAL_CONFIG.roles in fixlet_modifier.ojo.
    ],
    actionNamePrefix: 'Dereso'
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```
Note: dispatcher has only `defaultExpirationDays`; modifier has `roles[]` and `categories[]`. Role Assigner combines `targetGroups` (from dispatcher) + `roles[]` (from modifier) + adds `actionNamePrefix`.

**htmlEscape + setStatus pattern** (lines 69-81):
```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}

function setStatus(msg){
  var el = document.getElementById("status");
  if(el){ el.innerText = msg; }
}
```
Copy verbatim. Use `htmlEscape()` on ALL CSV-derived values before writing to `innerHTML`.

**XML helper functions pattern** (lines 266-277):
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
Copy verbatim. These are shared with dispatcher and modifier — do not modify.

**buildTargetRelevance pattern** (lines 285-300):
```javascript
function buildTargetRelevance(group){
  if(!group){ return "true"; }
  var id       = group.id;
  var name     = group.name;
  var site     = (group.siteName || "").toLowerCase();
  var type     = group.groupType || "Automatic";
  var safeName = String(name).replace(/"/g, '""');
  var safeSite = site.replace(/"/g, '""');
  if(type === "Manual"){
    return 'exists true whose (if true then (exists setting "__Group_0_' + safeName + '" whose (value of it is "True") of client) else false)';
  }
  if(type === "Server Based"){
    return 'exists true whose (if true then (exists setting "__Group_1_' + safeName + '" whose (value of it is "True") of client) else false)';
  }
  return 'exists true whose (if true then (member of group ' + id + ' of site whose (name of it as lowercase = "' + safeSite + '" as lowercase)) else false)';
}
```
Copy verbatim. Used for the DB-existence relevance guard in the generated SingleAction `<Relevance>` element. Note: for Role Assigner the `<Target>` uses explicit `<ComputerID>` elements (not `<CustomRelevance>`), but the `<Relevance>` client-side guard still uses this pattern (DB-existence relevance from RESEARCH.md Pattern 3).

**parseActionId pattern** (lines 303-323):
```javascript
function parseActionId(body){
  var m;
  if(!body){ return ""; }
  try {
    var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
    xml.async = false;
    xml.loadXML(body);
    var nodes = xml.getElementsByTagName("Action");
    if(nodes.length > 0){
      var idNode = nodes[0].selectSingleNode("ID");
      if(idNode && idNode.text){ return idNode.text; }
      var res = nodes[0].getAttribute("Resource");
      if(res){ var rm = /\/(\d+)$/.exec(res); if(rm && rm[1]){ return rm[1]; } }
    }
  } catch(ex) {}
  m = /\/api\/action\/(\d+)/i.exec(body);
  if(m && m[1]){ return m[1]; }
  m = /<ID>(\d+)<\/ID>/i.exec(body);
  if(m && m[1]){ return m[1]; }
  return "";
}
```
Copy verbatim. Used in the post-deploy success banner to display action IDs (D-16).

**Group selector (loadGroups + renderGroupSelect) pattern** (lines 539-615):
```javascript
function loadGroups(){
  // ...
  var rel = '(id of it as string & "|||" & name of it & "|||" & name of (site of it) & "|||" & (if (server based flag of it) then "Server Based" else if (automatic flag of it) then "Automatic" else "Manual")) of bes computer groups';
  var data = EvaluateRelevance(rel);
  // push to allGroups, sort, render
}
function renderGroupSelect(){
  var sel = document.getElementById("targetGroupSelect");
  // ... options from currentGroups
}
```
Copy structure verbatim. In Role Assigner the group selector is informational only (D-12) — no filtering of computer IDs occurs on selection. Wire `onchange` to update the suffix default (D-09) but do NOT filter the CSV preview.

**API.Post + success banner pattern** (lines 747-772):
```javascript
API.Post("actions", xml, function(e, s, b){
  if(s === 200 || s === 201){
    var bodyText  = (typeof b !== "undefined" && b !== null) ? String(b) : "";
    var actionIdR = parseActionId(bodyText);
    setStatus("Deployed successfully.");
    if(resultEl){
      resultEl.style.display = "";
      while(resultEl.firstChild){ resultEl.removeChild(resultEl.firstChild); }
      var strong = document.createElement("b");
      strong.appendChild(document.createTextNode("Deployed."));
      resultEl.appendChild(strong);
      resultEl.appendChild(document.createTextNode(" Action ID: " + (actionIdR || "(unknown)") + "   "));
      // ... Deploy Another button
    }
  } else {
    setStatus("Deploy failed: status=" + s);
    if(errEl){
      errEl.style.display = "";
      errEl.innerHTML = htmlEscape("Deploy failed: status=" + s + " — " + (e || ""));
    }
  }
});
```
Copy the callback structure verbatim. For Role Assigner, fire one `API.Post` call per role (D-01). Show one banner per role. Use sequential dispatch (wait for callback before next `API.Post`). Show a per-role progress indicator ("Deploying role 2 of 3...").

**Error and result div pattern** (lines 948-951 HTML):
```html
<div id="deployError" style="color:#cc0000; margin-top:8px; display:none;"></div>
<div id="deployResult" style="color:#237241; margin-top:8px; display:none;"></div>
```
Copy pattern. Add one error/result div pair per role, or a dynamic container that appends banner divs. No `alert()` calls — inline feedback only.

**initDashboard + inline script pattern** (lines 100-106, 955-961 HTML):
```javascript
function initDashboard(){
  setStatus("Ready.");
  loadGroups();
  // Role Assigner: also call loadAnalysisView() here
}
```
```html
<script>
try {
  initDashboard();
} catch(ex){
  alert("Init error: " + (ex.message || ex.description || String(ex)));
}
</script>
```
Copy verbatim. Add `loadAnalysisView()` call at end of `initDashboard()`.

**Phase 4 new functions** (no direct analog — derive from RESEARCH.md patterns):
- `parseCsv(text)` — RESEARCH.md Pattern 5
- `validateRows(rows, allowedRoles)` — RESEARCH.md Pattern 5
- `encodeMatrix(computers, users)` / `safeB64Encode(str)` — RESEARCH.md Pattern 1 + Pitfall 1
- `chunkString(s, size)` / `buildChunkParams(b64)` — RESEARCH.md Pattern 1
- `buildAssignActionXml(role, computerIds, chunkParams, suffix, targetRelevance)` — RESEARCH.md Pattern 4
- `buildAssignActionScript(role, chunkParams)` — RESEARCH.md Pattern 3
- `loadAnalysisView()` — RESEARCH.md Pattern 6
- `handleFileUpload(input)` — RESEARCH.md Pitfall 4 (FileReader + textarea fallback)
- `deployAll()` — sequential `API.Post` loop with per-role progress

---

### `Dashboard_4_samples/Dereso SWD.bes` (config/data, CRUD read — MODIFY)

**Analog:** `Dashboard_4_samples/Init  Current User and UserRole DB.bes` (ActionScript structure), self-reference for BES Analysis format.

**Current state** (lines 1-19, already read in full):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="..." xsi:noNamespaceSchemaLocation="BES.xsd">
  <Analysis>
    <Title>Dereso SWD</Title>
    <Description><![CDATA[<enter a description of the analysis here> ]]></Description>
    <Relevance>...RoleAwareness.db existence check...</Relevance>
    <Source>Internal</Source>
    <SourceReleaseDate>2026-06-24</SourceReleaseDate>
    ...
    <Property Name="Roles in r.db" ID="1" EvaluationPeriod="PT5M">...</Property>
    <Property Name="users in r.db" ID="2" EvaluationPeriod="PT5M">...</Property>
    <Property Name="mapped_users in r.db" ID="3" EvaluationPeriod="PT5M">...</Property>
    <Property Name="recent users" ID="4" EvaluationPeriod="PT1H">...</Property>
  </Analysis>
</BES>
```

**Only change required** (line 5):
```xml
<!-- BEFORE -->
<Description><![CDATA[<enter a description of the analysis here> ]]></Description>

<!-- AFTER -->
<Description><![CDATA[<P>Dereso Role Awareness Analysis. Reads from RoleAwareness.db on
reporting clients to surface role-to-user mappings, active roles, and recently-seen users.
Import this Analysis before using the Role Assigner dashboard. Evaluates every 5 minutes.</P>]]></Description>
```
No SQL changes needed — all column references verified correct against `Initialize-RoleDb.ps1` DDL (RESEARCH.md Pattern 7).

**Relevance expression** (line 6 of BES — also used verbatim in generated action's `<Relevance>` guard per D-02):
```
(exists folder it whose (exists files "RoleAwareness.db" whose (exists sqlite database of it) of it)) of
((concatenation (if windows of operating system then "\" else "/") of
  ((item 0 of it;item 1 of it;item 2 of it) of
    ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal"))))
```
Copy this verbatim into generated SingleAction's `<Relevance>` element (D-02 double guard).

---

### `tests/unit/role_assigner.test.js` (test, batch pure-JS)

**Analog:** `tests/unit/dispatcher.test.js` (full file read above)

**File header pattern** (lines 1-26):
```javascript
/**
 * role_assigner.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_role_assigner.ojo
 *
 * Functions covered:
 *   1. parseCsv(text)
 *   2. validateRows(rows, allowedRoles)
 *   3. encodeMatrix(computers, users) / safeB64Encode(str)
 *   4. chunkString(s, size)
 *   5. buildChunkParams(b64)
 *   6. xmlEscape(s)
 *   7. xmlCDataSafe(s)
 *   8. buildAssignActionXml(role, computerIds, chunkParams, suffix, rel)
 *   9. PORTAL_CONFIG validation
 *
 * Running: node tests/unit/role_assigner.test.js
 * Requirements: Node.js built-in `assert` and `fs` modules only.
 */

"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");
```

**Test infrastructure pattern** (lines 113-129 of dispatcher.test.js):
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
Copy verbatim. Use `expect()` + `section()` (not `runTest()` from integration test — those are for async).

**Summary footer pattern** (lines 250-261):
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
Copy verbatim.

**PORTAL_CONFIG test pattern** (lines 233-245):
```javascript
section("PORTAL_CONFIG");

expect("PORTAL_CONFIG.roles is a non-empty array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.roles), "Expected roles to be an array");
  assert.ok(PORTAL_CONFIG.roles.length > 0, "Expected at least one role");
});
expect("PORTAL_CONFIG.actionNamePrefix is 'Dereso'", function(){
  assert.strictEqual(PORTAL_CONFIG.actionNamePrefix, 'Dereso');
});
expect("PORTAL_CONFIG.targetGroups is an array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.targetGroups));
});
```

**Function extraction pattern** (lines 27-107 — functions copied verbatim from .ojo, then tested):
```javascript
// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from fixlet_role_assigner.ojo)
// ---------------------------------------------------------------------------

// xmlEscape — copy verbatim from fixlet_dispatcher.ojo (same function)
function xmlEscape(s){ ... }

// xmlCDataSafe — copy verbatim
function xmlCDataSafe(s){ ... }

// parseCsv — copy from role_assigner.ojo implementation
function parseCsv(text){ ... }

// validateRows — copy from role_assigner.ojo implementation
function validateRows(rows, allowedRoles){ ... }

// safeB64Encode — use Buffer.from().toString('base64') in Node (btoa not available)
function safeB64Encode(str){
  // In Node.js: Buffer.from(str, 'utf8').toString('base64')
  // In browser: btoa(unescape(encodeURIComponent(str)))
  // Test uses Node path; dashboard uses browser path.
  return Buffer.from(str, 'utf8').toString('base64');
}

// chunkString, buildChunkParams, buildAssignActionXml — copy from role_assigner.ojo
```
Note: `buildDeployXml()` in dispatcher.test.js is NOT tested (uses `ActiveXObject`). Same constraint applies: `buildAssignActionXml()` can be tested in Node because it only builds a string (no DOM). Test it.

**Fixture loading pattern** (Phase 4 addition — no direct analog, but follows `fs.readFileSync` convention):
```javascript
var FIXTURE_DIR = path.join(__dirname, '..', 'fixtures', 'phase-04');

section("parseCsv — fixture files");

expect("sample.csv parses to 4 data rows", function(){
  var text = fs.readFileSync(path.join(FIXTURE_DIR, 'sample.csv'), 'utf8');
  var result = parseCsv(text);
  assert.ok(result.rows, "Expected rows property");
  assert.strictEqual(result.rows.length, 4);
});
```

---

### `tests/integration/role_assigner.integration.test.js` (test, request-response)

**Analog:** `tests/integration/dispatcher.integration.test.js` (full file read above)

**Environment guard pattern** (lines 34-41):
```javascript
var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: BIGFIX_URL, BIGFIX_USER, and BIGFIX_TOKEN must all be set to run integration tests.");
  process.exit(0);
}
```
Copy verbatim. Same env var names as dispatcher integration test.

**apiRequest helper pattern** (lines 66-114):
```javascript
function apiRequest(method, relativePath, bodyXml, callback) {
  var parsed = new URL(BIGFIX_URL);
  var authHeader = "Basic " + Buffer.from(BIGFIX_USER + ":" + BIGFIX_TOKEN).toString("base64");
  var apiPath = "/api/" + relativePath;
  var requestOptions = {
    hostname: parsed.hostname,
    port:     parsed.port || 52311,
    path:     apiPath,
    method:   method,
    headers:  { "Authorization": authHeader, "Accept": "application/xml" },
    rejectUnauthorized: true,
    timeout: 10000
  };
  if ((method === "PUT" || method === "POST") && bodyXml) {
    var bodyBuffer = Buffer.from(bodyXml, "utf8");
    requestOptions.headers["Content-Type"]   = "application/xml";
    requestOptions.headers["Content-Length"] = bodyBuffer.length;
  }
  // ... https.request + callbacks
}
```
Copy verbatim.

**runAsyncTest + promise chain pattern** (lines 182-199, 403-427):
```javascript
function runAsyncTest(name, fn) {
  return new Promise(function(resolve) {
    fn(function(err) {
      if (err && err.isSkip) { skipped++; }
      else if (err) { failed++; failures.push(...); }
      else { passed++; }
      resolve();
    });
  });
}

// Chain:
runAsyncTest("Test 1: ...", test1)
  .then(function(){ return runAsyncTest("Test 2: ...", test2); })
  .then(function(){ ... process.exit(failed > 0 ? 1 : 0); });
```

**Phase 4 specific tests** (replace dispatcher tests with role assigner tests):

- Test 1: API connectivity — identical to dispatcher (copy `test1_apiConnectivity` verbatim)
- Test 2: POST minimal SingleAction with `<ComputerID>` targeting — build XML inline using `buildAssignActionXml()` logic; assert HTTP 200 or 201
- Test 3: parseActionId on response — assert non-empty string returned
- Test 4: Input guard — no CSV uploaded (synchronous; guard: `if(!csvRows || csvRows.length === 0) return;`)
- Test 5: API error handling — identical to dispatcher Test 6 (copy verbatim)

**skipTest pattern** (lines 175-179):
```javascript
function skipTest(reason) {
  var err = new Error(reason);
  err.isSkip = true;
  throw err;
}
```
Copy verbatim. Use for optional env vars (`TEST_COMPUTER_ID` for explicit targeting test).

---

### `tests/fixtures/phase-04/*.csv` (fixtures)

**Analog:** `Dashboard_4_samples/role_targeting.csv` for column format; `tests/fixtures/phase-03/sample-action-response.xml` for fixture file convention.

**Column format** (from role_targeting.csv, line 1):
```
user,computer,role
```
Phase 4 renames `computer` to `Computer_ID` (D-10). Header must be exactly:
```
user,Computer_ID,role
```

**sample.csv** — valid 3-role CSV (one row per role minimum, multiple rows per role):
```csv
user,Computer_ID,role
jsmith,100001,IT Operations
jsmith,100002,Finance
bdoe,100001,IT Operations
adavis,100003,HR
```
(4 data rows, 2 roles with 2 computers each for IT Operations, 1 Finance, 1 HR)

**invalid-unknown-role.csv** — triggers BLOCK validation (unknown role):
```csv
user,Computer_ID,role
jsmith,100001,IT Operations
bdoe,100002,SuperAdmin
```
Row 3: `SuperAdmin` is not in `PORTAL_CONFIG.roles` — must block deploy.

**invalid-blank-fields.csv** — triggers BLOCK validation (blank user, blank Computer_ID):
```csv
user,Computer_ID,role
,100001,IT Operations
jsmith,,Finance
jsmith,100003,HR
```
Row 2: blank user. Row 3: blank Computer_ID. Both block deploy.

**duplicate-rows.csv** — triggers WARN validation only (deploy allowed):
```csv
user,Computer_ID,role
jsmith,100001,IT Operations
jsmith,100001,IT Operations
bdoe,100002,Finance
```
Rows 2+3 are duplicates — warn only, deploy button stays enabled.

---

## Shared Patterns

### IE9 Compatibility
**Source:** `Existing Dashboards/fixlet_dispatcher.ojo` lines 11, 307, 548
**Apply to:** `fixlet_role_assigner.ojo` — all JS and HTML
```html
<meta http-equiv="X-UA-Compatible" content="IE=9">
```
```javascript
// XML parsing — only via ActiveXObject
var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
xml.async = false;
xml.loadXML(body);
```
```javascript
// Group loading — EvaluateRelevance (local data)
var data = EvaluateRelevance(rel);
// Analysis data — GetRelevance (remote client data)
var data = GetRelevance(rel);
```
Critical distinction: `EvaluateRelevance` for group lists (local console data); `GetRelevance` for Analysis properties (remote client data). Never swap them.

### XSS Prevention
**Source:** `Existing Dashboards/fixlet_dispatcher.ojo` lines 69-75, 197-204
**Apply to:** `fixlet_role_assigner.ojo` — every CSV-derived value written to DOM
```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}
// Usage pattern:
r.insertCell(-1).innerHTML = htmlEscape(item.name);
// NEVER: r.insertCell(-1).innerHTML = item.name;  // XSS risk
```
Apply `htmlEscape()` to every value from CSV (user, Computer_ID, role) before writing to `innerHTML`.

### ActionScript prefetch block (verbatim SHA hashes)
**Source:** `Dashboard_4_samples/Init  Current User and UserRole DB.bes` lines 38-41
**Apply to:** Generated ActionScript in `buildAssignActionScript()`
```
begin prefetch block
  add prefetch item name=unzip.exe sha1=e1652b058195db3f5f754b7ab430652ae04a50b8 size=167936 url=http://software.bigfix.com/download/redist/unzip-5.52.exe sha256=8d9b5190aace52a1db1ac73a65ee9999c329157c8e88f61a772433323d6b7a4a
  add prefetch item name=sqlite-tools-win-x64-3530100.zip sha1=184d4d0b75cd75c2118fb22a1727e9220f843b98 size=6511283  url=http://127.0.0.1:{maximum of ...}/Uploads/CustomRepository/sqlite_util/sqlite-tools-win-x64-3530100.zip sha256=bcc88a2f9ebcf3d90b7a95337cc96bd492b1633f741bbdbff0525d1806098fc2
  add prefetch item name=SQLite_dlls.zip sha1=bac30af87ccf0a091abd4de07770cc58efa6118d size=1963877 url=http://127.0.0.1:{maximum of ...}/Uploads/CustomRepository/sqlite_util/SQLite_dlls.zip sha256=e16a8d724f4f2e575b9bb7c9d79f5d47c255b30c06cbe6e70b9625aca1fff2ae
end prefetch block
```
Copy SHA1, SHA256, and size values verbatim. The URL pattern (port detection via registry) must also be copied verbatim from lines 39-40 of the Init BES.

### ActionScript directory parameter block (verbatim)
**Source:** `Dashboard_4_samples/Init  Current User and UserRole DB.bes` lines 44-48
**Apply to:** Generated ActionScript in `buildAssignActionScript()`
```
parameter "RootDir"="{ (pathname of parent folder of parent folder of client folder of site "actionsite") as string}"
parameter "ECDir"="{(concatenation (if windows of operating system then "\" else "/") of ( (item 0 of it;item 1 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC")))}"
parameter "SWPDir"="{(concatenation (if windows of operating system then "\" else "/") of ( (item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal")))}"
parameter "TargetStore"="{(concatenation (if windows of operating system then "\" else "/") of ( (item 0 of it; item 1 of it; item 2 of it; item 3 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal","RoleAwareness.db"))) }"
parameter "SQLiteDir"="{(concatenation (if windows of operating system then "\" else "/") of ( (item 0 of it; item 1 of it; item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","sqlite"))) }"
```
Copy verbatim. Then add Phase 4 specific parameters after these five:
```
parameter "CompID"="{id of computer}"
parameter "Role"="<role value from JS — xmlEscape'd>"
parameter "chunkCount"="<N>"
parameter "chunk0"="<B64 chunk 0>"
parameter "chunk1"="<B64 chunk 1>"
...
```

### ActionScript directory preparation + createfile pattern (verbatim)
**Source:** `Dashboard_4_samples/Init  Current User and UserRole DB.bes` lines 52-88
**Apply to:** Generated ActionScript in `buildAssignActionScript()`
```
if {not exists folder ((parameter "ECDir") as string)}
    runhidden cmd /c mkdir "{parameter "ECDir"}"
endif

if {not exists folder ((parameter "SWPDir") as string)}
    runhidden cmd /c mkdir "{parameter "SWPDir"}"
endif

if { ( exists (folder (parameter "SQLiteDir")) whose (number of files whose (name of it = "System.Data.SQLite.dll") of folders of it < 2) ) }
    folder delete "{(parameter "SQLiteDir")}"
    runhidden cmd /c mkdir "{parameter "SQLiteDir"}"
    utility __Download\unzip.exe
    folder create "{parameter "SQLiteDir"}"
    waithidden __Download\unzip.exe -o "{ download path "sqlite-tools-win-x64-3530100.zip" }"  -d "{parameter "SQLiteDir"}"
    waithidden __Download\unzip.exe -o "{ download path "SQLite_dlls.zip" }"  -d "{parameter "SQLiteDir"}"
endif

delete __createfile
delete "{parameter "SWPDir"}\Assign-RoleMapping.ps1"

createfile until _EOF_
[PowerShell script embedded here]
_EOF_

move __createfile "{parameter "SWPDir"}\Assign-RoleMapping.ps1"

action uses wow64 redirection {x64 of operating system}
waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "{parameter "SWPDir"}\Assign-RoleMapping.ps1" -DatabasePath "{parameter "TargetStore"}" -SQLDir "{parameter "SQLiteDir"}" -CompID "{parameter "CompID"}" -Role "{parameter "Role"}" -ChunkCount "{parameter "chunkCount"}" -chunk0 "{parameter "chunk0"}" -chunk1 "{parameter "chunk1"}"
```
The `waithidden` line must pass each chunk as a separate named parameter. For variable chunk counts, build the `-chunkN "{parameter "chunkN"}"` portion dynamically in the JS string builder.

### BES Analysis `<Description>` replacement
**Source:** `Dashboard_4_samples/Dereso SWD.bes` line 5 (MODIFY ONLY)
**Apply to:** `Dashboard_4_samples/Dereso SWD.bes`
The only edit: replace the `<enter a description...>` placeholder with production text. All SQL and relevance expressions are correct as-is.

### Node.js unit test `require` pattern
**Source:** `tests/unit/dispatcher.test.js` lines 24, `tests/integration/dispatcher.integration.test.js` lines 47-50
**Apply to:** `tests/unit/role_assigner.test.js`, `tests/integration/role_assigner.integration.test.js`
```javascript
// Unit test: assert only
var assert = require("assert");
var fs     = require("fs");
var path   = require("path");

// Integration test: assert + https + fs + path
var https = require("https");
var fs    = require("fs");
var path  = require("path");
```
No external packages. Node.js built-ins only.

---

## No Analog Found

All Phase 4 files have analogs. The following functions within `fixlet_role_assigner.ojo` have no existing codebase analog and must be built from RESEARCH.md patterns:

| Function / Capability | Reason | Reference |
|---|---|---|
| `parseCsv(text)` | No CSV parsing exists in any .ojo | RESEARCH.md Pattern 5 |
| `validateRows(rows, allowedRoles)` | No CSV validation exists | RESEARCH.md Pattern 5 |
| `safeB64Encode(str)` / `btoa()` | No Base64 encoding in any .ojo | RESEARCH.md Pattern 1 + Pitfall 1 |
| `chunkString(s, size)` | No chunking in any .ojo | RESEARCH.md Pattern 1 |
| `buildChunkParams(b64)` | No ActionScript parameter building | RESEARCH.md Pattern 1 |
| `buildAssignActionScript(role, chunks)` | No custom PS script embedding (only sourced fixlet actions in dispatcher) | RESEARCH.md Pattern 3 |
| `buildAssignActionXml(...)` with `<ComputerID>` targeting | Dispatcher uses `<CustomRelevance>` — explicit `<ComputerID>` not yet used | RESEARCH.md Pattern 4 + OQ-2 |
| `loadAnalysisView()` via `GetRelevance` | No Analysis property reading in any existing dashboard | RESEARCH.md Pattern 6 |
| `handleFileUpload(input)` with textarea fallback | No file upload in any existing dashboard | RESEARCH.md Pitfall 4 |

---

## Metadata

**Analog search scope:**
- `Existing Dashboards/` — all .ojo files (fixlet_dispatcher.ojo, fixlet_modifier.ojo read; fixlet_copier.ojo not read — less relevant)
- `Dashboard_4_samples/` — BES files and CSV prototype
- `tests/unit/` — all test files (dispatcher.test.js, modifier.test.js indexed; copier.test.js not read — same pattern)
- `tests/integration/` — dispatcher.integration.test.js read in full
- `tests/fixtures/` — directory structure confirmed (phase-01, phase-02, phase-03 directories)

**Files scanned:** 9 source files read in full
**Pattern extraction date:** 2026-06-27
