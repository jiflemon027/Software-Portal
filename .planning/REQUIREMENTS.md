---
document_type: requirements
version: 1.0
created: 2026-06-11
scope: Software Portal MVP
---

# Requirements — Software Portal

## Functional Requirements

### FR-01: Fixlet Copy Capability
Users must be able to copy installation fixlets from external BigFix instances or repositories into the "Dereso Software Portal" custom site.

**Acceptance Criteria:**
- Select source fixlet(s) from external repository
- Specify target custom site ("Dereso Software Portal")
- Dashboard validates copy compatibility
- Fixlets copied with all metadata (name, description, action script, relevance)

### FR-02: Role-Based Fixlet Association
Users must be able to create associations between user roles and software fixlets, enabling role-based access control.

**Acceptance Criteria:**
- Define or select user roles (e.g., "Developer", "Manager", "User")
- Associate roles with fixlets
- Modifier dashboard displays role-fixlet matrix
- Association data persists in BigFix

### FR-03: Role-Based Relevance Modification
When a role is associated with a fixlet, the fixlet's relevance rule must be modified to enforce role-based access.

**Acceptance Criteria:**
- System generates role-check relevance rules
- Relevance rules are syntactically correct and testable
- Modified relevance only returns true for users in authorized roles
- Original relevance logic is preserved and combined with role logic

### FR-04: Role-Based Description Update
Fixlet descriptions must be updated to reflect role associations and access context.

**Acceptance Criteria:**
- System appends or updates description with role information
- Description updates are auditable and reversible
- Format is consistent and readable

### FR-05: Target Group Deployment
Users must be able to deploy role-aware fixlets to specific target groups.

**Acceptance Criteria:**
- Select fixlet and target group
- Specify deployment parameters (installer, expiration date)
- Dashboard validates target group matches role (optional cross-check)
- Deployment created in BigFix

### FR-06: Automatic Offer Creation
When deploying fixlets, the dashboard must automatically create 'offer' style deployments with auto-derived category.

**Acceptance Criteria:**
- Offer type is selected automatically
- Category derived from selected fixlet's category
- Offer created successfully in BigFix
- Admin confirms deployment before final apply

### FR-07: Default Deployment Options
Deployment dashboard must pre-populate sensible default options to reduce manual selection.

**Acceptance Criteria:**
- Installer defaults to most recent available
- Target group selected by user
- Expiration defaults to 7 days (configurable)
- All defaults can be overridden by user

## Non-Functional Requirements

### NFR-01: Performance
- Dashboard operations complete in < 2 seconds
- Fixlet copy operation completes in < 30 seconds (per fixlet)
- Role association updates apply in < 5 seconds

### NFR-02: Reliability
- All operations are atomic or have clear rollback procedures
- Dashboard recovers gracefully from BigFix API errors
- Error messages guide admin to resolution

### NFR-03: Security
- All operations require BigFix admin authentication
- Dashboard respects BigFix role-based access controls
- Audit trail of all modifications (copy, modify, deploy)

### NFR-04: Usability
- Dashboards follow BigFix UI conventions
- All operations completable in < 5 minutes per fixlet
- Clear status indicators and progress feedback
- Help text and tooltips for all controls

### NFR-05: Maintainability
- Code is modular and testable
- Relevance rules are documented
- Configuration is externalized (configurable role list, defaults, etc.)

## Out of Scope

- Multi-tenant BigFix instances
- Advanced role hierarchies or nested permissions
- Fixlet versioning or rollback
- Integration with external RBAC systems (Active Directory, etc.)
- UI skins or theme customization beyond BigFix defaults

---

## Phase Mapping

| Phase | Requirements |
|-------|--------------|
| **Phase 1: Foundation** | FR-01 (Copier UI/API integration) |
| **Phase 2: Modifier** | FR-02, FR-03, FR-04 (Role association + relevance modification) |
| **Phase 3: Dispatcher** | FR-05, FR-06, FR-07 (Deployment + offers) |
| **All Phases** | NFR-01 through NFR-05 |

---

## Success Criteria

✅ All 7 functional requirements implemented and tested  
✅ All 5 non-functional requirements met  
✅ End-to-end workflow (copy → modify → deploy) completes in < 5 minutes  
✅ BigFix admins can use all three dashboards independently or in sequence  
✅ Zero critical security or reliability issues in code review  
