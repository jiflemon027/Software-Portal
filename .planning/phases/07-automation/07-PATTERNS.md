# Phase 7: End-to-End Automation (Operator-Role-Group model) - Pattern Map

**Mapped:** 2026-09-21
**Files analyzed:** 12 (new/modified), 6 archive-moves (no pattern extraction needed)
**Analogs found:** 11 / 12

> Supersedes `.planning/phases/07-automation/archive/07-PATTERNS.md` (the rejected Axonius
> reference-DB pipeline pattern map). That file maps files that are now retired
> (`Import-AxoniousExport.ps1`, per-region policy fixlets, `Reconcile-LocalRoles.ps1`, etc.) and
> must not be reused. This file is built fresh against `07-CONTEXT.md` (2026-09-21 rewrite) and
> `07-RESEARCH.md` (2026-09-21 rewrite) only.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Existing Dashboards/fixlet_role_manager.ojo` (NEW) | component (OJO dashboard) | request-response (REST) + CRUD (SQLite audit) | `Existing Dashboards/fixlet_dispatcher.ojo` (deploy/staging) + `Existing Dashboards/fixlet_role_assigner.ojo` (Analysis view, base64/XML helpers) + `Existing Dashboards/fixlet_role_admin.ojo` (tab-switch shell) | role-match (composite - no single dashboard already does group-create + action-deploy + root-server-write) |
| `scripts/Sync-RoleGroups.ps1` (NEW, D-06 drift-check, optional) | service / batch script | batch (root-server REST re-sync) | `scripts/Invoke-ContentSync.ps1` (root-server scheduled-task script shape) + `scripts/Assign-RoleMapping.ps1` (D-12 upsert discipline reference) | role-match |
| Root-server `RoleUsers`/`RolePublishRun` audit-table DDL (embedded in the dashboard's ActionScript per D-07, not a standalone .ps1) | migration (SQLite DDL) | CRUD | `Dashboard_4_samples/Initialize-RoleDb.ps1` (DDL shape, `PRAGMA table_info` migration idiom, `CREATE TABLE IF NOT EXISTS`) | exact (schema-shape analog) |
| `tests/unit/role_manager.test.js` (NEW) | test | transform (pure-function extraction) | `tests/unit/role_assigner.test.js` | exact |
| `tests/pester/Initialize-RoleUsersDb.Tests.ps1` (NEW) | test | CRUD (DDL idempotency) | `tests/pester/Initialize-RoleDb.Tests.ps1` | exact |
| `tests/pester/InitCurrentUserTask.Tests.ps1` (NEW) | test | transform (string/regex assertion against .bes) | `tests/pester/RoleRefPolicyBes.Tests.ps1` (superseded pipeline, still the closest ".bes content assertion" shape - read structure only, not its policy-template subject) | role-match |
| `Dashboard_4_samples/"Init  Current User and UserRole DB.bes"` (EDIT - Pattern 6 diff) | migration / task (BigFix Task, root-server-authored, endpoint-executed) | event-driven (logon-triggered scheduled task) | itself (in-place diff - see Pattern Assignments) | exact (self-analog, diff only) |
| `scripts/Register-AutomationTasks.ps1` (EDIT - remove stale rows, optionally add Sync-RoleGroups) | config / service registration | batch | itself (existing `$AutomationTaskTable` convention) | exact (self-analog, diff only) |
| `config/PipelineConfig.defaults.json` (EDIT - remove dead Axonius keys, optional/discretionary) | config | CRUD (config file) | itself | exact (self-analog, diff only) |
| `Existing Dashboards/archive/fixlet_role_admin.ojo` (MOVE, D-15) | n/a (archival) | n/a | n/a - `git mv`, no pattern extraction needed | n/a |
| `Existing Dashboards/archive/fixlet_role_assigner.ojo` (MOVE, D-15) | n/a (archival) | n/a | n/a - `git mv`, no pattern extraction needed | n/a |
| `scripts/archive/{Import-AxoniousExport,Publish-RoleSnapshot,Reconcile-LocalRoles}.ps1`, `bes/archive/RoleRef-Policy-template.bes` (MOVE, D-15) | n/a (archival) | n/a | n/a - `git mv`, no pattern extraction needed | n/a |
| `tests/unit/role_admin.test.js`, `tests/unit/role_assigner.test.js` (fate TBD - Open Question, Wave 0 gap) | test | n/a | n/a - planner decision: delete alongside archived `.ojo` subjects, or retain as frozen regression snapshots | n/a |

**Reused as-is (no pattern extraction needed - already-built, smoke-tested; this phase only wires them from the new generator):**
- `bes/Assign-RoleMapping.bes` - endpoint policy-action Task template (`__ROLE__`/`__ASSIGNED_BY__` tokens)
- `scripts/Assign-RoleMapping.ps1` - endpoint upsert script (D-12 discipline)
- `Dashboard_4_samples/Sqlite-Helper.ps1` - `Invoke-SqliteCommand`

---

## Pattern Assignments

### `Existing Dashboards/fixlet_role_manager.ojo` (component, request-response + CRUD)

This is a composite build - no single existing dashboard already does "find-or-create Computer
Group + find-or-create Task + deploy SingleAction + root-server audit write + read-only Analysis
view" in one place. Assemble from three analogs, each covering one slice.

**Analog 1: `Existing Dashboards/fixlet_dispatcher.ojo`** - REST deploy mechanics, root-server
staging, and shared XML-escaping helpers.

**PORTAL_CONFIG + root-server ComputerID via `<?relevance?>` tag** (lines 33-51):
```javascript
var PORTAL_CONFIG = {
  defaultExpirationDays: 7,
   rootServerComputerId: '<?relevance concatenation "" of ((id of it as string) of bes computers whose(exists value whose (it = "BES Root Server") of result (it, bes property "BES Relay Service Installed"))) ?>'
};
```
Reuse verbatim for the new dashboard's `PORTAL_CONFIG.rootServerComputerId` (D-07's audit-write
target) and add `PORTAL_CONFIG.roles` (array, D-03) alongside it, mirroring
`fixlet_role_assigner.ojo`'s `PORTAL_CONFIG.roles` shape (see Analog 2 below).

**XML/escaping helpers** (lines 470-481, identical copies also exist in `fixlet_role_assigner.ojo`
lines 98-109 - either source is fine, they are byte-identical):
```javascript
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
```

**Find-by-title session relevance** (line 998, adapt for Computer Groups AND Tasks - Pattern 1/3
step 1 in RESEARCH.md):
```javascript
var rel = '(id of it as string & "|||" & name of it & "|||" & name of (site of it) & "|||" & (if (server based flag of it) then "Server Based" else if (automatic flag of it) then "Automatic" else "Manual")) of bes computer groups';
var data = EvaluateRelevance(rel);
```
RESEARCH.md's `findComputerGroupIdByTitle()` (Code Examples section) is the trimmed single-title
version of this same idiom - use that form for the generator's find-or-create, not the "load
all groups for a dropdown" form (which is dispatcher's own use case, not this phase's).

**escapeActionScriptBraces - asymmetric brace doubling** (lines 622-632, load-bearing comment
explains WHY - do not "fix" this to double both braces):
```javascript
// Only the OPENING brace is doubled. "{{" is BigFix ActionScript's escape for a
// literal "{" -- it never opens a real {relevance} substitution, so a later plain
// "}" has nothing to close and passes through as a literal character on its own.
// Doubling "}" too produces a stray extra "}" ...
function escapeActionScriptBraces(s){
  return String(s).replace(/\{/g, "{{");
}
```
Needed if the D-07 root-server audit-write ActionScript embeds inline PowerShell via
`createfile` (see Pattern 5 below) - not needed for the group/action generator XML itself
(no createfile there).

**Root-server staging SingleAction (D-07's direct analog)** (lines 660-699 - `buildStagingActionXml`):
```javascript
function buildStagingActionXml(prefetchLines, title){
  if(!PORTAL_CONFIG.rootServerComputerId){ return ""; }
  ...
  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <SingleAction>\r\n';
  xml += '    <Title>' + xmlEscape('Dereso_Stage ' + (title || "") + ' ' + stamp) + '</Title>\r\n';
  xml += '    <Relevance>true</Relevance>\r\n';
  xml += '    <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">';
  xml += cdataStart() + xmlCDataSafe(script) + cdataEnd();
  xml += '</ActionScript>\r\n';
  xml += '    <Settings>\r\n';
  xml += '      <ActionUITitle>Stage prefetch files</ActionUITitle>\r\n';
  xml += '      <PreActionShowUI>false</PreActionShowUI>\r\n';
  xml += '      <HasEndTime>true</HasEndTime>\r\n';
  xml += '      <EndDateTimeLocalOffset>P1D</EndDateTimeLocalOffset>\r\n';
  ...
  xml += '    </Settings>\r\n';
  xml += '    <Target>\r\n';
  xml += '      <ComputerID>' + xmlEscape(PORTAL_CONFIG.rootServerComputerId) + '</ComputerID>\r\n';
  xml += '    </Target>\r\n';
  ...
}
```
This is THE template for the new D-07 audit-write action: `<Target><ComputerID>` (a single fixed
computer, not `<CustomRelevance>`), `<Relevance>true</Relevance>`, and a `createfile`-embedded
script built the same way `buildStagingActionScript()` (lines 637-658) builds its PowerShell
payload (`delete __createfile` / `createfile until _EOF_` / `escapeActionScriptBraces(...)` /
`move __createfile "<path>"` / `waithidden powershell.exe ...`). Swap the payload for an inline
`RoleUsers`/`RolePublishRun` upsert using `Sqlite-Helper.ps1` + `Invoke-SqliteCommand` (same
helper the endpoint script already dot-sources).

**Deploy with inline per-step error feedback, no `alert()`** (lines 1173-1244 - `deployFixlet`):
the exact sequencing discipline RESEARCH.md's Pitfall 4 calls for (Group PUT, then Task, then
Action, each step's success/failure surfaced separately):
```javascript
var errEl    = document.getElementById("deployError");
var resultEl = document.getElementById("deployResult");
if(errEl)    { errEl.style.display    = "none"; errEl.innerHTML    = ""; }
if(resultEl) { resultEl.style.display = "none"; resultEl.innerHTML = ""; }
...
API.Post("actions", xml, function(e, s, b){
  if(s === 200 || s === 201){
    ...
    if(resultEl){ resultEl.style.display = ""; resultEl.innerHTML = htmlEscape(...); }
  } else {
    setStatus("Deploy failed: status=" + s);
    if(errEl){ errEl.style.display = ""; errEl.innerHTML = htmlEscape("Deploy failed: status=" + s + " -- " + (e || "")); }
  }
});
```
Chain three of these (Group, Task, Action) for the per-role Publish flow (D-13), reporting each
step's own errEl/resultEl pair rather than a single combined status - this is what lets an
operator tell exactly which of the three BES objects is stale after a partial failure.

**`parseActionId(body)`** (lines 507-527) - reuse verbatim for extracting the new Action/Task's
ID from a POST response (needed by the "stop previous action" branch if Pitfall 7's Option B is
chosen).

**Rewrite prefetch URLs** (lines 591-599) - not needed for the group/action generator itself
(no prefetch in the generated `Assign-RoleMapping.bes` copy; it already prefetches
`Assign-RoleMapping.ps1` from a fixed Custom Repository path per role-template, not per-deploy),
but keep for reference if a future Sync-RoleGroups drift-check ever needs to restage.

**Analog 2: `Existing Dashboards/fixlet_role_assigner.ojo`** - PORTAL_CONFIG.roles shape, htmlEscape,
Analysis-read view (D-16), and base64 polyfill (only if chunked action params end up needed -
likely NOT needed here since `Assign-RoleMapping.bes` params are short strings, unlike the old
break-glass CSV's base64 matrix).

**PORTAL_CONFIG.roles - D-03's fixed/small role list, edited in a config block** (lines 40-53):
```javascript
var PORTAL_CONFIG = {
  targetGroups: [
    'All Workstations',
    'IT Department',
    'Finance Department',
    'All Servers'
  ],
  roles: [
	"IT Operations",
	"Business Operations"
  ],
  actionNamePrefix: 'DSD_',
  validityMonths: 6
};
```
Reuse this shape directly for the new dashboard's config block (D-03/D-10: `roles` array plus an
optional `targetGroups` list backing the D-10 "Target Group" scope-filter selector).

**htmlEscape** (lines 83-89):
```javascript
function htmlEscape(s){
  return String(s)
    .replace(/&/g,"&amp;")
    .replace(/</g,"&lt;")
    .replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;");
}
```

**D-16 Analysis view - read-only role-assignment table via `GetRelevance`** (lines 892-936,
`loadAnalysisView`) - reads `mapped_users`/`map_source`/`map_region` properties from
`Dashboard_4_samples/Dereso SWD.bes`. Reuse near-verbatim; the merge helper
`mergeAnalysisRows()` (lines 807-861) and the safe-read wrapper `getRelevanceSafe()`
(lines 863-872) are pure functions, straightforward to lift as-is:
```javascript
function getRelevanceSafe(rel){
  try {
    var d = GetRelevance(rel);
    return d ? d : [];
  } catch(ex){
    return [];
  }
}
// D-17 (carried over as D-16 numbering in this rewrite): GetRelevance (not
// EvaluateRelevance) to read remote client Analysis data
var relMapped = '(name of computer of it as string & "|||" & value of it as string) of results whose (value of it != "") of bes property whose (name of it = "mapped_users in r.db")';
var relSource = '(name of computer of it as string & "|||" & value of it as string) of results whose (value of it != "") of bes property whose (name of it = "map_source in r.db")';
var relRegion = '(name of computer of it as string & "|||" & value of it as string) of results whose (value of it != "") of bes property whose (name of it = "map_region in r.db")';
```
Note: `map_region` here is D-08's "Region survives for reporting only" column - keep the
Analysis column, drop nothing.

**D-02 autocomplete source** - the `Dashboard_4_samples/Dereso SWD.bes` Analysis already exposes
a `users in r.db` property reading `SELECT userid from users` (see `Dashboard_4_samples/Dereso
SWD.bes` line 15). No dashboard code currently consumes it (it is new surface for D-02), but the
read mechanism is identical to `loadAnalysisView`'s `GetRelevance` pattern above - build a
`relKnownUsers = '(value of it as string) of results whose (value of it != "") of bes property whose (name of it = "users in r.db")'`
call the same way, feed the result into an IE9-safe `<datalist>`-or-manual-suggestion UI (IE9 has
no native `<datalist>` filtering - a simple filtered `<div>` dropdown, same rendering style as
`fixlet_dispatcher.ojo`'s `renderGroupSelect()` at line 1045, is the safer IE9-proven precedent).

**Analog 3: `Existing Dashboards/fixlet_role_admin.ojo`** - IE9 tab-switch shell (D-14's dashboard
needs at minimum an "Edit/Publish" tab and an "Analysis" tab).

**Tab switching** (lines 166-178):
```javascript
// ==========================================================================
// TAB SWITCHING (fixlet_console.ojo L322 pattern / RESEARCH.md Pattern 8)
// ==========================================================================
function switchTab(tab){
  var ids = ["GroupRoleMap","RolePublication","Region","ReferenceDB"];
  var i, panel, btn;
  for(i=0;i<ids.length;i++){
    panel = document.getElementById("tab"+ids[i]);
    btn   = document.getElementById("tabBtn"+ids[i]);
    if(panel){ panel.style.display = (ids[i]===tab) ? "" : "none"; }
    if(btn){ btn.className = (ids[i]===tab) ? "tabBtn tabActive" : "tabBtn"; }
  }
}
```
Rename the `ids` array to the new dashboard's own tabs (e.g. `["Roles","Analysis"]`); the
add/remove-class mechanism is otherwise a direct copy. **Do not** carry over
`fixlet_role_admin.ojo`'s GroupRoleMap/Region/ReferenceDB tab *content* (D-15 retires all three);
only the switching mechanism itself is reused.

**Computer Group + relevance builders** - no direct codebase precedent exists (RESEARCH.md
confirms this is the one genuinely new surface this phase touches), but every sub-idiom is
independently proven. Use RESEARCH.md's Code Examples verbatim as the starting implementation:

```javascript
// "Exactly one of N logged on" relevance builder (D-09/D-10)
function buildRoleGroupRelevance(usernames, optionalScopeGroupId, optionalScopeSiteName) {
  if (!usernames || usernames.length === 0) { return "false"; }
  var quoted = [];
  for (var i = 0; i < usernames.length; i++) {
    var u = String(usernames[i]).toLowerCase().replace(/"/g, '""');
    quoted.push('"' + u + '"');
  }
  var base = '(number of (logged on users whose (name of it as lowercase is contained by ' +
    'set of (' + quoted.join(';') + ')))) = 1';
  if (optionalScopeGroupId) {
    var safeSite = String(optionalScopeSiteName || "").toLowerCase().replace(/"/g, '""');
    base += ' AND (member of group ' + optionalScopeGroupId + ' of site whose ' +
      '(name of it as lowercase = "' + safeSite + '" as lowercase))';
  }
  return base;
}

// ComputerGroup BES-XML builder (Pattern 1)
function buildComputerGroupXml(title, domain, relevance) {
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
```
Critical edge-case guard (RESEARCH.md Pitfall / highest-impact bug this generator could ship):
empty username list MUST return `"false"`, never an unconstrained match - unit-test this
explicitly (see `tests/unit/role_manager.test.js` below).

**Error handling pattern (shared across all REST calls):** `fixlet_dispatcher.ojo`'s
`deployFixlet()` inline errEl/resultEl convention above - no `alert()`, ever, anywhere in this
dashboard.

---

### `bes/Assign-RoleMapping.bes` (REUSED AS-IS - the Task-XML-per-role template)

Not modified by this phase. The generator's step-2 "find-or-create the role's Task" (RESEARCH.md
Pattern 3, step 1) must build fresh Task XML from this file's fields via `getElementsByTagName`
extraction - **never edit the fetched Task XML in place**. The from-scratch rebuild discipline is
`Existing Dashboards/fixlet_copier.ojo`'s `buildXml()` (lines 783-870ish) - extract every needed
element (`Title`, `Description`, `Relevance`, `DefaultAction`/`ActionScript`, `MIMEField`s) into
local variables, then re-emit a brand-new `<BES><Task>...</Task></BES>` document. This project has
a documented, confirmed 400-Bad-Request pitfall for in-place Task XML mutation - do not shortcut
this with e.g. a DOM `.replaceChild()` on the fetched document.

`__ROLE__`/`__ASSIGNED_BY__` token substitution (lines 4, 61, 75-76 of `bes/Assign-RoleMapping.bes`)
is a simple `.replace(/__ROLE__/g, ...)` / `.replace(/__ASSIGNED_BY__/g, ...)` pass over the raw
template text before the from-scratch XML rebuild - `__USERNAME__` stays as the client-relevance
literal `{name of current user as lowercase}` (line 77), never substituted with an actual
username (the whole point of the "exactly one of N" group is that the client resolves its own
identity).

---

### Root-server `RoleUsers`/`RolePublishRun` audit DDL (embedded, D-05/Pattern 5)

**Analog:** `Dashboard_4_samples/Initialize-RoleDb.ps1`

**DDL + idempotent-migration shape** (lines 100-217 - `CREATE TABLE IF NOT EXISTS`, table-existence
`[SKIP]`/`[CREATE]` logging, `PRAGMA table_info`-gated `ALTER TABLE` for any future additive
column):
```powershell
$rolesDdl = @"
CREATE TABLE IF NOT EXISTS Roles (
    RoleID  INTEGER PRIMARY KEY AUTOINCREMENT,
    Role    TEXT NOT NULL UNIQUE
)
"@
...
foreach ($tbl in @(
    @{ Name = 'Roles';     Ddl = $rolesDdl     }
    ...
)) {
    $before = Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir `
        -Sql "SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name=@n" `
        -Parameters @{ n = $tbl.Name }
    if ($before[0].n -eq 1) {
        Write-Host "[SKIP] $($tbl.Name) table already exists - no changes made"
    } else {
        Invoke-SqliteCommand -DatabasePath $DatabasePath -SQLDir $SQLDir -Sql $tbl.Ddl | Out-Null
        Write-Host "[CREATE] $($tbl.Name) table created"
    }
}
```
Apply this exact shape to the `RolePublishRun`/`RoleUsers` DDL proposed in RESEARCH.md Pattern 5
(full-snapshot-per-Publish design, `RunID` FK, two indexes). Since D-07 embeds the write directly
in ActionScript (via `createfile`, per `buildStagingActionXml` above) rather than as a standalone
`.ps1` file staged separately, the DDL block becomes part of that embedded PowerShell payload -
still dot-source `Sqlite-Helper.ps1` the same way `Assign-RoleMapping.ps1` does (see below), and
still use `Invoke-SqliteCommand -Parameters @{...}` for every value - never string-concatenate a
role/username into SQL (RESEARCH.md Security Domain, Tampering row).

**Dot-source + parameterized-write pattern** (from `scripts/Assign-RoleMapping.ps1`, lines 88-90,
145-146, 160-161 - the sibling endpoint script already doing exactly this against the same
`Sqlite-Helper.ps1`):
```powershell
if ([string]::IsNullOrWhiteSpace($SqliteHelperPath)) {
    $SqliteHelperPath = Join-Path (Split-Path $DatabasePath) 'Sqlite-Helper.ps1'
}
...
if (-not (Test-Path $SqliteHelperPath)) { throw "[ABORT] Sqlite-Helper.ps1 not found at: $SqliteHelperPath" }
. $SqliteHelperPath
...
Invoke-DbWrite "INSERT OR IGNORE INTO Users (UserID, LastSeen) VALUES (@u, datetime('now','localtime'))" @{ u = $user }
```

---

### `tests/unit/role_manager.test.js` (NEW)

**Analog:** `tests/unit/role_assigner.test.js`

**File header + extraction-test convention** (lines 1-29):
```javascript
/**
 * role_manager.test.js
 *
 * Unit tests for the pure JavaScript functions extracted from:
 *   Existing Dashboards/fixlet_role_manager.ojo
 *
 * Functions covered:
 *   1. buildRoleGroupRelevance(usernames, optionalScopeGroupId, optionalScopeSiteName)
 *   2. buildComputerGroupXml(title, domain, relevance)
 *   3. buildDeployXml-equivalent (SingleAction element order, Reapply/ReapplyInterval, IsOffer=false)
 *   4. xmlEscape(s) / xmlCDataSafe(s)
 *   5. switchTab(tab)
 *   6. PORTAL_CONFIG.roles validation
 *
 * Running: node tests/unit/role_manager.test.js
 * Requirements: Node.js built-in `assert` and `fs` modules only (no external packages).
 */
"use strict";
var assert = require("assert");
var fs     = require("fs");
var path   = require("path");
```
Copy each pure function's implementation directly into the test file as a same-behavior stub
(this project's established convention - see `role_assigner.test.js`'s comment "EXTRACTED
FUNCTION IMPLEMENTATIONS" at line 32), then assert against it. Priority assertions per
RESEARCH.md's Validation Architecture table: `buildRoleGroupRelevance([])` returns exactly
`"false"` (never `"true"` or an empty `set of ()`); a username containing `"` is escaped to `""`;
the D-10 scope clause is present only when a scope group ID is supplied.

---

### `tests/pester/Initialize-RoleUsersDb.Tests.ps1` (NEW)

**Analog:** `tests/pester/Initialize-RoleDb.Tests.ps1`

**sqlite3.exe discovery + skip-not-fail-on-missing pattern** (lines 1-24):
```powershell
function Find-SqliteDir {
    $probes = @()
    if ($env:SQLDIR) { $probes += $env:SQLDIR }
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite'
    $probes += 'C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\sqlite'
    $cmd = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    if ($cmd) { $probes += (Split-Path $cmd.Source -Parent) }
    foreach ($p in $probes) { if ($p -and (Test-Path (Join-Path $p 'sqlite3.exe'))) { return $p } }
    return $null
}
BeforeDiscovery {
    $script:HasSqlite = [bool](Find-SqliteDir)
}
```
Reuse verbatim (this is the project's standard "degrade gracefully when sqlite3.exe isn't on the
test-runner box" idiom - do not fail the whole suite over an environment gap). Test target: the
`RolePublishRun`/`RoleUsers` DDL block extracted from the D-07 ActionScript (or, if the planner
chooses to also ship it as a standalone `Initialize-RoleUsersDb.ps1` for reuse by
`Sync-RoleGroups.ps1`, test that file directly the same way `Initialize-RoleDb.Tests.ps1` tests
`Dashboard_4_samples/Initialize-RoleDb.ps1`).

---

### `tests/pester/InitCurrentUserTask.Tests.ps1` (NEW)

**Analog:** `tests/pester/RoleRefPolicyBes.Tests.ps1` (structure only - read for its
"assert against embedded ActionScript text via regex" shape; its own *subject*, the retired
`RoleRef-Policy-template.bes`, is not relevant).

Assert on `Dashboard_4_samples/"Init  Current User and UserRole DB.bes"` after the Pattern 6 diff
is applied:
- MUST NOT contain: `Reconcile-LocalRoles.ps1` (prefetch line, `copy` line, `mkdir ...\roleref`
  block, the `$actionReconcile` variable, or `@($actionInit, $actionReconcile)`).
- MUST contain unchanged: the v4 Map migration block (`Source_Type`/`Source_Value`/`Region`/
  `Assigned_By` `ALTER TABLE` lines), the `Unregister-ScheduledTask -TaskName 'RoleDB_Maintenance'`
  unconditional pre-guard, and `Register-ScheduledTask -Action @($actionInit)` (single-action form
  post-diff, since `$actionReconcile` no longer exists).

---

### `Dashboard_4_samples/"Init  Current User and UserRole DB.bes"` (EDIT, Pattern 6 - exact diff)

**Self-analog** - this is an in-place strip, not a new-file-from-analog build. Exact lines to
remove, located and quoted verbatim in this session:

**1. Prefetch line** (line 40):
```
	add prefetch item name=Reconcile-LocalRoles.ps1 sha1=49ebb985c069910d4cdca166ed0ac140da5dec43 size=14675 url=http://127.0.0.1:{...}/Uploads/CustomRepository/SoftwarePortal/roleref/Reconcile-LocalRoles.ps1
```

**2. Copy + mkdir block** (lines 653-661):
```
//=============================================================================================//
// Land Reconcile-LocalRoles.ps1 (07-02) next to the DB. ...
//=============================================================================================//
    if {not exists folder ((parameter "SWPDir") & "\roleref")}
        runhidden cmd /c mkdir "{parameter "SWPDir"}\roleref"
    endif
    copy "__Download\Reconcile-LocalRoles.ps1" "{parameter "SWPDir"}\Reconcile-LocalRoles.ps1"
```

**3. `$actionReconcile` variable + its use** (lines 715-716, 729-730):
```powershell
$actionReconcile = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NonInteractive -NoProfile -ExecutionPolicy Bypass -File `"{parameter "SWPDir"}\Reconcile-LocalRoles.ps1`" -Region `"{parameter "Region"}`" -SnapshotDir `"{parameter "SWPDir"}\roleref`" -SQLDir `"{parameter "SQLiteDir"}`" -DatabasePath `"{parameter "TargetStore"}`""
...
Register-ScheduledTask -TaskName "RoleDB_Maintenance" `
    -Action @($actionInit, $actionReconcile) `
```
becomes:
```powershell
Register-ScheduledTask -TaskName "RoleDB_Maintenance" `
    -Action @($actionInit) `
```

**MUST NOT touch (Pitfall 5 - this is the mechanism that lands the fix on already-provisioned
endpoints):**
```
    waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -Command "Unregister-ScheduledTask -TaskName 'RoleDB_Maintenance' -Confirm:$false -ErrorAction SilentlyContinue"

if {  not (exists (scheduled tasks whose (name of it = "RoleDB_Maintenance"))) }
```
This unconditional unregister-then-reregister-if-absent guard is what makes the corrected
single-action command line actually replace the old two-action one on endpoints that already ran
this task before - leave it exactly as-is.

**Everything else in the file (directory prep, `sqlite3.exe`/`unzip.exe` staging, the embedded
`Sqlite-Helper.ps1`/`Initialize-RoleDb.ps1` createfile blocks, the v4 Map migration itself) is
redeployed unchanged.**

---

### `scripts/Register-AutomationTasks.ps1` (EDIT, Pitfall 8 - exact diff)

**Self-analog.** Remove the two now-dead rows (lines 91-100 and 101-109 of the current file):
```powershell
    @{
        Name        = 'DeresoRoleIngest'
        Script      = 'Import-AxoniousExport.ps1'
        ...
    }
    @{
        Name        = 'DeresoRolePublish'
        Script      = 'Publish-RoleSnapshot.ps1'
        ...
    }
```
Leave `DeresoContentSync`/`DeresoRepoStage` (07-03, content pipeline) untouched - the
`$AutomationTaskTable` array, `Resolve-PsHost`, `New-TriggerFromSpec`, `Register-AutomationTask`,
and `Unregister-AutomationTask` functions are all otherwise unaffected. If the D-06 drift-check
job (`scripts/Sync-RoleGroups.ps1`) is built as a scheduled task rather than deferred, append a
new row here using the exact same hashtable shape (`Name`/`Script`/`Arguments`/`Trigger`/
`RunLevel`/`User`/`Description`) - this is an explicit, documented exception to the append-only
convention (removal), not a silent violation; note it in the plan/summary per RESEARCH.md
Pitfall 8.

---

## Shared Patterns

### XML escaping / CDATA safety
**Source:** `Existing Dashboards/fixlet_dispatcher.ojo` lines 470-481 (byte-identical copy also in
`fixlet_role_assigner.ojo` lines 98-109)
**Apply to:** every generated XML body in `fixlet_role_manager.ojo` - `ComputerGroup`, Task, and
`SingleAction` documents alike.
```javascript
function xmlEscape(s){ return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;").replace(/'/g,"&apos;"); }
function cdataStart(){ return '<!' + '[CDATA['; }
function cdataEnd(){   return ']]' + '>'; }
function xmlCDataSafe(s){ return String(s).replace(/\]\]>/g, ']]]]><![CDATA[>'); }
```

### Relevance-string escaping (injection defense, V5)
**Source:** RESEARCH.md Pattern 2 / Security Domain, consistent with
`fixlet_dispatcher.ojo`'s `buildTargetRelevance()` (line 495: `String(name).replace(/"/g, '""')`)
**Apply to:** every username or role name interpolated into a `whose`/`set of (...)` relevance
clause - double any `"` before interpolating, never pass raw user input through.

### SQL parameterization (injection defense, V5)
**Source:** `Dashboard_4_samples/Sqlite-Helper.ps1`'s `Invoke-SqliteCommand -Parameters @{...}` /
`ConvertTo-SqliteLiteral` (single-quote doubling)
**Apply to:** the D-07 root-server audit-write ActionScript's embedded PowerShell and any
`Sync-RoleGroups.ps1` writes - never string-concatenate a role or username into SQL text.

### No in-place Task/Fixlet XML mutation
**Source:** `Existing Dashboards/fixlet_copier.ojo`'s `buildXml()` (from-scratch rebuild via
`getElementsByTagName` extraction), documented as a confirmed 400-Bad-Request pitfall in
`.claude/skills/bigfix-relevance/SKILL.md` §7
**Apply to:** the generator's Task find-or-create step (RESEARCH.md Pattern 3, step 1) - always
extract fields from the fetched/template XML into variables and re-emit a fresh document; never
edit the fetched DOM node tree in place and re-serialize it.

### `SingleAction`, not `SourcedFixletAction`, for dynamic-group targeting
**Source:** `Existing Dashboards/fixlet_dispatcher.ojo`'s `buildDeployXml()`/`buildTargetRelevance()`
(lines 489-504, 1073-1170), confirmed by `.claude/skills/bigfix-relevance/SKILL.md` §3
**Apply to:** the Publish-flow's policy-action deploy (RESEARCH.md Pitfall 2) - `<CustomRelevance>
member of group <id> of site "..."</CustomRelevance>` inside `SingleAction/Target` only.
Element order is fixed: `Title -> Relevance -> ActionScript -> [SuccessCriteria] -> Settings ->
[SettingsLocks] -> [IsUrgent] -> Target -> [MIMEFieldSingleAction]` (Pitfall 3) - `Target` always
comes AFTER `Settings`.

### Inline per-step error feedback, never `alert()`
**Source:** `Existing Dashboards/fixlet_dispatcher.ojo`'s `deployFixlet()` errEl/resultEl pattern
(lines 1194-1220)
**Apply to:** all three Publish-flow REST calls (Group, Task, Action) - each gets its own
success/failure indicator so a partial-publish failure (Pitfall 4) is diagnosable at a glance.

### IE9 tab-switch shell
**Source:** `Existing Dashboards/fixlet_role_admin.ojo` lines 166-178
**Apply to:** `fixlet_role_manager.ojo`'s top-level tab structure (e.g. Roles / Analysis).

### CLM-safe SQLite only
**Source:** `Dashboard_4_samples/Sqlite-Helper.ps1` (`Invoke-SqliteCommand`, dot-sourced, zero
`Add-Type`)
**Apply to:** every new PowerShell touching SQLite in this phase - the D-07 audit-write payload
and `scripts/Sync-RoleGroups.ps1` alike. Never introduce `System.Data.SQLite.dll`/`Add-Type` or
PSGallery's `PSSQLite`.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| Computer Group create/update relevance + BES-XML generator functions (`buildRoleGroupRelevance`, `buildComputerGroupXml`) inside `fixlet_role_manager.ojo` | component (pure function) | transform | This repo has never created a BigFix Computer Group via REST before (RESEARCH.md's single biggest finding) - every prior dashboard only targets *existing* groups. No in-repo precedent; use RESEARCH.md's Code Examples (Pattern 1/2) as the starting implementation, verify against the official BES-XML schema cited there, and treat the first live POST as an explicit Wave-0 spike (RESEARCH.md Open Question 2) before building dashboard UI on top of unverified assumptions. |

---

## Metadata

**Analog search scope:** `Existing Dashboards/*.ojo`, `scripts/*.ps1`, `bes/*.bes`,
`Dashboard_4_samples/*`, `tests/unit/*.test.js`, `tests/pester/*.Tests.ps1`
**Files scanned/read:** `fixlet_dispatcher.ojo`, `fixlet_role_assigner.ojo`, `fixlet_role_admin.ojo`,
`fixlet_copier.ojo` (targeted sections), `Assign-RoleMapping.ps1`, `Assign-RoleMapping.bes`,
`Register-AutomationTasks.ps1`, `Initialize-RoleDb.ps1`, `Sqlite-Helper.ps1`,
`"Init  Current User and UserRole DB.bes"`, `Dereso SWD.bes`, `role_assigner.test.js`,
`Initialize-RoleDb.Tests.ps1`, `config/PipelineConfig.defaults.json`
**Pattern extraction date:** 2026-09-21
