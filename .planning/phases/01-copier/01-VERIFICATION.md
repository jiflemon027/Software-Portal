---
document_type: verification
phase: 1
phase_name: Copier Foundation
created: 2026-06-11
owner: Planner
---

# Phase 1 Verification Checklist — Copier Foundation

Gates
-----
- Unit Test Gate: All unit tests listed under `tests/phase-01/` must pass.
- Integration Gate: Integration test must demonstrate a successful copy into `Dereso Software Portal` and exact metadata preservation. If CI cannot run integration tests, an explicit manual run and sign-off by a BigFix admin is required.
- Docs Gate: Admin User Guide and Architecture/Integration docs present and reviewed.
- Code Review Gate: Review of `fixlet_copier.ojo` artifacts for obvious issues (broken references, missing metadata mappings).

Checks
------
1. Unit tests: `npm test` / `pytest` / or repo-specific command — all green.
2. Integration test steps:
   - Ensure `BIGFIX_URL`, `BIGFIX_USER`, `BIGFIX_TOKEN` are set in environment/CI secrets.
   - Run `tests/integration/phase-01-integration.sh` (or equivalent).
   - Assert: target site contains imported fixlets with identical `name`, `description`, `relevance`, and `action script`.
3. Negative case: run import of invalid fixture — expect validation error, no partial copy.
4. Docs: check `docs/phase-01/` contains `Admin-User-Guide.md`, `Architecture.md`, `API-Integration-Guide.md` and that each has Acceptance Criteria covered sections.
5. Hand-off: create a `PHASE-1-COMPLETE.md` with sign-offs from Dev and BigFix admin.

Exit Criteria
-------------
- All checks pass OR any remaining manual steps are documented with a named owner and deadline.
- `PHASE-1-COMPLETE.md` exists and is referenced in `STATE.md`.
