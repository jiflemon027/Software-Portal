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
- SQLite tools and DLL packages are fetched automatically during the init task via BigFix
  prefetch (unzip.exe, sqlite-tools-win-x64, SQLite_dlls.zip). Endpoints need access to
  the BigFix relay or server for these downloads

---

## Step 1 — Deploy the Initialisation Task

Import `Dashboard_4_samples/Init  Current User and UserRole DB.bes` into your BigFix instance
and deploy it to the target endpoints.

**What the task does:**

1. Downloads and installs the SQLite CLI and .NET assembly into `EC\sqlite\`
2. Creates `EC\SoftwarePortal\RoleAwareness.db` with four tables:

   | Table | Purpose |
   |-------|---------|
   | `Roles` | Lookup of valid role names (seeded with defaults on first run) |
   | `Users` | Registry of known users with `LastSeen` timestamp |
   | `Map` | Active role assignments (`UserID`, `Role`, `Active`, `Valid_to`) |
   | `Overrides` | Time-limited manual overrides written by the Modifier dashboard |

3. Seeds `Roles` with the default set if the table is empty
4. Detects and records the currently logged-on user (via `Win32_Process explorer.exe → GetOwner`)
5. **Registers the `Dereso\UpdateUserOnLogon` scheduled task** (see below)

The task is safe to re-run: `CREATE TABLE IF NOT EXISTS` skips tables that already exist, and
the scheduled task is re-registered with `/F` (overwrite), keeping its definition current if
the init task is redeployed to update paths after a BigFix client reinstall.

### Init Task Relevance

The task fires when:
- The DB does not yet exist on the endpoint, **or**
- A user is logged on whose `UserID` is not in the `Users` table with a `LastSeen` within the
  last 24 hours

This keeps the task relevant for new-user events without polling every checkin.

---

## Step 2 — How the Logon Scheduled Task Works (FR-08)

During each init task execution, a Windows Scheduled Task named `Dereso\UpdateUserOnLogon`
is registered on the endpoint. This task keeps `Users.LastSeen` current automatically
without requiring admin action.

| Property | Value |
|----------|-------|
| Task path | `\Dereso\UpdateUserOnLogon` |
| Trigger | At logon (any user) |
| Delay | 1 minute (allows user session and explorer.exe to fully start) |
| Runs as | SYSTEM (required for write access to `EC\SoftwarePortal\RoleAwareness.db`) |
| Script | `EC\SoftwarePortal\Update-UserOnLogon.ps1` |
| Max runtime | 5 minutes |
| Multiple instances | IgnoreNew (prevents parallel runs if logons overlap) |

**User detection method:** The task uses the same technique as the init script —
`Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe"` piped through
`Invoke-CimMethod -MethodName GetOwner`. This returns the SAM account name without a domain
prefix (e.g., `jsmith`), which is the format stored in the `Users` table by all other
components.

**What the task writes per logon:**

```sql
-- First logon: create the record
INSERT OR IGNORE INTO Users (UserID, LastSeen)
VALUES (@uid, datetime('now','localtime'));

-- Every logon: refresh LastSeen
UPDATE Users SET LastSeen = datetime('now','localtime')
WHERE UserID = @uid;
```

The poll loop retries every 5 seconds for up to 60 seconds, handling cases where the task
fires before `explorer.exe` is visible (fast logons, RDP reconnects).

**Verifying the task was registered:**

On any endpoint that has run the init task, open Task Scheduler and navigate to
`Task Scheduler Library → Dereso`. The `UpdateUserOnLogon` task should appear with
status `Ready`.

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
| `user` | SAM account name | Must match the format stored by `Update-UserOnLogon.ps1` (no domain prefix) |
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
| Scheduled task missing from endpoint | Init task has not run, or ran before Phase 5 update | Re-deploy the init task — it will create `Update-UserOnLogon.ps1` and register the task |
| Users.LastSeen not updating | Explorer.exe not detected within 60-second poll window | Check that the user has an interactive desktop session (not service-only login) |

---

## File Reference

| File | Purpose |
|------|---------|
| `Dashboard_4_samples/Init  Current User and UserRole DB.bes` | Init task — deploy first to all target endpoints |
| `Dashboard_4_samples/Dereso SWD.bes` | Analysis — import into BigFix after init |
| `Existing Dashboards/fixlet_role_assigner.ojo` | Role Assigner dashboard |
| `EC\SoftwarePortal\RoleAwareness.db` | Per-endpoint SQLite database (created by init task) |
| `EC\SoftwarePortal\Update-UserOnLogon.ps1` | Logon script (created by init task, run by scheduled task) |
| `EC\SoftwarePortal\Assign-RoleMapping.ps1` | Role assignment script (created by Role Assigner action) |
