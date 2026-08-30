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

### FR-08: Automatic User Registration on Logon
The system must automatically register a user in the RoleAwareness database the first time they log on to a managed endpoint, keep their `LastSeen` timestamp current on every subsequent logon, and keep their active role mappings from expiring — all without requiring admin action.

**Acceptance Criteria:**
- A Windows Scheduled Task (`RoleDB_Maintenance`) is deployed to each managed endpoint alongside DB initialisation
- Task triggers at user logon (any user), runs as SYSTEM
- The task reruns `Initialize-RoleDb.ps1` itself (the same script the init task runs) rather than a
  separate logon script — every step in it is idempotent, so a rerun on an already-initialised
  endpoint only performs the current-user upsert and the Valid_to renewal below
- On trigger: detects the logged-on user via `Win32_Process (explorer.exe)` owner query — same method as the init task, guaranteeing identical username format (SAM account name without domain prefix). This is a single one-shot check with no retry/poll loop; a logon where `explorer.exe` isn't yet visible is a no-op, picked up on the next logon
- If user does not exist in `Users` table: `INSERT` with `LastSeen = now`
- If user already exists: `UPDATE LastSeen = now` only (all other fields preserved)
- The logged-on user's `Map` rows where `Active = 1 AND Locked_by_Override = 0` have `Valid_to`
  extended to `now + ValidityMonths` (default 6) on every logon; rows with `Locked_by_Override = 1`
  are always skipped — an admin override must never be silently overwritten by automatic renewal
- The init task itself (not just the scheduled task) is redeploy-safe on an already-initialised
  endpoint: rewriting `Sqlite-Helper.ps1`/`Initialize-RoleDb.ps1` and rerunning the latter is
  unconditional, so redeploying migrates an existing `RoleAwareness.db` to the current schema
  (e.g. adding `Updated_on`/`Valid_to`) without touching existing `Map`/`Users`/`Roles` rows.
  Only the `RoleDB_Maintenance` task *registration* is conditional on it not already existing
- Task registration is idempotent: registration is skipped once `RoleDB_Maintenance` already exists on the endpoint
- Task is in scope for Milestone 2 (Role Awareness) — prerequisite for accurate role relevance

### FR-09: Role-Aware Web Report
BigFix operators must be able to view a consolidated Web Report showing all role-aware
fixlets in the Software Portal site alongside the actions generated from them, filtered to
only actions that affect computers within the logged-in operator's assigned scope.

**Acceptance Criteria:**
- Web Report retrieves all fixlets from the Dereso Software Portal site that carry
  role-awareness MIME fields (added by the Modifier dashboard)
- Web Report retrieves all actions spawned from those fixlets, identified via role-tracking
  MIME fields on the action XML
- Fixlets are displayed with their associated role(s) from the MIME fields
- Actions are displayed nested under their source fixlet (expandable row)
- Action list is scoped server-side to the logged-in operator's assigned computers —
  actions targeting computers outside the operator's scope are not shown
- Fixlets with no actions in scope display "No actions affecting your devices" on expand
- Report supports client-side filtering by role (dropdown — no server round-trip)
- Action rows show current BigFix action status (Open, Expired, Stopped, etc.)
- Delivered as a `.beswrpt` file importable into BigFix Web Reports
- All session relevance output is JS-escaped before injection into array literals (XSS mitigation)

### FR-10: Fixlet Version Update Tracking
The system must scan configurable source sites for fixlets that are newer versions of those already in the "Dereso Software Portal" site, present updates in a comparison table enabling admin-driven batch copy with automatic category/role transfer and metadata inheritance, stamp superseded portal fixlets with `X-Superseded-By` MIME field after successful copy, and surface net-new products in a "New Arrivals" tab with suggested categories from a CSV-based embedded lookup table.

**Acceptance Criteria:**
- Admin clicks "Scan for Updates" to trigger scan (no auto-scan on dashboard load — D-01)
- Live status message shows progress: "Scanning site X of Y… N fixlets found so far" (D-02)
- Results shown in comparison table with columns: checkbox, Current Portal Fixlet, Available Update, Source Site, Category, Roles (D-14)
- Version matching uses `/ v\d[\d.]+/g` strip regex; remainder is the product key (D-04)
- All newer versions shown per product (not just latest); all source site matches shown without deduplication (D-06, D-07)
- Two-step copy flow: checkboxes → "Copy Selected" → preview panel (editable Category + Roles) → "Confirm" (D-11)
- Category pre-filled from old portal fixlet `<Category>` element; fallback to CSV lookup (D-16)
- Roles pre-filled from old portal fixlet `Associated_Roles` MIME field; default blank if absent (D-17)
- Batch copy is atomic per item; partial failures reported individually in results panel (D-12)
- After successful copy, old portal fixlet stamped with `X-Superseded-By: <newFixletId>` MIME field via API.Put (D-08)
- "New Arrivals" tab shows products in source sites with no matching portal fixlet; suggested category from embedded CSV lookup; roles left blank (D-09)
- Source site list configured in `PORTAL_CONFIG.sourceSites` array (D-05)
- CSV shortlist categories compiled into embedded `var CATEGORY_MAP = {...}` constant at build time (D-18)

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
- Fixlet rollback (update tracking is covered by FR-10; rollback/revert remains out of scope)
- Integration with external RBAC systems (Active Directory, etc.)
- UI skins or theme customization beyond BigFix defaults

---

## Phase Mapping

| Phase | Requirements |
|-------|--------------|
| **Phase 1: Foundation** | FR-01 (Copier UI/API integration) |
| **Phase 2: Modifier** | FR-02, FR-03, FR-04 (Role association + relevance modification) |
| **Phase 3: Dispatcher** | FR-05, FR-06, FR-07 (Deployment + offers) |
| **Phase 4: Role Assigner** | FR-02 (extended — user-level DB mapping), FR-03 (extended — DB-backed relevance) |
| **Phase 5: Robustness** | FR-08 (Automatic user registration on logon), FR-09 (Role-aware web report) |
| **Phase 6: Update Tracker** | FR-10 (Fixlet version update tracking), NFR-01 through NFR-05 |
| **All Phases** | NFR-01 through NFR-05 |

---

## Success Criteria

✅ All 10 functional requirements implemented and tested
✅ All 5 non-functional requirements met
✅ End-to-end workflow (copy → modify → deploy) completes in < 5 minutes
✅ BigFix admins can use all dashboards independently or in sequence
✅ Zero critical security or reliability issues in code review
