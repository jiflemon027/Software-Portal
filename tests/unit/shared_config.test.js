/**
 * shared_config.test.js -- v1.0.0
 *
 * Unit tests for the shared-settings (dsp_config.json) code:
 *   scripts/shared/dsp_config_client.js  (copied into both dashboards)
 *   fixlet_role_manager.ojo parseSettingsForm / applyRoleList
 *   fixlet_console.ojo loadRoleValues (console-only "Invalidated")
 *
 * Running: node tests/unit/shared_config.test.js
 */
"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");

var ROOT = path.join(__dirname, "..", "..");
var SHARED_SRC = fs.readFileSync(path.join(ROOT, "scripts", "shared", "dsp_config_client.js"), "utf8").replace(/\r\n/g, "\n");
var CONSOLE_SRC = fs.readFileSync(path.join(ROOT, "Existing Dashboards", "fixlet_console.ojo"), "utf8").replace(/\r\n/g, "\n");
var RM_SRC = fs.readFileSync(path.join(ROOT, "Existing Dashboards", "fixlet_role_manager.ojo"), "utf8").replace(/\r\n/g, "\n");
var CONFIG_JSON = fs.readFileSync(path.join(ROOT, "config", "dsp_config.json"), "utf8");

var passed = 0, failures = 0;
function expect(label, fn){
  try { fn(); passed++; console.log("  ok: " + label); }
  catch(e){ failures++; console.log("  FAIL: " + label + "\n        " + (e && e.message ? e.message : e)); }
}
function section(name){ console.log("\n--- " + name + " ---"); }

function fnSource(src, name){
  var start = src.indexOf("function " + name + "(");
  assert.ok(start >= 0, name + " not found");
  var end = src.indexOf("\n}", start);
  return src.substring(start, end + 2);
}

// Shared module, evaluated exactly as shipped (API is never called by the pure helpers).
var S = new Function(SHARED_SRC + "\nreturn { dspNormalizeConfig: dspNormalizeConfig, dspParseConfigText: dspParseConfigText," +
  " dspFindFileIdInListing: dspFindFileIdInListing, dspMergeForSave: dspMergeForSave, dspSerializeConfig: dspSerializeConfig," +
  " dspConfigStatusText: dspConfigStatusText, DSP_ROLE_FORBIDDEN: DSP_ROLE_FORBIDDEN, dspTrim: dspTrim, DSP_CONFIG_FILE: DSP_CONFIG_FILE, DSP_CONFIG_SITE: DSP_CONFIG_SITE };")();

var DEFAULTS = {
  roles: ["IT Operations"],
  categories: ["Web Browser"],
  categoryMap: { "Firefox": "Web Browser" },
  console: { defaultSiteName: "Dereso Software Portal", sourceSites: ["Software Installer Library for Windows"], defaultExpirationDays: 7 }
};

section("both dashboards carry an identical copy of the shared block");

["fixlet_console.ojo", "fixlet_role_manager.ojo"].forEach(function(name){
  expect(name + " block matches scripts/shared/dsp_config_client.js", function(){
    var src = name === "fixlet_console.ojo" ? CONSOLE_SRC : RM_SRC;
    var b = src.indexOf("// BEGIN SHARED DSP_CONFIG_CLIENT\n"), e = src.indexOf("// END SHARED DSP_CONFIG_CLIENT");
    assert.ok(b >= 0 && e > b, "markers missing");
    var block = src.substring(b + "// BEGIN SHARED DSP_CONFIG_CLIENT\n".length, e).replace(/\s+$/, "");
    assert.strictEqual(block, SHARED_SRC.replace(/\s+$/, ""), "run: node scripts/sync_shared_config_client.js");
  });
});

expect("shared source is ASCII and contains nothing that breaks an .ojo wrapper", function(){
  assert.ok(!/[^\x00-\x7e]/.test(SHARED_SRC));
  ["]]>", "</script", "<?relevance"].forEach(function(bad){ assert.strictEqual(SHARED_SRC.toLowerCase().indexOf(bad), -1, bad); });
});

section("dspParseConfigText");

expect("parses a JSON object and strips a BOM", function(){
  var r = S.dspParseConfigText(String.fromCharCode(0xFEFF) + '{"roles":["A"]}');
  assert.strictEqual(r.error, "");
  assert.deepStrictEqual(r.obj.roles, ["A"]);
});
expect("reports invalid JSON, empty text and a non-object top level", function(){
  assert.ok(S.dspParseConfigText("{roles:").error.indexOf("not valid JSON") === 0);
  assert.strictEqual(S.dspParseConfigText("   ").error, "file is empty");
  assert.strictEqual(S.dspParseConfigText("[1,2]").error, "top level must be a JSON object");
});

section("dspNormalizeConfig");

expect("empty object -> exactly the defaults, no warnings", function(){
  var n = S.dspNormalizeConfig({}, DEFAULTS);
  assert.deepStrictEqual(n.config, DEFAULTS);
  assert.strictEqual(n.warnings.length, 0);
});
expect("trims, de-duplicates (case-insensitive) and drops blank roles", function(){
  var n = S.dspNormalizeConfig({ roles: [" IT Operations ", "it operations", "", "Finance"] }, DEFAULTS);
  assert.deepStrictEqual(n.config.roles, ["IT Operations", "Finance"]);
});
expect("rejects role names with forbidden characters, keeps the rest", function(){
  var n = S.dspNormalizeConfig({ roles: ["Ops, Europe", 'Say "hi"', "A|B", "Back\\slash", "Good"] }, DEFAULTS);
  assert.deepStrictEqual(n.config.roles, ["Good"]);
  assert.strictEqual(n.warnings.length, 4);
});
expect("non-list or all-invalid roles fall back to defaults with a warning", function(){
  assert.deepStrictEqual(S.dspNormalizeConfig({ roles: "IT" }, DEFAULTS).config.roles, ["IT Operations"]);
  var n = S.dspNormalizeConfig({ roles: ["", "  "] }, DEFAULTS);
  assert.deepStrictEqual(n.config.roles, ["IT Operations"]);
  assert.ok(n.warnings.length >= 1);
});
expect("categoryMap: bad type falls back; blank keys/values dropped", function(){
  assert.deepStrictEqual(S.dspNormalizeConfig({ categoryMap: ["x"] }, DEFAULTS).config.categoryMap, DEFAULTS.categoryMap);
  var n = S.dspNormalizeConfig({ categoryMap: { "VLC": "Media", "": "X", "Y": "", "Z": 3 } }, DEFAULTS);
  assert.deepStrictEqual(n.config.categoryMap, { "VLC": "Media" });
});
expect("console.defaultExpirationDays must be a whole number 1-365", function(){
  assert.strictEqual(S.dspNormalizeConfig({ console: { defaultExpirationDays: 14 } }, DEFAULTS).config.console.defaultExpirationDays, 14);
  [0, 400, 2.5, "7"].forEach(function(bad){
    var n = S.dspNormalizeConfig({ console: { defaultExpirationDays: bad } }, DEFAULTS);
    assert.strictEqual(n.config.console.defaultExpirationDays, 7, String(bad));
    assert.strictEqual(n.warnings.length, 1);
  });
});
expect("does not mutate the defaults object", function(){
  var n = S.dspNormalizeConfig({}, DEFAULTS);
  n.config.roles.push("X");
  n.config.console.sourceSites.push("Y");
  assert.deepStrictEqual(DEFAULTS.roles, ["IT Operations"]);
  assert.deepStrictEqual(DEFAULTS.console.sourceSites, ["Software Installer Library for Windows"]);
});

section("config/dsp_config.json (the file to upload)");

expect("is valid, normalizes with zero warnings, and matches fixlet_update_tracker.ojo's categories and suggestions", function(){
  var p = S.dspParseConfigText(CONFIG_JSON);
  assert.strictEqual(p.error, "");
  var n = S.dspNormalizeConfig(p.obj, DEFAULTS);
  assert.strictEqual(n.warnings.length, 0, n.warnings.join(" | "));
  assert.deepStrictEqual(n.config.roles, ["IT Operations", "Business Operations", "Database Administrators"]);
  assert.strictEqual(n.config.categories.length, 18);
  assert.strictEqual(Object.keys(n.config.categoryMap).length, 786);
  assert.strictEqual(p.obj.roles.indexOf("Invalidated"), -1, "Invalidated is console-only");
});

section("dspFindFileIdInListing");

var LISTING = '<BESAPI><SiteFile Resource="x"><Name>fixlet_console.ojo</Name><ID>47813</ID></SiteFile>' +
  '<SiteFile Resource="y"><Name>DSP_Config.JSON</Name><ID>47815</ID><IsClientFile>0</IsClientFile></SiteFile></BESAPI>';
expect("finds the file id by name, case-insensitively", function(){
  assert.strictEqual(S.dspFindFileIdInListing(LISTING, "dsp_config.json"), "47815");
});
expect("returns null when absent or on junk input", function(){
  assert.strictEqual(S.dspFindFileIdInListing(LISTING, "missing.json"), null);
  assert.strictEqual(S.dspFindFileIdInListing(null, "dsp_config.json"), null);
});

section("dspMergeForSave / dspSerializeConfig");

expect("keeps keys it did not edit (another dashboard's settings, comments)", function(){
  var out = S.dspMergeForSave({ configVersion: "1.0.0", _comment: "c", roles: ["A"], futureThing: { x: 1 } }, { roles: ["B"] });
  assert.deepStrictEqual(out, { configVersion: "1.0.0", _comment: "c", roles: ["B"], futureThing: { x: 1 } });
});
expect("serializes as indented JSON with a trailing newline that parses back", function(){
  var text = S.dspSerializeConfig({ roles: ["A"] });
  assert.strictEqual(text.charAt(text.length - 1), "\n");
  assert.deepStrictEqual(JSON.parse(text), { roles: ["A"] });
});

section("Role Manager parseSettingsForm");

var RM = new Function("DSP_ROLE_FORBIDDEN", "dspTrim",
  fnSource(RM_SRC, "linesToList") + "\n" + fnSource(RM_SRC, "categoryMapToText") + "\n" + fnSource(RM_SRC, "parseSettingsForm") +
  "\nreturn { parse: parseSettingsForm, mapText: categoryMapToText };")(S.DSP_ROLE_FORBIDDEN, S.dspTrim);

function form(over){
  var f = { roles: "IT Operations\r\nFinance\r\n", categories: "Web Browser\nMedia", categoryMap: "Firefox = Web Browser\nVLC = Media",
    defaultSiteName: "Dereso Software Portal", sourceSites: "Software Installer Library for Windows", defaultExpirationDays: "7" };
  for(var k in over){ f[k] = over[k]; }
  return f;
}

expect("valid form -> no errors, correct edited object", function(){
  var r = RM.parse(form({}), null);
  assert.deepStrictEqual(r.errors, []);
  assert.deepStrictEqual(r.edited.roles, ["IT Operations", "Finance"]);
  assert.deepStrictEqual(r.edited.categoryMap, { "Firefox": "Web Browser", "VLC": "Media" });
  assert.strictEqual(r.edited.console.defaultExpirationDays, 7);
});
expect("forbidden characters and duplicate roles are errors", function(){
  var r = RM.parse(form({ roles: "Ops, EU\nIT\nit" }), null);
  assert.strictEqual(r.errors.length, 2);
});
expect("empty roles/categories, bad expiry and empty site are errors", function(){
  var r = RM.parse(form({ roles: " ", categories: "", defaultExpirationDays: "0", defaultSiteName: "" }), null);
  assert.strictEqual(r.errors.length, 4);
});
expect("malformed suggestion line is an error; unknown category is only a warning", function(){
  var r = RM.parse(form({ categoryMap: "no equals sign\nPaint.NET = Graphics" }), null);
  assert.strictEqual(r.errors.length, 1);
  assert.strictEqual(r.warnings.length, 1);
});
expect("removing a role warns that its groups/tasks/actions are not deleted", function(){
  var r = RM.parse(form({ roles: "IT Operations" }), { roles: ["IT Operations", "Business Operations"] });
  assert.strictEqual(r.errors.length, 0);
  assert.ok(r.warnings.join(" ").indexOf("Business Operations") >= 0);
  assert.ok(r.warnings.join(" ").indexOf("NOT deleted") >= 0);
});
expect("categoryMapToText round-trips through the parser", function(){
  var map = { "VLC": "Media", "Firefox": "Web Browser" };
  var r = RM.parse(form({ categoryMap: RM.mapText(map) }), null);
  assert.deepStrictEqual(r.edited.categoryMap, map);
});

section("Console: Invalidated stays console-only");

expect("loadRoleValues puts Invalidated first and never duplicates it", function(){
  var ctx = new Function("CONSOLE_ONLY_ROLES", "PORTAL_CONFIG",
    "var roleValues = [];\n" + fnSource(CONSOLE_SRC, "loadRoleValues") + "\nloadRoleValues(); return roleValues;");
  assert.deepStrictEqual(ctx(["Invalidated"], { roles: ["IT Operations", "Invalidated", "Finance"] }), ["Invalidated", "IT Operations", "Finance"]);
});
expect("the console's built-in role list no longer contains Invalidated", function(){
  var m = /var PORTAL_CONFIG = \{[\s\S]*?roles: \[([\s\S]*?)\]/.exec(CONSOLE_SRC);
  assert.ok(m);
  assert.strictEqual(m[1].indexOf("Invalidated"), -1);
  assert.ok(CONSOLE_SRC.indexOf('var CONSOLE_ONLY_ROLES = ["Invalidated"];') >= 0);
});

section("UI wiring and versions");

expect("console v1.2.1 has a Reload config button and loads settings before init", function(){
  assert.ok(CONSOLE_SRC.indexOf('<div class="dashboardVersion">v1.2.1</div>') >= 0);
  assert.ok(CONSOLE_SRC.indexOf('onclick="onReloadConfigClick()"') >= 0);
  assert.ok(/function initDashboard\(\)\{[\s\S]*?dspLoadConfig\(CONSOLE_CONFIG_DEFAULTS, go\)/.test(CONSOLE_SRC));
});
expect("role manager v2.12.1 has the Settings tab, Generate JSON and Reload wiring, and never writes the site file", function(){
  assert.ok(RM_SRC.indexOf('<div class="dashboardVersion">v2.12.1</div>') >= 0);
  assert.ok(RM_SRC.indexOf('var ids = ["Roles","Analysis","Settings"];') >= 0);
  assert.ok(RM_SRC.indexOf('id="tabSettings"') >= 0 && RM_SRC.indexOf('onclick="onSettingsGenerateClick()"') >= 0);
  assert.strictEqual(RM_SRC.indexOf('onSettingsSaveClick'), -1);
  assert.strictEqual(SHARED_SRC.indexOf('API.Put('), -1, "the shared block must never write the site file");
  assert.strictEqual(SHARED_SRC.indexOf('dspSaveConfig'), -1);
  assert.ok(RM_SRC.indexOf('onclick="onReloadConfigClick()"') >= 0);
  assert.ok(/function initDashboard\(\)\{[\s\S]*?dspLoadConfig\(RM_CONFIG_DEFAULTS, go\)/.test(RM_SRC));
});

console.log("\n========================================");
console.log("Results: " + passed + " passed, " + failures + " failed");
console.log("========================================");
process.exit(failures > 0 ? 1 : 0);
