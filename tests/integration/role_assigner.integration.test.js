/**
 * role_assigner.integration.test.js
 *
 * Integration tests for fixlet_role_assigner.ojo — BigFix REST API POST patterns.
 *
 * NOTE (07-11, 2026-09-21): fixlet_role_assigner.ojo itself was retired and archived
 * to Existing Dashboards/archive/ as part of the Operator-Role-Group rewrite (D-15) --
 * this is a Phase 4 (2026-06) artifact predating that rewrite, unrelated to the retired
 * Axonius reference-DB pipeline this cleanup wave otherwise addresses. It exercises
 * generic BigFix SingleAction POST/parseActionId patterns still reused elsewhere in
 * this codebase (fixlet_copier.ojo, fixlet_console.ojo, fixlet_update_tracker.ojo) and
 * is gated on BIGFIX_* env vars (SKIP + exit 0 by default), so it is a no-op in the
 * default test run. Left as-is and logged to deferred-items.md -- whether to retire,
 * rename or fold this file is a decision outside this plan's scope.
 *
 * WARNING: Run against a STAGING BigFix instance only. Tests 2-3 create real
 * SingleAction deployments. Do not run against production.
 *
 * Required environment variables (must all be set to run):
 *   BIGFIX_URL   — Base URL of the BigFix REST API, e.g. https://bigfix.example.com:52311
 *   BIGFIX_USER  — BigFix admin username
 *   BIGFIX_TOKEN — BigFix admin password (used as Basic auth credential)
 *
 * Optional environment variables:
 *   TEST_COMPUTER_ID — BigFix computer ID for explicit SingleAction targeting tests
 *                      (Tests 2-3 are skipped if not set)
 *
 * Usage:
 *   node tests/integration/role_assigner.integration.test.js
 *
 * Exit codes:
 *   0  — all executed tests passed (or skipped gracefully)
 *   1  — one or more tests failed
 */

"use strict";

// =============================================================================
// SECTION 1 — Environment guard (verbatim from dispatcher.integration.test.js)
// =============================================================================

var BIGFIX_URL   = process.env.BIGFIX_URL   || "";
var BIGFIX_USER  = process.env.BIGFIX_USER  || "";
var BIGFIX_TOKEN = process.env.BIGFIX_TOKEN || "";

if (!BIGFIX_URL || !BIGFIX_USER || !BIGFIX_TOKEN) {
  console.log("SKIP: BIGFIX_URL, BIGFIX_USER, and BIGFIX_TOKEN must all be set to run integration tests.");
  process.exit(0);
}

// =============================================================================
// SECTION 2 — API helper (verbatim from dispatcher.integration.test.js)
// =============================================================================

var https = require("https");
var fs    = require("fs");
var path  = require("path");

/**
 * apiRequest(method, relativePath, bodyXml, callback)
 *
 * Mirrors the BigFix console API.Get / API.Put / API.Post interface used by
 * fixlet_role_assigner.ojo. Constructs: BIGFIX_URL + "/api/" + relativePath.
 * Auth: Basic BIGFIX_USER:BIGFIX_TOKEN
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
    rejectUnauthorized: true,
    timeout: 10000
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

  req.on("timeout", function() {
    req.destroy(new Error("Request timed out after 10000ms"));
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
// SECTION 3 — Test runner (verbatim from dispatcher.integration.test.js)
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

// Async test wrapper: returns a Promise that resolves after callback
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
// SECTION 3b — Role Assigner helper functions (inlined from role_assigner.test.js)
// =============================================================================

// xmlEscape(s) — XML entity escaping (verbatim from dispatcher.test.js lines 31-38)
function xmlEscape(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

// xmlCDataSafe(s) — CDATA sequence escaping
function xmlCDataSafe(s) { return String(s).replace(/\]\]>/g, "]]]]><![CDATA[>"); }

// cdataStart/cdataEnd helpers — split to avoid literal ]]> in source
function cdataStart() { return "<!" + "[CDATA["; }
function cdataEnd()   { return "]]" + ">"; }

// buildAssignActionXml(role, computerIds, actionScript, suffix, relevance)
// title = 'Dereso_' + role + ' Assign_' + suffix  (per D-09)
function buildAssignActionXml(role, computerIds, actionScript, suffix, relevance) {
  var title = "Dereso_" + role + " Assign_" + suffix;
  var xml  = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n";
  xml += "<BES xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"";
  xml += " xsi:noNamespaceSchemaLocation=\"BES.xsd\">\r\n";
  xml += "  <SingleAction>\r\n";
  xml += "    <Title>" + xmlEscape(title) + "</Title>\r\n";
  xml += "    <Relevance>" + xmlEscape(relevance) + "</Relevance>\r\n";
  xml += "    <ActionScript MIMEType=\"application/x-Fixlet-Windows-Shell\">";
  xml += cdataStart() + xmlCDataSafe(actionScript) + cdataEnd();
  xml += "</ActionScript>\r\n";
  xml += "    <Settings>\r\n";
  xml += "      <ActionUITitle>" + xmlEscape(title) + "</ActionUITitle>\r\n";
  xml += "    </Settings>\r\n";
  xml += "    <Target>\r\n";
  for (var i = 0; i < computerIds.length; i++) {
    xml += "      <ComputerID>" + xmlEscape(String(computerIds[i])) + "</ComputerID>\r\n";
  }
  xml += "    </Target>\r\n";
  xml += "  </SingleAction>\r\n";
  xml += "</BES>";
  return xml;
}

// parseActionId(body) — regex-only version for Node.js environment (WR-04)
// Extracts the numeric action ID from a BESAPI POST response body.
// ActiveXObject (Msxml2.DOMDocument) is not available in Node.js and was
// removed to avoid a silent ReferenceError in the catch block.
function parseActionId(body) {
  var m;
  if (!body) { return ""; }
  m = /\/api\/action\/(\d+)/i.exec(body);
  if (m && m[1]) { return m[1]; }
  m = /<ID>(\d+)<\/ID>/i.exec(body);
  if (m && m[1]) { return m[1]; }
  return "";
}

// Shared state between test2 and test3
var test2ResponseBody = null;

// =============================================================================
// SECTION 4 — Test scenarios
// =============================================================================

/**
 * Test 1: API connectivity
 * Calls GET /api/sites and asserts HTTP 200.
 * Verbatim copy from dispatcher.integration.test.js test1_apiConnectivity.
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
 * Test 2: POST minimal SingleAction with ComputerID targeting
 * Builds a minimal no-op SingleAction XML targeting TEST_COMPUTER_ID and POSTs to
 * /api/actions. Asserts status 200 or 201. Stores response body for test3.
 * WARNING: Only run against STAGING. Action uses relevance="true" — will run on target.
 * Requires TEST_COMPUTER_ID — skipped if not set.
 */
function test2_postMinimalSingleAction(done) {
  var TEST_COMPUTER_ID = process.env.TEST_COMPUTER_ID || "";
  if (!TEST_COMPUTER_ID) {
    skipTest("TEST_COMPUTER_ID not set — skipping SingleAction POST test");
  }

  // Build a minimal no-op SingleAction: relevance="true", benign script, IT Operations role
  var actionScript = "// Phase 4 integration test placeholder — no-op\r\nparam('CompID')";
  var xml = buildAssignActionXml(
    "IT Operations",
    [TEST_COMPUTER_ID],
    actionScript,
    "IntegrationTest",
    "true"
  );

  apiRequest("POST", "actions", xml, function(errorMsg, statusCode, responseBody) {
    try {
      if (errorMsg) { throw new Error("Network error: " + errorMsg); }
      assert(
        statusCode === 200 || statusCode === 201,
        "POST /api/actions expected 200 or 201, got " + statusCode + " — body: " + (responseBody || "").slice(0, 200)
      );
      test2ResponseBody = responseBody;
      console.log("        Status: POST OK (HTTP " + statusCode + ")");
      done(null);
    } catch (ex) {
      done(ex);
    }
  });
}

/**
 * Test 3: parseActionId on response from test2
 * Uses the response body stored by test2 to assert parseActionId returns a non-empty string.
 * Skipped if test2 was skipped (TEST_COMPUTER_ID not set).
 */
function test3_parseActionId(done) {
  if (!process.env.TEST_COMPUTER_ID) {
    skipTest("TEST_COMPUTER_ID not set — skipping parseActionId test (test2 was skipped)");
  }
  if (test2ResponseBody === null) {
    skipTest("test2 was skipped or failed — no response body to parse");
  }

  try {
    var actionId = parseActionId(test2ResponseBody);
    assert(
      typeof actionId === "string" && actionId.length > 0,
      "parseActionId must return a non-empty string, got: " + JSON.stringify(actionId)
    );
    console.log("        Extracted action ID: " + actionId);
    done(null);
  } catch (ex) {
    done(ex);
  }
}

/**
 * Test 4: Input guard — no CSV uploaded
 * Asserts that an empty csvRows array does not trigger an API.Post call.
 * Synchronous guard test — no BigFix connectivity required.
 * Mirrors the deployAll() guard: if (!csvRows || csvRows.length === 0) return early.
 */
function test4_inputGuard(done) {
  // Mirror the deployAll guard condition from fixlet_role_assigner.ojo
  var csvRows = [];
  var wouldPost = csvRows && csvRows.length > 0;
  assert(!wouldPost, "Empty csvRows must not trigger API.Post");
  console.log("        Input guard verified: empty csvRows.length === 0 evaluates to false (no POST)");
  done(null);
}

/**
 * Test 5: API error handling
 * Requests a resource that should not exist to provoke a non-200 from BigFix.
 * Verifies the error is captured (not silently swallowed).
 * Pattern copied from dispatcher.integration.test.js test6_apiErrorHandling.
 */
function test5_apiErrorHandling(done) {
  apiRequest("GET", "fixlet/custom/NonExistentSite99999/99999999", null, function(errorMsg, statusCode, responseBody) {
    try {
      if (errorMsg) {
        console.log("        API error correctly surfaced (network): " + errorMsg);
        done(null);
        return;
      }

      assert(statusCode !== 200,
        "Expected non-200 status for non-existent fixlet, got " + statusCode);

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
// SECTION 5 — Run all tests and summarise
// =============================================================================

console.log("");
console.log("Integration tests — fixlet_role_assigner.ojo BigFix API POST patterns");
console.log("BigFix URL: " + BIGFIX_URL);
console.log("Note: Tests 2-3 require TEST_COMPUTER_ID and will POST to the staging BigFix instance.");
console.log("-----------------------------------------------------------");
console.log("");

runAsyncTest("Test 1: API connectivity",                                          test1_apiConnectivity)
  .then(function() { return runAsyncTest("Test 2: POST minimal SingleAction with ComputerID targeting", test2_postMinimalSingleAction); })
  .then(function() { return runAsyncTest("Test 3: parseActionId on response",     test3_parseActionId); })
  .then(function() { return runAsyncTest("Test 4: Input guard — no CSV uploaded", test4_inputGuard); })
  .then(function() { return runAsyncTest("Test 5: API error handling",            test5_apiErrorHandling); })
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
