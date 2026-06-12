---
document_type: plan
phase: 1
phase_name: Copier Foundation
created: 2026-06-11
owner: Planner
mode: default
---

# Phase 1 Plan — Copier Foundation

Objective
---------
Deliver a validated, documented Copier dashboard that satisfies FR-01: reliable fixlet copy into the "Dereso Software Portal" custom site with metadata preserved.

Scope
-----
- Test harness and unit tests for metadata parsing and validation
- Integration tests exercising the importer against a BigFix staging instance
- Documentation: Admin User Guide, Architecture/Design doc, API Integration Guide
- Small code review and any minor cleanup required for `fixlet_copier.ojo`

Waves & Tasks
-------------

Wave 1 — Test harness & unit tests (1-2 days)
- 01-01: Extract metadata parsing/validation logic into testable scripts (or create test harness around `fixlet_copier.ojo`).
- 01-02: Write unit tests for parser and validation logic (happy path + negative cases).
- 01-03: Add fixture exports in `tests/fixtures/phase-01/` (3 sample fixlets).

Wave 2 — Integration tests & CI (1-3 days)
- 02-01: Provision/identify BigFix staging instance and create `Dereso Software Portal` site.
- 02-02: Implement integration test that triggers the copier flow and verifies fixlet presence and metadata fidelity in the target site.
- 02-03: Add CI job or documentation describing how to run integration tests locally when network access is restricted.

Wave 3 — Docs, review, release (1-2 days)
- 03-01: Author Admin User Guide — step-by-step usage and troubleshooting.
- 03-02: Write Architecture/Design doc referencing `fixlet_copier.ojo` internals and BigFix API calls.
- 03-03: Create API Integration Guide listing endpoints, auth, error codes.
- 03-04: Code review and minor fixes to `fixlet_copier.ojo` if issues found.

Acceptance Criteria (maps to FR-01)
---------------------------------
- AC-1: Copier dashboard loads without errors in staging environment.
- AC-2: Integration test imports sample fixlet into `Dereso Software Portal` and preserves name, description, relevance, and action script.
- AC-3: Negative test fixture triggers a clear validation error and no partial copy.
- AC-4: Admin User Guide and Architecture doc present in `.planning/docs/phase-01/` (or repo docs folder).
- AC-5: All unit tests pass; integration test passes in staging (or documented as manual step if CI cannot access BigFix).

Owners & Estimates
------------------
- Planner / Dev: implement tests and docs
- Reviewer: Tech writer / BigFix admin for acceptance
- Estimated effort: 3–7 days total depending on integration test availability

Dependencies
------------
- Access to a BigFix staging instance and admin credentials
- `fixlet_copier.ojo` located at `Existing Dashboards/fixlet_copier.ojo`
- CI runner with network access (optional)

Deliverables
------------
- `tests/fixtures/phase-01/*` — sample fixlets
- Unit test suite under `tests/phase-01/`
- Integration test script `tests/integration/phase-01-integration.*`
- `docs/phase-01/Admin-User-Guide.md`
- `docs/phase-01/Architecture.md`
- `docs/phase-01/API-Integration-Guide.md`
