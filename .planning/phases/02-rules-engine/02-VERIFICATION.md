---
document_type: verification
phase: 2
phase_name: Rules Engine
created: 2026-06-11
owner: Planner
---

# Phase 2 Verification Checklist — Rules Engine

Gates
-----
- Compile Gate: `tsc` passes for new files.
- Unit Test Gate: All unit tests under `tests/phase-02/` pass.
- Behavior Gate: Canonical test vectors (special-case tricks, robbing) match expected winners/scores.
- Code Review Gate: Peer review verifies correctness for tricky rule implementations.

Checks
------
1. `npm run build` or `pnpm build` — TypeScript compiles with no errors.
2. `npm test` — unit tests pass (Vitest/Jest output).
3. Run canonical vectors script `tests/phase-02/canonical-vectors.ts` which asserts:
   - `compareCards` ordering for 5T vs JT vs other cards
   - `trickWinner` returns expected `PlayerId` for provided play sequences
   - `applyRobDiscard` preserves hand counts and updates kitty correctly
4. Lint and formatting checks pass.
5. Documented examples in `README` or docstrings for each exported function.

Exit Criteria
-------------
- All checks pass OR any failing checks have an owner and due date recorded in `VERIFICATION.md`.
- Changes merged to main branch and referenced from `.planning/STATE.md` as Phase 2 planned.
