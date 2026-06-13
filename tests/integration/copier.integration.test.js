/**
 * Integration tests for fixlet_copier.ojo — BigFix REST API call patterns.
 *
 * WARNING: Run against a STAGING BigFix instance only. Test 3 creates a real
 * fixlet in the target site. Do not run against production.
 *
 * Required environment variables (set before running):
 *   BIGFIX_URL   — Base URL of the BigFix REST API, e.g. https://bigfix.example.com:52311
 *   BIGFIX_USER  — BigFix admin username
 *   BIGFIX_TOKEN — BigFix admin password (used as Basic auth credential)
 *
 * Optional environment variables:
 *   TEST_SOURCE_SITE_TYPE  — Site type of a real test fixlet to load (e.g. "custom")
 *   TEST_SOURCE_SITE_NAME  — Site name of that test fixlet (e.g. "My Test Site")
 *   TEST_SOURCE_FIXLET_ID  — Fixlet ID of that test fixlet (e.g. "12345")
 *   TEST_TARGET_SITE       — Custom site to create the test fixlet in
 *                            (defaults to "Dereso Software Portal")
 *
 * Usage:
 *   node tests/integration/copier.integration.test.js
 *
 * Exit codes:
 *   0  — all executed tests passed (or skipped gracefully)
 *   1  — one or more tests failed
 */

"use strict";

// =============================================================================
// SECTION 1 — Environment guard
// =============================================================================

var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: BIGFIX_URL, BIGFIX_USER, and BIGFIX_TOKEN must all be set to run integration tests.");
  process.exit(0);
}

// =============================================================================
// SECTION 2 — API helper (mirrors API.Get / API.Post from fixlet_copier.ojo)
// =============================================================================

var https = require("https");
var fs    = require("fs");
var path  = require("path");
var url   = require("url");

/**
 * apiRequest(method, relativePath, bodyXml, callback)
 *
 * Mirrors the BigFix console API.Get / API.Post interface used by fixlet_copier.ojo.
 * Constructs: BIGFIX_URL + "/api/" + relativePath
 * Auth:       Basic BIGFIX_USER:BIGFIX_TOKEN
 *
 * callback(errorMsg, statusCode, responseBody)
 *   errorMsg    — null on success, error string on network/parse failure
 *   statusCode  — HTTP status code (integer), or null on network error
 *   responseBody — full response body string, or null on network error
 */
function apiRequest(method, relativePath, bodyXml, callback) {
  var parsed = new URL(BIGFIX_URL);
  var authHeader = "Basic " + Buffer.from(BIGFIX_USER + ":" + BIGFIX_TOKEN).toString("base64");
  var apiPath = "/api/" + relativePath;

  var requestOptions = {
    hostname: parsed.hostname,
    port:     parsed.port || 52311,
    path:     apiPath,
    method:   method,
    headers:  {
      "Authorization": authHeader,
      "Accept":        "application/xml"
    },
    // For self-signed certs, set BIGFIX_CA_CERT=/path/to/ca.crt and pass ca: fs.readFileSync(process.env.BIGFIX_CA_CERT) in requestOptions.
    // Do NOT use NODE_TLS_REJECT_UNAUTHORIZED=0 — it disables TLS validation globally for the entire process.
    rejectUnauthorized: true
  };

  if (method === "POST" && bodyXml) {
    var bodyBuffer = Buffer.from(bodyXml, "utf8");
    requestOptions.headers["Content-Type"]   = "application/xml";
    requestOptions.headers["Content-Length"] = bodyBuffer.length;
  }

  var req = https.request(requestOptions, function(res) {
    var chunks = [];
    res.on("data", function(chunk) { chunks.push(chunk); });
    res.on("end", function() {
      var responseBody = Buffer.concat(chunks).toString("utf8");
      callback(null, res.statusCode, responseBody);
    });
  });

  req.on("error", function(err) {
    callback(err.message || String(err), null, null);
  });

  if (method === "POST" && bodyXml) {
    req.write(bodyBuffer);
  }

  req.end();
}

// =============================================================================
// SECTION 3 — Utility functions (ported from fixlet_copier.ojo)
// =============================================================================

/**
 * parseCreatedId(body)
 * Extracted from fixlet_copier.ojo lines 365–405.
 * Tries regex fallbacks (ActiveXObject is IE-only and skipped in Node.js).
 * Returns the new Fixlet ID string, or "" if not found.
 */
function parseCreatedId(body) {
  var m;
  if (!body) { return ""; }

  // ActiveXObject branch (IE/BigFix console only) — skipped in Node.js
  // try { ... } catch(ex) {}

  // Regex fallback 1: URL path containing fixlet type and numeric ID
  m = /fixlet\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
  if (m && m[1]) { return m[1]; }

  // Regex fallback 2: task variant
  m = /task\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
  if (m && m[1]) { return m[1]; }

  // Regex fallback 3: bare ID= attribute
  m = /\bID=["']?(\d+)["']?/i.exec(body);
  if (m && m[1]) { return m[1]; }

  return "";
}

/**
 * guardNoSource(sourceXml)
 * Returns the alert message if no source fixlet is selected, else null.
 * Mirrors fixlet_copier.ojo line 784.
 */
function guardNoSource(sourceXml) {
  if (sourceXml === "") { return "Select a source Fixlet first."; }
  return null;
}

/**
 * guardNoSite(site)
 * Returns the alert message if no target site is entered, else null.
 * Mirrors fixlet_copier.ojo line 785.
 */
function guardNoSite(site) {
  if (site === "") { return "Enter a target custom site."; }
  return null;
}

/**
 * guardNoActions(parsedActions)
 * Returns the alert message if no actions are available, else null.
 * Mirrors fixlet_copier.ojo line 786.
 */
function guardNoActions(parsedActions) {
  if (parsedActions.length === 0) { return "No actions available."; }
  return null;
}

// =============================================================================
// SECTION 4 — Test runner
// =============================================================================

var passed   = 0;
var failed   = 0;
var skipped  = 0;
var failures = [];

function assert(condition, message) {
  if (!condition) {
    var err = new Error("Assertion failed: " + message);
    err.isAssertionError = true;
    throw err;
  }
}

function assertEqual(actual, expected, label) {
  assert(
    actual === expected,
    (label || "assertEqual") + " — expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual)
  );
}

function assertNotEmpty(value, label) {
  assert(
    value !== null && value !== undefined && String(value).length > 0,
    (label || "assertNotEmpty") + " — expected non-empty value, got " + JSON.stringify(value)
  );
}

function runTest(name, fn) {
  try {
    fn();
    console.log("  PASS: " + name);
    passed++;
  } catch (ex) {
    if (ex.isSkip) {
      console.log("  SKIP: " + name + " — " + ex.message);
      skipped++;
    } else {
      console.log("  FAIL: " + name);
      console.log("        " + (ex.message || String(ex)));
      failed++;
      failures.push({ name: name, message: ex.message || String(ex) });
    }
  }
}

function skipTest(reason) {
  var err = new Error(reason);
  err.isSkip = true;
  throw err;
}

// Async test wrapper: returns a Promise that resolves/rejects
function runAsyncTest(name, fn) {
  return new Promise(function(resolve) {
    fn(function(err) {
      if (err && err.isSkip) {
        console.log("  SKIP: " + name + " — " + err.message);
        skipped++;
      } else if (err) {
        console.log("  FAIL: " + name);
        console.log("        " + (err.message || String(err)));
        failed++;
        failures.push({ name: name, message: err.message || String(err) });
      } else {
        console.log("  PASS: " + name);
        passed++;
      }
      resolve();
    });
  });
}

// =============================================================================
// SECTION 5 — Test scenarios
// =============================================================================

/**
 * Test 1: API connectivity
 * Calls GET /api/sites and asserts HTTP 200.
 * Mirrors testREST() in fixlet_copier.ojo lines 146–151.
 */
function test1_apiConnectivity(done) {
  apiRequest("GET", "sites", null, function(errorMsg, statusCode, responseBody) {
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }
      assertEqual(statusCode, 200, "GET /api/sites status");
      // Mirror the setStatus("API OK") feedback from copier.ojo
      console.log("        Status: API OK (HTTP " + statusCode + ")");
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

/**
 * Test 2: Load a source fixlet
 * Requires TEST_SOURCE_SITE_TYPE, TEST_SOURCE_SITE_NAME, TEST_SOURCE_FIXLET_ID.
 * Mirrors selectFixlet() in fixlet_copier.ojo lines 423–441.
 */
function test2_loadSourceFixlet(done) {
  var siteType = process.env.TEST_SOURCE_SITE_TYPE || "";
  var siteName = process.env.TEST_SOURCE_SITE_NAME || "";
  var fixletId = process.env.TEST_SOURCE_FIXLET_ID || "";

  if (!siteType || !siteName || !fixletId) {
    var skipErr = new Error("TEST_SOURCE_SITE_TYPE, TEST_SOURCE_SITE_NAME, TEST_SOURCE_FIXLET_ID not set");
    skipErr.isSkip = true;
    return done(skipErr);
  }

  var relativePath = "fixlet/" + encodeURIComponent(siteType) + "/" +
                     encodeURIComponent(siteName) + "/" +
                     encodeURIComponent(fixletId);

  apiRequest("GET", relativePath, null, function(errorMsg, statusCode, responseBody) {
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }
      assertEqual(statusCode, 200, "GET fixlet status");
      assert(responseBody && responseBody.indexOf("<BES>") !== -1,
             "responseBody should contain <BES> element");
      assert(responseBody && responseBody.indexOf("<Title>") !== -1,
             "responseBody should contain <Title> element");
      console.log("        Source XML loaded (" + responseBody.length + " bytes), Title element present");
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

/**
 * Test 3: Create fixlet — happy path (NFR-01 timing assertion)
 * POSTs valid-minimal.ojo to TEST_TARGET_SITE (default: "Dereso Software Portal").
 * Mirrors createFixlet() + API.Post in fixlet_copier.ojo lines 780–808.
 * Asserts: HTTP 200 or 201, non-empty ID returned, elapsed < 30000 ms (NFR-01).
 */
function test3_createFixletHappyPath(done) {
  var targetSite = process.env.TEST_TARGET_SITE || "Dereso Software Portal";
  var fixturePath = path.join(__dirname, "..", "fixtures", "phase-01", "valid-minimal.ojo");

  var fixtureXml;
  try {
    fixtureXml = fs.readFileSync(fixturePath, "utf8");
  } catch (ex) {
    return done(new Error("Could not read fixture file at " + fixturePath + ": " + ex.message));
  }

  var relativePath = "fixlets/custom/" + encodeURIComponent(targetSite);
  var start = Date.now();

  apiRequest("POST", relativePath, fixtureXml, function(errorMsg, statusCode, responseBody) {
    var elapsed = Date.now() - start;
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }

      assert(statusCode === 200 || statusCode === 201,
             "POST status should be 200 or 201, got " + statusCode);

      var parsedId = parseCreatedId(responseBody || "");
      assertNotEmpty(parsedId, "parseCreatedId(responseBody)");

      assert(elapsed < 30000,
             "NFR-01: elapsed " + elapsed + "ms must be < 30000ms");

      console.log("        Created Fixlet ID: " + parsedId +
                  " in site: " + targetSite +
                  " (elapsed: " + elapsed + "ms)");
      // Mirror setStatus("Created via ... ID=...") from copier.ojo line 800
      console.log("        Status: Created via " + relativePath + " ID=" + parsedId);
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

/**
 * Test 4: Input guard — no source selected
 * Synchronous — no BigFix connectivity required.
 * Mirrors copier.ojo line 784: if(sourceXml===""){alert("Select a source Fixlet first.");}
 */
function test4_guardNoSource() {
  var msg = guardNoSource("");
  assertEqual(msg, "Select a source Fixlet first.", "guardNoSource(\"\") return value");

  var msgPopulated = guardNoSource("<BES>some xml</BES>");
  assert(msgPopulated === null || msgPopulated === "",
         "guardNoSource(populated xml) should return null or empty — guard must NOT fire");
}

/**
 * Test 5: Input guard — no target site
 * Synchronous — no BigFix connectivity required.
 * Mirrors copier.ojo line 785: if(site===""){alert("Enter a target custom site.");}
 */
function test5_guardNoSite() {
  var msg = guardNoSite("");
  assertEqual(msg, "Enter a target custom site.", "guardNoSite(\"\") return value");

  var msgPopulated = guardNoSite("Dereso Software Portal");
  assert(msgPopulated === null || msgPopulated === "",
         "guardNoSite(valid site) should return null or empty — guard must NOT fire");
}

/**
 * Test 6: Input guard — no actions available
 * Synchronous — no BigFix connectivity required.
 * Mirrors copier.ojo line 786: if(parsedActions.length===0){alert("No actions available.");}
 */
function test6_guardNoActions() {
  var msg = guardNoActions([]);
  assertEqual(msg, "No actions available.", "guardNoActions([]) return value");

  var msgPopulated = guardNoActions([{ kind: "DefaultAction", script: "echo hi" }]);
  assert(msgPopulated === null || msgPopulated === "",
         "guardNoActions(with 1 action) should return null or empty — guard must NOT fire");
}

/**
 * Test 7: API error handling
 * Requests a fixlet that should not exist to provoke a 404 or 500 from BigFix.
 * Verifies the error is captured (not silently swallowed) — mirrors the else-branch
 * of API.Post in fixlet_copier.ojo lines 803–806.
 */
function test7_apiErrorHandling(done) {
  apiRequest("GET", "fixlet/custom/NonExistentSite99999/99999999", null, function(errorMsg, statusCode, responseBody) {
    try {
      // A network error is also an acceptable outcome (errorMsg set)
      if (errorMsg) {
        console.log("        API error correctly surfaced (network): " + errorMsg);
        done(null);
        return;
      }

      assert(statusCode !== 200,
             "Expected non-200 status for non-existent fixlet, got " + statusCode);

      // Error must be surfaced — either statusCode or a non-empty response body
      assert(statusCode !== null,
             "statusCode must not be null — error must not be silently swallowed");

      console.log("        API error correctly surfaced: status=" + statusCode);
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

// =============================================================================
// SECTION 6 — Run all tests and summarise
// =============================================================================

console.log("");
console.log("Integration tests — fixlet_copier.ojo BigFix API patterns");
console.log("BigFix URL: " + BIGFIX_URL);
console.log("-----------------------------------------------------------");
console.log("");

// Run synchronous tests first (Tests 4, 5, 6 — no network required)
console.log("[ Synchronous guard tests — no BigFix connectivity required ]");
runTest("Test 4: Input guard — no source selected",  test4_guardNoSource);
runTest("Test 5: Input guard — no target site",      test5_guardNoSite);
runTest("Test 6: Input guard — no actions available", test6_guardNoActions);
console.log("");

// Run async tests sequentially
console.log("[ Async API tests — require live BigFix instance ]");

runAsyncTest("Test 1: API connectivity",               test1_apiConnectivity)
  .then(function() { return runAsyncTest("Test 2: Load source fixlet", test2_loadSourceFixlet); })
  .then(function() { return runAsyncTest("Test 3: Create fixlet (happy path + NFR-01 timing)", test3_createFixletHappyPath); })
  .then(function() { return runAsyncTest("Test 7: API error handling", test7_apiErrorHandling); })
  .then(function() {
    console.log("");
    console.log("-----------------------------------------------------------");
    console.log("Results: " + passed + " passed, " + failed + " failed, " + skipped + " skipped");
    if (failures.length > 0) {
      console.log("");
      console.log("Failures:");
      failures.forEach(function(f, i) {
        console.log("  " + (i + 1) + ". " + f.name);
        console.log("     " + f.message);
      });
    }
    console.log("");
    process.exit(failed > 0 ? 1 : 0);
  })
  .catch(function(err) {
    console.error("Unexpected error in test runner: " + (err.message || String(err)));
    process.exit(1);
  });
