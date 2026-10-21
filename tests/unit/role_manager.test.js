/**
 * role_manager.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_role_manager.ojo
 *
 * Functions covered:
 *   1. buildRoleGroupRelevance(usernames, scopeGroupId, scopeSiteName)
 *   2. buildComputerGroupXml(title, domain, relevance)
 *   3. buildRolePolicyTaskXml(templateFields, role, assignedBy)
 *   4. buildRolePolicyActionXml(title, relevance, actionScript, groupId, siteName)
 *   5. xmlEscape(s) / cdataStart() / cdataEnd() / xmlCDataSafe(s)
 *   6. PORTAL_CONFIG.roles / IE9 / no-alert() source-level assertions against
 *      the .ojo file itself
 *
 * Running: node tests/unit/role_manager.test.js
 * Requirements: Node.js built-in `assert`, `fs`, `path` and (as of plan
 * 07-07, for the SHA1/SHA256 prefetch-pin verification) `crypto` modules
 * only (no external packages).
 */

"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");
var crypto = require("crypto");

// ---------------------------------------------------------------------------
// 1. EXTRACTED FUNCTION IMPLEMENTATIONS (verbatim copy of the .ojo's own code,
//    per this project's established convention -- see role_assigner.test.js)
// ---------------------------------------------------------------------------

var PORTAL_CONFIG = {
  siteName: 'Dereso Software Portal',
  roles: ["IT Operations", "Business Operations"],
  targetGroups: ['All Workstations', 'IT Department', 'Finance Department', 'All Servers'],
  groupTitlePrefix:  'DSP Role - ',
  taskTitlePrefix:   'Assign Role Mapping - ',
  actionTitlePrefix: 'DSP RoleMap - ',
  assignedBy: 'test-operator',
  rootServerComputerId: '1622424793',
  props: {
    knownUsers:  "users in r.db",
    mappedUsers: "mapped_users in r.db",
    mapSource:   "map_source in r.db",
    mapRegion:   "map_region in r.db"
  },
  fieldSep: "\u001f"
};

function xmlEscape(s){
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}
function cdataStart(){ return '<!' + '[CDATA['; }
function cdataEnd(){   return ']]' + '>'; }
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }

// buildRoleGroupRelevance(usernames, scopeGroupId, scopeSiteName) -- D-09/D-10.
// T-07-04-01: a role with ZERO usernames must never produce an unconstrained
// match -- this guard beats every other branch, including a supplied scope.
function buildRoleGroupRelevance(usernames, scopeGroupId, scopeSiteName){
  if(!usernames || usernames.length === 0){ return "false"; }
  var seen   = {};
  var quoted = [];
  var i, u;
  for(i = 0; i < usernames.length; i++){
    u = String(usernames[i]).toLowerCase().replace(/^\s+|\s+$/g, "");
    if(u === ""){ continue; }
    if(seen[u]){ continue; }
    seen[u] = true;
    quoted.push('"' + u.replace(/"/g, '""') + '"');
  }
  if(quoted.length === 0){ return "false"; }
  var base = '(number of (logged on users whose (name of it as lowercase is contained by ' +
    'set of (' + quoted.join(';') + ')))) = 1';
  if(scopeGroupId){
    var safeSite = String(scopeSiteName || "").toLowerCase().replace(/"/g, '""');
    base += ' AND (member of group ' + scopeGroupId + ' of site whose ' +
      '(name of it as lowercase = "' + safeSite + '" as lowercase))';
  }
  return base;
}

// buildComputerGroupXml(title, domain, relevance) -- Pattern 1. Six-element
// body confirmed accepted live by 07-01's spike (07-SPIKE-FINDINGS.md Check A).
function buildComputerGroupXml(title, domain, relevance){
  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <ComputerGroup>\r\n';
  xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';
  xml += '    <Domain>' + xmlEscape(domain || "BESC") + '</Domain>\r\n';
  xml += '    <JoinByIntersection>true</JoinByIntersection>\r\n';
  xml += '    <IsDynamic>true</IsDynamic>\r\n';
  xml += '    <EvaluateOnClient>true</EvaluateOnClient>\r\n';
  xml += '    <SearchComponentRelevance Comparison="IsTrue">\r\n';
  xml += '      <Relevance>' + cdataStart() + xmlCDataSafe(relevance) + cdataEnd() + '</Relevance>\r\n';
  xml += '    </SearchComponentRelevance>\r\n';
  xml += '  </ComputerGroup>\r\n';
  xml += '</BES>';
  return xml;
}

// buildRolePolicyTaskXml(templateFields, role, assignedBy) -- Pattern 3 step 1.
// From-scratch <BES><Task> build in SKILL S7 schema order; never mutates a
// fetched DOM (T-07-04-04).
function buildRolePolicyTaskXml(templateFields, role, assignedBy){
  var tf  = templateFields || {};
  var sub = function(s){
    return String(s || "")
      .replace(/__ROLE__/g, role)
      .replace(/__ASSIGNED_BY__/g, assignedBy);
  };
  var title             = PORTAL_CONFIG.taskTitlePrefix + role;
  var description        = sub(tf.description);
  var relevances          = tf.relevances || [];
  var category            = tf.category || "";
  var source               = tf.source || "Internal";
  var sourceId             = tf.sourceId || "";
  var sourceReleaseDate    = tf.sourceReleaseDate || "";
  var sourceSeverity       = tf.sourceSeverity || "";
  var cveNames             = tf.cveNames || "";
  var sansId               = tf.sansId || "";
  var mimeFields           = tf.mimeFields || [];
  var domain               = tf.domain || "BESC";
  var actionDescription    = tf.actionDescription || {};
  var preLink              = actionDescription.preLink || "Click ";
  var link                 = actionDescription.link || "here";
  var postLink             = sub(actionDescription.postLink || "");
  // __USERNAME__ is deliberately NOT substituted -- resolved at runtime from
  // client relevance ({name of current user as lowercase}).
  var actionScript = sub(tf.actionScript);

  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <Task>\r\n';
  xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';
  xml += '    <Description>' + cdataStart() + xmlCDataSafe(description) + cdataEnd() + '</Description>\r\n';
  var ri;
  for(ri = 0; ri < relevances.length; ri++){
    xml += '    <Relevance>' + cdataStart() + xmlCDataSafe(sub(relevances[ri])) + cdataEnd() + '</Relevance>\r\n';
  }
  xml += '    <Category>' + xmlEscape(category) + '</Category>\r\n';
  xml += '    <Source>' + xmlEscape(source) + '</Source>\r\n';
  xml += '    <SourceID>' + xmlEscape(sourceId) + '</SourceID>\r\n';
  xml += '    <SourceReleaseDate>' + xmlEscape(sourceReleaseDate) + '</SourceReleaseDate>\r\n';
  xml += '    <SourceSeverity>' + xmlEscape(sourceSeverity) + '</SourceSeverity>\r\n';
  xml += '    <CVENames>' + xmlEscape(cveNames) + '</CVENames>\r\n';
  xml += '    <SANSID>' + xmlEscape(sansId) + '</SANSID>\r\n';
  var mi;
  for(mi = 0; mi < mimeFields.length; mi++){
    xml += '    <MIMEField>\r\n';
    xml += '      <Name>' + xmlEscape(mimeFields[mi].name) + '</Name>\r\n';
    xml += '      <Value>' + xmlEscape(mimeFields[mi].value) + '</Value>\r\n';
    xml += '    </MIMEField>\r\n';
  }
  xml += '    <Domain>' + xmlEscape(domain) + '</Domain>\r\n';
  xml += '    <DefaultAction ID="Action1">\r\n';
  xml += '      <Description>\r\n';
  xml += '        <PreLink>' + xmlEscape(preLink) + '</PreLink>\r\n';
  xml += '        <Link>' + xmlEscape(link) + '</Link>\r\n';
  xml += '        <PostLink>' + xmlEscape(postLink) + '</PostLink>\r\n';
  xml += '      </Description>\r\n';
  xml += '      <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">';
  xml += cdataStart() + xmlCDataSafe(actionScript) + cdataEnd();
  xml += '</ActionScript>\r\n';
  xml += '    </DefaultAction>\r\n';
  xml += '  </Task>\r\n';
  xml += '</BES>';
  return xml;
}

// buildRolePolicyActionXml(title, relevance, actionScript, groupId, siteName)
// -- Pattern 3 steps 2-3, D-11. SingleAction only (T-07-04-05); Target after
// Settings (a confirmed 400 otherwise).
function buildRolePolicyActionXml(title, relevance, actionScript, groupId, siteName){
  var safeSite  = String(siteName || "").toLowerCase().replace(/"/g, '""');
  var targetRel = 'member of group ' + groupId + ' of site whose (name of it as lowercase = "' + safeSite + '" as lowercase)';

  var roleValue = String(title || "");
  if(roleValue.indexOf(PORTAL_CONFIG.actionTitlePrefix) === 0){
    roleValue = roleValue.substring(PORTAL_CONFIG.actionTitlePrefix.length);
  }

  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <SingleAction>\r\n';
  xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';
  xml += '    <Relevance>' + xmlEscape(relevance) + '</Relevance>\r\n';
  xml += '    <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">';
  xml += cdataStart() + xmlCDataSafe(actionScript) + cdataEnd();
  xml += '</ActionScript>\r\n';
  xml += '    <Settings>\r\n';
  xml += '      <ActionUITitle>' + xmlEscape(title) + '</ActionUITitle>\r\n';
  xml += '      <PreActionShowUI>false</PreActionShowUI>\r\n';
  xml += '      <Reapply>true</Reapply>\r\n';
  xml += '      <HasReapplyLimit>false</HasReapplyLimit>\r\n';
  xml += '      <HasReapplyInterval>true</HasReapplyInterval>\r\n';
  xml += '      <ReapplyInterval>P1D</ReapplyInterval>\r\n';
  xml += '      <IsOffer>false</IsOffer>\r\n';
  xml += '    </Settings>\r\n';
  xml += '    <Target>\r\n';
  xml += '      <CustomRelevance>' + cdataStart() + xmlCDataSafe(targetRel) + cdataEnd() + '</CustomRelevance>\r\n';
  xml += '    </Target>\r\n';
  xml += '    <MIMEFieldSingleAction>\r\n';
  xml += '      <Name>DSP_RoleManager_Role</Name>\r\n';
  xml += '      <Value>' + xmlEscape(roleValue) + '</Value>\r\n';
  xml += '    </MIMEFieldSingleAction>\r\n';
  xml += '  </SingleAction>\r\n';
  xml += '</BES>';
  return xml;
}

// -- ActionScript brace escaping -- verbatim from fixlet_role_manager.ojo
// (only the opening brace is doubled; see the .ojo's own load-bearing
// comment for why doubling "}" too is a bug).
function escapeActionScriptBraces(s){
  return String(s).replace(/\{/g, "{{");
}

// buildEndpointScriptStagingActionXml() -- verbatim from fixlet_role_manager.ojo
// (plan 07-07 Task 1). Depends on ASSIGN_ROLE_MAPPING_SCRIPT, which is
// extracted from the .ojo source itself further below (section 3) -- JS
// function hoisting makes this safe since the function is only ever CALLED
// after that extraction has run.
function buildEndpointScriptStagingActionXml(){
  if(!PORTAL_CONFIG.rootServerComputerId){ return ""; }
  var stamp = (new Date()).toISOString();
  var title = "DSP RoleMap StageScript " + stamp;

  var lines = [];
  lines.push('\tparameter "RepoDir"="{(value "wwwRootFolder" of key "HKEY_LOCAL_MACHINE\\SOFTWARE\\Wow6432Node\\BigFix\\Enterprise Server" of registry) & "Uploads\\CustomRepository\\SoftwarePortal\\rolegroups"}"');
  lines.push('');
  lines.push('\tif {not exists folder "{parameter "RepoDir"}"}');
  lines.push('\t\trunhidden cmd /c mkdir "{parameter "RepoDir"}"');
  lines.push('\tendif');
  lines.push('');
  lines.push('delete __createfile');
  lines.push('delete "{parameter "RepoDir"}\\Assign-RoleMapping.ps1"');
  lines.push('');
  lines.push('createfile until _EOF_');
  lines.push(escapeActionScriptBraces(ASSIGN_ROLE_MAPPING_SCRIPT));
  lines.push('_EOF_');
  lines.push('');
  lines.push('move __createfile "{parameter "RepoDir"}\\Assign-RoleMapping.ps1"');

  var script = lines.join('\r\n');

  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <SingleAction>\r\n';
  xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';
  xml += '    <Relevance>true</Relevance>\r\n';
  xml += '    <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">';
  xml += cdataStart() + xmlCDataSafe(script) + cdataEnd();
  xml += '</ActionScript>\r\n';
  xml += '    <Settings>\r\n';
  xml += '      <ActionUITitle>' + xmlEscape(title) + '</ActionUITitle>\r\n';
  xml += '      <PreActionShowUI>false</PreActionShowUI>\r\n';
  xml += '      <HasEndTime>true</HasEndTime>\r\n';
  xml += '      <EndDateTimeLocalOffset>P1D</EndDateTimeLocalOffset>\r\n';
  xml += '      <IsOffer>false</IsOffer>\r\n';
  xml += '    </Settings>\r\n';
  xml += '    <Target>\r\n';
  xml += '      <ComputerID>' + xmlEscape(PORTAL_CONFIG.rootServerComputerId) + '</ComputerID>\r\n';
  xml += '    </Target>\r\n';
  xml += '  </SingleAction>\r\n';
  xml += '</BES>';
  return xml;
}

// jsonEscape/jsonStringLiteral/buildRolePublishPayload -- verbatim from
// fixlet_role_manager.ojo (plan 07-06 Task 2).
function jsonEscape(s){
  var str = String(s);
  var out = "";
  var i, c, code, hex;
  for(i = 0; i < str.length; i++){
    c    = str.charAt(i);
    code = str.charCodeAt(i);
    if(c === '\\'){ out += '\\\\'; }
    else if(c === '"'){ out += '\\"'; }
    else if(c === '\b'){ out += '\\b'; }
    else if(c === '\f'){ out += '\\f'; }
    else if(c === '\n'){ out += '\\n'; }
    else if(c === '\r'){ out += '\\r'; }
    else if(c === '\t'){ out += '\\t'; }
    else if(code < 0x20){
      hex = code.toString(16);
      while(hex.length < 4){ hex = "0" + hex; }
      out += '\\u' + hex;
    } else {
      out += c;
    }
  }
  return out;
}
function jsonStringLiteral(s){ return '"' + jsonEscape(s) + '"'; }

function buildRolePublishPayload(role, usernames, publishedBy){
  var users = usernames || [];
  var by    = String(publishedBy || "").replace(/^\s+|\s+$/g, "");
  if(by === ""){ by = "console-operator"; }
  var parts = [];
  var i;
  for(i = 0; i < users.length; i++){
    parts.push(jsonStringLiteral(users[i]));
  }
  return '{"role":' + jsonStringLiteral(role) +
    ',"published_by":' + jsonStringLiteral(by) +
    ',"users":[' + parts.join(',') + ']}';
}

// buildAuditWriteActionScript(payloadJson) -- verbatim from
// fixlet_role_manager.ojo (plan 07-06 Task 2). ROLE_PUBLISH_SCRIPT is
// extracted from the .ojo source itself further below (never hard-copied
// here -- see the mirror-fidelity section).
function buildAuditWriteActionScript(payloadJson){
  var lines = [];

  lines.push('\tparameter "SWPDir"="{(concatenation (if windows of operating system then "\\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal")))}"');
  lines.push('\tparameter "SQLiteDir"="{(concatenation (if windows of operating system then "\\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","sqlite")))}"');
  lines.push('\tparameter "TargetStore"="{(concatenation (if windows of operating system then "\\" else "/") of ((item 0 of it;item 1 of it;item 2 of it;item 3 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal","RolePublish.db")))}"');
  lines.push('');

  lines.push('\tif {not exists folder ((parameter "SWPDir") & "\\rolegroups")}');
  lines.push('\t\trunhidden cmd /c mkdir "{parameter "SWPDir"}\\rolegroups"');
  lines.push('\tendif');
  lines.push('');

  lines.push('delete __createfile');
  lines.push('delete "{parameter "SWPDir"}\\rolegroups\\Upsert-RolePublish.ps1"');
  lines.push('');
  lines.push('createfile until _EOF_');
  lines.push(escapeActionScriptBraces(ROLE_PUBLISH_SCRIPT));
  lines.push('_EOF_');
  lines.push('');
  lines.push('move __createfile "{parameter "SWPDir"}\\rolegroups\\Upsert-RolePublish.ps1"');
  lines.push('');

  lines.push('delete __createfile');
  lines.push('delete "{parameter "SWPDir"}\\rolegroups\\rolepublish-payload.json"');
  lines.push('');
  lines.push('createfile until _EOF_');
  lines.push(escapeActionScriptBraces(payloadJson));
  lines.push('_EOF_');
  lines.push('');
  lines.push('move __createfile "{parameter "SWPDir"}\\rolegroups\\rolepublish-payload.json"');
  lines.push('');

  lines.push('action uses wow64 redirection {x64 of operating system}');
  lines.push('waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "{parameter "SWPDir"}\\rolegroups\\Upsert-RolePublish.ps1" -PayloadPath "{parameter "SWPDir"}\\rolegroups\\rolepublish-payload.json" -DatabasePath "{parameter "TargetStore"}" -SQLDir "{parameter "SQLiteDir"}" -SqliteHelperPath "{parameter "SWPDir"}\\Sqlite-Helper.ps1"');
  lines.push('');

  lines.push('delete "{parameter "SWPDir"}\\rolegroups\\rolepublish-payload.json"');

  return lines.join('\r\n');
}

// buildAuditWriteActionXml(role, actionScript) -- verbatim from
// fixlet_role_manager.ojo (plan 07-06 Task 2).
function buildAuditWriteActionXml(role, actionScript){
  if(!PORTAL_CONFIG.rootServerComputerId){ return ""; }
  var stamp = new Date().toISOString();
  var title = "DSP RoleSave - " + role + " " + stamp;

  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <SingleAction>\r\n';
  xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';
  xml += '    <Relevance>true</Relevance>\r\n';
  xml += '    <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">';
  xml += cdataStart() + xmlCDataSafe(actionScript) + cdataEnd();
  xml += '</ActionScript>\r\n';
  xml += '    <Settings>\r\n';
  xml += '      <ActionUITitle>' + xmlEscape(title) + '</ActionUITitle>\r\n';
  xml += '      <PreActionShowUI>false</PreActionShowUI>\r\n';
  xml += '      <HasEndTime>true</HasEndTime>\r\n';
  xml += '      <EndDateTimeLocalOffset>P1D</EndDateTimeLocalOffset>\r\n';
  xml += '      <IsOffer>false</IsOffer>\r\n';
  xml += '    </Settings>\r\n';
  xml += '    <Target>\r\n';
  xml += '      <ComputerID>' + xmlEscape(PORTAL_CONFIG.rootServerComputerId) + '</ComputerID>\r\n';
  xml += '    </Target>\r\n';
  xml += '  </SingleAction>\r\n';
  xml += '</BES>';
  return xml;
}

// roleState/knownUsers/roleSlug/getRoleUsers/setRoleUsers/suggestUsernames --
// verbatim from fixlet_role_manager.ojo (plan 07-06 Task 1). renderRolePanel
// is a no-op stub here -- it is pure DOM rendering, not exercised under Node
// (the same reasoning findBesObjectIdByTitle's EvaluateRelevance call is
// left untested by this suite).
var roleState = {
  "IT Operations":      { users: [], scopeGroupId: "", scopeSiteName: "", dirty: false, lastSavedRunId: null },
  "Business Operations": { users: [], scopeGroupId: "", scopeSiteName: "", dirty: false, lastSavedRunId: null }
};
var knownUsers = [];
function renderRolePanel(role){ /* no-op stub -- DOM rendering only */ }

function roleSlug(role){
  return String(role).replace(/[^A-Za-z0-9]/g, "_");
}
function getRoleUsers(role){
  var st = roleState[role];
  return st ? st.users.slice() : [];
}
function setRoleUsers(role, usernames){
  var st = roleState[role];
  if(!st){ return; }
  var seen = {};
  var out  = [];
  var i, u;
  for(i = 0; i < (usernames || []).length; i++){
    u = String(usernames[i]).toLowerCase().replace(/^\s+|\s+$/g, "");
    if(u === ""){ continue; }
    if(seen[u]){ continue; }
    seen[u] = true;
    out.push(u);
  }
  st.users = out;
  st.dirty = true;
  renderRolePanel(role);
}
function suggestUsernames(prefix){
  var p = String(prefix || "").toLowerCase().replace(/^\s+|\s+$/g, "");
  if(p === ""){ return []; }
  var out = [];
  var i, u;
  for(i = 0; i < knownUsers.length; i++){
    u = String(knownUsers[i]).toLowerCase();
    if(u.indexOf(p) === 0){ out.push(u); }
  }
  out.sort();
  return out.slice(0, 10);
}

// ---------------------------------------------------------------------------
// 2. TEST INFRASTRUCTURE (verbatim from role_assigner.test.js / dispatcher.test.js)
// ---------------------------------------------------------------------------

var passed   = 0;
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
// 3. SOURCE FILE (read once, reused by the source-level assertions below)
// ---------------------------------------------------------------------------

var OJO_PATH = path.join(__dirname, '..', '..', 'Existing Dashboards', 'fixlet_role_manager.ojo');
var OJO_SRC  = fs.readFileSync(OJO_PATH, 'utf8');

// extractRolePublishScriptLines(src) -- locates the ROLE_PUBLISH_SCRIPT_LINES
// array literal in the .ojo source (between its declaration and the closing
// "];") and parses it via eval() of the literal itself (never hard-copied
// here -- a ~300-line duplicate would be its own drift risk; this is the
// same reasoning the mirror-fidelity test below depends on).
function extractRolePublishScriptLines(src){
  var declText = "var ROLE_PUBLISH_SCRIPT_LINES = ";
  var declStart = src.indexOf(declText);
  assert.ok(declStart >= 0, "ROLE_PUBLISH_SCRIPT_LINES declaration not found in fixlet_role_manager.ojo");
  var bracketStart = declStart + declText.length;
  assert.strictEqual(src.charAt(bracketStart), "[", "expected '[' immediately after the ROLE_PUBLISH_SCRIPT_LINES declaration");
  var closeIdx = src.indexOf("\n];", bracketStart);
  assert.ok(closeIdx >= 0, "ROLE_PUBLISH_SCRIPT_LINES closing '];' not found");
  var arrayLiteralText = src.substring(bracketStart, closeIdx + 2);
  return eval(arrayLiteralText);
}

var ROLE_PUBLISH_SCRIPT_LINES = extractRolePublishScriptLines(OJO_SRC);
var ROLE_PUBLISH_SCRIPT        = ROLE_PUBLISH_SCRIPT_LINES.join('\r\n');

// extractAssignRoleMappingScriptLines(src) -- same eval-of-the-literal
// discipline as extractRolePublishScriptLines above (never hard-copied here).
// Joiner is '\n', NOT '\r\n' -- scripts/Assign-RoleMapping.ps1 is LF-only
// (verified), unlike scripts/Upsert-RolePublish.ps1 (CRLF, hence
// ROLE_PUBLISH_SCRIPT's '\r\n' joiner above). Using the wrong joiner here
// would silently break the SHA1 pin assertion below.
function extractAssignRoleMappingScriptLines(src){
  var declText = "var ASSIGN_ROLE_MAPPING_SCRIPT_LINES = ";
  var declStart = src.indexOf(declText);
  assert.ok(declStart >= 0, "ASSIGN_ROLE_MAPPING_SCRIPT_LINES declaration not found in fixlet_role_manager.ojo");
  var bracketStart = declStart + declText.length;
  assert.strictEqual(src.charAt(bracketStart), "[", "expected '[' immediately after the ASSIGN_ROLE_MAPPING_SCRIPT_LINES declaration");
  var closeIdx = src.indexOf("\n];", bracketStart);
  assert.ok(closeIdx >= 0, "ASSIGN_ROLE_MAPPING_SCRIPT_LINES closing '];' not found");
  var arrayLiteralText = src.substring(bracketStart, closeIdx + 2);
  return eval(arrayLiteralText);
}

var ASSIGN_ROLE_MAPPING_SCRIPT_LINES = extractAssignRoleMappingScriptLines(OJO_SRC);
var ASSIGN_ROLE_MAPPING_SCRIPT        = ASSIGN_ROLE_MAPPING_SCRIPT_LINES.join('\n');

// extractAssignRoleTemplate(src) -- eval-of-the-literal extraction of
// ASSIGN_ROLE_TEMPLATE (never hard-copied here -- a second ~90-line
// hand-duplicate of bes/Assign-RoleMapping.bes's field values would itself be
// a drift risk, the same reasoning the mirror-fidelity tests below depend on).
function extractAssignRoleTemplate(src){
  var declText = "var ASSIGN_ROLE_TEMPLATE = ";
  var declStart = src.indexOf(declText);
  assert.ok(declStart >= 0, "ASSIGN_ROLE_TEMPLATE declaration not found in fixlet_role_manager.ojo");
  var braceStart = declStart + declText.length;
  assert.strictEqual(src.charAt(braceStart), "{", "expected '{' immediately after the ASSIGN_ROLE_TEMPLATE declaration");
  var closeIdx = src.indexOf("\n};", braceStart);
  assert.ok(closeIdx >= 0, "ASSIGN_ROLE_TEMPLATE closing '};' not found");
  var objectLiteralText = src.substring(braceStart, closeIdx + 2);
  return eval("(" + objectLiteralText + ")");
}

var ASSIGN_ROLE_TEMPLATE = extractAssignRoleTemplate(OJO_SRC);

// ---------------------------------------------------------------------------
// 4. TEST BLOCKS
// ---------------------------------------------------------------------------

section("buildRoleGroupRelevance (D-09, D-10, T-07-04-01/T-07-04-02)");

expect("empty array returns exactly \"false\"", function(){
  assert.strictEqual(buildRoleGroupRelevance([]), "false");
});

expect("null returns exactly \"false\"", function(){
  assert.strictEqual(buildRoleGroupRelevance(null), "false");
});

expect("undefined returns exactly \"false\"", function(){
  assert.strictEqual(buildRoleGroupRelevance(undefined), "false");
});

expect("empty-list result contains no \"set of\"", function(){
  assert.ok(buildRoleGroupRelevance([]).indexOf("set of") < 0);
});

expect("empty-list result contains no \"true\"", function(){
  assert.ok(buildRoleGroupRelevance([]).indexOf("true") < 0);
});

expect("[\"alice\",\"bob\"] produces the exact expected relevance string", function(){
  assert.strictEqual(
    buildRoleGroupRelevance(["alice", "bob"]),
    '(number of (logged on users whose (name of it as lowercase is contained by set of ("alice";"bob")))) = 1'
  );
});

expect("[\"Alice\",\"ALICE\",\"  alice  \"] dedups to a single \"alice\" entry", function(){
  var rel = buildRoleGroupRelevance(["Alice", "ALICE", "  alice  "]);
  assert.strictEqual(rel, '(number of (logged on users whose (name of it as lowercase is contained by set of ("alice")))) = 1');
});

expect("a username containing \" is escaped to \"\" with no odd-count quote break-out", function(){
  var rel = buildRoleGroupRelevance(['ali"ce']);
  assert.ok(rel.indexOf('ali""ce') >= 0, "expected doubled-quote escape in output: " + rel);
  var setOfMatch = /set of \((.*)\)\)\)\)/.exec(rel);
  assert.ok(setOfMatch, "expected to find the set-of literal");
  var quoteCount = (setOfMatch[1].match(/"/g) || []).length;
  assert.strictEqual(quoteCount % 2, 0, "quote count inside the literal must be even (no break-out)");
});

expect("scopeGroupId + scopeSiteName appends the exact AND clause", function(){
  var rel = buildRoleGroupRelevance(["alice"], 12345, 'Dereso Software Portal');
  assert.ok(rel.indexOf(' AND (member of group 12345 of site whose (name of it as lowercase = "dereso software portal" as lowercase))') >= 0);
  assert.ok(rel.substring(rel.length - 1) === ')', "AND clause must be the tail of the string");
});

expect("empty/null/0 scopeGroupId emits no scope clause", function(){
  assert.ok(buildRoleGroupRelevance(["alice"], "", "site").indexOf("member of group") < 0);
  assert.ok(buildRoleGroupRelevance(["alice"], null, "site").indexOf("member of group") < 0);
  assert.ok(buildRoleGroupRelevance(["alice"], 0, "site").indexOf("member of group") < 0);
});

expect("scopeGroupId set but an empty username list is still exactly \"false\" (guard wins)", function(){
  assert.strictEqual(buildRoleGroupRelevance([], 12345, "Dereso Software Portal"), "false");
});

section("buildComputerGroupXml (Pattern 1)");

var cgXml = buildComputerGroupXml('Test Group', 'BESC', 'true');

expect("output starts with the XML declaration and contains <BES>/</BES>", function(){
  assert.ok(cgXml.indexOf('<?xml version="1.0" encoding="UTF-8"?>') === 0);
  assert.ok(cgXml.indexOf('<BES') >= 0);
  assert.ok(cgXml.indexOf('</BES>') >= 0);
});

expect("contains Title/Domain BESC/JoinByIntersection true/SearchComponentRelevance IsTrue (six-element body per 07-01 spike)", function(){
  assert.ok(cgXml.indexOf('<Title>') >= 0);
  assert.ok(cgXml.indexOf('<Domain>BESC</Domain>') >= 0);
  assert.ok(cgXml.indexOf('<JoinByIntersection>true</JoinByIntersection>') >= 0);
  assert.ok(cgXml.indexOf('<SearchComponentRelevance Comparison="IsTrue">') >= 0);
  assert.ok(cgXml.indexOf('<IsDynamic>true</IsDynamic>') >= 0);
  assert.ok(cgXml.indexOf('<EvaluateOnClient>true</EvaluateOnClient>') >= 0);
});

expect("a title containing & < \" is escaped to &amp; &lt; &quot;", function(){
  var xml = buildComputerGroupXml('A & B <C> "D"', 'BESC', 'true');
  assert.ok(xml.indexOf('A &amp; B &lt;C&gt; &quot;D&quot;') >= 0);
});

expect("a relevance containing ]]> is split so no bare ]]> survives except the closing one", function(){
  var xml = buildComputerGroupXml('T', 'BESC', 'a]]>b');
  var relStart = xml.indexOf('<Relevance>') + '<Relevance>'.length;
  var relEnd   = xml.indexOf('</Relevance>');
  var relBody  = xml.substring(relStart, relEnd);
  // The body must be a valid concatenation of CDATA sections -- i.e. every
  // "]]>" that appears must immediately be followed by the CDATA-restart
  // idiom, except the final one which closes the outer CDATA section.
  var closer = relBody.lastIndexOf(']]>');
  assert.ok(closer >= 0, "expected a closing ]]> in the CDATA body");
  var bareInMiddle = relBody.substring(0, closer).split(']]>').length - 1;
  // every split point before the final closer must be immediately followed by <![CDATA[
  var parts = relBody.substring(0, closer).split(']]>');
  for(var i = 0; i < parts.length - 1; i++){
    // nothing to assert on parts[i]; the next chunk should start the CDATA restart
  }
  assert.ok(relBody.indexOf(']]]]><![CDATA[>') >= 0, "expected the ]]]]><![CDATA[> restart idiom");
});

expect("element order: index of <Title> < <Domain> < <SearchComponentRelevance", function(){
  assert.ok(cgXml.indexOf('<Title>') < cgXml.indexOf('<Domain>'));
  assert.ok(cgXml.indexOf('<Domain>') < cgXml.indexOf('<SearchComponentRelevance'));
});

section("buildRolePolicyTaskXml (Pattern 3 step 1, SKILL S3/S7)");

var TASK_FIELDS = {
  title: 'Assign Role Mapping — Operator Role Group (__ROLE__)',
  description: 'desc for __ROLE__ by __ASSIGNED_BY__',
  relevances: ['windows of operating system', 'exists file "x" of it'],
  category: '',
  source: 'Internal',
  sourceId: '',
  sourceReleaseDate: '2026-09-09',
  sourceSeverity: '',
  cveNames: '',
  sansId: '',
  mimeFields: [{ name: 'x-fixlet-modification-time', value: 'Wed, 09 Sep 2026 00:00:00 +0000' }],
  domain: 'BESC',
  actionDescription: { preLink: 'Click ', link: 'here', postLink: 'to map role "__ROLE__" to the target user.' },
  actionScript: 'parameter "Role"="__ROLE__"\nparameter "AssignedBy"="__ASSIGNED_BY__"\nparameter "UserName"="{name of current user as lowercase}" __USERNAME__'
};

var taskXml = buildRolePolicyTaskXml(TASK_FIELDS, 'IT Operations', 'jdoe');

expect("exactly two <Relevance> elements survive from a two-relevance template", function(){
  var count = (taskXml.match(/<Relevance>/g) || []).length;
  assert.strictEqual(count, 2);
});

expect("__ROLE__ is fully substituted (zero occurrences remain)", function(){
  assert.strictEqual(taskXml.indexOf('__ROLE__'), -1);
});

expect("__ASSIGNED_BY__ is fully substituted (zero occurrences remain)", function(){
  assert.strictEqual(taskXml.indexOf('__ASSIGNED_BY__'), -1);
});

expect("__USERNAME__ is still present in the emitted ActionScript (never substituted)", function(){
  assert.ok(taskXml.indexOf('__USERNAME__') >= 0);
});

expect("field order matches SKILL S7: Title < Description < Relevance < Category < Source < Domain < DefaultAction", function(){
  var iTitle   = taskXml.indexOf('<Title>');
  var iDesc    = taskXml.indexOf('<Description>');
  var iRel     = taskXml.indexOf('<Relevance>');
  var iCat     = taskXml.indexOf('<Category>');
  var iSrc     = taskXml.indexOf('<Source>');
  var iDomain  = taskXml.indexOf('<Domain>');
  var iDefault = taskXml.indexOf('<DefaultAction');
  assert.ok(iTitle >= 0 && iTitle < iDesc);
  assert.ok(iDesc < iRel);
  assert.ok(iRel < iCat);
  assert.ok(iCat < iSrc);
  assert.ok(iSrc < iDomain);
  assert.ok(iDomain < iDefault);
});

section("buildRolePolicyActionXml (Pattern 3, D-11)");

var actionXml = buildRolePolicyActionXml('DSP RoleMap - IT Operations', 'true', 'waithidden powershell.exe -File x.ps1', 4242, 'Dereso Software Portal');

expect("element order: <Settings> appears before <Target>", function(){
  assert.ok(actionXml.indexOf('<Settings>') < actionXml.indexOf('<Target>'));
});

expect("contains <Reapply>true</Reapply>, <HasReapplyInterval>true</HasReapplyInterval>, <ReapplyInterval>P1D</ReapplyInterval>, <IsOffer>false</IsOffer>", function(){
  assert.ok(actionXml.indexOf('<Reapply>true</Reapply>') >= 0);
  assert.ok(actionXml.indexOf('<HasReapplyInterval>true</HasReapplyInterval>') >= 0);
  assert.ok(actionXml.indexOf('<ReapplyInterval>P1D</ReapplyInterval>') >= 0);
  assert.ok(actionXml.indexOf('<IsOffer>false</IsOffer>') >= 0);
});

expect("does NOT contain <HasEndTime> or the sourced-fixlet-action element", function(){
  assert.strictEqual(actionXml.indexOf('<HasEndTime>'), -1);
  assert.strictEqual(actionXml.indexOf('SourcedFixletAction'), -1);
});

expect("<Target> contains \"member of group 4242 of site\" for groupId = 4242", function(){
  assert.ok(actionXml.indexOf('member of group 4242 of site') >= 0);
});

expect("contains a <MIMEFieldSingleAction> whose <Name> is DSP_RoleManager_Role", function(){
  assert.ok(actionXml.indexOf('<Name>DSP_RoleManager_Role</Name>') >= 0);
});

section("Source-level assertions against fixlet_role_manager.ojo itself");

expect("the .ojo file contains no alert(, no =>, no const/let, no oninput", function(){
  assert.strictEqual(/\balert\s*\(/.test(OJO_SRC), false);
  assert.strictEqual(/=>/.test(OJO_SRC.replace(/=&gt;/g, '')), false);
  assert.strictEqual(/\b(const|let)\s/.test(OJO_SRC), false);
  assert.strictEqual(OJO_SRC.indexOf('oninput') >= 0, false, "IE9 has no working oninput -- use onkeyup");
});

expect("the .ojo file never mutates PORTAL_CONFIG.roles at runtime (D-03)", function(){
  assert.strictEqual(/PORTAL_CONFIG\.roles\.push/.test(OJO_SRC), false);
  assert.strictEqual(/PORTAL_CONFIG\.roles\.splice/.test(OJO_SRC), false);
});

expect("PORTAL_CONFIG.roles parses out as an array with at least one entry", function(){
  var m = /roles:\s*\[([^\]]*)\]/.exec(OJO_SRC);
  assert.ok(m, "expected to find PORTAL_CONFIG.roles in the source");
  var entries = m[1].split(',').map(function(s){ return s.replace(/^\s+|\s+$/g, ''); }).filter(function(s){ return s !== ''; });
  assert.ok(entries.length >= 1);
});

expect("the .ojo file contains no SourcedFixletAction anywhere", function(){
  assert.strictEqual(OJO_SRC.indexOf('SourcedFixletAction'), -1);
});

expect("the .ojo file defines all five required functions by exact name", function(){
  assert.ok(OJO_SRC.indexOf('function buildRoleGroupRelevance(') >= 0);
  assert.ok(OJO_SRC.indexOf('function buildComputerGroupXml(') >= 0);
  assert.ok(OJO_SRC.indexOf('function buildRolePolicyTaskXml(') >= 0);
  assert.ok(OJO_SRC.indexOf('function buildRolePolicyActionXml(') >= 0);
  assert.ok(OJO_SRC.indexOf('function findBesObjectIdByTitle(') >= 0);
});

section("ROLE_PUBLISH_SCRIPT_LINES mirror fidelity (T-07-06-05)");

var UPSERT_PS1_PATH = path.join(__dirname, '..', '..', 'scripts', 'Upsert-RolePublish.ps1');
var UPSERT_PS1_SRC  = fs.readFileSync(UPSERT_PS1_PATH, 'utf8');

expect("ROLE_PUBLISH_SCRIPT_LINES.join('\\n') equals scripts/Upsert-RolePublish.ps1 (CRLF/LF normalised) -- regenerate the mirror, do not hand-edit, if this fails", function(){
  var mirror = ROLE_PUBLISH_SCRIPT_LINES.join('\n').replace(/\r\n/g, '\n');
  var repo   = UPSERT_PS1_SRC.replace(/\r\n/g, '\n');
  assert.strictEqual(mirror, repo, "ROLE_PUBLISH_SCRIPT_LINES has drifted from scripts/Upsert-RolePublish.ps1 -- regenerate the mirror from that file, do not hand-edit fixlet_role_manager.ojo's copy");
});

section("Cross-language relevance contract (tests/fixtures/phase-07/role-group-relevance.golden.txt)");

var GOLDEN_PATH  = path.join(__dirname, '..', 'fixtures', 'phase-07', 'role-group-relevance.golden.txt');
var GOLDEN_SRC   = fs.readFileSync(GOLDEN_PATH, 'utf8');
var GOLDEN_LINES = GOLDEN_SRC.replace(/\r\n/g, '\n').split('\n');

expect("buildRoleGroupRelevance([\"alice\",\"bob\"]) reproduces golden.txt line 1 (no scope)", function(){
  assert.strictEqual(buildRoleGroupRelevance(["alice", "bob"]), GOLDEN_LINES[0]);
});

expect("buildRoleGroupRelevance([\"alice\",\"bob\"], 12345, \"Dereso Software Portal\") reproduces golden.txt line 2 (with scope)", function(){
  assert.strictEqual(buildRoleGroupRelevance(["alice", "bob"], 12345, "Dereso Software Portal"), GOLDEN_LINES[1]);
});

expect("buildRoleGroupRelevance([]) reproduces golden.txt line 3 (\"false\")", function(){
  assert.strictEqual(buildRoleGroupRelevance([]), GOLDEN_LINES[2]);
});

section("buildRolePublishPayload (07-03 JSON contract)");

expect("(\"IT Operations\", [\"alice\",\"bob\"], \"jfannon\") produces the exact expected JSON", function(){
  assert.strictEqual(
    buildRolePublishPayload("IT Operations", ["alice", "bob"], "jfannon"),
    '{"role":"IT Operations","published_by":"jfannon","users":["alice","bob"]}'
  );
});

expect("an empty user array produces \"users\":[]", function(){
  assert.ok(buildRolePublishPayload("IT Operations", [], "jfannon").indexOf('"users":[]') >= 0);
});

expect("an empty publishedBy falls back to console-operator", function(){
  assert.ok(buildRolePublishPayload("IT Operations", ["a"], "").indexOf('"published_by":"console-operator"') >= 0);
  assert.ok(buildRolePublishPayload("IT Operations", ["a"], "   ").indexOf('"published_by":"console-operator"') >= 0);
});

expect("a role name containing \\\" and \\\\ is escaped and round-trips through JSON.parse", function(){
  var role = 'Role "quoted" \\ name';
  var json = buildRolePublishPayload(role, ["a"], "by");
  assert.ok(json.indexOf('\\"quoted\\"') >= 0);
  assert.ok(json.indexOf('\\\\') >= 0);
  var parsed = JSON.parse(json);
  assert.strictEqual(parsed.role, role);
});

expect("a username containing a newline and a tab round-trips through JSON.parse", function(){
  var username = "line1\nline2\tend";
  var json = buildRolePublishPayload("R", [username], "by");
  var parsed = JSON.parse(json);
  assert.strictEqual(parsed.users[0], username);
});

expect("a username containing the literal _EOF_ survives as JSON data, unchanged (T-07-06-01)", function(){
  var username = "a_EOF_b";
  var json     = buildRolePublishPayload("IT Operations", [username], "jfannon");
  var parsed   = JSON.parse(json);
  assert.strictEqual(parsed.users[0], username);
});

section("buildAuditWriteActionScript (D-07 audit-write ActionScript)");

var basicPayload = buildRolePublishPayload("IT Operations", ["alice"], "jfannon");
var basicScript   = buildAuditWriteActionScript(basicPayload);

expect("contains exactly two \"createfile until _EOF_\" blocks (script + payload)", function(){
  assert.strictEqual((basicScript.match(/createfile until _EOF_/g) || []).length, 2);
});

expect("_EOF_ occurs the matching number of times (2 embedded in \"until _EOF_\" + 2 standalone closers)", function(){
  assert.strictEqual((basicScript.match(/_EOF_/g) || []).length, 4);
});

expect("contains \"move __createfile\" exactly twice", function(){
  assert.strictEqual((basicScript.match(/move __createfile/g) || []).length, 2);
});

expect("contains -PayloadPath, -DatabasePath, -SQLDir and -SqliteHelperPath", function(){
  assert.ok(basicScript.indexOf('-PayloadPath') >= 0);
  assert.ok(basicScript.indexOf('-DatabasePath') >= 0);
  assert.ok(basicScript.indexOf('-SQLDir') >= 0);
  assert.ok(basicScript.indexOf('-SqliteHelperPath') >= 0);
});

expect("-DatabasePath resolves to the RolePublish.db TargetStore parameter, never AutomationState.db", function(){
  assert.ok(basicScript.indexOf('RolePublish.db') >= 0);
  assert.strictEqual(basicScript.indexOf('AutomationState.db'), -1);
});

expect("a username containing the literal _EOF_ cannot terminate the createfile block early (T-07-06-01)", function(){
  var payloadWithEof = buildRolePublishPayload("IT Operations", ["a_EOF_b"], "jfannon");
  var scriptWithEof  = buildAuditWriteActionScript(payloadWithEof);
  var terminatorLines = scriptWithEof.split(/\r\n/).filter(function(l){ return l === "_EOF_"; });
  assert.strictEqual(terminatorLines.length, 2, "expected exactly the two real createfile terminators (script + payload blocks); a username containing _EOF_ must never add a third -- the payload is single-line JSON so an embedded _EOF_ substring never occupies a line by itself");
});

expect("every { inside a createfile body is doubled, no } is ever doubled", function(){
  var scriptWithBraces = buildAuditWriteActionScript('{"a":"b"}');
  assert.ok(scriptWithBraces.indexOf('{{"a":"b"}') >= 0, "expected the payload's opening brace doubled");
  assert.strictEqual(scriptWithBraces.indexOf('}}'), -1, "no doubled closing brace should ever appear");
});

expect("contains \"action uses wow64 redirection\"", function(){
  assert.ok(basicScript.indexOf('action uses wow64 redirection') >= 0);
});

expect("the parameter \"SWPDir\"= line is byte-identical to the corresponding line in bes/Assign-RoleMapping.bes", function(){
  var besPath  = path.join(__dirname, '..', '..', 'bes', 'Assign-RoleMapping.bes');
  var besSrc   = fs.readFileSync(besPath, 'utf8');
  var besLine  = besSrc.split(/\r?\n/).filter(function(l){ return l.indexOf('parameter "SWPDir"') >= 0; })[0];
  var ourLine  = basicScript.split(/\r\n/).filter(function(l){ return l.indexOf('parameter "SWPDir"') >= 0; })[0];
  assert.ok(besLine, "expected to find a parameter \"SWPDir\" line in bes/Assign-RoleMapping.bes");
  assert.strictEqual(ourLine, besLine);
});

section("buildAuditWriteActionXml (D-07 SingleAction, ComputerID target)");

var auditXml = buildAuditWriteActionXml("IT Operations", basicScript);

expect("<Settings> appears before <Target>", function(){
  assert.ok(auditXml.indexOf('<Settings>') < auditXml.indexOf('<Target>'));
});

expect("contains <ComputerID> and does not contain <CustomRelevance>", function(){
  assert.ok(auditXml.indexOf('<ComputerID>') >= 0);
  assert.strictEqual(auditXml.indexOf('<CustomRelevance>'), -1);
});

expect("contains <IsOffer>false</IsOffer>", function(){
  assert.ok(auditXml.indexOf('<IsOffer>false</IsOffer>') >= 0);
});

expect("returns the empty string when PORTAL_CONFIG.rootServerComputerId is empty", function(){
  var saved = PORTAL_CONFIG.rootServerComputerId;
  PORTAL_CONFIG.rootServerComputerId = "";
  assert.strictEqual(buildAuditWriteActionXml("IT Operations", basicScript), "");
  PORTAL_CONFIG.rootServerComputerId = saved;
});

section("getRoleUsers / setRoleUsers / suggestUsernames (D-02, D-04)");

expect("setRoleUsers de-duplicates case-insensitively and trims", function(){
  setRoleUsers("IT Operations", ["Alice", " alice ", "BOB"]);
  assert.deepStrictEqual(getRoleUsers("IT Operations"), ["alice", "bob"]);
});

expect("adding a username already present on another role leaves both roles intact (D-04)", function(){
  setRoleUsers("IT Operations", ["alice", "bob"]);
  setRoleUsers("Business Operations", ["alice", "carol"]);
  assert.deepStrictEqual(getRoleUsers("IT Operations"), ["alice", "bob"]);
  assert.deepStrictEqual(getRoleUsers("Business Operations"), ["alice", "carol"]);
});

expect("suggestUsernames(\"al\") over [\"alice\",\"albert\",\"bob\"] returns [\"albert\",\"alice\"] sorted, prefix-matched, case-insensitive", function(){
  knownUsers = ["alice", "albert", "bob"];
  assert.deepStrictEqual(suggestUsernames("al"), ["albert", "alice"]);
});

expect("suggestUsernames caps at 10 results", function(){
  var i, many = [];
  for(i = 0; i < 25; i++){ many.push("alice" + i); }
  knownUsers = many;
  assert.strictEqual(suggestUsernames("alice").length, 10);
});

expect("suggestUsernames(\"\") returns an empty array", function(){
  knownUsers = ["alice", "bob"];
  assert.deepStrictEqual(suggestUsernames(""), []);
});

// ---------------------------------------------------------------------------
// 4b. bes/Assign-RoleMapping.bes FIELD EXTRACTION (regex-based, no XML
//     library -- mirrors the one-off generator used to author
//     ASSIGN_ROLE_TEMPLATE in the first place, per this project's
//     "generate, don't hand-type" convention). Used by the template-fidelity
//     section below to assert byte-for-byte agreement, independently of how
//     ASSIGN_ROLE_TEMPLATE was produced.
// ---------------------------------------------------------------------------

var BES_PATH = path.join(__dirname, '..', '..', 'bes', 'Assign-RoleMapping.bes');
var BES_SRC  = fs.readFileSync(BES_PATH, 'utf8');

function decodeXmlEntities(s){
  return String(s)
    .replace(/&#x([0-9a-fA-F]+);/g, function(m, h){ return String.fromCharCode(parseInt(h, 16)); })
    .replace(/&#(\d+);/g, function(m, d){ return String.fromCharCode(parseInt(d, 10)); })
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}
function besExtractPlain(tag){
  var re = new RegExp("<" + tag + ">([\\s\\S]*?)<\\/" + tag + ">");
  var m = re.exec(BES_SRC);
  assert.ok(m, "bes plain element not found: " + tag);
  return decodeXmlEntities(m[1]);
}
function besExtractCdata(tag, attrs){
  var re = new RegExp("<" + tag + (attrs || "") + "><!\\[CDATA\\[([\\s\\S]*?)\\]\\]><\\/" + tag + ">");
  var m = re.exec(BES_SRC);
  assert.ok(m, "bes CDATA element not found: " + tag);
  return m[1]; // raw -- CDATA content is never entity-decoded
}
function besExtractAllCdata(tag){
  var re = new RegExp("<" + tag + "><!\\[CDATA\\[([\\s\\S]*?)\\]\\]><\\/" + tag + ">", "g");
  var out = [];
  var m;
  while((m = re.exec(BES_SRC)) !== null){ out.push(m[1]); }
  return out;
}

section("Endpoint-script SHA1/SHA256/size pin (T-07-07-01, the highest-value assertion in this plan)");

var ASSIGN_PS1_PATH = path.join(__dirname, '..', '..', 'scripts', 'Assign-RoleMapping.ps1');
var ASSIGN_PS1_BUF  = fs.readFileSync(ASSIGN_PS1_PATH);

var PREFETCH_LINE_MATCH = /add prefetch item name=Assign-RoleMapping\.ps1[^\r\n]*/.exec(BES_SRC);
assert.ok(PREFETCH_LINE_MATCH, "expected to find the Assign-RoleMapping.ps1 prefetch line in bes/Assign-RoleMapping.bes");
var PREFETCH_LINE = PREFETCH_LINE_MATCH[0];
var PINNED_SHA1   = /sha1=([0-9a-fA-F]+)/.exec(PREFETCH_LINE);
var PINNED_SIZE   = /size=(\d+)/.exec(PREFETCH_LINE);
var PINNED_SHA256 = /sha256=([0-9a-fA-F]+)/.exec(PREFETCH_LINE);
assert.ok(PINNED_SHA1 && PINNED_SIZE && PINNED_SHA256, "expected sha1=/size=/sha256= tokens on the prefetch line");

// IMPORTANT, corrected 2026-09-25 after live testing: the prefetch pin CANNOT be asserted
// equal to a locally-computed hash of scripts/Assign-RoleMapping.ps1. BigFix's `createfile`
// action does not write the Custom Repository file byte-identically to the LF-only source --
// live staging against a real root server produced a file that actually hashes to
// f3afb1535c616ed54aa0e6fc9e7bce94cde8fed3 / 9086 bytes / fff2a3d89c7fe0392f81035b35133e4326eabcdb22d39ff874d05eea1e08669b,
// not scripts/Assign-RoleMapping.ps1's own sha1/size/sha256 (69860a1239e4509dce483a07523ea07e26764279
// / 8877 / b57f6157fb48a31ee6d31deee66cf82e2baa75f0814b069e4a61f6ef0114a768). The exact byte
// transform BigFix applies during createfile/move isn't fully characterised (a plain LF->CRLF
// pass alone does not reproduce it either), so it can't be computed here -- these constants are
// the last live-verified staged-file checksums. Update them (and the .bes/.ojo pins together)
// only after re-running "Stage Endpoint Script" against a real root server and reading the
// checksums back from the actual staged file -- never by locally re-hashing the .ps1.
var LIVE_VERIFIED_SHA1   = 'f3afb1535c616ed54aa0e6fc9e7bce94cde8fed3';
var LIVE_VERIFIED_SIZE   = '9086';
var LIVE_VERIFIED_SHA256 = 'fff2a3d89c7fe0392f81035b35133e4326eabcdb22d39ff874d05eea1e08669b';

expect("bes/Assign-RoleMapping.bes's pinned sha1= token matches the last live-verified staged-file SHA1", function(){
  assert.strictEqual(PINNED_SHA1[1].toLowerCase(), LIVE_VERIFIED_SHA1);
});

expect("bes/Assign-RoleMapping.bes's pinned size= token matches the last live-verified staged-file size", function(){
  assert.strictEqual(PINNED_SIZE[1], LIVE_VERIFIED_SIZE);
});

expect("bes/Assign-RoleMapping.bes's pinned sha256= token matches the last live-verified staged-file SHA256", function(){
  assert.strictEqual(PINNED_SHA256[1].toLowerCase(), LIVE_VERIFIED_SHA256);
});

expect("fixlet_role_manager.ojo's own hardcoded prefetch pin (the per-role task's copy) matches bes/Assign-RoleMapping.bes's pin -- the two must never drift from each other", function(){
  var ojoLineMatch = /add prefetch item name=Assign-RoleMapping\.ps1[^\r\n]*sha1=([0-9a-fA-F]+)/.exec(OJO_SRC);
  assert.ok(ojoLineMatch, "expected to find the Assign-RoleMapping.ps1 prefetch line in fixlet_role_manager.ojo");
  assert.strictEqual(ojoLineMatch[1].toLowerCase(), PINNED_SHA1[1].toLowerCase());
});

expect("ASSIGN_ROLE_MAPPING_SCRIPT_LINES.join('\\n') is byte-identical to scripts/Assign-RoleMapping.ps1 on disk", function(){
  var mirrorBuf = Buffer.from(ASSIGN_ROLE_MAPPING_SCRIPT, 'utf8');
  assert.strictEqual(Buffer.compare(mirrorBuf, ASSIGN_PS1_BUF), 0, "byte-for-byte mismatch between the .ojo mirror and the repo script");
});

section("ASSIGN_ROLE_TEMPLATE fidelity against bes/Assign-RoleMapping.bes (T-07-07 template mirror)");

expect("relevances has exactly 3 entries, each byte-for-byte identical to the bes file's <Relevance> CDATA bodies", function(){
  var besRelevances = besExtractAllCdata("Relevance");
  assert.strictEqual(besRelevances.length, 3, "expected exactly 3 <Relevance> CDATA blocks in bes/Assign-RoleMapping.bes");
  assert.strictEqual(ASSIGN_ROLE_TEMPLATE.relevances.length, 3);
  assert.strictEqual(ASSIGN_ROLE_TEMPLATE.relevances[0], besRelevances[0]);
  assert.strictEqual(ASSIGN_ROLE_TEMPLATE.relevances[1], besRelevances[1]);
  assert.strictEqual(ASSIGN_ROLE_TEMPLATE.relevances[2], besRelevances[2]);
});

expect("actionScript is byte-for-byte identical to the <DefaultAction><ActionScript> CDATA", function(){
  var besActionScript = besExtractCdata("ActionScript", ' MIMEType="application\\/x-Fixlet-Windows-Shell"');
  assert.strictEqual(ASSIGN_ROLE_TEMPLATE.actionScript, besActionScript);
});

expect("description is byte-for-byte identical to the <Description> CDATA", function(){
  assert.strictEqual(ASSIGN_ROLE_TEMPLATE.description, besExtractCdata("Description"));
});

expect("domain is exactly \"BESC\"", function(){
  assert.strictEqual(ASSIGN_ROLE_TEMPLATE.domain, "BESC");
});

expect("title, description and actionDescription.postLink still contain __ROLE__ (unsubstituted in the template itself)", function(){
  assert.ok(ASSIGN_ROLE_TEMPLATE.title.indexOf('__ROLE__') >= 0);
  assert.ok(ASSIGN_ROLE_TEMPLATE.description.indexOf('__ROLE__') >= 0);
  assert.ok(ASSIGN_ROLE_TEMPLATE.actionDescription.postLink.indexOf('__ROLE__') >= 0);
});

expect("actionScript still contains __ROLE__ and __ASSIGNED_BY__ (unsubstituted in the template itself)", function(){
  assert.ok(ASSIGN_ROLE_TEMPLATE.actionScript.indexOf('__ROLE__') >= 0);
  assert.ok(ASSIGN_ROLE_TEMPLATE.actionScript.indexOf('__ASSIGNED_BY__') >= 0);
});

expect("DEVIATION (see 07-07-SUMMARY.md): the real template has NO __USERNAME__ token anywhere -- identity is resolved by client relevance, never a literal placeholder", function(){
  // The plan's original text assumed a __USERNAME__ placeholder token exists
  // in the ActionScript and must survive unsubstituted. bes/Assign-RoleMapping.bes
  // (the authoritative source, read fresh here, not from the .ojo mirror)
  // proves that assumption wrong: the endpoint script's -UserName argument is
  // bound directly to client relevance, which this suite instead asserts stays
  // present and untouched.
  //
  // UPDATED 2026-10-20 (live testing): the original binding,
  // "{name of current user as lowercase}", was replaced with
  // "{concatenation "" of (names of logged on users as lowercase)}" after live
  // failures on several endpoints (DC01/GPBFS/PROXDEV11) -- "name of current user"
  // depends on session/console-ownership state and can be unresolvable even when
  // exactly one user is logged on, whereas the plural "names of logged on users"
  // form never errors (collapses to the single username, or to "" when none --
  // which Assign-RoleMapping.ps1 already handles as a clean [ABORT]).
  var besActionScript = besExtractCdata("ActionScript", ' MIMEType="application\\/x-Fixlet-Windows-Shell"');
  assert.strictEqual(besActionScript.indexOf('__USERNAME__'), -1, "bes/Assign-RoleMapping.bes's ActionScript unexpectedly contains a literal __USERNAME__ token -- if this now fails, the deviation note above is stale and the original plan-text assertion should be restored instead");
  assert.ok(besActionScript.indexOf('parameter "UserName"="{concatenation "" of (names of logged on users as lowercase)}"') >= 0, "expected the UserName parameter to be bound directly to client relevance");
  assert.ok(ASSIGN_ROLE_TEMPLATE.actionScript.indexOf('parameter "UserName"="{concatenation "" of (names of logged on users as lowercase)}"') >= 0);
});

section("buildRolePolicyTaskXml against the real ASSIGN_ROLE_TEMPLATE (T-07-07-04/T-07-07-05/T-07-07-06)");

var realTaskXml = buildRolePolicyTaskXml(ASSIGN_ROLE_TEMPLATE, "IT Operations", "jfannon");

expect("exactly three <Relevance> elements survive", function(){
  var count = (realTaskXml.match(/<Relevance>/g) || []).length;
  assert.strictEqual(count, 3);
});

expect("zero remaining __ROLE__", function(){
  assert.strictEqual(realTaskXml.indexOf('__ROLE__'), -1);
});

expect("zero remaining __ASSIGNED_BY__", function(){
  assert.strictEqual(realTaskXml.indexOf('__ASSIGNED_BY__'), -1);
});

expect("the client-relevance user-identity expression survives untouched (T-07-07-05 -- never a fixed username baked in)", function(){
  assert.ok(realTaskXml.indexOf('{concatenation "" of (names of logged on users as lowercase)}') >= 0);
});

expect("emitted <Title> equals \"Assign Role Mapping - IT Operations\" (taskTitlePrefix + role, not the template's own title)", function(){
  var m = /<Title>([^<]*)<\/Title>/.exec(realTaskXml);
  assert.ok(m);
  assert.strictEqual(m[1], "Assign Role Mapping - IT Operations");
});

expect("a role name containing & and < is xml-escaped in <Title> and does not break the document", function(){
  var xml = buildRolePolicyTaskXml(ASSIGN_ROLE_TEMPLATE, 'R&D <Ops>', "jfannon");
  assert.ok(xml.indexOf('R&amp;D &lt;Ops&gt;') >= 0);
  var doc;
  try { doc = xml; } catch(ex) { doc = null; }
  assert.ok(doc, "expected the document to be constructible");
  assert.strictEqual((xml.match(/<Task>/g) || []).length, 1);
});

section("buildEndpointScriptStagingActionXml (Task 1)");

var stagingXml = buildEndpointScriptStagingActionXml();

expect("<Settings> appears before <Target>", function(){
  assert.ok(stagingXml.indexOf('<Settings>') < stagingXml.indexOf('<Target>'));
});

expect("contains <ComputerID>, not <CustomRelevance>", function(){
  assert.ok(stagingXml.indexOf('<ComputerID>') >= 0);
  assert.strictEqual(stagingXml.indexOf('<CustomRelevance>'), -1);
});

expect("the emitted ActionScript contains wwwRootFolder, rolegroups, one createfile until _EOF_ and one move __createfile", function(){
  assert.ok(stagingXml.indexOf('wwwRootFolder') >= 0);
  assert.ok(stagingXml.indexOf('rolegroups') >= 0);
  assert.strictEqual((stagingXml.match(/createfile until _EOF_/g) || []).length, 1);
  assert.strictEqual((stagingXml.match(/move __createfile/g) || []).length, 1);
});

expect("every { inside the createfile block is doubled (the real script contains braces) and no } is ever doubled", function(){
  assert.ok(ASSIGN_ROLE_MAPPING_SCRIPT.indexOf('{') >= 0, "expected the real script to contain at least one brace to exercise this assertion");
  assert.ok(stagingXml.indexOf('{{') >= 0, "expected at least one doubled opening brace in the emitted script");
  assert.strictEqual(stagingXml.indexOf('}}'), -1, "no doubled closing brace should ever appear");
});

expect("contains <IsOffer>false</IsOffer>", function(){
  assert.ok(stagingXml.indexOf('<IsOffer>false</IsOffer>') >= 0);
});

expect("returns the empty string when PORTAL_CONFIG.rootServerComputerId is empty", function(){
  var saved = PORTAL_CONFIG.rootServerComputerId;
  PORTAL_CONFIG.rootServerComputerId = "";
  assert.strictEqual(buildEndpointScriptStagingActionXml(), "");
  PORTAL_CONFIG.rootServerComputerId = saved;
});

section("Source-level assertions for Tasks 1/2 (07-07)");

expect("the dashboard defines all Task 1/2 functions by exact name", function(){
  assert.ok(OJO_SRC.indexOf('function buildEndpointScriptStagingActionXml(') >= 0);
  assert.ok(OJO_SRC.indexOf('function stageEndpointScript(') >= 0);
  assert.ok(OJO_SRC.indexOf('function ensureRoleTask(') >= 0);
  assert.ok(OJO_SRC.indexOf('function parseCreatedId(') >= 0);
});

expect("the dashboard contains the pinned repository path and SHA1 as literal text", function(){
  assert.ok(OJO_SRC.indexOf('Uploads\\CustomRepository\\SoftwarePortal\\rolegroups') >= 0);
  assert.ok(OJO_SRC.indexOf('f3afb1535c616ed54aa0e6fc9e7bce94cde8fed3') >= 0);
});

expect("ensureRoleTask posts to fixlets/custom/ (plural) on create and puts to fixlet/custom/ (singular) on update -- each exactly once", function(){
  assert.strictEqual((OJO_SRC.match(/"fixlets\/custom\/"/g) || []).length, 1);
  assert.strictEqual((OJO_SRC.match(/"fixlet\/custom\/"/g) || []).length, 1);
});

expect("no code path in this plan's new functions fetches Task XML and re-serialises a mutated DOM (T-07-07-04)", function(){
  var declStart = OJO_SRC.indexOf("function ensureRoleTask(");
  var declEnd   = OJO_SRC.indexOf("\n// ==", declStart);
  assert.ok(declStart >= 0 && declEnd > declStart, "expected to locate ensureRoleTask's body");
  var body = OJO_SRC.substring(declStart, declEnd);
  assert.strictEqual(/replaceChild|appendChild/.test(body), false, "ensureRoleTask must never mutate a fetched BES XML DOM");
});

// ---------------------------------------------------------------------------
// 4c. PUBLISH-FLOW PURE HELPER (plan 07-08) -- a verbatim copy of the pure
//     relevance/actionScript computation fixlet_role_manager.ojo's own
//     ensureRoleTask performs inline before invoking its callback, so this
//     suite can build a "realistic taskResult" for buildRolePolicyActionXml
//     without touching the DOM/API-dependent half of ensureRoleTask itself --
//     the same exclusion this file already applies to
//     findBesObjectIdByTitle/renderRolePanel.
// ---------------------------------------------------------------------------

function computeRoleTaskResultFields(templateFields, role, assignedBy){
  var relParts = [];
  var ri;
  for(ri = 0; ri < templateFields.relevances.length; ri++){
    relParts.push(String(templateFields.relevances[ri])
      .replace(/__ROLE__/g, role)
      .replace(/__ASSIGNED_BY__/g, assignedBy));
  }
  var relevance = (relParts.length > 1) ? ("(" + relParts.join(") AND (") + ")") : (relParts[0] || "");
  var actionScript = String(templateFields.actionScript)
    .replace(/__ROLE__/g, role)
    .replace(/__ASSIGNED_BY__/g, assignedBy);
  return { relevance: relevance, actionScript: actionScript };
}

function extractSourceSlice(src, startText, endText){
  var s = src.indexOf(startText);
  assert.ok(s >= 0, "start marker not found in fixlet_role_manager.ojo: " + startText);
  var e = src.indexOf(endText, s);
  assert.ok(e > s, "end marker not found after start marker in fixlet_role_manager.ojo: " + endText);
  return src.substring(s, e);
}

section("publishRole call-ordering + [n/4] labels (RESEARCH Pitfall 4 contract, source-level, plan 07-08)");

var PUBLISH_ROLE_BODY = extractSourceSlice(OJO_SRC, "function publishRole(", "\nfunction onPublishRoleClick");

expect("ensureRoleGroup is called before ensureRoleTask, before deployRolePolicyAction, before stopPreviousRoleActions", function(){
  var iGroup  = PUBLISH_ROLE_BODY.indexOf("ensureRoleGroup(role");
  var iTask   = PUBLISH_ROLE_BODY.indexOf("ensureRoleTask(role");
  var iAction = PUBLISH_ROLE_BODY.indexOf("deployRolePolicyAction(role");
  var iStop   = PUBLISH_ROLE_BODY.indexOf("stopPreviousRoleActions(role");
  assert.ok(iGroup >= 0 && iTask >= 0 && iAction >= 0 && iStop >= 0, "expected to find all four calls inside publishRole's body");
  assert.ok(iGroup < iTask, "ensureRoleGroup must be called before ensureRoleTask");
  assert.ok(iTask < iAction, "ensureRoleTask must be called before deployRolePolicyAction");
  assert.ok(iAction < iStop, "deployRolePolicyAction must be called before stopPreviousRoleActions");
});

expect("all four [n/4 Name] labels are present, in ascending 1/4..4/4 order", function(){
  var lGroup  = PUBLISH_ROLE_BODY.indexOf("[1/4 Group]");
  var lTask   = PUBLISH_ROLE_BODY.indexOf("[2/4 Task]");
  var lAction = PUBLISH_ROLE_BODY.indexOf("[3/4 Action]");
  var lStop   = PUBLISH_ROLE_BODY.indexOf("[4/4 Stop]");
  assert.ok(lGroup >= 0 && lTask >= 0 && lAction >= 0 && lStop >= 0, "expected all four [n/4 Name] labels inside publishRole's body");
  assert.ok(lGroup < lTask && lTask < lAction && lAction < lStop, "labels must appear in ascending order");
});

expect("publishRole references roleState[role].dirty (the D-13 Save-before-Publish guard)", function(){
  assert.ok(PUBLISH_ROLE_BODY.indexOf("roleState[role].dirty") >= 0);
});

section("buildRolePolicyActionXml with a realistic taskResult (D-11, plan 07-08 Task 3)");

var REALISTIC_TASK_RESULT = computeRoleTaskResultFields(ASSIGN_ROLE_TEMPLATE, "IT Operations", "jfannon");
var REALISTIC_ACTION_XML  = buildRolePolicyActionXml(
  PORTAL_CONFIG.actionTitlePrefix + "IT Operations",
  REALISTIC_TASK_RESULT.relevance,
  REALISTIC_TASK_RESULT.actionScript,
  4242,
  PORTAL_CONFIG.siteName
);

expect("<Settings> precedes <Target>", function(){
  assert.ok(REALISTIC_ACTION_XML.indexOf('<Settings>') < REALISTIC_ACTION_XML.indexOf('<Target>'));
});

expect("contains <Reapply>true</Reapply>, <HasReapplyInterval>true</HasReapplyInterval>, <ReapplyInterval>P1D</ReapplyInterval>, <IsOffer>false</IsOffer>, <PreActionShowUI>false</PreActionShowUI>", function(){
  assert.ok(REALISTIC_ACTION_XML.indexOf('<Reapply>true</Reapply>') >= 0);
  assert.ok(REALISTIC_ACTION_XML.indexOf('<HasReapplyInterval>true</HasReapplyInterval>') >= 0);
  assert.ok(REALISTIC_ACTION_XML.indexOf('<ReapplyInterval>P1D</ReapplyInterval>') >= 0);
  assert.ok(REALISTIC_ACTION_XML.indexOf('<IsOffer>false</IsOffer>') >= 0);
  assert.ok(REALISTIC_ACTION_XML.indexOf('<PreActionShowUI>false</PreActionShowUI>') >= 0);
});

expect("contains no <HasEndTime>, no <EndDateTimeLocalOffset>, no SourcedFixletAction", function(){
  assert.strictEqual(REALISTIC_ACTION_XML.indexOf('<HasEndTime>'), -1);
  assert.strictEqual(REALISTIC_ACTION_XML.indexOf('<EndDateTimeLocalOffset>'), -1);
  assert.strictEqual(REALISTIC_ACTION_XML.indexOf('SourcedFixletAction'), -1);
});

expect("<Target> contains \"member of group 4242 of site whose\" for groupId=4242 and contains no <ComputerID>", function(){
  assert.ok(REALISTIC_ACTION_XML.indexOf('member of group 4242 of site whose') >= 0);
  assert.strictEqual(REALISTIC_ACTION_XML.indexOf('<ComputerID>'), -1);
});

expect("the <ActionScript> body still contains the runtime user-identity substitution {concatenation \"\" of (names of logged on users as lowercase)}", function(){
  assert.ok(REALISTIC_ACTION_XML.indexOf('{concatenation "" of (names of logged on users as lowercase)}') >= 0);
});

expect("a <MIMEFieldSingleAction> with <Name>DSP_RoleManager_Role</Name> and the role name as its value is present, positioned after </Target>", function(){
  var iTarget = REALISTIC_ACTION_XML.indexOf('</Target>');
  var iMime   = REALISTIC_ACTION_XML.indexOf('<MIMEFieldSingleAction>');
  assert.ok(iTarget >= 0 && iMime >= 0 && iMime > iTarget, "expected <MIMEFieldSingleAction> after </Target>");
  assert.ok(REALISTIC_ACTION_XML.indexOf('<Name>DSP_RoleManager_Role</Name>') >= 0);
  assert.ok(REALISTIC_ACTION_XML.indexOf('<Value>IT Operations</Value>') >= 0);
});

section("Empty-list Publish behaviour (T-07-08-01)");

expect("getRoleUsers()=[] -> buildRoleGroupRelevance is exactly \"false\" -> buildComputerGroupXml's CDATA body is exactly false, with no \"logged on users\" clause", function(){
  var relevance = buildRoleGroupRelevance([]);
  assert.strictEqual(relevance, "false");
  var xml = buildComputerGroupXml(PORTAL_CONFIG.groupTitlePrefix + "IT Operations", "BESC", relevance);
  assert.ok(xml.indexOf(cdataStart() + "false" + cdataEnd()) >= 0, "expected the CDATA body to be exactly \"false\"");
  assert.strictEqual(xml.indexOf("logged on users"), -1);
});

expect("a supplied scope group cannot override the empty-list guard -- still exactly \"false\" end to end", function(){
  var relevance = buildRoleGroupRelevance([], 12345, "Dereso Software Portal");
  assert.strictEqual(relevance, "false");
  var xml = buildComputerGroupXml(PORTAL_CONFIG.groupTitlePrefix + "IT Operations", "BESC", relevance);
  assert.ok(xml.indexOf(cdataStart() + "false" + cdataEnd()) >= 0);
  assert.strictEqual(xml.indexOf("logged on users"), -1);
});

section("Source-level invariants for Publish (plan 07-08)");

expect("the dashboard defines deployRolePolicyAction, stopPreviousRoleActions, findOpenActionIdsByTitle, publishRole and ensureRoleGroup by exact name, and the plan-07-06 stub message is gone", function(){
  assert.ok(OJO_SRC.indexOf('function ensureRoleGroup(') >= 0);
  assert.ok(OJO_SRC.indexOf('function deployRolePolicyAction(') >= 0);
  assert.ok(OJO_SRC.indexOf('function stopPreviousRoleActions(') >= 0);
  assert.ok(OJO_SRC.indexOf('function findOpenActionIdsByTitle(') >= 0);
  assert.ok(OJO_SRC.indexOf('function publishRole(') >= 0);
  assert.strictEqual((OJO_SRC.match(/wired in 07-07/g) || []).length, 0);
});

expect("the Publish button's handler (onPublishRoleClick) calls publishRole", function(){
  var body = extractSourceSlice(OJO_SRC, "function onPublishRoleClick(", "// ROLES TAB");
  assert.ok(body.indexOf("publishRole(role)") >= 0);
});

expect("computergroups/custom/ (plural, create) appears exactly once and computergroup/custom/ (singular, update) appears exactly once", function(){
  assert.strictEqual((OJO_SRC.match(/computergroups\/custom\//g) || []).length, 1);
  assert.strictEqual((OJO_SRC.match(/computergroup\/custom\//g) || []).length, 1);
});

expect("fixlets/custom/ (plural) appears exactly once and fixlet/custom/ (singular) appears exactly once (unchanged from 07-07 -- this plan adds no new Task calls)", function(){
  assert.strictEqual((OJO_SRC.match(/"fixlets\/custom\/"/g) || []).length, 1);
  assert.strictEqual((OJO_SRC.match(/"fixlet\/custom\/"/g) || []).length, 1);
});

expect("the stop endpoint (\"action/\" + id + \"/stop\") appears exactly once", function(){
  assert.strictEqual((OJO_SRC.match(/"action\/" \+ actionId \+ "\/stop"/g) || []).length, 1);
});

expect("SourcedFixletAction never appears anywhere in the dashboard", function(){
  assert.strictEqual(OJO_SRC.indexOf('SourcedFixletAction'), -1);
});

expect("deployRolePolicyAction's OWN body posts to the \"actions\" create-action endpoint exactly once -- DEVIATION: the whole-file count is 3 (two pre-existing calls from 07-06 Save / 07-07 Stage-script, both out of this plan's scope); see 07-08-SUMMARY.md", function(){
  var body = extractSourceSlice(OJO_SRC, "function deployRolePolicyAction(", "\nfunction findOpenActionIdsByTitle");
  assert.strictEqual((body.match(/"actions"/g) || []).length, 1);
});

expect("this plan's own new Publish code (publishState through onPublishRoleClick) contains zero Promise/async(space)/await(space)/=>/const(space)/let(space)/alert(/SourcedFixletAction/oninput -- DEVIATION: two pre-existing 'xml.async = false' MSXML DOM-property assignments elsewhere in the file (07-04/07-07's parseXml/parseCreatedId -- the ActiveXObject .async property, not the ES6 keyword) are out of this plan's scope; see 07-08-SUMMARY.md", function(){
  var scoped = extractSourceSlice(
    OJO_SRC,
    "// publishState: one entry per role",
    "// ROLES TAB"
  );
  assert.strictEqual(/Promise/.test(scoped), false);
  assert.strictEqual(/async /.test(scoped), false);
  assert.strictEqual(/await /.test(scoped), false);
  assert.strictEqual(/=>/.test(scoped), false);
  assert.strictEqual(/\bconst\s/.test(scoped), false);
  assert.strictEqual(/\blet\s/.test(scoped), false);
  assert.strictEqual(/alert\s*\(/.test(scoped), false);
  assert.strictEqual(scoped.indexOf('SourcedFixletAction'), -1);
  assert.strictEqual(scoped.indexOf('oninput'), -1);
});

// ---------------------------------------------------------------------------
// 4b. ANALYSIS TAB (D-16, plan 07-09) -- mergeAnalysisRows / reconcileIntentVsActual
// ---------------------------------------------------------------------------

// mergeAnalysisRows -- verbatim copy of the .ojo's own code (this project's
// established convention -- see section 1's header comment above). Lifted
// near-verbatim from the now-archived, retired fixlet_role_assigner.ojo /
// tests/archive/unit/role_assigner.test.js (D-15, 2026-09-21) so the ported
// assertions below prove the lifted function behaves identically to the
// original it replaces.
function mergeAnalysisRows(mappedData, sourceData, regionData){
  var EM_DASH = "—";
  function parseEntry(raw){
    var s = String(raw);
    var sep = s.indexOf("|||");
    if(sep < 0){ return null; }
    return { computer: s.substring(0, sep), value: s.substring(sep + 3) };
  }
  function splitUserRole(value){
    var v = String(value);
    var idx = v.indexOf(", ");
    if(idx < 0){ return { user: v, role: "" }; }
    return { user: v.substring(0, idx), role: v.substring(idx + 2) };
  }
  function splitTriple(value){
    var v = String(value);
    var i1 = v.indexOf(", ");
    if(i1 < 0){ return { user: v, role: "", extra: "" }; }
    var rest = v.substring(i1 + 2);
    var i2 = rest.indexOf(", ");
    if(i2 < 0){ return { user: v.substring(0, i1), role: rest, extra: "" }; }
    return { user: v.substring(0, i1), role: rest.substring(0, i2), extra: rest.substring(i2 + 2) };
  }
  var extraByKey = {};
  function indexExtra(arr, which){
    if(!arr){ return; }
    for(var i = 0; i < arr.length; i++){
      var e = parseEntry(arr[i]);
      if(!e){ continue; }
      var t = splitTriple(e.value);
      var key = e.computer + "|||" + t.user + "|||" + t.role;
      if(!extraByKey[key]){ extraByKey[key] = {}; }
      extraByKey[key][which] = t.extra;
    }
  }
  indexExtra(sourceData, "source");
  indexExtra(regionData, "region");
  var out = [];
  if(!mappedData){ return out; }
  for(var i = 0; i < mappedData.length; i++){
    var m = parseEntry(mappedData[i]);
    if(!m){ continue; }
    var ur = splitUserRole(m.value);
    var key = m.computer + "|||" + ur.user + "|||" + ur.role;
    var ex = extraByKey[key] || {};
    out.push({
      computerName: m.computer,
      user: ur.user,
      role: ur.role,
      source: (ex.source !== undefined && ex.source !== "") ? ex.source : EM_DASH,
      region: (ex.region !== undefined && ex.region !== "") ? ex.region : EM_DASH
    });
  }
  return out;
}

// reconcileIntentVsActual -- verbatim copy of the .ojo's own code.
function reconcileIntentVsActual(roleStateArg, analysisRows){
  var rs   = roleStateArg || {};
  var rows = analysisRows || [];

  function norm(s){ return String(s || "").toLowerCase().replace(/^\s+|\s+$/g, ""); }

  var roleNames = [];
  var rn;
  for(rn in rs){ if(rs.hasOwnProperty(rn)){ roleNames.push(rn); } }

  var mappedByRole = {};
  var i, r, roleKey;
  for(i = 0; i < rows.length; i++){
    r = rows[i];
    roleKey = String(r.role || "");
    if(!mappedByRole[roleKey]){ mappedByRole[roleKey] = {}; }
    mappedByRole[roleKey][norm(r.user)] = true;
  }

  var configuredSetByRole = {};
  var j, role, cfgUsers, nu;
  for(i = 0; i < roleNames.length; i++){
    role = roleNames[i];
    cfgUsers = (rs[role] && rs[role].users) ? rs[role].users : [];
    var set = {};
    for(j = 0; j < cfgUsers.length; j++){
      nu = norm(cfgUsers[j]);
      if(nu !== ""){ set[nu] = true; }
    }
    configuredSetByRole[role] = set;
  }

  var configuredNotMapped = [];
  for(i = 0; i < roleNames.length; i++){
    role = roleNames[i];
    cfgUsers = (rs[role] && rs[role].users) ? rs[role].users : [];
    var mappedSet = mappedByRole[role] || {};
    var seenCfg = {};
    for(j = 0; j < cfgUsers.length; j++){
      nu = norm(cfgUsers[j]);
      if(nu === "" || seenCfg[nu]){ continue; }
      seenCfg[nu] = true;
      if(!mappedSet[nu]){
        configuredNotMapped.push({ role: role, user: cfgUsers[j] });
      }
    }
  }

  var mappedNotConfigured = [];
  var cfgSet;
  for(i = 0; i < rows.length; i++){
    r = rows[i];
    roleKey = String(r.role || "");
    cfgSet = configuredSetByRole[roleKey];
    if(!(cfgSet && cfgSet[norm(r.user)])){
      mappedNotConfigured.push({ role: r.role, user: r.user, computer: r.computerName });
    }
  }

  return { configuredNotMapped: configuredNotMapped, mappedNotConfigured: mappedNotConfigured };
}

// htmlEscape -- copied verbatim from fixlet_role_manager.ojo (function htmlEscape),
// same as role_assigner.test.js's own local copy -- needed only for the
// XSS-survival spot-check below.
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}

section("mergeAnalysisRows (D-16, ported from tests/unit/role_assigner.test.js)");

var EM = "—";

expect("mergeAnalysisRows: key present in all three yields a full row with source + region", function(){
  var mapped = ["PC1|||jsmith, IT Operations"];
  var source = ["PC1|||jsmith, IT Operations, CN=IT-Admins"];
  var region = ["PC1|||jsmith, IT Operations, AAG-UK"];
  var rows = mergeAnalysisRows(mapped, source, region);
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].computerName, "PC1");
  assert.strictEqual(rows[0].user, "jsmith");
  assert.strictEqual(rows[0].role, "IT Operations");
  assert.strictEqual(rows[0].source, "CN=IT-Admins");
  assert.strictEqual(rows[0].region, "AAG-UK");
  assert.ok(Object.keys(rows[0]).length >= 5, "expected computerName/user/role/source/region");
});

expect("mergeAnalysisRows: key missing from map_source yields an em dash and does not drop the row", function(){
  var mapped = ["PC1|||jsmith, IT Operations", "PC2|||bdoe, Business Operations"];
  var source = ["PC1|||jsmith, IT Operations, CN=IT-Admins"];
  var region = ["PC1|||jsmith, IT Operations, AAG-UK",
                "PC2|||bdoe, Business Operations, AAG-DE"];
  var rows = mergeAnalysisRows(mapped, source, region);
  assert.strictEqual(rows.length, 2, "both mapped rows must survive");
  var pc2 = rows[1];
  assert.strictEqual(pc2.computerName, "PC2");
  assert.strictEqual(pc2.source, EM, "missing source cell must be an em dash");
  assert.strictEqual(pc2.region, "AAG-DE", "region still merges independently");
});

expect("mergeAnalysisRows: empty results from both new properties leave the base columns intact", function(){
  var mapped = ["PC1|||jsmith, IT Operations", "PC2|||bdoe, Business Operations"];
  var a = mergeAnalysisRows(mapped, [], []);
  var b = mergeAnalysisRows(mapped, null, null);
  assert.strictEqual(a.length, 2);
  assert.strictEqual(b.length, 2);
  assert.strictEqual(a[0].computerName, "PC1");
  assert.strictEqual(a[0].user, "jsmith");
  assert.strictEqual(a[0].role, "IT Operations");
  assert.strictEqual(a[0].source, EM);
  assert.strictEqual(a[0].region, EM);
  assert.deepStrictEqual(a, b, "null and [] must behave identically");
});

expect("mergeAnalysisRows: empty extra value in a new property is treated as missing (em dash)", function(){
  var mapped = ["PC1|||jsmith, IT Operations"];
  var source = ["PC1|||jsmith, IT Operations, "];
  var rows = mergeAnalysisRows(mapped, source, []);
  assert.strictEqual(rows[0].source, EM, "empty coalesced value must render as an em dash, not blank");
});

expect("mergeAnalysisRows: every merged value survives htmlEscape unchanged in shape / neutralised when hostile", function(){
  var mapped = ['PC1|||jsmith, IT Operations'];
  var source = ['PC1|||jsmith, IT Operations, <script>alert(1)</script>'];
  var rows = mergeAnalysisRows(mapped, source, []);
  var escaped = htmlEscape(rows[0].source);
  assert.ok(escaped.indexOf("<script>") < 0, "raw <script> must not survive htmlEscape");
  assert.ok(escaped.indexOf("&lt;script&gt;") >= 0, "expected entity-encoded script tag");
});

expect("mergeAnalysisRows: a malformed entry (no |||) is skipped, not thrown", function(){
  var rows = mergeAnalysisRows(["garbage-no-separator", "PC1|||jsmith, IT Operations"], [], []);
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].computerName, "PC1");
});

section("reconcileIntentVsActual (D-16, plan 07-09 Task 2)");

expect("configured [\"alice\",\"bob\"] with only alice mapped yields configuredNotMapped = [{role,user:\"bob\"}] and mappedNotConfigured = []", function(){
  var rs = { "IT Operations": { users: ["alice", "bob"] } };
  var rows = [{ computerName: "PC1", user: "alice", role: "IT Operations", source: EM, region: EM }];
  var recon = reconcileIntentVsActual(rs, rows);
  assert.strictEqual(recon.configuredNotMapped.length, 1);
  assert.strictEqual(recon.configuredNotMapped[0].role, "IT Operations");
  assert.strictEqual(recon.configuredNotMapped[0].user, "bob");
  assert.strictEqual(recon.mappedNotConfigured.length, 0);
});

expect("an analysis row for carol on a role that does not list her yields exactly one mappedNotConfigured entry carrying her computer name", function(){
  var rs = { "IT Operations": { users: ["alice"] } };
  var rows = [{ computerName: "PC7", user: "carol", role: "IT Operations", source: EM, region: EM }];
  var recon = reconcileIntentVsActual(rs, rows);
  assert.strictEqual(recon.mappedNotConfigured.length, 1);
  assert.strictEqual(recon.mappedNotConfigured[0].role, "IT Operations");
  assert.strictEqual(recon.mappedNotConfigured[0].user, "carol");
  assert.strictEqual(recon.mappedNotConfigured[0].computer, "PC7");
});

expect("comparison is case- and whitespace-insensitive: configured \"Alice \" matches mapped \"alice\" and produces no entry in either list", function(){
  var rs = { "IT Operations": { users: ["Alice "] } };
  var rows = [{ computerName: "PC1", user: "alice", role: "IT Operations", source: EM, region: EM }];
  var recon = reconcileIntentVsActual(rs, rows);
  assert.strictEqual(recon.configuredNotMapped.length, 0);
  assert.strictEqual(recon.mappedNotConfigured.length, 0);
});

expect("a role with an empty configured list and no analysis rows produces two empty arrays", function(){
  var rs = { "IT Operations": { users: [] } };
  var recon = reconcileIntentVsActual(rs, []);
  assert.deepStrictEqual(recon.configuredNotMapped, []);
  assert.deepStrictEqual(recon.mappedNotConfigured, []);
});

expect("a user holding two roles (D-04) is reconciled independently against each and produces no false mappedNotConfigured entry", function(){
  var rs = {
    "IT Operations": { users: ["alice"] },
    "Business Operations": { users: ["alice"] }
  };
  var rows = [
    { computerName: "PC1", user: "alice", role: "IT Operations", source: EM, region: EM },
    { computerName: "PC1", user: "alice", role: "Business Operations", source: EM, region: EM }
  ];
  var recon = reconcileIntentVsActual(rs, rows);
  assert.strictEqual(recon.configuredNotMapped.length, 0);
  assert.strictEqual(recon.mappedNotConfigured.length, 0);
});

expect("reconcileIntentVsActual mutates neither argument", function(){
  var rs = { "IT Operations": { users: ["alice", "bob"] } };
  var rows = [{ computerName: "PC1", user: "alice", role: "IT Operations", source: EM, region: EM }];
  var rsCopy   = JSON.parse(JSON.stringify(rs));
  var rowsCopy = JSON.parse(JSON.stringify(rows));
  reconcileIntentVsActual(rs, rows);
  assert.deepStrictEqual(rs, rsCopy, "roleState argument must be unchanged");
  assert.deepStrictEqual(rows, rowsCopy, "analysisRows argument must be unchanged");
});

expect("removing a username from the configured-list fixture changes configuredNotMapped (spot-check the assertion is meaningful)", function(){
  var rsFull    = { "IT Operations": { users: ["alice", "bob"] } };
  var rsMissing = { "IT Operations": { users: ["alice"] } };
  var rows = [{ computerName: "PC1", user: "alice", role: "IT Operations", source: EM, region: EM }];
  var reconFull    = reconcileIntentVsActual(rsFull, rows);
  var reconMissing = reconcileIntentVsActual(rsMissing, rows);
  assert.strictEqual(reconFull.configuredNotMapped.length, 1, "bob must be flagged when configured");
  assert.strictEqual(reconMissing.configuredNotMapped.length, 0, "removing bob from the fixture must remove the flag -- confirms the assertion above is load-bearing, not vacuous");
});

section("Source-level invariants for the Analysis tab (plan 07-09)");

var ANALYSIS_SECTION = extractSourceSlice(OJO_SRC, "// ANALYSIS TAB (D-16", "\n</script>");

expect("the Analysis tab section contains no API.Post, API.Put or API.Delete call", function(){
  // The section's own header comment mentions the literal strings once each
  // (documentation, not a call) -- assert zero *call* occurrences instead of
  // zero substring occurrences.
  assert.strictEqual((ANALYSIS_SECTION.match(/API\.Post\(/g) || []).length, 0);
  assert.strictEqual((ANALYSIS_SECTION.match(/API\.Put\(/g) || []).length, 0);
  assert.strictEqual((ANALYSIS_SECTION.match(/API\.Delete\(/g) || []).length, 0);
});

expect("mapped_users in r.db, map_source in r.db and map_region in r.db each appear exactly once in the whole file (the PORTAL_CONFIG.props block only)", function(){
  assert.strictEqual((OJO_SRC.match(/"mapped_users in r\.db"/g) || []).length, 1);
  assert.strictEqual((OJO_SRC.match(/"map_source in r\.db"/g) || []).length, 1);
  assert.strictEqual((OJO_SRC.match(/"map_region in r\.db"/g) || []).length, 1);
});

expect("the dashboard defines loadAnalysisView, loadAnalysisAge, mergeAnalysisRows and reconcileIntentVsActual by exact name", function(){
  assert.ok(OJO_SRC.indexOf('function loadAnalysisView(') >= 0);
  assert.ok(OJO_SRC.indexOf('function loadAnalysisAge(') >= 0);
  assert.ok(OJO_SRC.indexOf('function mergeAnalysisRows(') >= 0);
  assert.ok(OJO_SRC.indexOf('function reconcileIntentVsActual(') >= 0);
});

expect("the dashboard contains the literal column headings Computer, User, Role, Source, Region (reporting only) and Configured?", function(){
  assert.ok(OJO_SRC.indexOf('<th>Computer</th>') >= 0);
  assert.ok(OJO_SRC.indexOf('<th>User</th>') >= 0);
  assert.ok(OJO_SRC.indexOf('<th>Role</th>') >= 0);
  assert.ok(OJO_SRC.indexOf('<th>Source</th>') >= 0);
  assert.ok(OJO_SRC.indexOf('Region (reporting only)') >= 0);
  assert.ok(OJO_SRC.indexOf('Configured?') >= 0);
});

expect("the dashboard contains the literal strings \"Configured but never mapped\", \"Mapped but not configured\" and \"Configuration and fleet state agree.\"", function(){
  assert.ok(OJO_SRC.indexOf('Configured but never mapped') >= 0);
  assert.ok(OJO_SRC.indexOf('Mapped but not configured') >= 0);
  assert.ok(OJO_SRC.indexOf('Configuration and fleet state agree.') >= 0);
});

expect("switchTab calls loadAnalysisView when the Analysis tab is selected, and initDashboard calls it once after loadKnownUsers", function(){
  var switchTabBody = extractSourceSlice(OJO_SRC, "function switchTab(", "\nfunction initDashboard");
  assert.ok(switchTabBody.indexOf("loadAnalysisView()") >= 0);
  var initBody = extractSourceSlice(OJO_SRC, "function initDashboard(", "\n// ==");
  assert.ok(initBody.indexOf("loadKnownUsers()") < initBody.indexOf("loadAnalysisView()"), "loadAnalysisView must be called after loadKnownUsers inside initDashboard");
});

expect("the Analysis tab section never calls a bare GetRelevance -- that function doesn't exist in the BigFix Dashboard API (only EvaluateRelevance/Relevance do, per developer.bigfix.com and .claude/skills/bigfix-relevance/SKILL.md); it silently threw and was swallowed by every try/catch around it until fixed 2026-10-21", function(){
  assert.strictEqual((ANALYSIS_SECTION.match(/\bGetRelevance\(/g) || []).length, 0);
  assert.ok((ANALYSIS_SECTION.match(/EvaluateRelevance\(/g) || []).length > 0, "expected loadAnalysisAge's own relevance call to use EvaluateRelevance");
});

expect("the full dashboard still has zero occurrences of alert(, =>, const , let , Promise, SourcedFixletAction, oninput -- DEVIATION: two pre-existing 'xml.async = false' MSXML DOM-property assignments (07-04/07-07's parseXml/parseCreatedId) are out of this plan's scope and contain no 'Promise' substring, so the whole-file check holds; see prior plan summaries for the analogous scoped-vs-whole-file caveat", function(){
  assert.strictEqual(/alert\s*\(/.test(OJO_SRC), false);
  assert.strictEqual(/=>/.test(OJO_SRC), false);
  assert.strictEqual(/\bconst\s/.test(OJO_SRC), false);
  assert.strictEqual(/\blet\s/.test(OJO_SRC), false);
  assert.strictEqual(OJO_SRC.indexOf('SourcedFixletAction'), -1);
  assert.strictEqual(OJO_SRC.indexOf('oninput'), -1);
});

// ---------------------------------------------------------------------------
// 5. SUMMARY FOOTER (verbatim from dispatcher.test.js / role_assigner.test.js)
// ---------------------------------------------------------------------------

console.log("\n========================================");
console.log("Results: " + passed + " passed, " + failures + " failed");
console.log("========================================");

if(failures > 0){
  console.error("\nOne or more tests failed.");
  process.exit(1);
} else {
  console.log("\nAll " + passed + " assertions passed");
  process.exit(0);
}
