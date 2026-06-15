---
document_type: context
phase: 3
phase_name: Dispatcher (Rapid Deployment)
created: 2026-06-14
status: ready-for-planning
---

# Phase 3: Dispatcher (Rapid Deployment) — Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 3 builds the Dispatcher Dashboard (`fixlet_dispatcher.ojo`) — a BigFix wizard that lets admins select a fixlet from the "Dereso Software Portal" custom site, auto-populate deployment options (offer type, category derived from fixlet, expiration default, target group), preview the offer, and fire a `POST /fixlet-deployments` call to create the deployment.

This phase covers **FR-05** (target group deployment), **FR-06** (automatic offer creation with auto-derived category), and **FR-07** (default deployment options). FR-04 (description/DefaultActionScript updates) is explicitly deferred to Phase 4.

</domain>

<decisions>
## Implementation Decisions

### Starting Point & Structure

- **D-01:** Scaffold `fixlet_dispatcher.ojo` from `Existing Dashboards/fixlet_modifier.ojo`. Strip role/category edit logic; keep the fixlet list, search bar, detail panel, and action button scaffold — the structural layout matches the dispatcher UX.

- **D-02:** Filename: `Existing Dashboards/fixlet_dispatcher.ojo`. Dashboard title: `Dereso Fixlet Dispatcher`. BigFix Dashboards menu entry follows the same pattern as copier and modifier.

- **D-03:** PORTAL_CONFIG block (at top of JS, same pattern as modifier) contains:
  ```js
  var PORTAL_CONFIG = {
    defaultExpirationDays: 7,
    targetGroups: [ /* list of common target group names */ ]
  };
  ```
  Admins edit only this block to add/remove target groups or change the expiry default.

### Fixlet List & Filtering

- **D-04:** Show **all fixlets** in the "Dereso Software Portal" custom site — no role-assignment filter. Admin sees the full portal inventory.

- **D-05:** Fixlet list columns: **Name, Category, Roles, Site**. Roles column reads the `Associated_Roles` MIME field (shows "—" if unset).

- **D-06:** Live name-search bar above the list — same debounced filter pattern as modifier.ojo. No additional column-based filters.

### Detail Panel (when fixlet is selected)

- **D-07:** The right-hand detail panel shows:
  - Fixlet **Name**
  - Fixlet **Category** (auto-populates offer category field)
  - **Assigned Roles** (from `Associated_Roles` MIME field — read-only, confirmation context)
  - **Existing action count** (number of actions defined on the fixlet)
  - **Action dropdown** — admin selects which action to deploy (see D-08)
  - **Deployment form** (target group, expiration, offer preview)

- **D-08:** When a fixlet has multiple actions, the admin selects the action from a dropdown in the detail panel. No auto-selection — explicit admin choice.

### Deployment Parameters & Form

- **D-09:** Target group input: a `<select>` dropdown populated from `PORTAL_CONFIG.targetGroups` **plus** a free-text `<input>` fallback for one-off group names not in the config list.

- **D-10:** Confirmation UX: a live preview panel updates as the admin fills in the form — shows offer title, description excerpt, category, target group, selected action, and expiry date. A single **"Deploy"** button at the bottom fires the `POST`. No separate confirm dialog.

- **D-11:** Post-deployment feedback:
  - **Success:** show the returned deployment ID in a success banner + a "Deploy Another" button that resets the form.
  - **Failure:** show the error message inline (below the Deploy button) with enough detail for the admin to act on it.

### Offer Field Mapping (FR-06)

When creating the offer-style deployment, the following fields are automatically transposed from the selected fixlet:

| Offer field | Source |
|---|---|
| Title | Fixlet name |
| Description | Fixlet `<Description>` content (copied as-is) |
| Category | Fixlet `<Category>` value (auto-derived, FR-06) |
| Type | `"offer"` (hardcoded) |
| Action | Admin-selected from dropdown |
| Target group | Admin-selected (PORTAL_CONFIG list or free-text) |
| Expiration | `defaultExpirationDays` from PORTAL_CONFIG (overrideable via date input) |

### FR-04 Scope

- **D-12:** FR-04 (fixlet description role-context DIV + DefaultActionScript defaults) is **deferred to Phase 4**. Phase 3 implements only FR-05, FR-06, FR-07. The dispatcher does not modify fixlet XML before deploying.

### Deployment Endpoint (Research Resolution)

- **D-13:** Deployment endpoint resolved to **`POST /api/actions`** (not `/fixlet-deployments`). Research confirmed via official BigFix REST API docs and restapi-examples repository: actions (including offer-type deployments) are created at `/api/actions` using `SourcedFixletAction` XML. The `/fixlet-deployments` reference in the domain section above was a placeholder assumption from discuss-phase, now superseded by D-13.

### Claude's Discretion

- Exact structure of the SourcedFixletAction request body sub-fields (staging-instance verification may be needed for offer Settings vs. SettingsLocks placement)
- Whether to add a "Reset" button alongside "Deploy Another" in the success state
- Column widths and panel proportions in the scaffold (follow modifier.ojo proportions)
- Whether to include a page-size selector in the fixlet list (include if modifier has one and it scaffolds cleanly)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project & Requirements
- `.planning/PROJECT.md` — Project vision, tech stack, BigFix context
- `.planning/REQUIREMENTS.md` — FR-05 (target deployment), FR-06 (offer creation), FR-07 (defaults), NFR-01 through NFR-05
- `.planning/ROADMAP.md` — Phase 3 goals, deliverables, success criteria

### Phase Context
- `.planning/phases/01-copier/01-CONTEXT.md` — Phase 1 decisions; copier delivery pattern (.ojo + docs)
- `.planning/phases/02-modifier/02-CONTEXT.md` — Phase 2 decisions; PORTAL_CONFIG pattern, MIME field storage, API.Get/Put, IE9 constraints, test structure
- `.planning/phases/02-modifier/02-CONTEXT.md` §specifics — FR-04 deferred ideas (for reference; Phase 3 does NOT implement)

### Source Implementation (scaffold base)
- `Existing Dashboards/fixlet_modifier.ojo` — Template for dispatcher scaffold; strip role/category edit logic, keep fixlet list + detail panel + action button structure
- `Existing Dashboards/fixlet_copier.ojo` — Phase 1 reference (.ojo format and BigFix Wizard XML structure)

### Existing Tests (reference patterns)
- `tests/unit/modifier.test.js` — Unit test structure to mirror for `dispatcher.test.js`
- `tests/integration/modifier.integration.test.js` — Integration test pattern for dispatcher integration tests
- `tests/unit/copier.test.js` — Additional unit test reference

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Existing Dashboards/fixlet_modifier.ojo` — Scaffold source; reuse HTML structure, CSS classes (`.panel`, `.panelBody`, `.tableGrid`, `.btn`, `.btnGreen`), fixlet list rendering loop, search bar filter, pagination, and `API.Get()` fetch-on-load pattern
- `tests/unit/modifier.test.js` / `tests/integration/modifier.integration.test.js` — Test file patterns; dispatcher tests mirror these exactly

### Established Patterns
- **BigFix Wizard XML:** `<BES><Wizard>` structure, `IE=9` meta, single `<Page Name="main">` containing all HTML/JS in `<Head>` CDATA block
- **API pattern:** `API.Get(path, callback)` for fetching; `API.Put(path, xml, callback)` for updates; Phase 3 adds `API.Post(path, xml, callback)` for `POST /fixlet-deployments`
- **PORTAL_CONFIG block:** Inline JSON constant at the top of the JS, clearly delimited with comments — admins edit only this block
- **MIME field read:** `Associated_Roles` is a MIME field on the fixlet node — read via XPath `selectNodes('MIME')`, filter by `Name` attribute
- **IE9/ActiveX XML:** `Msxml2.DOMDocument.6.0` ActiveXObject for XML parsing; `selectSingleNode()` / `selectNodes()` XPath

### Integration Points
- **Phase 2 → Phase 3:** Dispatcher reads fixlets from "Dereso Software Portal" custom site. Role MIME fields (`Associated_Roles`) and `Category` written by the Modifier are the data sources for the dispatcher's detail panel and offer mapping.
- **BigFix REST API — new call for Phase 3:** `POST /api/fixlet-deployments` (or BigFix equivalent endpoint) — planner must research exact endpoint path, request body schema, and required headers.
- **No Phase 3 → Phase 4 output artifact** — dispatcher creates deployments in BigFix; no files or state passed to Phase 4.

</code_context>

<specifics>
## Specific Ideas

### Offer field transposition (user requirement)
When creating the offer, **both the fixlet description and category must be transposed** into the offer's description and category fields exactly — not summarised or reformatted. The offer should mirror the fixlet's content so admins see a consistent view in the BigFix console.

### Detail panel layout (from discussion)
The detail panel should show: name → category → assigned roles → action count → action dropdown → deployment form (target group, expiry, preview). Sequential top-to-bottom flow so admin reads from "what is this fixlet" to "how should I deploy it."

</specifics>

<deferred>
## Deferred Ideas

- **FR-04 — Description/DefaultActionScript update (→ Phase 4):** Add a role-context `<DIV>` to fixlet descriptions and a `DefaultActionScript` defaults block. Was deferred from Phase 2 to Phase 3; now deferred again to Phase 4. When implemented, it should run as a pre-deploy step or a separate "Update Fixlet" operation in the dispatcher (or a fourth dashboard). Specific ideas in `.planning/phases/02-modifier/02-CONTEXT.md` §deferred.

</deferred>

---

*Phase: 3-Dispatcher (Rapid Deployment)*
*Context gathered: 2026-06-14*
