---
phase: 06-update-tracker
created: 2026-07-01
status: ready-for-planning
---

# Phase 6: Fixlet Update Tracker — Context

**Gathered:** 2026-07-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Build a new BigFix dashboard (`fixlet_update_tracker.ojo`) that:
1. Scans a configurable list of source sites for fixlets that are newer versions of those already in the "Dereso Software Portal" site
2. Presents available updates in a comparison table so admins can select and copy them
3. Automatically transfers category and role assignments from the old version to the new one
4. Marks the old portal fixlet as superseded after copying
5. Surfaces net-new products (in source sites but not in the portal) in a separate "New Arrivals" tab with suggested category

**NOT in scope for this phase:** auto-deploying the newly copied fixlets. Admins must use the existing Dispatcher dashboard to deploy after copying.

</domain>

<decisions>
## Implementation Decisions

### Scan Trigger & Freshness
- **D-01:** Manual-only scan — admin clicks a "Scan for Updates" button to trigger the scan. No auto-scan on dashboard load.
- **D-02:** During the scan, show a live status message with progress counts: "Scanning site X of Y… N fixlets checked so far." This gives confidence on large source sites.
- **D-03:** Results do not persist — cleared each time the dashboard is closed or re-opened. No sessionStorage caching. Admin re-scans on each visit.

### Version Matching
- **D-04:** Match fixlets by stripping the version segment from their name. Regex: strip ` vX.Y.Z` (space-v-digits-dots pattern, e.g. ` v26.01`, ` v11.0.31.11`, ` v25.0.3.9`). The remainder (product name + platform suffix) is the product key used for matching.
  - Example: `"7-Zip (MSI) v26.01 - Windows (x64)"` → key `"7-Zip (MSI) - Windows (x64)"`
  - Example: `"Eclipse Temurin JDK with Hotspot v21.0.11.10 - Windows (x64)"` → key `"Eclipse Temurin JDK with Hotspot - Windows (x64)"`
- **D-05:** Source sites are configured in `PORTAL_CONFIG.sourceSites` as an array of site name strings — same pattern as `PORTAL_CONFIG.roles` and `PORTAL_CONFIG.categories` in existing dashboards.

### Multi-version & Duplicate Handling
- **D-06:** Show **all** newer versions found (not just the latest). If the portal has v26.01 and source has v26.02 and v27.00, both rows appear in the Updates table. Admin decides which version(s) to copy.
- **D-07:** When the same product appears in multiple source sites, show **all** matches with the source site name visible in the table. No deduplication, no priority ordering. Admin selects which source to copy from.

### Old Version Fate
- **D-08:** After a successful copy, stamp `X-Superseded-By: <newFixletId>` as a MIME field on the old portal fixlet using `API.Put`. The old fixlet remains in the portal and is not deleted. The Modifier dashboard (which already shows MIME fields) will make this field visible to admins who need to clean up manually.

### Net-New Products (New Arrivals)
- **D-09:** Products found in source sites with no matching portal fixlet are shown in the "New Arrivals" tab. Category is suggested from the embedded CSV lookup (shortlist category from `software_categorized.csv`). Roles are left blank — admin must assign roles manually via the Modifier dashboard after copying.

### Match Review & Confirmation Flow
- **D-10:** Matched results are shown **directly** in the comparison table — no separate match-review or approval step before the table populates.
- **D-11:** Copying is a **two-step** flow: admin selects fixlets via checkboxes → clicks "Copy Selected" → a preview panel appears showing all planned updates (editable) → admin clicks "Confirm" to execute.
- **D-12:** **Batch mode**: admin can check multiple rows and copy them all in a single "Copy Selected" action. Each copy is atomic; partial failures are reported individually in the results panel.

### Preview Panel (Step 2 of Copy Flow)
- **D-13:** The preview panel shows a summary table of all selected updates: `From (current portal name)` → `To (new fixlet name)`, an editable **Category** dropdown (pre-filled from the old portal fixlet's `<Category>` element, falling back to CSV lookup), and editable **Roles** (pre-filled from the old fixlet's `Associated_Roles` MIME field). Admin can adjust before confirming.

### Dashboard Layout
- **D-14:** **Comparison table** layout (not the list+panel pattern used by Copier/Modifier). Columns: `☐ (checkbox) | Current Portal Fixlet | Available Update | Source Site | Category | Roles | Action`.
- **D-15:** **Two tabs**: "Updates" (portal fixlets with newer versions available) and "New Arrivals" (net-new products in source sites). Tab counts shown after scan completes, e.g., "Updates (12)  New Arrivals (4)".

### Category & Role Data Sources
- **D-16:** Category is read from the **native BigFix `<Category>` XML element** on the old portal fixlet (not a custom MIME field — confirmed by reading fixlet_modifier.ojo). If the old fixlet has no category, fall back to the CSV lookup table.
- **D-17:** Roles are read from the **`Associated_Roles` MIME field** on the old portal fixlet (established in Phase 2). If no `Associated_Roles` field is present, roles default to blank.

### Embedded CSV Lookup
- **D-18:** The `software_categorized.csv` shortlist categories are compiled into a JavaScript object (lookup table) embedded in the dashboard's `PORTAL_CONFIG` or as a `var CATEGORY_MAP = {...}` constant. Keyed by version-stripped product name. This avoids any file system or external dependency at runtime.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Dashboards (patterns to follow / integrate with)
- `Existing Dashboards/fixlet_copier.ojo` — Copy fixlet flow: `API.Get("fixlet/<id>")`, XML parse, `API.Post("custom-site/<site>/fixlet")`. Phase 6 reuses this copy pattern.
- `Existing Dashboards/fixlet_modifier.ojo` — MIME field write pattern (`Associated_Roles`), category in `<Category>` XML element, `PORTAL_CONFIG` block structure.
- `Existing Dashboards/fixlet_dispatcher.ojo` — `PORTAL_CONFIG.targetGroups` pattern; confirms IE9 + `language="javascript"` requirement.

### Category Source Data
- `Dashboard_4_samples/software_categorized.csv` — Shortlist Category column (col 5) is the preferred category value. Product name (col 2) must be version-stripped to build the lookup key.

### Requirements
- `.planning/REQUIREMENTS.md` — Note: "Fixlet versioning or rollback" is listed as out-of-scope for v1.0. Phase 6 supersedes that constraint — planner should add FR-10 covering fixlet update tracking.

### Planning Context
- `.planning/phases/02-modifier/02-CONTEXT.md` — Decisions on `Associated_Roles` MIME field format and PORTAL_CONFIG structure.
- `.planning/ROADMAP.md` — Phase 6 entry currently a placeholder; planner should update it with the correct goal and plans.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Copier flow** (`fixlet_copier.ojo`): `API.Get("fixlet/<id>/site/<site>")` + parse BES XML + `API.Post("custom-site/Dereso Software Portal/fixlet")` — reuse verbatim for the copy step in Phase 6.
- **MIME field write** (`fixlet_modifier.ojo` lines 609–620): `origDoc.createElement("MIMEField")` pattern — reuse to write `X-Superseded-By` on the old fixlet.
- **`EvaluateRelevance()`** (all dashboards): used to load portal fixlet list and source site fixlet lists. Phase 6 will call it once per source site in the scan loop.
- **`htmlEscape()`** (all dashboards): must be applied to all fixlet names inserted into DOM.
- **`makeSortHeader()` / table sort pattern** (all dashboards): reuse for sortable comparison table columns.
- **`PORTAL_CONFIG` block**: add `sourceSites: ["SiteName1", "SiteName2"]` alongside existing roles/categories fields.

### Established Patterns
- **IE9 compatibility**: use `language="javascript"`, `var` (no `let`/`const`), no arrow functions, no template literals, no `Array.from`, no `fetch`.
- **XML manipulation**: use `origDoc.selectSingleNode()` / `selectNodes()` (MSXML IE9 API) — not `querySelector`.
- **Status bar**: `document.getElementById("status").innerText = msg` — same pattern across all dashboards.
- **`API.Put(path, xml, cb)`**: used in modifier to update fixlet XML — Phase 6 uses this to write `X-Superseded-By` on the old fixlet.

### Integration Points
- Phase 6 reads from the portal site (same Relevance query used by Modifier: `bes fixlets whose (exists site whose (name of it contains "Dereso Software Portal") of it)`).
- Phase 6 reads from source sites via `EvaluateRelevance` with site-scoped fixlet queries.
- After copying, the new fixlet is a plain portal fixlet — admin uses existing Modifier dashboard to add role-awareness relevance (Phase 6 only transfers category and `Associated_Roles` MIME field, not the generated role relevance body).

</code_context>

<specifics>
## Specific Ideas

- The `software_categorized.csv` shortlist categories should be the **only** category values in the embedded lookup — not the "Specific Category" column. The user confirmed preference for shortlist categories.
- Product key derivation (version strip) must handle the "Eclipse Temurin JDK with Hotspot 25 v25.0.3.9" case — where a number appears before the version tag. The ` v\d[\d.]+` regex handles this correctly since it only strips the token prefixed with a space and a lowercase `v`.
- Tab badge counts after scan: "Updates (12)  New Arrivals (4)" — helps admin prioritise without switching tabs.
- `X-Superseded-By` MIME field value: the **ID** of the new fixlet (integer as string), so the Modifier dashboard or a future query can resolve it.

</specifics>

<deferred>
## Deferred Ideas

- **Auto-deploy of newly copied fixlets** — explicitly out of scope for Phase 6. If needed, this would be a workflow addition to the Dispatcher or a Phase 7 feature.
- **Rollback / revert** — restoring the old fixlet and removing the superseded marker. Noted for a potential future phase.
- **Localization & multi-language support** — the original Phase 6 placeholder content; deferred to a Phase 7 if ever needed.
- **Site priority ordering** — when the same product exists in multiple source sites, a priority list in PORTAL_CONFIG to auto-select the preferred source. Deferred; current decision is to show all and let admin choose.

</deferred>

---

*Phase: 6-update-tracker*
*Context gathered: 2026-07-01*
