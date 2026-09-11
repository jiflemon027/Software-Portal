# Role Assigner Redesign — Reference DB + Auto Assignment

**Created:** 2026-08-28
**Updated:** 2026-08-29 — opens 1–4 resolved (full CSV provided, username match confirmed, AKeyless path/identity fixed, region values supplied)
**Updated:** 2026-08-29 (later) — remaining smaller questions 1/2/4 resolved by operator; BigFix MCP back online; Phase-7 framing decided.
**Branch:** 260813-fjc-fixlet-console (uncommitted work already present — see memory `role-awareness-logon-rework-status`)
**Status:** DESIGN — decisions locked; ready to rewrite Phase 7 in place.
**Relation to Phase 7:** **REWRITE PHASE 7 IN PLACE (decided 2026-08-29).** Phase 7's
role-pipeline plans (`07-00`, `07-01`) and their supporting sections in `07-CONTEXT.md`
are replaced by this design. Phase 7 stays the single "End-to-End Automation" phase and
keeps its content-sync pipeline (`07-02`), automation dashboard (`07-03`), and rollout
(`07-04`). Phase 7's old role pipeline assumed server-side user→computer resolution +
per-ComputerID actions, which goal 3 below explicitly rejects.

---

## User's stated goals

1. **Automate the current manual task** — replace the admin CSV upload / preview / deploy
   loop in `fixlet_role_assigner.ojo` with a scheduled server-side pipeline.
2. **Break the link between the task and the CSV file** — source of truth becomes a
   reference database on the BigFix root server, populated from a daily Axonius export.
   Full anonymised export now on disk: `SampleAxonious/axonius-users_anond.csv`
   (~401 MB, one row per user, 47 columns; `axonious.db` is the same data as SQLite).
3. **Break the hardlink between users and computer IDs** — role assignment must follow the
   *user* to whatever computer they log into. No precomputed user→ComputerID matrix.
   Up to a **24-hour** propagation delay is acceptable.
   **Match key RESOLVED (2026-08-29):** ingest normalises to lowercased `sAMAccountName`;
   the endpoint compares against the BigFix client-relevance clause
   `name of current user` (lowercased). The two are confirmed to align — no
   `explorer.exe`→`GetOwner()` step needed. This removes the #1 risk.

---

## Current functionality (baseline being changed)

### `Existing Dashboards/fixlet_role_assigner.ojo` (BigFix console dashboard)
- `PORTAL_CONFIG` block: `roles` whitelist (`"IT Operations"`, `"Business Operations"`),
  `validityMonths: 6`, `targetGroups` (display only), `actionNamePrefix: 'DSD_'` (unused —
  title is hardcoded `Dereso_[role] Assign_[suffix]`).
- On load: `loadGroups()` (EvaluateRelevance over `bes computer groups`), `loadAnalysisView()`
  (GetRelevance on `mapped_users in r.db` from `Dereso SWD.bes`).
- CSV workflow: admin supplies `user,Computer_ID,role` CSV (file or paste) →
  `parseCsv()` / `validateRows()` (blank user/comp/role = blocking error; role not in
  whitelist = blocking error; duplicate = warning) → `renderPreview()` OK/WARN/ERROR table.
- Deploy (`deployAll` → `deployNextRole`): groups rows by role → **one SingleAction per
  unique role**, dispatched sequentially. Per role: `{computers:[...],users:[...]}` parallel
  arrays → JSON → UTF-8-safe base64 → 3000-char chunks as `parameter "chunkN"`.
  `<Target>` = explicit `<ComputerID>` list. `<Relevance>` = RoleAwareness.db existence guard.
- ActionScript (`buildAssignActionScript`) provisions `sqlite3.exe`, writes
  `EC\SoftwarePortal\Assign-RoleMapping.ps1`, runs it with `-CompID {computer id}` (server-
  side substitution), `-Role`, `-ValidityMonths`, chunks.
- `Assign-RoleMapping.ps1` (embedded): reassembles base64 → JSON, **matches its own
  `{computer id}` against the matrix `computers[]`**, then per matched user does D-12 upsert
  into local `RoleAwareness.db`: `INSERT OR IGNORE` Users + Map, then
  `UPDATE Map SET Active=1, Valid_to=now+N months WHERE ... AND Locked_by_Override = 0`.
- Analysis view cross-checks CSV Computer_IDs vs reporting computers → amber
  "DB not initialised (D-21)" for any missing.

### Supporting components
- `Dashboard_4_samples/Init  Current User and UserRole DB.bes` — creates endpoint
  `RoleAwareness.db` schema, registers `RoleDB_Maintenance` logon scheduled task
  (reruns `Initialize-RoleDb.ps1` every logon: refresh `Users.LastSeen`, renew
  `Map.Valid_to` for the logged-on user where `Active=1 AND Locked_by_Override=0`).
- `Dashboard_4_samples/Initialize-RoleDb.ps1` — schema + logon maintenance. Tables:
  `Roles`, `Users(UID,UserID,LastSeen)`, `Map(MapID,UserID,Role,Active,Locked_by_Override,
  Created_on,Updated_on,Valid_to, UNIQUE(UserID,Role))`, `Overrides`. Migration-safe
  (`CREATE TABLE IF NOT EXISTS`, `PRAGMA table_info`-gated `ALTER TABLE`). CLM-safe
  (`sqlite3.exe` via `Sqlite-Helper.ps1`, zero `Add-Type`).
- `Dashboard_4_samples/Dereso SWD.bes` — Analysis: `mapped_users in r.db`, `Roles in r.db`,
  `users in r.db`, `recent users`.
- Downstream consumers of `Map`/`Roles`: `fixlet_modifier.ojo` role relevance,
  `fixlet_console.ojo`, SSA `_dashboard.html` §1 role panel. **Contract to preserve.**

### Why the current design conflicts with the goals
- Goal 2: the CSV *is* the input contract. Must be replaced by the reference DB.
- Goal 3: `computers[]` in the payload + `-CompID {computer id}` match + `<Target>` =
  ComputerID list means a user is only assigned a role on the specific machine(s) the admin
  listed. Log into a new laptop → no role until the admin re-runs a CSV.

---

## Proposed architecture

Three decoupled loops. No ComputerID appears anywhere in the role pipeline.

### Loop 1 — Ingest (root server, scheduled daily)
`scripts/Import-AxoniousExport.ps1`
1. Read the daily Axonius export from a configured path (CSV; format TBD — see open
   questions). Stale-file guard (`MaxExportAgeDays`, warn don't abort).
2. Normalise: `username` → `.ToLower()` (matches BigFix `names of logged on users as
   lowercase` and every existing component's storage convention).
3. Resolve entitlements: each user's AD groups / mailing lists / Axonius attributes →
   role(s), via a `GroupRoleMap` rule table (exact + `*`-suffix wildcard, case-insensitive,
   priority-ordered — same matcher Phase 7 D-03 specced).
4. Upsert into `RoleReference.db` (root-server SQLite). For each (user, role, source-group)
   record *what* granted it: `Source_Type`, `Source_Value` (the CN / display name),
   `Source_System` (adapter), and which `GroupRoleMap` rule fired.
5. **Age-out marking:** any `UserRole` row not seen in *this* run gets `Active = 0` (row is
   kept, not deleted — audit/reporting). The snapshot emits only `Active = 1`, so an
   ex-member simply stops being renewed and their endpoint `Map` row lapses at `Valid_to`.
   No explicit endpoint deactivation — this *is* the age-out.
6. Log the run (`SyncRun` table + D-18 JSON log + Event Log on failure).

Region is **not** resolved here — the endpoint supplies its own via `GPC_Sub_Name`
(snapshot is global, endpoint self-filters). `RefUser.RegionID` is a reporting-only slot the
operator's region form (designed later) will populate.

---

## Database designs

### A. `RoleReference.db` — NEW, on the BigFix root server

Conventions match `Initialize-RoleDb.ps1`: `CREATE TABLE IF NOT EXISTS`, `INTEGER PRIMARY
KEY AUTOINCREMENT`, `datetime('now','localtime')` timestamps, partial indexes, `PRAGMA
table_info` migrations, CLM-safe access via `Sqlite-Helper.ps1`.

```sql
-- 1. Role catalogue — canonical role names. Mirrors RoleAwareness.db Roles and
--    fixlet PORTAL_CONFIG.roles.
CREATE TABLE IF NOT EXISTS Role (
    RoleID      INTEGER PRIMARY KEY AUTOINCREMENT,
    Role        TEXT NOT NULL UNIQUE COLLATE NOCASE,
    Description TEXT,
    Active      INTEGER NOT NULL DEFAULT 1,
    Created_on  TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 2. Region catalogue — valid GPC_Sub_Name client-setting values. Seed list is FIXED
--    (supplied by operator 2026-08-29), 13 distinct values:
--      UAP, MOT, APAC, APAC-MOT, APAC-M&A,
--      AAG-DE, AAG-FR, AAG-UK, AAG-ES, AAG-BLX, AAG-PL, AAG-PT, GPC
--    (No fleet sweep needed. Verify against live client settings once MCP is back.)
--    The (later) operator region form is a picker over this table.
CREATE TABLE IF NOT EXISTS Region (
    RegionID     INTEGER PRIMARY KEY AUTOINCREMENT,
    GPC_Sub_Name TEXT NOT NULL UNIQUE COLLATE NOCASE,  -- must equal the client setting value
    Description  TEXT,
    Active       INTEGER NOT NULL DEFAULT 1,
    Created_on   TEXT NOT NULL DEFAULT (datetime('now','localtime'))
);

-- 3. GroupRoleMap — entitlement rules (operator-authored; seeded now). A user's
--    Axonius group → a role. Match = exact (NOCASE) or '*'-suffix wildcard on Pattern.
CREATE TABLE IF NOT EXISTS GroupRoleMap (
    GRMID      INTEGER PRIMARY KEY AUTOINCREMENT,
    Pattern    TEXT NOT NULL,                 -- 'BNX-M365-E3' or 'IT-Dev*'  (trailing * = wildcard)
    Match_On   TEXT NOT NULL DEFAULT 'cn',    -- 'cn' | 'display' | 'dn' — which group field Pattern tests
    Role       TEXT NOT NULL COLLATE NOCASE,
    Priority   INTEGER NOT NULL DEFAULT 100,  -- lower evaluated first (advisory; all matches apply)
    Active     INTEGER NOT NULL DEFAULT 1,
    Notes      TEXT,
    Created_by TEXT,
    Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    Updated_on TEXT
);
CREATE INDEX IF NOT EXISTS idx_grm_active ON GroupRoleMap (Active, Role);

-- 4. RefUser — one row per distinct user in the export. Identity columns live here
--    (user-level, not entitlement-level) so username-match failures — the #1 risk
--    for goal 3 — are diagnosable. RegionID: operator-set later, reporting only.
CREATE TABLE IF NOT EXISTS RefUser (
    RefUserID    INTEGER PRIMARY KEY AUTOINCREMENT,
    UserID       TEXT NOT NULL UNIQUE COLLATE NOCASE,  -- normalised lowercased match key
    SamAccount   TEXT,                                 -- raw 'Azure Ad: AD sAMAccountName'
    Upn          TEXT,                                 -- raw 'Azure Ad: AD User Principal Name'
    Display_Name TEXT,                                 -- raw 'Aggregated: Display Name'
    Domain       TEXT,                                 -- raw 'Aggregated: Domain' (first value if multi)
    Username_Src TEXT NOT NULL,                        -- 'sam' | 'upn' | 'username' — where UserID came from
    RegionID     INTEGER REFERENCES Region(RegionID),  -- operator-set later; reporting only
    First_Seen   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    Last_Seen    TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    Last_RunID   TEXT
);

-- 5. UserRole — the reference itself. One row per (user, role, source-group):
--    a user granted one role by three groups = three rows. The publisher DISTINCTs
--    to (user, role) when building the snapshot.
CREATE TABLE IF NOT EXISTS UserRole (
    URID          INTEGER PRIMARY KEY AUTOINCREMENT,
    UserID        TEXT NOT NULL COLLATE NOCASE,        -- matches RefUser.UserID
    Role          TEXT NOT NULL COLLATE NOCASE,
    Source_Type   TEXT NOT NULL,                       -- 'AD Security Group' | 'Mailing List' | 'Azure AD Group' | 'KnowBe4' | ...
    Source_Value  TEXT NOT NULL,                       -- CN / display name that granted it, e.g. 'BNX-M365-E3'
    Source_System TEXT,                                -- adapter: 'active_directory_adapter' | 'azure_ad_adapter' | ...
    Matched_Rule  INTEGER REFERENCES GroupRoleMap(GRMID),
    Active        INTEGER NOT NULL DEFAULT 1,          -- 0 = not seen in the latest export (age-out audit; row kept)
    First_Seen    TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    Last_Seen     TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    Last_RunID    TEXT,
    UNIQUE (UserID, Role, Source_Value)
);
CREATE INDEX IF NOT EXISTS idx_userrole_role ON UserRole (Role, Active);
CREATE INDEX IF NOT EXISTS idx_userrole_user ON UserRole (UserID, Active);

-- 6. RolePublication — operator config: which (role, region) pairs are live.
--    Drives the distribution action's region relevance scope. RegionID NULL = all
--    regions. Seeded by hand for the first BU rollout; region form fills it later.
CREATE TABLE IF NOT EXISTS RolePublication (
    RPID       INTEGER PRIMARY KEY AUTOINCREMENT,
    Role       TEXT NOT NULL COLLATE NOCASE,
    RegionID   INTEGER REFERENCES Region(RegionID),   -- NULL = all regions
    Active     INTEGER NOT NULL DEFAULT 1,
    Created_by TEXT,
    Created_on TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    UNIQUE (Role, RegionID)
);

-- 7. Snapshot — record of each published snapshot (dashboard "last publish";
--    endpoint freshness gate compares its local copy's date to the newest here).
CREATE TABLE IF NOT EXISTS Snapshot (
    SnapshotID INTEGER PRIMARY KEY AUTOINCREMENT,
    RunID      TEXT NOT NULL,
    Built_on   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    File_Name  TEXT NOT NULL,                          -- 'roleref-20260828.json'
    SHA1       TEXT NOT NULL,
    Size_Bytes INTEGER,
    Role_Count INTEGER,
    User_Count INTEGER,
    Status     TEXT NOT NULL DEFAULT 'built'           -- 'built' | 'published' | 'failed'
);

-- 8. SyncRun — one row per Ingest OR Publish run. Same logging style as
--    Initialize-RoleDb.ps1; feeds the D-18 JSON log and Event Log on failure.
CREATE TABLE IF NOT EXISTS SyncRun (
    RunID        TEXT PRIMARY KEY,                     -- GUID 'N'
    Type         TEXT NOT NULL,                        -- 'Ingest' | 'Publish'
    Started_on   TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    Ended_on     TEXT,
    Status       TEXT NOT NULL DEFAULT 'running',      -- 'running' | 'success' | 'partial' | 'failed'
    Rows_In      INTEGER,                              -- export rows read (Ingest)
    Users_Seen   INTEGER,
    Roles_Seen   INTEGER,
    Entitlements INTEGER,                              -- UserRole rows touched
    Summary      TEXT,                                 -- human-readable; dashboard "View Log" text
    Error_Count  INTEGER NOT NULL DEFAULT 0
);

-- 9. Config — key/value (same idea as Phase 7 PipelineConfig). Seeded on init.
CREATE TABLE IF NOT EXISTS Config (
    Key         TEXT PRIMARY KEY,
    Value       TEXT,
    Description TEXT
);
```

**`Config` seed keys:** `AxoniousExportPath`, `MaxExportAgeDays` (`2`), `SnapshotOutputDir`
(`{DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\roleref`),
`SnapshotUrlBase` (`http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref`),
`BESRootUrl` (`https://localhost:52311`), `AKeylessTokenFile`
(`…\BES Client\EC\Cyera\.vault-token` — **reuse Cyera's identity, confirmed**),
`AKeylessSecretPath` (`/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` — **use as-is;
operator will correct if the path is wrong**), `ValidityMonths` (`6`, mirrors
`Initialize-RoleDb.ps1`), `UsernameSourcePriority` (`sam,upn,username`), `SQLDir`,
`AlertWebhook` (empty = off).

### B. Snapshot file (derived — not a table) — PER-REGION (decided 2026-08-29)

**One snapshot file per published region**, not one global file. The operator publishes
regions individually (see Loop 2). Filename carries the region:
`roleref-<region>-<date>.json` in the Custom Repository, plus a
`roleref-<region>-latest.json` pointer and a `.sha1` manifest per region.

```json
{
  "run_id": "…",
  "region": "AAG-UK",                          // exactly one; must equal a Region.GPC_Sub_Name
  "built_on": "2026-08-28T04:07:00Z",
  "validity_months": 6,
  "roles": [
    {
      "role":  "IT Operations",
      "users": ["jsmith", "adavis", "531223"]   // DISTINCT UserRole.UserID WHERE Active=1
                                                //   AND (role,region) is Active in RolePublication
    }
  ]
}
```
Region scoping is done twice, defence-in-depth: (a) the distribution action's `<Relevance>`
gates on `value of setting "GPC_Sub_Name" = "<region>"` so only that region's endpoints
prefetch the file at all; (b) the endpoint reconcile re-checks `snapshot.region` equals its
own `GPC_Sub_Name` before applying. For each role block, if the **current console user**
(`name of current user`, lowercased — decided 2026-08-29, no multi-user fan-out in v1) is in
`users`, upsert that (user, role) locally.

### C. `RoleAwareness.db` `Map` — endpoint migration

Added to the `PRAGMA table_info(Map)` block in `Initialize-RoleDb.ps1` (same mechanism as
the existing `Updated_on` / `Valid_to` migration — additive, idempotent):
```sql
ALTER TABLE Map ADD COLUMN Source_Type  TEXT;   -- '|'-joined if the user got the role from >1 group
ALTER TABLE Map ADD COLUMN Source_Value TEXT;   -- '|'-joined group list
ALTER TABLE Map ADD COLUMN Region       TEXT;   -- endpoint's own GPC_Sub_Name at assign time
ALTER TABLE Map ADD COLUMN Assigned_By  TEXT;   -- 'AxoniousSync' | 'AdminCSV' | 'Logon'
```
No change to `UNIQUE(UserID, Role)`, `Active`, `Locked_by_Override`, `Valid_to`, or the D-12
upsert. `Reconcile-LocalRoles.ps1` writes `Assigned_By='AxoniousSync'`, stamps `Region` from
`value of setting "GPC_Sub_Name"`, and does `INSERT OR IGNORE INTO Roles (Role)` for any
snapshot role missing locally (new roles propagate without an init redeploy).

### Loop 2 — Publish (root server, scheduled daily, after ingest)
`scripts/Publish-RoleSnapshot.ps1` — turns the reference DB into a distributable snapshot.

**Decided: snapshot-in-Custom-Repository is the primary (only) approach.** The real Axonius
export is enormous (383 MB CSV) and the target BU alone is ~10,000 endpoints / potentially
10k users, with "General Access" (effectively everyone) being a role a rule could include —
per-role base64 action payloads do not scale to that. Instead:

1. Write a compact snapshot from `RoleReference.db` — **one file per published region**,
   `roleref-<region>-<date>.json`, containing `{ region, roles:[ {role, users:[...]} ] }`,
   plus a `roleref-<region>-latest.json` pointer and a SHA1 manifest per region.
2. Place it in the BigFix Custom Repository:
   `{DataDirectory}\wwwrootbes\Uploads\CustomRepository\SoftwarePortal\roleref\` — the same
   mechanism the Dispatcher's `rewritePrefetchUrls()` already targets
   (`http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/...`).
3. **One open/policy action per published region** (decided 2026-08-29 — per-region, not one
   global action; not per role, not per ComputerID):
   - `<Target>` = broad group / all clients with `RoleAwareness.db`.
   - `<Relevance>` = RoleAwareness.db existence guard **AND a single-region gate**:
     `exists setting "GPC_Sub_Name" whose (value of it as string as lowercase =
     "<region, lowercased>") of client`. This is how that region's endpoints get targeted
     **without any ComputerID** — by the endpoint's own region client setting. The region
     comes from the operator form (a picker over the fixed `Region` seed list — see Region
     tab below); the operator publishes one region at a time.
   - Optional freshness gate so the action reapplies ~daily even where nobody logs off
     (relevance compares a stamped "last snapshot date" client setting / file mtime to now;
     24 h tolerance is generous).
   - ActionScript: `prefetch` the current `roleref-<region>-latest.json` (SHA1 from the
     manifest) to `EC\SoftwarePortal\roleref\`, then run the reconcile script.

Per-role SingleActions and the user→computer matrix are **removed entirely** from the role
pipeline. Multiple regions live = multiple concurrent per-region policy actions.

### Loop 3 — Reconcile (endpoint)
`EC\SoftwarePortal\Reconcile-LocalRoles.ps1` (new; the old `Assign-RoleMapping.ps1` stays
only for the dashboard's manual-override path). Runs from the Loop 2 policy action **and**
is added to the existing `RoleDB_Maintenance` logon task so a fresh login reconciles
immediately without waiting for the next policy pass.
1. Detect the current console user via BigFix client relevance `name of current user`
   (lowercased) — this is the match key the ingest normalises to (lowercased
   `sAMAccountName`). **RESOLVED 2026-08-29:** the operator confirms these align, so the old
   `explorer.exe`→`GetOwner()` approach and its "#1 risk" caveat are dropped.
   **Multi-user hosts (decided 2026-08-29): v1 reconciles the console user only** — no
   `names of logged on users` fan-out. A shared host gets roles for whoever is at the
   console when the action/logon-task runs; per-session reconcile is deferred.
2. Read `EC\SoftwarePortal\roleref\roleref-<region>-latest.json` (the region file prefetched
   by this endpoint's region-scoped policy action). Re-check `snapshot.region` equals
   `value of setting "GPC_Sub_Name"` and abort if not.
3. If the console user is found in the snapshot: for each of their roles, D-12 upsert into
   local `RoleAwareness.db` `Map` — `INSERT OR IGNORE` + `UPDATE ... Valid_to = now + N
   months WHERE UserID=@u AND Role=@r AND Locked_by_Override = 0`. Also write `Source_Type`,
   `Source_Value`, `Region`, `Assigned_By='AxoniousSync'` (new `Map` columns — migration).
   Also ensure the role exists in `Roles` (`INSERT OR IGNORE`).
4. **Revoke: DECIDED — none.** No deactivation logic. Rows age out naturally via `Valid_to`
   (the snapshot only ever renews rows for users still entitled; a user who loses a group
   simply stops being renewed and expires after the validity window). `EnableRevoke` flag
   not implemented in v1.

**`RoleAwareness.db` `Map` migration (endpoint, migration-safe like existing v2/v3):**
add `Source_Type TEXT`, `Source_Value TEXT`, `Region TEXT`, `Assigned_By TEXT`.
`Initialize-RoleDb.ps1` gains the `PRAGMA table_info(Map)` guarded `ALTER TABLE` block.

### `fixlet_role_assigner.ojo` after the change
- CSV upload/preview/deploy path is **demoted to a manual override / break-glass tool**
  (kept working, no longer the primary path). Its per-ComputerID targeting is fine for a
  one-off manual assignment.
- Analysis view gains `Source` and `Region` columns (read from the migrated `Map` via a
  new/expanded `Dereso SWD.bes` property).
- Optional new read-only tab: "Reference DB" viewer (last ingest time, per-role user counts,
  per-region breakdown) fed by a new Analysis property or REST query.

---

## What is preserved (no change)
- `RoleAwareness.db` remains the per-endpoint source of truth that all downstream role
  relevance reads (`fixlet_modifier.ojo`, `fixlet_console.ojo`, SSA `_dashboard.html`).
- D-12 upsert discipline (`INSERT OR IGNORE` + conditional `UPDATE`, never `INSERT OR
  REPLACE`), `Locked_by_Override=0` guard, `Valid_to` renewal semantics.
- CLM-safe SQLite (`sqlite3.exe` + `Sqlite-Helper.ps1`, zero `Add-Type`).
- `RoleDB_Maintenance` logon task — extended, not replaced, to also run reconcile.
- BigFix ActionScript `{` → `{{` escaping convention (memory
  `bigfix-actionscript-curly-brace-escaping`).

---

## Resolved decisions

| Topic | Decision |
|---|---|
| Process (2026-08-29) | **Rewrite Phase 7 in place.** Phase 7's role-pipeline plans (`07-00`, `07-01`) + the role sections of `07-CONTEXT.md` are replaced by this design; `07-02`/`07-03`/`07-04` (content sync, dashboard, rollout) stay. Phase 7 remains one "End-to-End Automation" phase. |
| Snapshot scope (2026-08-29) | **Per-region.** One `roleref-<region>-*.json` file + one region-scoped policy action per published region; operator publishes regions one at a time. Not one global self-filtering snapshot. |
| Region form (2026-08-29) | **New tab in `fixlet_role_assigner.ojo`** (not a separate dashboard). Picker over the fixed 13-value `Region` seed list; drives which region is published. |
| Multi-user hosts (2026-08-29) | **v1 = current console user only** (`name of current user`). No `names of logged on users` fan-out; per-session reconcile deferred. |
| Scale | 40k endpoints global, ~10k in target BU, up to ~10k users; most users "General Access". → snapshot-in-repo distribution, never per-role action payloads. |
| Region | **Operator-provided** via a form dropdown; values match endpoint client setting **`GPC_Sub_Name`**. Scopes the distribution action's relevance now; reserved for reporting / targeting later. |
| Region values (2026-08-29) | Fixed seed list, 13 distinct: `UAP, MOT, APAC, APAC-MOT, APAC-M&A, AAG-DE, AAG-FR, AAG-UK, AAG-ES, AAG-BLX, AAG-PL, AAG-PT, GPC`. No fleet sweep. |
| Username match (2026-08-29) | Lowercased `sAMAccountName` (ingest) ↔ `name of current user` lowercased (endpoint client relevance). Confirmed aligned — **#1 risk closed**, no `explorer.exe`/`GetOwner()`. |
| Full export (2026-08-29) | Provided: `SampleAxonious/axonius-users_anond.csv` (~401 MB, anonymised) + `axonious.db`. |
| Revoke | **Age-out only.** No deactivation logic in v1. |
| Credential | **AKeyless universal identity** (`G:\Gits\Cyera` pattern) — no plaintext, no DPAPI file. **Reuse Cyera's `.vault-token` identity** (confirmed 2026-08-29). Secret path `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` — use as-is, operator corrects if wrong. |
| MCP | BigFix MCP unavailable 2026-08-28 session; operator will restart the session to test it once this doc is updated. Live inspection (task 787, region client-setting verification) deferred to then. |

## Axonius export — findings

Now working against the **full anonymised export** (`SampleAxonious/axonius-users_anond.csv`,
~401 MB; `axonious.db` = same as SQLite). Header = 47 columns, BOM-prefixed, RFC-4180
quoted. Sample findings below (from the earlier top-10) all still hold on the full file:

- **One row per user.** Single table `axonious_susers`, ~46–47 TEXT columns.
- **Several columns are multi-valued** — one cell holds a newline-delimited list
  (`Aggregated: Assigned Groups: Name` / `Display Name` / `Group Type` / `Email`, and even
  `Aggregated: User Name` / `Mail` / `Domain`). Sub-lists across the `Assigned Groups: *`
  columns are only *loosely* aligned (blank slots where an adapter fills `Display Name` but
  not `Name`). Parser must be defensive, not index-zip.
- **Group values are LDAP DNs or display names**
  (`CN=BNX-M365-E3,OU=Service Groups,...,DC=office,DC=bzn`, `All Tenant Members`).
  → `GroupRoleMap` matches on the extracted `CN=` token or the display name, `*`-suffix
  wildcard, case-insensitive.
- **Username**: `Azure Ad: AD sAMAccountName` only ~70% populated in the sample; UPN and
  `Aggregated: User Name` 100%. Ingest coalesce: `sAMAccountName` → local-part of UPN →
  `User Name`, then `.ToLower()`. **RESOLVED 2026-08-29** — endpoint side uses client
  relevance `name of current user` lowercased, which the operator confirms equals the
  lowercased SAM; no `GetOwner()` parsing. Rows where SAM is blank and the coalesce falls
  back to UPN-localpart / User Name are the residual mismatch surface — keep
  `Username_Src` on `RefUser` so those are reportable, and spot-check a sample once MCP
  is back.
- **Source system** in `Aggregated: Adapter Connections` / `Assigned Groups: Adapter Source
  Application` (`azure_ad_adapter`, `active_directory_adapter`, `knowbe4_adapter`,
  `jamf_adapter`, `service_now_adapter`, `code42_adapter`). `Assigned Groups: Group Type`
  + presence of `Assigned Groups: Email` distinguish security group vs. mailing list →
  `Source_Type`.
- Full export **~383 MB CSV** → stream it; build `RoleReference.db` incrementally.

## Credential design — AKeyless universal identity

Pattern from `G:\Gits\Cyera\0_Retrieve_AKeylessVal.ps1`:
`.vault-token` file (rotated ~2-hourly by a scheduled task) → `POST api.akeyless.io/auth`
`{access-type:'universal_identity', uid-token:<file>}` → `.token` → `POST
api.akeyless.io/get-secret-value` `{names:['<path>'], token:<.token>}` → secret.

This phase: store the BigFix root-server **operator service account** as an AKeyless secret
at `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` (use as-is; operator will correct
the path if wrong). `scripts/Get-BigFixCredential.ps1` wraps auth + fetch, returns a
`PSCredential`; every root-server script calls it at runtime. **Decided 2026-08-29:**
RoleSync **reuses Cyera's existing universal identity** — the same token file at
`...\BES Client\EC\Cyera\.vault-token`. No new identity provisioned.

## Remaining smaller questions

3. **`GroupRoleMap` rules — the actual content.** The matcher is designed (exact + `*`-suffix
   NOCASE on `cn`/`display`/`dn`, priority-ordered); the authoring UI reuses the Phase 7
   D-17 Config-tab concept. **Still open: which CN / display-name patterns map to which
   role.** Needs the operator to supply the first rule set (or a starter derived from the
   real export's group frequency). This is the one gate on a live ingest run.

**Closed 2026-08-29:** full CSV (was Q: sample); username match key (was Q: validate
against endpoint logon names); AKeyless secret path + identity reuse; region value list;
region form location (→ tab in `fixlet_role_assigner.ojo`); snapshot scope (→ per-region);
multi-user hosts (→ console user only in v1).

---

## Phase 7 rewrite — plan map

Phase 7 stays "End-to-End Automation". The **role** plans are rewritten to this design;
the **content** plans are untouched.

| Phase 7 plan | Action | Deliverables |
|---|---|---|
| `07-00` Foundation | **Rewrite** | `RoleReference.db` schema init script; `Get-BigFixCredential.ps1` (AKeyless, reuses Cyera identity); `GroupRoleMap` seed/config table; endpoint `Map` migration (`Source_Type`/`Source_Value`/`Region`/`Assigned_By`) folded into `Initialize-RoleDb.ps1`; `Region` seed (13 values); test fixtures from `SampleAxonious`. Replaces `Initialize-AutomationDb.ps1` / `AutomationState.db` for the role side. |
| `07-01` Role pipeline | **Rewrite** | `Import-AxoniousExport.ps1` (streaming CSV → `RoleReference.db`, DN/username coalesce, GroupRoleMap resolve, `Source_Type` derivation, age-out marking); `Publish-RoleSnapshot.ps1` (per-region `roleref-<region>-*.json` → Custom Repository + SHA1 manifest); per-region policy fixlet (`.bes`) with single-region `GPC_Sub_Name` relevance + prefetch; `Reconcile-LocalRoles.ps1` (endpoint, console-user-only, D-12 upsert, wired into `RoleDB_Maintenance`); `SyncRun` logging; scheduled-task XML; unit tests. Replaces `Parse-AxoniousExport.ps1` / `Get-UserComputerMap.ps1` / `Invoke-RoleSync.ps1`. |
| `07-02` Content pipeline | **Keep as-is** | `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`, scheduled tasks. |
| `07-03` Automation Dashboard | **Amend** | `fixlet_automation_monitor.ojo` role tab reads `RoleReference.db` (last ingest, per-role/per-region counts) instead of the old user→computer matrix. Region-publish tab added to `fixlet_role_assigner.ojo` (per this design), CSV path demoted to break-glass. `Dereso SWD.bes` Analysis gains Source/Region columns. |
| `07-04` Integration + Rollout | **Amend** | `-WhatIf` dry-run for the new scripts; SAM ↔ `name of current user` spot-check on live endpoints; per-region phased enablement; admin run-book; full regression gate. |

**Blocked on:** `GroupRoleMap` rule content (remaining question 3) — needed before a live
ingest, not before writing and testing the scripts against fixtures.

## Environment note
- BigFix MCP server (`bigfix`) **back online 2026-08-29** — `getSession` OK
  (Operator `Administrator`, master operator, `swd`/`query`/`custom` apps). 2026-08-28
  `CONNECT_TIMEOUT` cleared.
- **The MCP-connected server is a 9-computer lab, not production `gpbfs` (40k).** So:
  - `GPC_Sub_Name` value verification **cannot be done from here** — wrong fleet, and client
    settings aren't exposed to session relevance (`settings ... of bes computers` →
    "operator not defined") without a retrieved property / Analysis. Defer to production, or
    add a `GPC_Sub_Name` Analysis property first. The 13-value seed list stands as given.
  - SAM ↔ `name of current user` spot-check likewise needs the production fleet.
- **Task 787 fetched 2026-08-29** (`custom/Dereso Software Portal`, id 787). Confirms memory
  `role-awareness-logon-rework-status`: the **live** Action1 (v2, CLM-safe sqlite3.exe) still
  (a) wraps the whole init + `Initialize-RoleDb.ps1` run in `if {not exists file (parameter
  "TargetStore")}` — the file-exists gate the local repo already removed; (b) detects the
  user via `Get-CimInstance explorer.exe → GetOwner → .Split('\')[-1].ToLower()` (bare
  lowercased SAM) + `INSERT OR REPLACE INTO Users`; (c) registers `RoleDB_Maintenance`
  (AtLogOn / SYSTEM) that reruns `Initialize-RoleDb.ps1`; (d) seeds roles `IT Operations`,
  `Business Operations`, `Business Default`. Action2 is the frozen Add-Type `_orig`.
  → This design's switch of endpoint user-detection from `explorer.exe/GetOwner` to client
  relevance `name of current user` is a real behavioural change from what's published;
  operator has confirmed the two values are equal (bare lowercased SAM).
- Local BigFix skills: `G:\Gits\bigfix_skills\skills\` — `jf-bigfix-mcp`,
  `jf-bigfix-dashboards`, `jf-bigfix-session-relevance`, `jf-bigfix-client-relevance`,
  `jf-bigfix-actionscript`, `jf-bigfix-parameterized-fixlets`, `jf-bigfix-webreports`,
  `jf-bigfix-api-powershell`, `jf-bigfix-log-analysis`.
- Working tree has uncommitted logon-rework changes (memory
  `role-awareness-logon-rework-status`) — commit before large new edits to avoid loss.
