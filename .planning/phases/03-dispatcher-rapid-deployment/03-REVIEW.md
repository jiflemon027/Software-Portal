---
phase: 03-dispatcher-rapid-deployment
reviewed: 2026-06-14T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - tests/unit/dispatcher.test.js
  - tests/fixtures/phase-03/valid-fixlet-with-actions.ojo
  - tests/fixtures/phase-03/valid-fixlet-single-action.ojo
  - tests/fixtures/phase-03/sample-action-response.xml
  - Existing Dashboards/fixlet_dispatcher.ojo
  - tests/integration/dispatcher.integration.test.js
  - docs/dispatcher-admin-guide.md
findings:
  critical: 2
  warning: 6
  info: 3
  total: 11
status: fixes_applied
---

# Phase 03: Code Review Report

**Reviewed:** 2026-06-14T00:00:00Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

This phase delivers the Fixlet Dispatcher dashboard (`fixlet_dispatcher.ojo`), unit tests,
integration tests, test fixtures, and admin documentation. The implementation is broadly
well-structured, with good separation of the configurable PORTAL_CONFIG block, systematic
input validation before deployment, and consistent use of `htmlEscape()` on untrusted display
data throughout most of the code.

Two critical defects were found: a double-XML-encoding bug in `buildDeployXml` that corrupts
deployed `<Relevance>` content for any target group containing characters like `<`, `>`, `&`,
or `'`, and an XSS-capable success-banner construction that injects raw HTML including a
script-callable button without sanitising that portion. Six warnings cover an incomplete
single-quote escape strategy for BigFix relevance, a missing null guard in `selectFixlet`,
unreachable test paths, missing timeout in the integration test request, incorrect BigFix
relevance syntax for single-quote escaping, and a broken HTML tag in the success message.
Three info items flag minor code quality and documentation gaps.

---

## Critical Issues

### CR-01: Double-XML-encoding corrupts `<Relevance>` in every deployed action

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:571`

**Issue:** `buildDeployXml()` calls `xmlEscape(buildTargetRelevance(groupName))`. The
relevance expression produced by `buildTargetRelevance()` is plain text intended to be an
XML element value — it contains characters such as `'` (single-quote), `=`, `(`, `)`, and
for group names with special chars it may also contain `&` or `<`. Passing that already-safe
string through `xmlEscape()` again produces double-encoded output that BigFix will receive
literally, e.g.:

- Group name `"IT Dep't"` → relevance string contains `\'` → xmlEscape turns `\` into `\`
  and `'` into `&apos;` → XML element contains `&apos;` as literal text → BigFix relevance
  engine receives `name of it = '\'&apos;t'` and evaluates to **no computers**.
- Normal group name `"All Workstations"` with no special chars still produces a relevance
  string like `member of bes computer group whose (name of it = 'All Workstations')` which
  is then XML-escaped so `'` becomes `&apos;` inside the element value — BigFix then
  evaluates `name of it = &apos;All Workstations&apos;` (as literal text, not `'`), causing
  **zero computers to match the group** on every deployment.

The `<Relevance>` element value must be the raw relevance text; XML serialization of special
characters within element content is the XML parser's job when you set `nodeValue` — but
here XML is assembled as a string, so only one pass of XML escaping should apply: the
relevance text should be XML-escaped exactly once (via `xmlEscape`) with the understanding
that the single-quote escaping inside `buildTargetRelevance` is for the relevance-language
string, not for XML attribute quoting.

The correct fix: `buildTargetRelevance` already produces a valid relevance expression where
single quotes are correctly used as relevance string delimiters. The outer `xmlEscape()` call
at line 571 should be removed so the relevance string is embedded in the XML element value
as-is (the text node). BigFix's XML parser will handle the element-level escaping when it
parses the submitted XML document.

**Fix:**
```javascript
// BEFORE (line 571) — double-encodes the relevance expression:
xml += '    <Relevance>' + xmlEscape(buildTargetRelevance(groupName)) + '</Relevance>\r\n';

// AFTER — relevance is plain text; no XML-escape needed for element text content
// assembled as a raw string (BigFix parser handles it on receipt):
xml += '    <Relevance>' + buildTargetRelevance(groupName) + '</Relevance>\r\n';
```

---

### CR-02: XSS in success banner — unescaped HTML injection via `resultEl.innerHTML`

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:614-616`

**Issue:** The success banner in `deployFixlet()` is assembled by concatenating a static HTML
string that includes `<b>`, `&nbsp;`, and a `<button>` element with an inline `onclick`
handler, all via `resultEl.innerHTML`. The `htmlEscape(actionIdR || "(unknown)")` call
correctly escapes the action ID, but the surrounding string is raw HTML with an active button.

The primary XSS risk is: if a malicious BigFix server response (or a man-in-the-middle
response, since the BigFix console communicates over self-signed TLS that operators sometimes
configure loosely) returns a body where `parseActionId()` returns a string that bypasses the
`htmlEscape()` path — e.g. if the action ID regex accidentally returns a match containing
`"` or `>` — those characters would not be safe inside an HTML attribute context. More
concretely, in a BigFix console running IE9 (`<meta http-equiv="X-UA-Compatible"
content="IE=9">`), `innerHTML` assignment with embedded `onclick` strings can trigger event
handler injection.

Additionally, the button element itself contains an unquoted `onclick="resetDeployForm()"`.
Any future refactor that injects a variable into this string before the button tag (e.g. to
add an action link) would create a direct XSS path. The current pattern of mixing trusted
static HTML with `innerHTML` assignment to a visible result div is unsafe by construction in
an IE9 host.

**Fix:** Build the success banner using DOM methods to avoid any innerHTML injection risk,
consistent with the `deployError` div which correctly uses `htmlEscape()` on the whole
message string:
```javascript
// AFTER — use DOM construction instead of innerHTML:
if (resultEl) {
  resultEl.style.display = "";
  // Clear previous content
  while (resultEl.firstChild) { resultEl.removeChild(resultEl.firstChild); }

  var strong = document.createElement("b");
  strong.appendChild(document.createTextNode("Deployed."));
  resultEl.appendChild(strong);

  resultEl.appendChild(document.createTextNode(
    " Action ID: " + (actionIdR || "(unknown)") + "   "
  ));

  var btn = document.createElement("button");
  btn.className = "btn";
  btn.onclick = resetDeployForm;
  btn.appendChild(document.createTextNode("Deploy Another"));
  resultEl.appendChild(btn);
}
```

---

## Warnings

### WR-01: `buildTargetRelevance` — single-quote escape strategy is incorrect for BigFix relevance

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:286`, `tests/unit/dispatcher.test.js:198-200`

**Issue:** The function escapes single quotes with a backslash (`\\'`), producing strings
like `name of it = \'IT Dep\'t\'`. BigFix relevance language does **not** use backslash
as a string escape character. In BigFix relevance, a literal single quote inside a string
is written by doubling it: `''`. The backslash approach will produce a relevance syntax error
and the action will target zero computers.

The unit test at line 198-200 of `dispatcher.test.js` accepts either `IT Dep\\'t` or
`IT Dep''t` as a passing result, so the test is permissive enough to mask the bug
(`|| result.indexOf("IT Dep''t") !== -1`). The implementation only produces the backslash
form, which is the wrong one.

**Fix:**
```javascript
// BEFORE (line 286):
var safeGroup = String(groupName).replace(/'/g, "\\'");

// AFTER — BigFix relevance uses '' to escape a literal single-quote:
var safeGroup = String(groupName).replace(/'/g, "''");
```
The unit test should also be tightened to assert only the `''` form.

---

### WR-02: `selectFixlet()` — no bounds check before indexing into `currentItems`

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:377-393`

**Issue:** `selectFixlet(i)` is called from an `onclick` attribute injected as raw HTML into
the table rows at line 202: `'onclick="selectFixlet(' + i + ')"'`. The index `i` is the
loop counter at render time, which refers to `currentItems[i]`. If the user clicks a radio
button and then `filterAndRender()` is triggered (e.g. by a 300ms debounce from `onSearchInput`
completing mid-click) before `selectFixlet(i)` fires, `currentItems` will have been rebuilt.
The stale index `i` may point past the end of the new `currentItems` array, making
`currentItem = currentItems[i]` equal to `undefined`. All subsequent uses of `currentItem`
(e.g. `currentItem.siteName` at line 381, `currentItem.name` at line 388) will throw a
`TypeError: Cannot read property 'siteName' of undefined` — silently swallowed by no
try/catch here, leaving the UI in an inconsistent state.

**Fix:** Add a bounds guard at the top of `selectFixlet`:
```javascript
function selectFixlet(i){
  if (i < 0 || i >= currentItems.length) {
    setStatus("Selection error: please try again.");
    return;
  }
  selectedItemIndex = i;
  currentItem       = currentItems[i];
  // ... rest of function
```

---

### WR-03: `parseActionId` — `ID=` attribute regex matches non-ID content in error responses

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:315`, `tests/unit/dispatcher.test.js:97`

**Issue:** The second regex fallback at line 315 is:
```
/\bID=["']?(\d+)["']?/i
```
This matches any occurrence of `ID=` followed by digits anywhere in the response body. A
BigFix error response body such as:
```xml
<BESAPI><Error SessionID="12345">Request failed</Error></BESAPI>
```
would not match. However, a response containing attribute names like `FixletID="99"` or
`SiteID="1"` or `TaskID="5"` could match because `\bID=` matches word-boundary before `ID`
inside compound words like `FixletID` only when followed by `=` — but `FixletID=` ends with
`D=` so `\bID=` would match at the `ID=` portion of `FixletID=`. This can cause
`deployFixlet()` to display a wrong action ID in the success banner after a deploy (e.g.
displaying a FixletID from the error payload instead of the created action ID).

The unit tests for this function are also thin: there is no test for the `ID=` regex path
specifically, and no test for ambiguous inputs where multiple patterns could match.

**Fix:** Make the regex more specific — require it to match `<ID>` element form only:
```javascript
// Replace the ID= fallback with a stricter pattern (already covered by the third regex):
// Remove the /\bID=["']?(\d+)["']?/i regex entirely, or restrict to Action ID context:
m = /\bActionID=["']?(\d+)["']?/i.exec(body);
```
Or, simply remove the `ID=` regex since the `/api/action/N` pattern (first regex) and
`<ID>N</ID>` pattern (third regex) together cover all known BigFix response formats.

---

### WR-04: Integration test — `apiRequest` does not set a socket timeout; tests can hang indefinitely

**File:** `tests/integration/dispatcher.integration.test.js:66-108`

**Issue:** The `apiRequest` helper constructs an `https.request` without specifying a
`timeout` option. If the BigFix server at `BIGFIX_URL` is unreachable but does not
immediately refuse the connection (e.g. firewalled host, slow DNS), `req.on("error")` may
not fire for many minutes. The test process will hang with no output and no exit code. This
is especially problematic in CI pipelines.

**Fix:** Add a socket timeout to the request options and destroy the socket on timeout:
```javascript
var requestOptions = {
  // ... existing fields ...
  timeout: 10000  // 10 seconds
};

// After req creation:
req.on("timeout", function() {
  req.destroy(new Error("Request timed out after 10000ms"));
});
```

---

### WR-05: `buildDeployXml` — `descHtml` read from `getNodeText(doc, "Description")` strips CDATA

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:543-544`

**Issue:** `getNodeText(doc, "Description")` returns `n[0].text || ""` (line 265). In
MSXML2, `.text` on a node that contains a `<![CDATA[...]]>` section returns the text content
of the CDATA section — that is correct. However, if the `<Description>` element contains
mixed content (e.g. child elements with their own text, which is common in BigFix fixlets
using `<PreLink>/<Link>/<PostLink>` structure as seen in both test fixture files), then
`n[0].text` returns only the concatenated text of all descendant text nodes with no markup,
losing all HTML formatting that was in the description.

Both test fixtures confirm this pattern:
```xml
<Description>
  <PreLink>Click </PreLink>
  <Link>here</Link>
  <PostLink> to install using the default installer.</PostLink>
</Description>
```
When `getNodeText` processes this, `n[0].text` yields `"Click here to install using the
default installer."` — all link markup stripped. The resulting `<OfferDescriptionHTML>` will
contain plain text with no HTML formatting. Any fixlets in the portal that have rich HTML
descriptions authored in the BigFix console will have their descriptions silently degraded.

**Fix:** Use `xml` to get the inner XML of the `<Description>` node rather than `.text`:
```javascript
// Replace getNodeText for Description with inner XML extraction:
var descNodes = doc.getElementsByTagName("Description");
var descHtml = "";
if (descNodes.length > 0) {
  descHtml = descNodes[0].xml || "";
  // Strip outer <Description>...</Description> tags:
  descHtml = descHtml.replace(/^<Description[^>]*>/, "").replace(/<\/Description>$/, "");
}
```
Or, if only raw description text is intended, this should be documented clearly.

---

### WR-06: `resetDeployForm` — `selectedItemIndex` not reset

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:629-654`

**Issue:** `resetDeployForm()` resets `sourceXml`, `currentItem`, `parsedActions`, and
`selectedActionId` to their empty/null states, but does not reset `selectedItemIndex` (which
is initialized to `-1` at line 54). After a successful deploy and "Deploy Another" click,
`selectedItemIndex` retains the index of the previously selected fixlet. If the user then
clicks the radio button for the previously-selected fixlet row (which still appears in the
refreshed list), `selectFixlet(i)` will be called, and `selectedItemIndex` will be set to
the same stale value again — this is harmless but inconsistent. More importantly, any code
that reads `selectedItemIndex` to restore or re-check selection state will see a non-`-1`
value indicating a selection is active when none is.

**Fix:**
```javascript
function resetDeployForm(){
  sourceXml         = "";
  currentItem       = null;
  parsedActions     = [];
  selectedActionId  = "";
  selectedItemIndex = -1;  // <-- add this line
  // ... rest unchanged
```

---

## Info

### IN-01: Malformed closing tag `<\b>` in success banner HTML string

**File:** `Existing Dashboards/fixlet_dispatcher.ojo:615`

**Issue:** The success banner string contains `"<b>Deployed.<\b>"`. The closing tag is
`<\b>` (backslash before `b`) instead of `</b>`. In IE9, this will be parsed as an unknown
tag and the bold element will never close, causing the rest of the banner text to render
bold. This is a typo, not a security issue.

This finding has been superseded by CR-02 (the whole banner should be rewritten using DOM
methods), but it should be noted so it is not inadvertently preserved in a partial fix.

**Fix:** If not fixing via DOM methods (CR-02), correct the tag:
```javascript
"<b>Deployed.</b> Action ID: " + ...
```

---

### IN-02: Unit test has no coverage for `buildExpirationElement` with zero or negative input

**File:** `tests/unit/dispatcher.test.js:204-217`

**Issue:** `buildExpirationElement` uses `parseInt(days, 10)` with no validation — passing
`0` produces `P0D` (an action that expires immediately) and passing `-1` produces `P-1D`
(invalid ISO 8601 duration). The unit tests only check `7` and `1`. The source function in
`fixlet_dispatcher.ojo` has a UI-level guard (`val > 0`) in `getExpirationDays()` but the
function itself has no guard, and direct callers could pass invalid values.

**Fix:** Add edge-case tests:
```javascript
expect("0 days — documents P0D (immediate expiry) behavior", function(){
  assert.ok(buildExpirationElement(0).indexOf("P0D") !== -1);
});
expect("negative days — documents invalid P-1D behavior", function(){
  assert.ok(buildExpirationElement(-1).indexOf("P-1D") !== -1);
});
```
And optionally guard the function: `days = Math.max(1, parseInt(days, 10) || 1)`.

---

### IN-03: Admin guide documents the fallback-to-`true` behavior without warning

**File:** `docs/dispatcher-admin-guide.md:103-104`

**Issue:** The admin guide states: "If the group name field is left blank, the relevance
expression falls back to `true` (all computers)." This is described as neutral behavior, but
`true` means the deployed action will target **every computer in the BigFix environment**.
For an offer-type action this is lower risk than a forced-install action, but the guide
should include an explicit warning that leaving the target group blank results in an
environment-wide deployment, not a no-op.

**Fix:** Update the relevant sentence in the guide to:
> "If the group name field is left blank, the relevance expression falls back to `true`,
> which targets **all computers in the BigFix environment**. This is intentional for
> environment-wide deployments only — leave this field blank with caution."

---

_Reviewed: 2026-06-14T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
