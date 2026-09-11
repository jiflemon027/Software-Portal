---
created: 2026-09-09T14:20:10.269Z
title: Rework how roles are assigned to users
area: planning
files:
  - .planning/phases/07-automation/07-05-PLAN.md
  - .planning/phases/07-automation/07-CONTEXT.md
  - .planning/quick/260828-fjc-role-reference-db/DESIGN.md
  - scripts/Import-AxoniousExport.ps1
  - scripts/Publish-RoleSnapshot.ps1
  - scripts/Reconcile-LocalRoles.ps1
  - Existing Dashboards/fixlet_role_admin.ojo
  - config/GroupRoleMap.json
---

## Problem

The user wants to change the model for assigning roles to users. Phase 7 as currently built
(5/6 plans done, all green against fixtures/mocks) implements this pipeline:

- `Import-AxoniousExport.ps1` reads the daily Axonius export into `AutomationState.db` on the
  BES root server, resolving each user's AD groups through `GroupRoleMap` rules into roles.
- `Publish-RoleSnapshot.ps1` writes one compact per-region snapshot JSON to the Custom
  Repository and re-PUTs a per-region policy Fixlet daily.
- Endpoints self-select by their own `GPC_Sub_Name` setting, prefetch
  `roleref-<region>-latest.json`, and `Reconcile-LocalRoles.ps1` writes the local
  `RoleAwareness.db` `Map` table with `Assigned_By = AxoniousSync`.
- Role follows the **user** (console user), not the machine. No `ComputerID` in the pipeline.
  No revoke — only `Valid_to` age-out.
- `fixlet_role_admin.ojo` is the operator console for authoring `GroupRoleMap` rules and
  publishing regions one at a time.

Key existing decisions this rework touches: D-02 (no ComputerID), D-11 (snapshot shape with
provenance objects), D-18 (endpoint `Map` migration), D-21 (13-value Region seed),
`GroupRoleMap.json` ships empty as a go-live gate, console-user-only reconcile in v1.

This todo is the reason Phase 7 is paused at the 07-05 blocking human checkpoint — see
`.planning/phases/07-automation/.continue-here.md`.

## Solution

TBD — to be worked with the user in a fresh context. Define the new assignment model, then
decide the impact on Phase 7:

- If the change is small (e.g. only the console-user relevance / `ConsoleUserRelevance`
  seam, or a `GroupRoleMap` authoring-flow tweak): fold it into the 07-05 production run and
  proceed.
- If the change reshapes ingest, snapshot distribution, or the endpoint reconcile: run
  `/gsd:discuss-phase 07` then `/gsd:plan-phase 07 --gaps` to replan 07-02 / 07-04 / 07-05
  against the new model before any production verification.

Do not run the 07-05 Task 4 production-fleet verification until this is decided.




=======
What was saved
File	Purpose
.planning/HANDOFF.json	Machine-readable pause state for /gsd:resume-work
.planning/phases/07-automation/.continue-here.md	Human handoff — where 07-05 stands, why it's paused, the Task 4 checklist, required reading
.planning/STATE.md	status: paused; In Progress / Next Steps / Pending Todos updated
memory role-reference-db-redesign.md	Appended a dated "PAUSED 2026-09-09" note
Todos added (.planning/todos/pending/)
260909-rework-role-assignment-approach.md — your next task: decide the new model for assigning roles to users, then decide whether Phase 7 (07-02 publish / 07-04 GroupRoleMap editor / 07-05 checkpoint) needs a --gaps replan or just proceeds. This blocks the 07-05 checkpoint.
260909-phase-07-05-production-fleet-verification.md (resolves_phase: 07) — the five production-fleet verifications still owed (A1 console-user identity, D-21 live GPC_Sub_Name values, task 787 redeploy, A2 prefetch reach, one-region pilot) plus root-server prereqs. Points at 07-05-UAT-CHECKLIST.md.
Where Phase 7 actually is
5/6 plans done and green. 07-05 Tasks 1–3 are committed (23b22aa, 286e6de, 2b05502) — the -WhatIf audit harness, the operator run-book, and the UAT checklist — with the whole estate green (245 Pester excl. Slow, 9 Node suites, 6 integration suites in skip mode). Only Task 4, the blocking human checkpoint, remains. 07-05-SUMMARY.md is not written and the phase is not marked complete, so re-running /gsd:execute-phase 7 later will pick up exactly at 07-05.

Note: .planning/config.json still shows as modified — that's a pre-existing change, untouched and not part of this commit.

