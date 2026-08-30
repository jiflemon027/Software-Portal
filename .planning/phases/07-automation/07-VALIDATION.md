---
phase: 07
slug: automation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-29
supersedes: "2026-08-01 draft (old role-pipeline design)"
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `07-RESEARCH.md` § Validation Architecture (2026-08-29 rewrite).

---

## Test Infrastructure

| Property | PowerShell scripts | OJO dashboard |
|----------|--------------------|----------------|
| **Framework** | Pester 5.7.1 (`Import-Module Pester -MinimumVersion 5.0`) | Node.js built-in `assert` |
| **Config file** | none — `Invoke-Pester -Path tests/pester -Output Detailed` | none — `node tests/unit/role_admin.test.js` |
| **Quick run command** | `Invoke-Pester tests/pester/<one>.Tests.ps1` | `node tests/unit/role_admin.test.js` |
| **Full suite command** | `node tests/unit/*.test.js` (9 suites — `automation_monitor.test.js` added in 07-04) `&& pwsh -c "Invoke-Pester -Path tests/pester -CI"` | same combined |
| **Estimated runtime** | ~60–90 s (real `sqlite3.exe` temp-db tests included; full CSV test is `[Category=Slow]`, CI-skipped) |

---

## Sampling Rate

- **After every task commit:** Run the one relevant `*.Tests.ps1` or `node tests/unit/role_admin.test.js` (< 30 s)
- **After every plan wave:** Full Pester run + all 9 Node suites
- **Before `/gsd:verify-work`:** Full suite green + the 07-05 human-verify checklist signed off
- **Max feedback latency:** 30 seconds per-task, ~90 seconds per-wave

---

## Per-Task Verification Map

| Req / decision | Behaviour under test | Test Type | Automated Command | File Exists | Status |
|---|---|---|---|---|---|
| D-05 / Pitfall 1 | `Import-Csv` streaming parses quoted embedded newlines; multi-value cells not index-zipped | Pester (fixture) | `Invoke-Pester tests/pester/Import-AxoniousExport.Tests.ps1` | ❌ W0/1 | ⬜ pending |
| D-06 | username coalesce sam→upn-localpart→UserName, `.ToLower()`, `Username_Src` recorded | Pester | `Invoke-Pester tests/pester/Import-AxoniousExport.Tests.ps1` | ❌ W0/1 | ⬜ pending |
| D-08 / Pitfall 10 | `GroupRoleMap` exact NOCASE + `*`-suffix; `Match_On` cn/display/dn; all matches apply | Pester | `Invoke-Pester tests/pester/GroupRoleMap.Tests.ps1` | ❌ W0/1 | ⬜ pending |
| D-09 | age-out sets `Active=0` for rows whose `Last_RunID` ≠ this run; row retained | Pester | `Invoke-Pester tests/pester/Import-AxoniousExport.Tests.ps1` | ❌ W0/1 | ⬜ pending |
| D-11 | snapshot = DISTINCT `Active=1` users, filtered by `RolePublication`; `region` = one `GPC_Sub_Name`; `.sha1` matches file | Pester | `Invoke-Pester tests/pester/Publish-RoleSnapshot.Tests.ps1` | ❌ W0/2 | ⬜ pending |
| D-12 (relevance) | region-gate + DB-guard + freshness string builds and is syntactically valid | Node assert / Pester string test | `node tests/unit/role_admin.test.js` | ❌ W0/2 | ⬜ pending |
| D-12 (upsert) / D-03 | `INSERT OR IGNORE` + guarded `UPDATE`; `Locked_by_Override=1` row never modified; never `INSERT OR REPLACE`; new `Map` cols written; `INSERT OR IGNORE INTO Roles` for unknown role | Pester (temp `RoleAwareness.db`) | `Invoke-Pester tests/pester/Reconcile-LocalRoles.Tests.ps1` | ❌ W0/2 | ⬜ pending |
| D-15 | reconcile ABORTS when `snapshot.region` ≠ `-Region` | Pester | `Invoke-Pester tests/pester/Reconcile-LocalRoles.Tests.ps1` | ❌ W0/2 | ⬜ pending |
| D-18 (Map migration) | `PRAGMA table_info`-gated `ALTER TABLE` adds 4 cols, idempotent, preserves rows | Pester (migrate v2 fixture db) | `Invoke-Pester tests/pester/Initialize-RoleDb.Tests.ps1` | ❌ W0 | ⬜ pending |
| D-20 | `Get-BigFixCredential.ps1` returns `[PSCredential]`; throws on missing token / empty secret; never logs the secret | Pester (mock `Invoke-RestMethod`) | `Invoke-Pester tests/pester/Get-BigFixCredential.Tests.ps1` | ❌ W0 | ⬜ pending |
| FR-10 / content | `Strip-Version` parity with `fixlet_update_tracker.ojo` `stripVersion`; plural/singular REST path from `is_task` | Pester + Node parity | `Invoke-Pester tests/pester/Invoke-ContentSync.Tests.ps1` | ❌ W3 | ⬜ pending |
| content stage | prefetch-line regex extracts sha1/size/url/sha256; on-disk path = `<wwwRootFolder>\Uploads\CustomRepository\SoftwarePortal\<sha1>\<file>` | Pester | `Invoke-Pester tests/pester/Stage-Repository.Tests.ps1` | ❌ W3 | ⬜ pending |
| NFR-NEW (audit trail) | `-WhatIf` on every new script emits a JSON log + makes **zero** API calls / DB writes | Pester (assert mocks not invoked) | per-script `.Tests.ps1` | ❌ W1–3 | ⬜ pending |
| D-22 | `fixlet_role_admin.ojo` pure fns: `switchTab`, GroupRoleMap row validate, "Test Pattern" matcher (JS mirror of PS matcher), base64-chunk | Node assert | `node tests/unit/role_admin.test.js` | ❌ W4 | ⬜ pending |
| Regression | all 7 existing OJO unit suites still green | Node assert | existing full suite | ✓ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Seams (where to cut for testability)

- `Invoke-SqliteCommand` — mock in Pester for pure-logic tests; real temp `.db` + real `sqlite3.exe` for upsert/migration tests.
- `Invoke-RestMethod` / `Invoke-WebRequest` — mock for `Get-BigFixCredential`, `Publish-RoleSnapshot` (fixlet PUT), `Invoke-ContentSync`.
- Console-user detection in `Reconcile-LocalRoles.ps1` — `-ConsoleUser` param is the seam; tests pass it explicitly, never exercise the `explorer.exe` branch in CI.
- Snapshot builder — pure `Build-RegionSnapshot -Rows $userRoleRows -Publication $pub -Region $r` returning the PSObject, separate from file IO.
- GroupRoleMap matcher — pure `Resolve-Roles -GroupViews @{cn=…;display=…;dn=…} -Rules $rows`.

---

## Wave 0 Requirements

- [ ] `tests/pester/` directory + a `PesterConfig` note pinning v5
- [ ] `tests/fixtures/phase-07/axonious-sample-50.csv` (BOM, blank-SAM row, quoted 3-line group cell, DN + display-name group), `axonious-multivalue-edge.csv`
- [ ] `tests/fixtures/phase-07/grouprolemap-seed.json`
- [ ] `tests/fixtures/phase-07/roleref-AAG-UK-sample.json` (hand-written to D-11 shape)
- [ ] `tests/fixtures/phase-07/automation-db-schema.sql` (full DDL for an in-memory test DB)
- [ ] `tests/fixtures/phase-07/roleawareness-v2.db` (pre-migration, `-wal` checkpointed)
- [ ] `tests/unit/role_admin.test.js` (stub + first assertions)
- [ ] confirm `sqlite3.exe` reachable from the test runner (`PesterConfig` / env var `SQLDIR`)
- [ ] Pester 5 installed on the dev/CI runner

*The full `axonious.db` / 420 MB CSV stay out of git — local-only 07-01 profiling + a `[Category=Slow]` CI-skipped test.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Client relevance `name of current user` returns the interactive console user | D-04 / D-14 | Needs the production fleet; the client runs as SYSTEM and the codebase's own role relevance uses plural `names of logged on users` | 07-05: on ≥3 pilot endpoints with a known logged-on user, run reconcile and confirm the right user's roles upsert. One-line config seam exists to switch to plural. |
| `127.0.0.1:52311/Uploads/CustomRepository/...` prefetch reach on non-root endpoints | D-11 / D-12 | Only proven in root-server context | 07-05: run the per-region policy action on a pilot endpoint; confirm snapshot downloads. Documented `Invoke-WebRequest` fallback if it fails. |
| Live `GPC_Sub_Name` values match the fixed 13-value Region seed | D-21 | MCP-connected server is a 9-computer lab, not production `gpbfs` (40k) | 07-05: enumerate `value of setting "GPC_Sub_Name"` across the fleet; reconcile spelling. |
| Task 787 redeploy (file-exists gate + old user detection → `name of current user`) | D-18 / 07-05 | Behavioural change vs what's live; `RoleDB_Maintenance` re-register gated on "not exists" | 07-05: unregister + re-register on already-provisioned endpoints; confirm reconcile runs on next logon. |
| `GroupRoleMap` first rule set produces correct role assignments on the real export | Deferred (go-live gate) | Operator must author the first rules | Not a phase blocker — scripts are tested against `SampleAxonious` fixtures. Go-live gate only. |

---

## Validation Sign-Off

- [ ] All tasks have an `<automated>` verify command or a Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING fixtures/suites above
- [ ] No watch-mode flags in any test command
- [ ] Feedback latency < 30 s per task
- [ ] `nyquist_compliant: true` set in frontmatter once the above hold
- [ ] 07-05 human-verify checklist (Manual-Only table) signed off before `/gsd:verify-work`

**Approval:** pending
