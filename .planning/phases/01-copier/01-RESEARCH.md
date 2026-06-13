---
document_type: research
phase: 1
phase_name: Copier Foundation
created: 2026-06-11
owner: Planner
---

# Phase 1 Research — Copier Foundation

Summary
-------
Phase 1 uses the existing `fixlet_copier.ojo` dashboard. Research here confirms test approach, integration points, and the minimal environment needed to validate FR-01.

Findings
--------
- Source artifact: `Existing Dashboards/fixlet_copier.ojo` — contains full dashboard XML and metadata.
- BigFix REST endpoints referenced by the dashboard (verify against target instance): `GET /api/fixlets`, `POST /api/custom-site-fixlets` (names may vary by BigFix install version). Planner must confirm exact endpoints when running integration tests.
- Target site: "Dereso Software Portal" must exist in test BigFix instance prior to integration testing.
- Authentication: BigFix admin credentials required for integration tests; use a test account with equivalent privileges.

Test Data
---------
- Create 3 sample test fixlets in a disposable test repository: minimal metadata, one with script, one with complex relevance, one intentionally invalid (missing required field) for negative testing.
- Test fixtures should be kept under `tests/fixtures/phase-01/` (repo-relative) and be exportable/importable as `.ojo` or JSON.

Integration Environment
-----------------------
- A disposable BigFix test instance (container or VM) or accessible staging server.
- Ensure `Dereso Software Portal` custom site exists. If not, create via BigFix console before test run.
- Test account credentials stored in CI secrets (never commit creds). Use CI environment variables for `BIGFIX_URL`, `BIGFIX_USER`, `BIGFIX_TOKEN`.

Verification Approach
---------------------
- Unit tests: parser/validator for copied fixlet metadata (local tests).
- Integration tests: run dashboard import flow against test BigFix instance and assert fixlet presence and metadata fidelity in `Dereso Software Portal` site.

Open Questions (RESOLVED)
------------------------
1. Exact BigFix REST API paths used by the environment under test — planner will confirm during integration setup.
   RESOLVED: Exact API paths confirmed from copier.ojo source inspection: `GET fixlet/{type}/{site}/{id}`, `POST fixlets/custom/{site}`, `GET sites`. Plans use these paths directly.

2. CI runner availability with network access to a BigFix staging instance — if unavailable, integration tests run locally by the developer or via scheduled pipeline with network access.
   RESOLVED: Integration tests skip gracefully when `BIGFIX_URL` is unset (process.exit(0) with SKIP message). No CI network access required to pass the test gate.

References
----------
- [Existing Dashboards/fixlet_copier.ojo](../../../Existing%20Dashboards/fixlet_copier.ojo)
- [ROADMAP.md](../../../ROADMAP.md)
