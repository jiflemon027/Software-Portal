---
phase: 4
slug: role-assigner
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-27
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in `assert` (no install required) |
| **Config file** | none — test files run directly |
| **Quick run command** | `node tests/unit/role_assigner.test.js` |
| **Full suite command** | `node tests/unit/copier.test.js && node tests/unit/modifier.test.js && node tests/unit/dispatcher.test.js && node tests/unit/role_assigner.test.js` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `node tests/unit/role_assigner.test.js`
- **After every plan wave:** Run full suite (all 4 unit test files)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 4-01-01 | 01 | 1 | FR-02 | — | N/A | fixture | file exists check | ❌ W0 | ⬜ pending |
| 4-01-02 | 01 | 1 | FR-02 | T-4-01 | validateRows blocks unknown role | unit | `node tests/unit/role_assigner.test.js` | ❌ W0 | ⬜ pending |
| 4-02-01 | 02 | 2 | FR-02 | T-4-01 | htmlEscape on CSV data rendered to DOM | unit | `node tests/unit/role_assigner.test.js` | ❌ W0 | ⬜ pending |
| 4-02-02 | 02 | 2 | FR-02 | — | One action per unique role | unit | `node tests/unit/role_assigner.test.js` | ❌ W0 | ⬜ pending |
| 4-03-01 | 03 | 3 | FR-02 | — | Full dashboard integration | manual | BigFix console | ❌ W0 | ⬜ pending |
| 4-03-02 | 03 | 3 | FR-03 | — | Analysis view shows active mappings | manual | BigFix console | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/unit/role_assigner.test.js` — stubs for FR-02 pure-JS behaviors: parseCsv, validateRows, encodeMatrix, chunkString, buildChunkParams, buildAssignActionXml
- [ ] `tests/fixtures/phase-04/sample.csv` — valid 3-role CSV (3 users × 3 roles)
- [ ] `tests/fixtures/phase-04/invalid-unknown-role.csv` — triggers block validation
- [ ] `tests/fixtures/phase-04/invalid-blank-fields.csv` — triggers blank-field block
- [ ] `tests/fixtures/phase-04/duplicate-rows.csv` — triggers warn-only validation
- [ ] `tests/integration/role_assigner.integration.test.js` — POST round-trip (env-var gated)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Client relevance guard — action only runs if RoleAwareness.db exists | FR-03 | Requires live BigFix agent with DB present/absent | Deploy action to test client; confirm runs only when DB exists |
| Analysis view shows active mappings (mapped_users in r.db) | FR-03 | Requires Analysis imported + reporting clients | Import Dereso SWD.bes; confirm mapped_users property appears in dashboard table |
| Multi-value Analysis property — multiple mappings per computer | FR-03 | Format unclear without live console | Import Analysis; confirm table shows one row per active mapping per computer |
| btoa() / FileReader availability in BigFix console browser | FR-02 | IE9 compat mode vs runtime engine | Open Role Assigner dashboard; upload CSV; confirm preview renders |
| SingleAction <Target> with explicit ComputerID list | FR-02 | Requires BES.xsd or test POST | Deploy action to 2 explicit computer IDs; confirm only those clients execute |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
