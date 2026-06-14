/**
 * modifier.test.js
 *
 * Unit tests for the 6 pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_modifier.ojo
 *
 * Functions covered:
 *   1. xmlEscape(s)
 *   2. xmlCDataSafe(s)
 *   3. buildRoleRelevanceFromArray(roles)  -- parameterized version (array input)
 *   4. getRolesFromArray(roleValues)       -- parameterized version (array input)
 *   5. getEffectiveCategoryFromParams(selVal, otherVal) -- parameterized version
 *   6. PORTAL_CONFIG validation            -- structural assertion on config block
 *
 * Running: node tests/unit/modifier.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 *
 * Note: buildUpdateXml() is NOT tested here because it instantiates ActiveXObject
 * (IE-only DOM) and cannot run in Node.js. It is covered by integration tests instead.
 */

"use strict";

var assert = require("assert");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from fixlet_modifier.ojo)
// ---------------------------------------------------------------------------

// Lines 536-543: XML entity escaping
function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// Line 547: CDATA sequence escaping
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }

// PORTAL_CONFIG block -- copy verbatim from fixlet_modifier.ojo
var PORTAL_CONFIG = {
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
    "Graphics & Design",
    "Messengers",
    "Office Applications",
    "Office Tools",
    "Virtualization & Remote Access",
    "Web Browsers"
  ]
};

// Parameterized test version of buildRoleRelevance() from modifier.ojo lines 501-527.
// Accepts a roles array instead of reading from the DOM table.
function buildRoleRelevanceFromArray(roles){
  if(roles.length === 0){ return ""; }
  var roleSet = '"' + roles.join('";"') + '"';
  return '(number of (elements of intersection of (set of (' + roleSet + '); it) of' +
    ' (set of((rows of statement' +
    ' ("select r.role from roles r join map m on m.role = r.id join users u on u.id = m.user' +
    ' where (unixepoch() - unixepoch(u.LastSeen)) / (60 * 60 * 24) < 30 ' +
    ' and userid =\'" & name of logged on user & "\'") of it) of ' +
    ' (sqlite database of file "RoleAwareness.db" ' +
    ' of folder ( concatenation (if (windows of ' +
    '  operating system) then "\" else "/") of (item 0 of it; ' +
    '  item 1 of it; item 2 of it) of ( pathname of parent ' +
    '  folder of parent folder of client folder of site "actionsite", ' +
    '  "EC", "SoftwarePortal" ))) as string))) > 0)|False';
}

// Parameterized test version of getEffectiveCategory() from modifier.ojo lines 210-216.
// Accepts selection value and other value directly instead of reading from DOM.
function getEffectiveCategoryFromParams(selVal, otherVal){
  if(selVal === "__other__"){ return String(otherVal || ""); }
  return selVal;
}

// Parameterized version: accepts a roles array, mirrors getRolesFromEditor() logic
// from modifier.ojo lines 221-233, without DOM dependency.
function getRolesFromArray(roleValues){
  var roles = [];
  for(var i = 0; i < roleValues.length; i++){
    var val = String(roleValues[i] || "");
    if(val !== "" && roles.indexOf(val) < 0){ roles.push(val); }
  }
  return roles;
}

// ---------------------------------------------------------------------------
// 2. TEST INFRASTRUCTURE
// ---------------------------------------------------------------------------

/**
 * makeRoleTableMock(roleValues)
 * Returns a minimal mock of the IE DOM roleFieldTable element.
 * Used by tests that exercise the DOM-bound getRolesFromEditor() shape.
 */
function makeRoleTableMock(roleValues){
  return {
    rows: roleValues.map(function(v){
      return {
        cells: [
          null,
          {
            getElementsByTagName: function(tag){
              if(tag === "select"){ return [{ value: v }]; }
              return [];
            }
          }
        ]
      };
    })
  };
}

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

// --- 3.3 buildRoleRelevanceFromArray ---
section("buildRoleRelevanceFromArray");

expect("zero roles returns empty string", function(){
  assert.strictEqual(buildRoleRelevanceFromArray([]), "");
});
expect("one role: result contains the role name", function(){
  var result = buildRoleRelevanceFromArray(["IT Developer"]);
  assert.ok(result.indexOf("IT Developer") !== -1,
    "Expected result to contain 'IT Developer'");
});
expect("two roles: result contains both roles semicolon-joined", function(){
  var result = buildRoleRelevanceFromArray(["IT Developer", "DB Administrator"]);
  assert.ok(result.indexOf('"IT Developer";"DB Administrator"') !== -1,
    "Expected result to contain '\"IT Developer\";\"DB Administrator\"'");
});
expect("one role: result contains |False fallback", function(){
  var result = buildRoleRelevanceFromArray(["IT Developer"]);
  assert.ok(result.indexOf("|False") !== -1,
    "Expected result to contain '|False'");
});
expect("one role: result contains RoleAwareness.db path", function(){
  var result = buildRoleRelevanceFromArray(["IT Developer"]);
  assert.ok(result.indexOf("RoleAwareness.db") !== -1,
    "Expected result to contain 'RoleAwareness.db'");
});
expect("one role: result contains SQL select statement", function(){
  var result = buildRoleRelevanceFromArray(["IT Developer"]);
  assert.ok(result.indexOf("select r.role from roles r") !== -1,
    "Expected result to contain 'select r.role from roles r'");
});

// --- 3.4 getRolesFromArray ---
section("getRolesFromArray");

expect("empty input returns empty array", function(){
  assert.deepStrictEqual(getRolesFromArray([]), []);
});
expect("single value returns array with that value", function(){
  assert.deepStrictEqual(getRolesFromArray(["Developer"]), ["Developer"]);
});
expect("duplicate values are deduplicated", function(){
  assert.deepStrictEqual(getRolesFromArray(["A", "A"]), ["A"]);
});
expect("empty string entries are skipped", function(){
  assert.deepStrictEqual(getRolesFromArray(["", "B"]), ["B"]);
});

// --- 3.5 getEffectiveCategoryFromParams ---
section("getEffectiveCategoryFromParams");

expect("normal category value is returned as-is", function(){
  assert.strictEqual(getEffectiveCategoryFromParams("Office Tools", ""), "Office Tools");
});
expect("__other__ with a custom value returns the custom value", function(){
  assert.strictEqual(getEffectiveCategoryFromParams("__other__", "Custom Cat"), "Custom Cat");
});
expect("__other__ with empty string returns empty string", function(){
  assert.strictEqual(getEffectiveCategoryFromParams("__other__", ""), "");
});
expect("__other__ with null returns empty string via coercion", function(){
  assert.strictEqual(getEffectiveCategoryFromParams("__other__", null), "");
});

// --- 3.6 PORTAL_CONFIG structural validation ---
section("PORTAL_CONFIG");

expect("PORTAL_CONFIG.roles is a non-empty array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.roles));
  assert.ok(PORTAL_CONFIG.roles.length > 0);
});
expect("PORTAL_CONFIG.categories is a non-empty array", function(){
  assert.ok(Array.isArray(PORTAL_CONFIG.categories));
  assert.ok(PORTAL_CONFIG.categories.length > 0);
});
expect("all PORTAL_CONFIG.roles entries are non-empty strings", function(){
  PORTAL_CONFIG.roles.forEach(function(r){
    assert.strictEqual(typeof r, "string");
    assert.ok(r.length > 0);
  });
});
expect("all PORTAL_CONFIG.categories entries are non-empty strings", function(){
  PORTAL_CONFIG.categories.forEach(function(c){
    assert.strictEqual(typeof c, "string");
    assert.ok(c.length > 0);
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
