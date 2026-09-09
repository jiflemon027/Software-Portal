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
