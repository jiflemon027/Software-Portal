# Phase 2: Modifier (Role-Based Categorization) — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-14
**Phase:** 2-Modifier (Role-Based Categorization)
**Areas discussed:** modifier.ojo code condition, FR-04 description updates, RoleAwareness.db dependency, Role list management

---

## Preflight: Stale Directory Removal

A `02-rules-engine/` directory was found in `.planning/phases/` containing plans from a different project (Twenty Five card game). User selected to delete it. It was removed via `git rm -r` and committed before discussion began.

---

## modifier.ojo code condition

| Option | Description | Selected |
|--------|-------------|----------|
| Fix bugs as part of Phase 2 | Clean up 2 bugs, remove dead code, strip debug alerts — then test and document the fixed version. The cleanedXml shadow bug could affect the MIME field on save. | ✓ |
| Test as-is, flag bugs in review | Follow the Phase 1 copier pattern: accept the file as-is, write tests, document, flag bugs in the code review report. | |
| You decide | Pick the cleanest approach based on severity of the bugs. | |

**User's choice:** Fix bugs as part of Phase 2

| Fix scope option | Description | Selected |
|-----------------|-------------|----------|
| Bugs only — minimal diff | Fix the 2 JS bugs (duplicate var, shadowed var). Leave dead code and debug comments in place. | |
| Bugs + cleanup | Fix bugs, remove _prefixed dead functions, strip commented-out alert() calls. Results in a clean, production-ready file. | ✓ |
| Full review — any other issues too | Do a full read-through before fixing: catch anything else beyond the 2 known bugs. | |

**User's choice:** Bugs + cleanup

| Testing option | Description | Selected |
|---------------|-------------|----------|
| Yes — unit tests for pure JS functions | Test buildRoleRelevance(), buildUpdateXml(), getRolesFromEditor(), xmlEscape() etc. Same pattern as copier.test.js from Phase 1. | ✓ |
| Integration tests only | Skip unit tests; focus on integration tests against a real BigFix instance. | |
| Both unit + integration | Full test suite: unit tests for pure functions + integration tests against BigFix staging. | |

**User's choice:** Unit tests for pure JS functions (same pattern as Phase 1)

**Notes:** Phase 2 deviates from Phase 1's "accept as-is" pattern because the modifier has confirmed bugs — specifically the `cleanedXml` shadow could cause the MIME field write to use the wrong (uncleaned) XML.

---

## FR-04 Description Updates

| Option | Description | Selected |
|--------|-------------|----------|
| Add description update to modifier.ojo | Add a Description textarea to the modifier UI. On save, append/replace a role-context block into the fixlet's <Description> element. | |
| FR-04 is already fulfilled by MIME field | The Associated_Roles MIME field is the machine-readable role record. No UI change needed. | |
| Defer description update to Phase 3 | Description updates interact with Phase 3 (Dispatcher) design. | ✓ |

**User's choice:** Defer to Phase 3

**Notes (verbatim from user):** "I want to modify the fixlet so that there is an additional section in the DefaultActionScript section. This addition will provide default settings for operators taking actions with the fixlet. This will need to take a copy of the existing description and the category. I want to ensure the description is then modified to have a DIV at the top with specific session relevance. defer this to phase 3 for discussion."

**Deferred idea captured:** FR-04 → Phase 3 will add a section to `DefaultActionScript` with default operator settings + copy existing description/category + DIV at top with session relevance.

---

## RoleAwareness.db Dependency

| Option | Description | Selected |
|--------|-------------|----------|
| It already exists — Phase 2 just documents the dependency | DB is deployed by a separate process. Phase 2 documents the path and schema requirement. | ✓ |
| Phase 2 must include a provisioning fixlet/script | Phase 2 needs to create a BigFix action/fixlet that deploys RoleAwareness.db to clients. | |
| Out of scope entirely — admin handles it manually | Document as a prerequisite in the admin guide only. | |

**User's choice:** Already exists — Phase 2 documents the dependency

| Test depth option | Description | Selected |
|-----------------|-------------|----------|
| API round-trip only | Test that the modifier correctly builds and PUTs the updated fixlet XML (roles MIME field + relevance injection). Don't test live DB evaluation. | ✓ |
| Full end-to-end incl. DB lookup | Verify the full chain including client relevance evaluation against RoleAwareness.db. | |
| You decide | Match what Phase 1 integration tests covered. | |

**User's choice:** API round-trip only

**Notes:** The `|False` fallback at the end of the generated relevance means a missing DB results in the fixlet silently not being offered — not an error. This should be documented as a known behavior.

---

## Role List Management

| Option | Description | Selected |
|--------|-------------|----------|
| Final list — hardcoded is fine | 7 roles are the real roles. No code change needed. | |
| Correct roles but need a way to update them | The 7 roles are right today but the list will change. Phase 2 should externalize them. | ✓ |
| They're placeholders — need to be replaced | Replace with actual roles (user would provide). | |

**User's choice:** Correct but need a way to update without editing JS

| Externalization option | Description | Selected |
|-----------------------|-------------|----------|
| BigFix client settings (EvaluateRelevance) | Store roles in a BigFix setting read at load time via EvaluateRelevance. | |
| External JSON/text config file | Store roles in EC/SoftwarePortal/roles.json, read via API.Get(). | ✓ (initial) |
| Editable block at top of .ojo JS | Move roles to a clearly marked config block at the top. | |

| Categories option | Description | Selected |
|------------------|-------------|----------|
| Same external JSON file | Add categories to the same config file as roles. | ✓ (initial) |
| Categories stay hardcoded | Keep category list in JS, only externalize roles. | |
| You decide | Pick what's more consistent. | |

| Config file location | Description | Selected |
|--------------------|-------------|----------|
| EC/SoftwarePortal/portal-config.json, read via API.Get | Place alongside RoleAwareness.db, read at load time. | |
| Inline in .ojo as a JSON string constant | Config block at top of .ojo JS, parsed at runtime. Admins edit one place. | ✓ |
| You decide | Pick whatever makes most sense. | |

**User's final choice:** Inline JSON string constant (`var PORTAL_CONFIG = {...}`) at top of `.ojo` JS. Both roles and categories in this block. Admins edit the config block without touching the rest of the JS.

**Notes:** The user initially selected "external JSON file" then refined to "inline in .ojo as JSON string constant" — a middle ground: structured/editable but no external file dependency.

---

## Claude's Discretion

- JSON config constant name (e.g., `PORTAL_CONFIG` vs `DERESO_CONFIG`)
- Comment header explaining how to edit the config block
- Unit test framework choice (follow Phase 1 pattern exactly)

## Deferred Ideas

- **FR-04 (→ Phase 3):** DefaultActionScript default operator settings + description DIV with session relevance. Full discussion at Phase 3 planning.
