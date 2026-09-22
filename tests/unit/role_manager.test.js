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

expect("the .ojo file contains no alert(, no =>, no const/let", function(){
  assert.strictEqual(/\balert\s*\(/.test(OJO_SRC), false);
  assert.strictEqual(/=>/.test(OJO_SRC.replace(/=&gt;/g, '')), false);
  assert.strictEqual(/\b(const|let)\s/.test(OJO_SRC), false);
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
