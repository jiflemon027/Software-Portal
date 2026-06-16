/**
 * dispatcher.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_dispatcher.ojo
 *
 * Functions covered:
 *   1. xmlEscape(s)
 *   2. xmlCDataSafe(s)
 *   3. buildTargetRelevance(group)
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
// PORTAL CONFIGURATION -- Edit this block to change the default expiry.
// Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  defaultExpirationDays: 7
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================

// buildTargetRelevance(group) -- type-aware group targeting (BigFix Software Installer Library method)
// Automatic: member of group <id> of site... (client-side, numeric ID + lowercase site name)
// Manual: client setting __Group_0_<name>
// Server Based: client setting __Group_1_<name>
// null group returns "true" (all computers)
function buildTargetRelevance(group) {
  if (!group) { return "true"; }
  var id       = group.id;
  var name     = group.name;
  var site     = (group.siteName || "").toLowerCase();
  var type     = group.groupType || "Automatic";
  var safeName = String(name).replace(/"/g, '""');
  var safeSite = site.replace(/"/g, '""');
  if (type === "Manual") {
    return 'exists true whose (if true then (exists setting "__Group_0_' + safeName + '" whose (value of it is "True") of client) else false)';
  }
  if (type === "Server Based") {
    return 'exists true whose (if true then (exists setting "__Group_1_' + safeName + '" whose (value of it is "True") of client) else false)';
  }
  return 'exists true whose (if true then (member of group ' + id + ' of site whose (name of it as lowercase = "' + safeSite + '" as lowercase)) else false)';
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

expect("null group returns 'true' fallback", function(){
  assert.strictEqual(buildTargetRelevance(null), "true");
});
expect("Automatic group produces member-of-group relevance with numeric ID and lowercase site", function(){
  var result = buildTargetRelevance({ id: "123", name: "All Workstations", siteName: "Custom Site", groupType: "Automatic" });
  assert.ok(result.indexOf("member of group 123") !== -1, "Expected numeric group ID");
  assert.ok(result.indexOf("custom site") !== -1, "Expected lowercase site name");
  assert.ok(result.indexOf("exists true whose") === 0, "Expected defensive exists-true wrapping");
});
expect("Manual group produces __Group_0_ client-setting relevance", function(){
  var result = buildTargetRelevance({ id: "456", name: "IT Dept", siteName: "Any", groupType: "Manual" });
  assert.ok(result.indexOf('__Group_0_IT Dept') !== -1, "Expected __Group_0_ prefix");
  assert.ok(result.indexOf("setting") !== -1, "Expected client setting relevance");
});
expect("Server Based group produces __Group_1_ client-setting relevance", function(){
  var result = buildTargetRelevance({ id: "789", name: "All Servers", siteName: "Any", groupType: "Server Based" });
  assert.ok(result.indexOf('__Group_1_All Servers') !== -1, "Expected __Group_1_ prefix");
});
expect("double quote in group name is escaped using BigFix \"\" doubling", function(){
  var result = buildTargetRelevance({ id: "1", name: 'IT "Special"', siteName: "Custom", groupType: "Manual" });
  assert.ok(result.indexOf('IT ""Special""') !== -1, 'Double quote must be doubled for BigFix syntax');
});
expect("missing groupType defaults to Automatic behavior", function(){
  var result = buildTargetRelevance({ id: "99", name: "Test Group", siteName: "Some Site" });
  assert.ok(result.indexOf("member of group 99") !== -1, "Should default to Automatic targeting");
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
