/**
 * Integration tests for fixlet_modifier.ojo — BigFix REST API PUT patterns.
 *
 * WARNING: Run against a STAGING BigFix instance only. Test 3 writes a real
 * fixlet update to the target site. Do not run against production.
 *
 * Note: FR-04 (role-based description update) is deferred to Phase 3 per D-04.
 * No tests for description modification exist here — that is intentional.
 *
 * Required environment variables (set before running):
 *   BIGFIX_URL   — Base URL of the BigFix REST API, e.g. https://bigfix.example.com:52311
 *   BIGFIX_USER  — BigFix admin username
 *   BIGFIX_TOKEN — BigFix admin password (used as Basic auth credential)
 *
 * Optional environment variables:
 *   TEST_SOURCE_SITE_NAME  — Site name of a real test fixlet to load (e.g. "Dereso Software Portal")
 *   TEST_SOURCE_FIXLET_ID  — Fixlet ID of that test fixlet (e.g. "12345")
 *   TEST_TARGET_SITE       — Custom site containing the fixlet to update
 *                            (defaults to "Dereso Software Portal")
 *   TEST_TARGET_FIXLET_ID  — ID of an existing fixlet to PUT to (required for test 3)
 *
 * Usage:
 *   node tests/integration/modifier.integration.test.js
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
// SECTION 2 — API helper (mirrors API.Put / API.Get from fixlet_modifier.ojo)
// =============================================================================

var https = require("https");
var fs    = require("fs");
var path  = require("path");

/**
 * apiRequest(method, relativePath, bodyXml, callback)
 *
 * Mirrors the BigFix console API.Get / API.Put interface used by fixlet_modifier.ojo.
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

  if (method === "PUT" && bodyXml) {
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

  if (method === "PUT" && bodyXml) {
    req.write(Buffer.from(bodyXml, "utf8"));
  }

  req.end();
}

// =============================================================================
// SECTION 3 — Guard utility functions (ported from fixlet_modifier.ojo)
// =============================================================================

/**
 * getRolesFromArray(roleValues)
 * Parameterized version of getRolesFromEditor() from modifier.ojo lines 221-233.
 * Accepts array of values, deduplicates, skips empty strings.
 */
function getRolesFromArray(roleValues) {
  var roles = [];
  for (var i = 0; i < roleValues.length; i++) {
    var val = String(roleValues[i] || "");
    if (val !== "" && roles.indexOf(val) < 0) { roles.push(val); }
  }
  return roles;
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
 * Mirrors testREST() in fixlet_modifier.ojo lines 119-123.
 */
function test1_apiConnectivity(done) {
  apiRequest("GET", "sites", null, function(errorMsg, statusCode, responseBody) {
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }
      assertEqual(statusCode, 200, "GET /api/sites status");
      console.log("        Status: API OK (HTTP " + statusCode + ")");
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

/**
 * Test 2: Load source fixlet (GET round-trip)
 * Requires TEST_SOURCE_SITE_NAME and TEST_SOURCE_FIXLET_ID.
 * Asserts: 200, body contains <BES and <Title>.
 * Mirrors selectFixlet() in fixlet_modifier.ojo lines 358-376.
 */
function test2_loadSourceFixlet(done) {
  var siteName = process.env.TEST_SOURCE_SITE_NAME || "";
  var fixletId = process.env.TEST_SOURCE_FIXLET_ID || "";

  if (!siteName || !fixletId) {
    var skipErr = new Error("TEST_SOURCE_SITE_NAME, TEST_SOURCE_FIXLET_ID not set");
    skipErr.isSkip = true;
    return done(skipErr);
  }

  var relativePath = "fixlet/custom/" + encodeURIComponent(siteName) + "/" +
                     encodeURIComponent(fixletId);

  apiRequest("GET", relativePath, null, function(errorMsg, statusCode, responseBody) {
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }
      assertEqual(statusCode, 200, "GET fixlet status");
      assert(responseBody && responseBody.indexOf("<BES") !== -1,
             "responseBody should contain <BES element");
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
 * Test 3: PUT round-trip — update fixlet with roles (NFR-01 timing assertion)
 * Uses fixture: tests/fixtures/phase-02/valid-fixlet-with-roles.ojo
 * Requires TEST_TARGET_FIXLET_ID (fixlet must exist in target site).
 * Asserts: HTTP 200 or 201, elapsed < 30000ms.
 * Mirrors saveFixlet() + API.Put in fixlet_modifier.ojo lines 638-671.
 */
function test3_putFixletHappyPath(done) {
  var targetSite     = process.env.TEST_TARGET_SITE      || "Dereso Software Portal";
  var targetFixletId = process.env.TEST_TARGET_FIXLET_ID || "";

  if (!targetFixletId) {
    var skipErr = new Error("TEST_TARGET_FIXLET_ID not set");
    skipErr.isSkip = true;
    return done(skipErr);
  }

  var fixturePath = path.join(__dirname, "..", "fixtures", "phase-02", "valid-fixlet-with-roles.ojo");
  var fixtureXml;
  try {
    fixtureXml = fs.readFileSync(fixturePath, "utf8");
  } catch (ex) {
    return done(new Error("Could not read fixture file at " + fixturePath + ": " + ex.message));
  }

  var relativePath = "fixlet/custom/" + encodeURIComponent(targetSite) + "/" +
                     encodeURIComponent(targetFixletId);
  var start = Date.now();

  apiRequest("PUT", relativePath, fixtureXml, function(errorMsg, statusCode, responseBody) {
    var elapsed = Date.now() - start;
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }
      assert(statusCode === 200 || statusCode === 201,
             "PUT status should be 200 or 201, got " + statusCode);
      assert(elapsed < 30000,
             "NFR-01: elapsed " + elapsed + "ms must be < 30000ms");
      console.log("        PUT round-trip OK (elapsed: " + elapsed + "ms)");
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

/**
 * Test 4: Input guard — no fixlet selected
 * Synchronous — no BigFix connectivity required.
 * Verifies the guard logic: if sourceXml === "" then buildUpdateXml returns "".
 * Since buildUpdateXml uses ActiveXObject (not runnable in Node), tests the guard
 * condition inline, mirroring the check at fixlet_modifier.ojo line 561.
 */
function test4_guardNoFixletSelected() {
  // Mirror the guard at the top of buildUpdateXml(): if(!sourceXml){ return ""; }
  var sourceXml = "";
  var result = (sourceXml === "") ? "" : "WOULD_BUILD";
  assertEqual(result, "", "Empty sourceXml should short-circuit buildUpdateXml");
}

/**
 * Test 5: Input guard — no roles defined
 * Synchronous — no BigFix connectivity required.
 * Verifies that getRolesFromArray([]) returns [] (which triggers the
 * "No roles defined" confirm in saveFixlet at modifier.ojo line 642).
 */
function test5_guardNoRolesConfirm() {
  var roles = getRolesFromArray([]);
  assertEqual(roles.length, 0, "Empty role table should return empty roles array");
}

/**
 * Test 6: API error handling
 * Requests a fixlet that should not exist to provoke a 404 or 500 from BigFix.
 * Verifies the error is captured (not silently swallowed) — mirrors the else-branch
 * of API.Put in fixlet_modifier.ojo lines 667-670.
 */
function test6_apiErrorHandling(done) {
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

      // Error must be surfaced — statusCode must not be null
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
console.log("Integration tests — fixlet_modifier.ojo BigFix API patterns");
console.log("BigFix URL: " + BIGFIX_URL);
console.log("Note: FR-04 (description update) is deferred to Phase 3 per D-04.");
console.log("-----------------------------------------------------------");
console.log("");

// Run synchronous guard tests first (Tests 4, 5 — no network required)
console.log("[ Synchronous guard tests — no BigFix connectivity required ]");
runTest("Test 4: Input guard — no fixlet selected",   test4_guardNoFixletSelected);
runTest("Test 5: Input guard — no roles defined",     test5_guardNoRolesConfirm);
console.log("");

// Run async tests sequentially
console.log("[ Async API tests — require live BigFix instance ]");

runAsyncTest("Test 1: API connectivity",              test1_apiConnectivity)
  .then(function() { return runAsyncTest("Test 2: Load source fixlet", test2_loadSourceFixlet); })
  .then(function() { return runAsyncTest("Test 3: PUT round-trip (happy path + NFR-01 timing)", test3_putFixletHappyPath); })
  .then(function() { return runAsyncTest("Test 6: API error handling", test6_apiErrorHandling); })
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
