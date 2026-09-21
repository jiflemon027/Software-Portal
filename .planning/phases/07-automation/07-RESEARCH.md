# Phase 7: End-to-End Automation — Research

**Researched:** 2026-09-21 (full rewrite — supersedes the 2026-08-29 file, which researched
the now-rejected Axonius reference-DB pipeline)
**Domain:** BigFix Automatic Computer Groups (REST + relevance), BigFix REST-deployed policy
actions (`SingleAction` vs `SourcedFixletAction`), CLM-safe SQLite via `sqlite3.exe` on the BES
root server, IE9-constrained OJO dashboard authoring, BigFix Task/.bes redeploy mechanics
**Confidence:** HIGH for codebase-derived patterns and for BigFix REST/relevance claims that
were directly verified against `developer.bigfix.com` in this session (curl-fetched, quoted
verbatim below) · MEDIUM/LOW for a few runtime behaviours that can only be confirmed against
the live root server (`gpbfs`) — flagged explicitly in Assumptions Log and Open Questions

---

## Summary

Phase 7 (rewritten) is **not a greenfield build**. The endpoint half of the Operator-Role-Group
model — `bes/Assign-RoleMapping.bes` + `scripts/Assign-RoleMapping.ps1` — was already written
and smoke-tested on 2026-09-11, before the Axonius pipeline was rejected. What remains to build
is the **generator**: the piece that turns an admin-edited flat username list into (1) one
Automatic Computer Group whose relevance admits a device only when exactly one of the role's
users is logged on, and (2) one redeployed policy action from the existing `.bes` template,
plus a small SQLite audit table on the root server and one new dashboard
(`fixlet_role_manager.ojo`) to drive all of it. The content pipeline (07-03) is untouched.

The single biggest research finding this session: **this repo has never once created a BigFix
Computer Group via REST before.** Every prior phase deploys against *existing* groups
(`fixlet_dispatcher.ojo`'s `targetGroupSelect`) or targets fixed `<ComputerID>` lists
(`fixlet_role_assigner.ojo`'s break-glass path). Creating/updating an **Automatic** Computer
Group via the modern REST API is well-documented and confirmed working (`computergroups/{site
type}/{site name}` POST, `computergroup/{site type}/{site name}/{id}` PUT — both take a
`<ComputerGroup>` BES-XML body: `Title`, `Domain`, `JoinByIntersection`, `IsDynamic`,
`EvaluateOnClient`, one or more `SearchComponentRelevance`) — but a widely-repeated, easy-to-
misread sentence in BigFix's *legacy* "Server API" docs ("no computer groups can be created by
using the Server API") is **not** about the modern REST API this project already uses
everywhere else. See Pitfall 1 — do not let this stale sentence block the design.

The "exactly one of N logged on" relevance is buildable entirely from already-confirmed BigFix
relevance idioms already proven working in this exact codebase (`is contained by`, `set of
(...)`, `{name of current user as lowercase}` in `Assign-RoleMapping.bes`) plus one officially
documented inspector (`logged on users`, plural of `logged on user`). No new/exotic relevance
constructs are required.

The Task 787 D-18 schema-migration fix is **already written** — `Dashboard_4_samples/"Init
Current User and UserRole DB.bes"` already embeds the v4 `Map` migration
(`Source_Type`/`Source_Value`/`Region`/`Assigned_By`) verbatim. The only remaining work is
redeploying it to the live root server (`gpbfs`) — but the current file **also** embeds the
now-retired `Reconcile-LocalRoles.ps1` as a second `RoleDB_Maintenance` scheduled-task action.
That must be stripped before redeploy — see Pitfall 6, this is a concrete, easy-to-miss task.

**Primary recommendation:** Treat the "policy action" half of the generator as a specialised
copy of `fixlet_dispatcher.ojo`'s existing `deployFixlet()` flow (extract `.bes` ActionScript +
Relevance → build a `SingleAction` with client-side `<CustomRelevance>member of group ID of
site "..."</CustomRelevance>` → reapply daily) rather than inventing a new deployment
mechanism. Treat the Computer Group half as a small, new, REST-only capability
(`ComputerGroup` BES-XML) that has no code precedent in this repo but is fully covered by
official docs fetched in this session.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Role → User List Model**
- D-01: Custom per-role username list, not BigFix Operator accounts. Any username, regardless
  of whether it maps to a real console operator.
- D-02: Autocomplete usernames against `RoleAwareness.db` `Users` (already-seen
  `sAMAccountName`s) via the existing Analysis/`GetRelevance` mechanism. Freeform entry allowed.
- D-03: Role list is fixed/small, edited in a `PORTAL_CONFIG.roles`-style config block. Adding a
  brand-new role means editing the dashboard's config block. Only usernames within a role are
  dashboard-managed.
- D-04: A user can hold more than one role — no exclusivity check. `UNIQUE(UserID, Role)` and
  D-12 upsert already support multiple `Map` rows per user.

**Storage & Root-Server Mechanism**
- D-05: SQLite table on the root server (`RoleUsers(Role, UserID, Added_by, Added_on)` or
  similar) is the source of truth for audit/history — not a JSON file, not the Computer Group
  relevance text itself.
- D-06: Dashboard writes are on-demand, plus a periodic refresh job (planner's call on cadence/
  mechanism) that re-syncs each role's Computer Group relevance against the current SQLite
  store, catching drift.
- D-07: REST for BES objects (`API.Put`/`API.Post` from the dashboard), a targeted `SingleAction`
  for the SQLite audit row — reusing `fixlet_dispatcher.ojo`'s `stageOnRootServer` pattern.

**Region**
- D-08: Region survives for reporting only, not targeting. No new Region table, no
  `RolePublication`, no region picker. `GPC_Sub_Name` may still be shown per role-holder for
  visibility only.

**Computer Group / Action Generation**
- D-09: Membership relevance = "exactly one of N logged on," regenerated from the full current
  username list on every Publish.
- D-10: Optional per-role scope filter — a "Target Group" selector that, if set, ANDs an
  additional scope condition into the generated relevance.
- D-11: Policy action reapplies daily ("reapply while relevant," ~24h cadence).
- D-12: Same-role clash on a shared login is an accepted gap (neither user gets mapped there).
  Different-role users sharing a machine are unaffected (each role's group evaluates
  independently).

**Publish Flow**
- D-13: Two-step Save (SQLite row upsert only) then explicit per-role Publish (Computer Group
  PUT + policy-action redeploy for that one role only).

**Dashboard Consolidation**
- D-14: One new dashboard, `Existing Dashboards/fixlet_role_manager.ojo` ("Dereso Role
  Manager"), replaces both `fixlet_role_admin.ojo` and `fixlet_role_assigner.ojo`. No CSV
  upload path survives.
- D-15: Retired files move to `archive/` (not deleted): `fixlet_role_admin.ojo`,
  `fixlet_role_assigner.ojo` → `Existing Dashboards/archive/`;
  `Import-AxoniousExport.ps1`/`Publish-RoleSnapshot.ps1`/`Reconcile-LocalRoles.ps1` →
  `scripts/archive/`; `bes/RoleRef-Policy-template.bes` → `bes/archive/`.
- D-16: Keep a read-only "current role assignments" Analysis view (`mapped_users`/`map_source`/
  `map_region` from `Dereso SWD.bes` via `GetRelevance`).

**Legacy Data & Migration**
- D-17: Legacy `Map` rows (`Assigned_By='AxoniousSync'` or old CSV import) are left alone —
  natural age-out at `Valid_to`, no active cleanup. (Never run against production.)
- D-18: Task 787 schema gap is a hard prerequisite — redeploy from the current
  `Dashboard_4_samples/Initialize-RoleDb.ps1` (already has the `PRAGMA table_info`-gated
  migration) before any dashboard/generator work is verified end-to-end.

### Claude's Discretion
- Exact SQLite schema for the root-server `RoleUsers` audit table (columns beyond
  `Role`/`UserID`, indexing) — see Architecture Patterns → Root-Server Audit Store below for a
  concrete proposal.
- Cadence/mechanism for the D-06 periodic drift-check job (scheduled task vs. lightweight policy
  action re-run) — see Pattern 4 below.
- Whether the D-07 root-server SQLite write is folded into the same `SingleAction` as the group/
  action publish, or dispatched separately — recommendation: separate (see Pattern 3).
- Exact wave/plan subdivision for 07-00 (planner's call whether to reuse or re-cut numbering).

### Deferred Ideas (OUT OF SCOPE)
- Dynamic role management from the dashboard (D-03 declined) — adding a brand-new role without
  a config-block edit.
- BigFix-Operator-account-based role membership (D-01 declined).
- Global "publish all" button (D-13 chose per-role).
- Same-role shared-login fallback to "map all logged-on matches" (D-12 declined).
- Region-based targeting (D-08 dropped it as a targeting mechanism).
- Per-session reconcile on multi-user hosts, revoke automation beyond age-out, Phase 8
  autonomous dispatch, multi-tenant/multi-BigFix, AD direct LDAP integration, fixlet rollback,
  Self-Service catalog UI.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

This phase implements no *new* FR/NFR IDs from `.planning/REQUIREMENTS.md` — Phase 7 is a
cross-cutting "wire it all together" phase layered on top of FR-02/FR-03 (role-based relevance,
Phase 2), FR-08 (automatic user registration on logon, Phase 5), and NFR-01–05. The table below
maps the requirements this phase *touches* to the research that supports them.

| ID | Description | Research Support |
|----|-------------|------------------|
| FR-02 | Role-fixlet association / role-based access control | Unaffected — the Operator-Role-Group model changes *how a user gets a role* (Computer Group membership), not how a role gates a fixlet's relevance (already built in Phase 2/4). |
| FR-03 | Role-based relevance modification | Same as above — `RoleAwareness.db` `Map`-driven relevance (Phase 2/4) is the consumer of what this phase's generator writes; no relevance-generation code in Phase 2/4 changes. |
| FR-08 | Automatic user registration on logon (`RoleDB_Maintenance` task, task 787) | Directly affected by the D-18 task-787 redeploy — see Architecture Patterns → Pattern 5 and Pitfall 6. The FR-08 logon-renewal behaviour (`Initialize-RoleDb.ps1` re-run) must survive the redeploy untouched; only the now-retired `Reconcile-LocalRoles.ps1` second action is dropped. |
| NFR-02 | Reliability — atomic operations, graceful API-error recovery | See Pitfall 4 (partial-publish failure handling: Group PUT succeeds, Task POST fails, etc.) and Pitfall 7 (redeploy vs. leave-running for the policy action). |
| NFR-03 | Security — audit trail of all modifications | Directly served by the D-05 `RoleUsers` root-server audit table — see Architecture Patterns → Root-Server Audit Store. |
| NFR-05 | Maintainability — externalized configuration | D-03's `PORTAL_CONFIG.roles`-style config block; D-10's optional scope-filter config. |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

No `./CLAUDE.md` file exists at the repository root. No project-level directive file to extract
constraints from. Project conventions instead live in `.claude/skills/bigfix-relevance/SKILL.md`
(read in full for this research — see Sources) and in the accumulated `.planning/STATE.md`
"Key Decisions" / "Established Patterns" sections summarized throughout this document.

---

## Architectural Responsibility Map

BigFix does not map cleanly onto the standard web-app tier vocabulary. This project's
equivalents, used throughout the table below:

| Standard tier | BigFix equivalent in this project |
|---|---|
| Browser / Client | The BigFix **Console**, running an OJO dashboard's IE9-engine JS (`API.Get/Post/Put`, `EvaluateRelevance`, `GetRelevance`) |
| Frontend Server (SSR) | *(no equivalent — no server-rendered layer in this stack)* |
| API / Backend | The **BES Root Server**'s REST API (`https://<root>:52311/api/...`) and its object model (fixlets, computer groups, actions, analyses) |
| CDN / Static | The BES Root Server's **Custom Repository** (`Uploads/CustomRepository/...`) serving prefetched files at `127.0.0.1:52311` |
| Database / Storage | Per-endpoint `RoleAwareness.db` (SQLite, via `sqlite3.exe`) **and** the new root-server `RoleUsers` audit SQLite table |
| *(BigFix-specific, no web analog)* | The **BES Client agent**, executing ActionScript locally on an endpoint — this is where `Assign-RoleMapping.ps1` actually runs |

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Role → username list editing/staging | Browser/Client (dashboard JS, Save button) | Database/Storage (root-server `RoleUsers` audit table) | The list is edited in the console UI; Save persists it to the audit table but does not yet touch BES objects (D-13 two-step). |
| Autocomplete against known users (D-02) | Browser/Client (dashboard JS) | Database/Storage (endpoint `RoleAwareness.db` `Users`, surfaced via `Dereso SWD.bes` Analysis + `GetRelevance`) | Read-only lookup; no write path. |
| Automatic Computer Group create/update | API/Backend (BES root server object model) | Browser/Client (dashboard issues the `API.Put`/`API.Post`) | The group definition and its live membership evaluation are server/client-relevance-engine concerns, not dashboard state. |
| Policy action (Task) generate/redeploy | API/Backend (BES root server object model) | Browser/Client (dashboard builds and posts the XML) | Same reasoning — the Task and its deployed `SingleAction` live in the BES object store. |
| Endpoint role-mapping upsert (`Map` table) | *(BigFix-specific)* BES Client agent, running `Assign-RoleMapping.ps1` | Database/Storage (`RoleAwareness.db` on that endpoint) | Runs locally on each targeted endpoint; no dashboard or root-server code executes this step. |
| Root-server audit row write (`RoleUsers`) | *(BigFix-specific)* BES Client agent (the root server's own client, targeted by ComputerID) | Database/Storage (root-server SQLite) | Reuses the `stageOnRootServer` pattern — a client-side script write, not a REST write, because REST has no generic "run arbitrary SQL on the root server" endpoint. |
| Task 787 schema fix / redeploy | *(BigFix-specific)* BES Client agent (every managed endpoint) | Database/Storage (endpoint `RoleAwareness.db` `Map` table) | Migration runs per-endpoint via the existing embedded-PowerShell mechanism; no server-side migration step exists or is needed (each endpoint has its own DB file). |
| Read-only Analysis view (D-16) | Browser/Client (dashboard `GetRelevance` read) | Database/Storage (endpoint `RoleAwareness.db`, exposed via `Dereso SWD.bes` Analysis properties) | Pure read; the Analysis property body is client relevance evaluated on each endpoint, aggregated server-side, read by the dashboard via `GetRelevance`. |
| Content pipeline (07-03, unchanged) | *(BigFix-specific)* Root-server PowerShell scheduled tasks (`Invoke-ContentSync.ps1`, `Stage-Repository.ps1`) | Database/Storage (`AutomationState.db` `ContentItem`/`ContentCache`) + CDN/Static (Custom Repository) | Out of scope for this rewrite; unaffected. |

---

## Standard Stack

No new libraries. This phase is 100% BigFix-native XML/relevance/ActionScript plus the
project's existing hand-rolled JS (OJO dashboards) and PowerShell 5.1 (CLM-safe, `sqlite3.exe`
via `Sqlite-Helper.ps1`). There is no npm/pip/cargo dependency surface to version-check.

### Core (reused as-is, no changes)
| Component | Version/Pin | Purpose | Why Standard (for this project) |
|---|---|---|---|
| `sqlite3.exe` | 3.53.1 (zip sha1 `184d4d0b75cd75c2118fb22a1727e9220f843b98`) | CLM-safe SQLite CLI, endpoint + root server | Already pinned and staged by task 787 / the content pipeline; do not introduce a different build. |
| `Dashboard_4_samples/Sqlite-Helper.ps1` | in-repo, no version | `Invoke-SqliteCommand` wrapper | The only sanctioned way to touch SQLite from PowerShell in this project (CLM-safe; `System.Data.SQLite.dll`/`Add-Type` are prohibited). |
| `bes/Assign-RoleMapping.bes` | in-repo, written 2026-09-11 | Endpoint policy-action Task template | Already smoke-tested; this phase only builds the generator around it, per CONTEXT.md D-18/canonical refs. |
| `scripts/Assign-RoleMapping.ps1` | in-repo, written 2026-09-11 | Endpoint upsert script | Already smoke-tested against `tests/fixtures/phase-07/roleawareness-v2.db`; reused as-is. |

### Supporting
| Component | Purpose | When to Use |
|---|---|---|
| `Get-BigFixCredential.ps1` (07-00) | AKeyless universal-identity credential retrieval, no secret at rest | Only needed for a **root-server-initiated** REST call (e.g. the D-06 periodic drift-check job, if implemented as a scheduled task rather than a policy action). Dashboard-initiated REST calls use the console's own authenticated session and do **not** need this. |
| `fixlet_dispatcher.ojo`'s `buildTargetRelevance()` / `buildStagingActionXml()` / `rewritePrefetchUrls()` | Client-side group-membership targeting, root-server staging pattern | Directly reusable patterns for the generator's SingleAction targeting and the D-07 audit write — see Architecture Patterns. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| REST-created Automatic Computer Group (`ComputerGroup` BES-XML) | A `ServerBasedGroup` (property-reference based) | `ServerBasedGroup` matches on a **retrieved property** value (e.g., an Analysis property holding the role name), refreshed only via `POST .../refresh` — adds a dependency on a new Analysis property per role and an explicit refresh call. The relevance-based `ComputerGroup` evaluates continuously on the client with no extra moving parts; matches D-09's "exactly one of N logged on" requirement directly. Not recommended. |
| Per-role dedicated Task (`fixlets/custom/<site>`, one per role) | One shared Task with a role parameter resolved at deploy time | BigFix Tasks have no first-class "deploy-time parameter override" mechanism usable from a REST-deployed `SingleAction`; the `Role`/`AssignedBy` values are baked into the Task's `<ActionScript>` parameter lines at authoring time (see `__ROLE__`/`__ASSIGNED_BY__` tokens in `Assign-RoleMapping.bes`). One Task per role (find-or-create by title) is the only mechanism that fits this project's existing `.bes` template. |
| `SingleAction` deployed with `<CustomRelevance>member of group ID of site "..."</CustomRelevance>` | `SourcedFixletAction` targeting the group directly | `SourcedFixletAction` evaluates `<CustomRelevance>` **server-side**, where `member of group` cannot resolve — confirmed pitfall already documented in this repo's `bigfix-relevance` skill (§3) from Phase 3/4 UAT. `SingleAction` evaluates client-side and is what every other dynamic-group deployment in this repo already uses. |

**Installation:** N/A — no new packages.

## Package Legitimacy Audit

**Not applicable.** This phase installs no new external npm/pip/cargo packages. The only
"dependency" touched is the already-pinned `sqlite3.exe` 3.53.1 build (verified/staged in prior
phases; unchanged here). No slopcheck run was needed.

---

## Architecture Patterns

### System Architecture Diagram

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │  BigFix Console                                                         │
 │  fixlet_role_manager.ojo  (new dashboard, replaces role_admin +         │
 │                             role_assigner)                              │
 │                                                                         │
 │   [Edit username list for Role X]                                      │
 │          │  Save (D-13 step 1)                                         │
 │          ▼                                                             │
 │   API.Post/Put → root-server SingleAction targeted at rootServer       │
 │   ComputerID → writes RoleUsers audit row via Sqlite-Helper.ps1  ──────┼──┐
 │                                                                         │  │
 │   [Publish Role X] (D-13 step 2, per-role button)                      │  │
 │          │                                                             │  │
 │          ├─(1)─▶ API.Get computergroups/custom/<site> ─ find-by-title ─┼──┤
 │          │       API.Post|Put computergroup/custom/<site>[/id]         │  │
 │          │       body: <ComputerGroup> Title/Domain/JoinByIntersection │  │
 │          │       /IsDynamic/EvaluateOnClient/SearchComponentRelevance  │  │
 │          │       Relevance = "exactly one of Role X's usernames        │  │
 │          │       logged on" [+ D-10 optional scope AND]                │  │
 │          │                                                             │  │
 │          ├─(2)─▶ API.Get fixlets/custom/<site> ─ find-by-title         │  │
 │          │       API.Post|Put fixlet/custom/<site>[/id]                │  │
 │          │       body: bes/Assign-RoleMapping.bes with __ROLE__ /      │  │
 │          │       __ASSIGNED_BY__ substituted (one Task per role)       │  │
 │          │                                                             │  │
 │          └─(3)─▶ API.Post actions  (SingleAction)                      │  │
 │                  Relevance/ActionScript copied from step 2's Task      │  │
 │                  DefaultAction; Target = CustomRelevance "member of    │  │
 │                  group <id-from-step-1> of site <site>"; Reapply=true, │  │
 │                  ReapplyInterval=P1D, IsOffer=false                    │  │
 └─────────────────────────────────────────────────────────────────────────┘
                                                                           │
        ┌──────────────────────────────────────────────────────────────┐ │
        │ BES Root Server (its own BES Client agent, ComputerID-       │◀┘
        │ targeted, same "stageOnRootServer" pattern as the Dispatcher) │
        │  → runs Sqlite-Helper.ps1 + inline PS to upsert a RoleUsers   │
        │    row (audit trail: Role, UserID, Added_by, Added_on)        │
        └──────────────────────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────────────────────┐
        │ Every endpoint matching "exactly one of Role X's users        │
        │ logged on" (client relevance, re-evaluated continuously)      │
        │  → policy action reapplies daily → Assign-RoleMapping.ps1     │
        │    upserts local RoleAwareness.db Map (D-12 discipline)       │
        └──────────────────────────────────────────────────────────────┘

        ┌──────────────────────────────────────────────────────────────┐
        │ Every managed endpoint (task 787, FR-08, unaffected by this   │
        │ phase except the D-18 schema-migration redeploy)              │
        │  → RoleDB_Maintenance scheduled task reruns                   │
        │    Initialize-RoleDb.ps1 on every logon → renews Valid_to,    │
        │    ensures Map has Source_Type/Source_Value/Region/           │
        │    Assigned_By columns                                       │
        └──────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

No new top-level folders — additions land in existing conventions:
```
Existing Dashboards/
├── fixlet_role_manager.ojo        # NEW — replaces role_admin + role_assigner
└── archive/
    ├── fixlet_role_admin.ojo      # moved here (D-15)
    └── fixlet_role_assigner.ojo   # moved here (D-15)
bes/
├── Assign-RoleMapping.bes         # unchanged (2026-09-11), reused as template
└── archive/
    └── RoleRef-Policy-template.bes # moved here (D-15)
scripts/
├── Assign-RoleMapping.ps1         # unchanged, reused as-is
├── Assign-RoleMapping_test.ps1    # unchanged
├── Sync-RoleGroups.ps1            # NEW (optional, D-06 drift-check — see Pattern 4)
└── archive/
    ├── Import-AxoniousExport.ps1
    ├── Publish-RoleSnapshot.ps1
    └── Reconcile-LocalRoles.ps1
Dashboard_4_samples/
├── Initialize-RoleDb.ps1          # unchanged — already has the v4/D-18 migration
├── Sqlite-Helper.ps1              # unchanged
└── "Init  Current User and UserRole DB.bes"  # EDIT — strip the Reconcile-LocalRoles.ps1
                                                # wiring before this phase's task-787 redeploy
                                                # (see Pitfall 6)
tests/unit/
├── role_manager.test.js           # NEW — pure-JS extraction tests for the new dashboard
└── (role_admin.test.js / role_assigner.test.js retained for regression until archived files
    are actually deleted from git history's working tree, or archived alongside their subjects)
```

### Pattern 1: Automatic Computer Group create/update via REST

**What:** POST (create) or PUT (update) a `<ComputerGroup>` BES-XML document to define a role's
membership group.

**When to use:** Every Publish (D-13) for a role — first Publish creates the group, subsequent
Publishes PUT the same group ID with a refreshed relevance string reflecting the current
username list.

**Verified schema** [CITED: developer.bigfix.com/other/platform-api/bes-xml/computer_groups.html
— fetched and quoted verbatim in this session]:
```
<ComputerGroup>
    <Title> xs:normalizedString </Title> [1]
    <JoinByIntersection> xs:boolean </JoinByIntersection> [1]
    <IsDynamic> xs:boolean </IsDynamic> [1]        -- "Must be true. For internal use."
    <EvaluateOnClient> xs:boolean </EvaluateOnClient> [1]  -- "Must be true. For internal use."
    <SearchComponentRelevance Comparison="IsTrue"|"IsFalse"> [0..*]
        <Relevance> RelevanceString </Relevance> [1]
    </SearchComponentRelevance>
    <!-- SearchComponentPropertyReference / SearchComponentGroupReference also valid, unused here -->
</ComputerGroup>
```
Note: the official schema text does **not** list `<Domain>`, but a confirmed real, working
example ships it — [CITED: github.com/jgstew/bigfix-content, `AutomaticComputerGroups/VM -
VMWare.bes`, fetched verbatim in this session]:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<BES xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="BES.xsd">
	<ComputerGroup>
		<Title>VM - VMWare</Title>
		<Domain>BESC</Domain>
		<JoinByIntersection>true</JoinByIntersection>
		<SearchComponentRelevance Comparison="IsTrue">
			<Relevance><![CDATA[ ... ]]></Relevance>
		</SearchComponentRelevance>
	</ComputerGroup>
</BES>
```
This real example **omits** `IsDynamic`/`EvaluateOnClient` entirely and it still works — but
since the official schema marks both `[1]` (mandatory), the safest generator output includes
**all** of `Title`, `Domain`, `JoinByIntersection`, `IsDynamic`, `EvaluateOnClient`,
`SearchComponentRelevance` (belt-and-suspenders; confirmed MEDIUM confidence via
cross-referencing both sources — no working example with all 6 present was found in this
session, so verify the first real create against the live console before relying on it).

**REST endpoints** [CITED: developer.bigfix.com/rest-api/api/computergroup.html — fetched and
quoted verbatim]:
```
GET    computergroups/{site type}/{site name}          -- list (find-by-title before create)
POST   computergroups/{site type}/{site name}           -- create; body = <BES><ComputerGroup>...
GET    computergroup/{site type}/{site name}/{id}        -- fetch one, BES.xsd
PUT    computergroup/{site type}/{site name}/{id}         -- update
DELETE computergroup/{site type}/{site name}/{id}         -- delete
GET    computergroup/{site type}/{site name}/{id}/computers  -- list current members
```
For this project's custom site, `{site type}/{site name}` = `custom/Dereso%20Software%20Portal`
— matches the existing `"fixlets/custom/" + encodeURIComponent(site)` convention already used in
`fixlet_copier.ojo` line 904.

**Find-or-create by title** — avoids persisting a group ID anywhere new; mirrors the existing
`allGroups` session-relevance query already used in `fixlet_dispatcher.ojo` (line 998):
```js
// Source: pattern lifted from fixlet_dispatcher.ojo's existing allGroups loader
var rel = '(id of it as string & "|||" & name of it) of bes computer groups whose ' +
  '(name of site of it = "' + PORTAL_CONFIG.siteName + '" and name of it = "' +
  safeName.replace(/"/g, '""') + '")';
var found = EvaluateRelevance(rel);
// found[0] (if any) = "<id>|||<title>" -> PUT computergroup/custom/<site>/<id>
// else -> POST computergroups/custom/<site>
```

### Pattern 2: The "exactly one of N logged on" relevance (D-09)

**What:** The `SearchComponentRelevance`'s `<Relevance>` body — client relevance, evaluated
continuously and independently on every endpoint (this is *why* `IsDynamic`/`EvaluateOnClient`
must be true).

**Confirmed building blocks:**
- `logged on user` / plural `logged on users` — "Returns zero or more users logged on to this
  computer... iterates through all logged-on users, using Fast User Switching, Terminal
  Services, ACLs" [CITED: developer.bigfix.com/relevance/reference/logged-on-user.html].
- `name of <user>` returns the bare username (no domain prefix observed/assumed in this
  project's existing usage — `Assign-RoleMapping.bes` already does `{name of current user as
  lowercase}` with no domain-stripping, and that file is smoke-tested and in production use)
  [VERIFIED: codebase, `bes/Assign-RoleMapping.bes` line 77].
- `X is contained by <set>` combined with `set of (tuple)` — already a **production-proven**
  idiom in this exact codebase, task 787's live relevance:
  `(name of logged on user is not contained by it) of (set of ((rows of statement "..." of it)
  as string))` [VERIFIED: codebase, `Dashboard_4_samples/"Init  Current User and UserRole
  DB.bes"` line 15].
- `number of <set/tuple>` for cardinality checks (used generically throughout BigFix relevance;
  a working "count logged-on users" idiom was independently confirmed:
  `"number of logged on users"` [CITED: forum.bigfix.com/t/relevance-to-detect-multiple-logged-on-users/50421]).

**Recommended generated relevance** (semicolon-tuple form, avoids any `it`-shadowing ambiguity
from nested `whose` clauses — the username list is inlined as string literals directly in the
`whose` predicate, not passed in via an outer `of (set of (...))` wrapper):
```
(number of (logged on users whose (name of it as lowercase is contained by set of
  ("alice";"bob";"carol")))) = 1
```
— substitute the role's current (lower-cased, `"`→`""`-escaped) username list for
`"alice";"bob";"carol"`. Wrap in `<SearchComponentRelevance Comparison="IsTrue">`.

**D-10 optional scope filter**, ANDed in when a "Target Group" is set — reuse
`fixlet_dispatcher.ojo`'s existing `member of group` idiom verbatim [VERIFIED: codebase,
`fixlet_dispatcher.ojo` line 503]:
```
(number of (logged on users whose (name of it as lowercase is contained by set of
  ("alice";"bob";"carol")))) = 1 AND (member of group 12345 of site whose
  (name of it as lowercase = "dereso software portal" as lowercase))
```

**Edge case (must guard in generator code):** a role with **zero** usernames must not produce
`set of ()` — build `false` (never matches) instead. Untested whether `set of ()` errors or
silently evaluates empty in this BigFix version — treat as LOW confidence, avoid entirely by
special-casing empty lists in the generator.

### Pattern 3: Policy action generation/redeploy (D-07, D-11, D-13)

**What:** Deploying `bes/Assign-RoleMapping.bes`'s `DefaultAction` against the role's Computer
Group, using the **same mechanism** `fixlet_dispatcher.ojo` already uses for any dynamic-group
deploy — `SingleAction` with client-side `<CustomRelevance>`, **not** `SourcedFixletAction`
[VERIFIED: codebase + `.claude/skills/bigfix-relevance/SKILL.md` §3 — `SourcedFixletAction`
evaluates `<CustomRelevance>` server-side, where `member of group` cannot resolve and silently
returns 0 relevant computers; confirmed by this project's own Phase 3/4 UAT history].

**Steps per Publish:**
1. Find-or-create the role's Task in `fixlets/custom/<site>` by title match (same
   session-relevance pattern as Pattern 1), POSTing a fresh copy of `bes/Assign-RoleMapping.bes`
   with `__ROLE__`/`__ASSIGNED_BY__` substituted if it doesn't exist yet, or re-PUTting it if the
   `AssignedBy` value changed. **Build the XML from scratch** (extract fields via
   `getElementsByTagName`, do not copy Task XML in place) — this project has a documented,
   confirmed 400-Bad-Request pitfall for in-place Task XML edits [VERIFIED: codebase,
   `.claude/skills/bigfix-relevance/SKILL.md` §7, and `fixlet_copier.ojo`'s `buildXml()`
   reference implementation].
2. Extract that Task's `<DefaultAction>` `<Relevance>`/`<ActionScript>` (same
   `getActionScript()`-style extraction already in `fixlet_dispatcher.ojo`).
3. Build a `SingleAction`:
   - `<Target><CustomRelevance>member of group <id-from-Pattern-1> of site "<site>"
     </CustomRelevance></Target>` — element order matters: `Target` after `Settings`
     [VERIFIED: codebase skill doc §3, confirmed 400-error if violated].
   - `<Settings>`: `<Reapply>true</Reapply>`, `<HasReapplyLimit>false</HasReapplyLimit>`,
     `<HasReapplyInterval>true</HasReapplyInterval>`, `<ReapplyInterval>P1D</ReapplyInterval>`
     [CITED: developer.bigfix.com ActionSettings schema — `ReapplyInterval` enum includes
     `P1D`, fetched and quoted in this session]. `<IsOffer>false</IsOffer>`,
     `<PreActionShowUI>false</PreActionShowUI>` — silent policy action, not an offer (unlike
     the Dispatcher's deploy flow, which always sets `IsOffer=true`).
   - No `<HasEndTime>` — this is a perpetual policy, not an expiring offer.
4. `API.Post("actions", xml, ...)`.

### Pattern 4: D-06 periodic drift-check job (discretion — recommendation)

Recommend a **root-server PowerShell scheduled task** (not a BigFix policy action), because the
work involved (re-reading `RoleUsers`, re-PUTting each role's `ComputerGroup`) is pure REST +
SQLite and has no need to run on arbitrary endpoints. This mirrors the already-established
07-03 content-pipeline pattern exactly:
- Reuse `Get-BigFixCredential.ps1` (AKeyless universal identity, already built in 07-00) for the
  root-server script's own REST calls — this is the **one** place in this phase that legitimately
  needs a service credential, because it runs unattended outside any console session (unlike the
  dashboard, which rides the operator's own authenticated console session).
- New script `scripts/Sync-RoleGroups.ps1`: for each role in the `RoleUsers` audit table, rebuild
  the Pattern 2 relevance from the latest username set and PUT the group if it differs from the
  live group's relevance (read via `GET computergroup/custom/<site>/<id>`).
- Register via the existing `Register-AutomationTasks.ps1` `$AutomationTaskTable` convention
  (07-00's "APPEND-ONLY" contract — see Pitfall 8 for a nuance the planner must resolve).

### Pattern 5: Root-Server Audit Store (D-05 schema proposal)

Follows this project's established SQLite conventions exactly (`INTEGER PRIMARY KEY
AUTOINCREMENT`, `datetime('now','localtime')`, `CREATE TABLE IF NOT EXISTS`,
`PRAGMA table_info`-gated future migrations — same shape as `Initialize-RoleDb.ps1`):
```sql
-- One row per Publish event, per role
CREATE TABLE IF NOT EXISTS RolePublishRun (
    RunID         INTEGER PRIMARY KEY AUTOINCREMENT,
    Role          TEXT NOT NULL,
    Published_by  TEXT NOT NULL,
    Published_on  TEXT NOT NULL DEFAULT (datetime('now','localtime')),
    UserCount     INTEGER NOT NULL
);

-- The username set as of that Publish (full snapshot, not a diff — matches D-09's
-- "regenerated from the full current username list on every Publish")
CREATE TABLE IF NOT EXISTS RoleUsers (
    RUID    INTEGER PRIMARY KEY AUTOINCREMENT,
    RunID   INTEGER NOT NULL REFERENCES RolePublishRun(RunID),
    Role    TEXT NOT NULL,
    UserID  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_roleusers_run  ON RoleUsers(RunID);
CREATE INDEX IF NOT EXISTS idx_roleusers_role ON RoleUsers(Role);
```
"Current" membership for a role = all `RoleUsers` rows whose `RunID` is that role's
`MAX(RunID)` in `RolePublishRun`. This gives Pattern 4's drift-check job a clean read path
without needing a separate "current state" table to keep in sync.

**Write mechanism** — reuse `fixlet_dispatcher.ojo`'s `stageOnRootServer` `SingleAction`
pattern verbatim: `<Target><ComputerID>{PORTAL_CONFIG.rootServerComputerId}</ComputerID>
</Target>` (not `CustomRelevance` — a single fixed computer, per the skill doc §3 guidance),
`<Relevance>true</Relevance>`, `ActionScript` built via `createfile` embedding an inline
PowerShell upsert (same `escapeActionScriptBraces()` — **double the opening `{` only**, never
the closing `}` — this project has a documented, previously-fixed bug from doubling both
[VERIFIED: codebase skill doc §2, `fixlet_dispatcher.ojo`'s staging-action-script history]).
`PORTAL_CONFIG.rootServerComputerId` is populated via the existing `<?relevance ?>` tag idiom
[VERIFIED: codebase, `fixlet_dispatcher.ojo` line 47] — reuse directly, do not re-derive.

### Pattern 6: Task 787 D-18 redeploy — exact diff needed

`Dashboard_4_samples/"Init  Current User and UserRole DB.bes"` **already contains** the v4 Map
migration (`Source_Type`/`Source_Value`/`Region`/`Assigned_By` via `PRAGMA table_info`-gated
`ALTER TABLE`, error code 5400) inside its embedded `Initialize-RoleDb.ps1` — this part needs no
further edits, only a live redeploy of the unmodified file. **However**, the same file **also**:
- Prefetches `Reconcile-LocalRoles.ps1` (a script D-15 retires to `scripts/archive/`).
- `copy`s it into `{SWPDir}\Reconcile-LocalRoles.ps1` on every endpoint.
- Registers it as a **second action** in the `RoleDB_Maintenance` scheduled task
  (`$actionReconcile`), alongside the FR-08 `$actionInit` action.

Before redeploying task 787 under this phase, **strip**:
- The `add prefetch item name=Reconcile-LocalRoles.ps1 ...` line.
- The `copy "__Download\Reconcile-LocalRoles.ps1" ...` + its enclosing `mkdir ...\roleref`
  block.
- The `$actionReconcile` variable and its inclusion in `Register-ScheduledTask -Action
  @($actionInit, $actionReconcile)` → becomes `-Action @($actionInit)` (or just `$actionInit`
  directly).

Everything else in the file — directory prep, `sqlite3.exe` staging, the embedded
`Sqlite-Helper.ps1`/`Initialize-RoleDb.ps1` createfile blocks, the `Unregister-ScheduledTask`
pre-registration-guard (Pitfall 5 from the prior research, still valid: gate the re-register on
non-existence would leave the OLD two-action command line forever on already-provisioned
endpoints if not unregistered first) — is unaffected by this rewrite and should be redeployed
unchanged.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SQLite access from PowerShell | A new `System.Data.SQLite`/`Add-Type`-based helper | `Dashboard_4_samples/Sqlite-Helper.ps1` (`Invoke-SqliteCommand`) | CLM-blocked otherwise; this helper is already the sole sanctioned mechanism project-wide. |
| Building the `SingleAction`/`ComputerGroup`/Task XML by hand per-call | Ad hoc string concatenation scattered through new code | The `buildXml()`/`buildDeployXml()`/`buildTargetRelevance()`/`getActionScript()` patterns already in `fixlet_dispatcher.ojo` and `fixlet_copier.ojo` | These already encode every schema gotcha this project has hit (element order, MIME-field copy, CDATA-escaping, "build from scratch don't mutate Task XML") — re-deriving them risks reintroducing already-fixed bugs. |
| Detecting "who is logged on" for the group-membership check | A custom WMI/registry poll from a PowerShell script | The BigFix relevance engine's own `logged on users` inspector, evaluated natively by the client as part of Computer Group membership | This is exactly what `IsDynamic`/`EvaluateOnClient` + client relevance already do — no polling script needed, no extra deployed component. |
| ActionScript brace-escaping for any new embedded PowerShell | A regex that doubles both `{` and `}` | `escapeActionScriptBraces()` — double `{` only | Doubling `}` too is a **documented, previously-shipped bug** in this exact codebase (confirmed in `fixlet_dispatcher.ojo`'s staging-action history) — don't reintroduce it. |

**Key insight:** every hard technical problem this phase touches (CLM-safe SQLite, dynamic-group
targeting, root-server staging, ActionScript escaping) already has a working, tested precedent
somewhere in this repository. The only genuinely new surface is the `ComputerGroup` REST/XML
shape (Pattern 1) — everything else is composition of existing, proven pieces.

---

## Runtime State Inventory

This phase retires a prior automation model. A grep audit of the repo finds files; it does not
find runtime state that a rejected-but-partially-built pipeline may have left on the live BES
environment. Answering each category explicitly:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | The `AutomationState.db` role tables (`Role`, `Region`, `GroupRoleMap`, `RefUser`, `UserRole`, `RolePublication`, `Snapshot`) exist only in **local dev/test fixtures** (`tests/fixtures/phase-07/`) and whatever `Initialize-AutomationDb.ps1 -WhatIf`/live runs happened during 07-00–07-04 development. Per `.planning/STATE.md`, execution paused **before** the 07-05 production-fleet verification step ever ran — the Axonius ingest/publish/reconcile pipeline was "never run against production" (CONTEXT.md D-17, explicit user statement). **No data migration needed** — there is no live `AutomationState.db` role data to migrate away from. Verify this assumption on the live root server before deleting anything (see Environment Availability). |
| Live service config | Per the same pause history, `RoleRef-Policy-template.bes`-derived per-region policy Fixlets, and the `DeresoRoleIngest`/`DeresoRolePublish` scheduled tasks, were likely **never registered** on the live root server (`Register-AutomationTasks.ps1`'s live run was part of the un-executed 07-05 Task 4). **Verify, do not assume** — run a one-time audit query (`GET fixlets/custom/<site>` filtered by title, `schtasks /query` on `gpbfs` for those two names) as an early Wave-0 task before archiving the source scripts, in case a manual test run registered something that a `git status`-only view can't see. |
| OS-registered state | Task 787 (`Init  Current User and UserRole DB`) **is** live in production (predates Phase 7, from FR-08/Phase 5) and **does** need the D-18 redeploy (Pattern 6). The `RoleDB_Maintenance` scheduled task is live on every managed endpoint and will pick up the corrected (single-action) command line automatically on the next task-787 action run, via the existing `Unregister-ScheduledTask` + re-register guard already in the file. |
| Secrets/env vars | No secret names change. `PipelineConfig.AKeylessTokenFile`/`AKeylessSecretPath` (content pipeline, unaffected) keep their existing values. |
| Build artifacts | None — no compiled/installed artifacts in this stack besides the already-pinned `sqlite3.exe`, unaffected. |

**Config file cleanup (new finding, not in the original 5 categories but adjacent):**
`config/PipelineConfig.defaults.json` carries several keys that become dead weight under the new
model: `AxoniousExportPath`, `SnapshotOutputDir`, `SnapshotUrlBase`, `UsernameSourcePriority`,
`ConsoleUserRelevance`. These are harmless if left (no code will read them once the ingest/
publish/reconcile scripts are archived), but leaving them risks confusing a future maintainer
into thinking the Axonius pipeline is still live config. Recommend removing them as part of this
phase's archival cleanup — **planner's call**, not a hard requirement.

---

## Common Pitfalls

### Pitfall 1: The "Server API can't create computer groups" trap
**What goes wrong:** A search for "BigFix REST API create computer group" surfaces an
often-quoted sentence — "only automatic groups can be created by importing through the console,
and no computer groups can be created by using the Server API" — that reads like a blanket
statement that automation is impossible.
**Why it happens:** That sentence is from the **BES-XML / legacy "Server API"** documentation
page (`developer.bigfix.com/other/platform-api/bes-xml/computer_groups.html`), a different,
older API surface than the **modern REST API** (`developer.bigfix.com/rest-api/api/
computergroup.html`) this project already uses for every other object type (`fixlets/custom`,
`actions`, `sites`). The modern REST API's own docs explicitly document `POST computergroups/
{site type}/{site name}` and `PUT computergroup/{site type}/{site name}/{id}` as working
operations, with `Request Schema: BES.xsd` (i.e., a `<ComputerGroup>` body, not just
`ServerBasedGroup`).
**How to avoid:** Trust the REST API docs (Pattern 1) over the legacy Server-API docs for this
project — every dashboard in this repo already uses the REST API exclusively, never the legacy
Server API.
**Warning signs:** If a generator's `POST computergroups/custom/<site>` call 404s or 400s, the
cause is almost certainly a malformed `<ComputerGroup>` body (missing mandatory element, wrong
site-type segment) — not an inherent API limitation.

### Pitfall 2: `SourcedFixletAction` silently deploys to zero computers
**What goes wrong:** Using `SourcedFixletAction` (which references a Fixlet/Task by ID plus a
`<CustomRelevance>`) to target the role's Computer Group returns HTTP 200 but the action
applies to 0 computers.
**Why it happens:** `SourcedFixletAction`'s `<CustomRelevance>` is evaluated **server-side**,
and `member of group` cannot resolve group membership server-side.
**How to avoid:** Always use `SingleAction` for this deploy (Pattern 3) — already the confirmed,
documented rule in this codebase for any dynamic-group target.
**Warning signs:** Deploy succeeds (action ID returned) but the action's computer count stays 0
in the console — a documented Phase 3/4 UAT finding, not new to this phase.

### Pitfall 3: `<Target>` element ordering
**What goes wrong:** `POST actions` returns 400 Bad Request.
**Why it happens:** `SingleAction` element order is fixed: `Title → Relevance → ActionScript →
[SuccessCriteria] → Settings → [SettingsLocks] → [IsUrgent] → Target →
[MIMEFieldSingleAction]`. Putting `<Target>` before `<Settings>` is a confirmed 400-causing
mistake in this codebase's history.
**How to avoid:** Follow the exact element order already encoded in
`fixlet_dispatcher.ojo`'s `buildDeployXml()`.

### Pitfall 4: Partial-publish failure leaves Group/Task/Action out of sync
**What goes wrong:** Group PUT succeeds, but the subsequent Task POST/PUT or Action POST fails
(network blip, REST 5xx) — the role now has an updated membership list with either a stale
policy action or none at all.
**Why it happens:** The three REST calls in Pattern 3's Publish flow are not transactional;
BigFix's REST API has no multi-object atomic-commit primitive.
**How to avoid:** Sequence the calls so the **least disruptive failure mode wins**: PUT the
Group first (worst case: membership rule updates but the same already-running, already-reapplied
action just re-evaluates against it — see Pitfall 7), then Task, then Action, with inline
per-step error surfacing (same "errEl"/"resultEl" inline-feedback pattern already used in
`fixlet_dispatcher.ojo`'s `deployFixlet()` — no `alert()`). Report each step's success/failure
distinctly in the dashboard UI so the operator knows exactly which of the three objects is
stale.

### Pitfall 5: `RoleDB_Maintenance` re-register only fires if the task doesn't already exist
**What goes wrong:** Redeploying task 787 (Pattern 6) has no effect on endpoints where
`RoleDB_Maintenance` is already registered, because the registration script only creates the
task "if not exists."
**Why it happens:** Documented in the current `.bes` itself — `if { not (exists (scheduled
tasks whose (name of it = "RoleDB_Maintenance"))) }` — this is exactly why the file already
`Unregister-ScheduledTask`s first (unconditionally) before that guard, a fix from a prior phase.
**How to avoid:** Confirm this `Unregister-ScheduledTask ... -ErrorAction SilentlyContinue`
step survives your Pattern-6 edit (it should — it's unrelated to the Reconcile-LocalRoles.ps1
lines being stripped) so the corrected single-action command line actually lands on
already-provisioned endpoints.

### Pitfall 6: Task 787's current file wires in the retired `Reconcile-LocalRoles.ps1`
**What goes wrong:** Redeploying `Dashboard_4_samples/"Init  Current User and UserRole DB.bes"`
byte-for-byte would land a prefetch + scheduled-task action for a script (`Reconcile-
LocalRoles.ps1`) that D-15 archives this same phase — every endpoint would download and
register a scheduled-task action for a script that (a) depends on a per-region snapshot file
that will never exist under the new model, and (b) is being moved to `scripts/archive/` and is
no longer maintained.
**Why it happens:** The file predates this rewrite (last touched during 07-02, before the
09-21 CONTEXT.md rewrite).
**How to avoid:** Apply the exact diff in Pattern 6 before any redeploy.
**Warning signs:** If skipped, `Reconcile-LocalRoles.ps1` runs on every logon on every endpoint,
finds no `roleref-<region>-latest.json` file (never published under the new model), and
presumably fails/no-ops silently or logs errors every logon — wasted work at best, log noise at
worst.

### Pitfall 7: Does "redeploy the policy action" mean stop-and-recreate every Publish, or create-once?
**What goes wrong:** CONTEXT.md D-13 says Publish does "the Computer Group PUT + policy-action
redeploy for that one role," which reads as "always create a new action." But BigFix actions are
immutable once deployed — you cannot edit a running `SingleAction`'s target or script. If every
Publish genuinely creates a brand-new action without stopping the previous one, the role
accumulates an ever-growing number of "Open" actions over time (each individually harmless due
to D-12's idempotent upsert, but noisy in the console and in `SyncRun`-style audit logs).
**Why it happens:** Because the *group's* relevance is what actually determines who the *already
running* action applies to, a first-Publish-only action deployment plus every-Publish-just-PUT-
the-group would functionally satisfy D-09/D-11 without ever needing to touch the action again —
but this contradicts the literal D-13 wording.
**How to avoid:** This needs an explicit planner/discuss-phase decision, not a research
guess (flagged in Open Questions below) — two viable, well-understood options exist: (a) create
the action once, PUT the group on every subsequent Publish (simpler, fewer BES objects, action's
own history in the console still reflects an accurate current-membership evaluation at any given
moment); (b) `POST /api/action/{id}/stop` the previous action (found via title-match session
relevance, same technique as Pattern 1) then create a fresh one on every Publish (matches the
literal D-13 wording, gives a clean per-Publish audit trail of exactly which action deployment
corresponds to which `RolePublishRun`, at the cost of one more BES object and REST round-trip
per Publish). [CITED: developer.bigfix.com/rest-api/api/action.html for the stop/delete
endpoints, fetched and quoted in this session.]

### Pitfall 8: `$AutomationTaskTable`'s "APPEND-ONLY" convention conflicts with archiving
**What goes wrong:** `scripts/Register-AutomationTasks.ps1` documents `$AutomationTaskTable` as
an APPEND-ONLY contract (07-00's stated design intent, so later waves could add rows without
later waves' code needing edits to earlier waves). This phase's D-15 archival of
`Import-AxoniousExport.ps1`/`Publish-RoleSnapshot.ps1` makes their corresponding
`DeresoRoleIngest`/`DeresoRolePublish` table rows dead — but removing rows breaks the stated
append-only contract.
**Why it happens:** The append-only rule was designed for incremental *feature* growth within
one coherent pipeline design, not for a mid-project pipeline replacement.
**How to avoid:** Treat this phase's archival work as an explicit, intentional exception to the
07-00 convention (this is a phase-level rewrite, not an incremental addition) — remove the two
stale rows rather than leaving dead entries that reference archived scripts. Flag this decision
in the phase's plan/summary so the exception is documented, not silently made.

---

## Code Examples

### Find-or-create a BES object by title (session relevance)
```javascript
// Source: pattern lifted from fixlet_dispatcher.ojo's existing allGroups loader (line 998)
// and reused for both Computer Groups (Pattern 1) and Tasks (Pattern 3, step 1).
function findComputerGroupIdByTitle(siteName, title) {
  var safeSite = String(siteName).replace(/"/g, '""');
  var safeName = String(title).replace(/"/g, '""');
  var rel = '(id of it as string) of bes computer groups whose (name of site of it = "' +
    safeSite + '" and name of it = "' + safeName + '")';
  var found = EvaluateRelevance(rel);
  return (found && found.length > 0) ? found[0] : null;
}
```

### "Exactly one of N logged on" relevance builder
```javascript
// Source: this research, Pattern 2 — no direct codebase precedent for this exact expression,
// but every sub-idiom (is contained by / set of / logged on users) is independently confirmed.
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
```

### ComputerGroup BES-XML builder
```javascript
// Source: this research, Pattern 1 — schema per developer.bigfix.com (cited above)
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

---

## State of the Art

| Old Approach (rejected 2026-09-21) | Current Approach (this rewrite) | When Changed | Impact |
|--------------------------------------|------------------------------------|---------------|--------|
| Daily Axonius CSV ingest → `AutomationState.db` reference tables → per-region JSON snapshot → endpoint `Reconcile-LocalRoles.ps1` | Admin-edited flat username list per role → generated Automatic Computer Group + redeployed policy action | 2026-09-21 CONTEXT.md rewrite | No more ingest pipeline, no per-region snapshot files, no `GroupRoleMap` pattern-matching; role assignment is immediate (next relevance re-evaluation + next reapply cycle) rather than daily-batch. |
| ComputerID-based targeting (Phase 4 CSV break-glass) | Client-side "exactly one of N logged on" relevance, no ComputerID anywhere | 2026-08-29 rewrite (carried forward) | Role follows the *user*, not the machine — a user gets the role's software/policy on whichever machine they're currently, uniquely, logged into. |
| `fixlet_role_admin.ojo` + `fixlet_role_assigner.ojo` (two dashboards) | `fixlet_role_manager.ojo` (one dashboard) | 2026-09-21 | Simpler operator workflow; D-14. |

**Deprecated/outdated:**
- The entire Axonius ingest/publish/reconcile pipeline and its `AutomationState.db` role tables
  — retired, archived, not to be extended (D-15, D-17).
- `fixlet_role_admin.ojo`'s Region/GroupRoleMap/Reference-DB tabs — retired (D-08, D-15).
- CSV-based break-glass role assignment (`fixlet_role_assigner.ojo`) — retired, no replacement
  path; the username-list editor is the only path now (D-14).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `POST computergroups/{site}` / `PUT computergroup/{site}/{id}` with a full `<ComputerGroup>` body (all 6 documented elements) will be accepted by this project's live BigFix version without further undocumented required elements. | Pattern 1 | If the live BES server rejects the POST/PUT (e.g., requires an element not in the fetched docs, or a specific `Domain` value), the entire generator's Group-creation step blocks. Mitigate with an early Wave-0 spike: POST one throwaway test group by hand via `curl`/Postman against the real root server before writing dashboard code against this shape. |
| A2 | `set of ("a";"b";"c")` (a semicolon-tuple literal wrapped in `set of (...)`) is valid BigFix relevance syntax for a small literal string set, by analogy with the confirmed-working `set of ((rows of statement ... ) as string)` idiom. | Pattern 2 | If the literal-tuple form doesn't parse the same way as the query-derived-tuple form, the generated Computer Group relevance is syntactically invalid and the group either errors or never matches. Verify against the BigFix Fixlet Debugger / QnA tool before shipping the generator. |
| A3 | `name of <logged on user>` never includes a domain prefix on this project's managed Windows fleet (carried over from the already-production `Assign-RoleMapping.bes`'s unguarded `{name of current user as lowercase}` usage). | Pattern 2 | If some endpoints return `DOMAIN\username`, the generated relevance's bare-username literals never match on those machines, silently under-mapping affected users. Low risk — this exact assumption is already live in production via `Assign-RoleMapping.bes`, so any failure would already be visible. |
| A4 | No live `DeresoRoleIngest`/`DeresoRolePublish` scheduled tasks or per-region policy Fixlets exist on the production root server (`gpbfs`) from the paused-before-verification Axonius pipeline work. | Runtime State Inventory | If wrong, archiving the source scripts without also unregistering/stopping the live tasks/fixlets leaves orphaned automation running against a script that no longer exists at its expected path, likely erroring on next scheduled run. Must be verified directly against the live root server, not assumed from git history. |
| A5 | `sqlite3.exe` is already present and at the pinned 3.53.1 build on the production BES root server (`gpbfs`), not just on dev/test hosts. | Pattern 5, Environment Availability | If absent, the root-server audit-write action (Pattern 5) and the D-06 drift-check job (Pattern 4) both fail on first run. Carried over from the prior research's A5, still unresolved per `.planning/STATE.md`'s "Pending Todos." |
| A6 | Including all 6 schema-documented `ComputerGroup` elements (`Title`/`Domain`/`JoinByIntersection`/`IsDynamic`/`EvaluateOnClient`/`SearchComponentRelevance`) is safe even though the one located real-world example omits `IsDynamic`/`EvaluateOnClient`. | Pattern 1 | Low risk (extra elements matching documented schema are unlikely to cause a rejection) but unverified against this project's specific BigFix server version. |

---

## Open Questions

1. **Stop-and-recreate vs. create-once for the policy action (Pitfall 7)**
   - What we know: BigFix actions are immutable once deployed; the Computer Group's own
     relevance is what actually re-evaluates membership on every reapply cycle regardless of
     which approach is chosen.
   - What's unclear: Whether D-13's "policy-action redeploy" wording is a strict requirement
     (stop+recreate every Publish) or a description of the end-to-end effect (which create-once
     also achieves).
   - Recommendation: Raise explicitly in `/gsd:discuss-phase` or as a plan-time
     `checkpoint:human-verify` — this materially affects whether the generator needs a
     stop-action REST call and how "policy action redeploy" is verified/tested.

2. **Live-environment verification of the `ComputerGroup` REST shape (A1, A2, A6)**
   - What we know: The documented schema and one real working example both check out.
   - What's unclear: Whether this project's specific BigFix server/console version accepts the
     exact combination of elements recommended in Pattern 1's "belt-and-suspenders" form.
   - Recommendation: A Wave-0 spike task — hand-build and POST one throwaway
     `ComputerGroup`/relevance pair against the real root server, confirm it appears correctly in
     the console with the expected live membership, before the dashboard generator code is
     written against unverified assumptions.

3. **Whether any live artifacts from the paused Axonius pipeline exist on `gpbfs` (A4)**
   - What we know: `.planning/STATE.md` states the 07-05 production-fleet verification Task 4
     never ran.
   - What's unclear: Whether any *earlier*, informal/manual test run against production happened
     outside the tracked plan-execution flow.
   - Recommendation: An early Wave-0 audit task (REST `GET` for fixlets/computer groups/tasks
     matching the retired naming patterns, `schtasks /query` for the two scheduled task names) —
     see Runtime State Inventory.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| BigFix root server REST API (`https://<root>:52311/api/...`) reachable from the console session | Every REST call in Patterns 1–3 | Assumed ✓ (every existing dashboard already depends on this) | Live version not confirmed in this session | None — hard dependency, but zero new risk vs. every other phase. |
| `sqlite3.exe` 3.53.1 staged at the configured `SQLDir` on the **root server** (`gpbfs`) | Pattern 5 (audit write), Pattern 4 (drift-check script) | **Unconfirmed on production** — carried-over open item (A5) from the prior research; `.planning/STATE.md` lists it under "Pending Todos" | 3.53.1 pinned (dev/test) | If absent: Pattern 5's audit write and Pattern 4's drift job both fail. Fallback: stage it via the same `unzip.exe` + Custom-Repository mechanism task 787 already uses for endpoints (`sqlite-tools-win-x64-3530100.zip`), as a one-time Wave-0 prerequisite step for the root server specifically. |
| The BES root server enrolled as a managed BES Client (so it can be `ComputerID`-targeted by a `SingleAction`) | Pattern 5 (audit write), the pre-existing `stageOnRootServer` mechanism it reuses | Assumed ✓ — `fixlet_dispatcher.ojo`'s `stageOnRootServer` feature already depends on this and is presumably already in production use (its checkbox is `checked disabled` — i.e., always-on, not experimental) | — | None identified — if this were broken, the pre-existing Dispatcher staging feature would already be non-functional, which is not reported as a known issue. |
| `Get-BigFixCredential.ps1` / AKeyless universal identity | Pattern 4 only (root-server-initiated drift-check script) — **not** needed for the dashboard's own REST calls | Built in 07-00 per `.planning/STATE.md`; live AKeyless secret path (`BigFix-RoleSync-Operator`) confirmation was part of the un-executed 07-05 Task 4 | — | If the AKeyless secret isn't actually provisioned yet, defer Pattern 4 (the periodic drift-check job) to a later plan/wave — it is Claude's-discretion scope, not a hard D-05/D-07 requirement, and the dashboard's on-demand Publish flow (D-13) does not depend on it at all. |
| BigFix Fixlet Debugger / QnA (for manually verifying Assumption A2's relevance syntax before shipping) | Pre-generator verification (Open Question 2) | Not checked in this session (no BigFix console access from this research environment) | — | If unavailable to whoever executes this phase, substitute the BigFix Console's own "Edit Automatic Computer Group" relevance-test dialog, or a throwaway `EvaluateRelevance()` call from any existing dashboard, to confirm A2 before shipping the generator. |

**Missing dependencies with no fallback:** None identified for the core Publish flow (Patterns
1–3) — everything needed is either already live (REST API, root-server enrollment) or has a
documented fallback (sqlite3.exe staging).

**Missing dependencies with fallback:** `sqlite3.exe` on the root server (A5) and the AKeyless
secret provisioning for Pattern 4 both have documented fallbacks/deferrals above and should be
confirmed as an early Wave-0 step rather than assumed.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Node.js built-in `assert`/`fs` (JS pure-function extraction tests) + Pester 5.7.1 (PowerShell) |
| Config file | None for Node (`node <file>.test.js` run directly). None for Pester beyond `tests/pester/README.md`'s documented `SQLDIR` env-var contract. |
| Quick run command | `node tests/unit/role_manager.test.js` (new dashboard) · `Invoke-Pester tests/pester/<OneFile>.Tests.ps1 -Output Detailed` |
| Full suite command | `node tests/unit/*.test.js` (all suites) `&& pwsh -c "Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI"` |

### Phase Requirements → Test Map
| Req/Decision | Behavior | Test Type | Automated Command | File Exists? |
|--------------|----------|-----------|-------------------|-------------|
| D-09 (relevance) | `buildRoleGroupRelevance()` produces the exact "exactly one of N logged on" string, including the empty-list `"false"` special case and `"` escaping | unit (Node assert, pure-function extraction, mirroring the existing `role_assigner.test.js`/`role_admin.test.js` "verbatim extraction" convention) | `node tests/unit/role_manager.test.js` | ❌ Wave 0 |
| D-10 (scope filter) | `buildRoleGroupRelevance()` correctly ANDs the `member of group` clause only when a scope group is supplied | unit (Node assert) | `node tests/unit/role_manager.test.js` | ❌ Wave 0 |
| Pattern 1 (Group XML) | `buildComputerGroupXml()` emits all 6 schema elements in a parseable order; `Relevance` is CDATA-wrapped and `]]>`-safe | unit (Node assert, DOM-parse the output string via the same `Msxml2.DOMDocument.6.0`-style parse already used in `role_assigner.test.js`, or a lightweight regex/string assertion if DOM parsing isn't available in the Node test harness) | `node tests/unit/role_manager.test.js` | ❌ Wave 0 |
| Pattern 3 (Action XML) | `SingleAction` element order (`Title→Relevance→ActionScript→Settings→Target`), `Reapply`/`ReapplyInterval` present, `IsOffer=false` | unit (Node assert, string-order assertion — same pattern already used implicitly by `dispatcher.test.js`'s XML-shape checks) | `node tests/unit/role_manager.test.js` | ❌ Wave 0 |
| Pattern 5 (audit schema) | `RolePublishRun`/`RoleUsers` DDL is idempotent (`CREATE TABLE IF NOT EXISTS`), and a second run against an already-initialised DB makes no destructive changes | Pester (temp SQLite DB via `sqlite3.exe`, same harness pattern as `Initialize-RoleDb.Tests.ps1`) | `Invoke-Pester tests/pester/Initialize-RoleUsersDb.Tests.ps1` (new file) | ❌ Wave 0 |
| Pattern 6 (task 787 diff) | The corrected `.bes` no longer contains `Reconcile-LocalRoles.ps1` prefetch/copy/scheduled-task-action text, while the v4 Map migration block is untouched | Pester (string/regex assertion against the `.bes` file's ActionScript CDATA — same style as `RoleRefPolicyBes.Tests.ps1` from the prior research, repurposed) | `Invoke-Pester tests/pester/InitCurrentUserTask.Tests.ps1` (new file) | ❌ Wave 0 |
| D-12 (endpoint upsert, regression only) | `Assign-RoleMapping.ps1`'s existing D-12 discipline still passes against a DB migrated by the corrected task-787 script | Pester (reuse/extend existing smoke test against `tests/fixtures/phase-07/roleawareness-v2.db`) | `Invoke-Pester tests/pester/Reconcile-LocalRoles.Tests.ps1` — **rename or replace**, this file's subject script is archived; the D-12 regression coverage should move to a new/renamed suite testing `Assign-RoleMapping.ps1` directly (it may already exist informally via `Assign-RoleMapping_test.ps1`, which is a manual smoke wrapper, not an automated Pester suite) | ⚠️ Wave 0 — confirm whether `Assign-RoleMapping.ps1` has automated Pester coverage anywhere; if not, this is a genuine Wave 0 gap, not just a rename |
| Regression | All existing dashboard unit suites (`role_admin.test.js`, `role_assigner.test.js`, others) still pass while the subjects they test are archived (files move, tests either move with them or are retired in the same commit) | Node assert | full existing suite | ✓ (existing) — but the plan must explicitly decide whether `role_admin.test.js`/`role_assigner.test.js` are deleted alongside their `.ojo` subjects or retained as frozen regression snapshots; leaving them green-but-orphaned is a maintainability smell worth a plan-time decision, not a silent default. |

### Sampling Rate
- **Per task commit:** the one relevant `*.test.js` or `*.Tests.ps1` file (< 30s)
- **Per wave merge:** full Node suite + full non-Slow Pester suite
- **Phase gate:** full suite green, plus the live-environment spikes from Open Questions 2–3
  (these are **not** automatable — they require a real BES root server) signed off as a
  `checkpoint:human-verify` before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/unit/role_manager.test.js` — new file, covers D-09/D-10 relevance builder + Pattern
      1/3 XML builders (no existing coverage — this is a brand-new dashboard)
- [ ] `tests/pester/Initialize-RoleUsersDb.Tests.ps1` — new file, covers Pattern 5's audit-table
      DDL idempotency
- [ ] `tests/pester/InitCurrentUserTask.Tests.ps1` — new file, covers the Pattern 6 diff (confirm
      `Reconcile-LocalRoles.ps1` wiring is gone, v4 migration is intact)
- [ ] Confirm whether `scripts/Assign-RoleMapping.ps1` has any existing **automated** (Pester)
      regression coverage beyond the manual `Assign-RoleMapping_test.ps1` smoke wrapper — if not,
      add one before relying on D-12 behaviour surviving the task-787 redeploy
- [ ] Decide (and document in the plan) the fate of `tests/unit/role_admin.test.js` /
      `role_assigner.test.js` when their `.ojo` subjects move to `archive/` (delete together,
      or retain as frozen snapshots — see Regression row above)

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No (new surface) | This phase adds no new authentication surface — REST calls ride the console operator's existing authenticated session (dashboard) or the existing AKeyless universal-identity credential (Pattern 4's root-server script, already built in 07-00). |
| V3 Session Management | No (new surface) | Same as above — no new session mechanism introduced. |
| V4 Access Control | Yes | The generator's REST calls execute with whatever BES operator permissions the logged-in console user already has (standard BigFix console RBAC) — creating/editing Computer Groups and deploying actions already requires appropriate console-operator rights; this phase does not elevate or bypass that. No custom access-control logic to build. |
| V5 Input Validation | Yes | Username-list entries (D-02 free-text entry) must be validated/escaped before being interpolated into (a) generated relevance strings (Pattern 2 — `"`→`""` escaping, already shown in the code examples) and (b) SQL parameters written to the `RoleUsers` audit table (use `Invoke-SqliteCommand`'s existing `ConvertTo-SqliteLiteral` parameterization — never string-concatenate raw usernames into SQL). |
| V6 Cryptography | No | No new cryptography — AKeyless credential retrieval (Pattern 4) reuses the already-built, already-reviewed `Get-BigFixCredential.ps1` from 07-00; no plaintext secrets introduced, no new crypto primitives hand-rolled. |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|----------------------|
| Relevance injection via a malicious/malformed username (e.g. a username containing `"` or BigFix relevance metacharacters, entered via D-02's freeform text path) | Tampering | Escape every username with `.replace(/"/g, '""')` before interpolating into the generated `SearchComponentRelevance` (already shown in `buildRoleGroupRelevance()`) — same discipline `fixlet_dispatcher.ojo`'s `buildTargetRelevance()` already applies to group names. |
| SQL injection into the `RoleUsers` audit table via a crafted username/role string | Tampering | Never string-concatenate into SQL — always go through `Invoke-SqliteCommand -Parameters @{...}`, which uses `ConvertTo-SqliteLiteral`'s single-quote-doubling (already the project-wide standard, confirmed safe against this project's documented ROADMAP injection payload test). |
| XML/CDATA injection when embedding a role name or username into `<Title>`/`<Relevance>` (e.g. a role or username containing `]]>` or `<`) | Tampering | Use the existing `xmlEscape()` for element text and `xmlCDataSafe()` (which escapes `]]>` by splitting the CDATA section) for CDATA bodies — both already used project-wide, apply identically here. |
| A stale/incorrect `AssignedBy` value silently persisting because the per-role Task (Pattern 3, step 1) isn't re-PUT when it should be | Repudiation | The audit trail's `Published_by` column (Pattern 5) records who triggered each Publish independent of what's baked into the Task XML, so even if the Task itself lags, the audit table remains an accurate record of who published what and when. |
| Over-broad Computer Group scope from a malformed/empty relevance accidentally matching every computer (e.g. a bug producing `"true"` instead of `"false"` for an empty username list) | Elevation of Privilege | The explicit empty-list guard in `buildRoleGroupRelevance()` (return `"false"`, never an unconstrained `"true"`) plus a unit test asserting this exact behavior (see Validation Architecture, D-09 row) — this is the single highest-impact bug this generator could ship, since it would silently apply a role's policy action fleet-wide. |

---

## Sources

### Primary (HIGH confidence)
- `.claude/skills/bigfix-relevance/SKILL.md` — read in full; this project's own accumulated,
  point-in-time-verified BigFix relevance/ActionScript/dashboard conventions (relevance
  dialects, brace escaping, `SingleAction`/`SourcedFixletAction`, prefetch rewriting, REST
  gotchas, `.beswrpt` format).
- `developer.bigfix.com/rest-api/api/computergroup.html` — fetched and quoted verbatim (curl) —
  REST endpoints, HTTP methods, `ServerBasedGroup` example, stop/refresh/delete semantics.
- `developer.bigfix.com/other/platform-api/bes-xml/computer_groups.html` — fetched and quoted
  verbatim (curl) — `<ComputerGroup>` BES-XML schema, the "Server API" restriction sentence
  (Pitfall 1's root cause).
- `developer.bigfix.com/other/platform-api/bes-xml/shared/searchcomponents.html` — fetched and
  quoted verbatim (curl) — `SearchComponentRelevance`/`SearchComponentPropertyReference`/
  `SearchComponentGroupReference` schema and semantics.
- `developer.bigfix.com/relevance/reference/logged-on-user.html` and `.../user.html` — fetched
  and quoted verbatim (curl) — `logged on user`/`logged on users` inspector semantics, `name of
  <user>` behavior.
- `developer.bigfix.com/rest-api/api/action.html` — fetched and quoted verbatim (curl) — action
  stop/delete endpoints (Pitfall 7).
- `github.com/jgstew/bigfix-content/blob/master/AutomaticComputerGroups/VM%20-%20VMWare.bes` —
  fetched verbatim (curl, raw file) — a real, working `ComputerGroup` BES-XML example.
- This repository's own code, read directly: `bes/Assign-RoleMapping.bes`,
  `scripts/Assign-RoleMapping.ps1`, `Existing Dashboards/fixlet_dispatcher.ojo`,
  `Existing Dashboards/fixlet_role_assigner.ojo`, `Existing Dashboards/fixlet_role_admin.ojo`,
  `Existing Dashboards/fixlet_modifier.ojo`, `Existing Dashboards/fixlet_copier.ojo`,
  `Dashboard_4_samples/Initialize-RoleDb.ps1`, `Dashboard_4_samples/"Init  Current User and
  UserRole DB.bes"`, `Dashboard_4_samples/Dereso SWD.bes`, `scripts/Register-AutomationTasks.ps1`,
  `config/PipelineConfig.defaults.json`, `tests/pester/README.md`, `tests/unit/role_assigner.test.js`.

### Secondary (MEDIUM confidence)
- `developer.bigfix.com` ActionSettings schema page (`Reapply`/`ReapplyInterval` enum) — fetched
  via curl, grepped for the relevant section rather than read end-to-end.
- WebSearch results cross-referencing the "Server API can't create groups" sentence against
  multiple independent sources (BigFix forum threads, HCL product docs) — all consistent with
  the Pitfall 1 interpretation.

### Tertiary (LOW confidence)
- `forum.bigfix.com/t/relevance-to-detect-multiple-logged-on-users/50421` — a community forum
  post confirming the `"number of logged on users"` idiom; not an official doc, but consistent
  with the officially-documented `logged on users` plural inspector, so treated as
  cross-verified rather than pure LOW confidence.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries, every reused component already pinned/verified in
  prior phases.
- Architecture (Computer Group + policy action generation): MEDIUM-HIGH — REST/relevance schema
  directly verified against official docs and one real working example in this session; the
  exact combination of "belt-and-suspenders" elements (A6) and the literal `set of (...)` form
  (A2) are not yet verified against this project's specific live BigFix version.
  Composition with already-proven codebase patterns (SingleAction targeting, root-server
  staging, XML-from-scratch building) is HIGH confidence.
- Pitfalls: HIGH for all pitfalls sourced directly from this codebase's own documented history
  (skill doc, `.bes` files); MEDIUM for Pitfall 7 (a genuine open design question, not a
  verified failure mode).

**Research date:** 2026-09-21
**Valid until:** ~30 days for the BigFix-relevance/REST-API findings (stable product surface,
unlikely to change) · re-verify immediately if the live BES root server version differs
materially from what these official docs describe, or once the Open Questions' Wave-0 spikes
produce ground truth (at which point their findings should be folded back into this document
or superseded by a `07-VALIDATION.md`/plan-time note).
