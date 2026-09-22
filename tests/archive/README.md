# Archived test suites (frozen historical snapshots)

**Archived:** 2026-09-21, as part of the Phase 7 Operator-Role-Group rewrite (see
`.planning/phases/07-automation/07-CONTEXT.md`, decisions D-14/D-15).

These suites cover the retired **Axonius reference-DB pipeline** — the *daily Axonius
export → reference DB → per-region snapshot → endpoint reconcile* design that was rejected
on 2026-09-21 in favor of the simpler Operator-Role-Group model (a flat per-role username
list, one Computer Group + one policy action per role, no ComputerID matrix, no reference
DB, no snapshot files, no Axonius). None of the retired pipeline was ever run against
production (the old-model 07-05 human-verify checkpoint never executed).

**These are frozen historical snapshots. They are deliberately excluded from the default
test run** — `Invoke-Pester -Path tests/pester` and `node tests/unit/*.test.js` (run
file-by-file or via any wrapper that globs `tests/unit`) do not discover anything under
`tests/archive/`, because it sits outside both of those default search roots.

## Where their subjects now live

| Archived suite | Subject | Subject's new location |
|---|---|---|
| `unit/role_admin.test.js` | `fixlet_role_admin.ojo` | `Existing Dashboards/archive/fixlet_role_admin.ojo` |
| `unit/role_assigner.test.js` | `fixlet_role_assigner.ojo` | `Existing Dashboards/archive/fixlet_role_assigner.ojo` |
| `pester/AxoniousParse.Tests.ps1` | `AxoniousParse.psm1` | `scripts/archive/AxoniousParse.psm1` |
| `pester/GroupRoleMap.Tests.ps1` | `AxoniousParse.psm1` (`Resolve-Roles`) | `scripts/archive/AxoniousParse.psm1` |
| `pester/Import-AxoniousExport.Tests.ps1` | `Import-AxoniousExport.ps1` | `scripts/archive/Import-AxoniousExport.ps1` |
| `pester/Publish-RoleSnapshot.Tests.ps1` | `SnapshotBuild.psm1` + `Publish-RoleSnapshot.ps1` | `scripts/archive/SnapshotBuild.psm1`, `scripts/archive/Publish-RoleSnapshot.ps1` |
| `pester/Reconcile-LocalRoles.Tests.ps1` | `Reconcile-LocalRoles.ps1` + `config/task-DeresoRole{Ingest,Publish}.xml` | `scripts/archive/Reconcile-LocalRoles.ps1`, `config/archive/task-DeresoRole{Ingest,Publish}.xml` |
| `pester/RoleRefPolicyBes.Tests.ps1` | `RoleRef-Policy-template.bes` + `Publish-RoleSnapshot.ps1` | `bes/archive/RoleRef-Policy-template.bes`, `scripts/archive/Publish-RoleSnapshot.ps1` |
| `pester/Assert-SnapshotShape.ps1` | (dot-sourced helper, not a suite — the shared extended-D-11 snapshot-shape contract) | stays alongside the other archived Pester suites; no live consumer remains |

`config/GroupRoleMap.json` also archived to `config/archive/GroupRoleMap.json` (read
directly by `unit/role_admin.test.js`, not via a dedicated suite).

Every suite above still resolves its shared fixtures from the **live**
`tests/fixtures/phase-07/` directory — the fixtures were not moved (they are small, and
moving them would break both these frozen snapshots and Phase 7's live
`RoleGroupRelevance.psm1`/`role_manager.test.js` cross-language golden-fixture contract for
no benefit).

## Not maintained

These suites are **reference material only** and are **not maintained**. They were
re-based (one extra `..` repo-root segment, plus their subject/cross-reference paths
updated to the `archive/` locations above) so each can still locate its own subject and
fixtures from its new depth, and each was run once after the move to record its outcome —
see `.planning/phases/07-automation/07-10-SUMMARY.md` for the per-suite pass/skip/fail
results. No future change to the live codebase is expected to keep these suites green, and
no CI gate depends on them.

If you are looking for the **live** role-pipeline test coverage, see
`tests/unit/role_manager.test.js` and `tests/pester/Sync-RoleGroups.Tests.ps1` /
`tests/pester/Upsert-RolePublish.Tests.ps1` / `tests/pester/InitCurrentUserTask.Tests.ps1`
instead — those cover the current Operator-Role-Group model.
