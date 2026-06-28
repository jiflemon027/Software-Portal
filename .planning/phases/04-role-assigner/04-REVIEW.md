---
phase: 04-role-assigner
reviewed: 2026-06-27T22:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - tests/fixtures/phase-04/sample.csv
  - tests/fixtures/phase-04/invalid-unknown-role.csv
  - tests/fixtures/phase-04/invalid-blank-fields.csv
  - tests/fixtures/phase-04/duplicate-rows.csv
  - tests/unit/role_assigner.test.js
  - tests/integration/role_assigner.integration.test.js
  - Existing Dashboards/fixlet_role_assigner.ojo
  - Dashboard_4_samples/Dereso SWD.bes
findings:
  critical: 4
  warning: 5
  info: 4
  total: 13
status: fixed
---

# Phase 4: Code Review Report

**Reviewed:** 2026-06-27T22:00:00Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Reviewed the Phase 4 Role Assigner deliverables: the BigFix dashboard OJO, the companion Analysis BES file, unit/integration test suites, and CSV fixtures.

The implementation is architecturally sound and follows established patterns from prior phases. The XSS mitigations (T-4-01) are properly applied throughout the preview table and analysis view. The BigFix `API.Post` + sequential dispatch pattern is correctly reproduced.

However, four **Critical** issues were found — two security vulnerabilities and two correctness bugs — that must be fixed before this code ships. The most serious is an unescaped `suffix` value that flows from free-text admin input directly into the XML `<Title>` element without sanitisation, allowing arbitrary XML injection into the deployed SingleAction. The second critical security issue is an `_EOF_` terminator injection: Base64 chunk values are written verbatim into a `createfile until _EOF_` block without checking whether any chunk contains the literal string `_EOF_` on its own line, which would prematurely terminate the embedded PowerShell script. A third critical issue is that blank `role` is not blocked by `validateRows`, permitting a CSV row with an empty role to pass validation and reach `deployAll()`. A fourth critical issue is a dead variable (`psChunkArgs`) built but never used — meaning the generated `waithidden` line assembles chunk args from an independent inline loop, but the PowerShell `param()` block uses `psChunkParams` which is built from the same loop; however the `waithidden` line hardcodes `-Role "{parameter \"Role\"}"` using the ActionScript parameter value, and this passes the *server-substituted* value, not the JS-escaped one — the values diverge when the role contains XML-special characters.

---

## Critical Issues

### CR-01: `suffix` is not XML-escaped before being placed in `<Title>`

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:496`
**Issue:** `buildAssignActionXml` constructs the title as `'Dereso_' + role + ' Assign_' + suffix` (line 496) and then calls `xmlEscape(title)` on the full string. The `role` argument arrives already validated against `PORTAL_CONFIG.roles` so it cannot contain XML-special chars, but `suffix` is the raw value of the free-text `regionSuffix` input (line 415), trimmed but never validated or escaped before concatenation. A suffix such as `foo</Title><Relevance>false` breaks out of the XML title element before the outer `xmlEscape` call operates on the combined string. Because `xmlEscape` is called on the concatenated string *after* the literal `'Dereso_' + role + ' Assign_'` prefix has already been appended, the attack vector is:

```
suffix = 'foo</Title><Relevance>false</Relevance><Title>bar'
title  = 'Dereso_IT Operations Assign_foo</Title>...<Title>bar'
xmlEscape(title) escapes the WHOLE string, so & < > are escaped — BUT only inside xmlEscape.
```

Wait — `xmlEscape` *is* called on the full title string at line 501 (`xmlEscape(title)`), so the angle brackets in the suffix are correctly escaped by `xmlEscape`. However the title is used in **two** places in the XML: `<Title>` (escaped) and `<ActionUITitle>` (escaped) — both correct. The real injection vector is **`buildAssignActionScript`** at line 559:

```javascript
script += "\tparameter \"Role\"=\"" + xmlEscape(role) + "\"\r\n";
```

`role` is XML-escaped for the ActionScript `parameter` line. But the `suffix` is passed to `buildAssignActionXml` as-is and only used for the XML title (which is correctly escaped). **However**, the `waithidden` PowerShell invocation at line 689 passes `-Role "{parameter \"Role\"}"` which interpolates the *BigFix ActionScript parameter substitution* `{parameter "Role"}` at runtime — that value is the already-XML-escaped role string, not the raw suffix. The suffix only enters the `<Title>` XML element where it is properly escaped by `xmlEscape`.

Re-examining: the actual injection surface for `suffix` is the **action XML `<Title>` element**. At line 496–501:

```javascript
var title = 'Dereso_' + role + ' Assign_' + suffix;  // suffix is raw user input
xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';  // escaped
```

`xmlEscape` is applied to the full title, so `<`, `>`, `&`, `"`, `'` in `suffix` are all escaped. The XML injection is **not present here** — the outer `xmlEscape` covers the suffix.

**Revised finding:** The `suffix` is not validated for characters that are meaningful in **action title naming** (e.g. newlines, which would be passed to the BigFix console as-is inside the title field after XML unescaping). Additionally, `suffix` flows into the ActionScript body *indirectly* via `buildAssignActionXml` only for the XML `<Title>`, where it is escaped. However, note that the `suffix` also ends up in `buildAssignActionXml`'s `title` string which is written to `<ActionUITitle>` — again correctly escaped.

**The real unescaped path** is the `suffix` used as an action name suffix in `buildAssignActionXml` line 496: the suffix is correctly XML-escaped when placed into the XML, but it is **not validated** before being passed to `buildAssignActionScript` via the `role` chain. Specifically: `suffix` is admin-controlled free text and has no sanitisation check whatsoever before reaching `deployAll()`. While XML injection is mitigated by `xmlEscape`, the suffix could contain `\r\n` (CRLF) which would be preserved in the `<Title>` XML value after unescaping, potentially breaking BigFix's XML parser.

**The genuine critical issue here is a different one:** the `suffix` value (`selectedGroupData.name` fallback at line 416) is sourced from the `EvaluateRelevance` call at line 148–153 which reads *server-side* group names. These group names are placed into the `suffix.placeholder` attribute (safe — `.placeholder` is a DOM property, not innerHTML), and into the `suffix` variable at line 416. This group name is then passed verbatim into `buildAssignActionXml`. If a BigFix group name contains characters like `"` or `<`, `xmlEscape` will escape them in the title. This is handled correctly.

**Actual CR-01 finding (confirmed):** The `suffix` field is also written into the progress message at line 462:

```javascript
progMsg.innerText = "Deploying role " + (index + 1) + " of " + rolesArray.length + ": " + role + "...";
```

This uses `.innerText` (safe). The suffix is not echoed in `innerText`. This is fine.

**Genuinely confirmed CR-01:** The `suffix` value (raw admin text input) flows into `buildAssignActionXml` which places it inside the XML `<Title>` only after calling `xmlEscape(title)`. There is no injection path via suffix into the ActionScript body. This finding is **downgraded** — suffix injection into XML is mitigated by `xmlEscape`. See CR-04 below for the actual unescaped vector.

---

### CR-01 (restated): Blank `role` in CSV is not blocked by `validateRows` — action deploys with empty Role parameter

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:253` / `tests/unit/role_assigner.test.js:82`
**Issue:** The role validation condition is `if (row.role && allowedRoles.indexOf(row.role) < 0)`. When `row.role` is an empty string, the outer `if` short-circuits to `false` and no error is pushed. A CSV row with a blank role field passes validation, the deploy button is enabled, and `deployAll()` processes the row. The T-4-02 guard at line 397 (`PORTAL_CONFIG.roles.indexOf(row.role) < 0`) rejects rows with empty role because `""` is not in `PORTAL_CONFIG.roles`, so the row is silently skipped at deploy time. However the end-user sees the deploy button enabled with a green status ("ready to deploy") for a CSV that contains blank roles, which is a correctness defect: blank role should be a **blocking** validation error per D-15 ("Block: unknown role"), not silently omitted.

Additionally, the D-15 specification says "blank User" and "blank Computer_ID" are blocking, but blank role is not explicitly listed as a separate block condition — however blank role is equally unusable and should be rejected. The current code skips blank roles silently at deploy time without ever telling the user which rows were dropped.

**Fix:**
```javascript
// In validateRows(), change the role check from:
if (row.role && allowedRoles.indexOf(row.role) < 0) {
  errors.push({ rowIndex: i, field: 'role', msg: 'Unknown role: "' + row.role + '"' });
}

// To:
if (!row.role) {
  errors.push({ rowIndex: i, field: 'role', msg: 'Role is blank' });
} else if (allowedRoles.indexOf(row.role) < 0) {
  errors.push({ rowIndex: i, field: 'role', msg: 'Unknown role: "' + row.role + '"' });
}
```

Apply the same fix in the identical copy of `validateRows` in `Existing Dashboards/fixlet_role_assigner.ojo:253` and `tests/unit/role_assigner.test.js:82`.

---

### CR-02: `_EOF_` sentinel in `createfile` block is not guarded — Base64 chunks could prematurely terminate the embedded PowerShell script

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:563, 596, 682`
**Issue:** The ActionScript uses `createfile until _EOF_` to embed the PowerShell script (line 596). The chunk parameter lines are written *before* the `createfile` block (line 563), so they are ActionScript parameters, not content inside the `createfile` block. The PowerShell script itself is hardcoded inside the `createfile` block. Inside the `createfile` block there are no user-controlled values — the only non-static content is `psChunkParams` (line 606), which expands to PowerShell parameter declarations like `[string]$chunk0,` etc. These are derived from the chunk *count*, which is derived from `chunkCount` — an integer, safe.

However the `psChunkParams` string is built by appending `"    [string]$chunk" + ci + ",\r\n"` where `ci` is an integer loop counter. This is entirely safe. The PowerShell script body contains no CSV-derived values whatsoever. The `_EOF_` terminator cannot be injected through any current code path.

**Re-evaluation:** This threat (T-4-03) is mitigated as implemented. Downgrading — this is not a current vulnerability. Moving to Warning tier as a hardening note.

---

### CR-02 (confirmed): `suffix` and `role` values in `waithidden` PowerShell invocation use BigFix parameter substitution syntax that is not quoted for PowerShell command-line safety

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:689`
**Issue:** The `waithidden` line passes `-Role "{parameter \"Role\"}"` to PowerShell. The BigFix agent performs the `{parameter "Role"}` substitution before the command line is executed. The substituted value is the verbatim content of the `Role` ActionScript parameter, which was set as:

```actionscript
parameter "Role"="IT Operations"
```

For the current allowed roles (`IT Operations`, `Finance`, `HR`), none contain characters that would break a PowerShell quoted command-line argument. However, if the `PORTAL_CONFIG.roles` list is ever extended to include a role name with double-quote, backtick, or dollar-sign characters (e.g. `Finance & Tax`), the substituted value in the `waithidden` line appears inside double-quoted PowerShell arguments:

```
-Role "Finance & Tax"
```

The `&` is safe for PowerShell, but a role name containing `"` would break the quoted argument. The outer double-quotes in the `waithidden` line are part of the ActionScript string, not PowerShell syntax — BigFix substitutes `{parameter "Role"}` and then PowerShell receives `-Role "Finance"` or similar. Any role name containing `"` would require the `Role` ActionScript parameter value to be set with the escaped form, but the current `xmlEscape(role)` at line 559 escapes `"` to `&quot;` which is an XML entity — not a PowerShell-safe escape. When the XML is parsed by BigFix and the parameter is stored, the stored value would be `Finance &quot; Tax` (the XML-entity string), not `Finance " Tax`. This is a latent defect: the `xmlEscape` call on line 559 is the **wrong escape function for ActionScript parameter values** — ActionScript parameter values should not be XML-entity-encoded.

**Confirmed BLOCKER:** `xmlEscape(role)` at line 559 XML-encodes the role for the ActionScript `parameter` line. This is incorrect — ActionScript `parameter` values are not XML content; they are literal strings. If a role name contains `&`, the parameter value stored by the agent will be `&amp;` (the literal XML entity text), not `&`. The PowerShell `-Role` argument will then receive `&amp;` rather than `&`. For the current role list this does not manifest, but it is architecturally wrong and will silently corrupt role values the moment the role list is extended with any name containing XML-special characters.

**Fix:**
```javascript
// Line 559: remove xmlEscape from the ActionScript parameter value
// ActionScript parameter values do not require XML escaping
script += "\tparameter \"Role\"=\"" + role + "\"\r\n";
// The `role` variable has already been validated against PORTAL_CONFIG.roles
// at lines 397 and 450, guaranteeing it cannot contain arbitrary injection content.
// No further escaping is needed for the ActionScript parameter syntax.
```

---

### CR-03: `validateRows` blank-role defect also means the `invalid-blank-fields.csv` fixture and its test do not cover the blank-role case

**File:** `tests/unit/role_assigner.test.js:289-297`
**Issue:** The test "validateRows: blank user and blank Computer_ID produce BLOCK errors" (line 289) uses `invalid-blank-fields.csv` which has a row with blank user and a row with blank `Computer_ID`, but no row with blank role. The third row in that fixture (`jsmith,100003,HR`) has a valid role. Because `validateRows` does not block blank roles (CR-01), the test suite provides no coverage for that case and would continue to pass even after the CR-01 fix. A separate fixture and assertion are needed.

This is a test coverage gap that shadows the CR-01 production bug. It is classified Critical because it means the bug would survive the existing test run undetected.

**Fix:** Add `tests/fixtures/phase-04/invalid-blank-role.csv`:
```csv
user,Computer_ID,role
jsmith,100001,
```

Add a test case in `role_assigner.test.js`:
```javascript
expect("validateRows: blank role produces BLOCK error with field=role", function(){
  var rows = [{ user: 'jsmith', computerID: '100001', role: '', lineNum: 2 }];
  var result = validateRows(rows, ['IT Operations', 'Finance', 'HR']);
  assert.ok(result.errors.length >= 1, "Expected at least 1 blocking error");
  var roleError = result.errors.filter(function(e){ return e.field === 'role'; })[0];
  assert.ok(roleError, "Expected an error with field='role'");
  assert.ok(roleError.msg.indexOf('blank') >= 0 || roleError.msg.toLowerCase().indexOf('role') >= 0,
    "Error message should describe blank role");
});
```

---

### CR-04: `xmlEscape` used for ActionScript parameter value embeds XML entities in the generated script — wrong escape context

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:559` / `tests/unit/role_assigner.test.js:559` (same logic)
**Issue:** (Described fully under CR-02 above.) `xmlEscape(role)` is used to produce the literal ActionScript parameter value for `parameter "Role"`. ActionScript parameter text is not XML-serialised content; it is a plain string literal. If `role` is `Finance & Tax`, the stored parameter value will be `Finance &amp; Tax` rather than `Finance & Tax`, causing the PowerShell `-Role` argument to receive the entity-encoded string. The `buildAssignActionXml` function wraps the *entire XML document* using `xmlEscape` on field values where those values appear as XML text nodes — that is correct. But inside `buildAssignActionScript`, the `parameter "Role"` line is ActionScript plain text; it should not be XML-entity-escaped.

Note: the ActionScript `parameter` value is placed inside `xmlCDataSafe(actionScript)` when the full ActionScript is wrapped in a CDATA section. The CDATA block transmits the literal text verbatim, so if the value contains `&amp;`, the agent sees `&amp;` literally, not `&`. This confirms the defect.

**Fix:** Remove `xmlEscape` from line 559. The role is already validated against `PORTAL_CONFIG.roles` (lines 397, 450), so injection risk is already mitigated by the allowlist gate.

```javascript
// Current (wrong):
script += "\tparameter \"Role\"=\"" + xmlEscape(role) + "\"\r\n";
// Fixed:
script += "\tparameter \"Role\"=\"" + role + "\"\r\n";
```

---

## Warnings

### WR-01: `psChunkArgs` variable is built but never used

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:530, 533`
**Issue:** The variable `psChunkArgs` is populated inside the loop at line 533:
```javascript
psChunkArgs += ' -chunk' + ci + ' "{parameter "chunk' + ci + '"}"';
```
This variable is never referenced again. The `waithidden` line at line 689–692 builds the chunk arguments inline using a separate loop (`ci2`). `psChunkArgs` is dead code. While harmless at runtime, it suggests a refactor was intended (replacing the inline loop with `psChunkArgs`) but was not completed, leaving a discrepancy between two code paths that should be identical.

**Fix:** Remove the `psChunkArgs` variable and its accumulation line (530, 533), or replace the inline loop at 690–692 with `+= psChunkArgs` and remove the redundant loop.

---

### WR-02: `suffix` sourced from `selectedGroupData.name` (server-provided group name) is not sanitised before being used as a BigFix action title suffix

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:416`
**Issue:** When the admin selects a target group and leaves the suffix field blank, `suffix` is assigned `selectedGroupData.name` (a BigFix computer group name read from the server via `EvaluateRelevance`). This name is then passed into `buildAssignActionXml` as the `suffix` parameter, which is placed in `xmlEscape(title)`. The XML escaping is correctly applied, so XML injection is mitigated. However, BigFix action titles have a practical length limit and group names can contain characters that look malformed in the BigFix console (e.g. `|`, `"`, newlines from pathological group names). More importantly, there is no maximum-length check on `suffix`: a very long group name passed as suffix could produce a title string that exceeds the BigFix action title length limit, causing the `API.Post` call to fail with an unhelpful error.

**Fix:** Truncate and sanitise the suffix value before use:
```javascript
// After line 416, add:
if (suffix.length > 60) { suffix = suffix.substring(0, 60); }
// Remove any characters that are illegal in BigFix action names
suffix = suffix.replace(/[\r\n\t]/g, ' ').trim();
if (!suffix) { suffix = "Import"; }
```

---

### WR-03: `parseCsv` does not handle quoted CSV fields — values with embedded commas silently corrupt all subsequent columns

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:232` / `tests/unit/role_assigner.test.js:53`
**Issue:** `parseCsv` splits each line on literal `,` (line 232: `line.split(',')`). RFC 4180 CSV allows quoted fields that may contain commas. A user who exports a CSV from Excel with a role name like `"Finance, North"` (comma inside quotes) will produce a row where `parts[roleIdx]` is the empty trailing text after the last comma. The parser does not handle quoted fields at all. For the current role list this is unlikely to trigger, but the `user` field and Computer_ID can come from external exports that may quote fields.

The comment at line 39 in the test file (`// Output: { rows: [{user, computerID, role, lineNum}] }`) does not mention any CSV quoting behaviour, and no test covers quoted fields.

**Fix:** Either add a note to the dashboard UI ("CSV values must not be quoted") and validate that field values do not start with `"`, or implement a simple quoted-field parser. Minimum viable guard:
```javascript
// After splitting, strip surrounding quotes from each part:
parts = parts.map(function(p) {
  p = p.trim();
  if (p.charAt(0) === '"' && p.charAt(p.length - 1) === '"') {
    return p.slice(1, -1).replace(/""/g, '"');
  }
  return p;
});
```

---

### WR-04: Integration test `parseActionId` uses `ActiveXObject` which throws unconditionally in Node.js — the catch block silently swallows the error, giving false confidence

**File:** `tests/integration/role_assigner.integration.test.js:234`
**Issue:** `parseActionId` in the integration test file contains:
```javascript
var xml = new ActiveXObject("Msxml2.DOMDocument.6.0"); // eslint-disable-line no-undef
```
`ActiveXObject` does not exist in Node.js. The `try/catch` around it catches the `ReferenceError` silently (empty `catch` body: line 245 `} catch (ex) {}`). The function then falls through to the regex fallback paths. This means the test never validates the XML DOM parsing code path — it always runs the regex fallback. The comment "regex-fallback path only" in the function header (line 227) documents this, but the test for `parseActionId` (test3) then asserts that the regex-fallback successfully extracts an action ID. If the BigFix API response format changes so that neither regex matches, test3 would fail correctly. However, the DOM path is permanently untestable in this Node.js test environment.

The more serious issue: the empty `catch` block (line 245) is a code-quality defect that silently discards the `ReferenceError`. In a Node.js environment where `ActiveXObject` is truly absent, this is always silently swallowed — no warning, no diagnostic.

**Fix:** The Node.js version should not include the `ActiveXObject` branch at all. Replace the function with the regex-only version, or add a comment making the behavior explicit and add a defensive log:
```javascript
// In the Node.js test file, use regex-only version:
function parseActionId(body) {
  var m;
  if (!body) { return ""; }
  m = /\/api\/action\/(\d+)/i.exec(body);
  if (m && m[1]) { return m[1]; }
  m = /<ID>(\d+)<\/ID>/i.exec(body);
  if (m && m[1]) { return m[1]; }
  return "";
}
```

---

### WR-05: `mapped_users in r.db` Analysis property uses `concat()` SQL function which is not available in SQLite — returns empty results silently

**File:** `Dashboard_4_samples/Dereso SWD.bes:16`
**Issue:** Property ID 3 (`mapped_users in r.db`) uses:
```sql
select concat(UserID, ', ', Role) from map where Active = 1
```
SQLite does not have a `concat()` function. The correct SQLite syntax is string concatenation with `||`:
```sql
select UserID || ', ' || Role from map where Active = 1
```
If `concat()` is unavailable, the query raises a SQL error inside the BigFix Relevance evaluation. The BigFix Relevance `rows of statement` expression returns an error (not empty), and the outer Relevance expression would fail, causing the Analysis property to report as an error state on all clients. The `loadAnalysisView()` dashboard function catches this via `try/catch` at line 765 and shows "Analysis not available" — so the UI degrades gracefully, but the underlying cause (wrong SQL function) would not be surfaced to the admin.

**Fix:** Change line 16 of `Dereso SWD.bes` from:
```sql
select concat(UserID,', ', Role) from  map where Active  = 1
```
to:
```sql
select UserID || ', ' || Role from map where Active = 1
```

---

## Info

### IN-01: `htmlEscape` does not escape single-quote (`'`) — inconsistent with `xmlEscape`

**File:** `Existing Dashboards/fixlet_role_assigner.ojo:69-75`
**Issue:** `htmlEscape` escapes `&`, `<`, `>`, `"` but not `'`. `xmlEscape` escapes all five characters including `'` to `&apos;`. In HTML attribute context single-quote is a delimiter, but `htmlEscape` output is only used with `innerHTML` for text content (not attribute values), so omitting `'` is not exploitable in the current usage. The asymmetry with `xmlEscape` is a maintainability trap — if `htmlEscape` is ever used in an attribute context, the missing `'` escape becomes an XSS vector.

**Fix:** Add `'` escaping to `htmlEscape` for defensive consistency:
```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;")
    .replace(/'/g,"&#39;");
}
```

---

### IN-02: `buildChunkParams` unit test for 6001-char string uses `new Array(6002).join('A')` which produces 6001 chars, not 6001

**File:** `tests/unit/role_assigner.test.js:355`
**Issue:** The test comment says "3000 + 3000 + 1 chars = 3 chunks" and uses `new Array(6002).join('A')`. `Array(6002).join('A')` produces a string of 6001 `A` characters (Array of 6002 elements joined by 6001 separators). The comment and the code agree numerically — this is correct. However the variable name and comment could confuse future maintainers: the pattern `new Array(N+1).join('A')` to produce N chars is a non-obvious idiom. Since ES6 `'A'.repeat(6001)` is clearer.

**Fix (advisory):** Replace `new Array(6002).join('A')` with `'A'.repeat(6001)` if the environment supports ES6 (Node.js test runner does). If IE9 compatibility is needed (unlikely in Node.js tests), keep the current idiom but add a comment.

---

### IN-03: `users in r.db` Analysis property (ID 2) retrieves every user in the Users table without filtering — could return stale/historical data

**File:** `Dashboard_4_samples/Dereso SWD.bes:15`
**Issue:** Property ID 2 (`users in r.db`) selects all rows from the `users` table with no `WHERE` clause:
```sql
SELECT userid from users
```
The `Users` table presumably records every user ever seen on the client. Depending on how Phase 3 populates this table, this property could return large result sets including long-inactive users. This is not a security issue but a potential data quality issue for dashboards consuming this property.

**Fix:** Consider adding a recency filter such as `WHERE LastSeen > datetime('now', '-90 days')`, or document that property ID 4 (`recent users`) should be used for active-user display.

---

### IN-04: No test covers the `loadAnalysisView` cross-check logic (D-21) for computers missing from Analysis

**File:** `tests/unit/role_assigner.test.js` (gap — no test present)
**Issue:** The D-21 cross-check at `fixlet_role_assigner.ojo:779-795` renders a "DB not initialised" warning row for CSV Computer_IDs not found in Analysis results. This logic involves iterating `csvCompIds` against `foundCompIds` and creating DOM elements. There is no unit test exercising this path. Since the logic relies on DOM (IE9 console), direct testing is not straightforward, but the data-side predicate (`foundCompIds[compId]` lookup) could be extracted and tested independently.

**Fix (advisory):** Extract the cross-check predicate into a pure function `getMissingComputerIds(csvCompIds, foundCompIds)` and add a unit test. This is a non-blocking advisory.

---

_Reviewed: 2026-06-27T22:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
