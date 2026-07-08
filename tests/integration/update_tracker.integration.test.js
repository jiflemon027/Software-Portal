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
 */

"use strict";

// =============================================================================
// SECTION 1 -- Environment guard
// =============================================================================

var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: BIGFIX_URL, BIGFIX_USER, and BIGFIX_TOKEN must all be set to run integration tests.");
  process.exit(0);
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

// Wave 3 fills in: fixture structure assertions + BIGFIX-gated API round-trip tests

// =============================================================================
// SECTION 6 -- Run all tests and summarise
// =============================================================================

console.log("");
console.log("Integration tests -- fixlet_update_tracker.ojo BigFix API patterns");
console.log("BigFix URL: " + BIGFIX_URL);
console.log("-----------------------------------------------------------");
console.log("");

// No synchronous or async tests yet -- Wave 3 fills in test scenarios
var testPromises = [];

Promise.all(testPromises).then(function() {
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
}).catch(function(err) {
  console.error("Unexpected error in test runner: " + (err.message || String(err)));
  process.exit(1);
});
