# Phase 7: End-to-End Automation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-29
**Phase:** 07-automation
**Areas discussed:** Approach to existing artifacts, Database topology, Dashboard split, Plan restructure, Endpoint reconcile coordination, OJO file layout
**Driving input:** `.planning/quick/260828-fjc-role-reference-db/DESIGN.md` (role-side design, decisions already locked in that doc)

---

## Approach to existing CONTEXT.md + 5 unexecuted plans

| Option | Description | Selected |
|--------|-------------|----------|
| Rewrite CONTEXT.md, replan after | Fold DESIGN.md in as the authoritative role-side design, keep content-pipeline decisions, regenerate affected plans | ✓ |
| Merge into existing CONTEXT.md | Append new D-xx with supersede notes, keep old role decisions visible | |
| View existing plans first | Inspect 07-00 / 07-02..04 before deciding | |

**User's choice:** Rewrite CONTEXT.md, replan after.
**Notes:** DESIGN.md explicitly mandates "rewrite Phase 7 in place." No plans executed, so a clean rewrite + replan carries no rework cost.

---

## Database topology

| Option | Description | Selected |
|--------|-------------|----------|
| Two separate DBs | `RoleReference.db` (role, per DESIGN) + shrunken `AutomationState.db` (content only); drop `RoleAssignment`; `GroupRoleMap` only in `RoleReference.db` | |
| One combined DB | All role + content tables in `AutomationState.db`; drop `RoleAssignment`; single init script; shared `SyncRun` / `PipelineConfig` | ✓ |
| You decide | — | |

**User's choice:** One combined DB.
**Notes:** DESIGN's `RoleReference.db` name is dropped; its 7 role tables plus the 2 content tables live in `AutomationState.db`. `SyncRun` gains a `Type` column spanning Ingest/Publish/ContentSync/RepoStage; DESIGN's `Config` seed keys merge into `PipelineConfig`. Recorded as D-01.

---

## Dashboard split

| Option | Description | Selected |
|--------|-------------|----------|
| DESIGN.md intent | GroupRoleMap authoring stays in `fixlet_automation_monitor.ojo` Config tab; role_assigner gets only a Region tab | |
| Consolidate on role_assigner | GroupRoleMap + RolePublication + Region all on the role dashboard; automation_monitor is content-only | ✓ |
| Defer automation_monitor | Ship only role_assigner amendments + scripts; monitoring via logs/Analysis | |
| You decide | — | |

**User's choice:** Consolidate the role-admin UI onto the role dashboard; `fixlet_automation_monitor.ojo` becomes content-pipeline only.
**Notes:** Follow-up question established the role-admin UI should be a **new `fixlet_role_admin.ojo`** rather than more tabs on `fixlet_role_assigner.ojo` (which stays the break-glass CSV + Analysis tool). Recorded as D-22/D-23/D-24.

---

## Plan restructure

| Option | Description | Selected |
|--------|-------------|----------|
| Keep 5, planner subdivides | Keep the 5-plan/5-wave shape; let plan-phase subdivide the heavy role pipeline plan internally | |
| Split into 6+ | Separate ingest from publish+reconcile as their own plans | ✓ |
| You decide | — | |

**User's choice:** Split into 6 plans / 6 waves — 07-00 foundation, 07-01 ingest, 07-02 publish+distribute+reconcile, 07-03 content pipeline (renumbered), 07-04 dashboards, 07-05 integration+rollout.
**Notes:** Existing 07-02/03/04 renumber to 07-03/04/05; none executed so the renumber is clean. Recorded as D-25.

---

## Endpoint reconcile coordination

| Option | Description | Selected |
|--------|-------------|----------|
| Commit logon-rework first | Commit the uncommitted logon-rework as its own baseline commit, then Phase 7 builds on top | |
| Fold into Phase 7 | 07-00 owns logon-rework finalisation + `Map` migration + Reconcile wiring, committed under the phase | ✓ |
| You decide | — | |

**User's choice:** Fold the uncommitted logon-rework into Phase 7 Wave 0.
**Notes:** 07-00 finalises `Initialize-RoleDb.ps1` v3 + the `.bes` changes, adds the additive `Map` migration (`Source_Type`/`Source_Value`/`Region`/`Assigned_By`), and wires `Reconcile-LocalRoles.ps1` into `RoleDB_Maintenance`. Live redeploy of task 787 is a 07-05 rollout step. Recorded as D-18/D-19.

---

## OJO file layout (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| One file, tabbed | All role admin as tabs on `fixlet_role_assigner.ojo` | |
| New `fixlet_role_admin.ojo` | Separate new dashboard for GroupRoleMap + RolePublication + Region + Reference-DB viewer | ✓ |
| You decide | — | |

**User's choice:** New `fixlet_role_admin.ojo`. `fixlet_role_assigner.ojo` stays the break-glass CSV tool (Analysis view gains Source/Region columns).

---

## Claude's Discretion

- Combined-DB internal naming where DESIGN.md and old D-05 disagree (`Config` vs `PipelineConfig`, `CacheEntry` vs `ContentCache`, unified `SyncRun` columns).
- Whether the per-region policy action carries the optional freshness gate in v1.
- Task-level subdivision inside the 07-01 streaming-ingest plan.
- `Dereso SWD.bes` property names for the new Source/Region Analysis columns.

## Deferred Ideas

- `GroupRoleMap` rule content — the one go-live gate (not a phase blocker; scripts test against `SampleAxonious` fixtures).
- Per-session reconcile on multi-user hosts.
- Operator region form populating `RefUser.RegionID` / `RolePublication` at scale.
- Revoke automation / `EnableRevoke`.
- Phase 8 autonomous dispatch; multi-tenant / multi-BigFix; AD direct LDAP; fixlet rollback; self-service catalog UI.
