# Pester test suite (Phase 7)

PowerShell unit tests for the Phase 7 root-server and endpoint scripts.

## Pester version

**Pester 5 only.** Always load it pinned:

```powershell
Import-Module Pester -MinimumVersion 5.0
```

The dev host also has the legacy Pester 3.4.0 side-by-side; it must never be the one
that loads. Every command below assumes 5.x.

Developed against **Pester 5.7.1**.

## Running

```powershell
# one suite
Invoke-Pester tests/pester/Initialize-AutomationDb.Tests.ps1 -Output Detailed

# the whole Pester folder (CI form)
Invoke-Pester -Path tests/pester -CI
```

`-CI` sets a non-zero exit code on failure so it can gate a commit.

## sqlite3.exe — the `SQLDIR` contract

The DB-backed suites shell out to `sqlite3.exe` through
`Dashboard_4_samples/Sqlite-Helper.ps1`. Each suite locates it in this order and uses
the first hit:

1. `$env:SQLDIR`  (set this to the directory that contains `sqlite3.exe` directly — no
   `x64\` / `x86\` arch subfolder)
2. `C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite`
3. `C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\sqlite`
4. `sqlite3.exe` on `PATH` (`Get-Command sqlite3.exe`)

Pinned build: **3.53.1**, tools zip sha1 `184d4d0b75cd75c2118fb22a1727e9220f843b98`
(from the BES `sqlite_util` CustomRepository).

If none of the probes resolve, the DB-backed `Describe`/`Context` blocks are **skipped,
not failed**, so the suite still exits 0 on a host without sqlite3.exe. To exercise them
locally, set `SQLDIR` first:

```powershell
$env:SQLDIR = 'C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite'
Invoke-Pester -Path tests/pester -CI
```

## The 420 MB export is out of scope for CI

Any test that touches `SampleAxonious/axonius-users_anond.csv` (or `axonious.db`) must be
tagged `-Tag Slow` and is excluded from normal / CI runs:

```powershell
Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI      # default
Invoke-Pester -Path tests/pester -Tag Slow                  # opt-in, local only
```

`SampleAxonious/` is `.gitignore`d (PII + size). Small carved fixtures live in
`tests/fixtures/phase-07/` instead.

## Suites

| Suite | Covers |
|-------|--------|
| `Initialize-AutomationDb.Tests.ps1` | `scripts/Initialize-AutomationDb.ps1` — 11-table schema, Region(13)/Role(3)/PipelineConfig(7) seeds, idempotent re-run, `-WhatIf` writes nothing |
| `Get-BigFixCredential.Tests.ps1` | `scripts/Get-BigFixCredential.ps1` (Invoke-RestMethod mocked) — pscredential shape, four failure modes, `-WhatIf` zero calls, source scan proving the secret never leaks; plus the `Register-AutomationTasks.ps1` Wave 0 skeleton |
| `Initialize-RoleDb.Tests.ps1` | the D-18 `Map` migration in `Dashboard_4_samples/Initialize-RoleDb.ps1` — adds 4 columns idempotently, preserves rows + lock state |
| `InitCurrentUserTask.Tests.ps1` | the D-18 hard-prerequisite rewire of task 787 (`Dashboard_4_samples/Init  Current User and UserRole DB.bes`) — retired-pipeline wiring stripped, `RoleDB_Maintenance` collapsed to a single action |
| `Invoke-ContentSync.Tests.ps1` | `scripts/Invoke-ContentSync.ps1` — the content pipeline's discover/copy driver |
| `Stage-Repository.Tests.ps1` | `scripts/Stage-Repository.ps1` — installer prefetch download + SHA1 verify into the Custom Repository |
| `Upsert-RolePublish.Tests.ps1` | `scripts/Upsert-RolePublish.ps1` — the D-05 append-only `RolePublishRun`/`RoleUsers` audit-store writer |
| `Sync-RoleGroups.Tests.ps1` | `scripts/RoleGroupRelevance.psm1` + `scripts/Sync-RoleGroups.ps1` — the D-06 periodic drift-check driver (golden-file relevance conformance, wrong-database guard, mocked-REST drift detection/correction, `-WhatIf` contract) |
| `WhatIfAudit.Tests.ps1` | `scripts/Invoke-WhatIfAudit.ps1` — the phase-wide `-WhatIf` zero-side-effect audit across the six live Phase 7 root-server scripts, plus the source scan and its own negative control |

`Assert-SnapshotShape.ps1` is a **dot-sourced helper, not a suite** — the single
definition of `Assert-RoleRefSnapshotShape` shared by 07-00 and 07-02.

**Retired suites:** the Axonius reference-DB pipeline's own test suites (`AxoniousParse.Tests.ps1`,
`GroupRoleMap.Tests.ps1`, `Import-AxoniousExport.Tests.ps1`, `Publish-RoleSnapshot.Tests.ps1`,
`Reconcile-LocalRoles.Tests.ps1`, `RoleRefPolicyBes.Tests.ps1`) were archived 2026-09-21 along
with the scripts they cover — see `tests/archive/README.md` for what moved, where, and their
last recorded pass/fail outcome. They are frozen, not maintained, and excluded from this
folder's default `Invoke-Pester -Path tests/pester` run by construction (they no longer live
here).

## Fixtures (`tests/fixtures/phase-07/`)

| File | Purpose |
|------|---------|
| `automation-db-schema.sql` | full 11-table DDL for spinning up a throwaway `AutomationState.db` in one call |
| `roleawareness-v2.db` | pre-migration endpoint DB (v2 `Map` schema, 4 rows incl. one `Locked_by_Override=1`, WAL checkpointed, no `-wal`/`-shm` sidecar) |
| `axonious-sample-50.csv` | ~44-row carve of the anonymised export: UTF-8 BOM, blank-SAM rows, a blank SAM+UPN row, a quoted 3-line group cell, an LDAP-DN group and a bare display-name group, all 47 headers |
| `axonious-multivalue-edge.csv` | D-07 loose-alignment cases: 3/2/4 mismatched multi-value counts, a blank middle slot, an email on one group only (Mailing List vs AD Security Group), and a zero-groups user |
| `grouprolemap-seed.json` | synthetic `GroupRoleMap` rules — cn exact, cn `*`-wildcard, display, dn, an `Active=0` rule, and two rules mapping the same group to two roles |
| `roleref-AAG-UK-sample.json` | extended-D-11 region snapshot; `users` are objects `{ id, source_type, source_value }`; includes a pipe-joined `source_value`, a `Mailing List` and an `AD Security Group` source, and the role `Contract Support` which is absent from a stock `RoleAwareness.db` (exercises the 07-02 `INSERT OR IGNORE INTO Roles` path). Deliberately ABSENT user: **`ktanaka`** — no role block references her; that is the normal General-Access default and 07-02's reconcile must treat it as a clean success, never an error. There is no `General Access` role block (General Access is never enumerated in a snapshot). |
