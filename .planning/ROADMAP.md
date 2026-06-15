---
document_type: roadmap
version: 1.0
created: 2026-06-11
status: active
---

# Roadmap — Software Portal v1.0

## Milestone 1: MVP (1 month)

### Phase 1: Copier Foundation
**Goal:** Test, document, and deliver the Copier dashboard so admins can import fixlets from external sources into Dereso Software Portal.

**Requirements:** FR-01 (Fixlet Copy), NFR-01 through NFR-05

**Plans:** 4 plans

Plans:
- [x] 01-01-PLAN.md — BES Fixlet XML test fixtures (valid-minimal, valid-with-script, invalid-missing-title)
- [x] 01-02-PLAN.md — Unit tests for 6 pure JS functions from fixlet_copier.ojo
- [x] 01-03-PLAN.md — Integration tests for BigFix REST API call patterns (7 scenarios)
- [x] 01-04-PLAN.md — Documentation: admin guide, architecture doc, API integration guide

**Deliverables:**
- BigFix dashboard XML for copier interface (existing: Existing Dashboards/fixlet_copier.ojo)
- Test fixtures (tests/fixtures/phase-01/)
- Unit tests (tests/unit/copier.test.js)
- Integration tests (tests/integration/copier.integration.test.js)
- Admin User Guide (docs/admin-guide.md)
- Architecture Document (docs/architecture.md)
- API Integration Guide (docs/api-integration-guide.md)

**Success Criteria:**
- Copier dashboard loads without errors
- Can successfully import test fixlets from external source
- Metadata preserved during import
- Admin receives clear success/error messages

**Estimated Effort:** 1 week  
**Dependencies:** None

---

### Phase 2: Modifier (Role-Based Categorization)
**Goal:** Fix, clean, test, and deliver the Modifier dashboard so admins can associate fixlets with user roles, inject role-awareness relevance, and update categories. FR-04 (description update) is deferred to Phase 3.

**Requirements:** FR-02, FR-03, FR-04 (FR-04 deferred to Phase 3 per D-04)

**Plans:** 3 plans

Plans:
- [x] 02-01-PLAN.md — Fix modifier.ojo bugs (duplicate fixletNode, stale cleanedXml), remove dead code, add PORTAL_CONFIG block, wire loadRoleValues() + loadCategoryOptions()
- [x] 02-02-PLAN.md — Test fixtures: tests/fixtures/phase-02/ (no-roles + with-roles BES XML)
- [x] 02-03-PLAN.md — Unit tests (6 functions) + integration tests (PUT round-trip, env-var gated)

**Deliverables:**
- Fixed BigFix dashboard XML: Existing Dashboards/fixlet_modifier.ojo
- Test fixtures: tests/fixtures/phase-02/
- Unit tests: tests/unit/modifier.test.js
- Integration tests: tests/integration/modifier.integration.test.js

**Success Criteria:**
- Modifier dashboard loads without JS errors
- PORTAL_CONFIG block lets admin update roles/categories without touching logic code
- node tests/unit/modifier.test.js exits 0
- node tests/integration/modifier.integration.test.js exits 0 (skip mode without BigFix)
- No duplicate var fixletNode, no stale cleanedXml, no dead functions

**Estimated Effort:** 1.5 weeks  
**Dependencies:** Phase 1 (requires fixlets in Dereso portal)

---

### Phase 3: Dispatcher (Rapid Deployment)
**Goal:** Implement the Dispatcher dashboard for rapid, confident deployment of role-aware fixlets to target groups via POST /api/actions with offer-type SourcedFixletAction XML.

**Requirements:** FR-05, FR-06, FR-07 (Target deployment, automatic offers, default options), NFR-01 through NFR-05

**Plans:** 3 plans

Plans:
- [x] 03-01-PLAN.md — Phase-03 test fixtures (valid-fixlet-with-actions.ojo, valid-fixlet-single-action.ojo, sample-action-response.xml) + dispatcher unit tests (buildTargetRelevance, buildExpirationElement, parseActionId, PORTAL_CONFIG)
- [ ] 03-02-PLAN.md — fixlet_dispatcher.ojo: scaffold from modifier, PORTAL_CONFIG (defaultExpirationDays + targetGroups), fixlet list (Name/Category/Roles/Site), detail panel, action dropdown, deployment form, buildDeployXml (SourcedFixletAction + IsOffer), API.Post("actions")
- [ ] 03-03-PLAN.md — dispatcher.integration.test.js (POST round-trip, NFR-01 timing) + docs/dispatcher-admin-guide.md + regression gate (all 3 unit suites)

**Deliverables:**
- BigFix dashboard XML: Existing Dashboards/fixlet_dispatcher.ojo
- Test fixtures: tests/fixtures/phase-03/
- Unit tests: tests/unit/dispatcher.test.js
- Integration tests: tests/integration/dispatcher.integration.test.js
- Admin guide: docs/dispatcher-admin-guide.md

**Success Criteria:**
- Dispatcher dashboard loads and displays all fixlets from Dereso Software Portal with Name/Category/Roles/Site columns
- Admin can select fixlet, action, target group (from PORTAL_CONFIG list or free-text), and expiration
- Offer automatically created with category and description from selected fixlet (FR-06)
- API.Post("actions") fires SourcedFixletAction XML; success banner shows deployment ID (D-11)
- node tests/unit/dispatcher.test.js exits 0
- node tests/integration/dispatcher.integration.test.js exits 0 in skip mode
- Regression gate: dispatcher + modifier + copier unit tests all pass

**Estimated Effort:** 1.5 weeks  
**Dependencies:** Phase 1 & 2 (requires categorized fixlets)

---

## Quality Gates (All Phases)

- ✅ **Code Review**: All code reviewed for correctness, security, maintainability
- ✅ **Testing**: Unit + integration tests for each phase
- ✅ **Performance**: Operations complete within NFR-01 targets
- ✅ **Security**: Admin auth, audit logging, no credential exposure
- ✅ **Documentation**: Inline code comments, user guide, API docs

---

## Milestone 2: Hardening (Post-MVP, optional)

### Phase 4: Robustness & Configuration
- Advanced error recovery and rollback procedures
- Configurable role list, deployment defaults
- Enhanced logging and monitoring
- Performance optimization for large fixlet sets
- Admin configuration UI

### Phase 5: Localization & Advanced Features
- Multi-language support
- Fixlet versioning and rollback
- Bulk operations (copy/modify/deploy multiple)
- Integration with external systems (optional)

---

## Timeline

| Phase | Duration | Start | End | Owner |
|-------|----------|-------|-----|-------|
| Phase 1: Copier | 1 week | Week 1 | Week 1 | TBD |
| Phase 2: Modifier | 1.5 weeks | Week 2 | Week 3 | TBD |
| Phase 3: Dispatcher | 1.5 weeks | Week 3 | Week 4 | TBD |
| Testing & Review | 0.5 weeks | Week 4 | Week 4 | TBD |
| **MVP Complete** | — | — | **End Week 4** | — |

---

## Success Metrics

- ✅ All 3 dashboards deployed to production
- ✅ < 5 min per complete workflow (copy → modify → deploy)
- ✅ Zero critical issues in code review
- ✅ BigFix admins trained and using dashboards
- ✅ Audit trail of all operations maintained

---

## Notes

- BigFix instance must be accessible throughout development and testing
- Role list must be finalized before Phase 2 begins
- Default deployment options require sign-off from ops team before Phase 3 deploy
- Consider feature flags for gradual rollout to production
