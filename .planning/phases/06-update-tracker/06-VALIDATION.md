---
phase: 6
slug: 06-update-tracker
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-08
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Node.js built-in `assert` module (no external packages — established across Phases 1–5) |
| **Config file** | None — scripts run directly with `node` |
| **Quick run command** | `node tests/unit/update_tracker.test.js` |
| **Full suite command** | `node tests/unit/copier.test.js && node tests/unit/modifier.test.js && node tests/unit/dispatcher.test.js && node tests/unit/role_assigner.test.js && node tests/unit/update_tracker.test.js` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `node tests/unit/update_tracker.test.js`
- **After every plan wave:** Run full suite (all 5 unit test files)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-00-01 | 00 | 0 | FR-10 | — | N/A | manual | `node scripts/generate_category_map.js` | ❌ W0 | ⬜ pending |
| 06-01-01 | 01 | 1 | FR-10 | — | N/A | unit | `node tests/unit/update_tracker.test.js` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | FR-10 | — | N/A | unit | `node tests/unit/update_tracker.test.js` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | FR-10 | T-06-XSS | `htmlEscape()` applied to all fixlet names in table cells | unit | `node tests/unit/update_tracker.test.js` | ❌ W0 | ⬜ pending |
| 06-02-01 | 02 | 2 | FR-10 | T-06-XSS | `htmlEscape()` on all DOM insertions; `xmlEscape()` on all BES XML values | unit | `node tests/unit/update_tracker.test.js` | ❌ W0 | ⬜ pending |
| 06-02-02 | 02 | 2 | FR-10 | T-06-XML | `xmlEscape()` applied to MIME field values before XML insertion | unit | `node tests/unit/update_tracker.test.js` | ❌ W0 | ⬜ pending |
| 06-03-01 | 03 | 3 | FR-10, NFR-01 | — | N/A | integration | `node tests/integration/update_tracker.integration.test.js` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/unit/update_tracker.test.js` — stubs for FR-10 pure functions (stripVersion, extractVersion, compareVersions, lookupCategory, buildScanResults)
- [ ] `tests/integration/update_tracker.integration.test.js` — integration test skeleton (SKIP mode without BigFix)
- [ ] `tests/fixtures/phase-06/portal-fixlet-with-roles.xml` — old portal fixlet with `<Category>` and `Associated_Roles` MIME field
- [ ] `tests/fixtures/phase-06/source-fixlet-new-version.xml` — newer version source fixlet to copy
- [ ] `tests/fixtures/phase-06/expected-copy-output.xml` — expected BES XML after copy builder
- [ ] `tests/fixtures/phase-06/expected-superseded-output.xml` — expected BES XML after X-Superseded-By stamp
- [ ] `scripts/generate_category_map.js` — build-time CSV → JS object generator; run once and embed output in dashboard

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Dashboard loads in BigFix Console without JS errors | FR-10 | Requires live BigFix Console (IE9 engine; not simulatable in Node.js) | Import `fixlet_update_tracker.ojo` into BigFix Console; open dashboard; verify no script errors in IE9 developer tools |
| Scan returns results against live source sites | FR-10 | Requires live BigFix + source sites configured | Click "Scan for Updates"; verify Updates and New Arrivals tabs populate correctly |
| Copy flow: fixlet copied to portal, old fixlet stamped with X-Superseded-By | FR-10 | Requires live BigFix REST API | Select one update row; go through two-step copy flow; verify new fixlet appears in portal; verify old fixlet has X-Superseded-By MIME field in Modifier dashboard |
| Per-site progress status shows during scan | FR-10 (D-02) | Requires live BigFix Console to observe repaint behavior | Watch status bar during scan — should show "Scanning site X of Y…" messages (or fallback: single completion message if IE9 setTimeout repaint doesn't work) |
| Preview panel pre-fills category and roles from old fixlet | FR-10 (D-13) | Requires scan results in Console | Select row with known category + roles; click "Copy Selected"; verify preview panel shows correct pre-filled values |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
