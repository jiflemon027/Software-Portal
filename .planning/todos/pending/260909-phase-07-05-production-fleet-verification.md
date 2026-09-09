---
created: 2026-09-09T14:20:10.269Z
title: Phase 7-05 production-fleet verification and pilot sign-off
area: planning
resolves_phase: "07"
files:
  - .planning/phases/07-automation/07-05-UAT-CHECKLIST.md
  - .planning/phases/07-automation/07-05-PLAN.md
  - docs/automation-admin-guide.md
  - .planning/phases/07-automation/07-VALIDATION.md
---

## Problem

Plan 07-05 Tasks 1–3 are committed (`23b22aa`, `286e6de`, `2b05502`) and the whole Phase 7
automated estate is green (245 Pester excl. Slow, 9 Node suites, 6 integration suites in skip
mode, `Invoke-WhatIfAudit.ps1` PASS for all 8 scripts + working negative control).

Task 4 is a **blocking `human-verify` checkpoint**. Five behaviours cannot be verified without
the production BigFix fleet (`gpbfs`, ~40k endpoints) — the MCP-connected server is a
nine-computer lab. Until Task 4 is signed off, `07-05-SUMMARY.md` is not written, phase
verification does not run, and Phase 7 is not marked complete.

NOTE: hold this until `260909-rework-role-assignment-approach.md` is settled — a change to the
assignment model could require replanning 07-02/07-04/07-05 first.

## Solution

Work `.planning/phases/07-automation/07-05-UAT-CHECKLIST.md` in order on the production fleet,
recording each outcome in that file. Then reply "approved" to the paused execution (or re-run
`/gsd:execute-phase 7`).

Outstanding items:

- [ ] Root-server Prerequisites (guide): `sqlite3.exe` 3.53.1 (sha1
      `184d4d0b75cd75c2118fb22a1727e9220f843b98`) at `PipelineConfig.SQLDir`; AKeyless secret
      `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` + egress to `api.akeyless.io`;
      scoped BigFix operator account in `PipelineConfig.BESOperatorUser`; Axonius export at
      `PipelineConfig.AxoniousExportPath`.
- [ ] Run `scripts/Invoke-WhatIfAudit.ps1` on the actual root server — all 8 scripts pass.
- [ ] **A1** console-user identity: `name of current user` == known lowercased SAM on ≥3
      pilot endpoints. On fail: set `PipelineConfig.ConsoleUserRelevance`, re-run
      `Publish-RoleSnapshot.ps1`, re-test. Highest-risk item — STOP the rollout on fail.
- [ ] **D-21** live `GPC_Sub_Name` values across the fleet vs the 13 seeds incl. spelling and
      case; correct the `Region` table before publishing any affected region.
- [ ] Author the first `GroupRoleMap` rules (guide Step 2 + Test Pattern field); confirm
      per-role counts on the Reference DB tab are plausible.
- [ ] **787** redeploy BigFix task 787 (`Init  Current User and UserRole DB.bes`); confirm
      `RoleDB_Maintenance` runs BOTH `Initialize-RoleDb.ps1` and `Reconcile-LocalRoles.ps1`
      on one already-provisioned endpoint (unregister-then-reregister took — Pitfall 5).
- [ ] **A2** publish ONE pilot region; a non-root endpoint downloads
      `roleref-<region>-latest.json`; record whether `127.0.0.1:52311` worked or the
      relay-qualified / `Invoke-WebRequest` fallback was needed.
- [ ] **Pilot** a real user's role in `RoleAwareness.db` `Map` with `Assigned_By=AxoniousSync`,
      future `Valid_to`, populated `Source_Value`, `Region` matching the endpoint; a
      `Locked_by_Override=1` row unchanged; `roleref_<region>_applied` setting written;
      `fixlet_modifier.ojo` / `fixlet_console.ojo` / SSA role panel still read roles.
- [ ] Confirm exactly one region enabled; content pipeline still `-WhatIf` or live with
      auto-approve OFF.
- [ ] On sign-off: record every outcome in `07-05-UAT-CHECKLIST.md`, then resume execution so
      `07-05-SUMMARY.md` is written and the phase is verified + completed.
