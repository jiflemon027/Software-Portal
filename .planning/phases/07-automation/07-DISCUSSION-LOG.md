# Phase 7: Automation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-21
**Phase:** 07-automation
**Areas discussed:** Role -> user list source, Dashboard consolidation & scope, Apply/publish flow, Multi-role / multi-user-per-machine handling, Root-server write mechanism, Legacy data migration, Task 787 schema gap

---

## Role -> user list source

| Option | Description | Selected |
|--------|-------------|----------|
| Real BigFix Operators | Query BES REST API for actual Operator accounts + a role/permission attribute | |
| Custom per-role username list | Flat admin-maintained list, independent of BigFix Operator accounts | ✓ |
| You decide | Let the planner pick | |

**User's choice:** Custom per-role username list

| Option | Description | Selected |
|--------|-------------|----------|
| Autocomplete from RoleAwareness.db | Suggest known usernames from Analysis/REST | ✓ |
| Freeform text only | No validation | |

**User's choice:** Autocomplete from RoleAwareness.db

| Option | Description | Selected |
|--------|-------------|----------|
| Dynamic — dashboard manages roles | Admin can add new roles from the dashboard | |
| Fixed config block (current pattern) | Roles stay a hardcoded list, like PORTAL_CONFIG.roles | ✓ |

**User's choice:** Fixed config block (current pattern)

| Option | Description | Selected |
|--------|-------------|----------|
| Small store on the BES root server | JSON/SQLite source of truth | ✓ |
| Baked directly into Computer Group relevance text | No separate store | |

**User's choice:** Small store on the BES root server

| Option | Description | Selected |
|--------|-------------|----------|
| Single JSON file | One RoleGroups.json in the Custom Repository | |
| SQLite table on root server | Small dedicated table | ✓ |

**User's choice:** SQLite table on root server

| Option | Description | Selected |
|--------|-------------|----------|
| Fully on-demand | No scheduled component at all | |
| Dashboard writes + a periodic refresh job | Adds a drift-check job on top | ✓ |

**User's choice:** Dashboard writes + a periodic refresh job

---

## Dashboard consolidation & scope

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, one new dashboard | Retire both fixlet_role_assigner.ojo and fixlet_role_admin.ojo | ✓ |
| New dashboard + keep CSV break-glass | Keep old CSV tool as fallback | |
| Retrofit fixlet_role_admin.ojo in place | Reuse existing file, replace its tabs | |

**User's choice:** Yes, one new dashboard

| Option | Description | Selected |
|--------|-------------|----------|
| Drop Region entirely | No more per-region distribution to gate by | |
| Keep for reporting only | Show GPC_Sub_Name for visibility, not targeting | ✓ |

**User's choice:** Keep for reporting only

| Option | Description | Selected |
|--------|-------------|----------|
| fixlet_role_manager.ojo | New filename, "Dereso Role Manager" | ✓ |
| Reuse fixlet_role_admin.ojo filename | Keep old filename, replace content | |

**User's choice:** fixlet_role_manager.ojo

| Option | Description | Selected |
|--------|-------------|----------|
| Delete old files | Nothing depends on them, git history is the backstop | |
| Move to an archive/ folder | Keep for reference, out of active paths | ✓ |
| Leave in place, unreferenced | Don't touch now | |

**User's choice:** Move to an archive/ folder

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, keep Analysis view | Read-only current-assignments visibility | ✓ |
| No, drop it | Verify elsewhere | |

**User's choice:** Yes, keep it

| Option | Description | Selected |
|--------|-------------|----------|
| Fully automatic targeting | No group-picker UI at all | |
| Keep an optional scope filter | Extra AND condition, defense-in-depth | ✓ |

**User's choice:** Keep an optional scope filter

---

## Apply/publish flow

| Option | Description | Selected |
|--------|-------------|----------|
| Regenerate + redeploy immediately | One-click, fully live | |
| Two-step: Save then explicit Publish | Review point before fleet changes | ✓ |

**User's choice:** Two-step: Save then explicit Publish

| Option | Description | Selected |
|--------|-------------|----------|
| Exactly-one-of-N logged on | Admits device only when exactly one role user is logged in | ✓ |
| At-least-one logged on | Looser, relies on ActionScript to resolve the right user | |

**User's choice:** Exactly-one-of-N logged on

| Option | Description | Selected |
|--------|-------------|----------|
| Per-role Publish button | Lower blast radius per click | ✓ |
| Single global Publish button | Simpler UI, touches everything dirty at once | |

**User's choice:** Per-role Publish button

| Option | Description | Selected |
|--------|-------------|----------|
| Reapply while relevant, daily | Standard BigFix policy cadence | ✓ |
| One-time action only | No re-map for hosts that never log off | |

**User's choice:** Reapply while relevant, daily

---

## Multi-role / multi-user-per-machine handling

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, allowed | A username can hold multiple roles at once | ✓ |
| No, enforce one role per user | Dashboard blocks double-membership | |

**User's choice:** Yes, allowed

| Option | Description | Selected |
|--------|-------------|----------|
| Both roles map independently | Each group's own check fires on its own list | ✓ |
| Neither maps — skip on multi-user ambiguity | Err toward doing nothing | |

**User's choice:** Both roles map independently

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, skip — acceptable gap | Two same-role users sharing a login is a rare, accepted miss | ✓ |
| Fall back to mapping all logged-on matches | Change group check to at-least-one | |

**User's choice:** Yes, skip — acceptable gap

---

## Root-server write mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Dashboard PUTs Computer Group via REST; root-server action writes SQLite row | Reuses fixlet_dispatcher.ojo's stageOnRootServer pattern | ✓ |
| Drop SQLite store; Computer Group relevance IS the source of truth | Fewer moving parts, no audit table | |

**User's choice:** Dashboard PUTs the Computer Group directly via REST; a root-server action writes the SQLite row

---

## Legacy data migration

| Option | Description | Selected |
|--------|-------------|----------|
| Leave them alone — age out naturally | AxoniousSync rows were never run against production anyway | ✓ |
| Actively re-tag or purge on first run | Explicit cleanup of prior-sourced rows | |

**User's choice:** Leave them alone — they age out naturally

---

## Task 787 schema gap

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, in scope | Hard prerequisite — Assign-RoleMapping.ps1 can't succeed without it | ✓ |
| No, separate follow-up | Track outside this phase | |

**User's choice:** Yes, in scope

---

## Claude's Discretion

- Exact SQLite schema for the root-server `RoleUsers` audit table beyond `Role`/`UserID`.
- Cadence/mechanism for the periodic drift-check job (D-06).
- Whether the root-server SQLite write is folded into the same action as the Computer Group
  publish, or dispatched separately (D-07).
- Exact wave/plan subdivision for the phase re-plan.

## Deferred Ideas

- Dynamic role management from the dashboard (declined for now — D-03).
- BigFix-Operator-account-based role membership (declined — D-01).
- Global "publish all" button (declined in favor of per-role — D-13).
- Same-role shared-login fallback to "map all logged-on matches" (declined — D-12).
- Region-based targeting revival (dropped — D-08).
