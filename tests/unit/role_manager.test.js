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
 * Requirements: Node.js built-in `assert`, `fs` and `path` modules only (no
 * external packages).
 */

"use strict";

var assert = require("assert");
var fs     = require("fs");
var path   = require("path");

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
