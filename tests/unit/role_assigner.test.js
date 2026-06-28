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
 * Requirements: Node.js built-in `assert` and `fs` modules only (no external packages).
 *
 * Wave 1 stubs: each section asserts only that the function exists and returns
 * a value of the expected type. Wave 2 replaces stubs with correctness assertions.
 */

"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (stubs — Wave 2 replaces with real code)
// ---------------------------------------------------------------------------

// parseCsv(text) — parses CSV text with user,Computer_ID,role header
// Input: raw CSV string (may have CRLF or LF)
// Output: { rows: [{user, computerID, role, lineNum}] } on success
//         { error: "Missing required columns: user, Computer_ID, role" } if header is wrong
// Header matching is case-insensitive; empty lines are skipped
function parseCsv(text) {
  var lines   = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  var headers = lines[0] ? lines[0].split(',').map(function(h){ return h.trim().toLowerCase(); }) : [];
  var userIdx = headers.indexOf('user');
  var compIdx = headers.indexOf('computer_id');
  var roleIdx = headers.indexOf('role');
  if (userIdx < 0 || compIdx < 0 || roleIdx < 0) {
    return { error: 'Missing required columns: user, Computer_ID, role' };
  }
  var rows = [];
  for (var i = 1; i < lines.length; i++) {
    var line = lines[i].trim();
    if (!line) { continue; }
    var parts = line.split(',');
    // Strip RFC 4180 quoted fields so values like "Finance, North" parse correctly (WR-03)
    parts = parts.map(function(p) {
      p = p.trim();
      if (p.length >= 2 && p.charAt(0) === '"' && p.charAt(p.length - 1) === '"') {
        return p.slice(1, -1).replace(/""/g, '"');
      }
      return p;
    });
    rows.push({
      user:       (parts[userIdx]  || '').trim(),
      computerID: (parts[compIdx]  || '').trim(),
      role:       (parts[roleIdx]  || '').trim(),
      lineNum:    i + 1
    });
  }
  return { rows: rows };
}

// validateRows(rows, allowedRoles) — validates parsed CSV rows
// Input: rows[] from parseCsv, allowedRoles string[]
// Output: { errors: [{rowIndex, field, msg}], warnings: [{rowIndex, msg}] }
// BLOCK errors: blank user, blank computerID, unknown role
// WARN only: duplicate key (user|computerID|role)
function validateRows(rows, allowedRoles) {
  var seen     = {};
  var errors   = [];
  var warnings = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var key = row.user + '|' + row.computerID + '|' + row.role;
    if (!row.user) {
      errors.push({ rowIndex: i, field: 'user', msg: 'User is blank' });
    }
    if (!row.computerID) {
      errors.push({ rowIndex: i, field: 'computerID', msg: 'Computer_ID is blank' });
    }
    if (!row.role) {
      errors.push({ rowIndex: i, field: 'role', msg: 'Role is blank' });
    } else if (allowedRoles.indexOf(row.role) < 0) {
      errors.push({ rowIndex: i, field: 'role', msg: 'Unknown role: "' + row.role + '"' });
    }
    if (seen[key]) {
      warnings.push({ rowIndex: i, msg: 'Duplicate row (will be ignored by upsert)' });
    }
    seen[key] = true;
  }
  return { errors: errors, warnings: warnings };
}

// safeB64Encode(str) — Base64-encodes a UTF-8 string
// In Node.js (test file): Buffer.from(str, 'utf8').toString('base64')
// In browser (OJO): btoa(unescape(encodeURIComponent(str)))
// Round-trip: Buffer.from(safeB64Encode(s), 'base64').toString('utf8') === s
function safeB64Encode(str) {
  return Buffer.from(str, 'utf8').toString('base64');
}

// chunkString(s, size) — splits a string into segments of exactly `size` chars
// Last element may be shorter; empty string returns []
function chunkString(s, size) {
  var chunks = [];
  for (var i = 0; i < s.length; i += size) {
    chunks.push(s.slice(i, i + size));
  }
  return chunks;
}

// buildChunkParams(b64) — produces ActionScript parameter lines for Base64 chunks
// CHUNK_SIZE = 3000; chunkCount is the last line
// Returns multi-line string: parameter "chunk0"="...", ..., parameter "chunkCount"="N"
var CHUNK_SIZE = 3000;
function buildChunkParams(b64) {
  var chunks = chunkString(b64, CHUNK_SIZE);
  var lines = [];
  for (var i = 0; i < chunks.length; i++) {
    lines.push('parameter "chunk' + i + '"="' + chunks[i] + '"');
  }
  lines.push('parameter "chunkCount"="' + chunks.length + '"');
  return lines.join('\r\n');
}

// xmlEscape(s) — XML entity escaping (verbatim from dispatcher.test.js lines 31-38)
function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// xmlCDataSafe(s) — CDATA sequence escaping (verbatim from dispatcher.test.js line 41)
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }

// cdataStart/cdataEnd helpers — split to avoid literal ]]> in source
function cdataStart(){ return '<!' + '[CDATA['; }
function cdataEnd(){ return ']]' + '>'; }

// buildAssignActionXml(role, computerIds, actionScript, suffix, relevance)
// title = 'Dereso_' + role + ' Assign_' + suffix  (per D-09)
// XML contains <Title>, <Relevance>, <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">,
// <Settings><ActionUITitle>, <Target> with one <ComputerID> per entry in computerIds
function buildAssignActionXml(role, computerIds, actionScript, suffix, relevance) {
  var title = 'Dereso_' + role + ' Assign_' + suffix;
  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <SingleAction>\r\n';
  xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';
  xml += '    <Relevance>' + xmlEscape(relevance) + '</Relevance>\r\n';
  xml += '    <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">';
  xml += cdataStart() + xmlCDataSafe(actionScript) + cdataEnd();
  xml += '</ActionScript>\r\n';
  xml += '    <Settings>\r\n';
  xml += '      <ActionUITitle>' + xmlEscape(title) + '</ActionUITitle>\r\n';
  xml += '    </Settings>\r\n';
  xml += '    <Target>\r\n';
  for (var i = 0; i < computerIds.length; i++) {
    xml += '      <ComputerID>' + xmlEscape(String(computerIds[i])) + '</ComputerID>\r\n';
  }
  xml += '    </Target>\r\n';
  xml += '  </SingleAction>\r\n';
  xml += '</BES>';
  return xml;
}

// PORTAL_CONFIG — per D-19 (exact values from CONTEXT.md)
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

// ---------------------------------------------------------------------------
// 2. TEST INFRASTRUCTURE (verbatim from dispatcher.test.js)
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
// 3. FIXTURE DIRECTORY
// ---------------------------------------------------------------------------

var FIXTURE_DIR = path.join(__dirname, '..', 'fixtures', 'phase-04');

// ---------------------------------------------------------------------------
// 4. TEST BLOCKS (Wave 2 — real correctness assertions for all 9 function groups)
// ---------------------------------------------------------------------------

// --- Section 1: parseCsv ---
section("parseCsv");

expect("parseCsv: valid single row returns correct fields", function(){
  var result = parseCsv("user,Computer_ID,role\njsmith,100001,IT Operations");
  assert.ok(result.rows, "Expected rows property");
  assert.strictEqual(result.rows.length, 1, "Expected 1 row");
  assert.strictEqual(result.rows[0].user, 'jsmith');
  assert.strictEqual(result.rows[0].computerID, '100001');
  assert.strictEqual(result.rows[0].role, 'IT Operations');
  assert.strictEqual(result.rows[0].lineNum, 2);
});

expect("parseCsv: wrong header returns error object", function(){
  var result = parseCsv("name,id,category\nfoo,bar,baz");
  assert.ok(!result.rows, "Expected no rows on error");
  assert.strictEqual(result.error, 'Missing required columns: user, Computer_ID, role');
});

expect("parseCsv: sample.csv returns 4 rows", function(){
  var text = fs.readFileSync(path.join(FIXTURE_DIR, 'sample.csv'), 'utf8');
  var result = parseCsv(text);
  assert.ok(result.rows, "Expected rows property");
  assert.strictEqual(result.rows.length, 4, "Expected 4 rows from sample.csv");
});

expect("parseCsv: CRLF and LF endings produce identical results", function(){
  var lf   = "user,Computer_ID,role\njsmith,100001,IT Operations\nbdoe,100002,Finance";
  var crlf = "user,Computer_ID,role\r\njsmith,100001,IT Operations\r\nbdoe,100002,Finance";
  var r1 = parseCsv(lf);
  var r2 = parseCsv(crlf);
  assert.strictEqual(r1.rows.length, r2.rows.length, "Row count must match for CRLF vs LF");
  assert.strictEqual(r1.rows[0].user, r2.rows[0].user, "First row user must match");
});

expect("parseCsv: header matching is case-insensitive", function(){
  var result = parseCsv("USER,COMPUTER_ID,ROLE\njsmith,100001,IT Operations");
  assert.ok(result.rows, "Expected rows, not error");
  assert.strictEqual(result.rows.length, 1);
  assert.strictEqual(result.rows[0].user, 'jsmith');
});

// --- Section 2: validateRows ---
section("validateRows");

expect("validateRows: valid rows return empty errors and warnings", function(){
  var rows = [{ user: 'jsmith', computerID: '100001', role: 'IT Operations', lineNum: 2 }];
  var result = validateRows(rows, ['IT Operations', 'Finance', 'HR']);
  assert.deepStrictEqual(result.errors, []);
  assert.deepStrictEqual(result.warnings, []);
});

expect("validateRows: unknown role produces BLOCK error with field=role", function(){
  var text = fs.readFileSync(path.join(FIXTURE_DIR, 'invalid-unknown-role.csv'), 'utf8');
  var rows = parseCsv(text).rows;
  var result = validateRows(rows, ['IT Operations', 'Finance', 'HR']);
  assert.ok(result.errors.length >= 1, "Expected at least 1 blocking error");
  var roleError = result.errors.filter(function(e){ return e.field === 'role'; })[0];
  assert.ok(roleError, "Expected an error with field='role'");
  assert.ok(roleError.msg.indexOf('SuperAdmin') >= 0, "Error message should mention 'SuperAdmin'");
});

expect("validateRows: blank user and blank Computer_ID produce BLOCK errors", function(){
  var text = fs.readFileSync(path.join(FIXTURE_DIR, 'invalid-blank-fields.csv'), 'utf8');
  var rows = parseCsv(text).rows;
  var result = validateRows(rows, ['IT Operations', 'Finance', 'HR']);
  assert.ok(result.errors.length >= 2, "Expected at least 2 blocking errors");
  var userError = result.errors.filter(function(e){ return e.field === 'user'; })[0];
  var compError = result.errors.filter(function(e){ return e.field === 'computerID'; })[0];
  assert.ok(userError, "Expected error with field='user'");
  assert.ok(compError, "Expected error with field='computerID'");
});

expect("validateRows: blank role produces BLOCK error with field=role", function(){
  var blankRoleText = fs.readFileSync(path.join(FIXTURE_DIR, 'invalid-blank-role.csv'), 'utf8');
  var blankRoleParsed = parseCsv(blankRoleText);
  assert.ok(!blankRoleParsed.error, 'parseCsv should succeed on valid header');
  var result = validateRows(blankRoleParsed.rows, PORTAL_CONFIG.roles);
  assert.ok(result.errors.length >= 1, 'Expected at least 1 blocking error for blank role');
  var roleError = result.errors.filter(function(e){ return e.field === 'role'; })[0];
  assert.ok(roleError, 'Expected an error with field="role"');
  assert.ok(
    roleError.msg.toLowerCase().indexOf('blank') >= 0 || roleError.msg.toLowerCase().indexOf('role') >= 0,
    'Error message should describe blank role: got "' + roleError.msg + '"'
  );
});

expect("validateRows: duplicate rows produce WARN (not error)", function(){
  var text = fs.readFileSync(path.join(FIXTURE_DIR, 'duplicate-rows.csv'), 'utf8');
  var rows = parseCsv(text).rows;
  var result = validateRows(rows, ['IT Operations', 'Finance', 'HR']);
  assert.strictEqual(result.errors.length, 0, "Expected 0 blocking errors for duplicates");
  assert.ok(result.warnings.length >= 1, "Expected at least 1 duplicate warning");
});

// --- Section 3: safeB64Encode / encodeMatrix ---
section("safeB64Encode / encodeMatrix");

expect("safeB64Encode returns a non-empty Base64 string", function(){
  var result = safeB64Encode("hello");
  assert.ok(typeof result === 'string' && result.length > 0, "Expected non-empty Base64 string");
  assert.ok(/^[A-Za-z0-9+/=]+$/.test(result), "Expected Base64 alphabet only");
});

expect("safeB64Encode round-trip: decode returns original string", function(){
  var original = "hello world";
  var encoded = safeB64Encode(original);
  var decoded = Buffer.from(encoded, 'base64').toString('utf8');
  assert.strictEqual(decoded, original, "Round-trip decode must equal original");
});

// --- Section 4: chunkString ---
section("chunkString");

expect("chunkString splits into correct segments", function(){
  assert.deepStrictEqual(chunkString("abcde", 2), ["ab", "cd", "e"]);
});

expect("chunkString empty string returns empty array", function(){
  assert.deepStrictEqual(chunkString("", 3000), []);
});

expect("chunkString string shorter than chunk size returns one element", function(){
  assert.deepStrictEqual(chunkString("abc", 10), ["abc"]);
});

// --- Section 5: buildChunkParams ---
section("buildChunkParams");

expect("buildChunkParams starts with chunk0 parameter line", function(){
  var result = buildChunkParams("abc");
  var firstLine = result.split('\r\n')[0];
  assert.ok(firstLine.indexOf('parameter "chunk0"=') === 0, "First line must start with chunk0 parameter");
});

expect("buildChunkParams: single chunk has chunkCount=1", function(){
  var result = buildChunkParams("shortstring");
  assert.ok(result.indexOf('parameter "chunkCount"="1"') >= 0, "Expected chunkCount=1 for short string");
});

expect("buildChunkParams: 6001-char string produces chunkCount=3", function(){
  // 3000 + 3000 + 1 chars = 3 chunks
  var long = new Array(6002).join('A');
  var result = buildChunkParams(long);
  assert.ok(result.indexOf('parameter "chunkCount"="3"') >= 0, "Expected chunkCount=3 for 6001-char string");
});

expect("buildChunkParams: chunk values contain only B64 alphabet chars", function(){
  var b64 = safeB64Encode("test string for b64 chunk verification");
  var result = buildChunkParams(b64);
  // Extract value between first =" and next "
  var match = result.match(/parameter "chunk0"="([^"]*)"/);
  assert.ok(match, "Expected chunk0 line to match parameter pattern");
  assert.ok(/^[A-Za-z0-9+/=]+$/.test(match[1]), "chunk0 value must contain only B64 alphabet chars");
});

// --- Section 6: xmlEscape ---
section("xmlEscape");

expect("xmlEscape: all five special chars escaped in one string", function(){
  assert.strictEqual(xmlEscape("&<>\"'"), "&amp;&lt;&gt;&quot;&apos;");
});

expect("xmlEscape: safe string unchanged", function(){
  assert.strictEqual(xmlEscape("safe string"), "safe string");
});

expect("xmlEscape: empty string returns empty string", function(){
  assert.strictEqual(xmlEscape(""), "");
});

// --- Section 7: xmlCDataSafe ---
section("xmlCDataSafe");

expect("xmlCDataSafe: replaces ]]> with split CDATA sequence", function(){
  assert.strictEqual(xmlCDataSafe("before]]>after"), "before]]]]><![CDATA[>after");
});

expect("xmlCDataSafe: string without ]]> is unchanged", function(){
  assert.strictEqual(xmlCDataSafe("no cdata end"), "no cdata end");
});

// --- Section 8: buildAssignActionXml ---
section("buildAssignActionXml");

expect("buildAssignActionXml: title contains Dereso_[Role] Assign_[suffix] (D-09)", function(){
  var result = buildAssignActionXml("IT Operations", ["100001", "100002"], "script content", "TestSuffix", "true");
  assert.ok(result.indexOf("Dereso_IT Operations Assign_TestSuffix") >= 0,
    "Title must follow D-09 naming convention");
});

expect("buildAssignActionXml: contains one <ComputerID> per entry", function(){
  var result = buildAssignActionXml("IT Operations", ["100001", "100002"], "script content", "TestSuffix", "true");
  assert.ok(result.indexOf("<ComputerID>100001</ComputerID>") >= 0, "Expected ComputerID 100001");
  assert.ok(result.indexOf("<ComputerID>100002</ComputerID>") >= 0, "Expected ComputerID 100002");
});

expect("buildAssignActionXml: contains <Relevance> element", function(){
  var result = buildAssignActionXml("IT Operations", ["100001"], "script content", "Test", "true");
  assert.ok(result.indexOf("<Relevance>") >= 0, "Expected <Relevance> element");
});

expect("buildAssignActionXml: contains <ActionScript MIMEType> element", function(){
  var result = buildAssignActionXml("IT Operations", ["100001"], "script content", "Test", "true");
  assert.ok(result.indexOf('<ActionScript MIMEType="application/x-Fixlet-Windows-Shell">') >= 0,
    "Expected ActionScript element with correct MIMEType");
});

expect("buildAssignActionXml: XML-special chars in role are escaped in title", function(){
  var result = buildAssignActionXml("Finance & Tax", ["100001"], "script", "Test", "true");
  assert.ok(result.indexOf("Finance &amp; Tax") >= 0, "& in role must be escaped to &amp;");
});

// --- Section 9: PORTAL_CONFIG ---
section("PORTAL_CONFIG");

expect("PORTAL_CONFIG.roles deep-equals ['IT Operations', 'Finance', 'HR'] (D-19)", function(){
  assert.deepStrictEqual(PORTAL_CONFIG.roles, ['IT Operations', 'Finance', 'HR']);
});

expect("PORTAL_CONFIG.actionNamePrefix is 'Dereso' (D-19)", function(){
  assert.strictEqual(PORTAL_CONFIG.actionNamePrefix, 'Dereso');
});

expect("PORTAL_CONFIG.targetGroups is non-empty array containing 'All Workstations' (D-19)", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.targetGroups) && PORTAL_CONFIG.targetGroups.length > 0,
    "Expected non-empty targetGroups array");
  assert.ok(PORTAL_CONFIG.targetGroups.indexOf('All Workstations') >= 0,
    "Expected 'All Workstations' in targetGroups");
});

// ---------------------------------------------------------------------------
// 5. SUMMARY FOOTER (verbatim from dispatcher.test.js)
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
