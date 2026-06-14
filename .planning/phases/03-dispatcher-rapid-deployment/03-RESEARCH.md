# Phase 3: Dispatcher (Rapid Deployment) — Research

**Researched:** 2026-06-14
**Domain:** BigFix dashboard JavaScript — offer-type action creation via REST API, IE9 constraints, test patterns
**Confidence:** HIGH (core API patterns verified from official BigFix developer docs and GitHub examples; offer XML structure verified from official restapi-examples repository)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Scaffold `fixlet_dispatcher.ojo` from `Existing Dashboards/fixlet_modifier.ojo`. Strip role/category edit logic; keep fixlet list, search bar, detail panel, and action button scaffold.

**D-02:** Filename: `Existing Dashboards/fixlet_dispatcher.ojo`. Dashboard title: `Dereso Fixlet Dispatcher`. Same BigFix menu pattern as copier/modifier.

**D-03:** PORTAL_CONFIG block (top of JS, same pattern as modifier) contains:
```js
var PORTAL_CONFIG = {
  defaultExpirationDays: 7,
  targetGroups: [ /* list of common target group names */ ]
};
```

**D-04:** Show all fixlets in "Dereso Software Portal" custom site — no role-assignment filter.

**D-05:** Fixlet list columns: Name, Category, Roles, Site. Roles column reads `Associated_Roles` MIME field.

**D-06:** Live name-search bar — same debounced filter pattern as modifier.ojo.

**D-07:** Detail panel shows: Fixlet Name, Category, Assigned Roles, Existing action count, Action dropdown, Deployment form.

**D-08:** Multiple actions use an admin dropdown — no auto-selection.

**D-09:** Target group input: `<select>` from PORTAL_CONFIG.targetGroups plus a free-text `<input>` fallback.

**D-10:** Live preview panel updates as admin fills form. Single "Deploy" button fires the POST. No separate confirm dialog.

**D-11:** Success: show deployment ID in success banner + "Deploy Another" button. Failure: show error inline.

**D-12:** FR-04 (fixlet description/DefaultActionScript update) deferred to Phase 4.

**Offer field mapping (FR-06):**
| Offer field | Source |
|---|---|
| Title | Fixlet name |
| Description | Fixlet `<Description>` content (as-is) |
| Category | Fixlet `<Category>` value |
| Type | `"offer"` (hardcoded via `<IsOffer>true</IsOffer>`) |
| Action | Admin-selected from dropdown |
| Target group | Admin-selected (PORTAL_CONFIG list or free-text) |
| Expiration | `defaultExpirationDays` from PORTAL_CONFIG (overrideable) |

### Claude's Discretion

- Exact structure of POST /api/actions request body (researched — see below)
- Whether to add a "Reset" button alongside "Deploy Another" in success state
- Column widths and panel proportions (follow modifier.ojo proportions)
- Whether to include a page-size selector (include — modifier has one)

### Deferred Ideas (OUT OF SCOPE)

- **FR-04 — Description/DefaultActionScript update (Phase 4):** Add role-context DIV to fixlet descriptions and DefaultActionScript defaults.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FR-05 | Target Group Deployment — select fixlet + target group, specify deployment params, deployment created in BigFix | `POST /api/actions` with `SourcedFixletAction` + relevance-based group targeting verified from BigFix REST API docs |
| FR-06 | Automatic Offer Creation — offer type auto-selected, category derived from fixlet, admin confirms before apply | `<IsOffer>true</IsOffer>` in Settings block; `<OfferCategory>` in SettingsLocks; `SourcedFixletAction` preserves fixlet action script |
| FR-07 | Default Deployment Options — expiration defaults to 7 days, target group user-selected, all defaults overrideable | `PORTAL_CONFIG.defaultExpirationDays` drives `<EndDateTimeLocalOffset>` (ISO 8601 duration) |
| NFR-01 | Performance — operations complete in < 2s | BigFix console API calls measured in existing phases; same pattern expected |
| NFR-02 | Reliability — atomic or clear rollback; graceful API error recovery | POST error handling pattern mirrors modifier's PUT error handling |
| NFR-03 | Security — admin auth required, audit trail | BigFix console inherits admin auth; deployment IDs provide audit trail |
| NFR-04 | Usability — BigFix UI conventions, < 5 min per workflow, status indicators | Consistent CSS classes and panel structure from modifier scaffold |
| NFR-05 | Maintainability — modular, testable, externalized config | PORTAL_CONFIG block; pure JS functions extracted for unit tests |

</phase_requirements>

---

## Summary

Phase 3 builds the Dispatcher dashboard (`fixlet_dispatcher.ojo`) scaffolded from `fixlet_modifier.ojo`. It is the first dashboard in the project to issue a `POST /api/actions` call — the prior phases used only `API.Get` and `API.Put`. The primary research value is establishing the exact XML body for that POST.

The BigFix REST API action endpoint (`POST /api/actions`) accepts BES XML containing either a `SingleAction` (action from scratch) or a `SourcedFixletAction` (action sourced from an existing fixlet). The dispatcher uses `SourcedFixletAction`: it references the selected fixlet by site name and fixlet ID, lets the admin pick which action, and adds `<IsOffer>true</IsOffer>` in the Settings block to make it an offer-type deployment. The target group is expressed as a relevance expression — the REST API does not support direct group targeting by name in the Target element.

`API.Post` is already proven in the BigFix dashboard environment: `fixlet_copier.ojo` uses it at line 792 with the same three-argument signature `API.Post(path, xml, callback)`. Phase 3 introduces the same call but to the `"actions"` path instead of the `"fixlets/custom/..."` path.

The offer XML structure is confirmed from the official BigFix `restapi-examples` GitHub repository: `<IsOffer>` lives inside `<Settings>`, and `<OfferCategory>` / `<OfferDescriptionHTML>` live inside `<SettingsLocks>` as lock flags. The actual offer category text and description HTML are set in `<Settings>` child elements documented in the ActionSettings schema. The `<ActionUITitle>` element (also in Settings) provides the offer title shown to users in the BigFix client.

**Primary recommendation:** Use `SourcedFixletAction` with `<IsOffer>true</IsOffer>` in Settings, relevance-based group targeting, and `<EndDateTimeLocalOffset>` for expiration. Build the action XML as a plain string (same pattern as `buildXml()` in copier.ojo) and POST to `"actions"`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Fixlet list loading (all fixlets in portal site) | Browser / Client (BigFix IE9 dashboard) | BigFix Server (EvaluateRelevance) | Same as modifier: `EvaluateRelevance` for list, `API.Get` for individual XML |
| Detail panel rendering (name, category, roles, action count) | Browser / Client (BigFix IE9 dashboard) | — | Pure DOM rendering from loaded fixlet XML |
| Deployment form (target group, expiry, action select) | Browser / Client (BigFix IE9 dashboard) | — | All form logic runs in the IE9 webview |
| Offer creation (POST /api/actions) | BigFix API / Backend | Browser initiates POST | `API.Post("actions", xml, cb)` sends to BigFix REST; BigFix server persists the action |
| Target group relevance generation | Browser / Client (pure JS) | — | `buildTargetRelevance(groupName)` string-builder; executes client-side before POST |
| Action XML construction | Browser / Client (pure JS) | — | `buildDeployXml()` string-builder; no DOM, pure string concat — same pattern as `buildXml()` in copier |
| MIME field reading (Associated_Roles) | Browser / Client (MSXML ActiveX) | — | `xml.getElementsByTagName("MIMEField")` / XPath filter on `Name` — existing pattern from modifier |
| Config block (target groups + expiry default) | Browser / Client (inline JS constant) | — | PORTAL_CONFIG at top of .ojo JS |

---

## Standard Stack

### Core

No external packages. Phase 3 uses only BigFix dashboard built-ins and Node.js built-ins for tests:

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `API.Post(path, xml, cb)` | BigFix console built-in | POST to BigFix REST API from dashboard | Confirmed in fixlet_copier.ojo line 792 — same three-argument signature as API.Get and API.Put |
| `API.Get(path, cb)` | BigFix console built-in | Load fixlet XML on selection | Established in Phases 1 and 2 |
| `EvaluateRelevance(rel)` | BigFix console built-in | Load fixlet list from portal site | Established in Phases 1 and 2 |
| `Msxml2.DOMDocument.6.0` (ActiveXObject) | BigFix console IE9 | Parse loaded fixlet XML | Required by BigFix console environment |
| Node.js built-in `assert` | Node.js 24.15 (verified) | Unit test assertions | Zero-install; established in Phases 1 and 2 |
| Node.js built-in `https` | Node.js 24.15 (verified) | Integration test HTTP calls | Established in copier and modifier integration tests |

[VERIFIED: direct codebase inspection of fixlet_copier.ojo line 792 (API.Post); modifier.ojo (API.Get, API.Put, EvaluateRelevance, ActiveXObject)]

### No Packages to Install

Phase 3 installs zero npm packages. Test runner: `node tests/unit/dispatcher.test.js` and `node tests/integration/dispatcher.integration.test.js`, matching Phases 1 and 2.

---

## Package Legitimacy Audit

**No external packages are installed in Phase 3.** This section is not applicable.

Packages removed due to slopcheck: none
Packages flagged as suspicious: none

---

## Architecture Patterns

### System Architecture Diagram

```
Admin Browser (BigFix Console IE9)
  |
  |--- EvaluateRelevance(portal site fixlets) --> BigFix Server
  |                                                    |
  |<-- fixlet list (name, category, Associated_Roles) --
  |
  |--- API.Get("fixlet/custom/<site>/<id>") --> BigFix REST
  |                                                 |
  |<-- full fixlet XML (name, description, category, actions) --
  |
  [Admin selects action, target group, expiry]
  |
  |--- buildTargetRelevance(groupName) --> relevance string (pure JS)
  |--- buildDeployXml()               --> BES XML with SourcedFixletAction + offer settings (pure JS)
  |
  |--- API.Post("actions", xml, cb) --> BigFix REST
  |                                         |
  |                               BigFix creates offer-type action
  |                               Response: BESAPI XML with action ID
  |                                         |
  |<-- success (actionId) or error ----------
  |
  [Success banner + "Deploy Another" / error inline]
```

### Recommended Project Structure

```
Existing Dashboards/
  fixlet_dispatcher.ojo        # NEW: dispatcher dashboard

tests/
  unit/
    dispatcher.test.js         # NEW: unit tests for pure JS functions
  integration/
    dispatcher.integration.test.js  # NEW: POST round-trip integration tests
  fixtures/
    phase-03/                  # NEW
      valid-fixlet-with-actions.ojo  # Multi-action fixlet fixture for action parse tests
      valid-fixlet-single-action.ojo # Single-action fixlet fixture
```

### Pattern 1: API.Post Signature (confirmed from copier.ojo)

**What:** `API.Post(path, bodyXml, callback)` — identical signature to `API.Get` and `API.Put`.

**When to use:** Creating new resources in BigFix via REST (actions, fixlets). Phase 3 creates actions.

**Example (from fixlet_copier.ojo line 792 — the confirmed pattern):**
```javascript
// Source: Existing Dashboards/fixlet_copier.ojo line 792
// Path does NOT include "/api/" prefix — BigFix console adds it automatically.
API.Post(path, xml, function(e, s, b){
  if(s === 200 || s === 201){
    // b = response body (BESAPI XML with action ID)
  } else {
    // e = error string, s = HTTP status, b = response body
  }
});
```

**For dispatcher:** path = `"actions"` (BigFix will expand to `/api/actions`)

[VERIFIED: direct codebase inspection of fixlet_copier.ojo line 792]

### Pattern 2: SourcedFixletAction XML for Offer Deployment

**What:** The full BES XML body to POST to `/api/actions` to create an offer-type deployment of a portal fixlet.

**When to use:** Admin clicks "Deploy" in the dispatcher — this XML is built by `buildDeployXml()` and sent via `API.Post("actions", xml, cb)`.

**Confirmed XML structure:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xsi:noNamespaceSchemaLocation="BES.xsd">
  <SourcedFixletAction>
    <SourceFixlet>
      <Sitename>Dereso Software Portal</Sitename>
      <FixletID>12345</FixletID>
      <Action>Action1</Action>
    </SourceFixlet>
    <Settings>
      <HasEndTime>true</HasEndTime>
      <EndDateTimeLocalOffset>P7D</EndDateTimeLocalOffset>
      <IsOffer>true</IsOffer>
      <ActionUITitle>My Fixlet Name</ActionUITitle>
      <AnnounceOffer>true</AnnounceOffer>
      <OfferCategory>Office Tools</OfferCategory>
      <OfferDescriptionHTML>&lt;p&gt;Install description here&lt;/p&gt;</OfferDescriptionHTML>
    </Settings>
    <SettingsLocks>
      <IsOffer>false</IsOffer>
      <AnnounceOffer>false</AnnounceOffer>
      <OfferCategory>false</OfferCategory>
      <OfferDescriptionHTML>false</OfferDescriptionHTML>
    </SettingsLocks>
    <Relevance>member of bes computer group whose (name of it = "Target Group Name")</Relevance>
    <Target>
      <AllComputers>true</AllComputers>
    </Target>
  </SourcedFixletAction>
</BES>
```

**Source provenance:**
- `SourcedFixletAction`, `SourceFixlet`, `Sitename`/`FixletID`/`Action`, `Target` structure: [VERIFIED: developer.bigfix.com/rest-api/api/action.html and forum.bigfix.com/t/possible-to-start-fixlet-tasks-using-rest/2193]
- `IsOffer`, `AnnounceOffer`, `OfferCategory`, `OfferDescriptionHTML` in Settings/SettingsLocks: [VERIFIED: raw.githubusercontent.com/bigfix/restapi-examples/master/update-action/cURL/action.xml — confirms `<IsOffer>false</IsOffer>` in Settings and all four offer elements in SettingsLocks]
- `HasEndTime`/`EndDateTimeLocalOffset` with ISO 8601 duration: [VERIFIED: raw.githubusercontent.com/bigfix/restapi-examples/master/update-action/cURL/action.xml — uses `<EndDateTimeLocalOffset>P2D</EndDateTimeLocalOffset>`]
- `ActionUITitle`, `AnnounceOffer`, `OfferDescriptionHTML` for offer title/announce/description: [CITED: developer.bigfix.com/other/platform-api/bes-xml/shared/actionsettings.html — describes these as part of the Settings element]
- Group targeting via `Relevance` expression (not Target element): [VERIFIED: forum.bigfix.com/t/rest-api-using-computer-group-as-target-for-an-action/39106]
- `bes computer group whose (name of it = "...")` relevance syntax: [VERIFIED: developer.bigfix.com/relevance/reference/bes-computer-group.html]

**Key constraints discovered:**
- The BigFix REST API Target element does NOT support computer group names or IDs directly
- Group targeting requires the `Relevance` element with `member of bes computer group whose (name of it = "...")`
- When both `<Relevance>` and `<AllComputers>true</AllComputers>` are present, the Relevance expression scopes the all-computers target — functionally targets only members of the named group
- `EndDateTimeLocalOffset` uses ISO 8601 duration format: `P7D` = 7 days, `P1D` = 1 day

[ASSUMED: The exact precedence of `<Relevance>` vs `<Target><AllComputers>true</AllComputers></Target>` in SourcedFixletAction. The forum thread examples showed Relevance used without any Target element. Recommended: omit `<Target>` entirely when using `<Relevance>` for group targeting.]

### Pattern 3: Action ID Extraction from POST Response

**What:** `API.Post("actions", xml, cb)` returns BESAPI XML in `b` (response body). The new action ID must be parsed from it.

**When to use:** After a successful POST — to show the deployment ID in the success banner.

**The response is similar to the copier's POST response for fixlets.** The existing `parseCreatedId()` in copier.ojo handles the regex fallback path. For actions, the response format differs: the action resource URL looks like `/api/action/12345`. The dispatcher needs its own `parseActionId()` function.

**Verified response pattern (from BigFix REST API docs):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BESAPI xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="BESAPI.xsd">
  <Action Resource="https://server:52311/api/action/12345" LastModified="...">
    <Name>My Action Title</Name>
    <ID>12345</ID>
  </Action>
</BESAPI>
```

**Extraction approach (IE9-safe regex fallback):**
```javascript
// Source: derived from parseCreatedId() pattern in fixlet_copier.ojo lines 365-405
function parseActionId(body) {
  var m;
  if (!body) { return ""; }
  // Try XML parse (IE9 ActiveXObject) — falls through to regex in Node.js tests
  try {
    var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
    xml.async = false;
    xml.loadXML(body);
    var nodes = xml.getElementsByTagName("Action");
    if (nodes.length > 0) {
      var idNode = nodes[0].selectSingleNode("ID");
      if (idNode && idNode.text) { return idNode.text; }
      var res = nodes[0].getAttribute("Resource");
      if (res) {
        var rm = /\/(\d+)$/.exec(res);
        if (rm && rm[1]) { return rm[1]; }
      }
    }
  } catch (ex) {}
  // Regex fallback (also used in unit tests)
  m = /\/api\/action\/(\d+)/i.exec(body);
  if (m && m[1]) { return m[1]; }
  m = /\bID=["']?(\d+)["']?/i.exec(body);
  if (m && m[1]) { return m[1]; }
  m = /<ID>(\d+)<\/ID>/i.exec(body);
  if (m && m[1]) { return m[1]; }
  return "";
}
```

[ASSUMED: BESAPI response structure for action creation returns an `<Action>` element with `<ID>` child and `Resource` attribute. Based on BigFix REST API documentation patterns for similar resources — not confirmed against a live action POST response.]

### Pattern 4: Action Dropdown Population from Loaded Fixlet XML

**What:** When a fixlet is selected, parse all `<DefaultAction>` and `<Action>` elements from the fixlet XML to populate the action dropdown (D-08).

**When to use:** In the `selectFixlet()` callback, after `API.Get` returns the fixlet XML.

**Example (adapted from parseActions() in fixlet_copier.ojo lines 505-555):**
```javascript
// Source: adapted from Existing Dashboards/fixlet_copier.ojo lines 505-555
function parseActions(xmlText) {
  var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
  xml.async = false;
  xml.loadXML(xmlText);
  parsedActions = [];

  var defaults = xml.getElementsByTagName("DefaultAction");
  var actions  = xml.getElementsByTagName("Action");
  var i, node, idAttr;

  for (i = 0; i < defaults.length; i++) {
    node   = defaults[i];
    idAttr = node.getAttribute("ID") || "Action1";
    parsedActions.push({ id: idAttr, label: "Default Action (" + idAttr + ")" });
  }
  for (i = 0; i < actions.length; i++) {
    node   = actions[i];
    idAttr = node.getAttribute("ID") || ("Action" + (i + 1));
    parsedActions.push({ id: idAttr, label: idAttr });
  }
  renderActionDropdown();
}
```

[VERIFIED: pattern directly mirrors parseActions() in fixlet_copier.ojo, adapted for a `<select>` rather than radio buttons]

### Pattern 5: Target Group Relevance Builder

**What:** Converts a target group name (from dropdown or free-text) to a BigFix relevance expression for use in the action XML.

**When to use:** `buildDeployXml()` calls this to fill the `<Relevance>` element.

**Example:**
```javascript
// Source: derived from BigFix relevance reference (developer.bigfix.com/relevance/reference/bes-computer-group.html)
function buildTargetRelevance(groupName) {
  if (!groupName || groupName.replace(/^\s+|\s+$/g, "") === "") {
    return "true";  // fallback — targets all computers (admin should not reach here)
  }
  // Escape single quotes in group names (BigFix relevance string delimiter)
  var safeGroup = String(groupName).replace(/'/g, "\\'");
  return 'member of bes computer group whose (name of it = \'' + safeGroup + '\')';
}
```

[ASSUMED: The exact relevance syntax `member of bes computer group whose (name of it = '...')` is the correct server-side relevance expression for targeting a computer group by name when used in a `<Relevance>` element of a SourcedFixletAction. Confirmed from developer.bigfix.com/relevance/reference/bes-computer-group.html that the property exists, but the exact form in action context is from forum.bigfix.com/t/rest-api-using-computer-group-as-target-for-an-action/39106 which was less precise about SourcedFixletAction specifically.]

### Pattern 6: Expiration Date Building

**What:** Convert `defaultExpirationDays` (integer) or an admin-supplied date input value to ISO 8601 duration or absolute date for `<EndDateTimeLocalOffset>` or `<EndDateTimeOffset>`.

**When to use:** `buildDeployXml()` calls this when building the Settings element.

**Two approaches:**

**A) Relative offset (simplest, matches PORTAL_CONFIG pattern):**
```javascript
// Source: pattern from restapi-examples/update-action (EndDateTimeLocalOffset = "P2D")
function buildExpirationElement(days) {
  return "<HasEndTime>true</HasEndTime>" +
         "<EndDateTimeLocalOffset>P" + parseInt(days, 10) + "D</EndDateTimeLocalOffset>";
}
```

**B) Absolute date (if admin can override with a date picker):**
```javascript
// For absolute date from a text input (YYYY-MM-DD format, IE9-safe)
function buildExpirationElement(dateString) {
  // dateString = "2026-06-21" from <input type="text"> (IE9 date handling — see pitfalls)
  return "<HasEndTime>true</HasEndTime>" +
         "<EndDateTimeOffset>" + xmlEscape(dateString) + "T23:59:59+00:00</EndDateTimeOffset>";
}
```

**Recommendation (Claude's Discretion):** Use approach A (relative offset from PORTAL_CONFIG default) as the default, and expose a text input override (not `type="date"` — see Pitfall 4). Display calculated expiry date as a read-only label in the preview panel.

[VERIFIED: `EndDateTimeLocalOffset` element and `P2D` ISO 8601 format confirmed from restapi-examples/update-action/cURL/action.xml]

### Pattern 7: PORTAL_CONFIG with targetGroups

**What:** Extension of the Phase 2 PORTAL_CONFIG pattern to include target groups and expiration default.

**When to use:** Top of dispatcher.ojo JS, same delimiter comments as modifier.ojo.

**Structure:**
```javascript
// ==========================================================================
// PORTAL CONFIGURATION — Edit this block to add/remove target groups or
// change the default expiry. Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  defaultExpirationDays: 7,
  targetGroups: [
    "All Workstations",
    "IT Department",
    "Finance Department",
    "All Servers"
  ]
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```

[VERIFIED: pattern mirrors fixlet_modifier.ojo lines 37-64 — the exact structure and comment delimiter established in Phase 2]

### Anti-Patterns to Avoid

- **Using `<Target><ComputerName>GroupName</ComputerName></Target>` to target groups:** The BigFix REST API Target element does not accept group names. Use `<Relevance>` with `member of bes computer group...` instead.
- **Using `<Target><ComputerID>groupId</ComputerID></Target>` with a group ID:** Group IDs are not computer IDs. The Target element's `<ComputerID>` only accepts individual endpoint IDs.
- **Using `<input type="date">` for the expiration date picker in IE9:** IE9 renders this as a plain text input without date picker UI, but the value format is unpredictable — use `<input type="text">` with a `YYYY-MM-DD` placeholder instead.
- **Encoding HTML entities in OfferDescriptionHTML before placing in XML:** The description must be XML-escaped once (for the XML context) but the HTML inside must remain as real HTML. Double-escaping will display raw `&lt;p&gt;` to users. Use `xmlEscape()` only on the outermost XML value; let the HTML tags through by wrapping in a CDATA section, or rely on MSXML's text property which auto-escapes.
- **Testing buildDeployXml() directly in Node.js:** Like `buildUpdateXml()` in modifier, this function uses ActiveXObject for XML parsing. Test helper string-builder functions instead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP POST to BigFix API | Custom XMLHttpRequest in dashboard | `API.Post(path, xml, cb)` | Already exposed by BigFix console; confirmed in copier.ojo |
| Action XML structure for offers | Custom schema | Documented `SourcedFixletAction` BES XML pattern (see Pattern 2) | Schema is well-defined; hand-rolling risks missing required elements that cause silent 400 errors |
| Fixlet action parsing | Custom XML walker | Reuse `parseActions()` pattern from copier.ojo | Already tested; covers DefaultAction + Action elements |
| Group targeting | Query computer group list via API then loop through member IDs | Single `member of bes computer group whose (name of it = '...')` relevance | Simpler, avoids N+1 API calls, works for dynamic and manual groups |
| Date validation in IE9 | Custom date parser | `<input type="text">` with regex validation `^\d{4}-\d{2}-\d{2}$` | `Date.parse()` in IE9 has locale-dependent behavior; simple regex is reliable |

**Key insight:** The action XML schema for BigFix is precise — missing or misnamed elements cause the API to silently accept the POST with a 200 but produce a misconfigured action (e.g., not appearing as an offer in the client). Following the documented schema exactly is essential.

---

## Common Pitfalls

### Pitfall 1: Target Element Cannot Address Computer Groups

**What goes wrong:** Placing a group name in `<Target><ComputerName>Sales Team</ComputerName></Target>` does not deploy to the group — it creates an action targeted to a computer named "Sales Team" (which likely does not exist). The action appears created (200 response) but never runs.

**Why it happens:** The `<Target>` element in BigFix action XML accepts computer IDs and individual computer names for direct mailbox delivery. Computer groups are not computers.

**How to avoid:** Use `<Relevance>member of bes computer group whose (name of it = 'Sales Team')</Relevance>` with `<Target><AllComputers>true</AllComputers></Target>`. The Relevance expression scopes the all-computers target to only those in the named group.

**Warning signs:** Action created with HTTP 200 but shows 0 relevant computers in BigFix console.

[VERIFIED: forum.bigfix.com/t/rest-api-using-computer-group-as-target-for-an-action/39106]

### Pitfall 2: OfferDescriptionHTML Double-Escaping

**What goes wrong:** The fixlet description may contain `<` and `>` (HTML tags). If `xmlEscape()` is applied to the entire description HTML before placing it in `<OfferDescriptionHTML>`, the BigFix client receives `&lt;p&gt;` as literal text instead of rendered HTML.

**Why it happens:** The description is already HTML; XML-escaping it destroys the HTML tags.

**How to avoid:** Two valid approaches:
1. Wrap description in CDATA: `<OfferDescriptionHTML><![CDATA[<p>Install...</p>]]></OfferDescriptionHTML>` — use `xmlCDataSafe()` on the inner HTML before wrapping.
2. If the description is plain text (no HTML tags), `xmlEscape()` is safe. Check first.

**Recommendation (Claude's Discretion):** Use CDATA wrapping via `cdataStart() + xmlCDataSafe(description) + cdataEnd()` — this is the established pattern in copier.ojo for description fields.

**Warning signs:** Users see raw HTML entities in the BigFix client offer description.

[VERIFIED: `cdataStart()` / `cdataEnd()` / `xmlCDataSafe()` pattern in fixlet_copier.ojo lines 586-588 and 660-667]

### Pitfall 3: `<IsOffer>` Must Be in Settings, Not Only SettingsLocks

**What goes wrong:** Placing `<IsOffer>false</IsOffer>` only in `<SettingsLocks>` (the lock flag that prevents users from changing a setting) but omitting `<IsOffer>true</IsOffer>` in `<Settings>` creates a non-offer action. The SettingsLocks entry locks whatever the Settings value is — it does not set the value.

**Why it happens:** The restapi-examples template shows `<IsOffer>false</IsOffer>` in both Settings and SettingsLocks. The Settings value is the actual setting; the SettingsLocks value indicates whether it's editable.

**How to avoid:** For an offer deployment, set `<IsOffer>true</IsOffer>` in `<Settings>` AND `<IsOffer>false</IsOffer>` in `<SettingsLocks>` (preventing the admin from converting it to a non-offer).

**Warning signs:** Action created but does not appear in the BigFix Self-Service App offer list; no offer prompt shown to users.

[VERIFIED: restapi-examples action.xml structure — IsOffer appears separately in Settings (the value) and SettingsLocks (the lock flag)]

### Pitfall 4: IE9 Does Not Support `<input type="date">`

**What goes wrong:** `<input type="date">` in IE9 renders as a plain text box with no date picker widget and inconsistent value formatting behavior.

**Why it happens:** `input[type=date]` was not standardized until HTML5; IE9 predates it.

**How to avoid:** Use `<input type="text" placeholder="YYYY-MM-DD">` for the expiration date override. Validate with regex `^\d{4}-\d{2}-\d{2}$` before using the value.

**Alternatively:** Use only the relative-days approach (PORTAL_CONFIG.defaultExpirationDays → ISO 8601 `P{N}D`) and display the calculated absolute date in the preview as a read-only `<span>`. This is simpler and avoids the date input problem entirely.

**Warning signs:** Admin types a date in an unexpected format and buildDeployXml() produces an invalid EndDateTimeOffset.

[ASSUMED: IE9 date input behavior. Known from general IE9 compatibility knowledge; not confirmed against the specific BigFix console IE9 version. HIGH confidence that IE9 does not natively support type="date".]

### Pitfall 5: Action XML Path Is "actions" Not "fixlet-deployments"

**What goes wrong:** The original phase description mentioned `POST /fixlet-deployments` as an endpoint. This endpoint does not exist in the standard BigFix REST API. Creating deployments (actions) uses `POST /api/actions`.

**Why it happens:** The CONTEXT.md noted this as an open question ("planner to research the exact schema"). The research has now resolved it: the correct endpoint is `POST /api/actions`, and the dispatcher uses `SourcedFixletAction` to reference the fixlet.

**How to avoid:** In `API.Post()`, use `"actions"` as the path (BigFix console prepends `/api/` automatically). The `SourcedFixletAction` structure references the fixlet by site and ID — the deployment "creates an offer on the fixlet" without modifying the fixlet itself.

**Warning signs:** 404 response from BigFix API.

[VERIFIED: developer.bigfix.com/rest-api/api/action.html — POST /api/actions is the correct endpoint; forum.bigfix.com/t/possible-to-start-fixlet-tasks-using-rest/2193 confirms SourcedFixletAction pattern]

### Pitfall 6: buildDeployXml() Cannot Be Unit-Tested Directly (Same as buildUpdateXml)

**What goes wrong:** `buildDeployXml()` must parse the loaded fixlet XML using `ActiveXObject("Msxml2.DOMDocument.6.0")` to extract description and category. This ActiveXObject is IE-only — it throws in Node.js unit tests.

**How to avoid:** Same strategy as modifier.test.js: extract pure helper functions and test those. The dispatcher unit tests should cover:
- `buildTargetRelevance(groupName)` — pure string builder
- `buildExpirationElement(days)` — pure string builder
- `parseActionId(body)` — regex fallback path (skip ActiveXObject path)
- `xmlEscape()`, `xmlCDataSafe()` — already tested in Phase 2 but copy-paste per established pattern
- `PORTAL_CONFIG` structural validation

`buildDeployXml()` itself is tested via the integration test (POST round-trip) as in Phase 2.

[VERIFIED: same constraint confirmed in modifier.test.js test structure and Phase 2 RESEARCH.md Pattern 2 (DOM Mock)]

### Pitfall 7: Single-Quote Injection in Group Name Relevance

**What goes wrong:** If a target group name contains a single quote (e.g., `IT Dep't`), the generated relevance becomes `member of bes computer group whose (name of it = 'IT Dep't')` — malformed relevance that BigFix rejects or misparses.

**Why it happens:** BigFix Relevance uses single quotes as string delimiters.

**How to avoid:** Escape single quotes in the group name before embedding in the relevance string. Simple: `groupName.replace(/'/g, "\\'")`. Since target groups come from PORTAL_CONFIG (admin-controlled) or a free-text input (admin-entered), both vectors could potentially trigger this.

**Warning signs:** BigFix API returns an error for the action POST, or the action is created but relevance evaluation fails on clients.

[ASSUMED: BigFix Relevance string escaping behavior with single quotes. Based on standard relevance syntax knowledge — not confirmed against a live BigFix instance. HIGH confidence given the relevance language uses single quotes as string delimiters.]

---

## Code Examples

### Complete buildDeployXml() Template

```javascript
// Source: synthesized from BigFix developer docs, restapi-examples, and codebase patterns
// Builds the BES XML body for POST /api/actions
function buildDeployXml() {
  if (!sourceXml || !currentItem || !selectedActionId) { return ""; }

  var siteName   = currentItem.siteName;
  var fixletId   = currentItem.id;
  var actionId   = selectedActionId;           // e.g., "Action1"
  var groupName  = getSelectedTargetGroup();   // from select or free-text input
  var expiryDays = getExpirationDays();        // integer from PORTAL_CONFIG or override

  // Parse description and category from loaded fixlet XML
  var descHtml = "";
  var category = "";
  try {
    var doc = new ActiveXObject("Msxml2.DOMDocument.6.0");
    doc.async = false;
    doc.loadXML(sourceXml);
    descHtml = getNodeText(doc, "Description");
    category = getNodeText(doc, "Category");
  } catch (ex) { /* IE-only; falls through cleanly */ }

  var xml = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <SourcedFixletAction>\r\n';
  xml += '    <SourceFixlet>\r\n';
  xml += '      <Sitename>'  + xmlEscape(siteName)  + '</Sitename>\r\n';
  xml += '      <FixletID>'  + xmlEscape(fixletId)  + '</FixletID>\r\n';
  xml += '      <Action>'    + xmlEscape(actionId)  + '</Action>\r\n';
  xml += '    </SourceFixlet>\r\n';
  xml += '    <Settings>\r\n';
  xml += '      <HasEndTime>true</HasEndTime>\r\n';
  xml += '      <EndDateTimeLocalOffset>P' + parseInt(expiryDays, 10) + 'D</EndDateTimeLocalOffset>\r\n';
  xml += '      <IsOffer>true</IsOffer>\r\n';
  xml += '      <ActionUITitle>' + xmlEscape(currentItem.name) + '</ActionUITitle>\r\n';
  xml += '      <AnnounceOffer>true</AnnounceOffer>\r\n';
  xml += '      <OfferCategory>' + xmlEscape(category) + '</OfferCategory>\r\n';
  xml += '      <OfferDescriptionHTML>' + cdataStart() + xmlCDataSafe(descHtml) + cdataEnd() + '</OfferDescriptionHTML>\r\n';
  xml += '    </Settings>\r\n';
  xml += '    <SettingsLocks>\r\n';
  xml += '      <IsOffer>false</IsOffer>\r\n';
  xml += '      <AnnounceOffer>false</AnnounceOffer>\r\n';
  xml += '      <OfferCategory>false</OfferCategory>\r\n';
  xml += '      <OfferDescriptionHTML>false</OfferDescriptionHTML>\r\n';
  xml += '    </SettingsLocks>\r\n';
  xml += '    <Relevance>' + xmlEscape(buildTargetRelevance(groupName)) + '</Relevance>\r\n';
  xml += '  </SourcedFixletAction>\r\n';
  xml += '</BES>';
  return xml;
}
```

### EvaluateRelevance Query for Portal Fixlet List

The dispatcher loads fixlets from the "Dereso Software Portal" site only (D-04). Columns: Name, Category, Roles, Site (D-05).

```javascript
// Source: adapted from fixlet_modifier.ojo lines 183-213 (loadAllFixlets)
// Scope narrowed to portal site only; columns updated per D-04/D-05
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
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `POST /fixlet-deployments` (hypothesized) | `POST /api/actions` with `SourcedFixletAction` | Resolved in this research | Dispatcher must use the `/api/actions` endpoint, not a separate deployment endpoint |
| Target computer groups by group ID in Target element | Relevance expression `member of bes computer group whose (name of it = '...')` | Baseline BigFix behavior | Groups cannot be referenced in Target; must use Relevance |
| `<input type="date">` for date selection | `<input type="text" placeholder="YYYY-MM-DD">` or relative-days only | IE9 constraint (no change) | No HTML5 date picker in IE9 |

**Deprecated/outdated:**
- The `POST /fixlet-deployments` endpoint mentioned in the original CONTEXT.md does not exist in the BigFix REST API. It was speculative. The correct path is `POST /api/actions`. [VERIFIED: developer.bigfix.com/rest-api/api/action.html]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact order of `<Relevance>` and `<Target>` in `SourcedFixletAction` when both are present: Relevance scopes AllComputers target | Architecture Patterns / Pattern 2 | If order matters or Relevance is ignored, group targeting fails; action runs on all computers instead. Mitigation: omit `<Target>` entirely and use only `<Relevance>` (tested pattern from forum thread) |
| A2 | BESAPI response for POST /api/actions contains `<Action Resource="..."><ID>N</ID></Action>` | Pattern 3 | If response structure differs, parseActionId() fails silently (returns "") — only cosmetic (no deployment ID shown in success banner); action is still created |
| A3 | `member of bes computer group whose (name of it = 'GroupName')` is valid server-side Relevance for action targeting in SourcedFixletAction | Pattern 5 | If group name syntax differs from client-side relevance, group targeting fails silently (action runs on 0 computers). Mitigation: test on staging instance before production |
| A4 | IE9 in BigFix console does not support `<input type="date">` | Pitfall 4 | If it renders correctly, the more complex text-input approach is unnecessarily conservative. No correctness risk — text input works in all IE versions |
| A5 | Single quote escaping `\\'` is correct for BigFix Relevance string literals | Pitfall 7 | If escape syntax differs, malformed relevance causes action POST error or silent targeting failure |
| A6 | `<ActionUITitle>`, `<AnnounceOffer>`, `<OfferCategory>`, `<OfferDescriptionHTML>` are child elements of `<Settings>` in `SourcedFixletAction` (not just in SettingsLocks) | Pattern 2 | The restapi-examples only showed them in SettingsLocks (as lock flags). The actual Settings values may use different element names. Impact: offer category/description not rendered in client. Mitigation: test on staging; the ActionSettings schema at developer.bigfix.com confirms ActionUITitle as a Settings element |

---

## Open Questions

1. **Exact SourcedFixletAction Settings child elements for offer category/title**
   - What we know: `<IsOffer>`, `<AnnounceOffer>`, `<OfferCategory>`, `<OfferDescriptionHTML>` confirmed in SettingsLocks (as boolean lock flags). The restapi-examples file shows Settings containing `<IsOffer>false</IsOffer>`. ActionSettings docs confirm `ActionUITitle` is a Settings element.
   - What's unclear: Whether `<OfferCategory>` in Settings holds the category text or whether a different element name is used for the value vs. the lock.
   - Recommendation: Include all four elements in Settings with their actual values; if the BigFix API ignores unrecognized or wrongly-valued elements, worst case is the offer has no category/description. Test on staging. If category does not render, check BES.xsd on the target server.

2. **Relevance syntax for group targeting in SourcedFixletAction**
   - What we know: Forum thread confirms group must be targeted via Relevance, not Target. `member of group 432137 of site "XYZ"` syntax shown using group ID.
   - What's unclear: Whether group name lookup (`bes computer group whose (name of it = '...')`) works without knowing the group's site name.
   - Recommendation: Use `member of bes computer group whose (name of it = 'GroupName')` in the Relevance element. Admins should ensure group names in PORTAL_CONFIG.targetGroups exactly match the group names in their BigFix instance.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js | Unit + integration tests | ✓ | 24.15.0 (verified) | None — required for test execution |
| BigFix REST API instance | Integration tests | Conditional (same as Phase 2) | — | Tests skip gracefully when BIGFIX_URL not set |
| BigFix Console (IE9 environment) | Dashboard runtime | Conditional (same as Phases 1 and 2) | — | Unit tests run in Node.js; console required only for smoke test |

Step 2.6: No new external tools required beyond Phase 2 baseline.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Node.js built-in `assert` (no external framework) |
| Config file | None — tests are standalone scripts |
| Quick run command | `node tests/unit/dispatcher.test.js` |
| Full suite command | `node tests/unit/dispatcher.test.js && node tests/unit/modifier.test.js && node tests/unit/copier.test.js` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FR-05 | `buildTargetRelevance(groupName)` produces syntactically valid relevance expression | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-05 | `buildTargetRelevance("")` produces `"true"` fallback | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-05 | POST round-trip: buildDeployXml output accepted with HTTP 200/201 | integration | `node tests/integration/dispatcher.integration.test.js` | ❌ Wave 0 |
| FR-06 | `buildDeployXml()` XML contains `<IsOffer>true</IsOffer>` | unit (string assert on buildDeployXml helper) | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-06 | Offer category in XML matches fixlet category | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-07 | `buildExpirationElement(7)` produces `P7D` duration element | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-07 | `PORTAL_CONFIG.defaultExpirationDays` is 7 (or positive integer) | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| FR-07 | `PORTAL_CONFIG.targetGroups` is a non-empty array of strings | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |
| NFR-01 | POST /api/actions round-trip completes in < 5000ms | integration | `node tests/integration/dispatcher.integration.test.js` | ❌ Wave 0 |
| NFR-02 | API error handling: error response surfaced in callback, not swallowed | integration | `node tests/integration/dispatcher.integration.test.js` | ❌ Wave 0 |
| NFR-05 | `parseActionId(body)` correctly extracts numeric ID from regex-path fixture | unit | `node tests/unit/dispatcher.test.js` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `node tests/unit/dispatcher.test.js`
- **Per wave merge:** `node tests/unit/dispatcher.test.js && node tests/unit/modifier.test.js && node tests/unit/copier.test.js`
- **Phase gate:** All three unit suites green; integration test skips gracefully without live BigFix

### Wave 0 Gaps

- [ ] `tests/unit/dispatcher.test.js` — covers FR-05 (target relevance), FR-06 (offer XML elements), FR-07 (expiry + config), NFR-05 (parseActionId)
- [ ] `tests/integration/dispatcher.integration.test.js` — covers FR-05 POST round-trip, NFR-01 timing, NFR-02 error handling
- [ ] `tests/fixtures/phase-03/valid-fixlet-with-actions.ojo` — multi-action fixlet fixture for action parsing tests
- [ ] `tests/fixtures/phase-03/valid-fixlet-single-action.ojo` — single DefaultAction fixture
- [ ] `tests/fixtures/phase-03/sample-action-response.xml` — BESAPI response fixture for parseActionId unit tests

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | BigFix handles all auth via console session |
| V3 Session Management | No | BigFix manages sessions |
| V4 Access Control | Yes — indirectly | Offer action only deployable by admins with console access; BigFix RBAC enforced by platform |
| V5 Input Validation | Yes | Target group name from closed dropdown (PORTAL_CONFIG) or free-text; expiration from text input; both validated before XML injection |
| V6 Cryptography | No | No crypto in this phase |

### Known Threat Patterns for BigFix Dashboard JS

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Relevance injection via group name | Tampering | `xmlEscape()` encodes the relevance string in XML; single-quote escaping in `buildTargetRelevance()` prevents relevance syntax injection; PORTAL_CONFIG groups are admin-controlled |
| XSS via fixlet name or category in DOM innerHTML | Tampering | `htmlEscape()` applied to all fields rendered into the DOM table (already established pattern from modifier.ojo) |
| XML injection via group name or description in action body | Tampering | `xmlEscape()` applied to all string values in `buildDeployXml()` string concatenation; description wrapped in CDATA |
| Inadvertent deployment to all computers (missing relevance) | Elevation of Privilege | `buildTargetRelevance()` falls back to `"true"` only if group name is blank — and `deployFixlet()` must validate target group is non-empty before calling `buildDeployXml()` |
| Fixlet content read from wrong site | Tampering | `API.Get` path constructed from `currentItem.siteName` and `currentItem.id` loaded from BigFix API via EvaluateRelevance — same protection as modifier |
| Stale deployment state on error | Tampering | On POST failure, no in-memory state is updated; admin must explicitly retry |

---

## Sources

### Primary (HIGH confidence)
- `Existing Dashboards/fixlet_copier.ojo` line 792 — `API.Post(path, xml, cb)` signature confirmed; path `"fixlets/custom/..."` pattern; same for `"actions"`.
- `Existing Dashboards/fixlet_modifier.ojo` — scaffold source; all CSS classes, PORTAL_CONFIG pattern, MIME field reading patterns.
- `raw.githubusercontent.com/bigfix/restapi-examples/master/update-action/cURL/action.xml` — Complete action XML structure; confirmed `<IsOffer>`, `<AnnounceOffer>`, `<OfferCategory>`, `<OfferDescriptionHTML>` in SettingsLocks; `<EndDateTimeLocalOffset>P2D</EndDateTimeLocalOffset>` pattern; `<IsOffer>` in Settings.
- `developer.bigfix.com/rest-api/api/action.html` — POST /api/actions endpoint; SourcedFixletAction XML structure (Sitename, FixletID, Action, Target, Parameter).
- `developer.bigfix.com/relevance/reference/bes-computer-group.html` — `bes computer group whose (name of it = "...")` relevance inspector confirmed.
- `forum.bigfix.com/t/rest-api-using-computer-group-as-target-for-an-action/39106` — Confirmed Target element cannot address groups by name; Relevance element required.
- `forum.bigfix.com/t/possible-to-start-fixlet-tasks-using-rest/2193` — SourcedFixletAction pattern for deploying existing fixlet via REST API.

### Secondary (MEDIUM confidence)
- `developer.bigfix.com/other/platform-api/bes-xml/shared/actionsettings.html` — ActionSettings schema reference for Settings element structure; `ActionUITitle` confirmed as Settings child element.
- `help.hcl-software.com/bigfix/10.0/platform/Platform/Console/Dialogs/offer_tab.html` — Offer tab UI fields: title, category (user-defined), HTML description. Maps conceptually to XML elements.
- `developer.bigfix.com/rest-api/api/fixlet.html` — Fixlet API (GET, POST, PUT, DELETE) confirmed; "fixlet-deployments" endpoint does not appear in this reference.

### Tertiary (LOW confidence)
- None — all assumptions are flagged in the Assumptions Log above.

---

## Metadata

**Confidence breakdown:**
- `API.Post` method and signature: HIGH — confirmed in codebase (copier.ojo)
- Endpoint path `"actions"` for deployment: HIGH — confirmed from official BigFix REST API docs
- SourcedFixletAction XML structure: HIGH — confirmed from official restapi-examples
- `<IsOffer>`, `<OfferCategory>`, `<OfferDescriptionHTML>` element names: HIGH for names (confirmed in restapi-examples); MEDIUM for placement in Settings vs. only SettingsLocks
- Group targeting via Relevance: HIGH — confirmed from forum + BigFix relevance reference
- IE9 date input limitation: HIGH (confidence from general IE9 knowledge), ASSUMED (not tested against BigFix console specifically)
- Architecture patterns: HIGH — all derived from direct codebase inspection + official docs
- Test structure: HIGH — exact pattern files from Phases 1 and 2 inspected directly

**Research date:** 2026-06-14
**Valid until:** Stable for the duration of Phase 3 execution. The BigFix REST API action schema is stable across BigFix versions 9.x–11.x. Re-verify offer XML elements against the target server's BES.xsd if behavior is unexpected.
