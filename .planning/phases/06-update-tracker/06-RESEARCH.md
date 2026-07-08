# Phase 6: Fixlet Update Tracker — Research

**Researched:** 2026-07-08
**Domain:** BigFix Dashboard (IE9 JS, MSXML, BigFix REST API, fixlet version comparison)
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Manual-only scan — admin clicks "Scan for Updates" button. No auto-scan on load.
- **D-02:** During scan, show live status message with progress counts: "Scanning site X of Y… N fixlets checked so far."
- **D-03:** Results do not persist — cleared each time dashboard is closed or re-opened. No sessionStorage.
- **D-04:** Version match by stripping ` vX.Y.Z` token (space-v-digits-dots). Regex: strip ` v\d[\d.]+`. Remainder is the product key.
- **D-05:** Source sites configured in `PORTAL_CONFIG.sourceSites` as array of site name strings.
- **D-06:** Show ALL newer versions found, not just the latest. Multiple updates per product are each their own row.
- **D-07:** When same product appears in multiple source sites, show ALL matches with source site name visible. No deduplication.
- **D-08:** After successful copy, stamp `X-Superseded-By: <newFixletId>` MIME field on old portal fixlet via `API.Put`. Old fixlet remains; not deleted.
- **D-09:** Net-new products ("New Arrivals") — category suggested from CSV lookup; roles left blank (admin assigns via Modifier).
- **D-10:** Matched results shown directly in comparison table — no separate match-review step.
- **D-11:** Two-step copy flow: checkboxes → "Copy Selected" → preview panel (editable) → "Confirm".
- **D-12:** Batch mode — admin selects multiple rows, one "Copy Selected" action. Each copy is atomic; partial failures reported individually.
- **D-13:** Preview panel shows: `From → To`, editable Category dropdown (pre-filled from old portal fixlet `<Category>`, fallback to CSV), editable Roles (pre-filled from `Associated_Roles` MIME field).
- **D-14:** Comparison table layout. Columns: `☐ | Current Portal Fixlet | Available Update | Source Site | Category | Roles | Action`.
- **D-15:** Two tabs: "Updates" and "New Arrivals". Tab badge counts shown after scan: "Updates (12)  New Arrivals (4)".
- **D-16:** Category read from native `<Category>` XML element on old portal fixlet. If absent, fall back to CSV lookup.
- **D-17:** Roles read from `Associated_Roles` MIME field on old portal fixlet. If absent, default to blank.
- **D-18:** `software_categorized.csv` shortlist categories compiled into a JS `var CATEGORY_MAP = {...}` constant embedded in the dashboard.

### Claude's Discretion

- Version regex exact form — use the CONTEXT.md form `/ v\d[\d.]+/g` (see Pitfall 3 below for why the discussion-log variant risks over-stripping).
- Tab count badge format after scan — "Updates (12)  New Arrivals (4)".
- `X-Superseded-By` field value — new fixlet ID as integer string.
- IE9-safe JavaScript patterns throughout (no `let`/`const`, no arrow functions, no template literals, no `Array.from`, no `fetch`).

### Deferred Ideas (OUT OF SCOPE)

- Auto-deploy of newly copied fixlets — out of scope. Admin uses Dispatcher after copying.
- Rollback / revert of superseded fixlets — future phase.
- Localization & multi-language support — original Phase 6 placeholder; future Phase 7.
- Site priority ordering for deduplication — deferred; current approach shows all matches.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FR-10 | **Fixlet Version Update Tracking (NEW — planner must add to REQUIREMENTS.md):** The system must scan configurable source sites for fixlets that are newer versions of those in the portal, present updates in a comparison table enabling admin-driven batch copy with automatic category/role transfer, stamp superseded fixlets with `X-Superseded-By`, and surface net-new products in a "New Arrivals" tab with suggested categories from the CSV lookup. | All decisions D-01 through D-18 satisfy this requirement. Research covers version strip regex, scan relevance query, copy XML builder, MIME field transfer, X-Superseded-By write, and batch callback sequencing. |
| NFR-01 | Performance: dashboard operations < 2s; fixlet copy < 30s per fixlet | Scan uses single EvaluateRelevance call (synchronous, fast); batch copy uses sequential callbacks capped at one item at a time; individual copy is 4 API calls which should complete in < 30s. |
| NFR-02 | Reliability: atomic operations, graceful error recovery, error messages guide admin | Batch copy uses deployNextRole-style recursive callback; each item independently succeeds or fails; results panel reports per-item status. |
| NFR-03 | Security: BigFix admin auth, no credential exposure, audit trail | BigFix handles auth. All DOM insertions use `htmlEscape()`. All BES XML insertions use `xmlEscape()`. Supersede stamp via `API.Put` creates audit trail in BigFix. |
| NFR-04 | Usability: BigFix UI conventions, < 5 min per workflow, clear status indicators | Two-tab layout follows BigFix panel convention. Progress status via `setStatus()`. Editable preview panel before commit. |
| NFR-05 | Maintainability: modular code, documented configuration, externalized config | `PORTAL_CONFIG.sourceSites` externalizes site list. `CATEGORY_MAP` generated from CSV at build time. Pure JS functions are unit-testable in Node.js. |
</phase_requirements>

---

## Summary

Phase 6 builds `fixlet_update_tracker.ojo`, a new BigFix dashboard that scans source sites for newer-version fixlets and enables admins to selectively update the portal. The implementation is firmly within the IE9/MSXML/BigFix-API stack established in Phases 1–5 — no new libraries or runtimes are introduced.

The primary engineering challenges are: (1) a correct version-strip regex that avoids over-stripping product-name version numbers; (2) sequencing 4 async API calls per fixlet in IE9 without Promises, using the recursive-callback pattern established in `fixlet_role_assigner.ojo`; and (3) embedding the 798-row CSV as a build-time generated `CATEGORY_MAP` constant to avoid runtime file I/O.

The scan itself is a single synchronous `EvaluateRelevance` call covering all source sites at once, followed by a JS-side matching loop. Tab UI is a simple div show/hide — no framework needed. The comparison table uses checkboxes (a new pattern vs existing radio buttons) and a sort header reused verbatim from existing dashboards.

**Primary recommendation:** Reuse patterns from `fixlet_role_assigner.ojo` (batch sequential callbacks), `fixlet_modifier.ojo` (MIME field write, `buildUpdateXml` string-strip trick), and `fixlet_copier.ojo` (`parseCreatedId`, POST path) verbatim. The net-new engineering is: version strip, version compare, scan aggregation, two-tab layout, checkbox multi-select, and CATEGORY_MAP generation script.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Scan source sites for fixlets | BigFix Client (EvaluateRelevance) | Dashboard JS | Relevance runs on client against server data; JS aggregates results |
| Version comparison and matching | Dashboard JS | — | Pure in-memory array operations after scan data is fetched |
| Category lookup (CSV) | Dashboard JS (embedded CATEGORY_MAP) | — | Static lookup table compiled at build time; no runtime file I/O |
| Copy fixlet to portal | BigFix REST API (API.Post) | Dashboard JS | API owns creation; JS builds the BES XML payload |
| Transfer category and roles to copy | Dashboard JS + BigFix REST API (API.Put) | — | JS reads old fixlet XML and rewrites new fixlet XML; API writes it |
| Mark old fixlet superseded | BigFix REST API (API.Put) | Dashboard JS | JS builds modified XML; API persists it |
| Comparison table + tab UI | Dashboard HTML/JS | — | Client-side rendering in IE9 HTML; no server involvement |
| Preview panel (editable) | Dashboard HTML/JS | — | Pure client-side form; no API calls until Confirm |
| Authentication and access control | BigFix Console | — | BigFix handles auth; dashboard inherits logged-in operator context |

---

## Standard Stack

### Core

No new packages required. Phase 6 uses the identical stack as Phases 1–5.

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| BigFix Dashboard XML (.ojo) | Platform version | Container for HTML+JS UI | All existing dashboards use this format |
| IE9 JavaScript (`language="javascript"`) | IE9 | Dashboard scripting | BigFix Console embeds IE9 engine |
| MSXML 6.0 ActiveX (`Msxml2.DOMDocument.6.0`) | 6.0 | XML parsing and building | Only XML DOM available in IE9 BigFix context |
| BigFix JS API (`API.Get`, `API.Post`, `API.Put`) | Platform | REST calls to BigFix server | Established pattern across all dashboards |
| `EvaluateRelevance()` | Platform | Query fixlet/site data | Synchronous; established in all dashboards |
| Node.js (dev tool) | ≥ 14 | Run `generate_category_map.js` and unit tests | Existing test infrastructure |

### Supporting (Development Only)

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| Node.js `assert` module | Built-in | Unit tests | All existing test suites use this |
| `scripts/generate_category_map.js` | New script | Generate `CATEGORY_MAP` from CSV | Wave 0 task; run once, embed output |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Embedded CATEGORY_MAP constant | Runtime CSV parse | Embedding avoids file I/O and is simpler; CSV parse in IE9 adds complexity with no benefit |
| Recursive callback chaining for batch copy | Parallel API.Post calls | Sequential is required — each copy needs the new ID before stamping the old fixlet |
| Single EvaluateRelevance (all sites) | Per-site loop + setTimeout | Single call is simpler; per-site loop needed only if per-site progress is a hard requirement (see Pitfall 1) |

**Installation:** No new packages to install. `scripts/generate_category_map.js` is a dev-time Node.js script with no dependencies beyond `fs`.

---

## Package Legitimacy Audit

No external packages are installed in this phase. Phase 6 introduces no new npm dependencies.

---

## Architecture Patterns

### System Architecture Diagram

```
Admin clicks "Scan for Updates"
        |
        v
[EvaluateRelevance — portal fixlets]       [EvaluateRelevance — all source sites (single call)]
        |                                              |
        v                                              v
  portalItems[]                                 sourceItems[]
  {id, name, category, roles}                  {id, name, siteName, siteType}
        |                                              |
        +-----------> buildScanResults() <------------+
                              |
              +---------------+---------------+
              |                               |
          updates[]                      arrivals[]
          (portalKey matches             (sourceKey has no
           sourceKey, source             matching portal fixlet)
           version is newer)
              |                               |
              v                               v
     renderUpdatesTable()            renderArrivalsTable()
     tab badge: "Updates (N)"        tab badge: "New Arrivals (M)"
              |
              [Admin checks rows, clicks "Copy Selected"]
              |
              v
     showPreviewPanel(selectedRows)
     - Category dropdown (pre-filled from old fixlet <Category>)
     - Roles field (pre-filled from Associated_Roles MIME field)
     - Admin can edit before confirming
              |
              [Admin clicks "Confirm"]
              |
              v
     copyNextItem(items, 0, results, onAllDone)   <-- recursive sequential
              |
         For each item:
          Step 1: API.Get("fixlet/custom/portal/<oldId>")  -- get old XML for category/roles
          Step 2: API.Get("fixlet/<type>/<sourceSite>/<sourceId>")  -- get source XML
          Step 3: buildCopyXml(sourceXml, category, roles)
                  API.Post("fixlets/custom/Dereso Software Portal", newXml)
                  -- capture newId from response
          Step 4: buildSupersededXml(oldXml, newId)
                  API.Put("fixlet/custom/Dereso Software Portal/<oldId>", xml)
              |
         results.push({ok, newId, name, error})
         copyNextItem(items, index+1, ...)
              |
              [All done]
              v
     renderResultsPanel(results)
     -- success/fail per item, new fixlet IDs listed
```

### Recommended Project Structure

```
Existing Dashboards/
├── fixlet_update_tracker.ojo     # new — Phase 6 dashboard
scripts/
├── generate_category_map.js      # new — build-time CSV → JS object
tests/
├── unit/
│   └── update_tracker.test.js    # new — pure JS unit tests
├── integration/
│   └── update_tracker.integration.test.js  # new — API round-trips (env-gated)
└── fixtures/
    └── phase-06/
        ├── portal-fixlet-with-roles.xml      # old portal fixlet (has category + roles)
        ├── source-fixlet-new-version.xml     # newer source fixlet to copy
        ├── expected-copy-output.xml          # expected BES XML after copy builder
        └── expected-superseded-output.xml    # expected BES XML after X-Superseded-By stamp
```

---

### Pattern 1: PORTAL_CONFIG Block (with sourceSites)

[VERIFIED: confirmed from reading fixlet_modifier.ojo lines 40-64 and fixlet_dispatcher.ojo lines 38-43]

```javascript
// ==========================================================================
// PORTAL CONFIGURATION -- Edit this block to add source sites, roles, and categories.
// Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  sourceSites: [
    "BigFix Software Installer Library for Windows"
    // Add additional source site names here
  ],
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
    "File Management & Archiving",
    "Graphics & Image Editing",
    "Java Runtime & JDK",
    "Media & Entertainment",
    "Office Suite & Writing",
    "PDF & Document Management",
    "Remote Access & Virtualization",
    "Security & Privacy",
    "System Utilities & Monitoring",
    "Web Browsers"
    // Categories must match CATEGORY_MAP values for consistent display
  ]
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```

---

### Pattern 2: Version Strip and Comparison (IE9 JS)

[VERIFIED: derived from CONTEXT.md D-04 and cross-checked against all CSV product names]

```javascript
// Strip version segment " vN.N..." from product name to derive matching key.
// Requires at least one digit/dot AFTER the first digit ([\d.]+, not [\d.]*).
// This avoids stripping product-name tokens like "v2" in "AWS Command Line Interface v2".
function stripVersion(name) {
  return String(name).replace(/ v\d[\d.]+/g, "");
}

// Extract the version string for comparison (without the leading space and "v").
function extractVersion(name) {
  var m = / v(\d[\d.]+)/.exec(name);
  return m ? m[1] : "";
}

// Segment-by-segment numeric version comparison.
// Returns: 1 if a > b, -1 if a < b, 0 if equal.
// Handles multi-part versions: "26.01", "11.0.31.11", "25.0.3.9".
function compareVersions(a, b) {
  var pa = a.split("."), pb = b.split(".");
  var len = Math.max(pa.length, pb.length);
  var i, na, nb;
  for (i = 0; i < len; i++) {
    na = parseInt(pa[i] || "0", 10) || 0;
    nb = parseInt(pb[i] || "0", 10) || 0;
    if (na > nb) { return 1; }
    if (na < nb) { return -1; }
  }
  return 0;
}
```

**Verified examples:**
| Input | stripVersion result | extractVersion |
|-------|--------------------|-|
| `"7-Zip (MSI) v26.01 - Windows (x64)"` | `"7-Zip (MSI) - Windows (x64)"` | `"26.01"` |
| `"Eclipse Temurin JDK with Hotspot v21.0.11.10 - Windows (x64)"` | `"Eclipse Temurin JDK with Hotspot - Windows (x64)"` | `"21.0.11.10"` |
| `"Eclipse Temurin JDK with Hotspot 25 v25.0.3.9 - Windows (x64)"` | `"Eclipse Temurin JDK with Hotspot 25 - Windows (x64)"` | `"25.0.3.9"` |
| `"AWS Command Line Interface v2 v2.35.9.0 - Windows (x64)"` | `"AWS Command Line Interface v2 - Windows (x64)"` | `"2.35.9.0"` (second token) |

---

### Pattern 3: CATEGORY_MAP Generation Script (Build-Time)

[ASSUMED — script logic derived from CSV structure; CSV columns verified from reading file]

The CSV has 798 data rows. Columns (0-indexed): `0=No, 1=Software Installer, 2=Description, 3=Specific Category, 4=Shortlist Category`.

```javascript
// scripts/generate_category_map.js
// Run once: node scripts/generate_category_map.js > /tmp/category_map_output.txt
// Copy var CATEGORY_MAP = {...} into fixlet_update_tracker.ojo PORTAL_CONFIG section.
"use strict";
var fs = require("fs");
var path = require("path");

var csvPath = path.join(__dirname, "..", "Dashboard_4_samples", "software_categorized.csv");
var lines = fs.readFileSync(csvPath, "utf8").replace(/\r/g, "").split("\n");
var map = {};

// Start at 1 to skip header row
for (var i = 1; i < lines.length; i++) {
  var line = lines[i].trim();
  if (!line) { continue; }
  // Simple split — CSV has no quoted fields with internal commas
  var col = line.split(",");
  if (col.length < 5) { continue; }
  var rawName  = (col[1] || "").trim();
  var category = (col[4] || "").trim();
  // Strip version to get lookup key (same regex as dashboard)
  var key = rawName.replace(/ v\d[\d.]+/g, "").trim();
  if (key && category) {
    map[key] = category;
  }
}

console.log("var CATEGORY_MAP = " + JSON.stringify(map, null, 2) + ";");
```

**CSV size note:** 798 data rows. After deduplication by version-stripped key, the embedded CATEGORY_MAP object will have ~300–400 unique keys (multiple CSV rows share the same key after stripping different version numbers from the same product). Estimated size: ~25–35 KB embedded in the .ojo file. Acceptable.

---

### Pattern 4: Scan with Per-Site Progress (IE9 setTimeout trick)

[ASSUMED — BigFix EvaluateRelevance is synchronous; setTimeout(fn, 0) may allow IE9 repaint between iterations]

`EvaluateRelevance` is synchronous: the browser event loop is blocked while it runs, so `setStatus()` calls inside a for-loop won't visibly update the DOM. To honor D-02 (live progress), use recursive setTimeout to yield between sites:

```javascript
var scanSourceResults = [];
var scanSiteIndex = 0;

function startScan() {
  scanSourceResults = [];
  scanSiteIndex = 0;
  setStatus("Loading portal fixlets...");
  // Load portal fixlets synchronously (fast — same server, filtered to one site)
  portalItems = loadPortalFixlets();
  setStatus("Scanning source sites...");
  setTimeout(scanNextSite, 0);  // Yield to allow initial repaint
}

function scanNextSite() {
  if (scanSiteIndex >= PORTAL_CONFIG.sourceSites.length) {
    // All source sites scanned — now match against portal
    processScanResults();
    return;
  }
  var siteName = PORTAL_CONFIG.sourceSites[scanSiteIndex];
  setStatus("Scanning site " + (scanSiteIndex + 1) + " of " +
    PORTAL_CONFIG.sourceSites.length + ": " + siteName +
    "... (" + scanSourceResults.length + " fixlets found so far)");
  // Each EvaluateRelevance call fetches one source site
  var safesite = siteName.replace(/"/g, '""');
  var rel = '(id of it as string' +
    ' & "|||" & name of it' +
    ' & "|||" & name of (site of it)' +
    ' & "|||" & (if custom site flag of (site of it) then "custom"' +
    '   else if external site flag of (site of it) then "external"' +
    '   else if operator site flag of (site of it) then "operator" else "master"))' +
    ' of bes fixlets whose (name of (site of it) = "' + safesite + '"' +
    '   and (fixlet flag of it or task flag of it))';
  var data = EvaluateRelevance(rel);
  var i, p;
  for (i = 0; i < data.length; i++) {
    p = String(data[i]).split("|||");
    scanSourceResults.push({ id: p[0], name: p[1], siteName: p[2], siteType: p[3] });
  }
  scanSiteIndex++;
  setTimeout(scanNextSite, 0);  // Yield to allow repaint before next site
}
```

**Alternative (simpler, no per-site progress):** Single EvaluateRelevance call covering all source sites using Relevance set membership. Cleaner code but no mid-scan progress. Use this if IE9 doesn't repaint on setTimeout(fn, 0):
```javascript
var siteSetStr = '"' + PORTAL_CONFIG.sourceSites.join('";"') + '"';
var rel = '...' + ' whose (name of (site of it) is contained by set of (' + siteSetStr + ') ...)';
```

---

### Pattern 5: Portal Fixlet Relevance Query

[VERIFIED: confirmed from reading fixlet_dispatcher.ojo lines 118–147]

```javascript
function loadPortalFixlets() {
  var rel =
    '(id of it as string' +
    ' & "|||" & name of it' +
    ' & "|||" & (if exists category of it then category of it as string else "")' +
    ' & "|||" & (if exists mime fields whose (name of it = "Associated_Roles") of it' +
    '   then concatenation of values of mime fields whose (name of it = "Associated_Roles") of it' +
    '   else ""))' +
    ' of bes fixlets whose (name of (site of it) = "Dereso Software Portal"' +
    '   and (fixlet flag of it or task flag of it))';
  var data = EvaluateRelevance(rel);
  var items = [];
  var i, p;
  for (i = 0; i < data.length; i++) {
    p = String(data[i]).split("|||");
    items.push({ id: p[0], name: p[1], category: p[2], roles: p[3] });
  }
  return items;
}
```

---

### Pattern 6: Scan Results Aggregation (Pure JS)

[ASSUMED — based on D-04, D-06, D-07 decisions]

```javascript
function buildScanResults(portalItems, sourceItems) {
  // Build a portal map keyed by version-stripped product name
  var portalMap = {};
  var i, key, pItem;
  for (i = 0; i < portalItems.length; i++) {
    pItem = portalItems[i];
    key = stripVersion(pItem.name);
    if (!portalMap[key]) { portalMap[key] = []; }
    portalMap[key].push(pItem);
  }

  var updates  = [];
  var arrivals = [];

  for (i = 0; i < sourceItems.length; i++) {
    var sItem    = sourceItems[i];
    var sKey     = stripVersion(sItem.name);
    var sVer     = extractVersion(sItem.name);

    if (portalMap[sKey]) {
      // Found a matching portal product — check if source version is newer
      var j, pMatch;
      for (j = 0; j < portalMap[sKey].length; j++) {
        pMatch = portalMap[sKey][j];
        var pVer = extractVersion(pMatch.name);
        if (compareVersions(sVer, pVer) > 0) {
          // D-06: show ALL newer versions, D-07: show ALL site matches
          updates.push({
            portalId:       pMatch.id,
            portalName:     pMatch.name,
            portalCategory: pMatch.category,
            portalRoles:    pMatch.roles,
            sourceId:       sItem.id,
            sourceName:     sItem.name,
            sourceSiteName: sItem.siteName,
            sourceSiteType: sItem.siteType,
            productKey:     sKey
          });
        }
      }
    } else {
      // No matching portal product — this is a "New Arrival"
      var suggested = (typeof CATEGORY_MAP !== "undefined" && CATEGORY_MAP[sKey]) || "";
      arrivals.push({
        sourceId:         sItem.id,
        sourceName:       sItem.name,
        sourceSiteName:   sItem.siteName,
        sourceSiteType:   sItem.siteType,
        productKey:       sKey,
        suggestedCategory: suggested
      });
    }
  }

  return { updates: updates, arrivals: arrivals };
}
```

---

### Pattern 7: Copy XML Builder (MSXML, reusing modifier.ojo approach)

[VERIFIED: adapted from fixlet_modifier.ojo buildUpdateXml() lines 566–625]

```javascript
function buildCopyXml(sourceXml, category, rolesValue) {
  // Strip existing Associated_Roles MIME field using string regex (modifier.ojo pattern)
  var cleanedXml = ("" + sourceXml).replace(
    /<MIMEField>\s*<Name>\s*Associated_Roles\s*<\/Name>[\s\S]*?<\/MIMEField>/gi, "");

  var origDoc = new ActiveXObject("Msxml2.DOMDocument.6.0");
  origDoc.async            = false;
  origDoc.validateOnParse  = false;
  origDoc.resolveExternals = false;
  origDoc.setProperty("SelectionLanguage", "XPath");
  origDoc.loadXML(cleanedXml);

  var fixletNode = origDoc.getElementsByTagName("Fixlet")[0] ||
                   origDoc.getElementsByTagName("Task")[0];
  if (!fixletNode) { return ""; }

  // Override category with the transferred value (from old portal fixlet or CSV)
  var catNodes = origDoc.getElementsByTagName("Category");
  if (catNodes.length > 0) { catNodes[0].text = category; }

  // Add Associated_Roles MIME field before <Domain> (modifier.ojo lines 609-620)
  if (rolesValue) {
    var newMime = origDoc.createElement("MIMEField");
    var nameEl  = origDoc.createElement("Name");
    var valueEl = origDoc.createElement("Value");
    nameEl.text  = "Associated_Roles";
    valueEl.text = rolesValue;
    newMime.appendChild(nameEl);
    newMime.appendChild(valueEl);
    var domainNode = fixletNode.selectSingleNode("Domain");
    if (domainNode) { fixletNode.insertBefore(newMime, domainNode); }
    else            { fixletNode.appendChild(newMime); }
  }

  return '<?xml version="1.0" encoding="UTF-8"?>\r\n' + origDoc.documentElement.xml;
}
```

---

### Pattern 8: X-Superseded-By Stamp (modifier.ojo lines 609–620 adapted)

[VERIFIED: read from fixlet_modifier.ojo lines 609-621; API.Put path from lines 653-654]

```javascript
function buildSupersededXml(oldPortalXml, newFixletId) {
  // Strip any existing X-Superseded-By field (idempotent)
  var cleanedXml = ("" + oldPortalXml).replace(
    /<MIMEField>\s*<Name>\s*X-Superseded-By\s*<\/Name>[\s\S]*?<\/MIMEField>/gi, "");

  var origDoc = new ActiveXObject("Msxml2.DOMDocument.6.0");
  origDoc.async            = false;
  origDoc.validateOnParse  = false;
  origDoc.resolveExternals = false;
  origDoc.setProperty("SelectionLanguage", "XPath");
  origDoc.loadXML(cleanedXml);

  var fixletNode = origDoc.getElementsByTagName("Fixlet")[0] ||
                   origDoc.getElementsByTagName("Task")[0];
  if (!fixletNode) { return ""; }

  var newMime = origDoc.createElement("MIMEField");
  var nameEl  = origDoc.createElement("Name");
  var valueEl = origDoc.createElement("Value");
  nameEl.text  = "X-Superseded-By";
  valueEl.text = String(newFixletId);  // new fixlet ID as integer string (D-08)
  newMime.appendChild(nameEl);
  newMime.appendChild(valueEl);
  var domainNode = fixletNode.selectSingleNode("Domain");
  if (domainNode) { fixletNode.insertBefore(newMime, domainNode); }
  else            { fixletNode.appendChild(newMime); }

  return '<?xml version="1.0" encoding="UTF-8"?>\r\n' + origDoc.documentElement.xml;
}
```

**PUT path:**
```javascript
var putPath = "fixlet/custom/" + encodeURIComponent("Dereso Software Portal") + "/" +
              encodeURIComponent(oldFixletId);
API.Put(putPath, supersededXml, function(e, s, b) { ... });
```

---

### Pattern 9: Batch Copy Sequential Callback (role_assigner.ojo deployNextRole pattern)

[VERIFIED: read from fixlet_role_assigner.ojo lines 467–528]

```javascript
function copyNextItem(items, index, results, onAllDone) {
  if (index >= items.length) {
    onAllDone(results);
    return;
  }

  var item = items[index];
  var progressEl = document.getElementById("copyProgress");
  if (progressEl) {
    var msg = document.createElement("div");
    msg.innerText = "Copying " + (index + 1) + " of " + items.length + ": " + item.sourceName + "...";
    progressEl.appendChild(msg);
  }

  // Step 1: GET old portal fixlet XML (to confirm current category/roles — user may have edited in preview)
  var portalGetPath = "fixlet/custom/" + encodeURIComponent("Dereso Software Portal") +
                      "/" + encodeURIComponent(item.portalId);
  API.Get(portalGetPath, function(e1, s1, b1) {
    if (s1 !== 200) {
      results.push({ ok: false, name: item.sourceName, error: "GET portal fixlet failed: status=" + s1 });
      copyNextItem(items, index + 1, results, onAllDone);
      return;
    }
    var portalXml = b1;

    // Step 2: GET source fixlet XML (the new version to copy)
    var srcPath = "fixlet/" + item.sourceSiteType + "/" +
                  encodeURIComponent(item.sourceSiteName) + "/" + encodeURIComponent(item.sourceId);
    API.Get(srcPath, function(e2, s2, b2) {
      if (s2 !== 200) {
        results.push({ ok: false, name: item.sourceName, error: "GET source fixlet failed: status=" + s2 });
        copyNextItem(items, index + 1, results, onAllDone);
        return;
      }

      // Step 3: POST copy to portal (with category + roles from preview panel values)
      var newXml  = buildCopyXml(b2, item.previewCategory, item.previewRoles);
      var postPath = "fixlets/custom/" + encodeURIComponent("Dereso Software Portal");
      API.Post(postPath, newXml, function(e3, s3, b3) {
        if (s3 !== 200 && s3 !== 201) {
          results.push({ ok: false, name: item.sourceName, error: "POST copy failed: status=" + s3 });
          copyNextItem(items, index + 1, results, onAllDone);
          return;
        }
        var newId = parseCreatedId(b3);  // reuse copier.ojo function verbatim

        // Step 4: PUT X-Superseded-By on old portal fixlet
        var supersededXml = buildSupersededXml(portalXml, newId);
        var putPath = "fixlet/custom/" + encodeURIComponent("Dereso Software Portal") +
                      "/" + encodeURIComponent(item.portalId);
        API.Put(putPath, supersededXml, function(e4, s4, b4) {
          var putOk = (s4 === 200 || s4 === 201);
          results.push({
            ok: putOk, name: item.sourceName, newId: newId,
            error: putOk ? "" : "PUT supersede failed: status=" + s4
          });
          copyNextItem(items, index + 1, results, onAllDone);
        });
      });
    });
  });
}
```

---

### Pattern 10: Two-Tab Layout (IE9 div show/hide)

[ASSUMED — no existing tab pattern in project; simple show/hide is the IE9-safe approach]

```html
<!-- Tab buttons -->
<div style="margin-bottom:0;">
  <button id="tabBtnUpdates"  class="tabBtn tabActive"  onclick="switchTab('updates')">
    Updates <span id="badgeUpdates"></span>
  </button>
  <button id="tabBtnArrivals" class="tabBtn"             onclick="switchTab('arrivals')">
    New Arrivals <span id="badgeArrivals"></span>
  </button>
</div>
<!-- Tab panels -->
<div id="tabUpdates"  class="tabPanel"></div>
<div id="tabArrivals" class="tabPanel" style="display:none;"></div>
```

```javascript
function switchTab(tab) {
  var u = document.getElementById("tabUpdates");
  var a = document.getElementById("tabArrivals");
  var bu = document.getElementById("tabBtnUpdates");
  var ba = document.getElementById("tabBtnArrivals");
  if (u) { u.style.display = tab === "updates"  ? "" : "none"; }
  if (a) { a.style.display = tab === "arrivals" ? "" : "none"; }
  if (bu) { bu.className = tab === "updates"  ? "tabBtn tabActive" : "tabBtn"; }
  if (ba) { ba.className = tab === "arrivals" ? "tabBtn tabActive" : "tabBtn"; }
}

// After scan completes, update badges (D-15)
function updateTabBadges(updCount, arrCount) {
  var bu = document.getElementById("badgeUpdates");
  var ba = document.getElementById("badgeArrivals");
  if (bu) { bu.innerHTML = updCount > 0 ? " (" + updCount + ")" : ""; }
  if (ba) { ba.innerHTML = arrCount > 0 ? " (" + arrCount + ")" : ""; }
}
```

---

### Pattern 11: Checkbox Multi-Select Pattern (new for Phase 6)

[ASSUMED — no existing checkbox pattern in project; radio buttons used in other dashboards]

```javascript
// Render row with checkbox (D-14)
function renderUpdateRow(t, item, index) {
  var r = t.insertRow(-1);
  r._rowData = item;  // Attach data to TR for getSelectedRows()
  var chkCell = r.insertCell(-1);
  var chk = document.createElement("input");
  chk.type = "checkbox";
  chk.id   = "chk_" + index;
  chkCell.appendChild(chk);
  r.insertCell(-1).innerHTML = htmlEscape(item.portalName);
  r.insertCell(-1).innerHTML = htmlEscape(item.sourceName);
  r.insertCell(-1).innerHTML = htmlEscape(item.sourceSiteName);
  r.insertCell(-1).innerHTML = htmlEscape(item.portalCategory || "");
  r.insertCell(-1).innerHTML = htmlEscape(item.portalRoles    || "");
}

function toggleSelectAll(masterChk) {
  var t = document.getElementById("updatesTable");
  var i, chk;
  for (i = 1; i < t.rows.length; i++) {  // skip header
    chk = t.rows[i].cells[0] && t.rows[i].cells[0].getElementsByTagName("input")[0];
    if (chk && chk.type === "checkbox") { chk.checked = masterChk.checked; }
  }
}

function getSelectedUpdateRows() {
  var t = document.getElementById("updatesTable");
  var selected = [];
  var i, chk;
  for (i = 1; i < t.rows.length; i++) {  // skip header
    chk = t.rows[i].cells[0] && t.rows[i].cells[0].getElementsByTagName("input")[0];
    if (chk && chk.type === "checkbox" && chk.checked) {
      selected.push(t.rows[i]._rowData);
    }
  }
  return selected;
}
```

---

### Pattern 12: MIME Field Read Pattern (from modifier.ojo / dispatcher.ojo)

[VERIFIED: confirmed from fixlet_modifier.ojo lines 423–435 and fixlet_dispatcher.ojo lines 443–454]

The `selectSingleNode` (MSXML XPath) approach is the established project standard:

```javascript
function readMimeField(xmlDoc, fieldName) {
  var mimeNodes = xmlDoc.getElementsByTagName("MIMEField");
  var m, nameNode, valueNode, mName;
  for (m = 0; m < mimeNodes.length; m++) {
    nameNode = mimeNodes[m].selectSingleNode("Name");
    mName    = nameNode ? String(nameNode.text || "").replace(/^\s+|\s+$/g, "") : "";
    if (mName === fieldName) {
      valueNode = mimeNodes[m].selectSingleNode("Value");
      return valueNode ? String(valueNode.text || "") : "";
    }
  }
  return "";
}
```

---

### Anti-Patterns to Avoid

- **Using `querySelector`:** MSXML does not support `querySelector`; use `getElementsByTagName` + `selectSingleNode` (XPath).
- **Using `let`/`const`/arrow functions/template literals:** IE9 does not support ES6. Use `var` and named functions only.
- **Using `Array.from` or `fetch`:** Not available in IE9. Use `for` loops and `API.Get`/`API.Post`/`API.Put`.
- **String-splitting `|||` on BigFix relevance output without `String()`:** Always wrap `data[i]` in `String(data[i])` before `.split("|||")`.
- **POST vs PUT confusion (Pitfall 2 below):** POST uses `"fixlets"` (plural path) for create; PUT uses `"fixlet"` (singular path) for update.
- **Stripping `Associated_Roles` via MSXML removeChild:** The string regex approach from modifier.ojo is more reliable. Always strip via regex on the raw XML string before parsing into DOM.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| New fixlet ID from POST response | Custom XML parser | `parseCreatedId()` from copier.ojo | Already handles `ID=`, `Resource=`, regex fallbacks; covers all response shapes |
| XML entity escaping | Custom escaper | `xmlEscape()` from modifier.ojo | Covers all 5 entities including `&apos;` |
| HTML entity escaping | Custom escaper | `htmlEscape()` from modifier.ojo / dispatcher.ojo | XSS prevention; consistent across all dashboards |
| CDATA wrapping | String concat | `cdataStart()` / `cdataEnd()` / `xmlCDataSafe()` from any dashboard | Handles `]]>` escape inside CDATA sections |
| Version number comparison | Regex/string compare | `compareVersions()` (Pattern 2) | Lexicographic comparison fails for `9 vs 10`; segment-based numeric is required |
| Sortable table headers | Custom sort UI | `makeSortHeader()` + `applySortToCurrentItems()` + `sortBy()` from any dashboard | Identical pattern in all 4 existing dashboards |

**Key insight:** Phase 6 is primarily a composition of existing patterns. The only genuinely new logic is version strip/compare, scan aggregation, and the two-tab + checkbox UI layer.

---

## Common Pitfalls

### Pitfall 1: EvaluateRelevance Blocks IE9 Event Loop
**What goes wrong:** Calling `setStatus()` before `EvaluateRelevance()` in a loop causes the status to update only after ALL iterations complete — the intermediate messages are never visible.
**Why it happens:** IE9 is single-threaded. EvaluateRelevance is synchronous. The browser can't repaint while JS is executing.
**How to avoid:** Use `setTimeout(fn, 0)` between iterations to yield to the event loop (Pattern 4 above). Alternatively, use a single EvaluateRelevance covering all source sites and accept that progress display is only shown as a final completion message.
**Warning signs:** Status text appears to "jump" from "Ready" to "Scan complete" with no intermediate updates visible.

---

### Pitfall 2: POST Uses Plural Path, GET/PUT Use Singular
**What goes wrong:** Using `"fixlet/custom/..."` for POST returns a 404 or 405.
**Why it happens:** BigFix REST API uses `"fixlets"` (plural) as a collection endpoint for POST (create), and `"fixlet"` (singular) + `/<id>` for GET/PUT (read/update).
**How to avoid:** Always use:
  - Create: `API.Post("fixlets/custom/" + encodeURIComponent(site), xml, cb)`
  - Read/Update: `API.Get("fixlet/custom/" + encodeURIComponent(site) + "/" + encodeURIComponent(id), cb)`
  - Update: `API.Put("fixlet/custom/" + encodeURIComponent(site) + "/" + encodeURIComponent(id), xml, cb)`
**Warning signs:** POST returning 404/405 despite correct XML.

---

### Pitfall 3: Version Regex Over-Strips Product-Name Version Numbers
**What goes wrong:** Using `/\s+v\d[\d.]*/ig` (zero-or-more after first digit) strips `" v2"` from `"AWS Command Line Interface v2 v2.35.9.0 - Windows (x64)"`, producing key `"AWS Command Line Interface v2.35.9.0 - Windows (x64)"` instead of `"AWS Command Line Interface v2 - Windows (x64)"`.
**Why it happens:** The `[\d.]*` (zero-or-more) variant matches `" v2"` followed by a space, stripping the product-family version tag. The CONTEXT.md regex `/ v\d[\d.]+/g` (ONE-or-more after first digit) correctly rejects `" v2"` alone because `[\d.]+` needs at least one more character that is a digit or dot.
**How to avoid:** Always use `/ v\d[\d.]+/g` exactly as specified in CONTEXT.md D-04. The discussion log mentions `/\s+v\d[\d.]*/i` which is INCORRECT for this edge case.
**Warning signs:** Products like "AWS CLI v2" appearing without the "v2" family label in scan results.

---

### Pitfall 4: Missing setProperty("SelectionLanguage", "XPath") on MSXML DOM
**What goes wrong:** `fixletNode.selectSingleNode("Name")` throws or returns null even when the node exists.
**Why it happens:** MSXML 6.0 defaults to XSLPattern query language, not XPath. `selectSingleNode` uses `SelectionLanguage` property.
**How to avoid:** Always call `origDoc.setProperty("SelectionLanguage", "XPath")` immediately after creating the ActiveXObject and before calling `selectSingleNode` or `selectNodes`. This is the pattern in modifier.ojo lines 577–579.
**Warning signs:** `selectSingleNode` returns null for nodes that are visibly present in the XML.

---

### Pitfall 5: Nesting Depth of 4 API Callbacks Per Item
**What goes wrong:** Deep callback nesting (GET → GET → POST → PUT) becomes hard to read and debug. Error handling at each level may be inconsistent.
**Why it happens:** IE9 has no Promises or async/await. Four sequential API calls = four nested callbacks.
**How to avoid:** Name the inner functions (don't inline them) to limit nesting depth. Use early-return on error at each level. Keep the pattern identical to `deployNextRole` in role_assigner.ojo for consistency. See Pattern 9 above.
**Warning signs:** Callback nesting deeper than 4 levels; inconsistent error propagation.

---

### Pitfall 6: API.Put Returns 200 (not 201) for Some BigFix Versions
**What goes wrong:** Code checks `s === 201` only for the supersede PUT — misses successful 200 responses.
**Why it happens:** BigFix API returns 200 for successful updates in some versions. The project already handles this in modifier.ojo line 660: `if(s === 200 || s === 201)`.
**How to avoid:** Always check `(s === 200 || s === 201)` for both POST and PUT success.
**Warning signs:** PUT appears to fail (error branch) but the fixlet is actually updated in BigFix.

---

## Code Examples

### Category Lookup with Fallback
```javascript
// Source: Pattern 2 + Pattern 3 above + D-16 decision
function lookupCategory(productKey, portalCategory) {
  // D-16: prefer old portal fixlet's native <Category>
  if (portalCategory && portalCategory !== "") { return portalCategory; }
  // Fallback: CSV lookup table embedded in dashboard
  if (typeof CATEGORY_MAP !== "undefined" && CATEGORY_MAP[productKey]) {
    return CATEGORY_MAP[productKey];
  }
  return "";  // blank — admin must fill in
}
```

### MIME Field Value from Old Portal Fixlet (for roles)
```javascript
// Source: fixlet_dispatcher.ojo lines 443-454 (VERIFIED)
function extractRolesFromXmlText(xmlText) {
  var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
  xml.async = false;
  xml.loadXML(xmlText);
  var mimeNodes = xml.getElementsByTagName("MIMEField");
  var m, nameNode, valueNode, mName;
  for (m = 0; m < mimeNodes.length; m++) {
    nameNode = mimeNodes[m].selectSingleNode("Name");
    mName    = nameNode ? String(nameNode.text || "").replace(/^\s+|\s+$/g, "") : "";
    if (mName === "Associated_Roles") {
      valueNode = mimeNodes[m].selectSingleNode("Value");
      return valueNode ? String(valueNode.text || "") : "";
    }
  }
  return "";
}
```

### API Path Constants for Reference
```javascript
// Source: fixlet_copier.ojo line 790, fixlet_modifier.ojo line 653 (VERIFIED)
var PORTAL_SITE   = "Dereso Software Portal";
var PORTAL_POST   = "fixlets/custom/" + encodeURIComponent(PORTAL_SITE);     // POST (create)
var PORTAL_FIXLET = "fixlet/custom/"  + encodeURIComponent(PORTAL_SITE) + "/"; // GET/PUT prefix
```

---

## Runtime State Inventory

This is not a rename/refactor/migration phase. Omitted per instructions.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `setTimeout(fn, 0)` in IE9/BigFix dashboard causes a browser repaint before the next EvaluateRelevance call, making per-site progress visible | Pattern 4 (Scan) | If wrong, per-site status updates won't render; fall back to single EvaluateRelevance call with post-scan status message |
| A2 | CSV file has no quoted fields containing commas — simple `split(",")` is sufficient for column parsing in `generate_category_map.js` | Pattern 3 (CATEGORY_MAP) | If wrong, some category values will be truncated; fix by using a proper CSV parser (quoted-field-aware) |
| A3 | The CATEGORY_MAP embedded object after deduplication will be ~300–400 unique keys (25–35 KB); acceptable to embed inline in .ojo | Pattern 3 | If significantly larger, may need to truncate or externalise; check generated file size |
| A4 | `API.Put` on a portal fixlet to add a MIME field returns 200 or 201; BigFix does not require a special header or version-lock parameter for fixlet updates | Pattern 8 + Pitfall 6 | If wrong, PUT will fail; check BigFix API version docs or test manually |
| A5 | Storing `_rowData` directly on a `<tr>` DOM element in IE9 (as a JS property, not an attribute) works reliably and doesn't interfere with BigFix console rendering | Pattern 11 | If wrong, use a parallel `rowData[]` array indexed by row number instead |
| A6 | New Arrival rows in the source scan can be safely GETted and POSTed via the same `buildCopyXml` + `API.Post` flow as Updates, just without an old portal fixlet to PUT supersede on | Pattern 9 adaptation | If wrong, source fixlet XML structure may require a different copy approach |

---

## Open Questions

1. **Do New Arrivals also go through the copy flow?**
   - What we know: D-09 says "Roles are left blank — admin must assign roles manually via Modifier after copying." This implies New Arrivals ARE copyable.
   - What's unclear: The CONTEXT.md doesn't explicitly describe a "Copy" action on the New Arrivals tab. Is there a "Copy to Portal" button per row, or per-row checkbox + bulk copy like the Updates tab?
   - Recommendation: Planner should add per-row "Copy" action button in the New Arrivals table, triggering a simplified copy (no old fixlet to GET/PUT; steps 1 and 4 of the batch copy are skipped).

2. **What siteType will PORTAL_CONFIG.sourceSites entries actually be in production?**
   - What we know: BigFix Software Installer Library for Windows is typically an "external" site type. Custom sites created by the customer would be "custom".
   - What's unclear: If a source site is an "operator" site, the path `"fixlet/operator/<siteName>/<id>"` may not be accessible via the REST API without special permissions.
   - Recommendation: Document the siteType in the scan output so it's captured at scan time (not re-derived at copy time). The Relevance query already captures this (see Pattern 4).

3. **Does the BigFix portal allow overwriting `<Category>` on the copied fixlet via POST?**
   - What we know: `buildCopyXml` modifies the `<Category>` node in the MSXML DOM before POST. The copier.ojo does the same.
   - What's unclear: If the source fixlet's `<Category>` is blank and we try to set it to a non-blank value via DOM manipulation — does BigFix accept this?
   - Recommendation: Build a test fixture where source fixlet has empty category and verify the POST creates the fixlet with the desired category set. Add to integration tests.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | Unit tests, CATEGORY_MAP generation | Expected (existing test suite passes) | ≥ 14 | — |
| BigFix Console (IE9 engine) | Dashboard runtime, integration tests | Requires live instance | Platform | Mark integration tests SKIP |
| `Dashboard_4_samples/software_categorized.csv` | CATEGORY_MAP generation | ✓ (verified at 799 lines) | — | — |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in `assert` module (no external packages — established across Phases 1–5) |
| Config file | None — scripts run directly with `node` |
| Quick run command | `node tests/unit/update_tracker.test.js` |
| Full suite command | `node tests/unit/copier.test.js && node tests/unit/modifier.test.js && node tests/unit/dispatcher.test.js && node tests/unit/role_assigner.test.js && node tests/unit/update_tracker.test.js` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FR-10 (version strip) | `stripVersion("7-Zip (MSI) v26.01 - Windows (x64)")` returns `"7-Zip (MSI) - Windows (x64)"` | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| FR-10 (version strip edge) | `stripVersion("AWS Command Line Interface v2 v2.35.9.0 - Windows (x64)")` returns `"AWS Command Line Interface v2 - Windows (x64)"` | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| FR-10 (version compare) | `compareVersions("26.02", "26.01")` returns 1; `compareVersions("9.0", "10.0")` returns -1 | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| FR-10 (category lookup) | `lookupCategory("7-Zip (MSI) - Windows (x64)", "")` returns `"File Management & Archiving"` from embedded CATEGORY_MAP | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| FR-10 (scan results) | `buildScanResults([{id:"1",name:"Firefox v128.0 - Windows (x64)",category:"Web Browsers",roles:""}], [{id:"2",name:"Firefox v130.0 - Windows (x64)",siteName:"Source",siteType:"external"}])` → `updates.length === 1, arrivals.length === 0` | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| FR-10 (new arrival) | Same scan with non-matching source → `updates.length === 0, arrivals.length === 1` | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| FR-10 (category fallback) | `lookupCategory("Unknown Product - Windows (x64)", "Existing Category")` returns `"Existing Category"` (portal category wins) | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| NFR-01 (timing) | Copy operation completes per-item in < 30s (measured in integration test) | integration | `node tests/integration/update_tracker.integration.test.js` | ❌ Wave 0 |
| NFR-02 (error recovery) | Partial batch failure: item 2 fails, items 1 and 3 still succeed | unit (mock) | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |
| NFR-03 (XSS) | `htmlEscape('<script>alert(1)</script>')` → `"&lt;script&gt;alert(1)&lt;/script&gt;"` (reuse existing test) | unit | `node tests/unit/update_tracker.test.js` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `node tests/unit/update_tracker.test.js`
- **Per wave merge:** Full suite (all 5 unit test files)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/unit/update_tracker.test.js` — covers FR-10 pure functions
- [ ] `tests/integration/update_tracker.integration.test.js` — covers API round-trips (SKIP mode without BigFix)
- [ ] `tests/fixtures/phase-06/portal-fixlet-with-roles.xml` — old portal fixlet with `<Category>` and `Associated_Roles`
- [ ] `tests/fixtures/phase-06/source-fixlet-new-version.xml` — newer version source fixlet
- [ ] `scripts/generate_category_map.js` — build-time CSV → JS object generator
- [ ] Run: `node scripts/generate_category_map.js` → produces `CATEGORY_MAP` to embed in dashboard

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | BigFix Console handles auth; dashboard inherits logged-in operator |
| V3 Session Management | No | BigFix Console manages sessions |
| V4 Access Control | Partial | BigFix operator permissions restrict site access; dashboard should not bypass REST auth |
| V5 Input Validation | Yes | `htmlEscape()` for all DOM insertions; `xmlEscape()` for all BES XML insertions |
| V6 Cryptography | No | No passwords, tokens, or secrets processed |

### Known Threat Patterns for BigFix Dashboard + IE9 JS

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| XSS via fixlet name in comparison table | Spoofing | `htmlEscape(item.name)` on all fixlet names before `.innerHTML` assignment |
| XML injection via fixlet name in BES XML | Tampering | `xmlEscape(value)` on all fields inserted into BES XML strings |
| MIME field value injection | Tampering | `xmlEscape(rolesValue)` before inserting into `<Value>` element |
| Copying malicious fixlet action script from source site | Tampering | Admin must review fixlet content; dashboard copies verbatim (no sanitization — this is by design, as BigFix admin is trusted) |
| Category map poisoning | Spoofing | CATEGORY_MAP is compiled at build time from a trusted CSV; not user-supplied at runtime |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual fixlet comparison by admins | Automated version-strip matching | Phase 6 new | Admins no longer need to manually identify outdated portal fixlets |
| `PORTAL_CONFIG` with roles/categories only | `PORTAL_CONFIG` with `sourceSites` array added | Phase 6 | Consistent configuration pattern; admin edits one block |
| Single-dashboard (Copier) copy flow | Update Tracker feeds pre-matched fixlets into copy flow | Phase 6 | Removes friction: no need to know which fixlet is the update |

**Deprecated/outdated for Phase 6:**
- Manual admin identification of "which source fixlet updates which portal fixlet" — replaced by automated version-strip matching.
- ROADMAP.md Phase 6 entry (currently describes "Localization & Advanced Features") — planner must update it to describe the Fixlet Update Tracker.

---

## Sources

### Primary (HIGH confidence)
- `Existing Dashboards/fixlet_modifier.ojo` — MIME field write (lines 609–621), category read, `buildUpdateXml` string-strip pattern, `PORTAL_CONFIG` block structure, `API.Put` path pattern
- `Existing Dashboards/fixlet_copier.ojo` — `API.Post` path ("fixlets/custom/..."), `parseCreatedId()`, `makeSortHeader()`, `xmlEscape()`, `htmlEscape()`
- `Existing Dashboards/fixlet_dispatcher.ojo` — portal fixlet relevance query with `Associated_Roles`, `PORTAL_CONFIG` usage, `htmlEscape()` consistent usage
- `Existing Dashboards/fixlet_role_assigner.ojo` — `deployNextRole()` recursive sequential callback pattern (lines 467–528)
- `Dashboard_4_samples/software_categorized.csv` — CSV structure confirmed: 799 lines (1 header + 798 data), columns verified, no quoted-field commas observed
- `.planning/phases/06-update-tracker/06-CONTEXT.md` — all locked decisions D-01 through D-18

### Secondary (MEDIUM confidence)
- `.planning/phases/06-update-tracker/06-DISCUSSION-LOG.md` — discussion alternatives considered; noted discrepancy between CONTEXT.md regex and discussion-log regex (see Pitfall 3)
- `tests/unit/modifier.test.js` — confirmed Node.js + `assert` test pattern; no external test framework

### Tertiary (LOW confidence, marked [ASSUMED])
- Behavior of `setTimeout(fn, 0)` in IE9 BigFix dashboard context (A1) — common browser behavior but not verified against BigFix Console specifically
- CATEGORY_MAP unique key count estimate (A3) — derived from CSV structure, not computed exactly
- `_rowData` property storage on `<tr>` DOM element in IE9 (A5) — standard practice but not tested in this context

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all patterns verified from reading existing dashboard code
- Version strip/compare algorithm: HIGH — traced against all documented CSV examples manually
- Architecture (batch callback, MIME field write, XML copy): HIGH — verbatim from existing dashboard patterns
- Scan EvaluateRelevance query: HIGH — confirmed from dispatcher/modifier patterns
- Tab UI and checkbox pattern: MEDIUM — simple HTML/JS with no known IE9 gotchas beyond `_rowData` storage
- Per-site setTimeout progress: LOW — IE9 repaint behavior in BigFix Console not confirmed empirically

**Research date:** 2026-07-08
**Valid until:** 2026-08-08 (stable BigFix API; valid until next BigFix platform release)
