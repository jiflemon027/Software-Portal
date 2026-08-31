/**
 * automation.integration.test.js
 *
 * Integration tests for the Phase 7 automation pipeline — fixtures, run-book and the
 * scheduled-task exports (always-on), plus BigFix REST round-trips (gated).
 *
 * WARNING: GROUP B talks to a live BigFix server. Run it against STAGING only.
 *
 * Required environment variables for GROUP B (all absent by default → GROUP B skips):
 *   BIGFIX_URL   -- Base URL of the BigFix REST API, e.g. https://bigfix.example.com:52311
 *   BIGFIX_USER  -- BigFix operator username
 *   BIGFIX_TOKEN -- BigFix operator password (Basic auth credential)
 *
 * Optional (GROUP B):
 *   TEST_TARGET_SITE      -- portal custom site name (default: "Dereso Software Portal")
 *   TEST_PILOT_REGION     -- a published region whose snapshot URL to SHA1-check (default: "AAG-UK")
 *   BIGFIX_SNAPSHOT_BASE  -- override the roleref base URL for the SHA1 round-trip
 *                            (default: BIGFIX_URL + "/Uploads/CustomRepository/SoftwarePortal/roleref")
 *
 * Usage:   node tests/integration/automation.integration.test.js
 * Exit:    0 = all executed tests passed (or skipped gracefully); 1 = a failure.
 *
 * Test groups:
 *   GROUP A -- fixture / run-book / task-XML structure. Always runs, no BigFix needed.
 *   GROUP B -- BIGFIX-gated REST round-trips. Skipped when BIGFIX_* are absent.
 *
 * Security note: BIGFIX_TOKEN is never logged. It is sent only as a Basic auth header
 * over HTTPS with rejectUnauthorized:true. For a self-signed cert set
 * BIGFIX_CA_CERT=/path/to/ca.crt. Do NOT set NODE_TLS_REJECT_UNAUTHORIZED=0.
 */

"use strict";

var fs    = require("fs");
var path  = require("path");
var https = require("https");
var crypto = require("crypto");

var REPO = path.join(__dirname, "..", "..");

// =============================================================================
// SECTION 1 -- tiny test runner
// =============================================================================

var passed = 0, failed = 0, skipped = 0;
var failures = [];

function assert(cond, msg) {
  if (!cond) { var e = new Error("Assertion failed: " + msg); e.isAssertionError = true; throw e; }
}
function skip(reason) { var e = new Error(reason); e.isSkip = true; throw e; }

function runTest(name, fn) {
  try {
    fn();
    console.log("  PASS: " + name);
    passed++;
  } catch (ex) {
    if (ex.isSkip) { console.log("  SKIP: " + name + " -- " + ex.message); skipped++; }
    else {
      console.log("  FAIL: " + name);
      console.log("        " + (ex.message || String(ex)));
      failed++;
      failures.push({ name: name, message: ex.message || String(ex) });
    }
  }
}
function runAsyncTest(name, fn) {
  return new Promise(function (resolve) {
    fn(function (err) {
      if (err && err.isSkip) { console.log("  SKIP: " + name + " -- " + err.message); skipped++; }
      else if (err) {
        console.log("  FAIL: " + name);
        console.log("        " + (err.message || String(err)));
        failed++; failures.push({ name: name, message: err.message || String(err) });
      } else { console.log("  PASS: " + name); passed++; }
      resolve();
    });
  });
}

// =============================================================================
// SECTION 2 -- helpers
// =============================================================================

function readRepo(rel) {
  return fs.readFileSync(path.join(REPO, rel), "utf8");
}
function exists(rel) {
  try { fs.accessSync(path.join(REPO, rel)); return true; } catch (e) { return false; }
}

/**
 * Minimal XML well-formedness check: no library available in this repo, and the other
 * integration suites do string-level checks. This validates tag nesting while skipping
 * comments, processing instructions, CDATA sections and self-closing tags.
 */
function assertWellFormedXml(xml, label) {
  var i = 0, n = xml.length;
  var stack = [];
  while (i < n) {
    var lt = xml.indexOf("<", i);
    if (lt < 0) break;
    if (xml.substr(lt, 4) === "<!--") { var end = xml.indexOf("-->", lt + 4); assert(end >= 0, label + ": unterminated comment"); i = end + 3; continue; }
    if (xml.substr(lt, 9) === "<![CDATA[") { var ce = xml.indexOf("]]>", lt + 9); assert(ce >= 0, label + ": unterminated CDATA"); i = ce + 3; continue; }
    if (xml.charAt(lt + 1) === "?") { var pe = xml.indexOf("?>", lt + 2); assert(pe >= 0, label + ": unterminated processing instruction"); i = pe + 2; continue; }
    if (xml.substr(lt, 2) === "<!") { var de = xml.indexOf(">", lt + 2); assert(de >= 0, label + ": unterminated declaration"); i = de + 1; continue; }
    var gt = xml.indexOf(">", lt + 1);
    assert(gt >= 0, label + ": unterminated tag near offset " + lt);
    var tag = xml.substring(lt + 1, gt).trim();
    i = gt + 1;
    if (tag === "") continue;
    if (tag.charAt(0) === "/") {
      var closeName = tag.substring(1).trim();
      assert(stack.length > 0, label + ": closing </" + closeName + "> with empty stack");
      var openName = stack.pop();
      assert(openName === closeName, label + ": </" + closeName + "> does not match <" + openName + ">");
    } else if (tag.charAt(tag.length - 1) === "/") {
      // self-closing -- nothing to push
    } else {
      var m = tag.match(/^([^\s/>]+)/);
      assert(m, label + ": unparseable tag <" + tag + ">");
      stack.push(m[1]);
    }
  }
  assert(stack.length === 0, label + ": unclosed element(s): " + stack.join(", "));
}

// BigFix REST (GROUP B)
var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";
var BIGFIX_AVAILABLE = !!(BIGFIX_URL && BIGFIX_USER && BIGFIX_TOKEN);
var TARGET_SITE   = process.env.TEST_TARGET_SITE  || "Dereso Software Portal";
var PILOT_REGION  = process.env.TEST_PILOT_REGION || "AAG-UK";

function httpGet(fullUrl, cb) {
  var u, opts;
  try { u = new URL(fullUrl); } catch (e) { return cb("bad URL: " + fullUrl); }
  opts = {
    hostname: u.hostname,
    port: u.port || 443,
    path: u.pathname + u.search,
    method: "GET",
    headers: { "Accept": "*/*" },
    rejectUnauthorized: true
  };
  if (BIGFIX_USER && BIGFIX_TOKEN && u.pathname.indexOf("/api/") === 0) {
    opts.headers["Authorization"] = "Basic " + Buffer.from(BIGFIX_USER + ":" + BIGFIX_TOKEN).toString("base64");
  }
  if (process.env.BIGFIX_CA_CERT) {
    try { opts.ca = fs.readFileSync(process.env.BIGFIX_CA_CERT); } catch (e) { /* ignore */ }
  }
  var req = https.request(opts, function (res) {
    var chunks = [];
    res.on("data", function (c) { chunks.push(c); });
    res.on("end", function () { cb(null, res.statusCode, Buffer.concat(chunks)); });
  });
  req.on("error", function (e) { cb(e.message || String(e)); });
  req.end();
}

// =============================================================================
// SECTION 3 -- GROUP A: fixture / run-book / task-XML structure (always run)
// =============================================================================

console.log("");
console.log("Integration tests -- Phase 7 automation pipeline");
console.log("BigFix URL: " + (BIGFIX_URL || "(not set)"));
console.log("-----------------------------------------------------------");
console.log("");
console.log("[ GROUP A: fixture / run-book / task-XML structure -- no BigFix connectivity required ]");
console.log("");

var PHASE07_FIXTURES = [
  { file: "tests/fixtures/phase-07/automation-db-schema.sql",  must: ["CREATE TABLE", "RefUser", "UserRole", "PipelineConfig", "ContentItem"] },
  { file: "tests/fixtures/phase-07/axonious-sample-50.csv",     must: ["sAMAccountName"] },
  { file: "tests/fixtures/phase-07/grouprolemap-seed.json",     must: ["Pattern", "Match_On", "Role"] },
  { file: "tests/fixtures/phase-07/roleref-AAG-UK-sample.json", must: ["\"region\"", "\"roles\"", "source_type", "source_value"] }
];

PHASE07_FIXTURES.forEach(function (fx) {
  runTest(fx.file + " exists and has the expected structure", function () {
    assert(exists(fx.file), "missing fixture: " + fx.file);
    var body = readRepo(fx.file);
    fx.must.forEach(function (token) {
      assert(body.indexOf(token) >= 0, fx.file + " must contain " + JSON.stringify(token));
    });
  });
});

runTest("roleawareness-v2.db fixture exists and is a SQLite file", function () {
  assert(exists("tests/fixtures/phase-07/roleawareness-v2.db"), "missing roleawareness-v2.db");
  var head = fs.readFileSync(path.join(REPO, "tests/fixtures/phase-07/roleawareness-v2.db")).slice(0, 16).toString("latin1");
  assert(head.indexOf("SQLite format 3") === 0, "roleawareness-v2.db is not a SQLite 3 database (header was " + JSON.stringify(head) + ")");
});

runTest("roleref-AAG-UK-sample.json parses and its region is AAG-UK", function () {
  var snap = JSON.parse(readRepo("tests/fixtures/phase-07/roleref-AAG-UK-sample.json"));
  assert(snap.region === "AAG-UK", "region should be AAG-UK, got " + JSON.stringify(snap.region));
  assert(Array.isArray(snap.roles), "roles must be an array");
  assert(snap.roles.length > 0, "roles array should not be empty");
  var u = snap.roles[0].users[0];
  assert(u && typeof u === "object" && "id" in u && "source_type" in u && "source_value" in u,
    "each user entry must be an { id, source_type, source_value } object");
});

var TASK_XMLS = [
  { file: "config/task-DeresoRoleIngest.xml",  script: "Import-AxoniousExport.ps1" },
  { file: "config/task-DeresoRolePublish.xml", script: "Publish-RoleSnapshot.ps1" },
  { file: "config/task-DeresoContentSync.xml", script: "Invoke-ContentSync.ps1" },
  { file: "config/task-DeresoRepoStage.xml",   script: "Stage-Repository.ps1" }
];

TASK_XMLS.forEach(function (t) {
  runTest(t.file + " parses as XML and runs powershell with " + t.script, function () {
    assert(exists(t.file), "missing task XML: " + t.file);
    var xml = readRepo(t.file);
    assertWellFormedXml(xml, t.file);
    assert(/<Command>[^<]*powershell\.exe<\/Command>/i.test(xml), t.file + " <Command> must invoke powershell.exe");
    assert(xml.indexOf("-File ") >= 0, t.file + " <Arguments> must pass -File");
    assert(xml.indexOf(t.script) >= 0, t.file + " must name " + t.script + " in its arguments");
  });
});

runTest("docs/automation-admin-guide.md has every required heading", function () {
  assert(exists("docs/automation-admin-guide.md"), "missing docs/automation-admin-guide.md");
  var g = readRepo("docs/automation-admin-guide.md");
  ["## Overview", "## Prerequisites", "## Configuring", "## Troubleshooting", "## File Reference"].forEach(function (h) {
    assert(g.indexOf(h) >= 0, "guide is missing heading: " + h);
  });
});

runTest("the guide names all four root-server tasks and RoleDB_Maintenance", function () {
  var g = readRepo("docs/automation-admin-guide.md");
  ["DeresoRoleIngest", "DeresoRolePublish", "DeresoContentSync", "DeresoRepoStage", "RoleDB_Maintenance"].forEach(function (n) {
    assert(g.indexOf(n) >= 0, "guide does not mention " + n);
  });
});

runTest("the guide documents the four call-out PipelineConfig keys", function () {
  var g = readRepo("docs/automation-admin-guide.md");
  ["ConsoleUserRelevance", "MaxAgeOutFraction", "MaxStageFileMB", "SnapshotOutputDir"].forEach(function (k) {
    assert(g.indexOf(k) >= 0, "guide does not document " + k);
  });
});

runTest("the guide has a Known Limitations section covering the three v1 caveats", function () {
  var g = readRepo("docs/automation-admin-guide.md");
  assert(/##\s+Known Limitations/i.test(g), "guide is missing a Known Limitations section");
  assert(/console user only/i.test(g), "Known Limitations must cover console-user-only reconcile");
  assert(/age-out/i.test(g) && /no revoke/i.test(g), "Known Limitations must cover age-out-only revoke");
  assert(/RolePublication.{0,40}hand-seeded/i.test(g) || /hand-seeded.{0,40}RolePublication/i.test(g),
    "Known Limitations must cover hand-seeded RolePublication");
});

runTest("the guide documents the task 787 redeploy with the unregister-then-reregister note", function () {
  var g = readRepo("docs/automation-admin-guide.md");
  assert(/task 787/i.test(g), "guide must mention task 787");
  assert(/Unregister-ScheduledTask/i.test(g), "guide must mention Unregister-ScheduledTask");
  assert(/re-?register/i.test(g), "guide must mention re-registering the task");
});

[
  "bes/RoleRef-Policy-template.bes",
  "Dashboard_4_samples/Init  Current User and UserRole DB.bes"
].forEach(function (bes) {
  runTest(bes + " parses as XML", function () {
    assert(exists(bes), "missing: " + bes);
    var xml = readRepo(bes);
    assert(/^\s*<\?xml/.test(xml) || /^\s*<BES\b/.test(xml), bes + " is not an XML document");
    assertWellFormedXml(xml, bes);
  });
});

runTest("RoleRef-Policy-template.bes is a Fixlet, not a SourcedFixletAction", function () {
  var xml = readRepo("bes/RoleRef-Policy-template.bes");
  assert(xml.indexOf("<Fixlet>") >= 0, "template must be a <Fixlet>");
  assert(xml.indexOf("SourcedFixletAction") < 0, "template must NOT be a SourcedFixletAction (0 relevant computers on a dynamic group)");
});

// =============================================================================
// SECTION 4 -- GROUP B: BIGFIX-gated REST round-trips
// =============================================================================

console.log("");
console.log("[ GROUP B: BIGFIX-gated REST round-trips ]");
console.log("");

if (!BIGFIX_AVAILABLE) {
  console.log("  NOTE: BIGFIX_URL / BIGFIX_USER / BIGFIX_TOKEN not set -- GROUP B skipped.");
  console.log("");
}

function testPortalSiteReachable(done) {
  if (!BIGFIX_AVAILABLE) return done(Object.assign(new Error("BIGFIX_* not set"), { isSkip: true }));
  httpGet(BIGFIX_URL.replace(/\/+$/, "") + "/api/site/custom/" + encodeURIComponent(TARGET_SITE), function (err, status, body) {
    if (err) return done(new Error("GET site failed: " + err));
    try {
      assert(status === 200, "expected 200 for the portal site, got " + status);
      done(null);
    } catch (ex) { done(ex); }
  });
}

function testAnalysisHasMapProps(done) {
  if (!BIGFIX_AVAILABLE) return done(Object.assign(new Error("BIGFIX_* not set"), { isSkip: true }));
  // Dereso SWD.bes is imported as an Analysis; the exact site/id vary per environment,
  // so scan the operator analyses list for the two new property names.
  httpGet(BIGFIX_URL.replace(/\/+$/, "") + "/api/analyses", function (err, status, body) {
    if (err) return done(new Error("GET /api/analyses failed: " + err));
    try {
      assert(status === 200, "expected 200 from /api/analyses, got " + status);
      var text = body.toString("utf8");
      assert(text.indexOf("map_source in r.db") >= 0, "Analysis list does not expose 'map_source in r.db' -- import the updated Dereso SWD.bes");
      assert(text.indexOf("map_region in r.db") >= 0, "Analysis list does not expose 'map_region in r.db'");
      done(null);
    } catch (ex) { done(ex); }
  });
}

function testSnapshotSha1RoundTrip(done) {
  if (!BIGFIX_AVAILABLE) return done(Object.assign(new Error("BIGFIX_* not set"), { isSkip: true }));
  var base = process.env.BIGFIX_SNAPSHOT_BASE ||
    (BIGFIX_URL.replace(/\/+$/, "") + "/Uploads/CustomRepository/SoftwarePortal/roleref");
  var rlc = PILOT_REGION.toLowerCase();
  var latestUrl = base + "/roleref-" + rlc + "-latest.json";
  var manifestUrl = latestUrl + ".sha1";
  httpGet(manifestUrl, function (err, mStatus, mBody) {
    if (err) return done(new Error("GET manifest failed: " + err));
    if (mStatus === 404) return done(Object.assign(new Error("no published snapshot for region " + PILOT_REGION), { isSkip: true }));
    try {
      assert(mStatus === 200, "expected 200 for the .sha1 manifest, got " + mStatus);
      var manifestSha1 = mBody.toString("utf8").trim().split(/\s+/)[0].toLowerCase();
      assert(/^[0-9a-f]{40}$/.test(manifestSha1), "manifest does not start with a 40-hex SHA1: " + JSON.stringify(manifestSha1));
      httpGet(latestUrl, function (e2, sStatus, sBody) {
        if (e2) return done(new Error("GET snapshot failed: " + e2));
        try {
          assert(sStatus === 200, "expected 200 for the snapshot, got " + sStatus);
          var actual = crypto.createHash("sha1").update(sBody).digest("hex");
          assert(actual === manifestSha1, "snapshot SHA1 " + actual + " != manifest SHA1 " + manifestSha1);
          done(null);
        } catch (ex) { done(ex); }
      });
    } catch (ex) { done(ex); }
  });
}

// =============================================================================
// SECTION 5 -- run GROUP B then summarise
// =============================================================================

runAsyncTest("portal site is reachable via REST", testPortalSiteReachable)
  .then(function () { return runAsyncTest("Dereso SWD Analysis exposes map_source / map_region properties", testAnalysisHasMapProps); })
  .then(function () { return runAsyncTest("a published region's snapshot URL returns the manifest SHA1", testSnapshotSha1RoundTrip); })
  .then(function () {
    console.log("");
    console.log("-----------------------------------------------------------");
    console.log("Results: " + passed + " passed, " + failed + " failed, " + skipped + " skipped");
    if (failures.length > 0) {
      console.log("");
      console.log("Failures:");
      failures.forEach(function (f, i) {
        console.log("  " + (i + 1) + ". " + f.name);
        console.log("     " + f.message);
      });
    }
    console.log("");
    process.exit(failed > 0 ? 1 : 0);
  })
  .catch(function (err) {
    console.error("Unexpected error in test runner: " + (err.message || String(err)));
    process.exit(1);
  });
