/**
 * role_admin.test.js
 *
 * Unit tests for the pure JavaScript functions that will be extracted from the new
 *   Existing Dashboards/fixlet_role_admin.ojo   (built in 07-04)
 *
 * Wave 0 (07-00): this is a WORKING STUB. The "scaffold" section has a real passing
 * assertion so the file can join the Node regression chain immediately; the other four
 * sections are placeholders that 07-04 fills in:
 *
 *   switchTab                    - IE9 tab-panel show/hide (mirror of the OJO helper)
 *   GroupRoleMap row validation  - Pattern/Match_On/Role/Priority/Active row checks
 *   Test Pattern matcher         - JS mirror of the PowerShell GroupRoleMap matcher
 *                                  (exact NOCASE + trailing-* wildcard, cn|display|dn)
 *   base64 chunk chain           - safeB64Encode / chunkString / buildChunkParams,
 *                                  lifted verbatim from fixlet_role_assigner.ojo
 *
 * Running: node tests/unit/role_admin.test.js
 * Requirements: Node.js built-in `assert` and `fs`/`path` only (no external packages).
 */

"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");

// ---------------------------------------------------------------------------
// TEST INFRASTRUCTURE (verbatim from role_assigner.test.js / dispatcher.test.js)
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

var FIXTURE_DIR = path.join(__dirname, "..", "fixtures", "phase-07");

// ---------------------------------------------------------------------------
// 1. scaffold  - real assertions so the file exits 0 and guards the fixtures
// ---------------------------------------------------------------------------
section("scaffold");

expect("phase-07 fixture directory exists", function(){
  assert.ok(fs.existsSync(FIXTURE_DIR), "expected " + FIXTURE_DIR + " to exist");
});

expect("roleref-AAG-UK-sample.json parses and is the extended D-11 shape", function(){
  var snap = JSON.parse(fs.readFileSync(path.join(FIXTURE_DIR, "roleref-AAG-UK-sample.json"), "utf8"));
  assert.strictEqual(snap.region, "AAG-UK");
  assert.ok(Array.isArray(snap.roles) && snap.roles.length >= 3, "expected >= 3 role blocks");
  var i, j, u;
  for (i = 0; i < snap.roles.length; i++){
    assert.ok(Array.isArray(snap.roles[i].users), "role block missing users[]");
    for (j = 0; j < snap.roles[i].users.length; j++){
      u = snap.roles[i].users[j];
      assert.strictEqual(typeof u, "object", "users[] entry must be an object, not a bare string");
      assert.ok(u.id && u.source_type, "users[] entry needs id + source_type");
      assert.ok(Object.prototype.hasOwnProperty.call(u, "source_value"), "users[] entry needs source_value key");
    }
  }
});

expect("config/GroupRoleMap.json is empty-by-design", function(){
  var grm = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "config", "GroupRoleMap.json"), "utf8"));
  assert.ok(Array.isArray(grm.rules), "expected a rules array");
  assert.strictEqual(grm.rules.length, 0, "config/GroupRoleMap.json must ship with zero production rules");
});

// ---------------------------------------------------------------------------
// 2. switchTab  - 07-04 fills this in
// ---------------------------------------------------------------------------
section("switchTab");
// (placeholder - no assertions yet)

// ---------------------------------------------------------------------------
// 3. GroupRoleMap row validation  - 07-04 fills this in
// ---------------------------------------------------------------------------
section("GroupRoleMap row validation");
// (placeholder - no assertions yet)

// ---------------------------------------------------------------------------
// 4. Test Pattern matcher  - 07-04 fills this in
// ---------------------------------------------------------------------------
section("Test Pattern matcher");
// (placeholder - no assertions yet)

// ---------------------------------------------------------------------------
// 5. base64 chunk chain  - 07-04 fills this in
// ---------------------------------------------------------------------------
section("base64 chunk chain");
// (placeholder - no assertions yet)

// ---------------------------------------------------------------------------
// SUMMARY FOOTER (verbatim from role_assigner.test.js)
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
