---
phase: 7
slug: 07-automation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-01
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in `assert` module (matches all 5 existing test files) |
| **Config file** | none — `node tests/unit/<file>.test.js` invoked directly |
| **Quick run command** | `node tests/unit/automation_monitor.test.js` |
| **Full suite command** | `node tests/unit/copier.test.js && node tests/unit/modifier.test.js && node tests/unit/dispatcher.test.js && node tests/unit/role_assigner.test.js && node tests/unit/update_tracker.test.js && node tests/unit/automation_monitor.test.js` |
| **Estimated runtime** | ~30 seconds (unit only) |

---

## Sampling Rate

- **After every task commit:** Run `node tests/unit/automation_monitor.test.js`
- **After every plan wave:** Run full 6-suite regression gate
- **Before `/gsd:verify-work`:** Full suite must be green (161 existing + new assertions)
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 7-00-01 | 00 | 0 | D-05 schema | — | N/A | unit (fixture) | `node tests/integration/automation.integration.test.js` GROUP A | ❌ W0 | ⬜ pending |
| 7-00-02 | 00 | 0 | D-03 wildcard | SQL injection via CSV | Invoke-SqliteCommand param substitution | unit | `node tests/unit/automation_monitor.test.js` | ❌ W0 | ⬜ pending |
| 7-01-01 | 01 | 1 | FR-02 (automation) | Info Disclosure (credentials) | DPAPI SecureString storage | unit | `node tests/unit/automation_monitor.test.js` | ❌ W0 | ⬜ pending |
| 7-01-02 | 01 | 1 | D-01 CSV parse | Tampering (stale export) | MaxExportAgeDays timestamp check | unit | `node tests/unit/automation_monitor.test.js` | ❌ W0 | ⬜ pending |
| 7-02-01 | 02 | 2 | FR-10 (automation) | Tampering (malicious prefetch URL) | SHA1 verify before staging | unit | `node tests/unit/automation_monitor.test.js` | ❌ W0 | ⬜ pending |
| 7-02-02 | 02 | 2 | D-10 repo stage | Tampering (malicious prefetch URL) | SHA1 mismatch = failure + log | unit | `node tests/unit/automation_monitor.test.js` | ❌ W0 | ⬜ pending |
| 7-03-01 | 03 | 3 | D-13 dashboard | Elevation of privilege (trigger as wrong op) | BigFix Console enforces operator perms | integration (manual) | manual — human-verified | N/A | ⬜ pending |
| 7-04-01 | 04 | 4 | D-20 dry-run | — | -WhatIf produces no API calls | integration (BIGFIX-gated) | `node tests/integration/automation.integration.test.js` GROUP B | ❌ W0 | ⬜ pending |
| 7-04-02 | 04 | 4 | D-18 log format | — | JSON log matches schema | unit | `node tests/unit/automation_monitor.test.js` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/fixtures/phase-07/sample-axonious.csv` — covers Axonious parse patterns (multi-delimiter groups: pipe, semicolon, comma)
- [ ] `tests/fixtures/phase-07/sample-grouprolemap.json` — covers wildcard pattern matching (exact + `*`-suffix, case-insensitive)
- [ ] `tests/fixtures/phase-07/sample-automation-db.sql` — schema DDL for in-memory test DB (all 6 tables: SyncRun, RoleAssignment, ContentItem, CacheEntry, GroupRoleMap, PipelineConfig)
- [ ] `tests/fixtures/phase-07/sample-portal-fixlets.xml` — covers prefetch line extraction by Stage-Repository
- [ ] `tests/fixtures/phase-07/sample-prefetch-script.txt` — covers Stage-Repository `prefetch <file> sha1:<sha1> size:<n> <url>` regex
- [ ] `tests/unit/automation_monitor.test.js` — stubs for all pure JS functions in fixlet_automation_monitor.ojo (GroupRoleMap matching, content stage transitions, prefetch regex)
- [ ] `tests/integration/automation.integration.test.js` — GROUP A: fixture assertions (no BIGFIX env var needed), GROUP B: API round-trips (BIGFIX-gated, skip pattern matches existing files)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `-WhatIf` dry-run produces no BigFix API side effects | D-20 | Requires live BigFix instance to confirm no actions created | Run `.\Invoke-RoleSync.ps1 -WhatIf -Verbose`; confirm no action IDs in log; check BigFix Console for no new actions |
| Automation Dashboard Config tab writes GroupRoleMap | D-17 | Requires live BigFix Console + root server enrollment | Add a test pattern in Config tab, save, re-open dashboard; confirm row in GroupRoleMap table |
| Scheduled Task fires after Axonious export deposit | D-08 | Requires live Windows Scheduled Task trigger | Place file at configured `AxoniousExportPath`, wait for task trigger time; check SyncRun table for new entry |
| Dashboard Status tab reads from AutomationState.db via Analysis | D-14 | Requires root server as managed BES client + deployed Analysis | After a sync run, refresh Status tab; verify last run timestamp and counts visible |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
