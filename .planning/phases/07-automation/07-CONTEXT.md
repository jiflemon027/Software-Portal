---
phase: 07-automation
created: 2026-08-01
updated: 2026-09-21
status: ready-for-planning
supersedes: "2026-08-29 Axonius reference-DB pipeline design (all of D-01..D-26 below, plus DESIGN.md at .planning/quick/260828-fjc-role-reference-db/DESIGN.md)"
---

# Phase 7: End-to-End Automation — Context

**Gathered:** 2026-08-01
**Rewritten:** 2026-08-29 — Axonius reference-DB pipeline (role follows the user, no ComputerID)
**Rewritten again:** 2026-09-21 — Operator-Role-Group model replaces the Axonius pipeline entirely

> **This is a second rewrite-in-place.** The 2026-08-29 version modelled the role pipeline as
> *daily Axonius export → reference DB → per-region snapshot → endpoint reconcile*. That
> design is now **rejected** — it was never run against production (the 07-05 human-verify
> checkpoint never executed) and the user found it too heavy to operate. The role pipeline
> below is the **Operator-Role-Group model**: an admin maintains a flat username list per
> role in a small dashboard; the generator turns each role into one automatic Computer Group
> ("exactly one of this role's users is logged on") and one policy action that upserts
> `RoleAwareness.db`. No Axonius, no snapshot files, no per-region distribution, no
> `GroupRoleMap` pattern-matching. The **content pipeline** (unchanged since 2026-08-01) is
> untouched by this rewrite.

---

<domain>
## Phase Boundary

Phase 7 wires the Phases 1–6 tools into automated pipelines. After this rewrite it delivers:

1. **Role pipeline (Operator-Role-Group model, NEW)** — an admin edits a flat
   Role → [usernames] list in a new dashboard (`fixlet_role_manager.ojo`). Publishing a role
   (re)generates that role's automatic Computer Group ("exactly one of the role's usernames is
   currently logged on") and (re)deploys a policy action from the `Assign-RoleMapping.bes`
   template targeting that group. The action resolves the single matching user via client
   relevance and runs `Assign-RoleMapping.ps1`, which upserts `RoleAwareness.db` `Map` using
   the existing D-12 discipline. **No ComputerID matrix, no reference DB, no snapshot files,
   no region-based distribution, no Axonius.**

2. **Content pipeline** — scheduled scan of source sites → copy new/updated fixlets with
   category + role MIME transfer → pre-stage installer downloads in the Custom Repository.
   **Unchanged from the 2026-08-01 design; not in scope for this rewrite.**

3. **Root-server audit store (NEW, small)** — a SQLite table (not a full `AutomationState.db`)
   recording each role's current username list, written via a root-server-targeted action
   (reusing the existing "stage on root server" action pattern from `fixlet_dispatcher.ojo`),
   for audit/history. The Computer Group relevance is regenerated from this store on Publish.

**What is retired by this rewrite:** the entire Axonius ingest/publish/reconcile pipeline
(`Import-AxoniousExport.ps1`, `Publish-RoleSnapshot.ps1`, `Reconcile-LocalRoles.ps1`,
`bes/RoleRef-Policy-template.bes`), `fixlet_role_admin.ojo` (GroupRoleMap/Region/
Reference-DB tabs), `fixlet_role_assigner.ojo` (CSV break-glass), the `AutomationState.db`
role tables (`Role`, `Region`, `GroupRoleMap`, `RefUser`, `UserRole`, `RolePublication`,
`Snapshot`), and the 13-value `GPC_Sub_Name` Region seed as a **targeting** mechanism (Region
survives only as a read-only reporting column — see D-08). All of it moves to
`Existing Dashboards/archive/` and `scripts/archive/` rather than being deleted (nothing in
it was ever run against production).

**What's kept from the Axonius era:** `Assign-RoleMapping.ps1` / `bes/Assign-RoleMapping.bes`
(written 2026-09-11, the endpoint half of this exact model — reused as-is, plus the task-787
schema fix below), the underlying `RoleAwareness.db` schema and D-12 upsert discipline, and
the content pipeline in full.

**What stays manual:** final deployment of an offer action via the Dispatcher (unrelated to
roles).

**What runs where:** the dashboard (BigFix Console OJO) does all Computer Group / policy
action REST calls directly. The only root-server-side execution is the small audit-store
write, done via a targeted action — there is no scheduled task, no daily cron, no Windows
Scheduled Task for the role pipeline itself.

</domain>

---

<decisions>
## Implementation Decisions

### Role → User List Model

- **D-01: Custom per-role username list, not BigFix Operator accounts.** A role's members
  are a flat list of Windows usernames maintained directly in the dashboard — **not** derived
  from real BigFix Operator objects, permissions, or console-operator provisioning. Any
  username can be added regardless of whether it corresponds to a BigFix console operator.
  Matches `Assign-RoleMapping.ps1`'s `-UserName`/`-AssignedBy` params, which already take any
  username.

- **D-02: Autocomplete usernames against known users.** When adding a username to a role, the
  dashboard suggests matches from `RoleAwareness.db` `Users` (already-seen `sAMAccountName`s,
  read via Analysis/`GetRelevance`, same mechanism as the old Analysis view) to catch typos
  before they silently fail to match at runtime. Freeform entry is still allowed for users not
  yet seen on any endpoint.

- **D-03: Role list is fixed/small, edited in a config block.** Roles themselves are NOT
  dynamically added/removed from the dashboard — same pattern as today's
  `PORTAL_CONFIG.roles` array. Adding a brand-new role still means editing the dashboard's
  config block (and re-running the generator for that new role). Only the *usernames within*
  each existing role are dashboard-managed.

- **D-04: A user can hold more than one role.** No exclusivity check — a username can appear
  in multiple roles' lists simultaneously. `Assign-RoleMapping.ps1`'s existing
  `UNIQUE(UserID, Role)` schema and D-12 upsert already support multiple `Map` rows per user;
  each role's Computer Group and policy action operate independently.

### Storage & Root-Server Mechanism

- **D-05: SQLite table on the root server as the source of truth**, not a JSON file and not
  the Computer Group relevance text itself. A small dedicated table (e.g. `RoleUsers(Role,
  UserID, Added_by, Added_on)`) — much smaller than the retired `AutomationState.db`, but
  keeps the audit trail the flat-file option would lose.

- **D-06: Dashboard writes are on-demand, plus a periodic refresh job.** There is no daily
  ingest pipeline, but the design keeps a periodic (root-server scheduled task or policy
  action, planner's call on cadence) job that re-validates/re-syncs each role's Computer Group
  relevance against the current SQLite store, catching drift if a group is ever hand-edited or
  a publish is interrupted partway.

- **D-07: Root-server write mechanism — REST for BES objects, a targeted action for the SQLite
  row.** The dashboard PUTs/POSTs the Computer Group and policy-action Fixlet directly via
  `API.Put`/`API.Post` (same as every other dashboard in this repo — no new mechanism needed
  for BES objects). For the SQLite audit row, Publish also fires a small `SingleAction`
  targeted at the root server itself, reusing the existing "stage on root server" action
  pattern from `fixlet_dispatcher.ojo`'s `stageOnRootServer` checkbox/flow, which runs
  `Sqlite-Helper.ps1` locally on the root server to write the row.

### Region

- **D-08: Region survives for reporting only, not targeting.** The 13-value `GPC_Sub_Name`
  seed list and per-region gating are dropped as a targeting/distribution mechanism entirely
  (there's no more per-region snapshot to gate). The Analysis view may still show each
  role-holder's `GPC_Sub_Name` (already-existing client setting) purely for visibility — no
  new Region table, no `RolePublication`, no region picker driving what gets published.

### Computer Group / Action Generation

- **D-09: Membership relevance = "exactly one of N logged on."** Each role's automatic
  Computer Group admits a device only when exactly one of that role's usernames is currently
  a logged-on user — preserves the original design intent (avoid ambiguity on shared
  machines) and is regenerated from the full current username list on every Publish.

- **D-10: Optional per-role scope filter.** The dashboard keeps a "Target Group" selector
  (like the old CSV tool's informational group picker) that, if set, ANDs an additional
  scope condition (e.g. "member of group X") into the generated Computer Group relevance —
  defense-in-depth narrowing, not required.

- **D-11: Policy action reapplies daily.** "Reapply while relevant" with a ~24h cadence, so a
  host where the role-holder never logs off still gets (re-)mapped, matching the cadence used
  elsewhere in this project.

- **D-12: Same-role clash on a shared login is an accepted gap.** If two users who hold the
  *same* role are both logged into one shared machine at once, "exactly one of N" fails to
  admit the device and neither gets mapped there. This is intentional — erring toward doing
  nothing rather than guessing which one to map. **Different-role** users sharing a machine
  are unaffected: each role's own group evaluates independently against its own username set,
  so e.g. an IT Ops user and a Finance user both logged into the same box get both roles
  mapped correctly (each group's own "exactly one" check passes against its own list).

### Publish Flow

- **D-13: Two-step Save then explicit Publish, per role.** Saving a role's username list edits
  are staged (SQLite row upsert only); a separate **per-role** Publish button (not a single
  global button) does the Computer Group PUT + policy-action redeploy for that one role.
  Mirrors the old per-region publish flow's "review before it touches the fleet" property,
  scoped down to one role at a time so publishing one role's change never touches unrelated
  roles' live groups/actions.

### Dashboard Consolidation

- **D-14: One new dashboard replaces both old ones.** `Existing Dashboards/fixlet_role_admin.ojo`
  (GroupRoleMap/Region/Reference-DB) and `Existing Dashboards/fixlet_role_assigner.ojo` (CSV
  break-glass) are both retired. New file: **`Existing Dashboards/fixlet_role_manager.ojo`**,
  titled "Dereso Role Manager". No CSV upload path survives — the username-list editor is the
  only path now, normal or otherwise.

- **D-15: Retired files move to `archive/`, not deleted.** `Existing Dashboards/fixlet_role_admin.ojo`,
  `Existing Dashboards/fixlet_role_assigner.ojo` → `Existing Dashboards/archive/`.
  `scripts/Import-AxoniousExport.ps1`, `scripts/Publish-RoleSnapshot.ps1`,
  `scripts/Reconcile-LocalRoles.ps1` → `scripts/archive/`. `bes/RoleRef-Policy-template.bes` →
  `bes/archive/`. None of this was ever deployed to production, so archiving (not deleting) is
  purely for reference — git history is the real backstop.

- **D-16: Keep a read-only "current role assignments" Analysis view.** Same purpose as the old
  Analysis panel (reads `mapped_users` / `map_source` / `map_region` properties from
  `Dereso SWD.bes` via `GetRelevance`) — lets an admin see what actually landed in
  `RoleAwareness.db` versus what the config intends, catching mismatches/typos.

### Legacy Data & Migration

- **D-17: Legacy `Map` rows are left alone — natural age-out, no active cleanup.** Any rows
  tagged `Assigned_By='AxoniousSync'` (never actually run against production — the 07-05
  checkpoint never executed) or from the old CSV import just stop being renewed under the new
  model and lapse at `Valid_to` like any other row. No migration script, no re-tag-on-first-run
  logic.

- **D-18: Task 787 schema gap is fixed as part of this phase (hard prerequisite).**
  The live root-server "Init Current User and UserRole DB" task (787 on `gpbfs`) has not been
  redeployed with the D-18 `Map` migration (`Source_Type`/`Source_Value`/`Region`/
  `Assigned_By` columns) that `Assign-RoleMapping.ps1`'s UPDATE already writes to. Without
  this fix, every real-endpoint run fails with "no such column." Redeploy task 787 from the
  current `Dashboard_4_samples/Initialize-RoleDb.ps1` (already contains the
  `PRAGMA table_info`-gated migration) as part of this phase, before any dashboard/generator
  work is verified end-to-end.

### Claude's Discretion

- Exact SQLite schema for the root-server `RoleUsers` audit table (column names beyond
  `Role`/`UserID`, indexing).
- Cadence and implementation mechanism for the D-06 periodic drift-check job (scheduled task
  vs. a lightweight policy action re-run).
- Whether the D-07 root-server SQLite write action is folded into the same `SingleAction` as
  the Computer Group publish, or dispatched separately.
- Exact wave/plan subdivision for 07-00 (unless a full `--gaps` replan restructures the whole
  6-plan shape — planner's call whether the existing 07-00..07-05 numbering is reused or
  re-cut).

</decisions>

---

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The model this phase now implements
- `.planning/todos/pending/260909-rework-role-assignment-approach.md` — the pause reason and
  the decision criteria ("reshapes ingest/publish/reconcile" → discuss-phase + plan-phase
  `--gaps`) that led to this rewrite.
- `bes/Assign-RoleMapping.bes` — the endpoint policy-action template (`__ROLE__`,
  `__USERNAME__`/client-relevance-resolved, `__ASSIGNED_BY__` tokens); reused as-is by the
  generator this phase builds.
- `scripts/Assign-RoleMapping.ps1` — the endpoint upsert script (D-12 discipline, CLM-safe,
  already smoke-tested against `tests/fixtures/phase-07/roleawareness-v2.db`); reused as-is.
- `scripts/Assign-RoleMapping_test.ps1` — manual smoke-test CLI wrapper.

### Existing Dashboards (patterns to reuse)
- `Existing Dashboards/fixlet_dispatcher.ojo` — `stageOnRootServer` checkbox + the
  "stage on root server" action-dispatch pattern (lines ~1199–1240): the mechanism D-07 reuses
  to write the SQLite audit row on the root server.
- `Existing Dashboards/fixlet_role_assigner.ojo` — base64 chunk / `buildAssignActionXml` /
  Analysis-read view; the Analysis panel structure (D-16) and the `htmlEscape`/relevance
  patterns are lifted into the new dashboard before this file is archived.
- `Existing Dashboards/fixlet_role_admin.ojo` — tab-switch shell pattern, IE9 constraints;
  before archiving, review for any reusable REST-call scaffolding.
- `Existing Dashboards/fixlet_modifier.ojo` — role relevance build, `PORTAL_CONFIG`, IE9
  tab-switch pattern.

### Server-side + endpoint scripts (patterns to reuse / extend)
- `Dashboard_4_samples/Initialize-RoleDb.ps1` — the D-18 `Map` migration
  (`PRAGMA table_info`-gated `ALTER TABLE`) that task 787 needs redeployed with (D-18 in this
  CONTEXT).
- `Dashboard_4_samples/Sqlite-Helper.ps1` — `Invoke-SqliteCommand`, CLM-safe; used by both the
  endpoint script and the new root-server audit-write script.
- `Dashboard_4_samples/Init  Current User and UserRole DB.bes` — task 787 itself; the
  redeploy target for the D-18 schema fix.
- `Dashboard_4_samples/Dereso SWD.bes` — Analysis properties (`mapped_users`, `map_source`,
  `map_region`) the new dashboard's Analysis view reads from.

### Superseded (for historical reference only — do not implement against these)
- `.planning/quick/260828-fjc-role-reference-db/DESIGN.md` — the rejected Axonius reference-DB
  design. Useful only for understanding why it was rejected (too heavy to operate); not a
  spec for this phase.
- `scripts/Import-AxoniousExport.ps1`, `scripts/Publish-RoleSnapshot.ps1`,
  `scripts/Reconcile-LocalRoles.ps1`, `bes/RoleRef-Policy-template.bes` — archived per D-15,
  not extended.

### Prior phase context
- `.planning/phases/04-role-assigner/04-CONTEXT.md` — base64 chunk / action XML origin
  (break-glass, now archived)
- `.planning/phases/05-robustness/05-CONTEXT.md` — logon scheduled task, `Valid_to` renewal
- `.planning/phases/06-update-tracker/06-CONTEXT.md` — content pipeline (unchanged)
- `.planning/phases/03-dispatcher-rapid-deployment/03-CONTEXT.md` — prefetch rewrite chain,
  `stageOnRootServer` origin

### Memory (point-in-time; verify against code)
- `role-reference-db-redesign` — full history of the Axonius design AND its 2026-09-09 pause;
  superseded by this CONTEXT but useful for "why not X" context.
- `bigfix-role-relevance-schema` — `RoleAwareness.db` schema + role relevance pattern
- `bigfix-actionscript-curly-brace-escaping` — not needed for `Assign-RoleMapping.bes` itself
  (it prefetches the script rather than `createfile`-embedding it), but still applies to any
  new root-server audit-write ActionScript that embeds PowerShell inline.
- `sqlite-helper-pattern` — `Invoke-SqliteCommand` via `sqlite3.exe`
- `bigfix-prefetch-url-rewrite` — Dispatcher `rewritePrefetchUrls()` URL shape (relevant if the
  new dashboard's generated action prefetches anything, e.g. `Assign-RoleMapping.ps1` itself)
- `ojo-file-safety` — never save `.ojo` files from within VS Code

### Local BigFix skills
- `G:\Gits\bigfix_skills\skills\` — `jf-bigfix-dashboards`, `jf-bigfix-client-relevance`,
  `jf-bigfix-session-relevance`, `jf-bigfix-actionscript`, `jf-bigfix-parameterized-fixlets`,
  `jf-bigfix-mcp`, `jf-bigfix-api-powershell`, `jf-bigfix-log-analysis`

</canonical_refs>

---

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Assign-RoleMapping.ps1` / `Assign-RoleMapping.bes`** — the entire endpoint half of this
  model is already written and smoke-tested; this phase only needs to build the generator
  (Computer Group + action) and the dashboard around it.
- **`fixlet_dispatcher.ojo`'s `stageOnRootServer` pattern** — the only existing precedent in
  this repo for a dashboard action that runs something on the root server itself; D-07 reuses
  it rather than inventing a new mechanism.
- **`Sqlite-Helper.ps1` / `Invoke-SqliteCommand`** — used by the endpoint script already; the
  new root-server audit-write script uses the same helper.
- **`fixlet_role_assigner.ojo`'s Analysis-read code + base64/XML-build helpers** — lifted into
  the new dashboard before the file is archived (D-16).

### Established Patterns
- **CLM-safe SQLite only** — `sqlite3.exe` + `Sqlite-Helper.ps1`, zero `Add-Type`.
- **D-12 upsert discipline** — `INSERT OR IGNORE` + conditional `UPDATE`, never
  `INSERT OR REPLACE`; `Locked_by_Override = 0` guard everywhere — unchanged, already in
  `Assign-RoleMapping.ps1`.
- **IE9-only OJO JS** — `var` only, no arrow functions/template literals;
  `Msxml2.DOMDocument.6.0`; `API.Get/Post/Put`.
- **Prefetch, not `createfile`, for endpoint scripts** — `Assign-RoleMapping.bes` already
  prefetches its script rather than embedding it, sidestepping the
  `bigfix-actionscript-curly-brace-escaping` concern entirely for that file.

### Integration Points
- Endpoint `RoleAwareness.db` `Map` ← `Assign-RoleMapping.ps1` (policy action per role,
  redeployed on Publish)
- Root-server `RoleUsers` SQLite table ← the new audit-write action (D-07), read by the
  generator when rebuilding a role's Computer Group relevance
- `name of current user` (client relevance) — the single user-identity source in the
  Computer Group's "exactly one of N" check and in `Assign-RoleMapping.bes`'s
  `-UserName` parameter

</code_context>

---

<specifics>
## Specific Ideas

- **"Make it easier to manage"** — the driving complaint against the Axonius design; this
  rewrite trades the ingest/publish/reconcile pipeline for a flat, directly-editable
  username list per role.
- **"BigFix operators" in the Sep 11 commit message meant colloquial role-holders, not BigFix
  Operator accounts** — clarified via D-01; avoid conflating the two in implementation.
- **One role, one group, one action** — the mental model the whole generator hangs off: every
  role maps 1:1 to a Computer Group and 1:1 to a policy action, regenerated together on
  Publish.

</specifics>

---

<deferred>
## Deferred Ideas

- **Dynamic role management from the dashboard** (D-03 declined this for now) — adding a
  brand-new role without editing a config block. Revisit if the role count grows past what a
  short hardcoded list can comfortably hold.
- **BigFix-Operator-account-based role membership** (D-01 declined) — tying role membership to
  real console-operator permissions instead of a flat list. Would be a bigger rework tying
  into BES operator provisioning; not pursued now.
- **Global "publish all" button** (D-13 chose per-role instead) — could be added later as a
  convenience on top of the per-role buttons without changing the underlying model.
- **Same-role shared-login fallback to "map all logged-on matches"** (D-12 declined) — could
  revisit if the accepted gap turns out to matter in practice.
- **Region-based targeting** (D-08 dropped it) — if geographic/regional targeting is ever
  needed again, it would need to be redesigned from scratch against this simpler model rather
  than reviving the old per-region snapshot mechanism.
- Everything already deferred in the 2026-08-29 context that doesn't depend on the retired
  pipeline still applies where relevant: per-session reconcile on multi-user hosts, revoke
  automation beyond age-out, Phase 8 autonomous dispatch, multi-tenant/multi-BigFix, AD direct
  LDAP integration, fixlet rollback, Self-Service catalog UI.

</deferred>

---

*Phase: 7-automation*
*Context gathered: 2026-08-01 · rewritten 2026-08-29 · rewritten again 2026-09-21*
