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

var FIXTURE_DIR = path.join(__dirname, "..", "..", "fixtures", "phase-07");

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
  var grm = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "..", "..", "config", "archive", "GroupRoleMap.json"), "utf8"));
  assert.ok(Array.isArray(grm.rules), "expected a rules array");
  assert.strictEqual(grm.rules.length, 0, "config/GroupRoleMap.json must ship with zero production rules");
});

// ---------------------------------------------------------------------------
// EXTRACTED FUNCTION IMPLEMENTATIONS
// Copied VERBATIM from Existing Dashboards/fixlet_role_admin.ojo with the source
// marker noted. The GroupRoleMap matcher block mirrors scripts/AxoniousParse.psm1
// Resolve-Roles one-for-one; parity is asserted here AND in Pester.
// ---------------------------------------------------------------------------

// --- fixlet_role_admin.ojo: function htmlEscape (L "-- HTML escaping --") ---
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}

// --- fixlet_role_admin.ojo: btoa polyfill + safeB64Encode / chunkString /
//     CHUNK_SIZE / buildChunkParams (verbatim from fixlet_role_assigner.ojo) ---
if (typeof btoa === 'undefined') {
  btoa = function(s) {
    var CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var str = String(s), out = '', i = 0;
    while (i < str.length) {
      var b0 = str.charCodeAt(i++), b1 = str.charCodeAt(i++), b2 = str.charCodeAt(i++);
      out += CHARS.charAt(b0 >> 2)
           + CHARS.charAt(((b0 & 3) << 4) | (b1 >> 4))
           + (isNaN(b1) ? '=' : CHARS.charAt(((b1 & 15) << 2) | (b2 >> 6)))
           + (isNaN(b2) ? '=' : CHARS.charAt(b2 & 63));
    }
    return out;
  };
}
function safeB64Encode(str) {
  return btoa(unescape(encodeURIComponent(str)));
}
function chunkString(s, size) {
  var chunks = [];
  for (var i = 0; i < s.length; i += size) {
    chunks.push(s.slice(i, i + size));
  }
  return chunks;
}
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

// --- fixlet_role_admin.ojo: function switchTab (RESEARCH Pattern 8) ---
function switchTab(tab){
  var ids = ["GroupRoleMap","RolePublication","Region","ReferenceDB"];
  var i, panel, btn;
  for(i=0;i<ids.length;i++){
    panel = document.getElementById("tab"+ids[i]);
    btn   = document.getElementById("tabBtn"+ids[i]);
    if(panel){ panel.style.display = (ids[i]===tab) ? "" : "none"; }
    if(btn){ btn.className = (ids[i]===tab) ? "tabBtn tabActive" : "tabBtn"; }
  }
}

// --- fixlet_role_admin.ojo: function trimStr ---
function trimStr(s){ return String(s).replace(/^\s+|\s+$/g, ""); }

// --- fixlet_role_admin.ojo: function deriveViews (mirror of Get-GroupViews) ---
function deriveViews(raw, display){
  var r = (raw === undefined || raw === null) ? "" : trimStr(raw);
  var cn = r;
  if(/^\s*CN=/i.test(r)){
    var rest = r.substring(r.indexOf("=") + 1);
    var buf = "";
    for(var i = 0; i < rest.length; i++){
      var ch = rest.charAt(i);
      if(ch === "\\" && (i + 1) < rest.length){
        buf += rest.charAt(i + 1);
        i++;
        continue;
      }
      if(ch === ","){ break; }
      buf += ch;
    }
    cn = buf;
  }
  var disp = (display !== undefined && display !== null && trimStr(display) !== "") ? trimStr(display) : r;
  return { dn: r, cn: cn, display: disp };
}

// --- fixlet_role_admin.ojo: function matchesRule (mirror of Resolve-Roles per-rule) ---
function matchesRule(rule, views){
  if(!rule){ return null; }

  var active = 1;
  if(rule.Active !== undefined && rule.Active !== null && String(rule.Active) !== ""){
    var av = parseInt(rule.Active, 10);
    active = isNaN(av) ? 1 : av;
  }
  if(active === 0){ return null; }

  var matchOn = "cn";
  if(rule.Match_On !== undefined && rule.Match_On !== null && trimStr(rule.Match_On) !== ""){
    matchOn = trimStr(rule.Match_On).toLowerCase();
  }
  if(matchOn !== "cn" && matchOn !== "display" && matchOn !== "dn"){ return null; }

  var view = "";
  if(views && views[matchOn] !== undefined && views[matchOn] !== null){ view = String(views[matchOn]); }
  if(trimStr(view) === ""){ return null; }

  var pattern = (rule.Pattern === undefined || rule.Pattern === null) ? "" : String(rule.Pattern);
  if(pattern === ""){ return null; }

  var isMatch = false;
  if(pattern.charAt(pattern.length - 1) === "*"){
    var prefix = pattern.substring(0, pattern.length - 1).toLowerCase();
    isMatch = view.toLowerCase().indexOf(prefix) === 0;
  } else {
    isMatch = view.toLowerCase() === pattern.toLowerCase();
  }
  if(!isMatch){ return null; }

  var priority = 100;
  if(rule.Priority !== undefined && rule.Priority !== null && trimStr(rule.Priority) !== ""){
    var p = parseInt(rule.Priority, 10);
    if(!isNaN(p)){ priority = p; }
  }

  return {
    Role:         (rule.Role === undefined || rule.Role === null) ? "" : String(rule.Role),
    GRMID:        (rule.GRMID !== undefined) ? rule.GRMID : null,
    Match_On:     matchOn,
    Matched_View: view,
    Priority:     priority
  };
}

// --- fixlet_role_admin.ojo: function resolveRolesJs ---
function resolveRolesJs(rules, views){
  var out = [];
  if(!rules){ return out; }
  for(var i = 0; i < rules.length; i++){
    var m = matchesRule(rules[i], views);
    if(m){ out.push(m); }
  }
  out.sort(function(a, b){ return a.Priority - b.Priority; });
  return out;
}

// --- fixlet_role_admin.ojo: function validateRuleRow ---
function validateRuleRow(rule, existingRules){
  var errors = [];
  var warnings = [];
  var allowed = { cn: true, display: true, dn: true };

  var pattern = (rule && rule.Pattern != null) ? String(rule.Pattern) : "";
  var role    = (rule && rule.Role != null) ? String(rule.Role) : "";
  var matchOn = (rule && rule.Match_On != null) ? String(rule.Match_On).toLowerCase() : "";

  if(trimStr(pattern) === ""){ errors.push("Pattern is blank"); }
  if(trimStr(role) === ""){ errors.push("Role is blank"); }
  if(!allowed[matchOn]){ errors.push("Match_On must be one of cn, display, dn"); }

  var star = pattern.indexOf("*");
  if(star >= 0 && star !== pattern.length - 1){
    errors.push("Asterisk is only allowed as the final character (suffix wildcard only)");
  }

  if(existingRules){
    for(var i = 0; i < existingRules.length; i++){
      var ex = existingRules[i];
      if(!ex){ continue; }
      if(String(ex.Pattern) === pattern &&
         String(ex.Match_On).toLowerCase() === matchOn &&
         String(ex.Role) === role){
        warnings.push("A rule with the same Pattern, Match_On and Role already exists");
        break;
      }
    }
  }
  return { errors: errors, warnings: warnings };
}

// ---------------------------------------------------------------------------
// Minimal IE9-style DOM stub for switchTab
// ---------------------------------------------------------------------------
function makeEl(){ return { style: { display: "" }, className: "" }; }
function makeFakeDoc(ids){
  var store = {};
  for(var i = 0; i < ids.length; i++){
    store["tab" + ids[i]]    = makeEl();
    store["tabBtn" + ids[i]] = makeEl();
  }
  return { _store: store, getElementById: function(id){ return store[id] || null; } };
}
var TAB_IDS = ["GroupRoleMap","RolePublication","Region","ReferenceDB"];

// ---------------------------------------------------------------------------
// 2. switchTab
// ---------------------------------------------------------------------------
section("switchTab");

(function(){
  var t;
  for (t = 0; t < TAB_IDS.length; t++){
    (function(target){
      var doc = makeFakeDoc(TAB_IDS);
      global.document = doc;
      switchTab(target);
      expect("switchTab('" + target + "') shows exactly one panel", function(){
        var shown = 0, k;
        for (k = 0; k < TAB_IDS.length; k++){
          if (doc._store["tab" + TAB_IDS[k]].style.display === ""){ shown++; }
        }
        assert.strictEqual(shown, 1, "exactly one panel visible");
        assert.strictEqual(doc._store["tab" + target].style.display, "", "the target panel is the visible one");
      });
      expect("switchTab('" + target + "') marks exactly one button active", function(){
        var active = 0, k;
        for (k = 0; k < TAB_IDS.length; k++){
          if (doc._store["tabBtn" + TAB_IDS[k]].className === "tabBtn tabActive"){ active++; }
        }
        assert.strictEqual(active, 1, "exactly one button active");
        assert.strictEqual(doc._store["tabBtn" + target].className, "tabBtn tabActive");
      });
    })(TAB_IDS[t]);
  }

  expect("switchTab('Unknown') hides all panels and activates no button without throwing", function(){
    var doc = makeFakeDoc(TAB_IDS);
    global.document = doc;
    assert.doesNotThrow(function(){ switchTab("Unknown"); });
    var k, shown = 0, active = 0;
    for (k = 0; k < TAB_IDS.length; k++){
      if (doc._store["tab" + TAB_IDS[k]].style.display === ""){ shown++; }
      if (doc._store["tabBtn" + TAB_IDS[k]].className === "tabBtn tabActive"){ active++; }
    }
    assert.strictEqual(shown, 0, "no panel visible for an unknown id");
    assert.strictEqual(active, 0, "no button active for an unknown id");
  });
})();

// ---------------------------------------------------------------------------
// 3. GroupRoleMap row validation
// ---------------------------------------------------------------------------
section("GroupRoleMap row validation");

expect("validateRuleRow: blank Pattern is an error", function(){
  var v = validateRuleRow({ Pattern: "  ", Match_On: "cn", Role: "IT Ops" }, []);
  assert.ok(v.errors.length >= 1);
  assert.ok(v.errors.join(" ").indexOf("Pattern") >= 0);
});

expect("validateRuleRow: blank Role is an error", function(){
  var v = validateRuleRow({ Pattern: "ACME-Admins", Match_On: "cn", Role: "" }, []);
  assert.ok(v.errors.join(" ").indexOf("Role") >= 0);
});

expect("validateRuleRow: Match_On outside cn|display|dn is an error", function(){
  var v = validateRuleRow({ Pattern: "ACME-Admins", Match_On: "sid", Role: "IT Ops" }, []);
  assert.ok(v.errors.join(" ").indexOf("Match_On") >= 0);
});

expect("validateRuleRow: mid-string asterisk is an error", function(){
  var v = validateRuleRow({ Pattern: "ACME-*-Admins", Match_On: "cn", Role: "IT Ops" }, []);
  assert.ok(v.errors.join(" ").toLowerCase().indexOf("asterisk") >= 0);
});

expect("validateRuleRow: trailing asterisk is allowed (no asterisk error)", function(){
  var v = validateRuleRow({ Pattern: "ACME-*", Match_On: "cn", Role: "IT Ops" }, []);
  var hasStarErr = false, i;
  for (i = 0; i < v.errors.length; i++){ if (v.errors[i].toLowerCase().indexOf("asterisk") >= 0){ hasStarErr = true; } }
  assert.strictEqual(hasStarErr, false);
});

expect("validateRuleRow: a valid unique rule has no errors and no warnings", function(){
  var v = validateRuleRow({ Pattern: "ACME-Admins", Match_On: "cn", Role: "IT Ops" }, [
    { Pattern: "OTHER", Match_On: "dn", Role: "HR" }
  ]);
  assert.deepStrictEqual(v.errors, []);
  assert.deepStrictEqual(v.warnings, []);
});

expect("validateRuleRow: a duplicate Pattern+Match_On+Role is a WARNING, not an error", function(){
  var existing = [{ Pattern: "ACME-Admins", Match_On: "cn", Role: "IT Ops" }];
  var v = validateRuleRow({ Pattern: "ACME-Admins", Match_On: "cn", Role: "IT Ops" }, existing);
  assert.strictEqual(v.errors.length, 0, "duplicate must not block");
  assert.ok(v.warnings.length >= 1, "duplicate must warn");
});

// ---------------------------------------------------------------------------
// 4. Test Pattern matcher  (mirror of AxoniousParse.psm1 Resolve-Roles)
// ---------------------------------------------------------------------------
section("Test Pattern matcher");

var V_DN = deriveViews("CN=ACME-Admins,OU=Groups,DC=office,DC=bzn", "");

expect("matcher 1/8: exact match is case-insensitive", function(){
  var m = matchesRule({ Pattern: "acme-admins", Match_On: "cn", Role: "IT Ops" }, V_DN);
  assert.ok(m && m.Role === "IT Ops");
});

expect("matcher 2/8: a non-matching exact pattern does not fire", function(){
  var m = matchesRule({ Pattern: "acme-users", Match_On: "cn", Role: "IT Ops" }, V_DN);
  assert.strictEqual(m, null);
});

expect("matcher 3/8: a trailing-* pattern matches on prefix", function(){
  var m = matchesRule({ Pattern: "ACME-*", Match_On: "cn", Role: "IT Ops" }, V_DN);
  assert.ok(m && m.Match_On === "cn");
});

expect("matcher 4/8: a trailing-* pattern does NOT match a string shorter than the prefix", function(){
  var views = deriveViews("ACME-", "");
  var m = matchesRule({ Pattern: "ACME-Admins*", Match_On: "cn", Role: "IT Ops" }, views);
  assert.strictEqual(m, null);
});

expect("matcher 5/8: a mid-string asterisk is treated as a literal (equality, not wildcard)", function(){
  var noMatch = matchesRule({ Pattern: "AC*ME", Match_On: "cn", Role: "IT Ops" }, deriveViews("ACME", ""));
  assert.strictEqual(noMatch, null, "'AC*ME' must not wildcard-match 'ACME'");
  var litMatch = matchesRule({ Pattern: "AC*ME", Match_On: "cn", Role: "IT Ops" }, deriveViews("ac*me", ""));
  assert.ok(litMatch, "'AC*ME' matches the literal 'ac*me' case-insensitively");
});

expect("matcher 6/8: Match_On selects the named view", function(){
  var mCn = matchesRule({ Pattern: "ACME-Admins", Match_On: "cn", Role: "IT Ops" }, V_DN);
  var mDn = matchesRule({ Pattern: "ACME-Admins", Match_On: "dn", Role: "IT Ops" }, V_DN);
  assert.ok(mCn, "cn view matches the RDN");
  assert.strictEqual(mDn, null, "dn view is the full DN, so an RDN-only pattern does not match it");
});

expect("matcher 7/8: an Active=0 rule never fires", function(){
  var m = matchesRule({ Pattern: "ACME-Admins", Match_On: "cn", Role: "IT Ops", Active: "0" }, V_DN);
  assert.strictEqual(m, null);
});

expect("matcher 8/8: two rules matching one group both fire; Priority orders but does not suppress", function(){
  var rules = [
    { GRMID: "1", Pattern: "ACME-Admins", Match_On: "cn", Role: "IT Ops",  Priority: "50" },
    { GRMID: "2", Pattern: "CN=ACME-Admins,OU=Groups,DC=office,DC=bzn", Match_On: "dn", Role: "DB Admin", Priority: "10" }
  ];
  var fired = resolveRolesJs(rules, V_DN);
  assert.strictEqual(fired.length, 2, "both rules apply");
  assert.strictEqual(fired[0].Priority, 10, "lower Priority sorts first");
  assert.strictEqual(fired[1].Priority, 50);
  assert.strictEqual(fired[0].Role, "DB Admin");
});

expect("matcher extra: Match_On defaults to cn when absent", function(){
  var m = matchesRule({ Pattern: "ACME-Admins", Role: "IT Ops" }, V_DN);
  assert.ok(m && m.Match_On === "cn");
});

expect("matcher extra: an unknown Match_On is skipped, not thrown", function(){
  assert.doesNotThrow(function(){
    var m = matchesRule({ Pattern: "ACME-Admins", Match_On: "objectGUID", Role: "IT Ops" }, V_DN);
    assert.strictEqual(m, null);
  });
});

expect("matcher extra: a blank named view is skipped", function(){
  var m = matchesRule({ Pattern: "anything", Match_On: "display", Role: "IT Ops" }, deriveViews("CN=X,OU=Y", ""));
  // display falls back to the raw DN "CN=X,OU=Y" here, so use a truly blank case:
  var m2 = matchesRule({ Pattern: "anything", Match_On: "display", Role: "IT Ops" }, { cn: "X", dn: "CN=X", display: "" });
  assert.strictEqual(m2, null);
});

// -- deriveViews (DN -> CN derivation, incl. escaped comma) --
section("deriveViews");

expect("deriveViews: a DN yields the first CN RDN as cn, the raw string as dn", function(){
  var v = deriveViews("CN=BNX-M365-E3,OU=Groups,DC=office,DC=bzn", "");
  assert.strictEqual(v.cn, "BNX-M365-E3");
  assert.strictEqual(v.dn, "CN=BNX-M365-E3,OU=Groups,DC=office,DC=bzn");
});

expect("deriveViews: a backslash-escaped comma inside the RDN is kept in cn", function(){
  var v = deriveViews("CN=Smith\\, John,OU=People,DC=office,DC=bzn", "");
  assert.strictEqual(v.cn, "Smith, John");
});

expect("deriveViews: a plain display name is its own cn (not a DN)", function(){
  var v = deriveViews("All Tenant Members", "");
  assert.strictEqual(v.cn, "All Tenant Members");
  assert.strictEqual(v.dn, "All Tenant Members");
});

expect("deriveViews: a supplied display name overrides the raw value for the display view", function(){
  var v = deriveViews("CN=grp1,OU=x", "Group One");
  assert.strictEqual(v.display, "Group One");
  assert.strictEqual(v.cn, "grp1");
});

// ---------------------------------------------------------------------------
// 5. base64 chunk chain
// ---------------------------------------------------------------------------
section("base64 chunk chain");

expect("base64 chunk chain: a >3000-char payload round-trips into the expected number of chunks", function(){
  var payload = new Array(5001).join("A"); // 5000 chars
  var b64 = safeB64Encode(payload);
  assert.strictEqual(b64.length, Math.ceil(5000 / 3) * 4, "base64 length is deterministic");
  var chunks = chunkString(b64, CHUNK_SIZE);
  var expected = Math.ceil(b64.length / CHUNK_SIZE);
  assert.strictEqual(chunks.length, expected, "chunk count = ceil(b64Len / 3000)");
  assert.ok(chunks.length >= 3, "a 5000-char payload spans at least 3 chunks");
  var params = buildChunkParams(b64);
  assert.ok(params.indexOf('parameter "chunkCount"="' + expected + '"') >= 0);
  var reassembled = chunks.join("");
  assert.strictEqual(reassembled, b64, "chunks concatenate back to the base64 string");
  var decoded = Buffer.from(reassembled, "base64").toString("utf8");
  assert.strictEqual(decoded, payload, "decode of the reassembled chunks equals the original payload");
});

expect("base64 chunk chain: a short payload is a single chunk with chunkCount=1", function(){
  var params = buildChunkParams(safeB64Encode("small"));
  assert.ok(params.indexOf('parameter "chunkCount"="1"') >= 0);
});

// ---------------------------------------------------------------------------
// 6. htmlEscape
// ---------------------------------------------------------------------------
section("htmlEscape");

expect("htmlEscape: neutralises a script-tag payload", function(){
  var out = htmlEscape('<script>alert("xss")</script>');
  assert.ok(out.indexOf("<script>") < 0);
  assert.ok(out.indexOf("&lt;script&gt;") >= 0);
  assert.ok(out.indexOf("&quot;") >= 0);
});

expect("htmlEscape: leaves a safe string untouched", function(){
  assert.strictEqual(htmlEscape("ACME-Admins"), "ACME-Admins");
});

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
