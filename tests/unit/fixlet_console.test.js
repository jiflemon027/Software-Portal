/**
 * fixlet_console.test.js
 *
 * Unit tests for the pure JavaScript functions backing the new unified
 * dashboard:
 *   Existing Dashboards/fixlet_console.ojo
 *
 * fixlet_console.ojo merges the catalog/search/filter grid pattern (from
 * fixlet_dispatcher.ojo / fixlet_modifier.ojo), the deploy engine (from
 * fixlet_dispatcher.ojo), the edit engine (from fixlet_modifier.ojo), and
 * the version-comparison scan engine (from fixlet_update_tracker.ojo) --
 * those ported functions are already covered by dispatcher.test.js,
 * modifier.test.js, and update_tracker.test.js respectively, and are
 * verbatim/near-verbatim here, so this file focuses on what's actually NEW:
 *
 *   1. rolesSetEqual(a, b) -- set-equality comparison for pipe-delimited
 *      role strings, order-independent.
 *   2. buildOpenOffersRows(rawData, allItems, site) -- site filter, JSON
 *      parse of the SmartRole_Source MIME field, catalog join by fixlet id,
 *      and category/role drift flagging for the "Open Offers" tab.
 *   3. mapCatalogItemsForScan(items) -- adapter from the catalog's row shape
 *      to the shape buildScanResults() (ported from update_tracker) expects.
 *
 * Running: node tests/unit/fixlet_console.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 *
 * Note: loadOpenOffers(), loadAllFixlets(), deployFixlet(), saveFixlet(),
 * copyNextItem(), etc. are NOT tested here because they call
 * EvaluateRelevance() / API.Get|Post|Put() / ActiveXObject, none of which
 * exist in Node.js -- same omission pattern as the other *.test.js files in
 * this directory.
 */

"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from fixlet_console.ojo)
// ---------------------------------------------------------------------------

function rolesSetEqual(a, b){
  var pa = String(a || "").split("|").map(function(s){ return s.replace(/^\s+|\s+$/g, ""); }).filter(function(s){ return s !== ""; }).sort();
  var pb = String(b || "").split("|").map(function(s){ return s.replace(/^\s+|\s+$/g, ""); }).filter(function(s){ return s !== ""; }).sort();
  if(pa.length !== pb.length){ return false; }
  for(var i = 0; i < pa.length; i++){ if(pa[i] !== pb[i]){ return false; } }
  return true;
}

function buildOpenOffersRows(rawData, allItemsArg, siteArg){
  var byId = {};
  var i;
  for(i = 0; i < allItemsArg.length; i++){ byId[allItemsArg[i].id] = allItemsArg[i]; }

  var rows = [];
  var p, source, fixlet;
  for(i = 0; i < rawData.length; i++){
    p = String(rawData[i]).split("|||");
    source = null;
    try { source = JSON.parse(p[4] || ""); } catch(ex) { source = null; }
    if(!source || source.sitename !== siteArg){ continue; }

    fixlet = byId[source.id];
    rows.push({
      actionId:       p[0],
      actionName:     p[1],
      deployCategory: p[2] || "",
      deployRoles:    p[3] || "",
      targetGroup:    source.targetGroup || "",
      fixletId:       source.id || "",
      fixletFound:    !!fixlet,
      currentCategory: fixlet ? fixlet.category  : "",
      currentRoles:    fixlet ? fixlet.roleValue : "",
      categoryDiffers: fixlet ? (fixlet.category !== p[2]) : false,
      rolesDiffers:    fixlet ? !rolesSetEqual(fixlet.roleValue, p[3]) : false
    });
  }
  return rows;
}

function mapCatalogItemsForScan(items){
  var out = [], i;
  for(i = 0; i < items.length; i++){
    out.push({ id: items[i].id, name: items[i].name, category: items[i].category, roles: items[i].roleValue });
  }
  return out;
}

function flagDuplicateArrivals(arrivalRowsArg, catalogItemsArg){
  var existingNames = {}, i;
  for(i = 0; i < catalogItemsArg.length; i++){ existingNames[catalogItemsArg[i].name] = true; }
  var out = [];
  for(i = 0; i < arrivalRowsArg.length; i++){
    out.push({
      sourceId:           arrivalRowsArg[i].sourceId,
      sourceName:         arrivalRowsArg[i].sourceName,
      sourceSiteName:     arrivalRowsArg[i].sourceSiteName,
      sourceSiteType:     arrivalRowsArg[i].sourceSiteType,
      productKey:         arrivalRowsArg[i].productKey,
      suggestedCategory:  arrivalRowsArg[i].suggestedCategory,
      existsInTargetSite: !!existingNames[arrivalRowsArg[i].sourceName]
    });
  }
  return out;
}

function buildRepoRootRegistryRelevance(){
  return '(value "wwwRootFolder" of key "HKEY_LOCAL_MACHINE\\SOFTWARE\\Wow6432Node\\BigFix\\Enterprise Server" of registry) as string';
}

function buildPrecacheFileFoundRelevance(sha1, filename){
  var safeFile = String(filename).replace(/"/g, '""');
  var safeSha1 = String(sha1).toLowerCase().replace(/"/g, '""');
  return 'exists folder ((item 0 of it & concatenation "\\" of (item 1 of it; item 2 of it; item 3 of it; item 4 of it)) of (' +
    buildRepoRootRegistryRelevance() + ', "Uploads", "CustomRepository", "SoftwarePortal", "' + safeSha1 + '") as string) whose (exists files whose (name of it = "' + safeFile + '") of it)';
}

function buildPrecacheDoneRelevance(prefetchLines){
  if(!prefetchLines || prefetchLines.length === 0){ return ""; }
  var parts = [], i;
  for(i = 0; i < prefetchLines.length; i++){
    parts.push('(' + buildPrecacheFileFoundRelevance(prefetchLines[i].sha1, prefetchLines[i].filename) + ')');
  }
  return parts.join(' AND ');
}

function buildStagingGateRelevance(prefetchLines){
  var doneRel = buildPrecacheDoneRelevance(prefetchLines);
  return doneRel === "" ? "true" : ("not (" + doneRel + ")");
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

// --- 3.1 rolesSetEqual ---
section("rolesSetEqual");

expect("identical strings are equal", function(){
  assert.strictEqual(rolesSetEqual("IT Operations", "IT Operations"), true);
});
expect("same roles in different order are equal (order-independent)", function(){
  assert.strictEqual(rolesSetEqual("IT Operations|Business Operations", "Business Operations|IT Operations"), true);
});
expect("different role sets are not equal", function(){
  assert.strictEqual(rolesSetEqual("IT Operations", "Business Operations"), false);
});
expect("both empty are equal", function(){
  assert.strictEqual(rolesSetEqual("", ""), true);
});
expect("empty vs. non-empty are not equal", function(){
  assert.strictEqual(rolesSetEqual("", "IT Operations"), false);
});
expect("stray whitespace around a role does not cause a false mismatch", function(){
  assert.strictEqual(rolesSetEqual("IT Operations| Business Operations ", "Business Operations|IT Operations"), true);
});
expect("a trailing empty segment from a trailing pipe does not count as a role", function(){
  assert.strictEqual(rolesSetEqual("IT Operations|", "IT Operations"), true);
});
expect("duplicate-count differences ARE detected (not just set membership)", function(){
  // "A|A" has two segments post-split; "A" has one -- lengths differ, so not equal.
  assert.strictEqual(rolesSetEqual("A|A", "A"), false);
});

// --- 3.2 buildOpenOffersRows ---
section("buildOpenOffersRows");

var sampleCatalog = [
  // Category is "Database Tools" (not the governed PORTAL_CONFIG value
  // "Database & Data Tools") because this mirrors the LIVE fixlet category
  // actually observed for id 807 on gpbfs.esm-technology.com, 2026-08-13 --
  // a real fixlet's Category is free text and isn't required to match the
  // configured list (see loadCategoryFilterOptions()'s comment in the .ojo).
  { id: "807", name: "Install: SQL Server Management Studio 20 v20.2.1 - Windows (x64)", category: "Database Tools", roleValue: "IT Operations" },
  { id: "818", name: "Install: Eclipse Temurin JDK with Hotspot v11.0.31.11 - Windows (x64)", category: "Java Runtime & JDK", roleValue: "IT Operations" },
  { id: "862", name: "Install: OpenOffice v4.1.16 - Windows", category: "Communication & Conferencing", roleValue: "Business Operations" }
];

// Real shape captured from gpbfs.esm-technology.com on 2026-08-13 via the
// live BigFix MCP query tool (see conversation) -- action 1849 matches the
// catalog's id 807 with an IDENTICAL category/roles (no drift); action 1798
// matches id 818 but with a DIFFERENT deploy-time category ("Developer
// Tools" vs. the catalog's "Java Runtime & JDK") -- confirmed real drift.
var sampleRaw = [
  '1849|||Install: SQL Server Management Studio 20 v20.2.1 - Windows (x64)|||Database Tools|||IT Operations|||{"id":"807","sitename":"Dereso Software Portal","targetGroup":"All Workstations"}',
  '1798|||Install: Eclipse Temurin JDK with Hotspot v11.0.31.11 - Windows (x64)|||Developer Tools|||IT Operations|||{"id":"818","sitename":"Dereso Software Portal","targetGroup":"All Workstations"}',
  '1803|||Install: Apache Tomcat 9 v9.0.117 - Windows (x64)|||Developer Tools||||||{"id":"861","sitename":"Dereso Software Portal","targetGroup":"All Workstations"}',
  '9999|||Install: Something Else - Windows|||Other Category|||Other Role|||{"id":"1","sitename":"A Totally Different Site","targetGroup":"Servers"}'
];

expect("rows from a different site are excluded entirely", function(){
  var rows = buildOpenOffersRows(sampleRaw, sampleCatalog, "Dereso Software Portal");
  for(var i = 0; i < rows.length; i++){
    assert.notStrictEqual(rows[i].actionId, "9999", "action 9999 belongs to a different site and must be filtered out");
  }
});
expect("3 of the 4 sample rows belong to the selected site", function(){
  var rows = buildOpenOffersRows(sampleRaw, sampleCatalog, "Dereso Software Portal");
  assert.strictEqual(rows.length, 3);
});
expect("matching category/roles is NOT flagged as differing (real no-drift case, action 1849)", function(){
  var rows = buildOpenOffersRows(sampleRaw, sampleCatalog, "Dereso Software Portal");
  var row  = rows.filter(function(r){ return r.actionId === "1849"; })[0];
  assert.ok(row, "action 1849 should be present");
  assert.strictEqual(row.fixletFound, true);
  assert.strictEqual(row.categoryDiffers, false);
  assert.strictEqual(row.rolesDiffers, false);
});
expect("a genuinely different deploy-time category IS flagged (real drift case, action 1798)", function(){
  var rows = buildOpenOffersRows(sampleRaw, sampleCatalog, "Dereso Software Portal");
  var row  = rows.filter(function(r){ return r.actionId === "1798"; })[0];
  assert.ok(row, "action 1798 should be present");
  assert.strictEqual(row.deployCategory, "Developer Tools");
  assert.strictEqual(row.currentCategory, "Java Runtime & JDK");
  assert.strictEqual(row.categoryDiffers, true);
  assert.strictEqual(row.rolesDiffers, false, "roles match ('IT Operations' both sides) and must not be flagged");
});
expect("an action whose fixlet id is not in the current catalog is marked fixletFound=false, not flagged as differing", function(){
  var rows = buildOpenOffersRows(sampleRaw, sampleCatalog, "Dereso Software Portal");
  var row  = rows.filter(function(r){ return r.actionId === "1803"; })[0];
  assert.ok(row, "action 1803 should be present");
  assert.strictEqual(row.fixletFound, false, "fixlet id 861 is not in sampleCatalog");
  assert.strictEqual(row.categoryDiffers, false, "cannot claim drift when there is nothing to compare against");
  assert.strictEqual(row.rolesDiffers, false);
});
expect("an empty deploy-time Associated_Roles field (blank 4th segment) parses as empty string, not undefined", function(){
  var rows = buildOpenOffersRows(sampleRaw, sampleCatalog, "Dereso Software Portal");
  var row  = rows.filter(function(r){ return r.actionId === "1803"; })[0];
  assert.strictEqual(row.deployRoles, "");
});
expect("a malformed/missing SmartRole_Source JSON is skipped rather than throwing", function(){
  var badRaw = ['1|||Some Action|||Cat|||Role|||NOT VALID JSON'];
  var rows = buildOpenOffersRows(badRaw, sampleCatalog, "Dereso Software Portal");
  assert.strictEqual(rows.length, 0);
});
expect("targetGroup is read through from the SmartRole_Source JSON", function(){
  var rows = buildOpenOffersRows(sampleRaw, sampleCatalog, "Dereso Software Portal");
  var row  = rows.filter(function(r){ return r.actionId === "1849"; })[0];
  assert.strictEqual(row.targetGroup, "All Workstations");
});
expect("no site selected (empty catalog/raw) yields no rows", function(){
  var rows = buildOpenOffersRows([], [], "Dereso Software Portal");
  assert.deepStrictEqual(rows, []);
});

// --- 3.3 mapCatalogItemsForScan ---
section("mapCatalogItemsForScan");

expect("maps catalog row shape to the {id,name,category,roles} shape buildScanResults expects", function(){
  var catalogRows = [
    { id: "1", name: "Foo v1.0", category: "Developer Tools", roleValue: "IT Operations", siteName: "X", itemType: "fixlet", openDeployments: "0" }
  ];
  var mapped = mapCatalogItemsForScan(catalogRows);
  assert.deepStrictEqual(mapped, [
    { id: "1", name: "Foo v1.0", category: "Developer Tools", roles: "IT Operations" }
  ]);
});
expect("empty input yields empty output", function(){
  assert.deepStrictEqual(mapCatalogItemsForScan([]), []);
});

// --- 3.3b flagDuplicateArrivals (2026-08-16 ask) ---
section("flagDuplicateArrivals");

expect("flags an arrival whose sourceName exactly matches an existing catalog item's name", function(){
  var arrivals = [{ sourceId: "9", sourceName: "Foo Bar", sourceSiteName: "Src", sourceSiteType: "external", productKey: "Foo Bar", suggestedCategory: "Developer Tools" }];
  var catalog  = [{ id: "1", name: "Foo Bar", category: "Developer Tools", roleValue: "" }];
  var flagged  = flagDuplicateArrivals(arrivals, catalog);
  assert.strictEqual(flagged[0].existsInTargetSite, true);
});
expect("does NOT flag an arrival with no matching name in the catalog", function(){
  var arrivals = [{ sourceId: "9", sourceName: "Totally New App", sourceSiteName: "Src", sourceSiteType: "external", productKey: "Totally New App", suggestedCategory: "" }];
  var catalog  = [{ id: "1", name: "Foo Bar", category: "Developer Tools", roleValue: "" }];
  var flagged  = flagDuplicateArrivals(arrivals, catalog);
  assert.strictEqual(flagged[0].existsInTargetSite, false);
});
expect("match is case-sensitive (2026-08-16 ask: \"exact name match\")", function(){
  var arrivals = [{ sourceId: "9", sourceName: "foo bar", sourceSiteName: "Src", sourceSiteType: "external", productKey: "foo bar", suggestedCategory: "" }];
  var catalog  = [{ id: "1", name: "Foo Bar", category: "Developer Tools", roleValue: "" }];
  var flagged  = flagDuplicateArrivals(arrivals, catalog);
  assert.strictEqual(flagged[0].existsInTargetSite, false, "\"foo bar\" must not match \"Foo Bar\" -- exact means exact");
});
expect("preserves every other field on the arrival row unchanged", function(){
  var arrivals = [{ sourceId: "9", sourceName: "Foo Bar", sourceSiteName: "Src", sourceSiteType: "external", productKey: "Foo Bar", suggestedCategory: "Developer Tools" }];
  var flagged  = flagDuplicateArrivals(arrivals, []);
  assert.strictEqual(flagged[0].sourceId, "9");
  assert.strictEqual(flagged[0].sourceSiteName, "Src");
  assert.strictEqual(flagged[0].sourceSiteType, "external");
  assert.strictEqual(flagged[0].productKey, "Foo Bar");
  assert.strictEqual(flagged[0].suggestedCategory, "Developer Tools");
  assert.strictEqual(flagged[0].existsInTargetSite, false);
});
expect("empty catalog or empty arrivals both handled without error", function(){
  assert.deepStrictEqual(flagDuplicateArrivals([], []), []);
  var flagged = flagDuplicateArrivals([{ sourceId: "1", sourceName: "X", sourceSiteName: "S", sourceSiteType: "external", productKey: "X", suggestedCategory: "" }], []);
  assert.strictEqual(flagged[0].existsInTargetSite, false);
});

// --- 3.4 buildRepoRootRegistryRelevance / buildPrecacheFileFoundRelevance / buildPrecacheDoneRelevance / buildStagingGateRelevance ---
section("staging action <Relevance> gate (2026-08-15 ask)");

expect("registry value + \"Uploads\\CustomRepository\\SoftwarePortal\" (the same suffix the path-join tuple appends) is byte-identical to this project's own proven 'Repository Root Path' Analysis property (not a fresh guess at the registry inspector syntax)", function(){
  var besPath = path.join(__dirname, "..", "..", "Dashboard_4_samples", "Dereso SWD Repository Cache.bes");
  var besSrc  = fs.readFileSync(besPath, "utf8");
  var m = /Name="Repository Root Path"[^>]*><!\[CDATA\[([\s\S]*?)\]\]><\/Property>/.exec(besSrc);
  assert.ok(m, "could not find the 'Repository Root Path' property in " + besPath);
  var reconstructed = buildRepoRootRegistryRelevance() + ' & "Uploads\\CustomRepository\\SoftwarePortal"';
  assert.strictEqual(reconstructed, m[1],
    "buildRepoRootRegistryRelevance() has drifted from the Analysis property it was copied from -- re-sync or update both intentionally");
});
expect("buildPrecacheFileFoundRelevance joins all 5 path segments (registry value, Uploads, CustomRepository, SoftwarePortal, sha1) -- not just the first 4", function(){
  var rel = buildPrecacheFileFoundRelevance("ABC123", "Setup.exe");
  assert.ok(rel.indexOf("item 4 of it") !== -1,
    "the folder-path join must include item 4 (the sha1 segment) or the resulting path stops one level short of the actual per-file cache folder");
  assert.ok(rel.indexOf('"abc123"') !== -1, "sha1 must be lowercased");
  assert.ok(rel.indexOf('"Setup.exe"') !== -1);
});
expect("a filename or sha1 containing a double-quote is escaped, not left to break the relevance string", function(){
  var rel = buildPrecacheFileFoundRelevance("abc", 'evil".exe');
  assert.ok(rel.indexOf('evil"".exe') !== -1, "expected the embedded quote to be doubled per BigFix relevance string-escaping rules: " + rel);
});
expect("buildPrecacheDoneRelevance AND-joins multiple prefetch lines (staging isn't done until every file has landed)", function(){
  var rel = buildPrecacheDoneRelevance([
    { filename: "A.exe", sha1: "AAA", size: "1", url: "http://x" },
    { filename: "B.msi", sha1: "BBB", size: "2", url: "http://y" }
  ]);
  var andCount = (rel.match(/ AND /g) || []).length;
  assert.strictEqual(andCount, 1, "two lines joined by exactly one AND");
  assert.ok(rel.indexOf('"A.exe"') !== -1 && rel.indexOf('"B.msi"') !== -1, rel);
});
expect("buildPrecacheDoneRelevance returns empty string for no prefetch lines", function(){
  assert.strictEqual(buildPrecacheDoneRelevance([]), "");
  assert.strictEqual(buildPrecacheDoneRelevance(null), "");
});
expect("buildStagingGateRelevance NEGATES the done-relevance -- action must stay relevant (need to run) while staging is incomplete, then auto-resolve to Fixed once every file exists, since this SingleAction carries no SuccessCriteria", function(){
  var lines = [{ filename: "Setup.exe", sha1: "ABC123", size: "10", url: "http://x" }];
  var gate = buildStagingGateRelevance(lines);
  var done = buildPrecacheDoneRelevance(lines);
  assert.strictEqual(gate, "not (" + done + ")");
});
expect("buildStagingGateRelevance falls back to \"true\" when called with no prefetch lines", function(){
  assert.strictEqual(buildStagingGateRelevance([]), "true");
});

// ---------------------------------------------------------------------------
// 4. STRUCTURAL ASSERTIONS AGAINST THE ACTUAL .ojo FILE
// ---------------------------------------------------------------------------

section("Structural: fixlet_console.ojo");

var consolePath = path.join(__dirname, "..", "..", "Existing Dashboards", "fixlet_console.ojo");
var consoleSrc   = fs.readFileSync(consolePath, "utf8");

expect("console file exists and is non-trivial in size", function(){
  assert.ok(consoleSrc.length > 50000, "fixlet_console.ojo looks suspiciously small: " + consoleSrc.length + " bytes");
});
expect("uses `source fixlet` NOWHERE for open-action lookups (confirmed non-existent relevance relationship for SingleActions, 2026-08-13)", function(){
  assert.ok(consoleSrc.indexOf("source fixlet of it") === -1,
    "SingleActions have no source-fixlet relevance link -- deployed offers must be joined via SmartRole_Source, not this");
});
expect("open-offers query reads SmartRole_Source, Associated_Roles, and offer category of it", function(){
  assert.ok(consoleSrc.indexOf('name of it="SmartRole_Source"') !== -1);
  assert.ok(consoleSrc.indexOf('name of it="Associated_Roles"') !== -1);
  assert.ok(consoleSrc.indexOf("offer category of it") !== -1);
});
expect("does NOT hardcode \"Dereso Software Portal\" into the deploy/copy path builders (must use the dynamic selectedSite/currentItem.siteName instead)", function(){
  // Deliberately scoped to the functions that write to a site, not to
  // PORTAL_CONFIG.defaultSiteName or comments, which legitimately mention it.
  var deployFn = consoleSrc.slice(consoleSrc.indexOf("function buildDeployXml"), consoleSrc.indexOf("function deployFixlet") );
  assert.ok(deployFn.indexOf('"Dereso Software Portal"') === -1,
    "buildDeployXml must not hardcode a site name -- it should always use currentItem.siteName");
});
expect("copyNextItem/copyArrival POST paths use the dynamic `selectedSite`, not a hardcoded site literal", function(){
  var copyFn = consoleSrc.slice(consoleSrc.indexOf("function copyNextItem"), consoleSrc.indexOf("function onCopyArrival"));
  assert.ok(copyFn.indexOf("encodeURIComponent(selectedSite)") !== -1,
    "Expected encodeURIComponent(selectedSite) in the copy engine");
  assert.ok(copyFn.indexOf('encodeURIComponent("Dereso Software Portal")') === -1,
    "Copy engine must not hardcode the Dereso Software Portal site name");
});
expect("does NOT contain the forbidden correlated open-deployments self-comparison (same regression guard as open_deployments.test.js)", function(){
  assert.ok(consoleSrc.indexOf("name of it = name of it") === -1);
});
expect("catalog grid uses a single radio-select (dispatcher-style), not the modifier's checkbox multi-select", function(){
  assert.ok(consoleSrc.indexOf('type="radio" name="fixSel"') !== -1);
  assert.ok(consoleSrc.indexOf("toggleFixletSelection") === -1,
    "Bulk multi-select was deliberately dropped from this console -- single-item Edit/Deploy/Update-check only");
});
expect("deleteFixlet() exists, confirms before deleting, and is wired to a button in the Edit sub-tab (2026-08-13 ask)", function(){
  assert.ok(consoleSrc.indexOf("function deleteFixlet()") !== -1);
  var fn = consoleSrc.slice(consoleSrc.indexOf("function deleteFixlet()"), consoleSrc.indexOf("function deleteFixlet()") + 800);
  assert.ok(fn.indexOf("confirm(") !== -1, "delete must be confirm()-gated -- it is irreversible");
  assert.ok(fn.indexOf("API.Delete(") !== -1);
  assert.ok(consoleSrc.indexOf('onclick="deleteFixlet()"') !== -1, "expected a Delete Fixlet button wired in the HTML");
});
expect("stopOffer() exists, confirms before stopping, and posts to the per-action REST stop endpoint (2026-08-13 ask)", function(){
  assert.ok(consoleSrc.indexOf("function stopOffer(") !== -1);
  var fn = consoleSrc.slice(consoleSrc.indexOf("function stopOffer("), consoleSrc.indexOf("function stopOffer(") + 800);
  assert.ok(fn.indexOf("confirm(") !== -1, "stop must be confirm()-gated -- it affects a live deployment");
  assert.ok(fn.indexOf('API.Post("action/"') !== -1, "expected the singular action/{id}/stop path, distinct from the plural actions/ collection POST used to create actions");
  assert.ok(fn.indexOf("/stop") !== -1);
});
expect("Open Offers rows render a Stop button wired to stopOffer(), so it's reachable from both the site-wide tab and the per-fixlet sub-tab", function(){
  assert.ok(consoleSrc.indexOf("stopOffer(actionId, actionName)") !== -1);
});
expect("the staging action does NOT embed a SuccessCriteria (2026-08-15: reverted after a live 400 -- matches fixlet_dispatcher.ojo's proven no-SuccessCriteria buildStagingActionXml verbatim); instead its own <Relevance> is wired to buildStagingGateRelevance(), the negated per-file precache check, so the action auto-resolves to Fixed once staging completes (2026-08-15 ask)", function(){
  var fn = consoleSrc.slice(consoleSrc.indexOf("function buildStagingActionXml"), consoleSrc.indexOf("function getActionScript"));
  assert.ok(fn.indexOf("SuccessCriteria") === -1,
    "SuccessCriteria was reverted 2026-08-15 after failing live with a 400 -- do not reintroduce it here without re-verifying against a real root server first");
  assert.ok(fn.indexOf("buildPrecacheSuccessRelevance") === -1);
  assert.ok(fn.indexOf("buildStagingGateRelevance(prefetchLines)") !== -1);
  assert.ok(fn.indexOf("<Relevance>true</Relevance>") === -1,
    "the staging action's Relevance must no longer be hardcoded true -- it needs to go false once staging completes for the default (no-SuccessCriteria) success detection to fire");
});
expect("New Arrivals are flagged for an exact-name duplicate against the target site's catalog and rendered in orange (2026-08-16 ask)", function(){
  assert.ok(consoleSrc.indexOf("arrivalRows = flagDuplicateArrivals(result.arrivals, allItems)") !== -1,
    "processScanResults() must run arrivals through flagDuplicateArrivals() before rendering");
  var renderFn = consoleSrc.slice(consoleSrc.indexOf("function renderArrivalsTable"), consoleSrc.indexOf("function toggleSelectAll"));
  assert.ok(renderFn.indexOf("item.existsInTargetSite") !== -1);
  assert.ok(renderFn.indexOf("dupFlag") !== -1, "expected the orange .dupFlag class to be used for a flagged arrival's name");
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
