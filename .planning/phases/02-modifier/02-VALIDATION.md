---
phase: 2
slug: modifier
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-14
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in `assert` (no external framework) |
| **Config file** | None — tests are standalone scripts |
| **Quick run command** | `node tests/unit/modifier.test.js` |
| **Full suite command** | `node tests/unit/modifier.test.js && node tests/unit/copier.test.js` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `node tests/unit/modifier.test.js`
- **After every plan wave:** Run `node tests/unit/modifier.test.js && node tests/unit/copier.test.js`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | FR-02 | — | Roles come from admin-controlled config only | unit | `node tests/unit/modifier.test.js` | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | FR-03 | — | Role names are quoted strings; DB path is fixed | unit | `node tests/unit/modifier.test.js` | ❌ W0 | ⬜ pending |
| 2-01-03 | 01 | 1 | NFR-05 | — | PORTAL_CONFIG is parseable; roles/categories non-empty | unit | `node tests/unit/modifier.test.js` | ❌ W0 | ⬜ pending |
| 2-02-01 | 02 | 2 | FR-02 | — | PUT round-trip writes Associated_Roles MIME field | integration | `node tests/integration/modifier.integration.test.js` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/unit/modifier.test.js` — stubs for FR-02, FR-03, NFR-05 function-level behaviors
- [ ] `tests/integration/modifier.integration.test.js` — stubs for FR-02 PUT round-trip
- [ ] `tests/fixtures/phase-02/valid-fixlet-no-roles.ojo` — fixture (no existing roles/relevance)
- [ ] `tests/fixtures/phase-02/valid-fixlet-with-roles.ojo` — fixture (has existing roles + injected relevance)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No duplicate `var fixletNode` in buildUpdateXml() | D-01 | Static code review — not testable at runtime | Open modifier.ojo and verify single declaration at line ~570 |
| Dead functions removed (_previewXml, _renumberRoleRows, addCategoryRow) | D-01 | Absence of dead code verified by inspection | Search modifier.ojo for `_previewXml`, `_renumberRoleRows`, `addCategoryRow` — none should exist |
| No commented alert() calls remain | D-01 | Static review | Search modifier.ojo for `//.*alert\(` — zero matches |
| Modifier dashboard loads without errors in BigFix console | FR-02 | Requires live BigFix console | Load modified .ojo in BigFix Web Reports; verify no JS console errors |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
