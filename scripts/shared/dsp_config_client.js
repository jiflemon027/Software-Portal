// dsp_config_client.js -- v1.0.1 (shared by fixlet_console.ojo and fixlet_role_manager.ojo)
// Source of truth for the shared-config block. Copied verbatim into both dashboards
// between the BEGIN/END SHARED DSP_CONFIG_CLIENT markers by
//   node scripts/sync_shared_config_client.js
// Never edit the copies inside the .ojo files.
//
// The config lives in ONE site file, dsp_config.json, in DSP_CONFIG_SITE. It is read live
// over REST (GET site/custom/<site>/file/<id>) so edits apply on "Reload config" without
// waiting for the console to gather a new site version. The dashboards never write it:
// writing site-file content over REST did not work on this server (2026-11-17), so the
// admin uploads it by hand (console: Manage Site Files) -- see config/dsp_config.json.
// Role Manager > Settings > Generate JSON produces the full file text to upload.
//
// ES5 only (dashboards run in the console's IE9-mode engine). JSON.parse/stringify exist there.

var DSP_CONFIG_SITE = "Dereso Software Portal";
var DSP_CONFIG_FILE = "dsp_config.json";

// What was loaded, for the UI and for the optimistic-concurrency check on save.
var DSP_CONFIG_STATE = { source: "defaults", fileId: null, rawText: null, raw: null, error: "", warnings: [] };

// -- pure helpers (unit-tested) ------------------------------------------------

function dspTrim(s){ return String(s == null ? "" : s).replace(/^\s+|\s+$/g, ""); }

// Characters that would break titles, relevance strings or the Analysis row parsing
// ("UserID, Role" is split on the first ", ") if they appeared in a role name.
var DSP_ROLE_FORBIDDEN = /[",|\u001f\\]/;

// dspCleanList(value, label, forbidden, warnings) -> array or null (null = invalid, use default)
function dspCleanList(value, label, forbidden, warnings){
  if(Object.prototype.toString.call(value) !== "[object Array]"){
    warnings.push(label + " is not a list -- using built-in default.");
    return null;
  }
  var out = [], seen = {}, i, v;
  for(i = 0; i < value.length; i++){
    if(typeof value[i] !== "string"){ warnings.push(label + ": ignored a non-text entry."); continue; }
    v = dspTrim(value[i]);
    if(v === ""){ continue; }
    if(forbidden && forbidden.test(v)){ warnings.push(label + ": ignored \"" + v + "\" (contains a forbidden character: \" , | \\)."); continue; }
    if(seen[v.toLowerCase()]){ continue; }
    seen[v.toLowerCase()] = true;
    out.push(v);
  }
  if(out.length === 0){ warnings.push(label + " is empty -- using built-in default."); return null; }
  return out;
}

// dspNormalizeConfig(obj, defaults) -> { config, warnings }
// config always has every key of defaults; any missing/invalid field falls back to the
// default with a warning. Unknown keys in obj are ignored here (but kept for saving --
// see dspMergeForSave).
function dspNormalizeConfig(obj, defaults){
  var warnings = [];
  var d = defaults || {};
  var o = (obj && typeof obj === "object") ? obj : {};
  var cfg = {};
  var list;

  list = (o.roles === undefined) ? null : dspCleanList(o.roles, "roles", DSP_ROLE_FORBIDDEN, warnings);
  cfg.roles = list || (d.roles || []).slice();

  list = (o.categories === undefined) ? null : dspCleanList(o.categories, "categories", null, warnings);
  cfg.categories = list || (d.categories || []).slice();

  cfg.categoryMap = {};
  var srcMap = o.categoryMap, k;
  if(srcMap !== undefined && (typeof srcMap !== "object" || srcMap === null || Object.prototype.toString.call(srcMap) === "[object Array]")){
    warnings.push("categoryMap is not an object -- using built-in default.");
    srcMap = undefined;
  }
  if(srcMap === undefined){ srcMap = d.categoryMap || {}; }
  for(k in srcMap){
    if(!srcMap.hasOwnProperty(k)){ continue; }
    if(typeof srcMap[k] !== "string" || dspTrim(k) === "" || dspTrim(srcMap[k]) === ""){ continue; }
    cfg.categoryMap[dspTrim(k)] = dspTrim(srcMap[k]);
  }

  var dc = d.console || {};
  var oc = (o.console && typeof o.console === "object") ? o.console : {};
  cfg.console = {};
  cfg.console.defaultSiteName = (typeof oc.defaultSiteName === "string" && dspTrim(oc.defaultSiteName) !== "") ? dspTrim(oc.defaultSiteName) : (dc.defaultSiteName || "");
  list = (oc.sourceSites === undefined) ? null : dspCleanList(oc.sourceSites, "console.sourceSites", null, warnings);
  cfg.console.sourceSites = list || (dc.sourceSites || []).slice();
  var days = oc.defaultExpirationDays;
  if(days !== undefined && !(typeof days === "number" && days >= 1 && days <= 365 && Math.floor(days) === days)){
    warnings.push("console.defaultExpirationDays must be a whole number 1-365 -- using built-in default.");
    days = undefined;
  }
  cfg.console.defaultExpirationDays = (days !== undefined) ? days : dc.defaultExpirationDays;

  return { config: cfg, warnings: warnings };
}

// dspParseConfigText(text) -> { obj, error }
function dspParseConfigText(text){
  var t = String(text == null ? "" : text);
  if(t.charCodeAt(0) === 0xFEFF){ t = t.substring(1); } // strip a UTF-8 BOM
  if(dspTrim(t) === ""){ return { obj: null, error: "file is empty" }; }
  var obj;
  try { obj = JSON.parse(t); } catch(ex){ return { obj: null, error: "not valid JSON (" + (ex && ex.message ? ex.message : ex) + ")" }; }
  if(!obj || typeof obj !== "object" || Object.prototype.toString.call(obj) === "[object Array]"){
    return { obj: null, error: "top level must be a JSON object" };
  }
  return { obj: obj, error: "" };
}

// dspFindFileIdInListing(xml, name) -> "47815" | null   (GET site/custom/<site>/files response)
function dspFindFileIdInListing(xml, name){
  var re = /<SiteFile\b[\s\S]*?<\/SiteFile>/g, m, nm, id;
  var want = String(name).toLowerCase();
  while((m = re.exec(String(xml || ""))) !== null){
    nm = /<Name>([^<]*)<\/Name>/.exec(m[0]);
    id = /<ID>(\d+)<\/ID>/.exec(m[0]);
    if(nm && id && dspTrim(nm[1]).toLowerCase() === want){ return id[1]; }
  }
  return null;
}

// dspMergeForSave(rawObj, edited) -> object to write. Keeps every key the file already had
// (so one dashboard never drops another's settings), overwriting only what was edited.
function dspMergeForSave(rawObj, edited){
  var out = {}, k;
  var base = (rawObj && typeof rawObj === "object") ? rawObj : {};
  for(k in base){ if(base.hasOwnProperty(k)){ out[k] = base[k]; } }
  for(k in edited){ if(edited.hasOwnProperty(k)){ out[k] = edited[k]; } }
  return out;
}

function dspSerializeConfig(obj){ return JSON.stringify(obj, null, 2) + "\n"; }

// -- REST (not unit-tested; needs the console's API object) ---------------------

function dspSitePath(){ return "site/custom/" + encodeURIComponent(DSP_CONFIG_SITE); }

// dspFetchConfigText(cb) -- cb(err, text, fileId)
function dspFetchConfigText(cb){
  API.Get(dspSitePath() + "/files", function(e, s, b){
    if(s !== 200){ cb("could not list site files (status " + s + (e ? ", " + e : "") + ")"); return; }
    var id = dspFindFileIdInListing(b, DSP_CONFIG_FILE);
    if(!id){ cb(DSP_CONFIG_FILE + " not found in site \"" + DSP_CONFIG_SITE + "\""); return; }
    API.Get(dspSitePath() + "/file/" + id, function(e2, s2, b2){
      if(s2 !== 200){ cb("could not read " + DSP_CONFIG_FILE + " (status " + s2 + (e2 ? ", " + e2 : "") + ")", null, id); return; }
      cb(null, (b2 === undefined || b2 === null) ? "" : String(b2), id);
    });
  });
}

// dspLoadConfig(defaults, cb) -- cb(config, DSP_CONFIG_STATE). Never fails: on any error the
// built-in defaults are returned and DSP_CONFIG_STATE.error says why.
function dspLoadConfig(defaults, cb){
  dspFetchConfigText(function(err, text, fileId){
    DSP_CONFIG_STATE = { source: "defaults", fileId: fileId || null, rawText: null, raw: null, error: "", warnings: [] };
    if(err){
      DSP_CONFIG_STATE.error = err;
      cb(dspNormalizeConfig({}, defaults).config, DSP_CONFIG_STATE);
      return;
    }
    var parsed = dspParseConfigText(text);
    if(parsed.error){
      DSP_CONFIG_STATE.error = DSP_CONFIG_FILE + ": " + parsed.error;
      DSP_CONFIG_STATE.rawText = text;
      cb(dspNormalizeConfig({}, defaults).config, DSP_CONFIG_STATE);
      return;
    }
    var n = dspNormalizeConfig(parsed.obj, defaults);
    DSP_CONFIG_STATE.source = "file";
    DSP_CONFIG_STATE.rawText = text;
    DSP_CONFIG_STATE.raw = parsed.obj;
    DSP_CONFIG_STATE.warnings = n.warnings;
    cb(n.config, DSP_CONFIG_STATE);
  });
}

// dspConfigStatusText(state) -> one-line description for the UI.
function dspConfigStatusText(state){
  var st = state || DSP_CONFIG_STATE;
  if(st.source === "file"){
    return "Shared settings loaded from " + DSP_CONFIG_FILE + " (site file " + st.fileId + ")" +
      (st.warnings && st.warnings.length ? " with " + st.warnings.length + " warning(s): " + st.warnings.join(" ") : ".");
  }
  return "Using built-in defaults -- " + (st.error || "shared settings not loaded") + ".";
}
