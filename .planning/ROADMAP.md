---
document_type: roadmap
version: 1.0
created: 2026-06-11
status: active
---

# Roadmap — Software Portal v1.0

## Milestone 1: MVP (1 month)

### Phase 1: Copier Foundation
**Goal:** Implement the Copier dashboard to import fixlets from external sources into Dereso Software Portal.

**Requirements:** FR-01 (Fixlet Copy)

**Deliverables:**
- BigFix dashboard XML for copier interface
- API integration to BigFix (`GET /fixlets`, `POST /custom-site-fixlets`)
- Fixlet metadata validation and import logic
- Basic error handling and user feedback
- Test suite covering happy path + error cases

**Success Criteria:**
- Copier dashboard loads without errors
- Can successfully import test fixlets from external source
- Metadata preserved during import
- Admin receives clear success/error messages

**Estimated Effort:** 1 week  
**Dependencies:** None

---

### Phase 2: Modifier (Role-Based Categorization)
**Goal:** Enable BigFix admins to associate fixlets with user roles and modify relevance/descriptions accordingly.

**Requirements:** FR-02, FR-03, FR-04 (Role association, relevance modification, description updates)

**Deliverables:**
- BigFix dashboard XML for modifier interface (role matrix UI)
- Role definition storage (settings or relevance)
- Relevance rule generator for role-based access
- Description updater with audit trail
- Test suite covering role creation, association, and relevance generation

**Success Criteria:**
- Modifier dashboard loads and displays fixlet list
- Admin can create/select roles and associate with fixlets
- Generated relevance rules are syntactically correct
- Role-based access verified in test environment
- Descriptions updated with role context

**Estimated Effort:** 1.5 weeks  
**Dependencies:** Phase 1 (requires fixlets in Dereso portal)

---

### Phase 3: Dispatcher (Rapid Deployment)
**Goal:** Implement the Dispatcher dashboard for rapid, confident deployment of role-aware fixlets to target groups.

**Requirements:** FR-05, FR-06, FR-07 (Target deployment, automatic offers, default options)

**Deliverables:**
- BigFix dashboard XML for dispatcher interface
- Target group selection and validation
- Default deployment option pre-population logic
- Automatic 'offer' type creation with auto-derived category
- Deployment execution API calls (`POST /fixlet-deployments`)
- Test suite covering deployment scenarios

**Success Criteria:**
- Dispatcher dashboard loads and displays fixlets + target groups
- Admin can select fixlet, target group, and deployment options
- Offer automatically created with correct category
- Deployment successfully applies in test BigFix instance
- End-to-end workflow (copy → modify → deploy) completes in < 5 min

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
