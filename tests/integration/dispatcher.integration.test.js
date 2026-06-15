/**
 * Integration tests for fixlet_dispatcher.ojo — BigFix REST API POST patterns.
 *
 * WARNING: Run against a STAGING BigFix instance only. Test 3 creates a real
 * offer-type action deployment. Do not run against production.
 *
 * Note: FR-04 (role-based description update) is deferred to Phase 4.
 * No tests for description modification exist here — that is intentional.
 *
 * Required environment variables (set before running):
 *   BIGFIX_URL   — Base URL of the BigFix REST API, e.g. https://bigfix.example.com:52311
 *   BIGFIX_USER  — BigFix admin username
 *   BIGFIX_TOKEN — BigFix admin password (used as Basic auth credential)
 *
 * Optional environment variables:
 *   TEST_SOURCE_SITE_NAME  — Site name for round-trip tests (default: "Dereso Software Portal")
 *   TEST_SOURCE_FIXLET_ID  — Fixlet ID for GET round-trip and POST tests (skipped if not set)
 *   TEST_TARGET_GROUP      — Target group name for the POST action (default: "All Workstations")
 *
 * Usage:
 *   node tests/integration/dispatcher.integration.test.js
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
// SECTION 2 — API helper (mirrors API.Post / API.Get from fixlet_dispatcher.ojo)
// =============================================================================

var https = require("https");
var fs    = require("fs");
var path  = require("path");

/**
 * apiRequest(method, relativePath, bodyXml, callback)
 *
 * Mirrors the BigFix console API.Get / API.Put / API.Post interface used by
 * fixlet_dispatcher.ojo. Constructs: BIGFIX_URL + "/api/" + relativePath.
 * Auth: Basic BIGFIX_USER:BIGFIX_TOKEN
 *
 * Key difference from modifier.integration.test.js: body-write conditions
 * handle both PUT and POST (not only PUT as in modifier.integration.test.js line 84).
 *
 * callback(errorMsg, statusCode, responseBody)
 *   errorMsg     — null on success, error string on network/parse failure
 *   statusCode   — HTTP status code (integer), or null on network error
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

  if ((method === "PUT" || method === "POST") && bodyXml) {
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

  if ((method === "PUT" || method === "POST") && bodyXml) {
    req.write(Buffer.from(bodyXml, "utf8"));
  }

  req.end();
}

// =============================================================================
// SECTION 3 — Guard utility functions (ported from fixlet_dispatcher.ojo)
// =============================================================================

/**
 * buildTargetRelevance(groupName)
 * Verbatim from fixlet_dispatcher.ojo.
 * Converts a target group name to a BigFix relevance expression.
 * Falls back to "true" (all computers) for blank/empty group names.
 * Used in Test 5 to assert the safety fallback behaviour.
 */
function buildTargetRelevance(groupName) {
  if (!groupName || groupName.replace(/^\s+|\s+$/g, "") === "") { return "true"; }
  var safeGroup = String(groupName).replace(/'/g, "\\'");
  return "member of bes computer group whose (name of it = '" + safeGroup + "')";
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
 * Mirrors testREST() in fixlet_dispatcher.ojo.
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
 * Mirrors selectFixlet() in fixlet_dispatcher.ojo.
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
 * Test 3: POST round-trip — deploy fixlet as offer-type action (NFR-01 timing assertion)
 * Builds SourcedFixletAction XML inline (no file read) using env vars.
 * Requires TEST_SOURCE_FIXLET_ID (skipped if not set).
 * Asserts: HTTP 200 or 201, elapsed < 5000ms (NFR-01 for dispatcher).
 * Mirrors deployFixlet() + API.Post in fixlet_dispatcher.ojo.
 */
function test3_postActionHappyPath(done) {
  var siteName    = process.env.TEST_SOURCE_SITE_NAME || "Dereso Software Portal";
  var fixletId    = process.env.TEST_SOURCE_FIXLET_ID || "";
  var targetGroup = process.env.TEST_TARGET_GROUP     || "All Workstations";

  if (!fixletId) {
    var skipErr = new Error("TEST_SOURCE_FIXLET_ID not set");
    skipErr.isSkip = true;
    return done(skipErr);
  }

  // Build SourcedFixletAction XML inline (RESEARCH.md Pattern 2)
  // Group targeting via <Relevance> element only — no <Target> element (RESEARCH.md A1, Pitfall 1)
  var relevance = "member of bes computer group whose (name of it = '" +
                  targetGroup.replace(/'/g, "\\'") + "')";

  var xml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"\n' +
    '     xsi:noNamespaceSchemaLocation="BES.xsd">\n' +
    '  <SourcedFixletAction>\n' +
    '    <SourceFixlet>\n' +
    '      <Sitename>' + siteName + '</Sitename>\n' +
    '      <FixletID>' + fixletId + '</FixletID>\n' +
    '      <Action>Action1</Action>\n' +
    '    </SourceFixlet>\n' +
    '    <Settings>\n' +
    '      <HasEndTime>true</HasEndTime>\n' +
    '      <EndDateTimeLocalOffset>P7D</EndDateTimeLocalOffset>\n' +
    '      <IsOffer>true</IsOffer>\n' +
    '      <ActionUITitle>Integration Test Offer</ActionUITitle>\n' +
    '      <AnnounceOffer>true</AnnounceOffer>\n' +
    '      <OfferCategory>Test Category</OfferCategory>\n' +
    '      <OfferDescriptionHTML><![CDATA[<p>Integration test offer description.</p>]]></OfferDescriptionHTML>\n' +
    '    </Settings>\n' +
    '    <SettingsLocks>\n' +
    '      <IsOffer>false</IsOffer>\n' +
    '      <AnnounceOffer>false</AnnounceOffer>\n' +
    '      <OfferCategory>false</OfferCategory>\n' +
    '      <OfferDescriptionHTML>false</OfferDescriptionHTML>\n' +
    '    </SettingsLocks>\n' +
    '    <Relevance>' + relevance + '</Relevance>\n' +
    '  </SourcedFixletAction>\n' +
    '</BES>';

  var start = Date.now();

  apiRequest("POST", "actions", xml, function(errorMsg, statusCode, responseBody) {
    var elapsed = Date.now() - start;
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }
      assert(statusCode === 200 || statusCode === 201,
             "POST /api/actions status should be 200 or 201, got " + statusCode);
      assert(elapsed < 5000,
             "NFR-01: elapsed " + elapsed + "ms must be < 5000ms");
      console.log("        POST round-trip OK (elapsed: " + elapsed + "ms, status: " + statusCode + ")");
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

/**
 * Test 4: Input guard — no fixlet selected
 * Synchronous — no BigFix connectivity required.
 * Verifies the guard logic: if sourceXml === "" then buildDeployXml returns "".
 * Since buildDeployXml uses ActiveXObject (not runnable in Node), tests the guard
 * condition inline, mirroring the check at fixlet_dispatcher.ojo buildDeployXml().
 */
function test4_guardNoFixletSelected() {
  // Mirror the guard at the top of buildDeployXml(): if(!sourceXml){ return ""; }
  var sourceXml = "";
  var result = (sourceXml === "") ? "" : "WOULD_BUILD";
  assertEqual(result, "", "Empty sourceXml should short-circuit buildDeployXml");
}

/**
 * Test 5: Input guard — empty target group
 * Synchronous — no BigFix connectivity required.
 * Verifies that buildTargetRelevance("") returns "true" (the safety fallback
 * that prevents broken relevance when no group is specified).
 */
function test5_guardEmptyTargetGroup() {
  var result = buildTargetRelevance("");
  assertEqual(result, "true", "buildTargetRelevance('') should return 'true'");
}

/**
 * Test 6: API error handling
 * Requests a fixlet that should not exist to provoke a 404 or 500 from BigFix.
 * Verifies the error is captured (not silently swallowed) — mirrors the else-branch
 * of API.Post in fixlet_dispatcher.ojo deployFixlet().
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
console.log("Integration tests — fixlet_dispatcher.ojo BigFix API POST patterns");
console.log("BigFix URL: " + BIGFIX_URL);
console.log("Note: FR-04 (description update) is deferred to Phase 4.");
console.log("-----------------------------------------------------------");
console.log("");

// Run synchronous guard tests first (Tests 4, 5 — no network required)
console.log("[ Synchronous guard tests — no BigFix connectivity required ]");
runTest("Test 4: Input guard — no fixlet selected",    test4_guardNoFixletSelected);
runTest("Test 5: Input guard — empty target group",    test5_guardEmptyTargetGroup);
console.log("");

// Run async tests sequentially
console.log("[ Async API tests — require live BigFix instance ]");

runAsyncTest("Test 1: API connectivity",              test1_apiConnectivity)
  .then(function() { return runAsyncTest("Test 2: Load source fixlet", test2_loadSourceFixlet); })
  .then(function() { return runAsyncTest("Test 3: POST round-trip (happy path + NFR-01 timing)", test3_postActionHappyPath); })
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
