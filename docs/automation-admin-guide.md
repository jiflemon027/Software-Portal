# Dereso Automation Pipeline — Admin Guide

> **2026-09-21: the Axonius reference-DB role pipeline was retired**, replaced by the
> Operator-Role-Group model (D-14/D-15, `.planning/phases/07-automation/07-CONTEXT.md`).
> Its scripts, dashboards, `.bes` template and config live on for reference only under
> `scripts/archive/`, `Existing Dashboards/archive/`, `bes/archive/` and
> `config/archive/` — see `tests/archive/README.md` for the full move list. **This guide
> now covers the content pipeline only.** For the live role pipeline, see
> `docs/role-manager-admin-guide.md`.

## Overview

Phase 7 turns the manual "copy a fixlet, assign a role, deploy it" workflow into
scheduled loops that run unattended on the BigFix **root server**. There is no new UI to
learn to keep the content pipeline running — once the loops are enabled they run on
Windows Scheduled Tasks — but there *is* a one-time setup. This document is the run-book
for the content pipeline; the role pipeline (its own dashboard, its own one-time setup,
its own drift-check job) has its own guide.

### The content loops

| Loop | Where it runs | Trigger | What it does |
|------|---------------|---------|---------------|
| **Content sync** — `Invoke-ContentSync.ps1` | root server | weekly (`DeresoContentSync`) | Scans the configured source sites for newer / newly-arrived product fixlets, records them as `discovered` ContentItems, and — only for items an operator advanced to `stage = 'ready'` — performs the 4-step copy into the portal site and stamps the superseded item with `X-Superseded-By`. Chains the staging task on success. |
| **Repository stage** — `Stage-Repository.ps1` | root server | on demand, chained from a successful content sync (`DeresoRepoStage`) | Downloads each copied fixlet's `prefetch` installer from its **original** URL, SHA1- and byte-length-verifies it, and places a match under `…\Uploads\CustomRepository\SoftwarePortal\<sha1>\<file>`. A mismatch is always discarded, never staged. |

### Role pipeline (short version — see `docs/role-manager-admin-guide.md`)

An admin maintains a flat username list per role in `Existing Dashboards/fixlet_role_manager.ojo`.
Publishing a role (re)generates that role's automatic Computer Group ("exactly one of
the role's usernames is currently logged on") and (re)deploys a policy action that
upserts `RoleAwareness.db`. A daily drift-check job, `DeresoRoleGroupSync`, re-syncs each
role's group relevance against the root-server `RolePublish.db` audit store — a
**different file** from this guide's `AutomationState.db`. Full detail, including the
one-time setup (importing the Analysis, redeploying task 787, staging the endpoint
script) and the Known Limitations an operator needs to know, lives in
`docs/role-manager-admin-guide.md`.

---

## Prerequisites

Tick every box on the **root server** before enabling anything. `PipelineConfig` holds
**paths and tuning values only — never a secret**.

- [ ] **`sqlite3.exe` 3.53.1** is present at the directory named by `PipelineConfig.SQLDir`
      (default `C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite`), *directly*
      in that folder (no `x64\` / `x86\` subfolder). The tools zip SHA1 is
      `184d4d0b75cd75c2118fb22a1727e9220f843b98`; it is the same build already prefetched
      to endpoints by task 787. `Initialize-AutomationDb.ps1` exits with error `6000`
      and the full remediation text if it is missing.
- [ ] **The root server is enrolled as a managed BES client.** `fixlet_automation_monitor.ojo`'s
      Status tab reads `AutomationState.db` through a client-relevance Analysis on the
      root server (RESEARCH A3). If it is not a managed client, that tab has no data
      source.
- [ ] **The AKeyless secret exists.** `PipelineConfig.AKeylessSecretPath` defaults to
      `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator`. Confirm the secret exists and
      that **Cyera's existing universal identity is authorised to read it** (RESEARCH A4).
      `Get-BigFixCredential.ps1` fails loud (Event 8001, class `secret-empty`) if the path
      returns nothing. This is shared by every root-server script that talks to the BigFix
      REST API, content pipeline and role drift-check alike.
- [ ] **Egress to `api.akeyless.io` (HTTPS) is open** from the root server. This is a hard
      dependency with no fallback.
- [ ] **A scoped BigFix operator service account** has been chosen, scoped to **only** the
      `Dereso Software Portal` site and the target computer groups, and its username
      recorded in `PipelineConfig.BESOperatorUser`. Its password lives at the AKeyless
      secret path above — never in `PipelineConfig`, never on disk.
- [ ] **PowerShell 7 (`pwsh.exe`) is installed**, or you have accepted the PowerShell 5.1
      path (RESEARCH A5). Every root-server script prefers `pwsh.exe` and falls back to
      `powershell.exe`; `Register-AutomationTasks.ps1` records which it used in the exported
      task XML. Under 5.1 the BigFix REST calls fall back to a `ServicePointManager`
      certificate callback instead of `-SkipCertificateCheck`.
- [ ] **`.vault-token` is present** at `PipelineConfig.AKeylessTokenFile`
      (`…\BES Client\EC\Cyera\.vault-token`). It is **Cyera's** — RoleSync/content scripts
      only ever read it. Cyera's rotator (~2-hourly) is the sole writer.

---

## Step 1 — Initialise `AutomationState.db`

```powershell
pwsh -File scripts\Initialize-AutomationDb.ps1 `
  -DatabasePath "C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db" `
  -SQLDir      "C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite"
```

The script is idempotent — a second run reports `[SKIP]` for every object. After it
completes, verify:

- **The `PipelineConfig` seed** — 7 keys from `config\PipelineConfig.defaults.json`, none
  holding a secret value.
- **The Windows Event Log source `DereseSoftwarePortal`** is registered (needs admin,
  once). Every root-server script logs failures to `Application` with Event IDs in the
  **8000–8099** range; without the source, `Write-EventLog` throws and failures become
  invisible.

The 11-table schema also still creates and seeds `Role`/`Region`/`GroupRoleMap`/`RefUser`/`UserRole`/`RolePublication`/`Snapshot` — these are the retired role pipeline's own tables, kept only because dropping tables from a live database is destructive and out of the 2026-09-21 rewrite's scope (07-CONTEXT.md decision 2). No live script writes to them any more; do not seed or edit them expecting any effect.

Run it with `-WhatIf` first if you want to see the full plan without writing anything.

---

## Step 2 — Dry run

1. **Audit every root-server script at once:**
   ```powershell
   pwsh -File scripts\Invoke-WhatIfAudit.ps1
   ```
   Every one of the six live scripts (`Initialize-AutomationDb.ps1`,
   `Get-BigFixCredential.ps1`, `Invoke-ContentSync.ps1`, `Stage-Repository.ps1`,
   `Register-AutomationTasks.ps1`, `Sync-RoleGroups.ps1`) must report `PASS` (zero file
   writes, zero DB writes, zero mutating REST / scheduled-task calls) **and** produce its
   run-audit record. Run this on the *actual root server*, not only on a dev host.
2. **Dry-run a content sync** and read the JSON log under `…\SoftwarePortal\logs\`:
   ```powershell
   pwsh -File scripts\Invoke-ContentSync.ps1 -WhatIf -DatabasePath "...\AutomationState.db" -SQLDir "...\sqlite"
   ```
   Confirm the plan names the source sites it would scan and that nothing gets written.

---

## Step 3 — Register the scheduled tasks

```powershell
pwsh -File scripts\Register-AutomationTasks.ps1 `
  -DatabasePath "...\AutomationState.db" -SQLDir "...\sqlite" -LogDir "...\SoftwarePortal\logs"
```

This registers three root-server tasks (SYSTEM, Highest) and re-exports each to
`config\task-<Name>.xml`:

| Task | Script | Schedule | Notes |
|------|--------|----------|-------|
| **`DeresoContentSync`** | `Invoke-ContentSync.ps1` | Weekly | Records `discovered` items and copies only `stage = 'ready'` ones. `-AutoApprove` is OFF. |
| **`DeresoRepoStage`** | `Stage-Repository.ps1` | On demand | Started only by a successful `DeresoContentSync`. |
| **`DeresoRoleGroupSync`** | `Sync-RoleGroups.ps1` | Daily 04:00 | The role pipeline's D-06 drift check (see `docs/role-manager-admin-guide.md`). Reads `RolePublish.db`, **not** `AutomationState.db` — a different file, passed via a different parameter, on purpose. |

**Importable fallback:** the three `config\task-*.xml` files are valid Task Scheduler 1.2
XML. If the programmatic registration is not an option on your root server, import them
with `schtasks /Create /XML config\task-DeresoContentSync.xml /TN DeresoContentSync` (and
the other two). They carry the script's default parameter paths — edit the `<Arguments>`
line if your install layout differs.

---

## Configuring — `PipelineConfig` keys

Every row is `Key / Value / Description`. Edit values through the
`fixlet_automation_monitor.ojo` **Config** tab (which writes via a SingleAction to the
root-server client) or directly on the root server. The `AKeyless*` keys are **paths, not
secrets** — the dashboard shows them as PATH-ONLY, never a password field.

`config/PipelineConfig.defaults.json` carries exactly these **7** keys. The six retired, Axonious-only keys (`AxoniousExportPath`, `MaxExportAgeDays`, `SnapshotOutputDir`, `SnapshotUrlBase`, `UsernameSourcePriority`, `ConsoleUserRelevance`) were removed 2026-09-21 along with the pipeline that read them:

| Key | Meaning | Default | Blast radius if wrong |
|-----|---------|---------|-----------------------|
| `BESRootUrl` | BigFix REST base URL for root-server scripts. | `https://localhost:52311` | Wrong = fixlet `PUT` and `/api/query` fail. |
| `AKeylessTokenFile` | Path to Cyera's `.vault-token` (read-only). | `…\BES Client\EC\Cyera\.vault-token` | Missing/stale = every root script fails at credential fetch (Event 8001, class `token-file-missing`). |
| `AKeylessSecretPath` | AKeyless path of the operator password. | `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` | Wrong path returns empty → Event 8001 class `secret-empty`. |
| `BESOperatorUser` | Username of the scoped operator service account. | *(empty)* | Empty or over-scoped = policy-Fixlet / Computer Group `PUT` fails or has more authority than it should. |
| `ValidityMonths` | How far forward a reconciled `Map.Valid_to` is pushed. | `6` | Too short = roles lapse before the next reconcile on a host nobody logs off. |
| `SQLDir` | Directory holding `sqlite3.exe` directly. | `…\BES Client\EC\sqlite` | Missing `sqlite3.exe` = `Initialize-AutomationDb.ps1` error `6000`. |
| `AlertWebhook` | Optional failure-alert webhook. | *(empty = off)* | — |

Two additional, **content-pipeline-only** keys are read if present but are *not* seeded
by default — add them to opt in:

| Key | Meaning | Internal default when absent |
|-----|---------|-------------------------------|
| `MaxStageFileMB` | **Disk brake.** `Stage-Repository.ps1` logs and skips any prefetch file larger than this. | `4096` |
| `ContentSourceSites` | Comma-separated source sites the content pipeline scans. Seeded on first `Invoke-ContentSync.ps1` run from the `fixlet_update_tracker.ojo` list. | *(seeded on first run)* |

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `DeresoContentSync` runs but discovers nothing | `PipelineConfig.ContentSourceSites` is empty or names the wrong sites | Confirm the key via the `fixlet_automation_monitor.ojo` Config tab; it self-seeds from `fixlet_update_tracker.ojo`'s list on first run only. |
| A copied fixlet's installer never stages | `Stage-Repository.ps1` discarded a SHA1 or byte-length mismatch against the original URL (this is by design, not a bug — T-07-03-01) | Check the day's JSON log under `…\SoftwarePortal\logs\`; if the mismatch is a false positive, verify the source URL is serving the expected file. |
| A large installer is silently skipped | It exceeds `PipelineConfig.MaxStageFileMB` (default 4096, not seeded) | Raise the key if the file is legitimate, or leave it — this is the disk-fill brake working as intended. |
| Scheduled runs fail with nothing in the Application event log | The `DereseSoftwarePortal` Event Log source is not registered | Re-run `Initialize-AutomationDb.ps1` as an admin once — it registers the source (`New-EventLog`) if `SourceExists` is false. |
| `fixlet_automation_monitor.ojo`'s Status tab is empty while `SyncRun` clearly has rows on disk | The dashboard can only make BigFix API calls — it reads `AutomationState.db` through a client-relevance Analysis on the root server, which is not reporting | Confirm the root server is an enrolled managed BES client and that the `AutomationState.db` Analysis property bodies have been published and evaluated at least once (up to 5 min). |
| `DeresoRoleGroupSync` fails or behaves unexpectedly | This is the role pipeline's own drift-check job | See `docs/role-manager-admin-guide.md`'s Troubleshooting section, not this guide. |

---

## File Reference

### Root-server scripts (`scripts\`)

| File | Purpose |
|------|---------|
| `Initialize-AutomationDb.ps1` | Creates `AutomationState.db` (11 tables — 9 are the retired role pipeline's own, kept unused per decision 2), seeds `Region` (13) / `Role` (3, unused) / `PipelineConfig` (7), registers the `DereseSoftwarePortal` Event Log source, preflights `sqlite3.exe`. |
| `Get-BigFixCredential.ps1` | Returns the operator `[pscredential]` from AKeyless via Cyera's universal identity. No secret at rest. Shared by the content pipeline and the role drift-check. |
| `Invoke-ContentSync.ps1` | Weekly source-site scan → `discovered` ContentItems → operator-gated 4-step copy → `X-Superseded-By` stamp → chains `DeresoRepoStage`. |
| `ContentSyncCore.psm1` | Pure content-pipeline functions (`Get-StrippedName`, `Compare-FixletVersion`, `New-SupersededXml`, `Read-PrefetchLine`, …). |
| `Stage-Repository.ps1` | Downloads + SHA1/size-verifies each copied fixlet's prefetch installer into `…\CustomRepository\SoftwarePortal\<sha1>\<file>`. Discards any mismatch. |
| `Register-AutomationTasks.ps1` | Registers the three root-server scheduled tasks from one append-only table and exports each to `config\task-<Name>.xml`. |
| `Invoke-WhatIfAudit.ps1` | One command that dry-runs all six live root-server scripts and proves zero side effects, plus a source scan for forbidden constructs. Run it during Step 2 and on the real root server. |
| `RoleGroupRelevance.psm1`, `Sync-RoleGroups.ps1` | The role pipeline's `DeresoRoleGroupSync` drift-check driver — registered by the same `Register-AutomationTasks.ps1` table above. Full detail in `docs/role-manager-admin-guide.md`. |

### `.bes` files (`Dashboard_4_samples\`)

| File | Purpose |
|------|---------|
| `Init  Current User and UserRole DB.bes` | **Task 787.** Endpoint init + `Map` migration + registers `RoleDB_Maintenance`. Role-pipeline infrastructure — see `docs/role-manager-admin-guide.md`. |
| `Dereso SWD.bes` | Analysis feeding the role pipeline's Analysis tab (`map_source in r.db` / `map_region in r.db` over the migrated `Map` columns). |

### Config (`config\`)

| File | Purpose |
|------|---------|
| `PipelineConfig.defaults.json` | The 7 documented seed keys. No secret values. |
| `task-DeresoContentSync.xml` | Export for `DeresoContentSync`. |
| `task-DeresoRepoStage.xml` | Export for `DeresoRepoStage`. |
| `task-DeresoRoleGroupSync.xml` | Export for `DeresoRoleGroupSync` (role pipeline). |

### Dashboards (`Existing Dashboards\`)

| File | Purpose |
|------|---------|
| `fixlet_automation_monitor.ojo` | Content-pipeline only: Status, Content Queue (approve/reject), Repository Cache (unverified-hash signal), `PipelineConfig` editor. No role controls. |
| `fixlet_role_manager.ojo` | The role pipeline's one live dashboard — see `docs/role-manager-admin-guide.md` for full detail. |

### Scheduled tasks

| Task | Tier | Trigger |
|------|------|---------|
| `DeresoContentSync` | root server | Weekly |
| `DeresoRepoStage` | root server | On demand (chained) |
| `DeresoRoleGroupSync` | root server | Daily 04:00 |
