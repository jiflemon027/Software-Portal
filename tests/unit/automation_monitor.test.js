/**
 * automation_monitor.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_automation_monitor.ojo   (built in 07-04)
 *
 * The monitor is CONTENT-PIPELINE ONLY (D-24): it has no role controls. That is
 * enforced by a grep assertion in the plan, not here; these tests cover the pure
 * render/model helpers:
 *
 *   switchTab                  - IE9 tab-panel show/hide over the four content tabs
 *   badgeCounts                - per-stage ContentItem counts
 *   queueRowModel              - which stages are actionable / read-only
 *   cacheRowModel/countUnverified - verified = 0 -> error class + separate count
 *   buildPipelineConfigOps + base64 chunk chain - the config-write payload
 *   htmlEscape                 - XSS-safe encoding of a hostile filename
 *
 * Running: node tests/unit/automation_monitor.test.js
 * Requirements: Node.js built-in `assert` only (no external packages).
 */

"use strict";

var assert = require("assert");

// ---------------------------------------------------------------------------
// TEST INFRASTRUCTURE (verbatim from role_assigner.test.js / role_admin.test.js)
// ---------------------------------------------------------------------------
var passed   = 0;
var failures = 0;
function expect(label, fn){
  try{ fn(); passed++; }
  catch(e){ failures++; console.error("  FAIL: " + label); console.error("        " + (e.message || String(e))); }
}
function section(name){ console.log("\n--- Testing " + name + " ---"); }

// ---------------------------------------------------------------------------
// EXTRACTED FUNCTION IMPLEMENTATIONS
// Copied VERBATIM from Existing Dashboards/fixlet_automation_monitor.ojo with the
// source marker noted.
// ---------------------------------------------------------------------------

// --- fixlet_automation_monitor.ojo: CONTENT_STAGES / PRE_READY_STAGES ---
var CONTENT_STAGES   = ["discovered", "staged", "categorized", "ready", "live", "rejected"];
var PRE_READY_STAGES = ["discovered", "staged", "categorized"];

// --- fixlet_automation_monitor.ojo: function htmlEscape ---
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}

// --- fixlet_automation_monitor.ojo: btoa polyfill + base64 chunk chain ---
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
function safeB64Encode(str) { return btoa(unescape(encodeURIComponent(str))); }
function chunkString(s, size) {
  var chunks = [];
  for (var i = 0; i < s.length; i += size) { chunks.push(s.slice(i, i + size)); }
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

// --- fixlet_automation_monitor.ojo: PORTAL_CONFIG.sensitiveKeys (subset needed) ---
var PORTAL_CONFIG = { sensitiveKeys: ["AKeylessSecretPath", "AKeylessTokenFile"] };

// --- fixlet_automation_monitor.ojo: function switchTab ---
function switchTab(tab){
  var ids = ["Status","ContentQueue","RepositoryCache","Config"];
  var i, panel, btn;
  for(i=0;i<ids.length;i++){
    panel = document.getElementById("tab"+ids[i]);
    btn   = document.getElementById("tabBtn"+ids[i]);
    if(panel){ panel.style.display = (ids[i]===tab) ? "" : "none"; }
    if(btn){ btn.className = (ids[i]===tab) ? "tabBtn tabActive" : "tabBtn"; }
  }
}

// --- fixlet_automation_monitor.ojo: function badgeCounts ---
function badgeCounts(items){
  var counts = {};
  var i;
  for(i = 0; i < CONTENT_STAGES.length; i++){ counts[CONTENT_STAGES[i]] = 0; }
  if(!items){ return counts; }
  for(i = 0; i < items.length; i++){
    var st = (items[i] && items[i].stage != null) ? String(items[i].stage) : "";
    if(counts[st] === undefined){ counts[st] = 0; }
    counts[st]++;
  }
  return counts;
}

// --- fixlet_automation_monitor.ojo: function isActionableStage / queueRowModel ---
function isActionableStage(stage){
  var s = String(stage);
  var i;
  for(i = 0; i < PRE_READY_STAGES.length; i++){ if(PRE_READY_STAGES[i] === s){ return true; } }
  return false;
}
function queueRowModel(item){
  var stage = (item && item.stage != null) ? String(item.stage) : "";
  return {
    stage:      stage,
    actionable: isActionableStage(stage),
    readOnly:   (stage === "live"),
    className:  (stage === "rejected") ? "error-row" : (stage === "live" ? "dim" : "")
  };
}

// --- fixlet_automation_monitor.ojo: function cacheRowModel / countUnverified ---
function cacheRowModel(row){
  var v = (row && row.verified != null) ? String(row.verified) : "";
  var unverified = (v === "0");
  return { unverified: unverified, className: unverified ? "error-row" : "" };
}
function countUnverified(rows){
  var n = 0, i;
  if(!rows){ return 0; }
  for(i = 0; i < rows.length; i++){ if(cacheRowModel(rows[i]).unverified){ n++; } }
  return n;
}

// --- fixlet_automation_monitor.ojo: function buildPipelineConfigOps / buildConfigWriteChunkParams ---
function buildPipelineConfigOps(formValues){
  var ops = [];
  for(var k in formValues){
    if(formValues.hasOwnProperty(k)){
      ops.push({
        table:     "PipelineConfig",
        key:       String(k),
        value:     String(formValues[k]),
        sensitive: (PORTAL_CONFIG.sensitiveKeys.indexOf(String(k)) >= 0)
      });
    }
  }
  return ops;
}
function buildConfigWriteChunkParams(ops){
  return buildChunkParams(safeB64Encode(JSON.stringify(ops)));
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
var TAB_IDS = ["Status","ContentQueue","RepositoryCache","Config"];

// ---------------------------------------------------------------------------
// 1. switchTab
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
        assert.strictEqual(shown, 1);
        assert.strictEqual(doc._store["tab" + target].style.display, "");
      });
      expect("switchTab('" + target + "') marks exactly one button active", function(){
        var active = 0, k;
        for (k = 0; k < TAB_IDS.length; k++){
          if (doc._store["tabBtn" + TAB_IDS[k]].className === "tabBtn tabActive"){ active++; }
        }
        assert.strictEqual(active, 1);
        assert.strictEqual(doc._store["tabBtn" + target].className, "tabBtn tabActive");
      });
    })(TAB_IDS[t]);
  }
  expect("switchTab('Nope') hides all panels and activates no button, no throw", function(){
    var doc = makeFakeDoc(TAB_IDS);
    global.document = doc;
    assert.doesNotThrow(function(){ switchTab("Nope"); });
    var k, shown = 0, active = 0;
    for (k = 0; k < TAB_IDS.length; k++){
      if (doc._store["tab" + TAB_IDS[k]].style.display === ""){ shown++; }
      if (doc._store["tabBtn" + TAB_IDS[k]].className === "tabBtn tabActive"){ active++; }
    }
    assert.strictEqual(shown, 0);
    assert.strictEqual(active, 0);
  });
})();

// ---------------------------------------------------------------------------
// 2. badgeCounts
// ---------------------------------------------------------------------------
section("badgeCounts");

expect("badgeCounts: mixed ContentItem array yields the right per-stage counts", function(){
  var items = [
    { stage: "discovered" }, { stage: "discovered" }, { stage: "staged" },
    { stage: "ready" }, { stage: "live" }, { stage: "live" }, { stage: "rejected" }
  ];
  var c = badgeCounts(items);
  assert.strictEqual(c.discovered, 2);
  assert.strictEqual(c.staged, 1);
  assert.strictEqual(c.categorized, 0);
  assert.strictEqual(c.ready, 1);
  assert.strictEqual(c.live, 2);
  assert.strictEqual(c.rejected, 1);
});

expect("badgeCounts: an empty array is zero for every known stage", function(){
  var c = badgeCounts([]);
  var i;
  for (i = 0; i < CONTENT_STAGES.length; i++){
    assert.strictEqual(c[CONTENT_STAGES[i]], 0, CONTENT_STAGES[i] + " must be 0");
  }
});

// ---------------------------------------------------------------------------
// 3. queueRowModel  (pre-ready = actionable; live = read-only, no Approve)
// ---------------------------------------------------------------------------
section("queueRowModel");

expect("queueRowModel: discovered / staged / categorized rows are actionable", function(){
  assert.strictEqual(queueRowModel({ stage: "discovered" }).actionable, true);
  assert.strictEqual(queueRowModel({ stage: "staged" }).actionable, true);
  assert.strictEqual(queueRowModel({ stage: "categorized" }).actionable, true);
});

expect("queueRowModel: a 'live' row is read-only and exposes NO Approve control", function(){
  var m = queueRowModel({ stage: "live" });
  assert.strictEqual(m.actionable, false, "live must not be actionable -> renderer emits no Approve/Reject");
  assert.strictEqual(m.readOnly, true);
});

expect("queueRowModel: 'ready' and 'rejected' rows are not actionable", function(){
  assert.strictEqual(queueRowModel({ stage: "ready" }).actionable, false);
  assert.strictEqual(queueRowModel({ stage: "rejected" }).actionable, false);
  assert.strictEqual(queueRowModel({ stage: "rejected" }).className, "error-row");
});

// ---------------------------------------------------------------------------
// 4. cacheRowModel / countUnverified  (verified = 0 -> error class + own count)
// ---------------------------------------------------------------------------
section("cacheRowModel / countUnverified");

expect("cacheRowModel: verified = 0 gets the error class and is flagged unverified", function(){
  var m = cacheRowModel({ verified: "0" });
  assert.strictEqual(m.unverified, true);
  assert.strictEqual(m.className, "error-row");
});

expect("cacheRowModel: verified = 1 has no error class", function(){
  var m = cacheRowModel({ verified: "1" });
  assert.strictEqual(m.unverified, false);
  assert.strictEqual(m.className, "");
});

expect("countUnverified: counts only the verified = 0 rows, separately from the total", function(){
  var rows = [
    { verified: "1" }, { verified: "0" }, { verified: "1" }, { verified: "0" }, { verified: "0" }
  ];
  assert.strictEqual(countUnverified(rows), 3);
  assert.strictEqual(rows.length, 5, "total is unchanged");
  assert.strictEqual(countUnverified([]), 0);
});

// ---------------------------------------------------------------------------
// 5. config-write payload builder + base64 chunk chain
// ---------------------------------------------------------------------------
section("buildPipelineConfigOps + base64 chunk chain");

expect("buildPipelineConfigOps: produces one PipelineConfig op per key with the expected value", function(){
  var ops = buildPipelineConfigOps({ MaxExportAgeDays: "2", ContentSourceSites: "SiteA" });
  assert.strictEqual(ops.length, 2);
  var byKey = {};
  var i;
  for (i = 0; i < ops.length; i++){ byKey[ops[i].key] = ops[i]; }
  assert.strictEqual(byKey.MaxExportAgeDays.table, "PipelineConfig");
  assert.strictEqual(byKey.MaxExportAgeDays.value, "2");
  assert.strictEqual(byKey.ContentSourceSites.value, "SiteA");
});

expect("buildPipelineConfigOps: flags AKeyless path keys as sensitive (path, never secret)", function(){
  var ops = buildPipelineConfigOps({ AKeylessSecretPath: "/gpc/infra/x", MaxItems: "50" });
  var byKey = {};
  var i;
  for (i = 0; i < ops.length; i++){ byKey[ops[i].key] = ops[i]; }
  assert.strictEqual(byKey.AKeylessSecretPath.sensitive, true);
  assert.strictEqual(byKey.MaxItems.sensitive, false);
});

expect("config-write payload passes through the base64 chunk chain and round-trips (payload > 3000 chars)", function(){
  var big = {};
  var i;
  for (i = 0; i < 200; i++){ big["Key" + i] = new Array(31).join("v"); } // ~200 * ~40 chars JSON
  var ops = buildPipelineConfigOps(big);
  var payload = JSON.stringify(ops);
  assert.ok(payload.length > 3000, "test payload must exceed one chunk");
  var params = buildConfigWriteChunkParams(ops);
  var b64 = safeB64Encode(payload);
  var expected = Math.ceil(b64.length / CHUNK_SIZE);
  assert.ok(params.indexOf('parameter "chunkCount"="' + expected + '"') >= 0, "chunkCount line matches ceil(b64Len/3000)");
  var chunks = chunkString(b64, CHUNK_SIZE);
  assert.strictEqual(chunks.length, expected);
  var decoded = Buffer.from(chunks.join(""), "base64").toString("utf8");
  assert.strictEqual(decoded, payload, "reassembled chunks decode back to the JSON payload");
  assert.deepStrictEqual(JSON.parse(decoded), ops, "and parse back to the op list");
});

// ---------------------------------------------------------------------------
// 6. htmlEscape  (hostile filename in the Repository Cache table)
// ---------------------------------------------------------------------------
section("htmlEscape");

expect("htmlEscape: neutralises a script-tag payload in a filename", function(){
  var out = htmlEscape('evil<script>alert("x")</script>.msi');
  assert.ok(out.indexOf("<script>") < 0);
  assert.ok(out.indexOf("&lt;script&gt;") >= 0);
});

expect("htmlEscape: leaves an ordinary filename untouched", function(){
  assert.strictEqual(htmlEscape("7-Zip-x64.msi"), "7-Zip-x64.msi");
});

// ---------------------------------------------------------------------------
// SUMMARY FOOTER (verbatim from role_admin.test.js)
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
