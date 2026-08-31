# Dereso Automation Pipeline — Admin Guide

## Overview

Phase 7 turns the manual "copy a fixlet, assign a role, deploy it" workflow into five
scheduled loops that run unattended on the BigFix **root server** and on managed
**endpoints**. There is no new UI to learn to keep it running — once the loops are
enabled they run on Windows Scheduled Tasks — but there *is* a one-time setup, a
per-region rollout order, and a redeploy of an already-live task. This document is the
run-book for all three.

### The three role loops

| Loop | Where it runs | Trigger | What it does |
|------|---------------|---------|--------------|
| **Ingest** — `Import-AxoniousExport.ps1` | root server | daily (`DeresoRoleIngest`) | Streams the Axonius user export into `AutomationState.db`: one lowercased match key per user, entitlements resolved through the operator-authored `GroupRoleMap` rules, departed members marked `Active = 0` (never deleted). |
| **Publish** — `Publish-RoleSnapshot.ps1` | root server | daily, after ingest (`DeresoRolePublish`) | For each *published* region, writes `roleref-<region>-latest.json` + a `.sha1` manifest into the Custom Repository and re-`PUT`s that region's policy Fixlet so its `prefetch` line always names today's hash. |
| **Reconcile** — `Reconcile-LocalRoles.ps1` | every endpoint | the per-region policy action **and** the `RoleDB_Maintenance` logon task | Reads the prefetched region snapshot, re-checks the region, and upserts the **current console user's** roles into the endpoint's `RoleAwareness.db` `Map` table with `Assigned_By = 'AxoniousSync'`. |

### The two content loops

| Loop | Where it runs | Trigger | What it does |
|------|---------------|---------|--------------|
| **Content sync** — `Invoke-ContentSync.ps1` | root server | weekly (`DeresoContentSync`) | Scans the configured source sites for newer / newly-arrived product fixlets, records them as `discovered` ContentItems, and — only for items an operator advanced to `stage = 'ready'` — performs the 4-step copy into the portal site and stamps the superseded item with `X-Superseded-By`. Chains the staging task on success. |
| **Repository stage** — `Stage-Repository.ps1` | root server | on demand, chained from a successful content sync (`DeresoRepoStage`) | Downloads each copied fixlet's `prefetch` installer from its **original** URL, SHA1- and byte-length-verifies it, and places a match under `…\Uploads\CustomRepository\SoftwarePortal\<sha1>\<file>`. A mismatch is always discarded, never staged. |

### Two facts that surprise people

1. **Role assignment follows the *user*, not the *machine*.** There is no
   user→ComputerID resolution anywhere. An endpoint decides which snapshot applies to it
   from its own `GPC_Sub_Name` client setting; the reconcile only ever writes rows for
   whoever is at the console.
2. **Up to ~24 hours of propagation delay is by design.** Ingest is daily, publish is
   daily, and an endpoint reconciles on the next policy-action evaluation or the next
   logon. A newly-granted role is not instant, and a *removed* role is not revoked — it
   simply stops being renewed and lapses at `Valid_to` (see **Known Limitations**).

---

## Prerequisites

Tick every box on the **root server** before enabling anything. `PipelineConfig` holds
**paths and tuning values only — never a secret**.

- [ ] **`sqlite3.exe` 3.53.1** is present at the directory named by `PipelineConfig.SQLDir`
      (default `C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite`), *directly*
      in that folder (no `x64\` / `x86\` subfolder). The tools zip SHA1 is
      `184d4d0b75cd75c2118fb22a1727e9220f843b98`; it is the same build already prefetched
      to endpoints by the init task. `Initialize-AutomationDb.ps1` exits with error `6000`
      and the full remediation text if it is missing.
- [ ] **The root server is enrolled as a managed BES client.** The dashboards read
      `AutomationState.db` through a client-relevance Analysis on the root server
      (RESEARCH A3). If it is not a managed client, the `fixlet_role_admin.ojo` Reference
      DB tab and the `fixlet_automation_monitor.ojo` Status tab have no data source.
- [ ] **The AKeyless secret exists.** `PipelineConfig.AKeylessSecretPath` defaults to
      `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator`. Confirm the secret exists and
      that **Cyera's existing universal identity is authorised to read it** (RESEARCH A4).
      `Get-BigFixCredential.ps1` fails loud (Event 8001, class `secret-empty`) if the path
      returns nothing.
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
      (`…\BES Client\EC\Cyera\.vault-token`). It is **Cyera's** — RoleSync only ever reads
      it. Cyera's rotator (~2-hourly) is the sole writer.
- [ ] **The daily Axonius export** is being delivered to the path named by
      `PipelineConfig.AxoniousExportPath` (empty until you set it).
- [ ] **The `role_db/` scratch folder** on the root server is `.gitignore`d local working
      state only — nothing reads it in production.

---

## Step 1 — Initialise `AutomationState.db`

```powershell
pwsh -File scripts\Initialize-AutomationDb.ps1 `
  -DatabasePath "C:\Program Files (x86)\BigFix Enterprise\BES Server\SoftwarePortal\AutomationState.db" `
  -SQLDir      "C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite"
```

The script is idempotent — a second run reports `[SKIP]` for every object. After it
completes, verify:

- **13 `Region` rows** with the exact D-21 spellings:
  `UAP, MOT, APAC, APAC-MOT, APAC-M&A, AAG-DE, AAG-FR, AAG-UK, AAG-ES, AAG-BLX, AAG-PL, AAG-PT, GPC`.
- **The `PipelineConfig` seed** — 13 keys from `config\PipelineConfig.defaults.json`, none
  holding a secret value.
- **The Windows Event Log source `DereseSoftwarePortal`** is registered (needs admin,
  once). Every root-server script logs failures to `Application` with Event IDs in the
  **8000–8099** range; without the source, `Write-EventLog` throws and failures become
  invisible.

Run it with `-WhatIf` first if you want to see the full plan without writing anything.

---

## Step 2 — Author the first `GroupRoleMap` rules (the go-live gate)

**This is the one gate that blocks go-live.** The pipeline ships with
`config\GroupRoleMap.json` empty by design. Until an operator writes the first rule set,
every ingest resolves **zero** entitlements and every snapshot is empty. Nothing else in
this run-book matters until this step is done.

1. Get the ranked candidate list:
   ```powershell
   pwsh -File scripts\Import-AxoniousExport.ps1 -ReportGroupFrequency `
     -DatabasePath "...\AutomationState.db" -SQLDir "...\sqlite"
   ```
   This emits `group-frequency-<RunId>.csv` (`Source_Value, Source_Type, UserCount`,
   ranked) beside the JSON log. It reads only the DB — no export needed.
2. Open **BigFix Console → Dashboards → Dereso Role Admin** (`fixlet_role_admin.ojo`),
   **GroupRoleMap** tab.
3. For each candidate rule set `Pattern` (exact, or a trailing `*` for a prefix match),
   `Match_On` (`cn` / `display` / `dn`), and `Role`. Use the **Test Pattern** field to
   check the rule against real group values *before* saving — the Test Pattern matcher is
   a line-for-line mirror of the ingest's `Resolve-Roles`, so what it shows is what the
   pipeline will do (`Active = 0` rules never fire; **all** matching rules apply;
   `Priority` only orders).
4. Save the rules (they are written by a SingleAction to the root-server BES client).
5. Run one ingest and confirm the **Reference DB** tab's per-role user counts look sane
   *before* you publish anything.

---

## Step 3 — Seed `RolePublication` and pick the pilot region

`RolePublication` is `(Role, RegionID)` pairs; a `NULL` `RegionID` means "all regions". In
v1 it is **hand-seeded** — there is no bulk editor.

- Add rows for the roles you want live **in the pilot region only**.
- One region at a time. Each published region is one more concurrent fleet-wide policy
  action, and one more daily `PUT` of a policy Fixlet against live content.

---

## Step 4 — Dry run

1. **Audit every new script at once:**
   ```powershell
   pwsh -File scripts\Invoke-WhatIfAudit.ps1
   ```
   Every one of the eight scripts must report `PASS` (zero file writes, zero DB writes,
   zero mutating REST / scheduled-task calls) **and** produce its run-audit record. Run
   this on the *actual root server*, not only on a dev host.
2. **Dry-run ingest and publish against the real export** and read the JSON logs under
   `…\SoftwarePortal\logs\`:
   ```powershell
   pwsh -File scripts\Import-AxoniousExport.ps1 -WhatIf -DatabasePath "...\AutomationState.db" -SQLDir "...\sqlite"
   pwsh -File scripts\Publish-RoleSnapshot.ps1  -WhatIf -SkipFixletPut -Region <PILOT> -DatabasePath "...\AutomationState.db" -SQLDir "...\sqlite"
   ```
   Confirm `Rows_In` is close to the known user count (not the physical line count — see
   Troubleshooting), and that the publish plan names the region file, size and SHA1 it
   *would* write.

---

## Step 5 — Register the scheduled tasks

```powershell
pwsh -File scripts\Register-AutomationTasks.ps1 `
  -DatabasePath "...\AutomationState.db" -SQLDir "...\sqlite" -LogDir "...\SoftwarePortal\logs"
```

This registers four root-server tasks (SYSTEM, Highest) and re-exports each to
`config\task-<Name>.xml`:

| Task | Script | Schedule | Notes |
|------|--------|----------|-------|
| **`DeresoRoleIngest`** | `Import-AxoniousExport.ps1` | Daily 03:00 | Must run **before** `DeresoRolePublish`. |
| **`DeresoRolePublish`** | `Publish-RoleSnapshot.ps1` | Daily (after ingest) | Shares the 03:00 trigger with ingest today — sequence it with a trigger offset (e.g. 03:30) or task chaining so publish always sees a completed ingest. |
| **`DeresoContentSync`** | `Invoke-ContentSync.ps1` | Weekly | Records `discovered` items and copies only `stage = 'ready'` ones. `-AutoApprove` is OFF. |
| **`DeresoRepoStage`** | `Stage-Repository.ps1` | On demand | Started only by a successful `DeresoContentSync`. |

**Importable fallback:** the four `config\task-*.xml` files are valid Task Scheduler 1.2
XML. If the programmatic registration is not an option on your root server, import them
with `schtasks /Create /XML config\task-DeresoRoleIngest.xml /TN DeresoRoleIngest` (and
the other three). They carry the script's default parameter paths — edit the `<Arguments>`
line if your install layout differs.

---

## Step 6 — Redeploy task 787 (`Init  Current User and UserRole DB`)

This is a **behavioural change to already-published content**, so treat it as a change,
not a routine push.

**What is live today (task 787's current `Action1`):**

- wraps `Initialize-RoleDb.ps1` in an `if {not exists file (parameter "TargetStore")}`
  gate (so a redeploy is a no-op on an already-initialised endpoint),
- detects the user via `explorer.exe` → `GetOwner` → `Split('\')[-1].ToLower()`, and
- registers `RoleDB_Maintenance` running **only** `Initialize-RoleDb.ps1`.

**What the committed repo `.bes` does instead:**

- the file-exists gate is removed — the migration-safe init runs every time,
- the additive `Map` migration (`Source_Type`, `Source_Value`, `Region`, `Assigned_By`) is
  applied, and
- `RoleDB_Maintenance` now runs **two** sequential actions — `Initialize-RoleDb.ps1` then
  `Reconcile-LocalRoles.ps1` — with an `Unregister-ScheduledTask` **before** the
  "not exists" re-register guard, so an already-provisioned endpoint adopts the new
  two-action command line instead of silently keeping the old one (RESEARCH Pitfall 5).

**Procedure:**

1. Push the committed `Dashboard_4_samples\Init  Current User and UserRole DB.bes` to
   **task 787** in `custom/Dereso Software Portal` (REST `PUT /api/task/custom/<site>/787`,
   or replace it via the console).
2. Confirm the new `Action1` body on the server matches the committed `.bes`.
3. **Verify on ONE already-provisioned endpoint first:** deploy the task explicitly to a
   single test computer, then in Task Scheduler confirm `RoleDB_Maintenance` now shows
   **two** actions (`Initialize-RoleDb.ps1` and `Reconcile-LocalRoles.ps1`), and that a
   logoff/logon runs both. Only then widen the deployment.
4. If a test endpoint still shows the single old action, the unregister-then-reregister did
   not take — unregister `RoleDB_Maintenance` manually on the pilot endpoints and re-run
   the task, then fix the gating before the fleet.

The `Reconcile-LocalRoles.ps1` file itself is shipped to endpoints as a **prefetched file
resource** (SHA1-pinned in the `.bes`). If that script changes in a later plan, both the
`.bes` prefetch item **and** the Custom Repository staged copy must be re-pinned.

---

## Step 7 — Per-region phased enablement (D-26)

Do **not** enable everything at once. The order is deliberate:

| Phase | Action | Check before proceeding |
|-------|--------|-------------------------|
| **Week 1** | Everything in `-WhatIf`. `DeresoRoleIngest` / `DeresoRolePublish` registered but run with `-WhatIf`; read the JSON logs daily. | Ingest `Rows_In` ≈ known user count; publish plan sane for the pilot region. |
| **Pilot** | Role pipeline **live for one pilot region only**. Remove `-WhatIf`; publish that region; enable its policy action from the Role Admin dashboard's **Region** tab (one `confirm()` that names the region). | Checklist section **Pilot** in `07-05-UAT-CHECKLIST.md` signed off — a real user's role is in a real endpoint's `RoleAwareness.db` with `Assigned_By = 'AxoniousSync'`. |
| **Widen** | Add regions **one at a time**. For each: reconcile its live `GPC_Sub_Name` value against the seed (checklist section **D-21**), seed `RolePublication`, publish, enable the policy action. | The new region's live setting value matches a `Region` seed row exactly, including case. |
| **Content — manual** | `DeresoContentSync` / `DeresoRepoStage` live, `-AutoApprove` **OFF**. Operators approve each `ContentItem` in the `fixlet_automation_monitor.ojo` **Content Queue**. | The Content Queue has been operated manually for a **full cycle** (discover → approve → copy → stage → live) with no surprises. |
| **Content — auto** | Enable auto-approve for **low-risk categories only**, last. | Everything above has run clean for at least one cycle. |

**No region beyond the pilot is enabled until the pilot is signed off.**

---

## Configuring — `PipelineConfig` keys

Every row is `Key / Value / Description`. Edit values through the
`fixlet_automation_monitor.ojo` **Config** tab (which writes via a SingleAction to the
root-server client) or directly on the root server. The `AKeyless*` keys are **paths, not
secrets** — the dashboard shows them as PATH-ONLY, never a password field.

| Key | Meaning | Default | Blast radius if wrong |
|-----|---------|---------|-----------------------|
| `AxoniousExportPath` | Full path to the daily export CSV. | *(empty)* | Ingest aborts with error `6710` until set. |
| `MaxExportAgeDays` | Stale-export guard. Older than this → **warn (Event 8010) and continue**, never abort. | `2` | Too low = noisy warnings; too high = a silently stale export keeps renewing dead grants. |
| `SnapshotOutputDir` | **Override only.** Empty = derive from the `wwwRootFolder` registry value + `\Uploads\CustomRepository\SoftwarePortal\roleref`. | *(empty — keep it empty)* | A non-empty wrong value writes snapshots where nothing serves them. Normally leave blank so the path is registry-derived. |
| `SnapshotUrlBase` | Base URL the per-region policy action prefetches from. | `http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref` | Wrong host = endpoints cannot download the snapshot (see checklist section A2). |
| `BESRootUrl` | BigFix REST base URL for root-server scripts. | `https://localhost:52311` | Wrong = fixlet `PUT` and `/api/query` fail. |
| `AKeylessTokenFile` | Path to Cyera's `.vault-token` (read-only). | `…\BES Client\EC\Cyera\.vault-token` | Missing/stale = every root script fails at credential fetch (Event 8001, class `token-file-missing`). |
| `AKeylessSecretPath` | AKeyless path of the operator password. | `/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator` | Wrong path returns empty → Event 8001 class `secret-empty`. |
| `BESOperatorUser` | Username of the scoped operator service account. | *(empty)* | Empty or over-scoped = policy-Fixlet `PUT` fails or has more authority than it should. |
| `ValidityMonths` | How far forward a reconciled `Map.Valid_to` is pushed. | `6` | Too short = roles lapse before the next reconcile on a host nobody logs off. |
| `UsernameSourcePriority` | Coalesce order for the match key. | `sam,upn,username` | Wrong order = users keyed on the wrong identifier and never matched by the reconcile. |
| `SQLDir` | Directory holding `sqlite3.exe` directly. | `…\BES Client\EC\sqlite` | Missing `sqlite3.exe` = `Initialize-AutomationDb.ps1` error `6000`. |
| `AlertWebhook` | Optional failure-alert webhook. | *(empty = off)* | — |
| `ConsoleUserRelevance` | **The A1 fallback seam.** The client-relevance expression the policy action substitutes to identify the console user. | `name of current user` | If `name of current user` turns out not to be the interactive user on the fleet (checklist section A1), change this **one value** to `names of logged on users` (or an item-zero form of that plural list) and re-run `Publish-RoleSnapshot.ps1` so the policy Fixlet ActionScript picks up the new substitution. No code edit. |
| `MaxAgeOutFraction` | **Mass-revocation brake.** *Not seeded by default* — add the key to opt in. Ingest refuses an age-out sweep that would deactivate more than this fraction of active entitlements (sets `Status = 'partial'`, Event 8012). | `0.5` (internal default when the key is absent) | Too low = a legitimate large change is blocked; absent = the internal `0.5` still applies. |
| `MaxStageFileMB` | **Disk brake.** *Not seeded by default* — add the key to opt in. `Stage-Repository.ps1` logs and skips any prefetch file larger than this. | `4096` (internal default when the key is absent) | Too low = large installers never stage; too high = a runaway download fills the repository volume. |
| `ContentSourceSites` | Comma-separated source sites the content pipeline scans. Seeded on first `Invoke-ContentSync.ps1` run from the `fixlet_update_tracker.ojo` list. | *(seeded on first run)* | Wrong = the pipeline scans the wrong sites or none. |
| `RoleRefFixletId_<region>` | Auto-recorded id of each region's policy Fixlet (set on first publish). | *(auto)* | Do not hand-edit — a wrong id makes the daily re-`PUT` target the wrong Fixlet. |

---

## Troubleshooting

Keyed on the **symptom you see**, not the cause. One row per RESEARCH pitfall.

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| `SyncRun.Rows_In` is far larger than the known user count; `UserRole.Source_Value` values look like fragments of a DN. | **(Pitfall 1)** A line-based reader split one quoted multi-line group cell across many physical lines. | The pipeline uses `Import-Csv` (RFC-4180-correct) — this should not happen. If it does, a code change broke the single-pipeline streaming read; revert to `Import-Csv \| ForEach-Object` with no buffering cmdlets inside the loop. |
| `Reconcile-LocalRoles.ps1` logs `[SKIP] no console user` on machines that clearly have someone logged in; `Map` rows never gain `Assigned_By = 'AxoniousSync'`. | **(Pitfall 2 / A1)** `name of current user` is not returning the interactive user on this fleet. | Set `PipelineConfig.ConsoleUserRelevance` to `names of logged on users` (or an item-zero form), re-run `Publish-RoleSnapshot.ps1`, re-test. This is checklist section **A1** and is a STOP gate before any region goes live. |
| Endpoint client logs show a download failure or a `prefetch` hash mismatch for `roleref-<region>-latest.json`; `Snapshot.Status = 'published'` but no `Map` changes anywhere. | **(Pitfall 3)** The policy Fixlet's `prefetch sha1:` is stale — it names yesterday's file. | `Publish-RoleSnapshot.ps1` is supposed to re-`PUT` the Fixlet every run with today's `sha1:`/`size:`. Confirm `DeresoRolePublish` actually ran and its JSON log shows the prefetch-line diff. If the re-`PUT` is failing, check the operator credential and `BESRootUrl`. |
| Reconcile works on the root server and relays but nowhere else. | **(Pitfall 4 / A2)** The `http://127.0.0.1:52311/…` prefetch URL does not resolve to the parent relay's server root on ordinary endpoints. | Switch `PipelineConfig.SnapshotUrlBase` to the relay-qualified form, or fall back to the documented `Invoke-WebRequest` GET inside the reconcile. This is checklist section **A2** — record which the pilot used. |
| After the Step 6 redeploy, logon still runs only `Initialize-RoleDb.ps1`, never the reconcile. | **(Pitfall 5)** The `RoleDB_Maintenance` re-registration is gated on "task does not exist", so an already-provisioned endpoint kept the old command line. | Confirm the redeployed `.bes` contains the `Unregister-ScheduledTask -TaskName RoleDB_Maintenance -Confirm:$false` line **before** the re-register guard. Unregister the task manually on affected endpoints and re-run the init task. |
| Ingest wall-clock is in the tens of minutes; `sqlite3.exe` churns in Process Monitor. | **(Pitfall 6)** Per-row SQLite process spawn instead of batched transactions. | The ingest batches `-BatchSize` (default 400) rows per `BEGIN;…COMMIT;`. If it regressed to per-row writes, restore the batch flush. Raise `-BatchSize` if `sqlite3.exe` spawn overhead still dominates. |
| Scheduled runs fail with nothing in the Application event log. | **(Pitfall 7)** The `DereseSoftwarePortal` Event Log source is not registered. | Re-run `Initialize-AutomationDb.ps1` as an admin once — it registers the source (`New-EventLog`) if `SourceExists` is false. |
| The Role Admin **Reference DB** tab (or the monitor **Status** tab) is empty while `SyncRun` clearly has rows on disk. | **(Pitfall 8 / A3)** The dashboard can only make BigFix API calls — it reads `AutomationState.db` through a client-relevance Analysis on the root server, which is not reporting. | Confirm the root server is an enrolled managed BES client and that the `AutomationState.db` Analysis property bodies have been published and have evaluated at least once (up to 5 min). |
| `powershell.exe` working set climbs past ~1 GB during ingest. | **(Pitfall 9)** The `Import-Csv` pipeline was accidentally collected into a variable (or a `Select-Object` / `Where-Object` buffers it). | Keep the ingest as one unassigned `Import-Csv … \| ForEach-Object { … }` pipeline; flush SQLite batches inside the loop. |
| Users with obviously-matching groups get zero roles; `SyncRun.Entitlements` is near zero on a real run. | **(Pitfall 10)** A `GroupRoleMap` rule's `Match_On` (`cn` / `display` / `dn`) does not match the shape of the value it is tested against. | In the Role Admin **GroupRoleMap** tab, use **Test Pattern** against a real group value and adjust `Match_On`. `cn` = first `CN=` RDN of a DN; `display` = the display name; `dn` = the raw string. |
| The `Reconcile-LocalRoles.ps1` extracted from the `.bes` has stray `}}` or won't run. | **(Pitfall 11)** Brace escaping when embedding PowerShell in ActionScript. | The reconcile ships as a **prefetched file resource**, not `createfile`d, so there is no brace-escaping surface. If a later change reintroduces `createfile`, only double the **opening** brace (`{` → `{{`); never touch `{parameter "X"}` / `{name of current user}` / `{value of setting …}`. |
| Dashboard counts lag reality by minutes during a rollout; a redeployed Analysis appears to "reset". | **(Pitfall 12)** `Dereso SWD.bes` properties evaluate on a `PT5M` period, and a redeployed Analysis re-baselines. | Expected. Every data-bearing dashboard tab shows the Analysis **last-reported** time next to its counts — read that before concluding a reconcile did not happen. |

---

## Known Limitations (v1 — state these plainly, do not let anyone discover them in production)

- **Console user only.** `Reconcile-LocalRoles.ps1` reconciles **only the interactive
  console user**. On a shared host, whoever is at the console gets their roles written;
  other logged-on sessions are not reconciled. Per-session reconcile is deferred.
- **No revoke — only `Valid_to` age-out.** There is no deactivation path. When a user
  loses a group, their `UserRole` row is marked `Active = 0` and simply stops being
  published; the endpoint `Map` row lapses when `Valid_to` is reached (up to
  `ValidityMonths`, default 6). Losing a role is therefore **slow**, and a role held via a
  `Locked_by_Override = 1` row is never touched at all.
- **A stale export delays revocation but never grants.** An out-of-date Axonius export
  keeps renewing existing grants (age-out only fires after a clean full read) but cannot
  invent new ones.
- **`RefUser.RegionID` is reporting-only.** It is not used for snapshot filtering — the
  endpoint self-filters by its own `GPC_Sub_Name`.
- **`RolePublication` is hand-seeded.** There is no bulk editor in v1; rows are added by
  hand, one region at a time.

---

## File Reference

### Root-server scripts (`scripts\`)

| File | Purpose |
|------|---------|
| `Initialize-AutomationDb.ps1` | Creates `AutomationState.db` (11 tables), seeds `Region` (13) / `Role` (3) / `PipelineConfig`, registers the `DereseSoftwarePortal` Event Log source, preflights `sqlite3.exe`. |
| `Get-BigFixCredential.ps1` | Returns the operator `[pscredential]` from AKeyless via Cyera's universal identity. No secret at rest. |
| `Import-AxoniousExport.ps1` | Daily streaming ingest of the Axonius export → `RefUser` / `UserRole` / `SyncRun`. `-ReportGroupFrequency` emits the ranked group list for rule authoring. |
| `AxoniousParse.psm1` | Pure transforms used by the ingest (`Resolve-UserName`, `Get-GroupViews`, `Get-SourceType`, `Resolve-Roles`, `Get-GroupRows`). |
| `Publish-RoleSnapshot.ps1` | Per-region snapshot JSON + `.sha1` manifest into the Custom Repository; re-`PUT`s each region's policy Fixlet every run. |
| `SnapshotBuild.psm1` | Pure snapshot / prefetch-line / policy-relevance / Fixlet-render functions used by the publisher. |
| `Reconcile-LocalRoles.ps1` | Endpoint reconcile — console-user D-12 upsert into `RoleAwareness.db` `Map` with the four provenance columns. Shipped to endpoints as a prefetched file resource. |
| `Invoke-ContentSync.ps1` | Weekly source-site scan → `discovered` ContentItems → operator-gated 4-step copy → `X-Superseded-By` stamp → chains `DeresoRepoStage`. |
| `ContentSyncCore.psm1` | Pure content-pipeline functions (`Get-StrippedName`, `Compare-FixletVersion`, `New-SupersededXml`, `Read-PrefetchLine`, …). |
| `Stage-Repository.ps1` | Downloads + SHA1/size-verifies each copied fixlet's prefetch installer into `…\CustomRepository\SoftwarePortal\<sha1>\<file>`. Discards any mismatch. |
| `Register-AutomationTasks.ps1` | Registers the four root-server scheduled tasks from one append-only table and exports each to `config\task-<Name>.xml`. |
| `Invoke-WhatIfAudit.ps1` | One command that dry-runs all eight scripts and proves zero side effects, plus a source scan for forbidden constructs. Run it during Step 4 and on the real root server. |

### `.bes` files (`Dashboard_4_samples\`, `bes\`)

| File | Purpose |
|------|---------|
| `Dashboard_4_samples\Init  Current User and UserRole DB.bes` | **Task 787.** Endpoint init + `Map` migration + registers `RoleDB_Maintenance` (now two actions: init then reconcile). Redeployed in Step 6. |
| `Dashboard_4_samples\Dereso SWD.bes` | Analysis. Gains `map_source in r.db` (ID 5) and `map_region in r.db` (ID 6) over the migrated `Map` columns. |
| `bes\RoleRef-Policy-template.bes` | Per-region policy Fixlet template. `__REGION_LC__` / `__PREFETCH_LINE__` / `__RECONCILE_PREFETCH__` tokens are substituted per region by `Publish-RoleSnapshot.ps1`. Combined 3-clause `<Relevance>`: DB-existence guard **AND** single-region `GPC_Sub_Name` gate **AND** the freshness gate. |

### Config (`config\`)

| File | Purpose |
|------|---------|
| `PipelineConfig.defaults.json` | The 13 documented seed keys. No secret values. |
| `GroupRoleMap.json` | Empty by design — rule content is the Step 2 go-live gate. |
| `task-DeresoRoleIngest.xml` | Task Scheduler 1.2 export for `DeresoRoleIngest` (importable fallback). |
| `task-DeresoRolePublish.xml` | Export for `DeresoRolePublish`. |
| `task-DeresoContentSync.xml` | Export for `DeresoContentSync`. |
| `task-DeresoRepoStage.xml` | Export for `DeresoRepoStage`. |

### Dashboards (`Existing Dashboards\`)

| File | Purpose |
|------|---------|
| `fixlet_role_admin.ojo` | GroupRoleMap rule authoring + Test Pattern, RolePublication scope, one-region-at-a-time publish picker, read-only Reference DB health. |
| `fixlet_automation_monitor.ojo` | Content-pipeline only: Status, Content Queue (approve/reject), Repository Cache (unverified-hash signal), `PipelineConfig` editor. No role controls. |
| `fixlet_role_assigner.ojo` | Break-glass / manual-override CSV path (demoted). Analysis view gains Source + Region columns. |

### Scheduled tasks

| Task | Tier | Trigger |
|------|------|---------|
| `DeresoRoleIngest` | root server | Daily 03:00 |
| `DeresoRolePublish` | root server | Daily, after ingest |
| `DeresoContentSync` | root server | Weekly |
| `DeresoRepoStage` | root server | On demand (chained) |
| `RoleDB_Maintenance` | every endpoint | At logon — runs `Initialize-RoleDb.ps1` then `Reconcile-LocalRoles.ps1` |
