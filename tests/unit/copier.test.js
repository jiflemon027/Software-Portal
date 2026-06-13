/**
 * copier.test.js
 *
 * Unit tests for the 6 pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_copier.ojo
 *
 * Functions covered:
 *   1. xmlEscape(s)                   — XML entity escaping
 *   2. xmlCDataSafe(s)                — CDATA sequence escaping
 *   3. buildRelevanceXml(text)        — multi-line relevance XML builder
 *   4. parseCreatedId(body)           — BigFix API response ID extraction (regex paths only)
 *   5. getNodeText(xml, tag)          — IE DOM node text reader
 *   6. getAllNodeText(xml, tag)        — IE DOM multi-node text reader
 *   7. applySortToCurrentItems()      — numeric/lexicographic sort
 *
 * Running: node tests/unit/copier.test.js
 * Requirements: Node.js built-in `assert` module only (no external packages).
 *
 * Source line references are from fixlet_copier.ojo.
 */

"use strict";

var assert = require("assert");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim from fixlet_copier.ojo)
// ---------------------------------------------------------------------------

// Lines 577-584: XML entity escaping
function xmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;")
    .replace(/'/g,"&apos;");
}

// Line 588: CDATA sequence escaping
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }

// Lines 648-658: multi-line relevance builder
function buildRelevanceXml(text){
  var lines = String(text).split(/\r?\n/);
  var out = "";
  for(var i=0;i<lines.length;i++){
    if(String(lines[i]).replace(/^\s+|\s+$/g,"")!==""){
      out += "<Relevance>" + xmlEscape(lines[i]) + "</Relevance>";
    }
  }
  if(out===""){ out = "<Relevance>true</Relevance>"; }
  return out;
}

// Lines 365-405: BigFix API response ID extraction.
//   The ActiveXObject block (IE-only) is retained in a try/catch so the function
//   silently falls through to the regex-fallback paths when run in Node.js.
//   Unit tests exercise ONLY the regex paths (T-01-02-02 mitigation).
function parseCreatedId(body){
  var xml, nodes, txt, m;
  if(!body){ return ""; }

  try{
    // ActiveXObject is IE-console-only; throws in Node.js — caught silently below.
    xml = new ActiveXObject("Msxml2.DOMDocument.6.0"); // jshint ignore:line
    xml.async = false;
    xml.loadXML(body);

    nodes = xml.getElementsByTagName("Fixlet");
    if(nodes.length>0){
      txt = nodes[0].getAttribute("ID");
      if(txt && txt !== ""){ return txt; }
      txt = nodes[0].getAttribute("Resource");
      if(txt && txt !== ""){
        m = /\/([^\/]+)$/.exec(txt);
        if(m && m[1]){ return m[1]; }
      }
    }

    nodes = xml.getElementsByTagName("Task");
    if(nodes.length>0){
      txt = nodes[0].getAttribute("ID");
      if(txt && txt !== ""){ return txt; }
      txt = nodes[0].getAttribute("Resource");
      if(txt && txt !== ""){
        m = /\/([^\/]+)$/.exec(txt);
        if(m && m[1]){ return m[1]; }
      }
    }
  } catch(ex) { /* ActiveXObject not available — fall through to regex paths */ }

  m = /fixlet\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
  if(m && m[1]){ return m[1]; }
  m = /task\/(?:custom|operator|external|master)\/[^\/]+\/(\d+)/i.exec(body);
  if(m && m[1]){ return m[1]; }
  m = /\bID=["']?(\d+)["']?/i.exec(body);
  if(m && m[1]){ return m[1]; }

  return "";
}

// Lines 489-503: IE ActiveXObject DOM node readers.
//   n[0].text is the IE DOM .text property (not .textContent).
//   Unit tests supply a mock object via makeXmlMock() below.
function getNodeText(xml, tag){
  var n=xml.getElementsByTagName(tag);
  if(n.length>0){ return n[0].text || ""; }
  return "";
}

function getAllNodeText(xml, tag){
  var n=xml.getElementsByTagName(tag);
  var out="";
  for(var i=0;i<n.length;i++){
    if(i>0){ out+="\r\n"; }
    out += (n[i].text || "");
  }
  return out;
}

// Lines 76-93: Sort logic.
//   Original function reads from module globals (currentItems, sortColumn, sortAsc).
//   Approach used here: inject state via outer-scope variables set before each test,
//   matching the original signature so tests validate the real implementation path.
//   (Approach B: module-level test variables set before each call)
var currentItems = [];   // test-controlled injection — matches original global name
var sortColumn   = "";   // test-controlled injection — matches original global name
var sortAsc      = true; // test-controlled injection — matches original global name

function applySortToCurrentItems(){
  if(sortColumn === ""){ return; }
  var col = sortColumn;
  var asc = sortAsc;
  currentItems.sort(function(a, b){
    var va, vb, na, nb;
    if(col === "id"){
      na = parseInt(String(a[col] || ""), 10) || 0;
      nb = parseInt(String(b[col] || ""), 10) || 0;
      return asc ? na - nb : nb - na;
    }
    va = String(a[col] || "").toLowerCase();
    vb = String(b[col] || "").toLowerCase();
    if(va < vb){ return asc ? -1 : 1; }
    if(va > vb){ return asc ? 1 : -1; }
    return 0;
  });
}

// ---------------------------------------------------------------------------
// 2. TEST INFRASTRUCTURE
// ---------------------------------------------------------------------------

/**
 * makeXmlMock(tagMap)
 *
 * Returns a minimal mock of the IE ActiveXObject XML DOM used by getNodeText
 * and getAllNodeText. tagMap maps tag name → array of text-content strings.
 *
 * Example:
 *   var mock = makeXmlMock({ Title: ["My Fixlet"], Relevance: ["line1","line2"] });
 *   getNodeText(mock, "Title")       // "My Fixlet"
 *   getAllNodeText(mock, "Relevance") // "line1\r\nline2"
 */
function makeXmlMock(tagMap){
  return {
    getElementsByTagName: function(tag){
      var texts = tagMap[tag] || [];
      return texts.map(function(t){ return { text: t }; });
    }
  };
}

var passed  = 0;
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

// --- 3.1 xmlEscape ---
section("xmlEscape");

expect("escapes ampersand", function(){
  assert.strictEqual(xmlEscape("&"), "&amp;");
});
expect("escapes less-than", function(){
  assert.strictEqual(xmlEscape("<"), "&lt;");
});
expect("escapes greater-than", function(){
  assert.strictEqual(xmlEscape(">"), "&gt;");
});
expect("escapes double-quote", function(){
  assert.strictEqual(xmlEscape('"'), "&quot;");
});
expect("escapes single-quote", function(){
  assert.strictEqual(xmlEscape("'"), "&apos;");
});
expect("escapes all five characters in one string", function(){
  assert.strictEqual(
    xmlEscape('a&b<c>d"e\'f'),
    "a&amp;b&lt;c&gt;d&quot;e&apos;f"
  );
});
expect("empty string returns empty string", function(){
  assert.strictEqual(xmlEscape(""), "");
});
expect("non-string number is coerced — no throw", function(){
  var result;
  try{
    result = xmlEscape(123);
  } catch(e){
    assert.fail("xmlEscape(123) threw: " + e.message);
  }
  assert.strictEqual(result, "123");
});

// --- 3.2 xmlCDataSafe ---
section("xmlCDataSafe");

expect("replaces ]]> with split CDATA sequence", function(){
  assert.strictEqual(
    xmlCDataSafe("hello]]>world"),
    "hello]]]]><![CDATA[>world"
  );
});
expect("string without ]]> is unchanged", function(){
  assert.strictEqual(xmlCDataSafe("no cdata here"), "no cdata here");
});
expect("empty string returns empty string", function(){
  assert.strictEqual(xmlCDataSafe(""), "");
});
expect("multiple ]]> occurrences are all replaced", function(){
  assert.strictEqual(
    xmlCDataSafe("a]]>b]]>c"),
    "a]]]]><![CDATA[>b]]]]><![CDATA[>c"
  );
});

// --- 3.3 buildRelevanceXml ---
section("buildRelevanceXml");

expect("single non-empty line wrapped in Relevance element", function(){
  assert.strictEqual(
    buildRelevanceXml("windows of bes computers"),
    "<Relevance>windows of bes computers</Relevance>"
  );
});
expect("two lines produce two Relevance elements", function(){
  assert.strictEqual(
    buildRelevanceXml("line1\nline2"),
    "<Relevance>line1</Relevance><Relevance>line2</Relevance>"
  );
});
expect("CRLF line ending also splits correctly", function(){
  assert.strictEqual(
    buildRelevanceXml("line1\r\nline2"),
    "<Relevance>line1</Relevance><Relevance>line2</Relevance>"
  );
});
expect("empty string defaults to <Relevance>true</Relevance>", function(){
  assert.strictEqual(buildRelevanceXml(""), "<Relevance>true</Relevance>");
});
expect("whitespace-only line skipped — result defaults to true", function(){
  assert.strictEqual(buildRelevanceXml("   "), "<Relevance>true</Relevance>");
});
expect("blank line between two non-blank lines is skipped", function(){
  assert.strictEqual(
    buildRelevanceXml("line1\n   \nline2"),
    "<Relevance>line1</Relevance><Relevance>line2</Relevance>"
  );
});
expect("special XML chars inside relevance text are entity-escaped", function(){
  assert.strictEqual(
    buildRelevanceXml('name of it = "test"'),
    '<Relevance>name of it = &quot;test&quot;</Relevance>'
  );
});

// --- 3.4 parseCreatedId (regex paths only) ---
section("parseCreatedId");

expect("fixlet/custom/ URL path -> extracts numeric ID", function(){
  assert.strictEqual(
    parseCreatedId("fixlet/custom/MySite/12345"),
    "12345"
  );
});
expect("fixlet/operator/ URL path -> extracts numeric ID", function(){
  assert.strictEqual(
    parseCreatedId("fixlet/operator/MySite/999"),
    "999"
  );
});
expect("task/operator/ URL path -> extracts numeric ID", function(){
  assert.strictEqual(
    parseCreatedId("task/operator/MySite/99"),
    "99"
  );
});
expect("task/custom/ URL path -> extracts numeric ID", function(){
  assert.strictEqual(
    parseCreatedId("task/custom/AnotherSite/7"),
    "7"
  );
});
expect('ID="456" attribute pattern -> extracts ID', function(){
  assert.strictEqual(parseCreatedId('ID="456"'), "456");
});
expect("ID=789 (no quotes) -> extracts ID", function(){
  assert.strictEqual(parseCreatedId("ID=789"), "789");
});
expect("ID='101' (single quotes) -> extracts ID", function(){
  assert.strictEqual(parseCreatedId("ID='101'"), "101");
});
expect("empty string -> returns empty string", function(){
  assert.strictEqual(parseCreatedId(""), "");
});
expect("body with no matching pattern -> returns empty string", function(){
  assert.strictEqual(
    parseCreatedId("no relevant content here at all"),
    ""
  );
});
expect("null/undefined body -> returns empty string", function(){
  assert.strictEqual(parseCreatedId(null), "");
  assert.strictEqual(parseCreatedId(undefined), "");
});

// --- 3.5 getNodeText / getAllNodeText ---
section("getNodeText / getAllNodeText");

expect("getNodeText: present tag returns text", function(){
  var mock = makeXmlMock({ Title: ["My Fixlet"] });
  assert.strictEqual(getNodeText(mock, "Title"), "My Fixlet");
});
expect("getNodeText: missing tag returns empty string", function(){
  var mock = makeXmlMock({});
  assert.strictEqual(getNodeText(mock, "Missing"), "");
});
expect("getNodeText: node with empty text returns empty string", function(){
  var mock = makeXmlMock({ Title: [""] });
  assert.strictEqual(getNodeText(mock, "Title"), "");
});
expect("getAllNodeText: multiple tags joined by CRLF", function(){
  var mock = makeXmlMock({ Relevance: ["line1", "line2"] });
  assert.strictEqual(getAllNodeText(mock, "Relevance"), "line1\r\nline2");
});
expect("getAllNodeText: single element returns text without CRLF", function(){
  var mock = makeXmlMock({ Relevance: ["only line"] });
  assert.strictEqual(getAllNodeText(mock, "Relevance"), "only line");
});
expect("getAllNodeText: missing tag returns empty string", function(){
  var mock = makeXmlMock({});
  assert.strictEqual(getAllNodeText(mock, "Relevance"), "");
});
expect("getAllNodeText: three elements joined with two CRLFs", function(){
  var mock = makeXmlMock({ Relevance: ["a", "b", "c"] });
  assert.strictEqual(getAllNodeText(mock, "Relevance"), "a\r\nb\r\nc");
});

// --- 3.6 applySortToCurrentItems ---
section("applySortToCurrentItems");

expect("sort by id ascending (numeric, not lexicographic)", function(){
  currentItems = [{ id: "10", name: "b" }, { id: "2", name: "a" }];
  sortColumn = "id";
  sortAsc = true;
  applySortToCurrentItems();
  assert.deepStrictEqual(
    currentItems.map(function(i){ return i.id; }),
    ["2", "10"]
  );
});
expect("sort by id descending", function(){
  currentItems = [{ id: "2", name: "a" }, { id: "10", name: "b" }];
  sortColumn = "id";
  sortAsc = false;
  applySortToCurrentItems();
  assert.deepStrictEqual(
    currentItems.map(function(i){ return i.id; }),
    ["10", "2"]
  );
});
expect("sort by name ascending (lexicographic)", function(){
  currentItems = [{ id: "10", name: "Banana" }, { id: "2", name: "apple" }];
  sortColumn = "name";
  sortAsc = true;
  applySortToCurrentItems();
  assert.deepStrictEqual(
    currentItems.map(function(i){ return i.name; }),
    ["apple", "Banana"]
  );
});
expect("sort by name descending", function(){
  currentItems = [{ id: "2", name: "apple" }, { id: "10", name: "Banana" }];
  sortColumn = "name";
  sortAsc = false;
  applySortToCurrentItems();
  assert.deepStrictEqual(
    currentItems.map(function(i){ return i.name; }),
    ["Banana", "apple"]
  );
});
expect("sortColumn empty string — array unchanged", function(){
  currentItems = [{ id: "10", name: "b" }, { id: "2", name: "a" }];
  sortColumn = "";
  sortAsc = true;
  applySortToCurrentItems();
  // Order must be unmodified
  assert.strictEqual(currentItems[0].id, "10");
  assert.strictEqual(currentItems[1].id, "2");
});
expect("numeric sort: string id values parsed as integers (no string-compare '10' < '2')", function(){
  currentItems = [
    { id: "10" },
    { id: "9"  },
    { id: "100" },
    { id: "2"  }
  ];
  sortColumn = "id";
  sortAsc = true;
  applySortToCurrentItems();
  assert.deepStrictEqual(
    currentItems.map(function(i){ return i.id; }),
    ["2", "9", "10", "100"]
  );
});
expect("missing id field defaults to 0 for numeric sort", function(){
  currentItems = [{ id: "5" }, { name: "no-id" }, { id: "3" }];
  sortColumn = "id";
  sortAsc = true;
  applySortToCurrentItems();
  // missing id becomes 0 — sorts first ascending
  assert.strictEqual(currentItems[0].name, "no-id");
});

// ---------------------------------------------------------------------------
// 4. SUMMARY FOOTER
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
