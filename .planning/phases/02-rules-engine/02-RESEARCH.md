---
document_type: research
phase: 2
phase_name: Rules Engine
created: 2026-06-11
owner: Planner
---

# Phase 2 Research — Rules Engine

Summary
-------
Phase 2 implements the core game rules for the engine: ranking, trick resolution, robbing, and scoring. Research confirms data shapes, algorithm choices, test vectors, and interfaces the rest of the system expects.

Key Decisions (candidate)
-------------------------
- `PlayerId` is a numeric alias (`number`).
- `RankTable` is a precomputed `Record<`"Rank:Suit"`, number>` used for fast comparisons.
- Expose pure functions: `buildRankTable(rules)`, `compareCards(a,b,rankTable)`, `legalPlays(hand, leadSuit, trumpSuit, rules)`.
- Robbing is a two-step flow: `offerRob(robberId, kitty)` → `robDiscard(robberId, discardCard)`; careful to preserve hand counts.

Algorithms & Edge Cases
----------------------
- Ranking: support custom `RuleSet` (e.g., StandardIrishRules) including 5 of trumps, jacks, and other special ordering.
- Compare with deterministic tie-breakers; no randomness inside compare function.
- Tricks: `trickWinner(plays, trumpSuit, ledSuit, rankTable)` returns `PlayerId`.
- Robbing: validate that discarding a card after robbing leaves correct hand size; handle illegal robs (e.g., robbing when not dealer).

Test Fixtures & Vectors
-----------------------
- Provide canonical card fixtures to cover special cases: 5T (five of trumps), JT (jack of trumps), right/left bower if applicable.
- Add trick sequences with tied ranks and with trump overrides.
- Add robbing sequences that exercise the two-step flow and invalid rob attempts.

Implementation notes
--------------------
- Language: TypeScript (existing project uses TS in previous phases).
- Files to create: `ranking.ts`, `trick.ts`, `robbing.ts`, `scoring.ts`, `types.ts`, and tests under `tests/phase-02/`.
- Export pure functions only; stateful orchestration lives in Phase 3 (`machine.ts`).

References
----------
- Phase 1 CONTEXT: `.planning/phases/01-copier/01-CONTEXT.md` (for project conventions)
- Roadmap decisions captured in project roadmap and Phase 1 discussion logs.

Open Questions
--------------
1. Confirm exact rule variants to support in `StandardIrishRules` (jinx points, reneging penalties).
2. Confirm canonical representation for `Rank` and `Suit` strings used across engine and presentation layers.