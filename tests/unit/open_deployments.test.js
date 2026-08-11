/**
 * open_deployments.test.js
 *
 * Unit tests for the pure JavaScript functions backing the "Open Deployments"
 * grid column, duplicated verbatim into:
 *   Existing Dashboards/fixlet_dispatcher.ojo
 *   Existing Dashboards/fixlet_modifier.ojo
 *
 * Functions covered:
 *   1. buildOpenDeploymentMap(names)
 *   2. compareOpenDeployments(a, b, asc) -- comparator body mirrored in
 *      applySortToCurrentItems() of both .ojo files
 *
 * Running: node tests/unit/open_deployments.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 *
 * Note: loadOpenDeploymentCounts() is NOT tested here because it calls
 * EvaluateRelevance(), which only exists inside the BigFix console host and
 * does not exist in Node.js. Same omission pattern as dispatcher.test.js
 * omitting buildDeployXml() (ActiveXObject-only).
 */

"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from both .ojo files)
// ---------------------------------------------------------------------------

// buildOpenDeploymentMap(names) -- verbatim from the plan's shared_helper section
function buildOpenDeploymentMap(names){
  var map = {}, i, key;
  for(i = 0; i < names.length; i++){
    key = String(names[i]);
    map[key] = (map[key] || 0) + 1;
  }
  return map;
}

// compareOpenDeployments(a, b, asc) -- standalone extraction of the numeric
// sort branch that Tasks 2 and 3 add to applySortToCurrentItems()
function compareOpenDeployments(a, b, asc){
  var na = parseInt(String(a.openDeployments || ""), 10) || 0;
  var nb = parseInt(String(b.openDeployments || ""), 10) || 0;
  return asc ? na - nb : nb - na;
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

// --- 3.1 buildOpenDeploymentMap ---
section("buildOpenDeploymentMap");

expect("empty array returns empty map, not null", function(){
  var result = buildOpenDeploymentMap([]);
  assert.notStrictEqual(result, null);
  assert.deepStrictEqual(result, {});
});
expect("counts duplicate names correctly", function(){
  var result = buildOpenDeploymentMap(["A", "B", "A"]);
  assert.deepStrictEqual(result, { A: 2, B: 1 });
});
expect("counting is case-sensitive", function(){
  var result = buildOpenDeploymentMap(["Adobe", "adobe"]);
  assert.deepStrictEqual(result, { Adobe: 1, adobe: 1 });
  assert.strictEqual(Object.keys(result).length, 2);
});
expect("lookup of an absent name via (map[name] || 0) yields 0", function(){
  var result = buildOpenDeploymentMap(["A"]);
  assert.strictEqual(result["NotPresent"] || 0, 0);
});

// --- 3.2 compareOpenDeployments ---
section("compareOpenDeployments");

expect("numeric comparator sorts '10' after '9' ascending", function(){
  var a = { openDeployments: "10" };
  var b = { openDeployments: "9" };
  assert.ok(compareOpenDeployments(a, b, true) > 0, "10 should sort after 9 ascending");
});
expect("numeric comparator treats '' as 0", function(){
  var a = { openDeployments: "" };
  var b = { openDeployments: "0" };
  assert.strictEqual(compareOpenDeployments(a, b, true), 0);
});
expect("numeric comparator treats '—' (em dash) as 0", function(){
  var a = { openDeployments: "—" };
  var b = { openDeployments: "0" };
  assert.strictEqual(compareOpenDeployments(a, b, true), 0);
});
expect("numeric comparator does not produce NaN ordering", function(){
  var a = { openDeployments: "—" };
  var b = { openDeployments: "5" };
  var result = compareOpenDeployments(a, b, true);
  assert.ok(!isNaN(result), "Result must not be NaN");
  assert.ok(result < 0, "0 should sort before 5 ascending");
});
expect("numeric comparator descending is the exact reverse of ascending", function(){
  var a = { openDeployments: "3" };
  var b = { openDeployments: "7" };
  var asc  = compareOpenDeployments(a, b, true);
  var desc = compareOpenDeployments(a, b, false);
  assert.strictEqual(Math.sign(asc), -Math.sign(desc));
});

// ---------------------------------------------------------------------------
// 4. STRUCTURAL PARITY ASSERTIONS
// ---------------------------------------------------------------------------
// Task 3 appends fixlet_modifier.ojo structural assertions plus the
// cross-file buildOpenDeploymentMap identity check here.

section("Structural parity: fixlet_dispatcher.ojo");

var dispatcherPath = path.join(__dirname, "..", "..", "Existing Dashboards", "fixlet_dispatcher.ojo");
var dispatcherSrc  = fs.readFileSync(dispatcherPath, "utf8");

expect("dispatcher contains makeSortHeader(\"openDeployments\"", function(){
  assert.ok(dispatcherSrc.indexOf('makeSortHeader("openDeployments"') !== -1,
    "Expected makeSortHeader(\"openDeployments\" call in fixlet_dispatcher.ojo");
});
expect("dispatcher contains loadOpenDeploymentCounts()", function(){
  assert.ok(dispatcherSrc.indexOf("loadOpenDeploymentCounts()") !== -1,
    "Expected loadOpenDeploymentCounts() call in fixlet_dispatcher.ojo");
});
expect("dispatcher contains buildOpenDeploymentMap", function(){
  assert.ok(dispatcherSrc.indexOf("buildOpenDeploymentMap") !== -1,
    "Expected buildOpenDeploymentMap in fixlet_dispatcher.ojo");
});
expect("dispatcher contains openDeployments: field", function(){
  assert.ok(dispatcherSrc.indexOf("openDeployments:") !== -1,
    "Expected openDeployments: field in fixlet_dispatcher.ojo");
});
expect("dispatcher does NOT contain the forbidden correlated self-comparison", function(){
  assert.ok(dispatcherSrc.indexOf("name of it = name of it") === -1,
    "Forbidden correlated-subquery form found in fixlet_dispatcher.ojo");
});

// ---------------------------------------------------------------------------
// 5. SUMMARY FOOTER
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
