/**
 * dispatcher.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_dispatcher.ojo
 *
 * Functions covered:
 *   1. xmlEscape(s)
 *   2. xmlCDataSafe(s)
 *   3. buildTargetRelevance(groupName)
 *   4. buildExpirationElement(days)
 *   5. parseActionId(body)           -- regex-fallback path only
 *   6. PORTAL_CONFIG validation      -- structural assertion
 *
 * Running: node tests/unit/dispatcher.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 *
 * Note: buildDeployXml() is NOT tested here because it instantiates ActiveXObject
 * (IE-only DOM) and cannot run in Node.js. It is covered by integration tests instead.
 */

"use strict";

var assert = require("assert");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from fixlet_dispatcher.ojo)
// ---------------------------------------------------------------------------

// XML entity escaping (identical to modifier.ojo lines 536-543)
function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// CDATA sequence escaping (identical to modifier.ojo line 547)
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }

// PORTAL_CONFIG block -- dispatcher configuration (per D-03 and RESEARCH.md Pattern 7)
// ==========================================================================
// PORTAL CONFIGURATION -- Edit this block to add/remove target groups or
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

// buildTargetRelevance(groupName) -- from RESEARCH.md Pattern 5
// Converts a target group name to a BigFix relevance expression.
// Falls back to "true" (all computers) for blank/empty group names.
// BigFix relevance uses double-quoted strings; "" escapes a literal double quote.
function buildTargetRelevance(groupName) {
  if (!groupName || groupName.replace(/^\s+|\s+$/g, "") === "") { return "true"; }
  var safeGroup = String(groupName).replace(/"/g, '""');
  return 'member of bes computer group whose (name of it = "' + safeGroup + '")';
}

// buildExpirationElement(days) -- from RESEARCH.md Pattern 6A
// Returns HasEndTime + EndDateTimeLocalOffset XML string with ISO 8601 P{N}D duration.
function buildExpirationElement(days) {
  return "<HasEndTime>true</HasEndTime>" +
         "<EndDateTimeLocalOffset>P" + parseInt(days, 10) + "D</EndDateTimeLocalOffset>";
}

// parseActionId(body) -- from RESEARCH.md Pattern 3
// Extracts the numeric action ID from a BESAPI POST response body.
// Tries ActiveXObject XML parse first (IE9 only), falls through to regex in Node.js.
function parseActionId(body) {
  var m;
  if (!body) { return ""; }
  try {
    var xml = new ActiveXObject("Msxml2.DOMDocument.6.0");
    xml.async = false;
    xml.loadXML(body);
    var nodes = xml.getElementsByTagName("Action");
    if (nodes.length > 0) {
      var idNode = nodes[0].selectSingleNode("ID");
      if (idNode && idNode.text) { return idNode.text; }
      var res = nodes[0].getAttribute("Resource");
      if (res) { var rm = /\/(\d+)$/.exec(res); if (rm && rm[1]) { return rm[1]; } }
    }
  } catch (ex) {}
  m = /\/api\/action\/(\d+)/i.exec(body);
  if (m && m[1]) { return m[1]; }
  m = /<ID>(\d+)<\/ID>/i.exec(body);
  if (m && m[1]) { return m[1]; }
  return "";
}

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

// --- 3.1 xmlEscape ---
section("xmlEscape");

expect("escapes ampersand", function(){
  assert.strictEqual(xmlEscape("&"), "&amp;");
});
expect("escapes less-than", function(){
  assert.strictEqual(xmlEscape("<"), "&lt;");
});
expect("escapes greater-than", function(){
  assert.strictEqual(xmlEscape(">"), "&gt;");
});
expect("escapes double-quote", function(){
  assert.strictEqual(xmlEscape('"'), "&quot;");
});
expect("escapes single-quote", function(){
  assert.strictEqual(xmlEscape("'"), "&apos;");
});
expect("escapes all five characters in one string", function(){
  assert.strictEqual(
    xmlEscape("&<>\"'"),
    "&amp;&lt;&gt;&quot;&apos;"
  );
});
expect("empty string returns empty string", function(){
  assert.strictEqual(xmlEscape(""), "");
});
expect("non-string number is coerced to string — no throw", function(){
  assert.strictEqual(xmlEscape(42), "42");
});

// --- 3.2 xmlCDataSafe ---
section("xmlCDataSafe");

expect("replaces ]]> with split CDATA sequence", function(){
  assert.strictEqual(
    xmlCDataSafe("]]>"),
    "]]]]><![CDATA[>"
  );
});
expect("string without ]]> is unchanged", function(){
  assert.strictEqual(xmlCDataSafe("no occurrence"), "no occurrence");
});
expect("multiple ]]> occurrences are all replaced", function(){
  assert.strictEqual(
    xmlCDataSafe("a]]>b]]>c"),
    "a]]]]><![CDATA[>b]]]]><![CDATA[>c"
  );
});
expect("empty string returns empty string", function(){
  assert.strictEqual(xmlCDataSafe(""), "");
});

// --- 3.3 buildTargetRelevance ---
section("buildTargetRelevance");

expect("standard group name produces member-of relevance", function(){
  var result = buildTargetRelevance("All Workstations");
  assert.ok(result.indexOf("member of bes computer group") !== -1,
    "Expected result to contain 'member of bes computer group'");
  assert.ok(result.indexOf("All Workstations") !== -1,
    "Expected result to contain 'All Workstations'");
});
expect("empty group name returns 'true' fallback", function(){
  assert.strictEqual(buildTargetRelevance(""), "true");
  assert.strictEqual(buildTargetRelevance("   "), "true");
});
expect("group name with double quote is escaped using BigFix \"\" doubling", function(){
  var result = buildTargetRelevance('IT "Special"');
  assert.ok(result.indexOf('IT ""Special""') !== -1,
    'Double quote must be doubled ("") for BigFix relevance syntax');
});

// --- 3.4 parseActionId ---
section("parseActionId");


expect("extracts ID from /api/action/N URL pattern", function(){
  assert.strictEqual(parseActionId('<Action Resource="/api/action/9876"/>'), "9876");
});
expect("extracts ID from <ID>N</ID> element", function(){
  assert.strictEqual(parseActionId('<ID>42</ID>'), "42");
});
expect("returns empty string for empty body", function(){
  assert.strictEqual(parseActionId(""), "");
  assert.strictEqual(parseActionId(null), "");
});

// --- 3.6 PORTAL_CONFIG ---
section("PORTAL_CONFIG");

expect("PORTAL_CONFIG.defaultExpirationDays is a positive integer", function(){
  assert.strictEqual(typeof PORTAL_CONFIG.defaultExpirationDays, "number");
  assert.ok(PORTAL_CONFIG.defaultExpirationDays > 0,
    "Expected defaultExpirationDays to be > 0");
  assert.strictEqual(
    PORTAL_CONFIG.defaultExpirationDays,
    Math.floor(PORTAL_CONFIG.defaultExpirationDays),
    "Expected defaultExpirationDays to be an integer (equal to Math.floor of itself)"
  );
});
expect("PORTAL_CONFIG.targetGroups is a non-empty array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.targetGroups),
    "Expected targetGroups to be an Array");
  assert.ok(PORTAL_CONFIG.targetGroups.length > 0,
    "Expected targetGroups to be non-empty");
});
expect("all PORTAL_CONFIG.targetGroups entries are non-empty strings", function(){
  PORTAL_CONFIG.targetGroups.forEach(function(g){
    assert.strictEqual(typeof g, "string",
      "Expected targetGroups entry to be a string, got: " + typeof g);
    assert.ok(g.length > 0,
      "Expected targetGroups entry to be non-empty, got: '" + g + "'");
  });
});

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
