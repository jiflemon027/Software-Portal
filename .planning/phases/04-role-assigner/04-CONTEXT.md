# Phase 4: Role Assigner Dashboard - Context

**Gathered:** 2026-06-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 delivers two artefacts:
1. **`fixlet_role_assigner.ojo`** — BigFix dashboard for importing role-to-user mappings via CSV and viewing current assignment state.
2. **Finalised `Dereso SWD.bes`** — production-ready BigFix Analysis that reads `RoleAwareness.db` properties from reporting clients.

The dashboard allows a BigFix admin to:
- Upload a CSV of (user, Computer_ID, role) assignments
- Preview and validate the CSV
- Deploy one BigFix action per role (add type), each updating the target clients' `RoleAwareness.db`
- View current mappings (read-only) from the Analysis

Out of scope for Phase 4: revoke UI, override management, DB initialisation deployment, automated scheduling.

</domain>

<decisions>
## Implementation Decisions

### Write-back Mechanism
- **D-01:** One `API.Post("actions")` call per unique role in the CSV — no Multi-Action-Group. For a CSV covering 3 roles, 3 add actions are created. Remove actions are a separate (Phase 5) UI flow.
- **D-02:** Each action targets an explicit computer ID list (all Computer_IDs for that role from the CSV). Client-side relevance also guards: action only runs if `RoleAwareness.db` exists on the client (double guard).
- **D-03:** Matrix encoding: JSON object `{ "computers": [id1, id2, ...], "users": ["user1", "user2", ...] }` where index `i` represents one (computer, user) pair. Parallel arrays — NOT nested objects.
- **D-04:** Matrix is Base64-compressed and chunked into ~3000-char segments stored as ActionScript parameters: `parameter "chunk0"`, `chunk1`, `chunk2`... Client PowerShell concatenates chunks then decodes B64 to recover the JSON.
- **D-05:** Client identifies itself using `parameter "CompID"="{id of computer}"` (BigFix server-side relevance substitution per target). PowerShell finds all indices where `computers[i] == CompID` and processes those users.
- **D-06:** Action 1 (add) uses the D-12 upsert pattern from `Initialize-RoleDb.ps1`: `INSERT OR IGNORE` then conditional `UPDATE` to reactivate the row if `Active=0`. Rows where `Locked_by_Override=1` are skipped entirely.
- **D-07:** Action 2 (remove — generated from Analysis-driven UI in Phase 5): soft delete — set `Active=0` AND `Valid_to=datetime('now','localtime')`. Rows where `Locked_by_Override=1` are skipped.
- **D-08:** Each action's ActionScript follows the structure of `Dashboard_4_samples/Init Current User and UserRole DB.bes`: prefetch SQLite DLLs + tools from the BigFix custom repo, set directory parameters (`RootDir`, `ECDir`, `SWPDir`, `TargetStore`, `SQLiteDir`), create dirs if absent, write the PowerShell script via `createfile…_EOF_`, then `waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass`.
- **D-09:** Action naming convention: `Dereso_[Role] Assign_[suffix]` for add actions. Suffix = region/geo text entered by admin in the UI; defaults to the selected group name if left blank. (Remove actions in Phase 5 use `Dereso_[Role] Revoke_[suffix]`.)

### Assignment Model
- **D-10:** The `computer` column in the CSV is renamed `Computer_ID` and holds the BigFix computer ID. It determines which client runs the action AND which client's Map table is updated — role scope is per-client, not user-global. Each client's Map table records only the users assigned to roles on that machine.
- **D-11:** A single CSV import drives only ADD operations. The remove workflow (Phase 5) uses the Analysis `mapped_users in r.db` property to let the admin select mappings to revoke — a separate UI path.
- **D-12:** Group selector follows the Dispatcher pattern: dropdown populated from `PORTAL_CONFIG.targetGroups`. Selection is informational/context (contributes to action title suffix default); it does not hard-filter the computer ID list.

### Admin UI Pattern
- **D-13:** Single-page vertical flow: group selector → region/suffix text input → CSV file upload → parsed preview table → Deploy button.
- **D-14:** Preview table columns: User | Computer_ID | Role. Row count shown. Validation errors highlighted inline. Deploy button disabled until all blocking errors are resolved.
- **D-15:** CSV validation rules:
  - **Block (deploy disabled):** unknown role (not in `PORTAL_CONFIG.roles`), blank User, blank Computer_ID.
  - **Warn (deploy allowed, row flagged):** duplicate (User, Computer_ID, Role) rows.
- **D-16:** Post-deploy feedback: success banner per action showing the action ID returned by `API.Post("actions")` — same UX pattern as the Dispatcher dashboard.
- **D-17:** Read-only Analysis view: table below the deploy section, columns Computer Name | User | Role. Populated from the `mapped_users in r.db` Analysis property via `GetRelevance`. One row per active mapping per reporting computer. Initialisation indicator: if a Computer_ID from the CSV is absent from the Analysis results, flag it as "DB not initialised" (warn only — no deploy action taken).
- **D-18:** Revoke UI: read-only in Phase 4 (shows current mappings; no action generated). Full revoke UI deferred to Phase 5.

### PORTAL_CONFIG
- **D-19:** PORTAL_CONFIG structure (same pattern as Modifier and Dispatcher):
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
          // update this list when management changes the role definitions
      ],
      actionNamePrefix: 'Dereso'
  };
  ```
  Role list is the single place to update when management changes role definitions.

### Phase 4 Scope
- **D-20:** Deliverables: `Existing Dashboards/fixlet_role_assigner.ojo` + finalised `Dashboard_4_samples/Dereso SWD.bes` Analysis.
- **D-21:** DB initialisation: the dashboard checks whether target computers have an initialised DB (via Analysis) and shows a warning if not. It does NOT deploy `Initialize-RoleDb.ps1` — that remains a separate admin prerequisite (`Init Current User and UserRole DB.bes`).
- **D-22:** Override management: the Overrides table schema exists in the DB but is out of scope for Phase 4. No override UI, no override MIME fields, no Analysis property for overrides surfaced.
- **D-23:** The `Init Current User and UserRole DB.bes` task is a prerequisite that admins deploy separately, not a Phase 4 deliverable.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Prototype Artefacts (primary references)
- `Dashboard_4_samples/Initialize-RoleDb.ps1` — DB schema (Roles, Users, Map, Overrides tables), upsert pattern (D-12), migration logic, error codes 5100–5400. MUST read before writing any PowerShell that touches `RoleAwareness.db`.
- `Dashboard_4_samples/Init  Current User and UserRole DB.bes` — Reference ActionScript pattern: prefetch, directory setup, `createfile…_EOF_` PowerShell embedding, `waithidden powershell.exe` invocation. MUST use this structure for all generated actions.
- `Dashboard_4_samples/Dereso SWD.bes` — BigFix Analysis prototype; four properties: `Roles in r.db`, `users in r.db`, `mapped_users in r.db`, `recent users`. Phase 4 finalises this file.
- `Dashboard_4_samples/role_targeting.csv` — CSV format prototype: columns `user`, `Computer_ID`, `role`. Phase 4 renames `computer` → `Computer_ID`.
- `Dashboard_4_samples/gpbfs_analysis_results.txt` — Sample Analysis output for computer GPBFS. Shows the actual format of Analysis property values returned by `GetRelevance`.

### Existing Dashboard Patterns (code analogs)
- `Existing Dashboards/fixlet_dispatcher.ojo` — `PORTAL_CONFIG` pattern, `API.Post("actions")` call, group selector from config, success banner with action ID. Role Assigner follows these patterns directly.
- `Existing Dashboards/fixlet_modifier.ojo` — `PORTAL_CONFIG` pattern, role list definition. Role list sync between Modifier and Role Assigner is required (D-19).

### External References
- BigFix MAG REST API: https://forum.bigfix.com/t/solved-multiple-action-group-creation-via-rest-api/16255 — captured for context; Phase 4 uses individual `API.Post("actions")` per role instead (D-01).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PORTAL_CONFIG` pattern: used in both Modifier and Dispatcher. Role Assigner adds `roles[]` and `actionNamePrefix` fields to the same structure.
- `API.Post("actions")` + action ID banner: proven in Dispatcher. Role Assigner reuses same call and UX pattern.
- Group selector dropdown: populated from `PORTAL_CONFIG.targetGroups` in Dispatcher — replicate exactly.
- `API.GetRelevance()`: used throughout existing ojos. Role Assigner uses it to read Analysis properties (`mapped_users in r.db`, `Roles in r.db`).

### Established Patterns
- ActionScript directory parameters (`RootDir`, `ECDir`, `SWPDir`, `TargetStore`, `SQLiteDir`) — defined in `Init Current User and UserRole DB.bes` and must be reproduced verbatim in generated actions.
- BigFix prefetch block for SQLite tools (`unzip.exe`, `sqlite-tools-win-x64-3530100.zip`, `SQLite_dlls.zip`) from the custom repo at `/Uploads/CustomRepository/sqlite_util/` — same URLs and SHA hashes as in the Init BES task.
- `waithidden powershell.exe -NonInteractive -NoProfile -ExecutionPolicy Bypass -File "{param}" -DatabasePath "{param}" -SQLDir "{param}"` — established invocation pattern.
- `createfile until _EOF_ … _EOF_` with `move __createfile` — embedded script delivery pattern.

### Integration Points
- **Analysis dependency:** `Dereso SWD.bes` must be imported and reporting in the BigFix console before the Role Assigner's read-only view works. Phase 4 finalises and delivers this Analysis.
- **Modifier role list sync:** `PORTAL_CONFIG.roles` in Role Assigner must match the role list in `fixlet_modifier.ojo`. Planner should note this dependency.
- **Init BES task prerequisite:** `RoleAwareness.db` must exist on target clients (deployed via `Init Current User and UserRole DB.bes`) before Role Assigner actions will run.

</code_context>

<specifics>
## Specific Ideas

- **Sample data:** `Dashboard_4_samples/RoleAwareness_from GPBFS.db` is a real DB from computer GPBFS — useful as a test fixture.
- **Analysis property format:** `mapped_users in r.db` returns `"UserID, Role"` strings (comma+space separated). The BES file uses tuple string parsing (`following text of first "%22"`). Dashboard JS will need to parse this format from `GetRelevance` results.
- **B64 chunk size:** ~3000 chars per chunk (below the ~4000 BigFix agent parameter limit, with headroom). Planner should note this constant.
- **Role list evolution:** Current defaults in `Initialize-RoleDb.ps1` are `IT Developer, IT Support, DB Developer, DB Administrator, Payments Processor, Marketer`. These will collapse to `IT Operations, Finance, HR` (management decision, not finalised). `PORTAL_CONFIG.roles` is the single source of truth — DB default seeding in the Init script is separate and does not need to match exactly.
- **Action type for add/remove:** Both add and remove actions use the same BigFix `SingleAction` type (same as Dispatcher). The distinction is in the PowerShell logic embedded in each action.

</specifics>

<deferred>
## Deferred Ideas

- **Revoke UI** — Admin selects mappings from Analysis view and fires `Dereso_[Role] Revoke_[suffix]` actions. Deferred to Phase 5.
- **Override management** — Creating/viewing/expiring Overrides table entries. Deferred to Phase 5.
- **DB init deployment from dashboard** — One-click "Initialise DB on selected computers" button. Deferred to Phase 5.
- **Group overlap indicator (non-required)** — Visual indicator showing whether all CSV Computer_IDs are members of the selected group. Noted as a nice-to-have; not required in Phase 4.
- **Multi-Action-Group** — MAG approach (referenced BigFix forum post) was considered and rejected for Phase 4 in favour of simpler per-action API calls. Revisit if role count grows significantly.

</deferred>

---

*Phase: 4-role-assigner*
*Context gathered: 2026-06-27*
