---
document_type: context
phase: 2
phase_name: Modifier (Role-Based Categorization)
created: 2026-06-14
status: ready-for-planning
---

# Phase 2: Modifier (Role-Based Categorization) — Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 fixes, cleans, tests, and documents the existing Modifier dashboard (`fixlet_modifier.ojo`) — enabling BigFix admins to associate fixlets with user roles, inject role-awareness relevance, and update fixlet categories. Role associations are stored as `Associated_Roles` MIME fields; relevance queries a pre-existing `RoleAwareness.db` SQLite database on client machines.

This phase does **not** modify fixlet descriptions or DefaultActionScript (deferred to Phase 3), and does **not** provision `RoleAwareness.db` (it already exists).

</domain>

<decisions>
## Implementation Decisions

### modifier.ojo Code Condition (D-01 through D-03)

- **D-01:** Fix bugs + cleanup as part of Phase 2. Do **not** test-as-is and flag in review.
  - Fix Bug 1: duplicate `var fixletNode` declaration inside `buildUpdateXml()` (lines 567 & 570)
  - Fix Bug 2: `cleanedXml` redeclared inside `buildUpdateXml()` (lines 547 & 600) — second declaration shadows the first, potentially using stale XML when writing MIME fields
  - Remove dead code: `_previewXml()` and `_renumberRoleRows()` functions (prefixed with `_`, never called)
  - Strip commented-out `alert()` diagnostic calls throughout

- **D-02:** Fix scope = bugs + cleanup only (not a full rewrite). Deliver a clean, production-ready `.ojo` file.

- **D-03:** Add unit tests for pure JS functions — same pattern as `tests/unit/copier.test.js` from Phase 1.
  - Target functions: `buildRoleRelevance()`, `buildUpdateXml()`, `getRolesFromEditor()`, `xmlEscape()`, `xmlCDataSafe()`, `getEffectiveCategory()`
  - Tests live in `tests/unit/modifier.test.js`

### FR-04 Description Updates

- **D-04:** FR-04 is **deferred to Phase 3**. The `Associated_Roles` MIME field is the sufficient role record for Phase 2. No description field modification is needed in this phase.

### RoleAwareness.db Dependency

- **D-05:** `RoleAwareness.db` already exists on client machines (deployed by a separate process outside this portal). Phase 2 just documents it — path, schema dependency, and fallback behavior (`|False` when DB missing).

- **D-06:** Integration tests cover **API round-trip only**: build updated fixlet XML → PUT to BigFix API → verify 200/201 response. Do **not** test live DB evaluation on clients (that requires a live `RoleAwareness.db`).

### Role and Category List Management

- **D-07:** The 7 current roles are correct for this deployment but the list must be updatable without editing deep JS. Solution: move roles and categories into a clearly marked **inline JSON config block at the top of the `.ojo` JS**, structured as a JSON string constant (e.g., `var PORTAL_CONFIG = { roles: [...], categories: [...] };`). Admins edit this one block only.

- **D-08:** Both roles **and** categories go into the same config block. Category list (currently 9 values) is externalized alongside roles.

### Claude's Discretion

- JSON config block naming and exact structure (e.g., `PORTAL_CONFIG` vs `DERESO_CONFIG`) — pick the clearest name
- Whether to add a comment header above the config block explaining how to update it
- Unit test file structure (mocha, jest, or follow exact Phase 1 pattern)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project & Requirements
- `.planning/PROJECT.md` — Project vision, tech stack, BigFix context
- `.planning/REQUIREMENTS.md` — FR-02 (role association), FR-03 (relevance modification), FR-04 (description — deferred), NFR-01 through NFR-05
- `.planning/ROADMAP.md` — Phase 2 goals, deliverables, success criteria

### Phase Context
- `.planning/phases/01-copier/01-CONTEXT.md` — Phase 1 decisions; establishes pattern (existing .ojo accepted as-is → test + doc). Phase 2 deviates: fix bugs first, then test + doc.
- `.planning/phases/01-copier/01-02-PLAN.md` — Unit test plan for copier (reference for modifier.test.js structure)

### Source Implementation
- `Existing Dashboards/fixlet_modifier.ojo` — Complete modifier dashboard (the file being fixed, tested, documented in this phase)
- `Existing Dashboards/fixlet_copier.ojo` — Phase 1 reference implementation (same .ojo pattern)

### Existing Tests (Phase 1 reference)
- `tests/unit/copier.test.js` — Unit test pattern to follow for modifier.test.js
- `tests/integration/copier.integration.test.js` — Integration test pattern for modifier integration tests

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tests/unit/copier.test.js` — Unit test structure to mirror for modifier unit tests
- `tests/integration/copier.integration.test.js` — Integration test pattern; modifier integration follows same shape
- `tests/fixtures/phase-01/*.ojo` — Fixture pattern; Phase 2 needs `tests/fixtures/phase-02/` equivalents

### Established Patterns
- **BigFix dashboard API:** `API.Get(path, cb)` / `API.Put(path, xml, cb)` for REST; `EvaluateRelevance(rel)` for client-side data
- **MIME field storage:** `Associated_Roles` MIME field (pipe-separated values) already the established pattern for role persistence
- **ActiveXObject XML parsing:** `Msxml2.DOMDocument.6.0` — IE9-based BigFix dashboard constraint; XPath via `selectSingleNode()` / `selectNodes()`
- **Relevance injection pattern:** Remove all `Relevance` nodes containing `'RoleAwareness.db'`, then insert fresh one before `<Category>`
- **Phase 1 delivery:** Raw `.ojo` + docs — Phase 2 follows same delivery model

### Integration Points
- **Phase 1 → Phase 2:** Fixlets copied by Phase 1 (in "Dereso Software Portal" custom site) are the fixlets the modifier operates on. No code coupling — clean hand-off.
- **Phase 2 → Phase 3:** Role-associated fixlets (with MIME fields + relevance) flow into Phase 3 Dispatcher. Modifier makes no changes to action scripts or deployment parameters.
- **RoleAwareness.db:** Lives at `<BigFix client folder>/EC/SoftwarePortal/RoleAwareness.db`. Pre-existing; not provisioned by this portal. Document path and schema in admin guide.

</code_context>

<specifics>
## Specific Ideas

### Config block structure (user direction)
Move roles and categories to an inline JSON constant at the top of the `.ojo` JS — not an external file, not a BigFix setting. Structure as a parseable JSON string so admins can find and edit it without understanding the rest of the JS.

### Modifier.ojo bugs to fix (specific locations)
1. `buildUpdateXml()` line ~567: remove the first `var fixletNode` declaration (keep the second or merge into one)
2. `buildUpdateXml()` line ~600: remove the redundant `var cleanedXml = String(sourceXml).replace(...)` — the cleaned XML is already built at line ~547 and stored; the second one was a copy-paste residue
3. Dead functions to delete: `_previewXml()`, `_renumberRoleRows()`
4. Commented alerts to strip (they were debugging artifacts)

### FR-04 deferred idea (for Phase 3 discussion)
- Add a section to `DefaultActionScript` providing default settings for operators taking actions with the fixlet
- Copy existing description + category into a structured header
- Add a `<DIV>` at top of fixlet description with specific session relevance showing role context
- Discuss in Phase 3 as part of Dispatcher design

</specifics>

<deferred>
## Deferred Ideas

- **FR-04 — Description/DefaultActionScript update (→ Phase 3):** Add a role-context block to `DefaultActionScript` and a DIV at the top of fixlet descriptions showing session relevance. Deferred because it interacts with how the Dispatcher configures actions (Phase 3 scope).

</deferred>

---

*Phase: 2-Modifier*
*Context gathered: 2026-06-14*
