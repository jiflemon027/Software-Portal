// scripts/generate_category_map.js
//
// Build-time CSV → JS object generator for CATEGORY_MAP.
//
// Usage:
//   node scripts/generate_category_map.js
//
// Output: Prints `var CATEGORY_MAP = {...};` to stdout.
// Copy the output into fixlet_update_tracker.ojo in the PORTAL_CONFIG section.
//
// CSV: Dashboard_4_samples/software_categorized.csv
// Columns (0-indexed):
//   0 = No
//   1 = Software Installer   <- product name (key after version strip)
//   2 = Description
//   3 = Specific Category
//   4 = Shortlist Category   <- category value for the map
//
// Version strip regex: / v\d[\d.]+/g  (ONE-or-more after first digit)
// Rationale: avoids stripping product-name tokens like "v2" in
// "AWS Command Line Interface v2" (Pitfall 3 in 06-RESEARCH.md).
"use strict";
var fs   = require("fs");
var path = require("path");

var csvPath = path.join(__dirname, "..", "Dashboard_4_samples", "software_categorized.csv");
var rawCsv;
try {
  rawCsv = fs.readFileSync(csvPath, "utf8");
} catch (e) {
  console.error("ERROR: Cannot read CSV at " + csvPath + " — " + e.message);
  process.exit(1);
}
var lines = rawCsv.replace(/\r/g, "").split("\n");
var map   = {};

// Start at 1 to skip header row
for (var i = 1; i < lines.length; i++) {
  var line = lines[i].trim();
  if (!line) { continue; }
  // Simple split -- CSV has no quoted fields with internal commas (verified from file)
  var col = line.split(",");
  if (col.length < 5) { continue; }
  var rawName  = (col[1] || "").trim();
  var category = (col[4] || "").trim();
  // Strip version segment to derive lookup key (same regex as dashboard)
  // CRITICAL: use [\d.]+ (one-or-more) NOT [\d.]* (zero-or-more)
  var key = rawName.replace(/ v\d[\d.]+/g, "").trim();
  if (key && category) {
    map[key] = category;
  }
}

// CR-03 Part B: validate all emitted category values against the canonical portal list.
// These must match PORTAL_CONFIG.categories in fixlet_update_tracker.ojo exactly.
var PORTAL_CATEGORIES = [
  "Cloud & File Sync",
  "Communication & Conferencing",
  "Containers & DevOps",
  "Database & Data Tools",
  "Developer Tools",
  "File Management & Archiving",
  "Graphics & Image Editing",
  "Java Runtime & JDK",
  "Media & Entertainment",
  "Network Tools",
  "Office Suite & Writing",
  "PDF & Document Management",
  "Productivity & Organization",
  "Remote Access & Virtualization",
  "Security & Privacy",
  "System Utilities & Monitoring",
  "Video & Screen Recording",
  "Web Browser"
];

var validationErrors = [];
var seen = {};
for (var key in map) {
  if (Object.prototype.hasOwnProperty.call(map, key)) {
    var cat = map[key];
    if (PORTAL_CATEGORIES.indexOf(cat) === -1 && !seen[cat]) {
      seen[cat] = true;
      validationErrors.push("  Unknown category: " + JSON.stringify(cat) + " (key: " + JSON.stringify(key) + ")");
    }
  }
}
if (validationErrors.length > 0) {
  console.error("ERROR: CATEGORY_MAP contains values not in PORTAL_CONFIG.categories:");
  for (var vi = 0; vi < validationErrors.length; vi++) {
    console.error(validationErrors[vi]);
  }
  process.exit(1);
}

console.log("var CATEGORY_MAP = " + JSON.stringify(map, null, 2) + ";");
