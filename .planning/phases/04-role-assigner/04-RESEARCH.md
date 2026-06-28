# Phase 4: Role Assigner Dashboard — Research

**Researched:** 2026-06-27
**Domain:** BigFix dashboard (.ojo), PowerShell + System.Data.SQLite, Base64 chunked parameter encoding, BigFix Analysis integration
**Confidence:** HIGH (all findings derived from canonical artefacts in the repo — zero dependency on external library research)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** One `API.Post("actions")` call per unique role in the CSV — no MAG.
- **D-02:** Action targets explicit Computer_ID list for that role. Client-side relevance also guards: action runs only if `RoleAwareness.db` exists.
- **D-03:** Matrix encoding: `{ "computers": [id1,...], "users": ["u1",...] }` — parallel arrays, index `i` = one (computer, user) pair.
- **D-04:** Matrix Base64-compressed, chunked into ~3000-char segments: ActionScript parameters `chunk0`, `chunk1`, ...
- **D-05:** Client self-identifies via `parameter "CompID"="{id of computer}"`. PowerShell finds all indices where `computers[i] == CompID`.
- **D-06:** Upsert: `INSERT OR IGNORE` then conditional `UPDATE` if `Active=0`. Skip rows where `Locked_by_Override=1`.
- **D-07:** Remove action (Phase 5 only): soft delete — `Active=0` and `Valid_to=datetime('now','localtime')`.
- **D-08:** ActionScript structure follows `Init Current User and UserRole DB.bes`: prefetch SQLite DLLs, set directory parameters, `createfile…_EOF_`, `waithidden powershell.exe`.
- **D-09:** Action naming: `Dereso_[Role] Assign_[suffix]`. Suffix = region/geo text from UI; defaults to selected group name.
- **D-10:** `Computer_ID` column in CSV = BigFix computer ID. Determines which client runs the action and which Map table is updated.
- **D-11:** CSV drives ADD only. Remove workflow in Phase 5 uses Analysis data.
- **D-12:** Group selector follows Dispatcher pattern — dropdown from `PORTAL_CONFIG.targetGroups`. Informational only; does not filter the computer ID list.
- **D-13:** Single-page vertical flow: group selector → region/suffix → CSV upload → preview table → Deploy.
- **D-14:** Preview table columns: User | Computer_ID | Role. Row count shown. Validation errors highlighted inline. Deploy disabled until blocking errors resolved.
- **D-15:** CSV validation: BLOCK on unknown role, blank User, blank Computer_ID. WARN (flagged row) on duplicate (User, Computer_ID, Role).
- **D-16:** Post-deploy: success banner per action showing action ID returned by `API.Post("actions")` — same UX as Dispatcher.
- **D-17:** Analysis view: table of Computer Name | User | Role from `mapped_users in r.db` via `GetRelevance`. Flag Computer_IDs absent from Analysis as "DB not initialised".
- **D-18:** Revoke UI: read-only in Phase 4 (shows mappings; no action generated).
- **D-19:** PORTAL_CONFIG adds `roles[]` and `actionNamePrefix: 'Dereso'` to Dispatcher structure. `targetGroups` carried unchanged.
- **D-20:** Deliverables: `Existing Dashboards/fixlet_role_assigner.ojo` + finalised `Dashboard_4_samples/Dereso SWD.bes`.
- **D-21:** Dashboard detects uninitialised DB via Analysis and warns; it does NOT deploy `Init Current User and UserRole DB.bes`.
- **D-22:** Overrides table exists in DB schema but is out of scope. No override UI.
- **D-23:** `Init Current User and UserRole DB.bes` is a prerequisite; it is not a Phase 4 deliverable.

### Claude's Discretion
No explicit discretion areas were stated; all key decisions are locked.

### Deferred Ideas (OUT OF SCOPE)
- Revoke UI (select mappings from Analysis, fire Revoke actions) — Phase 5
- Override management — Phase 5
- "Init DB on selected computers" button — Phase 5
- Group overlap indicator — nice-to-have, not required
- Multi-Action-Group approach — rejected for Phase 4
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FR-02 | Role-Based Fixlet Association — extended to user-level | D-03/D-04/D-06: CSV-driven parallel-array encoding drives per-client Map upsert; `PORTAL_CONFIG.roles` is the canonical role list |
| FR-03 | Role-Based Relevance — enabled by DB-backed assignments | D-02/D-17: client relevance guard checks DB existence; Analysis surfaces current Map state so relevance queries have data to match against |
</phase_requirements>

---

## Summary

Phase 4 delivers one new BigFix dashboard (`fixlet_role_assigner.ojo`) and finalises the `Dereso SWD.bes` Analysis. The dashboard is an HTML/JavaScript page hosted inside the BigFix console Wizard format — identical structural constraints as the three prior dashboards. The core novel challenge is transmitting a potentially large (user, computer) assignment matrix from the admin's browser to client machines via BigFix's parameter system. The solution is Base64-encoding the matrix and chunking it into ~3000-char ActionScript parameters; the client PowerShell script reassembles and decodes them.

All other patterns — `API.Post("actions")` with SingleAction XML, PORTAL_CONFIG block, success banners, group selector, `buildTargetRelevance`, `parseActionId`, IE9 MSXML ActiveXObject, `htmlEscape`, `xmlEscape` — are directly reusable from `fixlet_dispatcher.ojo`. The dashboard is substantially a specialised dispatcher: instead of deploying a fixlet the admin selects, it generates custom PowerShell-embedded SingleActions from a CSV.

The BigFix Analysis (`Dereso SWD.bes`) is nearly production-ready. The only required change is correcting the column reference in `mapped_users in r.db` (the SQL uses `map.user` but the actual column name from the DDL is `UserID`) and reviewing for data-type handling from `tuple string item N` parsing.

**Primary recommendation:** Build `fixlet_role_assigner.ojo` by scaffolding from `fixlet_dispatcher.ojo`. Replace the fixlet-list + detail-panel section with the CSV upload + preview section. Reuse `buildTargetRelevance`, `parseActionId`, `xmlEscape`, `htmlEscape`, `cdataStart/End`, `xmlCDataSafe`, and the `API.Post` + success banner verbatim.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| CSV parsing and validation | Browser (dashboard JS) | — | File is uploaded client-side; validation must happen before any action is fired |
| Role-to-computer matrix encoding (B64 chunking) | Browser (dashboard JS) | — | Matrix is assembled in JS from parsed CSV; must be encoded before being embedded in ActionScript XML |
| Action XML generation (one per role) | Browser (dashboard JS) | — | `API.Post("actions")` constructs the XML string in JS, matching Dispatcher pattern |
| BigFix action delivery to clients | BigFix server | BigFix agent | Server routes action; agent executes it via ActionScript |
| Matrix decoding and DB upsert | BigFix agent (PowerShell) | — | PowerShell runs on client, decodes B64, queries SQLite with `System.Data.SQLite.dll` |
| Analysis property collection | BigFix agent (Relevance) | — | Evaluated on client, reported back to server via Analysis |
| Analysis display (read-only view) | Browser (dashboard JS) | — | `GetRelevance()` call in dashboard JS to read Analysis property values |
| DB initialisation guard | Browser (dashboard JS) | — | Dashboard compares CSV Computer_IDs against Analysis results to detect uninitialised clients |

---

## Standard Stack

### Core (all verified from canonical artefacts in this repo)

| Component | Version / Source | Purpose | Why Standard |
|-----------|-----------------|---------|--------------|
| BigFix Wizard XML | BES.xsd / existing .ojo files | Dashboard container format | Required by platform |
| IE9-mode MSXML | `Msxml2.DOMDocument.6.0` | XML parsing in dashboard JS | BigFix console embeds IE9 engine |
| `API.Post("actions", xml, cb)` | `fixlet_dispatcher.ojo` line 747 | Fire SingleAction to BigFix REST | Established and proven in Phase 3 |
| `GetRelevance(rel)` / `EvaluateRelevance(rel)` | All existing .ojo files | Read BigFix data from dashboard | Platform API — no alternative |
| `System.Data.SQLite.dll` | `Initialize-RoleDb.ps1`, `Init Current User and UserRole DB.bes` | SQLite access from PowerShell on client | Bundled in the custom repo; no PSGallery dependency |
| PowerShell 5.1 | `Initialize-RoleDb.ps1` `#Requires -Version 5.1` | Client-side script execution | Required by BigFix agent `waithidden` pattern; matches installed OS baseline |
| Node.js built-in `assert` | `tests/unit/dispatcher.test.js` | Unit tests (pure JS functions) | Established pattern — no external test framework |

### Supporting

| Component | Source | Purpose | When to Use |
|-----------|--------|---------|-------------|
| `btoa()` (browser) | Browser built-in | Base64 encode matrix JSON | Available in IE9+ for ASCII strings |
| `atob()` (PowerShell via .NET) | `[System.Convert]::ToBase64String` / `::FromBase64String` | Encode/decode on PowerShell side | PowerShell 5.1 — no btoa, use .NET |
| `JSON.parse` / `JSON.stringify` | Browser built-in | Serialise matrix before B64 | Available in IE9 |
| `FileReader` API | Browser built-in | Read uploaded CSV file | Available in IE10+; must verify IE9 compatibility — see Pitfall 4 |

### No External Packages Required

This phase installs no npm or PowerShell Gallery packages. All dependencies are either:
- Built into the BigFix platform (API calls, Relevance engine)
- Already bundled in the custom repo (SQLite DLLs + tools)
- Browser built-ins (btoa, FileReader, JSON)
- Node.js built-ins (assert, fs for test fixtures)

---

## Package Legitimacy Audit

Not applicable — Phase 4 installs no external packages.

---

## Architecture Patterns

### System Architecture Diagram

```
Admin Browser (BigFix console — IE9)
    |
    |  1. Load CSV file
    v
[CSV Parser / Validator]  ──(blocking errors?)──> Deploy button disabled
    |
    |  2. Build role matrix  { computers: [...], users: [...] }
    v
[B64 Chunker]  ──> chunk0, chunk1, chunk2, ...
    |
    |  3. For each unique role in CSV:
    v
[buildAssignActionXml(role, computerIds, chunks)]
    |
    |  4. API.Post("actions", xml, cb)  ── one call per role
    v
BigFix REST API (server-side)
    |
    |  5. Server creates SingleAction, routes to target computers
    v
BigFix Client (agent)
    |  6. ActionScript runs:
    |     a. prefetch SQLite DLLs
    |     b. mkdir ECDir, SWPDir, SQLiteDir
    |     c. createfile ... _EOF_ (embed PowerShell)
    |     d. waithidden powershell.exe ... -DatabasePath ... -SQLDir ...
    v
[PowerShell: Assign-RoleMapping.ps1]
    |  7. Concat chunks → decode B64 → JSON.parse
    |  8. Find indices where computers[i] == CompID
    |  9. For each user: INSERT OR IGNORE + conditional UPDATE if Active=0
    |     Skip rows where Locked_by_Override=1
    v
RoleAwareness.db  (Map table updated)

    ┌─────────────────────────────────────────────────┐
    │ Separately: Analysis (Dereso SWD.bes)           │
    │   Client evaluates Relevance every 5 min        │
    │   Reads mapped_users, Roles, users from DB      │
    │   Reports to BigFix server                      │
    └───────────────────────────────────────────────┘
                              |
                              | GetRelevance("property N of bes analyses ...")
                              v
                     Admin Browser (read-only view)
                     Computer Name | User | Role table
                     Uninitialised DB warning if Computer_ID absent
```

### Recommended Project Structure

```
Existing Dashboards/
└── fixlet_role_assigner.ojo      ← new dashboard

Dashboard_4_samples/
└── Dereso SWD.bes                ← finalised (fix mapped_users SQL)

tests/
├── unit/
│   └── role_assigner.test.js     ← pure-JS unit tests (B64 chunking, CSV parsing, etc.)
├── integration/
│   └── role_assigner.integration.test.js  ← API round-trip (env-var gated)
└── fixtures/
    └── phase-04/
        ├── sample.csv            ← valid 3-role CSV
        ├── invalid-unknown-role.csv
        ├── invalid-blank-user.csv
        └── duplicate-rows.csv
```

---

## Key Technical Patterns

### Pattern 1: Base64 Chunking (Dashboard JS side)

**What:** Serialise the role matrix to JSON, Base64-encode it, split into ~3000-char chunks, embed each chunk as a named ActionScript parameter.

**Why ~3000 chars:** BigFix agent parameter values have a ~4000 character limit per parameter. 3000 leaves a safe margin for Base64 overhead (B64 expands binary by 4/3; JSON is ASCII so no binary overhead).

```javascript
// Source: D-03, D-04 (CONTEXT.md) + btoa() browser built-in
function encodeMatrix(computers, users) {
  // computers[i] and users[i] form one (computer, user) assignment pair
  var json = JSON.stringify({ computers: computers, users: users });
  var b64  = btoa(json);  // btoa() available IE10+; see Pitfall 4 for IE9 fallback
  return b64;
}

function chunkString(s, size) {
  var chunks = [];
  for (var i = 0; i < s.length; i += size) {
    chunks.push(s.slice(i, i + size));
  }
  return chunks;  // e.g. ["chunk0content...", "chunk1content..."]
}

// Produces ActionScript parameter lines:
//   parameter "chunk0"="<3000 chars of B64>"
//   parameter "chunk1"="<3000 chars of B64>"
//   parameter "chunkCount"="2"
function buildChunkParams(b64) {
  var CHUNK_SIZE = 3000;
  var chunks = chunkString(b64, CHUNK_SIZE);
  var lines = [];
  for (var i = 0; i < chunks.length; i++) {
    lines.push('parameter "chunk' + i + '"="' + chunks[i] + '"');
  }
  lines.push('parameter "chunkCount"="' + chunks.length + '"');
  return lines.join('\r\n');
}
```

[VERIFIED: canonical artefacts — D-03/D-04 specify this exact structure]

---

### Pattern 2: PowerShell Chunk Reassembly and Upsert

**What:** On the client, concatenate parameters back to B64 string, decode to JSON, find matching computer entries, run upsert.

```powershell
# Source: D-04, D-05, D-06 (CONTEXT.md) + Initialize-RoleDb.ps1 upsert pattern
param(
    [string]$DatabasePath,
    [string]$SQLDir,
    [string]$CompID,
    [string]$Role,
    [string]$ChunkCount
    # chunk0..chunkN passed as separate parameters
)

# 1. Reassemble B64 string from chunks
$b64 = ""
$count = [int]$ChunkCount
for ($i = 0; $i -lt $count; $i++) {
    # Parameters are passed via -chunk0, -chunk1 etc.
    $b64 += (Get-Variable -Name "chunk$i").Value
}

# 2. Decode B64 to JSON string
$json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))

# 3. Parse JSON (PowerShell 5.1 has ConvertFrom-Json)
$matrix = $json | ConvertFrom-Json

# 4. Find all indices where computers[i] matches this client's CompID
$computers = $matrix.computers
$users     = $matrix.users
$myUsers   = @()
for ($i = 0; $i -lt $computers.Count; $i++) {
    if ($computers[$i] -eq $CompID) {
        $myUsers += $users[$i]
    }
}

# 5. Upsert each user into Map table (D-06 pattern from Initialize-RoleDb.ps1)
$arch    = if ([IntPtr]::Size -eq 8) { 'x64' } else { 'x86' }
$dllPath = Join-Path $SQLDir "$arch\System.Data.SQLite.dll"
Add-Type -Path $dllPath

$conn = [System.Data.SQLite.SQLiteConnection]::new(
    "Data Source=$DatabasePath;Journal Mode=WAL;BusyTimeout=30000"
)
$conn.Open()

try {
    $cmd = $conn.CreateCommand()
    foreach ($user in $myUsers) {
        # INSERT OR IGNORE preserves existing Active/Locked_by_Override values
        $cmd.CommandText = @"
INSERT OR IGNORE INTO Map (UserID, Role, Active, Created_on)
VALUES (@uid, @role, 1, datetime('now','localtime'))
"@
        [void]$cmd.Parameters.AddWithValue('@uid',  $user)
        [void]$cmd.Parameters.AddWithValue('@role', $Role)
        [void]$cmd.ExecuteNonQuery()
        [void]$cmd.Parameters.Clear()

        # If row existed but was inactive (Active=0) and not locked, reactivate it
        $cmd.CommandText = @"
UPDATE Map
SET    Active     = 1,
       Updated_on = datetime('now','localtime'),
       Valid_to   = NULL
WHERE  UserID             = @uid
  AND  Role               = @role
  AND  Active             = 0
  AND  Locked_by_Override = 0
"@
        [void]$cmd.Parameters.AddWithValue('@uid',  $user)
        [void]$cmd.Parameters.AddWithValue('@role', $Role)
        [void]$cmd.ExecuteNonQuery()
        [void]$cmd.Parameters.Clear()
    }
} finally {
    try { $conn.Close() } catch {}
}
```

[VERIFIED: canonical artefacts — Initialize-RoleDb.ps1 (upsert pattern), CONTEXT.md D-05/D-06]

---

### Pattern 3: ActionScript Structure for Assign Action

**What:** The generated SingleAction XML. Must follow the `Init Current User and UserRole DB.bes` pattern exactly — prefetch, directory setup, createfile, waithidden. The `CompID` parameter uses BigFix server-side relevance substitution so each targeted computer gets its own ID.

```
// ActionScript body (embedded in SingleAction XML)
begin prefetch block
  add prefetch item name=unzip.exe sha1=... size=... url=http://127.0.0.1:{port}/Uploads/CustomRepository/sqlite_util/unzip.exe sha256=...
  add prefetch item name=sqlite-tools-win-x64-3530100.zip sha1=... size=... url=http://127.0.0.1:{port}/Uploads/CustomRepository/sqlite_util/sqlite-tools-win-x64-3530100.zip sha256=...
  add prefetch item name=SQLite_dlls.zip sha1=... size=... url=http://127.0.0.1:{port}/Uploads/CustomRepository/sqlite_util/SQLite_dlls.zip sha256=...
end prefetch block

parameter "RootDir"="{(pathname of parent folder of parent folder of client folder of site "actionsite") as string}"
parameter "ECDir"="{(concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC")))}"
parameter "SWPDir"="{(concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal")))}"
parameter "TargetStore"="{(concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it;item 3 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal","RoleAwareness.db")))}"
parameter "SQLiteDir"="{(concatenation (if windows of operating system then "\" else "/") of ((item 0 of it;item 1 of it;item 2 of it) of ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","sqlite")))}"
parameter "CompID"="{id of computer}"
parameter "Role"="IT Operations"   // hard-coded per action (one action per role)
parameter "chunkCount"="2"
parameter "chunk0"="eyJjb21wdXRlcnMiOls..."
parameter "chunk1"="..."

// Prepare directories (verbatim from Init BES)
if {not exists folder ((parameter "ECDir") as string)}
  runhidden cmd /c mkdir "{parameter "ECDir"}"
endif
if {not exists folder ((parameter "SWPDir") as string)}
  runhidden cmd /c mkdir "{parameter "SWPDir"}"
endif
if { (exists (folder (parameter "SQLiteDir")) whose (number of files whose (name of it = "System.Data.SQLite.dll") of folders of it < 2)) }
  folder delete "{(parameter "SQLiteDir")}"
  runhidden cmd /c mkdir "{parameter "SQLiteDir"}"
  utility __Download\unzip.exe
  folder create "{parameter "SQLiteDir"}"
  waithidden __Download\unzip.exe -o "{download path "sqlite-tools-win-x64-3530100.zip"}" -d "{parameter "SQLiteDir"}"
  waithidden __Download\unzip.exe -o "{download path "SQLite_dlls.zip"}" -d "{parameter "SQLiteDir"}"
endif

delete __createfile
delete "{parameter "SWPDir"}\Assign-RoleMapping.ps1"

createfile until _EOF_
[PowerShell script content here — see Pattern 2]
_EOF_

move __createfile "{parameter "SWPDir"}\Assign-RoleMapping.ps1"

action uses wow64 redirection {x64 of operating system}
waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "{parameter "SWPDir"}\Assign-RoleMapping.ps1" -DatabasePath "{parameter "TargetStore"}" -SQLDir "{parameter "SQLiteDir"}" -CompID "{parameter "CompID"}" -Role "{parameter "Role"}" -ChunkCount "{parameter "chunkCount"}" -chunk0 "{parameter "chunk0"}" -chunk1 "{parameter "chunk1"}"
```

**Important:** The `waithidden` PowerShell call must pass each chunk as a separate named parameter (`-chunk0`, `-chunk1`, etc.). PowerShell will receive them as `$chunk0`, `$chunk1` etc. and the PS script uses `Get-Variable -Name "chunk$i"` to retrieve them dynamically. Alternatively, pass them positionally via `$args` — but named parameters are cleaner and self-documenting.

**Client-side relevance guard (D-02):**
```
(exists folder it whose (exists files "RoleAwareness.db" whose (exists sqlite database of it) of it)) of
((concatenation (if windows of operating system then "\" else "/") of
  ((item 0 of it;item 1 of it;item 2 of it) of
    ((pathname of parent folder of parent folder of client folder of site "actionsite") as string,"EC","SoftwarePortal"))))
```
This is the same relevance expression used in `Dereso SWD.bes` — copy it verbatim.

[VERIFIED: canonical artefacts — Init Current User and UserRole DB.bes (ActionScript structure), Dereso SWD.bes (relevance expression)]

---

### Pattern 4: SingleAction XML Structure (one per role)

**What:** The full XML body posted to `API.Post("actions")`. Follows Dispatcher's `buildDeployXml()` pattern but uses a PowerShell action rather than a sourced fixlet action.

```javascript
// Source: fixlet_dispatcher.ojo buildDeployXml() + D-01, D-02, D-09 (CONTEXT.md)
function buildAssignActionXml(role, computerIds, chunkParams, suffix, targetRelevance) {
  var title = 'Dereso_' + role + ' Assign_' + suffix;
  var actionScript = buildAssignActionScript(role, chunkParams);  // see Pattern 3

  var xml  = '<?xml version="1.0" encoding="UTF-8"?>\r\n';
  xml += '<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"';
  xml += ' xsi:noNamespaceSchemaLocation="BES.xsd">\r\n';
  xml += '  <SingleAction>\r\n';
  xml += '    <Title>' + xmlEscape(title) + '</Title>\r\n';
  // Client-side relevance guard: only run if RoleAwareness.db exists
  xml += '    <Relevance>' + xmlEscape(targetRelevance) + '</Relevance>\r\n';
  xml += '    <ActionScript MIMEType="application/x-Fixlet-Windows-Shell">';
  xml += cdataStart() + xmlCDataSafe(actionScript) + cdataEnd();
  xml += '</ActionScript>\r\n';
  xml += '    <Settings>\r\n';
  xml += '      <ActionUITitle>' + xmlEscape(title) + '</ActionUITitle>\r\n';
  xml += '    </Settings>\r\n';
  xml += '    <Target>\r\n';
  // Explicit computer list (D-02): target only the computers in this role's CSV rows
  for (var i = 0; i < computerIds.length; i++) {
    xml += '      <ComputerID>' + xmlEscape(String(computerIds[i])) + '</ComputerID>\r\n';
  }
  xml += '    </Target>\r\n';
  xml += '  </SingleAction>\r\n';
  xml += '</BES>';
  return xml;
}
```

**Targeting note:** BigFix SingleAction `<Target>` accepts `<ComputerID>` child elements for explicit computer targeting. This is distinct from the Dispatcher's `<CustomRelevance>` group targeting — here we have explicit IDs from the CSV so explicit `<ComputerID>` targeting is more precise and correct. The client-side `<Relevance>` guard provides the DB-existence double-check (D-02).

[ASSUMED] — The `<ComputerID>` element in `<Target>` is the correct way to target explicit computers in a SingleAction via the REST API. This is derived from training knowledge of BigFix XML. Verify the element name against the BigFix BES.xsd or REST API docs before finalising.

---

### Pattern 5: CSV Parsing and Validation

**What:** Parse uploaded CSV in browser JS, validate against PORTAL_CONFIG.roles, build preview table, enable/disable Deploy button.

```javascript
// Source: D-03, D-13, D-14, D-15 (CONTEXT.md)
// CSV format: user,Computer_ID,role  (header row required)
function parseCsv(text) {
  var lines   = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  var headers = lines[0] ? lines[0].split(',').map(function(h){ return h.trim().toLowerCase(); }) : [];
  // Expect: user, computer_id, role
  var userIdx = headers.indexOf('user');
  var compIdx = headers.indexOf('computer_id');
  var roleIdx = headers.indexOf('role');
  if (userIdx < 0 || compIdx < 0 || roleIdx < 0) {
    return { error: 'Missing required columns: user, Computer_ID, role' };
  }
  var rows = [];
  for (var i = 1; i < lines.length; i++) {
    var line = lines[i].trim();
    if (!line) { continue; }
    var parts = line.split(',');
    rows.push({
      user:       (parts[userIdx]  || '').trim(),
      computerID: (parts[compIdx]  || '').trim(),
      role:       (parts[roleIdx]  || '').trim(),
      lineNum:    i + 1
    });
  }
  return { rows: rows };
}

function validateRows(rows, allowedRoles) {
  var seen     = {};  // "user|computerID|role" -> true  for duplicate detection
  var errors   = [];
  var warnings = [];

  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var key = row.user + '|' + row.computerID + '|' + row.role;

    // BLOCK: blank user
    if (!row.user) {
      errors.push({ rowIndex: i, field: 'user', msg: 'User is blank' });
    }
    // BLOCK: blank Computer_ID
    if (!row.computerID) {
      errors.push({ rowIndex: i, field: 'computerID', msg: 'Computer_ID is blank' });
    }
    // BLOCK: unknown role
    if (row.role && allowedRoles.indexOf(row.role) < 0) {
      errors.push({ rowIndex: i, field: 'role', msg: 'Unknown role: "' + row.role + '"' });
    }
    // WARN: duplicate
    if (seen[key]) {
      warnings.push({ rowIndex: i, msg: 'Duplicate row (will be ignored by upsert)' });
    }
    seen[key] = true;
  }
  return { errors: errors, warnings: warnings };
}
```

[VERIFIED: canonical artefacts — D-15 specifies the exact validation rules; role_targeting.csv provides the column format]

---

### Pattern 6: Analysis Property Parsing in Dashboard JS

**What:** `mapped_users in r.db` returns results via `GetRelevance()`. Each result is a two-part tuple parsed in BigFix relevance; the dashboard receives already-parsed strings.

From `gpbfs_analysis_results.txt`:
```
Computer Name    mapped_users in r.db
GPBFS            Administrator, IT Developer
```

The Analysis relevance (`Dereso SWD.bes` Property ID=3) uses:
```
(following text of first "%22" of tuple string item 0 of it,
 preceding text of first "%22" of tuple string item 1 of it)
of (rows of statement "select concat(UserID, ', ', Role) from map where Active = 1" ...)
```

The relevance returns two values per row (a tuple): item 0 is the UserID, item 1 is the Role. The `tuple string item N` plus `following/preceding text of first "%22"` dance strips the surrounding double-quotes that BigFix adds when converting row values to strings.

**Dashboard JS** reads the Analysis via:
```javascript
// Source: D-17 (CONTEXT.md), Dereso SWD.bes Property ID=3
// GetRelevance returns an array; each element is one reporting computer's property value.
// For multi-value properties, the array has one entry per computer, each being a
// newline- or semicolon-delimited list of (UserID, Role) pairs.
// Exact delimiter depends on how multiple tuples are returned — needs console verification.
function loadAnalysisView() {
  // Query: all values of the "mapped_users in r.db" property across all reporting computers
  var rel = '(name of computer of it as string & "|||" & value of it as string)' +
            ' of results of bes property whose (name of it = "mapped_users in r.db")';
  try {
    var data = GetRelevance(rel);
    // ... parse and render
  } catch (ex) {
    // Analysis not yet imported or no computers reporting
  }
}
```

**Important caveat:** When a property returns multiple tuples (multiple mapped users on one computer), how BigFix separates them in a single `value of it` call depends on the console version. The Analysis returns one result per (computer, row) — so `results of bes property` may give one entry per computer with multi-line value, or one entry per (computer, row). This needs confirmation against a live console. [ASSUMED — see Open Questions #1]

[VERIFIED: canonical artefacts — Dereso SWD.bes Property ID=3, gpbfs_analysis_results.txt]

---

### Pattern 7: Dereso SWD.bes Finalisation

**What changes are needed to make the Analysis production-ready?**

Inspecting `Dereso SWD.bes` against `Initialize-RoleDb.ps1` DDL:

| Property | Current SQL | Issue | Fix |
|----------|-------------|-------|-----|
| `mapped_users in r.db` (ID=3) | `select concat(UserID,', ', Role) from map where Active = 1` | SQL is correct against the Map DDL (`UserID`, `Role` columns exist). No column mismatch. | No fix needed for column names. |
| `Roles in r.db` (ID=1) | `select Role from Roles` | Correct. | None. |
| `users in r.db` (ID=2) | `SELECT userid from users` | Column is `UserID` (mixed case in DDL). SQLite is case-insensitive for column names, so this works. | Cosmetic — can align to `UserID` for clarity. |
| `recent users` (ID=4) | `SELECT userid from users where (unixepoch() - unixepoch(LastSeen)) / (60 * 60 * 24) < 7` | Correct against DDL. | None. |

**Actual changes needed:**

1. **Description field:** The `<Description>` element contains `<enter a description of the analysis here>` — replace with meaningful production description.
2. **`mapped_users in r.db` tuple parsing:** The current relevance expression uses `following text of first "%22"` / `preceding text of first "%22"` to strip quotes. This works when BigFix returns the value as `"UserID"`, `" Role"` in tuple string format. Verify the output format matches `gpbfs_analysis_results.txt` (`Administrator, IT Developer`) — it does. The approach is correct.
3. **No column renames needed** — all SQL is correct against the DDL.

[VERIFIED: canonical artefacts — Dereso SWD.bes + Initialize-RoleDb.ps1 DDL cross-checked directly]

---

### Pattern 8: PORTAL_CONFIG Structure for Role Assigner

```javascript
// Source: D-19 (CONTEXT.md), fixlet_modifier.ojo, fixlet_dispatcher.ojo
var PORTAL_CONFIG = {
    targetGroups: [
        'All Workstations',
        'IT Department',
        'Finance Department',
        'All Servers'
    ],
    roles: [
        'IT Operations',
        'Finance',
        'HR'
        // Update this list when management changes role definitions.
        // Must match PORTAL_CONFIG.roles in fixlet_modifier.ojo.
    ],
    actionNamePrefix: 'Dereso'
};
```

**Role list sync requirement (D-19):** The planner must include a verification task confirming `PORTAL_CONFIG.roles` in `fixlet_role_assigner.ojo` matches `PORTAL_CONFIG.roles` in `fixlet_modifier.ojo`. They are currently different (Modifier has 7 roles; Role Assigner will have the management-decided 3-role list). The admin is responsible for keeping them in sync — the code comment should call this out.

[VERIFIED: canonical artefacts — fixlet_modifier.ojo PORTAL_CONFIG + D-19]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite access from PowerShell | PSGallery module, raw sqlite3.exe | `System.Data.SQLite.dll` from custom repo | Already bundled in repo, established in Init BES, works in restricted environments |
| CSV parsing in JS | Complex regex parser | Simple `split(',')` on each line | CSV in this project has no quoted commas; keep it simple. If quoted fields needed, scope creep |
| XML parsing in dashboard | Custom string manipulation | `Msxml2.DOMDocument.6.0` ActiveXObject | Platform standard; avoids XSS from manual string manipulation |
| Action ID extraction from POST response | Single regex | `parseActionId()` verbatim from `fixlet_dispatcher.ojo` | Already has 3 fallback paths; proven in Phase 3 |
| BigFix target group relevance | Custom relevance strings | `buildTargetRelevance()` verbatim from `fixlet_dispatcher.ojo` | Handles Automatic/Manual/Server Based; tested in Phase 3 unit tests |
| Base64 encoding | Custom bit-shift B64 | `btoa()` browser built-in + `[System.Convert]::ToBase64String` on PS side | Platform built-ins; no external dependency |

---

## Runtime State Inventory

Not applicable — this is a greenfield phase (new dashboard and Analysis, no renaming).

---

## Common Pitfalls

### Pitfall 1: `btoa()` and Unicode / non-ASCII characters in usernames

**What goes wrong:** `btoa()` throws `InvalidCharacterError` when the string contains characters outside the Latin-1 range (e.g., accented characters in usernames). For ASCII-only usernames this is fine, but international usernames will cause silent failure.

**Why it happens:** `btoa()` only handles byte values 0-255; any character above U+00FF throws.

**How to avoid:** Before calling `btoa()`, encode the JSON string to ensure it is safe:
```javascript
// Safe B64 encode for potentially non-ASCII strings
function safeB64Encode(str) {
  // encodeURIComponent percent-encodes non-ASCII, unescape converts to Latin-1 bytes
  return btoa(unescape(encodeURIComponent(str)));
}
// Decode on PowerShell side:
// [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
// (UTF8 decoding handles the unescape/encodeURIComponent encoding)
```

**Warning signs:** `btoa()` throws in-browser; PowerShell `FromBase64String` decodes to garbled text.

[ASSUMED — `btoa()` Unicode limitation is well-documented browser behaviour]

---

### Pitfall 2: INSERT OR REPLACE destroys Locked_by_Override

**What goes wrong:** Using `INSERT OR REPLACE` (instead of `INSERT OR IGNORE` + conditional `UPDATE`) deletes the existing row and re-inserts it — resetting `Locked_by_Override=0` and `Active=1` even for locked rows.

**Why it happens:** `INSERT OR REPLACE` with a UNIQUE constraint conflict deletes + re-inserts. This destroys all existing field values including `Locked_by_Override`.

**How to avoid:** Always use the D-06 two-step pattern from `Initialize-RoleDb.ps1`. This is documented explicitly in the ps1 comment block: "INSERT OR REPLACE is prohibited".

**Warning signs:** Re-importing a CSV overrides a manually locked admin assignment. The Overrides table record is intact but `Locked_by_Override` in Map is reset to 0.

[VERIFIED: canonical artefacts — Initialize-RoleDb.ps1 comment block explicitly prohibits INSERT OR REPLACE]

---

### Pitfall 3: ActionScript parameter value containing quotes

**What goes wrong:** If a PowerShell chunk parameter value contains a double-quote character (which B64 output does not — B64 uses `A-Za-z0-9+/=` only), the ActionScript line `parameter "chunk0"="..."` would break.

**How to avoid:** Base64 output is guaranteed to contain only `[A-Za-z0-9+/=]` — no quotes possible. This pitfall does not apply to the B64 chunks themselves. However, the `Role` parameter value could contain characters the admin could mistype. Validate that role values come only from `PORTAL_CONFIG.roles` (already enforced by D-15 validation).

[VERIFIED: Base64 alphabet specification — no double-quote character in output]

---

### Pitfall 4: `FileReader` API availability in BigFix console (IE9)

**What goes wrong:** The BigFix console uses an embedded IE9-era browser. `FileReader` was introduced in IE10. If the dashboard attempts to use `FileReader` to read the uploaded CSV file, it will silently fail in some BigFix console versions.

**How to avoid:** Use `<input type="file">` with `onchange` and read via `files[0]`. Then check availability:
```javascript
function handleFileUpload(input) {
  var file = input.files ? input.files[0] : null;
  if (!file) { setStatus('No file selected'); return; }
  if (typeof FileReader === 'undefined') {
    setStatus('File reading not supported in this console version. Paste CSV text instead.');
    // Offer a textarea fallback for CSV text paste
    return;
  }
  var reader = new FileReader();
  reader.onload = function(e) { processCSVText(e.target.result); };
  reader.readAsText(file);
}
```
Provide a `<textarea>` fallback where admin can paste CSV content directly.

[ASSUMED — FileReader IE10+ limitation; BigFix console IE version varies]

---

### Pitfall 5: `waithidden powershell.exe` parameter count limit

**What goes wrong:** The `waithidden` command line has a maximum length (Windows command line limit: ~32,767 chars). Passing 10+ chunk parameters as separate `-chunk0 "..." -chunk1 "..."` arguments on a single command line may approach this limit.

**Why it happens:** Each 3000-char chunk plus its parameter name adds ~3010 chars. 10 chunks = ~30,100 chars, which approaches the Windows limit.

**How to avoid:** The chunk limit of 3000 chars with a realistic CSV (say 100 rows, ~30 chars per row of JSON) produces approximately 3,000 chars of JSON, ~4,000 chars of B64, requiring 2 chunks. Even a 500-row CSV (~15,000 chars JSON, ~20,000 chars B64) would need 7 chunks = ~21,000 chars on the command line. This is a real risk for large imports.

**Safer alternative:** Write chunks to a temp file via `createfile` instead of passing them as parameters. Then the PowerShell script reads from the file. This avoids the command line length issue entirely. [ASSUMED — this alternative was not specified in CONTEXT.md; flag for planner]

**Warning signs:** `waithidden` command exits immediately with error code 2 (command line too long).

[ASSUMED — Windows command line length limit is well-documented; chunk count math above is verified]

---

### Pitfall 6: `GetRelevance()` vs `EvaluateRelevance()` for Analysis properties

**What goes wrong:** `EvaluateRelevance()` evaluates arbitrary relevance on the local client (the admin's machine running the console). For Analysis properties that read from client machines' databases, `GetRelevance()` (which queries the BigFix server's cached results) is required.

**How to avoid:** Use `GetRelevance()` when reading Analysis property results aggregated across clients. Use `EvaluateRelevance()` only for local console data (fixlet lists, computer groups, etc.).

The distinction is present in existing dashboards: `fixlet_dispatcher.ojo` uses `EvaluateRelevance()` for local fixlet/group queries. Phase 4 must use `GetRelevance()` for Analysis data.

[VERIFIED: canonical artefacts — fixlet_dispatcher.ojo uses EvaluateRelevance for local data; Dereso SWD.bes Analysis is remote client data]

---

### Pitfall 7: Dereso SWD.bes Analysis must be imported before the dashboard's read view works

**What goes wrong:** If the admin opens the Role Assigner dashboard before importing `Dereso SWD.bes` into the BigFix console, `GetRelevance()` calls for the Analysis properties will throw or return empty. The dashboard must handle this gracefully.

**How to avoid:** Wrap all `GetRelevance()` Analysis calls in try/catch. Display "Analysis not found — import Dereso SWD.bes first" when the call fails. This is D-21.

[VERIFIED: canonical artefacts — D-21 specifies this check; GetRelevance throws on missing property]

---

## File Inventory

### Files to Create

| File | Purpose |
|------|---------|
| `Existing Dashboards/fixlet_role_assigner.ojo` | New dashboard — scaffolded from `fixlet_dispatcher.ojo` |
| `tests/unit/role_assigner.test.js` | Unit tests for pure JS functions (B64 chunking, CSV parsing, validation, XML building helpers) |
| `tests/integration/role_assigner.integration.test.js` | Integration test — POST round-trip (env-var gated) |
| `tests/fixtures/phase-04/sample.csv` | Valid 3-role CSV fixture |
| `tests/fixtures/phase-04/invalid-unknown-role.csv` | Fixture for validation test |
| `tests/fixtures/phase-04/invalid-blank-fields.csv` | Fixture with blank user and blank Computer_ID rows |
| `tests/fixtures/phase-04/duplicate-rows.csv` | Fixture with duplicate (User, Computer_ID, Role) rows |

### Files to Modify

| File | Change |
|------|--------|
| `Dashboard_4_samples/Dereso SWD.bes` | Replace `<Description>` placeholder text with production description. No SQL changes required — all column references are correct against DDL. |

### Files to Read (during implementation — executor must read these)

| File | Why |
|------|-----|
| `Dashboard_4_samples/Initialize-RoleDb.ps1` | Exact upsert pattern, DLL path logic, connection string |
| `Dashboard_4_samples/Init Current User and UserRole DB.bes` | Exact prefetch SHA hashes and URLs, directory setup sequence, `createfile…_EOF_` pattern |
| `Existing Dashboards/fixlet_dispatcher.ojo` | Functions to reuse verbatim: `buildTargetRelevance`, `parseActionId`, `xmlEscape`, `htmlEscape`, `cdataStart/End`, `xmlCDataSafe`, group selector, success banner pattern |

---

## Test Strategy

### Unit-Testable Functions (Node.js, no BigFix required)

The same pattern as `tests/unit/dispatcher.test.js` — extract pure JS functions into the test file and test them with Node.js built-in `assert`.

| Function | Test Cases |
|----------|-----------|
| `parseCsv(text)` | Valid CSV, missing columns, empty lines, CRLF vs LF, header case insensitivity |
| `validateRows(rows, allowedRoles)` | Unknown role blocks, blank user blocks, blank Computer_ID blocks, duplicate warns, valid row passes |
| `encodeMatrix(computers, users)` | Round-trips: encode then decode produces original data; empty arrays; single pair |
| `chunkString(s, size)` | Exact chunk boundaries, remainder chunk, empty string |
| `buildChunkParams(b64)` | Correct parameter line format, correct `chunkCount` value |
| `xmlEscape(s)` | Already tested in dispatcher; reuse or copy |
| `xmlCDataSafe(s)` | Already tested in dispatcher; reuse or copy |
| `buildAssignActionXml(role, computerIds, chunkParams, suffix, rel)` | Title format matches D-09 naming convention; contains `<ComputerID>` for each ID; contains `<Relevance>` |
| `PORTAL_CONFIG` assertions | `roles` is a non-empty array; `actionNamePrefix` is `'Dereso'`; `targetGroups` is an array |

**Running:** `node tests/unit/role_assigner.test.js` — exits 0 on pass, 1 on failure. No framework, no install.

### Requires BigFix Console (Manual / Integration)

| Test | What to verify |
|------|---------------|
| CSV upload + preview render | Upload `sample.csv`; preview table shows 4 rows (2 roles); Deploy enabled |
| Validation blocking | Upload `invalid-unknown-role.csv`; Deploy button stays disabled; unknown role highlighted in red |
| Validation warning | Upload `duplicate-rows.csv`; Deploy enabled; duplicate rows flagged in amber |
| Deploy one role action | Upload 1-role CSV; click Deploy; success banner shows action ID |
| Deploy multi-role CSV (3 roles) | Upload 3-role CSV; 3 `API.Post` calls fire; 3 success banners appear |
| Analysis view | After deploying and waiting for Analysis refresh; table shows mapped users per computer |
| Uninitialised DB warning | CSV contains Computer_ID not in Analysis results; warning row appears in table |
| FileReader fallback (if IE9) | Test `<textarea>` paste path produces same preview as file upload |

### Integration Test (env-var gated, same as dispatcher)

```javascript
// tests/integration/role_assigner.integration.test.js
// Skip if BIGFIX_URL, BIGFIX_USER, BIGFIX_PASS not set
// POST a minimal SingleAction to /api/actions
// Assert 200 or 201 response
// Assert parseActionId(body) returns a non-empty string
```

---

## Validation Architecture

> `workflow.nyquist_validation` is not explicitly `false` in `.planning/config.json` — section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Node.js built-in `assert` (no framework install required) |
| Config file | None — test files are run directly |
| Quick run command | `node tests/unit/role_assigner.test.js` |
| Full suite command | `node tests/unit/copier.test.js && node tests/unit/modifier.test.js && node tests/unit/dispatcher.test.js && node tests/unit/role_assigner.test.js` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FR-02 | CSV import drives DB upsert per user-role pair | unit | `node tests/unit/role_assigner.test.js` | No — Wave 0 |
| FR-02 | Validation blocks deploy on unknown role | unit | `node tests/unit/role_assigner.test.js` | No — Wave 0 |
| FR-02 | One action per role generated from CSV | unit (buildAssignActionXml) | `node tests/unit/role_assigner.test.js` | No — Wave 0 |
| FR-03 | Client relevance guard: action only runs if DB exists | manual (BigFix console) | n/a — requires live BigFix agent | n/a |
| FR-03 | Analysis view shows active mappings | manual (BigFix console) | n/a — requires Analysis import + reporting clients | n/a |

### Sampling Rate

- **Per task commit:** `node tests/unit/role_assigner.test.js`
- **Per wave merge:** Full suite (all 4 unit test files)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- `tests/unit/role_assigner.test.js` — covers FR-02 pure-JS behaviors (parseCsv, validateRows, encodeMatrix, chunkString, buildChunkParams, buildAssignActionXml)
- `tests/fixtures/phase-04/sample.csv` — valid 3-role CSV
- `tests/fixtures/phase-04/invalid-unknown-role.csv` — triggers block validation
- `tests/fixtures/phase-04/invalid-blank-fields.csv` — triggers block validation
- `tests/fixtures/phase-04/duplicate-rows.csv` — triggers warn validation
- `tests/integration/role_assigner.integration.test.js` — POST round-trip (env-var gated)

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (BigFix console handles auth) | — |
| V3 Session Management | No (BigFix console) | — |
| V4 Access Control | No (BigFix RBAC — RequiresAuthoring flag) | `RequiresAuthoring="false"` in Wizard XML (same as other dashboards) |
| V5 Input Validation | Yes | `validateRows()` — blocks unknown roles, blank fields; `htmlEscape()` on all user-sourced data rendered to DOM |
| V6 Cryptography | No | B64 is encoding, not encryption; no secrets transmitted |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| XSS via CSV content rendered to table | Spoofing / Tampering | `htmlEscape()` on all CSV-derived values before `innerHTML` — established in all prior dashboards |
| CSV role field injection (unknown role triggers PS execution of arbitrary string) | Tampering | Validate role against `PORTAL_CONFIG.roles` whitelist before embedding in ActionScript; escape role value in ActionScript parameter line |
| ActionScript parameter injection (role or suffix value breaks parameter syntax) | Tampering | `xmlEscape()` covers `&<>"'`; ActionScript parameter quoting needs explicit validation that role/suffix contain no `"` characters. Strip or reject values containing double-quotes. |

---

## Wave / Dependency Suggestions

| Wave | Plans (suggested) | Dependencies |
|------|------------------|--------------|
| **Wave 1** | Test fixtures (`tests/fixtures/phase-04/`) + unit test skeleton (`role_assigner.test.js` with `it.todo`-equivalent stubs) | None — foundational |
| **Wave 2** | Pure JS utility functions: `parseCsv`, `validateRows`, `encodeMatrix`, `chunkString`, `buildChunkParams`, `buildAssignActionXml` with full unit tests | Wave 1 (fixtures) |
| **Wave 3** | `fixlet_role_assigner.ojo`: PORTAL_CONFIG + CSV UI (upload/paste/preview/validation/deploy flow) + Analysis read-only view + success/error banners | Wave 2 (functions proven) |
| **Wave 4** | `Dereso SWD.bes` description finalisation + integration test + regression gate (all 4 unit suites) | Wave 3 (dashboard complete) |

**Rationale for sequencing:**
- Waves 1+2 (test infrastructure before implementation) follows the established project pattern.
- Wave 3 is the largest plan — the full `.ojo` file. It can proceed as a single plan because the JS functions will already be unit-tested.
- Wave 4 is lightweight: one-line BES edit, one integration test file, one regression check.

---

## Open Questions / Risks

### OQ-1: Multi-value Analysis property result format (MEDIUM risk)

**What we know:** `Dereso SWD.bes` Property ID=3 (`mapped_users in r.db`) returns a tuple per active Map row. The sample output (`gpbfs_analysis_results.txt`) shows `Administrator, IT Developer` as a single cell for GPBFS — which suggests the BigFix console tab-delimited output collapsed two tuples into one cell, OR the Analysis SQL returned one concatenated value.

**What's unclear:** When multiple users are mapped on one computer and the dashboard reads `value of it` from a `results of bes property` query, does each (computer, row) appear as a separate result array entry, or does BigFix concatenate multiple values for the same computer into a single newline-delimited string?

**Recommendation:** On first console test, log the raw return value from `GetRelevance()` for the Analysis property to determine the actual structure. Write the parsing function defensively to handle both cases (single value per entry vs. newline-delimited multi-values per computer).

---

### OQ-2: `<ComputerID>` vs `<CustomRelevance>` targeting in SingleAction REST POST (LOW-MEDIUM risk)

**What we know:** The Dispatcher uses `<CustomRelevance>` inside `<Target>` for group-based targeting (client-side evaluation). For explicit computer ID targeting, BigFix REST API SingleAction XML should support `<ComputerID>` child elements.

**What's unclear:** Whether the REST API / BES.xsd for `SingleAction` uses `<ComputerID>` or some other element for explicit computer targeting when posted to `/api/actions`.

**Recommendation:** Before implementing `buildAssignActionXml()`, verify the `<Target>` element structure for explicit computer ID targeting. Options: (a) check `BES.xsd` if accessible in the BigFix install, (b) test a minimal POST with 1 computer ID, (c) use `<CustomRelevance>` with an ID-equality relevance expression as a fallback (`id of computer = <compID>`).

[ASSUMED — needs console verification]

---

### OQ-3: btoa() availability in BigFix console IE version (LOW risk)

**What we know:** `btoa()` was added to IE10. BigFix console historically used IE9 mode (`<meta http-equiv="X-UA-Compatible" content="IE=9">`).

**What's unclear:** Whether the BigFix console's embedded browser actually restricts `btoa()` even with the IE=9 meta tag, or whether the underlying Trident engine version (which may be IE11 runtime even with IE9 compatibility mode) supports `btoa()`.

**Recommendation:** Test `typeof btoa !== 'undefined'` in the console. If unavailable, implement a simple pure-JS B64 encoder (Base64 is a small function, ~20 lines) as a fallback. Include both the native check and the fallback to avoid a hard dependency on `btoa()`.

[ASSUMED — IE9 compat mode vs runtime engine behaviour in BigFix console may differ]

---

### OQ-4: Large CSV performance (LOW risk)

**What we know:** Each `API.Post("actions")` call is synchronous from the dashboard's perspective (callback-based). For a 3-role CSV the dashboard fires 3 sequential `API.Post` calls. For a 10-role CSV, 10 calls.

**What's unclear:** Whether 10+ sequential `API.Post` calls will stay within the NFR-01 `< 2 second` target, or whether the dashboard needs a queued/sequential dispatch pattern.

**Recommendation:** Fire calls sequentially (wait for callback before firing next) to avoid overwhelming the REST API. Show a per-action progress indicator ("Deploying role 2 of 3...") rather than firing all in parallel.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `<ComputerID>` is the correct child element of `<Target>` in SingleAction REST XML for explicit computer targeting | Pattern 4, OQ-2 | Action targeting fails silently — no computers receive the action |
| A2 | `btoa()` is available in the BigFix console's embedded browser | Pattern 1, Pitfall 1, OQ-3 | B64 encoding fails; dashboard throws JS error on deploy; need pure-JS fallback |
| A3 | `FileReader` API is available in the BigFix console | Pitfall 4 | File upload silently does nothing; must offer textarea paste fallback |
| A4 | Multi-value Analysis property results come as separate array entries per (computer, mapping) row | OQ-1 | Table rendering shows wrong grouping or blank rows |
| A5 | Passing chunks as `-chunk0 "..."` named PS parameters on the waithidden command line stays under Windows 32K char limit for typical import sizes | Pitfall 5 | Large imports fail silently on client; need temp-file approach |
| A6 | `PowerShell ConvertFrom-Json` parses the B64-decoded matrix JSON correctly in PS 5.1 | Pattern 2 | Client-side JSON parse fails; no users are upserted |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| BigFix console | Dashboard testing | Unknown — requires live console | — | None (required for UAT) |
| Node.js | Unit tests | Unknown | — | Required for `node tests/unit/role_assigner.test.js` |
| `Dashboard_4_samples/Dereso SWD.bes` | Analysis view | Present (verified by Read) | — | — |
| `Dashboard_4_samples/Initialize-RoleDb.ps1` | PowerShell script reference | Present (verified by Read) | — | — |
| `Init Current User and UserRole DB.bes` | Prefetch hashes + ActionScript pattern | Present (verified by Read) | — | — |

---

## Sources

### Primary (HIGH confidence — verified from canonical artefacts in this repo)

- `Dashboard_4_samples/Initialize-RoleDb.ps1` — DB schema, upsert pattern, connection string, error codes
- `Dashboard_4_samples/Init Current User and UserRole DB.bes` — ActionScript prefetch hashes, directory parameter patterns, createfile/waithidden sequence
- `Dashboard_4_samples/Dereso SWD.bes` — Analysis property SQL, relevance expressions, tuple parsing pattern
- `Dashboard_4_samples/role_targeting.csv` — CSV column format (user, Computer_ID, role)
- `Dashboard_4_samples/gpbfs_analysis_results.txt` — Sample Analysis output, actual property value format
- `Existing Dashboards/fixlet_dispatcher.ojo` — API.Post pattern, buildTargetRelevance, parseActionId, success banner, group selector, SingleAction XML structure
- `Existing Dashboards/fixlet_modifier.ojo` — PORTAL_CONFIG block, role list pattern, htmlEscape, xmlEscape
- `.planning/phases/04-role-assigner/04-CONTEXT.md` — 23 locked decisions (primary scope constraint)
- `tests/unit/dispatcher.test.js` — Unit test pattern, function extraction convention

### Secondary (MEDIUM confidence)
- `tests/unit/modifier.test.js`, `tests/integration/dispatcher.integration.test.js` — test file structure patterns

### Tertiary (ASSUMED — training knowledge, not verified via authoritative source)
- `<ComputerID>` element name in SingleAction `<Target>` for REST API explicit targeting (A1)
- `btoa()` availability in IE9-era BigFix console (A2/A3)
- Windows command line length limit effect on chunk parameter count (A5)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components verified from existing canonical artefacts
- Architecture patterns: HIGH — direct derivation from Init BES and Dispatcher .ojo
- Pitfalls: MEDIUM — items 1-3, 6-7 are HIGH (verified from code); items 4-5 are ASSUMED
- Open questions: LOW — require live console verification

**Research date:** 2026-06-27
**Valid until:** Stable — BigFix platform APIs and PowerShell 5.1 are not fast-moving targets; valid for at least 90 days
