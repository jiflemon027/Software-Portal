# Dereso Fixlet Copier — BigFix API Integration Guide

## The API Object

The BigFix Console provides a built-in `API` object to all dashboard scripts. This object
handles base URL construction, authentication, and HTTP transport transparently — dashboard
code does not set auth headers or manage sessions. The admin must be logged into BigFix
Console for the `API` object to function.

Three method signatures are used across the Software Portal dashboards:

```javascript
// Fetch a resource by relative path
API.Get(relativePath, callback(errorMsg, statusCode, responseBody))

// Create or submit a resource with an XML body
API.Post(relativePath, bodyXml, callback(errorMsg, statusCode, responseBody))

// Update an existing resource with an XML body (used in modifier dashboard)
API.Put(relativePath, bodyXml, callback(errorMsg, statusCode, responseBody))
```

**Callback parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `errorMsg` | String | Human-readable error description. Empty on success. |
| `statusCode` | Number | HTTP status code returned by the BigFix server. |
| `responseBody` | String | Raw response body as a string. For POST operations, this contains BES XML with the created resource details. |

The base URL (e.g., `https://bigfix.example.com:52311/api/`) is implicit — dashboard code
provides only the path segment relative to `/api/`. No real hostnames, credentials, or tokens
appear in dashboard source code.

---

## Endpoint Reference

All three endpoints used by the Fixlet Copier:

| Method | Path | Purpose | Success Codes |
|--------|------|---------|---------------|
| `GET` | `sites` | Test API connectivity — verifies the `API` object can reach the BigFix REST service | 200 |
| `GET` | `fixlet/{siteType}/{siteName}/{id}` | Fetch the full BES XML of a source fixlet for display and editing | 200 |
| `POST` | `fixlets/custom/{siteName}` | Create a new fixlet in the specified custom site; response body contains the created fixlet's ID | 200, 201 |

---

## Path Construction

All variable path segments must be URL-encoded with `encodeURIComponent()`. Site names and
fixlet titles in BigFix frequently contain spaces, slashes, and other characters that are
not safe in URL paths.

**GET — fetch a specific fixlet** (copier.ojo lines 426–427):
```javascript
var path = "fixlet/" +
           encodeURIComponent(currentItem.siteType) + "/" +
           encodeURIComponent(currentItem.siteName) + "/" +
           encodeURIComponent(currentItem.id);
API.Get(path, function(e, s, b){ ... });
```

`siteType` is one of: `custom`, `operator`, `external`, `master`.

**POST — create a fixlet** (copier.ojo line 790):
```javascript
var path = "fixlets/custom/" + encodeURIComponent(site);
API.Post(path, xml, function(e, s, b){ ... });
```

Only `custom` sites are supported as POST targets via this endpoint. The BigFix REST API
does not permit creating fixlets directly in operator, external, or master sites through
this path.

---

## Response Handling

### GET Response

A successful `GET fixlet/{siteType}/{siteName}/{id}` returns HTTP 200 with the raw BES XML
of the fixlet as the response body. The copier stores this in `sourceXml` and passes it to
`parseSourceFields()` and `parseActions()` for field extraction (copier.ojo lines 428–440):

```javascript
API.Get(path, function(e, s, b){
  if(s == 200){
    sourceXml = b;
    parseSourceFields(b);
    parseActions(b);
    setStatus("Loaded source XML from " + path);
  } else {
    alert("Load failed: " + e + " status=" + s + " path=" + path);
    setStatus("Load failed: " + e + " status=" + s);
  }
});
```

### POST Response

A successful `POST fixlets/custom/{siteName}` returns HTTP 200 or 201 with a BES XML body
containing details of the created resource. The copier extracts the new fixlet's ID from
this response body via `parseCreatedId()` (copier.ojo lines 792–807):

```javascript
API.Post(path, xml, function(e, s, b){
  if(s == 200 || s == 201){
    var bodyText = (typeof b !== "undefined" && b !== null) ? String(b) : "";
    var newId = parseCreatedId(bodyText);
    lastCreatedId = newId;
    lastCreatedSite = site;
    updateCreatedInfo(newId, site, bodyText);
    setStatus("Created via " + path + (newId !== "" ? (" ID=" + newId) : ""));
    refreshAfterCreate();
    alert("Created successfully" + (newId !== "" ? ("\nFixlet ID: " + newId) : ""));
  } else {
    alert("Failed: status=" + s + " error=" + e + " path=" + path + " response=" + b);
    setStatus("Failed via " + path + " status=" + s);
  }
});
```

---

## Response ID Parsing (parseCreatedId)

BigFix may return the created fixlet's ID in several different formats depending on the
server version and response structure. `parseCreatedId(body)` implements four fallback
strategies in order of reliability (copier.ojo lines 365–405):

### Strategy 1 — ActiveXObject XML Parse (IE/ActiveX only)

The response body is parsed as XML using `Msxml2.DOMDocument.6.0`. The function looks for
the created resource's ID in two places:

1. The `ID` attribute of the `<Fixlet>` element: `nodes[0].getAttribute("ID")`
2. The `Resource` attribute URL, from which the ID is extracted with `/\/([^\/]+)$/`

The same logic is applied to `<Task>` elements as a fallback within this strategy.

This approach is IE-only and is wrapped in `try/catch` — if `ActiveXObject` throws (e.g.,
outside BigFix Console), execution falls through to the regex strategies.

### Strategy 2 — Fixlet URL Path Regex

Matches a fixlet path embedded anywhere in the response body string:

```javascript
m = /fixlet\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
if(m && m[1]){ return m[1]; }
```

Captures the numeric ID from paths like `fixlet/custom/Dereso%20Software%20Portal/12345`.

### Strategy 3 — Task URL Path Regex

Matches a task path in the response body (BigFix may return task-style paths for some
fixlet types):

```javascript
m = /task\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
if(m && m[1]){ return m[1]; }
```

### Strategy 4 — Bare ID Attribute Regex

Matches a bare `ID=NNN` attribute anywhere in the response body:

```javascript
m = /\bID=["']?(\d+)["']?/i.exec(body);
if(m && m[1]){ return m[1]; }
```

Handles formats like `ID=12345`, `ID="12345"`, or `ID='12345'`.

### Fallback — Return Empty String

If all four strategies fail to extract an ID, `parseCreatedId` returns `""`. Callers must
handle this case — the copier still records the clone as successful (HTTP 200/201 was
received) but the "Open Created Fixlet" button will be disabled and no ID will be shown.

---

## Error Codes

| Status Code | Context | Meaning | Action |
|-------------|---------|---------|--------|
| 200 | GET / POST | Success | Proceed normally |
| 201 | POST | Created | Proceed normally (most BigFix versions return 201 for new fixlets) |
| 400 | POST | Malformed request XML | Inspect the XML being submitted; check for encoding issues |
| 401 | GET / POST | Unauthenticated or credentials expired | Re-open BigFix Console and re-authenticate |
| 403 | POST | Insufficient permissions for the target site | Verify console account has authoring rights on the target custom site |
| 404 | GET | Fixlet not found at the specified path | Verify fixlet ID, site name, and site type are correct; fixlet may have been deleted |
| 500 | GET / POST | BigFix server error | Check BigFix server logs; retry after a delay |

---

## Testing Outside BigFix Console

The `API.Get` and `API.Post` methods are provided exclusively by the BigFix Console host
environment and are not available in standalone Node.js or browser environments.

For integration testing outside the console, the equivalent HTTP calls can be made using the
`https` module with Basic authentication:

```javascript
// Node.js equivalent of API.Get("sites", callback)
const https = require("https");
const auth = Buffer.from(
  process.env.BIGFIX_USER + ":" + process.env.BIGFIX_TOKEN
).toString("base64");

https.get(
  process.env.BIGFIX_URL + "/api/sites",
  {
    headers: { "Authorization": "Basic " + auth },
    rejectUnauthorized: false  // self-signed certs are common in BigFix deployments
  },
  (res) => {
    let body = "";
    res.on("data", (chunk) => { body += chunk; });
    res.on("end", () => {
      callback("", res.statusCode, body);
    });
  }
).on("error", (err) => {
  callback(err.message, 0, "");
});
```

Required environment variables for integration tests:

| Variable | Description |
|----------|-------------|
| `BIGFIX_URL` | Base URL of the test BigFix instance (e.g., `https://bigfix.example.com:52311`) |
| `BIGFIX_USER` | BigFix admin username |
| `BIGFIX_TOKEN` | BigFix admin password or API token |

The integration test suite at `tests/integration/copier.integration.test.js` uses this
pattern to replicate the copier's `API.Get` and `API.Post` calls in a test environment.
Do not include real credential values in test files — always read from environment variables.

---

## Reference

- **Copier source:** `Existing Dashboards/fixlet_copier.ojo`
- **API call sites:** Lines 147–151 (testREST), 428–440 (selectFixlet), 790–808 (createFixlet)
- **parseCreatedId:** Lines 365–405
- **Path construction:** Lines 426–427, 790
- **Admin guide:** `docs/admin-guide.md`
- **Architecture:** `docs/architecture.md`
