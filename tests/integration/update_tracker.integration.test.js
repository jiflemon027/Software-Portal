/**
 * update_tracker.integration.test.js
 *
 * Integration tests for fixlet_update_tracker.ojo — BigFix REST API patterns.
 *
 * WARNING: Run against a STAGING BigFix instance only.
 * Tests in Wave 3 will write real fixlet updates to the target site.
 * Do not run against production.
 *
 * Required environment variables (set before running):
 *   BIGFIX_URL   -- Base URL of the BigFix REST API, e.g. https://bigfix.example.com:52311
 *   BIGFIX_USER  -- BigFix admin username
 *   BIGFIX_TOKEN -- BigFix admin password (used as Basic auth credential)
 *
 * Optional environment variables:
 *   TEST_SOURCE_SITE_TYPE  -- Site type of source fixlet (default: "external")
 *   TEST_SOURCE_SITE_NAME  -- Site name of a real test source fixlet
 *   TEST_SOURCE_FIXLET_ID  -- Fixlet ID of a source fixlet to test copy flow
 *   TEST_PORTAL_FIXLET_ID  -- Fixlet ID of an existing portal fixlet to test supersede flow
 *   TEST_TARGET_SITE       -- Custom site to copy into (default: "Dereso Software Portal")
 *
 * Usage:
 *   node tests/integration/update_tracker.integration.test.js
 *
 * Exit codes:
 *   0  -- all executed tests passed (or skipped gracefully)
 *   1  -- one or more tests failed
 *
 * Test groups:
 *   GROUP A  -- Fixture structure assertions (always run; no BigFix instance required)
 *   GROUP B  -- BIGFIX-gated API round-trip tests (skipped when BIGFIX_* env vars are absent)
 *
 * Security note (T-06-03-01): BIGFIX_TOKEN is never logged. It is only transmitted as a
 * Basic auth header over HTTPS with rejectUnauthorized:true. For self-signed certs, set
 * BIGFIX_CA_CERT=/path/to/ca.crt and pass ca: fs.readFileSync(process.env.BIGFIX_CA_CERT)
 * in requestOptions. Do NOT use NODE_TLS_REJECT_UNAUTHORIZED=0 -- that disables TLS
 * validation globally.
 */

"use strict";

// =============================================================================
// SECTION 1 -- Environment guard
// =============================================================================

var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

// BIGFIX_AVAILABLE controls GROUP B (API round-trip) tests.
// GROUP A (fixture structure) tests always run regardless of this flag.
var BIGFIX_AVAILABLE = !!(BIGFIX_URL && BIGFIX_USER && BIGFIX_TOKEN);

if (!BIGFIX_AVAILABLE) {
  console.log("NOTE: BIGFIX_URL, BIGFIX_USER, BIGFIX_TOKEN not set.");
  console.log("      GROUP A (fixture structure) tests will run normally.");
  console.log("      GROUP B (API round-trip) tests will be SKIPPED.");
  console.log("");
}

// =============================================================================
// SECTION 2 -- API helper (mirrors API.Get / API.Post / API.Put from fixlet_update_tracker.ojo)
// =============================================================================

var https = require("https");
var fs    = require("fs");
var path  = require("path");

/**
 * apiRequest(method, relativePath, bodyXml, callback)
 *
 * Mirrors the BigFix console API.Get / API.Post / API.Put interface.
 * Constructs: BIGFIX_URL + "/api/" + relativePath
 * Auth:       Basic BIGFIX_USER:BIGFIX_TOKEN
 *
 * callback(errorMsg, statusCode, responseBody)
 *   errorMsg     -- null on success, error string on network/parse failure
 *   statusCode   -- HTTP status code (integer), or null on network error
 *   responseBody -- full response body string, or null on network error
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
    // For self-signed certs, set BIGFIX_CA_CERT=/path/to/ca.crt and pass
    // ca: fs.readFileSync(process.env.BIGFIX_CA_CERT) in requestOptions.
    // Do NOT use NODE_TLS_REJECT_UNAUTHORIZED=0 -- it disables TLS validation globally.
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
// SECTION 3 -- Optional environment variables
// =============================================================================

var TEST_SOURCE_SITE_TYPE = process.env.TEST_SOURCE_SITE_TYPE || "external";
var TEST_SOURCE_SITE_NAME = process.env.TEST_SOURCE_SITE_NAME || "";
var TEST_SOURCE_FIXLET_ID = process.env.TEST_SOURCE_FIXLET_ID || "";
var TEST_PORTAL_FIXLET_ID = process.env.TEST_PORTAL_FIXLET_ID || "";
var TEST_TARGET_SITE      = process.env.TEST_TARGET_SITE      || "Dereso Software Portal";

// =============================================================================
// SECTION 4 -- Test runner
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
    (label || "assertEqual") + " -- expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual)
  );
}

function runTest(name, fn) {
  try {
    fn();
    console.log("  PASS: " + name);
    passed++;
  } catch (ex) {
    if (ex.isSkip) {
      console.log("  SKIP: " + name + " -- " + ex.message);
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
        console.log("  SKIP: " + name + " -- " + err.message);
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
// SECTION 5 -- Test scenarios
// =============================================================================

// --------------------------------------------------------------------------
// GROUP B: BIGFIX-gated API round-trip test functions
// (Called from SECTION 6 after synchronous GROUP A tests complete)
// --------------------------------------------------------------------------

/**
 * GROUP B Test 1: GET source fixlet returns 200 (NFR-01 timing)
 * Verifies that a source site fixlet is readable via the BigFix REST API and
 * that the response completes within the NFR-01 budget of 30 seconds.
 *
 * NOTE: NFR-01 covers all 4 steps of copyNextItem (GET portal, GET source,
 * POST copy, PUT supersede). This test measures the GET step only. Full
 * round-trip testing would require writing a test fixlet to the portal, which
 * could contaminate the staging environment. Kept read-only by design.
 *
 * Requires: BIGFIX_AVAILABLE, TEST_SOURCE_SITE_NAME, TEST_SOURCE_FIXLET_ID
 */
function testGroupB_getSourceFixlet(done) {
  if (!BIGFIX_AVAILABLE) {
    var skipErr = new Error("BIGFIX env not set (BIGFIX_URL, BIGFIX_USER, BIGFIX_TOKEN required)");
    skipErr.isSkip = true;
    return done(skipErr);
  }
  if (!TEST_SOURCE_SITE_NAME || !TEST_SOURCE_FIXLET_ID) {
    var skipErr2 = new Error("TEST_SOURCE_SITE_NAME or TEST_SOURCE_FIXLET_ID not set");
    skipErr2.isSkip = true;
    return done(skipErr2);
  }
  var t0 = Date.now();
  apiRequest(
    "GET",
    "fixlet/" + TEST_SOURCE_SITE_TYPE + "/" + encodeURIComponent(TEST_SOURCE_SITE_NAME) + "/" + TEST_SOURCE_FIXLET_ID,
    null,
    function(err, status, body) {
      if (err) { done(new Error("GET failed: " + err)); return; }
      var elapsed = Date.now() - t0;
      try {
        assertEqual(status, 200, "GET source fixlet status");
        assert(elapsed < 30000, "GET source fixlet must complete in < 30s (NFR-01); elapsed=" + elapsed + "ms");
        done(null);
      } catch (ex) {
        done(ex);
      }
    }
  );
}

/**
 * GROUP B Test 2: GET portal fixlet returns 200
 * Verifies that a portal fixlet is readable via the BigFix REST API and that
 * the response body contains a Fixlet or Task element.
 *
 * Requires: BIGFIX_AVAILABLE, TEST_PORTAL_FIXLET_ID
 */
function testGroupB_getPortalFixlet(done) {
  if (!BIGFIX_AVAILABLE) {
    var skipErr = new Error("BIGFIX env not set (BIGFIX_URL, BIGFIX_USER, BIGFIX_TOKEN required)");
    skipErr.isSkip = true;
    return done(skipErr);
  }
  if (!TEST_PORTAL_FIXLET_ID) {
    var skipErr2 = new Error("TEST_PORTAL_FIXLET_ID not set");
    skipErr2.isSkip = true;
    return done(skipErr2);
  }
  apiRequest(
    "GET",
    "fixlet/custom/" + encodeURIComponent(TEST_TARGET_SITE) + "/" + TEST_PORTAL_FIXLET_ID,
    null,
    function(err, status, body) {
      if (err) { done(new Error("GET failed: " + err)); return; }
      try {
        assertEqual(status, 200, "GET portal fixlet status");
        assert(
          body.indexOf("<Fixlet>") >= 0 || body.indexOf("<Task>") >= 0,
          "Response must contain Fixlet or Task element"
        );
        done(null);
      } catch (ex) {
        done(ex);
      }
    }
  );
}

// =============================================================================
// SECTION 6 -- Run all tests and summarise
// =============================================================================

console.log("");
console.log("Integration tests -- fixlet_update_tracker.ojo BigFix API patterns");
console.log("BigFix URL: " + (BIGFIX_URL || "(not set)"));
console.log("-----------------------------------------------------------");
console.log("");

// --------------------------------------------------------------------------
// GROUP A: Fixture structure tests (synchronous -- always run)
// --------------------------------------------------------------------------

console.log("[ GROUP A: Fixture structure tests -- no BigFix connectivity required ]");
console.log("");

runTest("portal-fixlet-with-roles.xml has version v26.01 in title", function() {
  var xml = fs.readFileSync(
    path.join(__dirname, "..", "fixtures", "phase-06", "portal-fixlet-with-roles.xml"), "utf8"
  );
  assert(xml.indexOf("v26.01") >= 0, "Expected v26.01 in portal fixlet title");
});

runTest("portal-fixlet-with-roles.xml has Associated_Roles MIMEField", function() {
  var xml = fs.readFileSync(
    path.join(__dirname, "..", "fixtures", "phase-06", "portal-fixlet-with-roles.xml"), "utf8"
  );
  assert(xml.indexOf("<Name>Associated_Roles</Name>") >= 0, "Expected Associated_Roles MIMEField");
  assert(xml.indexOf("IT Support|General Access") >= 0, "Expected role value IT Support|General Access");
});

runTest("source-fixlet-new-version.xml has version v26.02 and category Utilities", function() {
  var srcXml = fs.readFileSync(
    path.join(__dirname, "..", "fixtures", "phase-06", "source-fixlet-new-version.xml"), "utf8"
  );
  assert(srcXml.indexOf("v26.02") >= 0, "Expected v26.02 in source fixlet title");
  assert(srcXml.indexOf("<Category>Utilities</Category>") >= 0, "Expected Utilities category in source");
  assert(srcXml.indexOf("Associated_Roles") < 0, "Source fixlet must NOT have Associated_Roles MIMEField");
});

runTest("expected-copy-output.xml: source title + portal category + portal roles", function() {
  var copyXml = fs.readFileSync(
    path.join(__dirname, "..", "fixtures", "phase-06", "expected-copy-output.xml"), "utf8"
  );
  assert(copyXml.indexOf("v26.02") >= 0, "Expected source version v26.02 in copy output title");
  assert(copyXml.indexOf("File Management") >= 0, "Expected portal category in copy output (D-16)");
  assert(copyXml.indexOf("Utilities") < 0, "Copy output must NOT have source category Utilities (D-16)");
  assert(copyXml.indexOf("IT Support|General Access") >= 0, "Expected portal roles in copy output (D-17)");
});

runTest("expected-superseded-output.xml: portal title + X-Superseded-By before Domain", function() {
  var supXml = fs.readFileSync(
    path.join(__dirname, "..", "fixtures", "phase-06", "expected-superseded-output.xml"), "utf8"
  );
  assert(supXml.indexOf("v26.01") >= 0, "Expected original portal title v26.01 in superseded output");
  assert(supXml.indexOf("<Name>X-Superseded-By</Name>") >= 0, "Expected X-Superseded-By MIMEField (D-08)");
  assert(supXml.indexOf("<Value>99999</Value>") >= 0, "Expected newFixletId 99999 as X-Superseded-By value");
  var xsIdx = supXml.indexOf("X-Superseded-By");
  var domIdx = supXml.indexOf("<Domain>BESC</Domain>");
  assert(xsIdx < domIdx, "X-Superseded-By MIMEField must appear BEFORE <Domain> in superseded output");
});

runTest("expected-copy-output.xml: MIMEField appears before Domain", function() {
  var copyXml = fs.readFileSync(
    path.join(__dirname, "..", "fixtures", "phase-06", "expected-copy-output.xml"), "utf8"
  );
  assert(
    copyXml.indexOf("Associated_Roles") < copyXml.indexOf("<Domain>BESC</Domain>"),
    "Associated_Roles MIMEField must appear before <Domain> in copy output"
  );
});

console.log("");

// --------------------------------------------------------------------------
// GROUP B: BIGFIX-gated API round-trip tests (async)
// --------------------------------------------------------------------------

console.log("[ GROUP B: BIGFIX-gated API round-trip tests ]");
console.log("");

runAsyncTest("GET source fixlet returns 200 (NFR-01 timing)", testGroupB_getSourceFixlet)
  .then(function() {
    return runAsyncTest("GET portal fixlet returns 200", testGroupB_getPortalFixlet);
  })
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
