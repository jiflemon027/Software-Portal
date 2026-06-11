---
document_type: context
phase: 1
phase_name: Copier Foundation
created: 2026-06-11
status: ready-for-planning
---

# Phase 1: Copier Foundation — Context & Decisions

## Domain

**Phase 1 implements the Copier Dashboard** — a BigFix wizard that enables administrators to import installation fixlets from external sources into the "Dereso Software Portal" custom site.

This is the first phase of the three-phase MVP. Copier operates **standalone** in Phase 1 (no role-based logic yet — that's Phase 2).

---

## Locked Requirements (from REQUIREMENTS.md)

**FR-01: Fixlet Copy Capability**
- Select source fixlet(s) from external repository
- Specify target custom site ("Dereso Software Portal")
- Dashboard validates copy compatibility
- Fixlets copied with all metadata (name, description, action script, relevance)

**Acceptance Criteria:**
- ✅ Copier dashboard loads without errors
- ✅ Can successfully import test fixlets from external source
- ✅ Metadata preserved during import
- ✅ Admin receives clear success/error messages

---

## Decisions Captured

### Architecture & Implementation

| Decision | Rationale |
|----------|-----------|
| **Use existing copier.ojo as-is** | The existing `fixlet_copier.ojo` file provides complete, tested functionality. No re-implementation needed. |
| **Standalone copier in Phase 1** | Copier operates independently; integration with Modifier (Phase 2) and Dispatcher (Phase 3) happens downstream. Clear separation of concerns. |
| **Delivery: Raw .ojo + docs** | Distribute the XML dashboard file alongside comprehensive documentation (admin guide, architecture, API integration reference). |

### Testing Strategy

| Scope | Details |
|-------|---------|
| **Unit tests** | Test fixlet metadata parsing, validation logic, error handling paths |
| **Integration tests** | Test with actual BigFix instance: source API connectivity, target site operations, copy success/failure scenarios |
| **Test coverage** | Happy path (successful copy) + error cases (validation failures, API errors, permission issues) |

### Documentation Required

| Document | Purpose |
|----------|---------|
| **Admin User Guide** | How BigFix admins use the Copier dashboard; step-by-step workflow; troubleshooting common issues |
| **Architecture/Design Doc** | How the copier works internally; data flow; BigFix API integration points; validation logic |
| **API Integration Guide** | Technical reference for BigFix REST API calls used by copier; required endpoints (`GET /fixlets`, `POST /custom-site-fixlets`); authentication; error responses |

### Known Constraints

- ✅ **"Dereso Software Portal" target site** must exist in the BigFix instance before copier is used
- ✅ **BigFix admin authentication** required (enforced by BigFix dashboard security model)
- ✅ **Metadata preservation** — all fixlet properties (name, description, relevance, action script) copied exactly; no transformations in Phase 1

### Out of Scope for Phase 1

- Role-based fixlet association (Phase 2)
- Fixlet deployment/offers (Phase 3)
- Multi-tenant BigFix support
- Automated retries or recovery
- Bulk copy scheduling

---

## Integration Points

### Phase 1 → Phase 2 Interface

Phase 2 (Modifier) will consume fixlets copied by Phase 1. No code changes needed in Phase 1; clean hand-off:
- **Input:** Fixlets in "Dereso Software Portal" custom site
- **Output:** Same fixlets, now role-associated and with modified relevance (Phase 2)

### Phase 1 → Phase 3 Interface

Phase 3 (Dispatcher) will deploy role-modified fixlets. Again, clean hand-off:
- **Input:** Role-categorized fixlets from Phase 2
- **Output:** Deployments with auto-created offers (Phase 3)

---

## Canonical References

- [ROADMAP.md](../../../ROADMAP.md) — Phase 1 goals, timeline, success criteria
- [REQUIREMENTS.md](../../../REQUIREMENTS.md) — Functional & non-functional requirements (FR-01, NFR-01 through NFR-05)
- [PROJECT.md](../../../PROJECT.md) — Project vision, tech stack, BigFix context
- [Existing Dashboards/fixlet_copier.ojo](../../../Existing%20Dashboards/fixlet_copier.ojo) — Complete implementation to be tested and documented

---

## Success Criteria (Phase 1 Completion)

✅ Copier dashboard tested (unit + integration)  
✅ Copier metadata handling verified  
✅ Admin user guide written  
✅ Architecture documentation complete  
✅ BigFix API integration guide provided  
✅ All tests passing  
✅ Ready for Phase 2 handoff  

---

## Notes for Planner & Researcher

1. **No implementation work needed** — the copier.ojo file is complete and accepted. Focus Phase 1 planning on:
   - Test suite creation and execution
   - Documentation generation (admin guide, architecture, API reference)
   - Code review and cleanup (if needed)

2. **Integration point:** Phase 2 planner should read this CONTEXT.md to understand how fixlets flow from Phase 1 → Phase 2.

3. **Deferred to future phases:**
   - Advanced error recovery and retry logic (Phase 4: Robustness)
   - Bulk operations (Phase 5)
   - Localization (Phase 5)

