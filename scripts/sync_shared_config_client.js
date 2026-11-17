// sync_shared_config_client.js -- v1.0.0
// Copies scripts/shared/dsp_config_client.js verbatim into both dashboards, between
//   // BEGIN SHARED DSP_CONFIG_CLIENT
//   // END SHARED DSP_CONFIG_CLIENT
// Run after editing the shared source:  node scripts/sync_shared_config_client.js
"use strict";
var fs = require("fs");
var path = require("path");

var ROOT   = path.join(__dirname, "..");
var SRC    = path.join(__dirname, "shared", "dsp_config_client.js");
var TARGETS = ["fixlet_console.ojo", "fixlet_role_manager.ojo"].map(function(f){
  return path.join(ROOT, "Existing Dashboards", f);
});
var BEGIN = "// BEGIN SHARED DSP_CONFIG_CLIENT";
var END   = "// END SHARED DSP_CONFIG_CLIENT";

var body = fs.readFileSync(SRC, "utf8").replace(/\r\n/g, "\n").replace(/\s+$/, "");
["]]>", "</script", "<?relevance"].forEach(function(bad){
  if(body.toLowerCase().indexOf(bad) >= 0){ throw new Error("shared source contains forbidden sequence " + bad); }
});
if(/[^\x00-\x7e]/.test(body)){ throw new Error("shared source must be ASCII-only"); }

TARGETS.forEach(function(t){
  var raw = fs.readFileSync(t, "utf8");
  var eol = raw.indexOf("\r\n") >= 0 ? "\r\n" : "\n";
  var b = raw.indexOf(BEGIN), e = raw.indexOf(END);
  if(b < 0 || e < b){ throw new Error("markers not found in " + t); }
  var block = (BEGIN + "\n" + body + "\n").replace(/\n/g, eol);
  fs.writeFileSync(t, raw.substring(0, b) + block + raw.substring(e), "utf8");
  console.log("synced " + path.basename(t));
});
