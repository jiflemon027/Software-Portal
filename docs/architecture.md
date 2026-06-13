# Dereso Fixlet Copier — Architecture & Design

## Overview

The Fixlet Copier is a BigFix wizard dashboard implemented as a single HTML page embedded within
a BES XML `<Wizard>` element (the `.ojo` file format). All logic is client-side JavaScript
running inside the BigFix Console browser, which operates in IE 9 compatibility mode. The
dashboard uses two BigFix Console built-ins exclusively: the `API` object for REST calls and
the `EvaluateRelevance` function for querying the BigFix relevance engine. No external libraries
or frameworks are loaded — the entire implementation is self-contained in the `.ojo` file.

---

## Global State

All mutable state is stored in 14 module-level `var` declarations at the top of the JavaScript
block (copier.ojo lines 42–56). No closures or objects are used to encapsulate this state.

| Variable | Type | Purpose |
|----------|------|---------|
| `currentItems` | `Array` | Filtered and sorted subset of fixlets shown on the current page. Rebuilt by `filterAndRender()` on every search/sort/page change. |
| `currentItem` | `Object \| null` | The single fixlet currently selected by the user (radio button row). Has properties: `id`, `name`, `siteType`, `siteName`, `category`, `severity`. Set to `null` on init. |
| `sourceXml` | `String` | Raw XML body of the selected fixlet, fetched from the BigFix REST API. Empty string until a fixlet is selected and loaded. Used as the precondition guard in `createFixlet()`. |
| `parsedActions` | `Array` | Array of action objects extracted by `parseActions()`. Each entry has: `kind` (`"default"` or `"action"`), `xml` (full action block string), `script` (ActionScript text), `title` (action description text). |
| `selectedActionIndex` | `Number` | Zero-based index into `parsedActions` identifying which action is currently displayed in the ActionScript editor. Default: `0`. |
| `lastCreatedId` | `String` | Fixlet ID returned by BigFix after a successful `API.Post`. Used by `openCreatedFixlet()` to filter the grid. Empty string until a clone succeeds. |
| `lastCreatedSite` | `String` | Name of the custom site used in the last successful clone operation. Stored alongside `lastCreatedId` for display in the "Created Info" panel. |
| `currentPage` | `Number` | Zero-based page cursor for the fixlet grid. Reset to `0` on sort, search, or new load. |
| `allItems` | `Array` | Full, unfiltered list of all fixlet objects returned by `EvaluateRelevance`. `filterAndRender()` reads from this and populates `currentItems`. |
| `searchTimer` | `Number \| null` | Return value of `setTimeout()` used to debounce the search input event. Cleared and reset on each keypress. |
| `sourceMimeFields` | `Array` | MIME fields (custom metadata) extracted from the selected fixlet via `parseSourceFields()`. Each entry is `{name, value}`. |
| `sortColumn` | `String` | Name of the column currently used for sorting (`"id"`, `"name"`, `"category"`, `"siteName"`, `"severity"`, or `""` for unsorted). |
| `sortAsc` | `Boolean` | Sort direction. `true` = ascending, `false` = descending. Toggled by `sortBy()` when the same column is clicked twice. |
| `selectedItemIndex` | `Number` | Index within `currentItems` of the currently selected row. Set to `-1` on init (no selection). Updated by `selectFixlet(i)`. |

---

## Data Flow

The copier's runtime behaviour follows a 5-step pipeline from dashboard initialisation through
fixlet creation.

### Step 1 — Dashboard Initialisation

**Function:** `initDashboard()` → `loadSitenames()`  
**Reads:** Nothing (cold start)  
**Writes:** Resets `currentItems`, `currentItem`, `sourceXml`, `parsedActions`, `lastCreatedId`, `lastCreatedSite` to their initial values  
**Side effects:**
- DOM: Status bar set to "Ready."
- Calls `loadSitenames()`, which invokes `EvaluateRelevance` with a relevance expression that
  returns all BigFix sites with their types. Results are split on the `|||` delimiter and used
  to populate the **Sites** multi-select filter and the **Target Site** dropdown (custom sites only).

### Step 2 — Load Fixlets

**Trigger:** User clicks "Load Fixlets"  
**Function:** `loadAllFixlets()` → `filterAndRender()`  
**Reads:** DOM — selected site filter values, search text  
**Writes:** `allItems` (full unfiltered list), `currentItems` (filtered/sorted for display), `currentPage = 0`  
**Side effects:**
- `EvaluateRelevance` returns all BigFix fixlets as multi-field rows (ID, name, siteType,
  siteName, category, severity), split on `|||`.
- `filterAndRender()` applies search text and site filter to `allItems`, applies any active
  sort via `applySortToCurrentItems()`, and re-renders the HTML table including pagination
  controls.

### Step 3 — Select a Source Fixlet

**Trigger:** User clicks a radio button row  
**Function:** `selectFixlet(i)` → `API.Get(path)` callback → `parseSourceFields(b)` + `parseActions(b)`  
**Reads:** `currentItems[i]` (to build the API path)  
**Writes:** `currentItem`, `selectedItemIndex`, `sourceXml`, `parsedActions`, `sourceMimeFields`  
**Side effects:**
- API call: `GET fixlet/{siteType}/{siteName}/{id}` fetches the source fixlet's full XML.
- DOM: Title and Category fields populated from fetched XML; ActionScript editor populated
  with the first action's script; status bar updated.
- `parseSourceFields()` uses `ActiveXObject("Msxml2.DOMDocument.6.0")` to parse the XML
  and extract Description, Category, Relevance, and MIME fields.
- `parseActions()` extracts `DefaultAction` and `Action` elements and populates the
  action selector list.

### Step 4 — Clone the Fixlet

**Trigger:** User clicks "Clone Selected Fixlet"  
**Function:** `createFixlet()` → `buildXml()` → `API.Post(path, xml)` callback → `parseCreatedId(b)` → `updateCreatedInfo()`  
**Reads:** `sourceXml` (precondition guard), `parsedActions` (precondition guard), DOM (all form field values)  
**Writes:** `lastCreatedId`, `lastCreatedSite`  
**Side effects:**
- Three precondition guards checked before any API call (see Input Guard Pattern below).
- `buildXml()` assembles the BES/Fixlet XML string from current form field values.
- API call: `POST fixlets/custom/{siteName}` submits the XML.
- On success: `parseCreatedId(b)` extracts the new fixlet ID from the response body;
  `updateCreatedInfo()` updates the "Created Info" panel; status bar shows success message;
  grid is refreshed and filtered to the new ID.
- On failure: Alert shows HTTP status and error details; status bar shows failure message.

### Step 5 — XML Assembly (buildXml internal)

**Function:** `buildXml()` → `buildActionInsertion()` → BES/Fixlet XML string  
**Reads:** All DOM form fields (Title, Category, Description, Relevance, clone mode selector, ActionScript editor)  
**Writes:** Returns the assembled XML string (no global state modified)  
**Side effects:** None — pure string construction  
**Output shape:**
```
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="...">
  <Fixlet>
    <Title>{xmlEscape(title)}</Title>
    <Description><![CDATA[{xmlCDataSafe(description)}]]></Description>
    <Relevance>...</Relevance>
    <!-- MIME fields -->
    <!-- Action block(s) from buildActionInsertion() -->
  </Fixlet>
</BES>
```

---

## XML Building Strategy

The copier uses two distinct encoding strategies depending on the content type:

### CDATA Wrapping (Description, ActionScript)

Content that may contain markup or special characters is wrapped in a CDATA section:

```javascript
function cdataStart(){ return '<!' + '[CDATA['; }
function cdataEnd()  { return ']]' + '>'; }
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }
```

The `cdataStart()` and `cdataEnd()` functions return the CDATA delimiters as concatenated
string literals. This prevents the XML parser that processes the `.ojo` file from consuming
the inner CDATA delimiters when the dashboard HTML is loaded. `xmlCDataSafe()` escapes any
`]]>` sequences within the content to prevent premature CDATA section termination.

### Entity Escaping (Title, Category, and other text fields)

Short text fields that appear as XML element content or attributes are encoded using entity
references:

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

### Relevance XML

Multi-line relevance expressions are built line by line. Each non-blank line becomes a separate
`<Relevance>` element. Blank and whitespace-only lines are silently skipped. If all lines are
blank, the output defaults to `<Relevance>true</Relevance>`.

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

---

## BigFix API Surface

The dashboard interacts with three BigFix REST API endpoints. The `API` object is provided
by the BigFix Console and handles base URL construction and authentication transparently —
no explicit auth headers or credentials are present in the dashboard code.

| Method | Path Template | Purpose | Success Codes |
|--------|--------------|---------|---------------|
| `GET` | `sites` | Test API connectivity | 200 |
| `GET` | `fixlet/{siteType}/{siteName}/{id}` | Fetch source fixlet XML for display and editing | 200 |
| `POST` | `fixlets/custom/{siteName}` | Create a new fixlet in the specified custom site | 200, 201 |

All path segments are URL-encoded with `encodeURIComponent()` to handle site names and fixlet
IDs that contain spaces or special characters.

---

## EvaluateRelevance Convention

The dashboard uses `EvaluateRelevance` to query the BigFix relevance engine for site lists
and fixlet lists. Multiple fields per result row are concatenated using `|||` as a delimiter.

**Example — site loading** (copier.ojo line 154):
```javascript
var rel = '(name of it & "|||" & (if external site flag of it then "External" else ...)) of (bes sites ; bes custom sites)';
var data = EvaluateRelevance(rel);
for(var i = 0; i < data.length; i++){
  var p = String(data[i]).split("|||");
  // p[0] = site name, p[1] = site type
}
```

**Example — fixlet loading** (copier.ojo line 192):
```javascript
var rel = '(id of it as string & "|||" & name of it & "|||" & ... & "|||" & category & "|||" & severity) of bes fixlets';
var data = EvaluateRelevance(rel);
// p[0]=id, p[1]=name, p[2]=siteType, p[3]=siteName, p[4]=category, p[5]=severity
```

`EvaluateRelevance` returns a JavaScript array where each element is a string representing
one result row. The `|||` delimiter is the project-wide convention for separating fields
within a single relevance result row.

---

## IE Compatibility Notes

The dashboard targets Internet Explorer 9 compatibility mode, as required by the BigFix
Console browser:

```html
<meta http-equiv="X-UA-Compatible" content="IE=9">
```

Key IE-specific code paths:

- **`parseSourceFields()`** and **`parseActions()`** create an `ActiveXObject("Msxml2.DOMDocument.6.0")`
  to parse the source fixlet's XML. This is IE-only; the call will throw in any non-IE environment.
- **`parseCreatedId()`** attempts `ActiveXObject` XML parsing first, then falls back to
  three regex-based strategies when `ActiveXObject` is unavailable or throws. This three-tier
  fallback design exists precisely to handle environments where `ActiveXObject` may be blocked
  or unavailable.
- **String/DOM methods** used throughout are limited to IE 9-compatible APIs (no `querySelector`,
  no `const`/`let`, no arrow functions, no template literals).

---

## Audit Trail (NFR-03)

### Current Capability (Phase 1)

The copier records each clone operation via `setStatus()` (copier.ojo lines 116–119), which
writes a message to the `#status` element in the dashboard HTML:

```javascript
function setStatus(msg){
  var el = document.getElementById("status");
  if(el){ el.innerHTML = msg; }
}
```

On success, the status message is:
```
Created via fixlets/custom/{site} ID={newId}
```

On failure:
```
Failed via {path} status={s}
```

On connectivity test:
```
API OK
```

### Known Limitation

This status message is **ephemeral**. It is displayed in the BigFix Console UI only and is
**not written to any persistent log, file, database, or event stream**. Once the dashboard
session ends, the user navigates away, or the status bar is overwritten by the next operation,
the audit record is permanently lost.

### Deferred Work — NFR-03

**NFR-03** requires a persistent audit trail of all fixlet copy operations. Phase 1 does **not**
satisfy this requirement. The current `setStatus()` mechanism is the only record produced by a
clone operation.

Persistent audit logging is deferred to **Phase 4 (Robustness)**. Candidate approaches include:

- Writing clone events to a BigFix analysis property that accumulates records.
- Appending entries to a server-side log file via a separate API endpoint.
- Emitting events to an external logging or SIEM service.

Until Phase 4 is implemented, operators who require an audit trail must manually record clone
operations from the status bar message immediately after each clone. Automated compliance
reporting against NFR-03 is not possible with the Phase 1 implementation.
