---
document_type: plan
phase: 2
phase_name: Rules Engine
created: 2026-06-11
owner: Planner
mode: default
---

# Phase 2 Plan — Rules Engine

Objective
---------
Implement the pure game-rule functions required by the engine: ranking, trick resolution, robbing, and scoring. These modules are pure and well-tested; stateful orchestration is Phase 3.

Scope
-----
- `types.ts` — core types (`PlayerId`, `Card`, `Rank`, `Suit`, `RuleSet`, `RankTable`)
- `ranking.ts` — `buildRankTable`, `compareCards`
- `trick.ts` — `legalPlays`, `trickWinner`, `evaluateTrick`
- `robbing.ts` — `canRob`, `offerRob`, `applyRobDiscard`
- `scoring.ts` — `scoreTricks`, `detectWin`
- Tests: unit tests & canonical test vectors under `tests/phase-02/`

Waves & Tasks
-------------

Wave 1 — Types & Ranking (1 day)
- 02-01: Create `types.ts` with canonical type definitions.
- 02-02: Implement `ranking.ts` with `buildRankTable` and `compareCards`.
- 02-03: Add unit tests for ranking logic and rank table generation.

Wave 2 — Tricks & Legal Plays (1-2 days)
- 02-04: Implement `trick.ts` — `legalPlays`, `trickWinner`.
- 02-05: Add unit tests for trick winner logic including trump and lead suit edge cases.

Wave 3 — Robbing & Scoring (1-2 days)
- 02-06: Implement `robbing.ts` with validation and discard application.
- 02-07: Implement `scoring.ts` with `scoreTricks` and `detectWin`.
- 02-08: Add unit tests for robbing sequences and scoring rules (jinx, reneging penalty).

Wave 4 — Integration Tests & Gates (0.5-1 day)
- 02-09: Add canonical fixtures `tests/fixtures/phase-02/`.
- 02-10: Run test gate: TypeScript compile, unit tests (Vitest/Jest), lint.
- 02-11: Code review and small fixes.

Acceptance Criteria
-------------------
- AC-1: `types.ts`, `ranking.ts`, `trick.ts`, `robbing.ts`, `scoring.ts` exist and export documented functions.
- AC-2: Unit tests cover special-case rules (5T, JT, trump overrides) and pass.
- AC-3: `compareCards` and `trickWinner` deterministic and well-documented.
- AC-4: Robbing flow preserves hand sizes and returns clear error for illegal rob attempts.
- AC-5: `scoreTricks` computes scores per `RuleSet` including jinx bonus and reneging penalty.

Estimates & Owners
------------------
- Developer: implement code and tests — 3–6 days depending on edge-case coverage.
- Reviewer: peer dev + rules expert for correctness validation.

Deliverables
------------
- `src/phase-02/types.ts`
- `src/phase-02/ranking.ts` + tests
- `src/phase-02/trick.ts` + tests
- `src/phase-02/robbing.ts` + tests
- `src/phase-02/scoring.ts` + tests
- `tests/fixtures/phase-02/*`
