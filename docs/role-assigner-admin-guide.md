# Dereso Role Assigner — Admin Guide

## Overview

The Role Assigner system lets BigFix administrators maintain a per-endpoint database
(`RoleAwareness.db`) that records which users are assigned to which roles on each managed
device. This database drives role-based relevance: fixlets modified by the Dereso Modifier
dashboard check this database at evaluation time, so only users in the correct role see
offers for the software assigned to that role.

The system has three components, deployed in order:

| Component | File | Purpose |
|-----------|------|---------|
| Init Task | `Dashboard_4_samples/Init  Current User and UserRole DB.bes` | Creates the DB schema on each endpoint; registers the logon scheduled task |
| Analysis | `Dashboard_4_samples/Dereso SWD.bes` | BigFix Analysis that reads DB state back to the server for reporting |
| Role Assigner Dashboard | `Existing Dashboards/fixlet_role_assigner.ojo` | Admin UI for CSV-based role assignment; surfaces Analysis data |

---

## Prerequisites

- BigFix admin credentials with authoring rights
- The `EC\SoftwarePortal` directory path is derived automatically from the BigFix client
  installation folder — no manual path configuration is required
- The SQLite CLI (`sqlite3.exe`) is fetched automatically during the init task via BigFix
  prefetch (unzip.exe, sqlite-tools-win-x64). Endpoints need access to the BigFix relay or
  server for this download
- All database access is CLM-safe: `sqlite3.exe` via `Sqlite-Helper.ps1`, zero `Add-Type` /
  `System.Data.SQLite.dll` usage. Endpoints running PowerShell Constrained Language Mode
  (locked-down/secured systems) are fully supported — this was the reason the DLL-based
  approach was retired

---

## Step 1 — Deploy the Initialisation Task

Import `Dashboard_4_samples/Init  Current User and UserRole DB.bes` into your BigFix instance
and deploy it to the target endpoints.

**What the task does, every time it runs — including on an endpoint that was already
initialised:**

1. Downloads and installs the SQLite CLI (`sqlite3.exe`) into `EC\sqlite\` (only if missing)
2. **Unconditionally** rewrites `Sqlite-Helper.ps1` and `Initialize-RoleDb.ps1` in
   `EC\SoftwarePortal\` to the versions carried by this task, then **unconditionally** runs
   `Initialize-RoleDb.ps1` against `EC\SoftwarePortal\RoleAwareness.db`:

   | Table | Purpose |
   |-------|---------|
   | `Roles` | Lookup of valid role names (seeded with defaults on first run) |
   | `Users` | Registry of known users with `LastSeen` timestamp |
   | `Map` | Active role assignments (`UserID`, `Role`, `Active`, `Valid_to`) |
   | `Overrides` | Time-limited manual overrides written by the Modifier dashboard |

3. Seeds `Roles` with the default set if the table is empty
4. Detects and records the currently logged-on user (via `Win32_Process explorer.exe → GetOwner`)
   and renews `Valid_to` on their active, non-overridden `Map` rows
5. **Registers the `RoleDB_Maintenance` scheduled task, only if it doesn't already exist**
   (see below) — gated separately from steps 1–4, and only attempted if `RoleAwareness.db`
   actually exists at that point (a defensive check, not expected to fail in practice)

**On a brand-new endpoint** this creates everything from scratch. **On an already-initialised
endpoint** (existing `RoleAwareness.db`, possibly on an older schema) re-running/redeploying
this task safely upgrades it in place: every step in `Initialize-RoleDb.ps1` is idempotent
(`CREATE TABLE IF NOT EXISTS`, `PRAGMA table_info`-gated `ALTER TABLE` for the `Updated_on`/
`Valid_to` migration, `[SKIP]`-on-already-populated role seeding), so nothing gets dropped or
re-created — existing `Map`/`Users`/`Roles` rows are preserved untouched, missing columns and
indexes get added, and the currently logged-on user's mappings get renewed. This is the
mechanism for rolling a schema change (or a script bug fix) out to endpoints that were
initialised by an older version of this task — just redeploy it.

Steps 1–4 previously only ran when `RoleAwareness.db` did not yet exist, which meant
redeploying the task to an already-initialised endpoint was a no-op and schema/script updates
never reached it. That gate was removed — the scripts and the migration-safe init now always
run. Step 5's "only if it doesn't already exist" gate is intentionally different and was kept:
the scheduled task's `-Argument` string is baked in at registration time, so blindly
re-registering it on every run would be wasted work (and would briefly disrupt a task that's
already `Ready`). If `SWPDir`/`TargetStore` ever change (e.g. after a BigFix client reinstall
to a different drive), the task must be removed manually before redeploying the init task, so
it gets registered fresh with the new paths.

### Init Task Relevance

The task's default (automatic-offering) relevance fires when:
- The DB does not yet exist on the endpoint, **or**
- A user is logged on whose `UserID` is not in the `Users` table with a `LastSeen` within the
  last 24 hours

This keeps the task relevant for new-user events without polling every checkin — but it also
means an already-initialised endpoint with a recently-seen user may show as "not relevant" for
automatic/policy-based offering even though redeploying would still safely apply a schema or
script update. To force a migration across a fleet regardless of relevance, target and deploy
the task explicitly (BigFix Console → Take Action → select computers) rather than relying on
the default applicable-computers list.

---

## Step 2 — How the Logon Scheduled Task Works (FR-08)

During each init task execution, a Windows Scheduled Task named `RoleDB_Maintenance` is
registered on the endpoint (via `Scheduled_RoleDb_mnc.ps1`, also written by the init task).
This task keeps `Users.LastSeen` current **and** keeps the logged-on user's active role
mappings from expiring, both without requiring admin action.

Unlike a dedicated lightweight logon script, `RoleDB_Maintenance` simply **reruns
`Initialize-RoleDb.ps1` itself** on every logon, with the same `-DatabasePath`/`-SQLDir`
arguments used at init time. This is safe because every step in `Initialize-RoleDb.ps1` is
idempotent (`CREATE TABLE IF NOT EXISTS`, `[SKIP]`-on-already-present-role, etc.) — a logon
rerun on an already-initialised endpoint just walks through and skips every step except the
current-user upsert and the `Valid_to` renewal, which are meant to run every time.

| Property | Value |
|----------|-------|
| Task name | `RoleDB_Maintenance` |
| Trigger | At logon (any user) |
| Runs as | SYSTEM (required for write access to `EC\SoftwarePortal\RoleAwareness.db`) |
| Script | `EC\SoftwarePortal\Initialize-RoleDb.ps1` (same file the init task itself runs) |
| Execution time limit | None (`-ExecutionTimeLimit 0`) |
| Settings | `-AllowStartIfOnBatteries -DontStopIfGoingOnBatteries` |

**User detection method:** `Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'"`
piped through `Invoke-CimMethod -MethodName GetOwner`. This returns the SAM account name
without a domain prefix (e.g., `jsmith`), which is the format stored in the `Users` table by
all other components. Unlike the CSV-deploy path, this is a single one-shot check with no
retry/poll loop — on a very fast logon where `explorer.exe` isn't visible yet, that pass is a
`[SKIP] No current user found` no-op and the next logon (or the next scheduled/admin-triggered
run) picks it up. Not usually an issue in practice, but worth knowing if `LastSeen`/`Valid_to`
seem to lag by one logon on a given machine.

**What each run writes, once a user is detected:**

```sql
-- Current-user upsert (runs every time, resets LastSeen even for an existing user)
INSERT OR REPLACE INTO Users (UserID, LastSeen)
VALUES (@uid, datetime('now','localtime'));

-- Valid_to renewal: every one of this user's active, non-overridden role mappings
UPDATE Map SET Updated_on = datetime('now','localtime'),
               Valid_to   = datetime('now','localtime','+6 months')
WHERE UserID = @uid AND Active = 1 AND Locked_by_Override = 0;
```

**Valid_to renewal:** every mapping the user currently holds gets `Valid_to` reset to
`now + ValidityMonths` (default 6, matching `PORTAL_CONFIG.validityMonths` in
`fixlet_role_assigner.ojo`) on every single logon — not only when nearing expiry. Rows with
`Locked_by_Override = 1` are always skipped: an admin override is a deliberate "stop
auto-renewing this mapping" signal, and this step must never overwrite it. Same D-12 upsert
pattern the Role Assigner dashboard's CSV-deploy path already uses (see
`Assign-RoleMapping.ps1`), just applied automatically instead of by admin action. On a
brand-new user's very first run there are no `Map` rows yet, so this is a `0`-row no-op —
nothing to renew until the Role Assigner dashboard (or `Invoke-RoleSync.ps1`) actually
assigns them a role.

To change the renewal window, edit `-ValidityMonths` in `Initialize-RoleDb.ps1` and redeploy
the init task (`RoleDB_Maintenance` does not pass `-ValidityMonths` explicitly, so it picks up
the script's new default without any scheduled-task change).

**Verifying the task was registered:**

On any endpoint that has run the init task, open Task Scheduler and navigate to
`Task Scheduler Library`. The `RoleDB_Maintenance` task should appear with status `Ready`.

---

## Step 3 — Import the Analysis

Import `Dashboard_4_samples/Dereso SWD.bes` into BigFix. This Analysis defines four
properties that the Role Assigner dashboard reads back:

| Property | Returns |
|----------|---------|
| `mapped_users in r.db` | `UserID, Role` for each active mapping |
| `Roles in r.db` | All role names in the `Roles` table |
| `users in r.db` | All `UserID` values in the `Users` table |
| `recent users` | Users seen within the last 24 hours |

After import, allow clients to check in (typically within the next scheduled gather interval).
The Role Assigner dashboard's Analysis view will remain empty until at least one client
has reported results.

---

## Step 4 — Open the Role Assigner Dashboard

Navigate to **BigFix Console → Dashboards → Dereso Role Assigner**.

On load the dashboard:
1. Shows "Ready." in the status bar
2. Queries all BigFix computer groups and populates the **Target Group** dropdown
3. Calls `GetRelevance` to populate the **Current Role Assignments** table from Analysis results

---

## Step 5 — Prepare the CSV

The Role Assigner accepts a CSV with exactly these three columns (header row required,
order-independent):

```
user,Computer_ID,role
jsmith,100001,IT Operations
bjones,100001,Finance
awhite,100002,IT Operations
```

| Column | Content | Notes |
|--------|---------|-------|
| `user` | SAM account name | Must match the format stored by `Initialize-RoleDb.ps1`'s current-user detection (no domain prefix) |
| `Computer_ID` | BigFix numeric Computer ID | Shown in BigFix Console → Computers. The deployed action targets this ID directly |
| `role` | Role name | Must exactly match an entry in `PORTAL_CONFIG.roles` |

**Validation rules applied on Preview:**

| Error type | Effect on Deploy |
|------------|-----------------|
| Blank `user` or `Computer_ID` | Blocks deploy |
| Unknown `role` (not in `PORTAL_CONFIG.roles`) | Blocks deploy |
| Blank `role` | Blocks deploy |
| Duplicate row (same user/Computer_ID/role) | Warning only — deploy proceeds; DB upsert handles it safely |

---

## Step 6 — Preview and Deploy

1. Click **Browse** or paste CSV text into the text area
2. Click **Preview** — the table shows each row with OK / WARN / ERROR status
3. Correct any errors (red rows) in the CSV and re-preview
4. Optionally type a **Region / Suffix** to distinguish this import in action names
   (e.g., `North` → action name `Dereso_IT Operations Assign_North`)
5. Click **Deploy** — the dashboard fires one BigFix action per unique role in the CSV

Each deployed action:
- Targets only the `Computer_ID` values from the CSV for that role
- Runs the `Assign-RoleMapping.ps1` script on each targeted endpoint
- Matches users from the CSV to the endpoint's own `Computer_ID` (D-05 pattern), so each
  endpoint only writes the rows that belong to it
- Creates or reactivates the user's `Map` entry with `Valid_to` set to the validity window
  (default: 1 month, configurable via `PORTAL_CONFIG.validityMonths`)

**Action naming convention:** `Dereso_[Role] Assign_[suffix]`

---

## Configuring the Dashboard

Edit only the `PORTAL_CONFIG` block near the top of `fixlet_role_assigner.ojo`. Do not
modify any code below this section.

```javascript
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
    // Must match PORTAL_CONFIG.roles in fixlet_modifier.ojo
  ],
  actionNamePrefix: 'Dereso',
  validityMonths: 1
};
```

| Key | Effect |
|-----|--------|
| `targetGroups` | Informational filter shown in the Target Group dropdown. Not used for targeting (each action targets specific Computer IDs from the CSV). |
| `roles` | Whitelist of valid role names. CSV rows with a role not in this list are blocked at Preview. Must stay in sync with `fixlet_modifier.ojo`'s `PORTAL_CONFIG.roles`. |
| `actionNamePrefix` | Prefix on all generated action names. |
| `validityMonths` | How long a role assignment is valid. Sets `Map.Valid_to = now + N months` on every insert and re-activation. Default: `1`. |

---

## Analysis View

The **Current Role Assignments** panel at the bottom of the dashboard reads live data
from the `mapped_users in r.db` Analysis property. Each row shows:

| Column | Source |
|--------|--------|
| Computer Name | BigFix computer name from Analysis |
| User | `UserID` from `Map` table (SAM account name) |
| Role | `Role` from `Map` table |

If a `Computer_ID` from the currently loaded CSV is absent from Analysis results, the row
appears in amber with "DB not initialised (D-21)" — this means the init task has not yet
run successfully on that endpoint.

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| Analysis view empty after deploy | Clients have not checked in since Analysis was imported | Wait for the next client gather interval (default: 15 minutes) |
| "DB not initialised" for a Computer_ID | Init task has not run on that endpoint | Deploy the init task to that computer and wait for completion |
| Deploy button stays disabled | CSV has at least one error row | Fix red rows in the CSV (blank fields or unknown role) and re-preview |
| No file reading in IE9 console | `input.files` is null in IE9 | Paste CSV text into the text area instead of using the Browse button |
| Scheduled task missing from endpoint | Init task has not run, or ran before the `RoleDB_Maintenance` update | Re-deploy the init task — it will create `Scheduled_RoleDb_mnc.ps1` and register the task. Note the registration is skipped once `RoleDB_Maintenance` already exists, so a path change (e.g. after a client reinstall) requires removing the task manually before redeploying |
| Users.LastSeen not updating | Explorer.exe not detected on that logon (no retry/poll loop) | Usually resolves on the next logon. Check that the user has an interactive desktop session (not service-only login) |
| A user's role mapping expired despite them logging in regularly | `Map.Locked_by_Override = 1` on that row | Expected behaviour — an override row is intentionally excluded from logon renewal. Check `Map.Locked_by_Override` for that UserID/Role before assuming a bug |

---

## File Reference

| File | Purpose |
|------|---------|
| `Dashboard_4_samples/Init  Current User and UserRole DB.bes` | Init task — deploy first to all target endpoints |
| `Dashboard_4_samples/Dereso SWD.bes` | Analysis — import into BigFix after init |
| `Existing Dashboards/fixlet_role_assigner.ojo` | Role Assigner dashboard |
| `EC\SoftwarePortal\RoleAwareness.db` | Per-endpoint SQLite database (created by init task) |
| `EC\SoftwarePortal\Sqlite-Helper.ps1` | CLM-safe sqlite3.exe wrapper (created by init task; dot-sourced by `Initialize-RoleDb.ps1`) |
| `EC\SoftwarePortal\Initialize-RoleDb.ps1` | Schema init **and** logon maintenance script — LastSeen refresh + Map.Valid_to renewal live in its "Load Current User" step, rerun on every logon by `RoleDB_Maintenance` |
| `EC\SoftwarePortal\Scheduled_RoleDb_mnc.ps1` | One-shot registrar for the `RoleDB_Maintenance` scheduled task (created and run once by the init task) |
| `EC\SoftwarePortal\Assign-RoleMapping.ps1` | Role assignment script (created by Role Assigner action) |
