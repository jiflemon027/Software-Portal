---
phase: 01-copier
plan: "01"
subsystem: test-fixtures
tags: [fixtures, xml, bes, bigfix, testing]
dependency_graph:
  requires: []
  provides: [tests/fixtures/phase-01/valid-minimal.ojo, tests/fixtures/phase-01/valid-with-script.ojo, tests/fixtures/phase-01/invalid-missing-title.ojo]
  affects: [Wave 2 unit tests, Wave 2 integration tests]
tech_stack:
  added: []
  patterns: [BES Fixlet XML, buildXml() output shape, buildKnownGoodDefaultAction() structure]
key_files:
  created:
    - tests/fixtures/phase-01/valid-minimal.ojo
    - tests/fixtures/phase-01/valid-with-script.ojo
    - tests/fixtures/phase-01/invalid-missing-title.ojo
  modified: []
decisions:
  - "ActionScript content left unescaped in fixture (not XML-entity-escaped) — matches what buildKnownGoodDefaultAction() does via xmlEscape() at build time; fixtures are static XML so content is already the final form"
  - "Title element omitted entirely (not empty) in invalid-missing-title.ojo — getNodeText() returns '' for both cases but 'absent element' is stricter negative test"
metrics:
  duration_minutes: 5
  completed_date: "2026-06-13"
  tasks_completed: 3
  tasks_total: 3
  files_created: 3
  files_modified: 0
requirements_covered: [FR-01, NFR-05]
---

# Phase 01 Plan 01: BES Fixture Files Summary

**One-liner:** Three BES Fixlet XML fixture files matching buildXml()/buildKnownGoodDefaultAction() output shape for Wave 2 unit and integration tests.

## What Was Built

Three `.ojo` (BES XML) fixture files under `tests/fixtures/phase-01/`:

| File | Purpose | Key Feature |
|------|---------|-------------|
| `valid-minimal.ojo` | Happy-path unit test fixture | All 12 required elements, minimal values, single DefaultAction |
| `valid-with-script.ojo` | Multi-action + real script fixture | DefaultAction + Action2, real msiexec ActionScript, exercises cloneMode=all |
| `invalid-missing-title.ojo` | Negative test fixture | Well-formed XML, Title element entirely absent |

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create valid-minimal.ojo | 17e6a83 | tests/fixtures/phase-01/valid-minimal.ojo |
| 2 | Create valid-with-script.ojo | 8c65a57 | tests/fixtures/phase-01/valid-with-script.ojo |
| 3 | Create invalid-missing-title.ojo | 733d30c | tests/fixtures/phase-01/invalid-missing-title.ojo |

## Verification Results

All 5 verification criteria passed:

1. Directory `tests/fixtures/phase-01/` exists with exactly 3 files — PASS
2. `valid-minimal.ojo`: contains `<BES xmlns:xsi`, `<Title>Sample Minimal Fixlet</Title>`, `<Relevance>true</Relevance>`, `<DefaultAction ID="Action1">` — PASS
3. `valid-with-script.ojo`: contains `<Title>Sample Scripted Fixlet</Title>`, `<DefaultAction ID="Action1">`, `<Action ID="Action2">`, `msiexec.exe` — PASS
4. `invalid-missing-title.ojo`: does NOT contain `<Title>`, DOES contain `<BES xmlns:xsi` — PASS
5. All three files are well-formed XML (Python xml.etree.ElementTree parse succeeds for all) — PASS

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None. These are static test data files; no stub patterns apply.

## Threat Flags

None. All three files are static test fixtures under version control with no runtime trust boundary crossed. Matches T-01-01 in the plan's threat register (accepted).

## Self-Check: PASSED

- [x] `tests/fixtures/phase-01/valid-minimal.ojo` exists
- [x] `tests/fixtures/phase-01/valid-with-script.ojo` exists
- [x] `tests/fixtures/phase-01/invalid-missing-title.ojo` exists
- [x] Commit 17e6a83 exists (Task 1)
- [x] Commit 8c65a57 exists (Task 2)
- [x] Commit 733d30c exists (Task 3)
