---
phase: 03-dispatcher-rapid-deployment
plan: "02"
subsystem: dashboard
tags: [dispatcher, bigfix, offer-deployment, api-post, sourcefixletaction, ie9]
dependency_graph:
  requires:
    - tests/unit/dispatcher.test.js (plan 03-01)
    - tests/fixtures/phase-03/ (plan 03-01)
    - Existing Dashboards/fixlet_modifier.ojo (scaffold source)
  provides:
    - Existing Dashboards/fixlet_dispatcher.ojo
  affects:
    - tests/unit/dispatcher.test.js (functions implemented here match test contracts)
tech_stack:
  added: []
  patterns:
    - BigFix Wizard XML (BES > Wizard > Page, IE=9 meta, Head CDATA block)
    - API.Post("actions", xml, cb) — first use of POST in the project (prior phases used GET/PUT)
    - SourcedFixletAction XML with IsOffer=true — offer-type deployment via REST API
    - buildTargetRelevance() — group targeting via Relevance element (not Target element)
    - PORTAL_CONFIG pattern (targetGroups + defaultExpirationDays) — admins edit only this block
    - htmlEscape() on all innerHTML writes; xmlEscape() on all XML string values
    - CDATA wrapping via cdataStart()/xmlCDataSafe()/cdataEnd() for OfferDescriptionHTML
    - parseActionId() three-path regex fallback (ActiveXObject → URL regex → ID= regex → <ID> regex)
key_files:
  created:
    - Existing Dashboards/fixlet_dispatcher.ojo
  modified: []
decisions:
  - "Implemented Tasks 1 and 2 atomically in a single file write — both the scaffold and deploy logic were written together for correctness (avoids a half-functional intermediate state)"
  - "No <Target> element in SourcedFixletAction XML per RESEARCH.md A1 and Pitfall 1 — group targeting uses <Relevance> element only"
  - "alert() appears only in the init error handler (BigFix console convention) and in comments — deploy/feedback paths use inline DOM elements exclusively per D-11"
  - "renderActionDropdown() explicitly sets selectedActionId='' after rendering — no auto-selection per D-08; deploy guard (!selectedActionId) prevents deployment without explicit admin choice"
  - "<Target> mention in comments is documentation of intentional omission — not an actual XML element in the template"
metrics:
  duration: "12 minutes"
  completed: "2026-06-15"
  tasks_completed: 2
  files_created: 1
  files_modified: 0
---

# Phase 03 Plan 02: Fixlet Dispatcher Dashboard Summary

**One-liner:** BigFix Wizard XML dispatcher dashboard with SourcedFixletAction offer deployment, PORTAL_CONFIG targetGroups, portal-scoped fixlet list, detail panel, action dropdown, live preview, and API.Post("actions") with inline success/error feedback.

## What Was Built

### Task 1: Scaffold, PORTAL_CONFIG, and Fixlet List

`Existing Dashboards/fixlet_dispatcher.ojo` created as a new file (fixlet_modifier.ojo untouched).

**Outer XML structure:** BigFix Wizard XML wrapper with `<Title>Dereso Fixlet Dispatcher</Title>` (both occurrences), IE=9 meta, single `<Page Name="main">` with `<Head>` CDATA block.

**CSS:** All classes from modifier.ojo copied verbatim (`body`, `.page`, `h1`, `.panel`, `.panelBody`, `.rowTable`, `.rowTable td`, `.lbl`, `input[type=text]`, `textarea`, `.txt`, `.txtWide`, `.btn`, `.btnGreen`, `.tableGrid`, `.tableGrid td/th`, `.small`, `.right`, `.divider`). `.roleTable` omitted (not needed in dispatcher).

**PORTAL_CONFIG block (D-03):**
```javascript
var PORTAL_CONFIG = {
  defaultExpirationDays: 7,
  targetGroups: ["All Workstations", "IT Department", "Finance Department", "All Servers"]
};
```
Same delimiter comment format as modifier.ojo.

**Module-level state:** Added `parsedActions = []` and `selectedActionId = ""`. Omitted `roleValues = []`.

**Fixlet list functions:**
- `loadAllFixlets()` — EvaluateRelevance scoped to `"Dereso Software Portal"` site only (D-04), five pipe-separated fields: id, name, siteName, category, roleValue
- `addHeader()` — 5 columns: Select, Fixlet Name, Category, Roles, Site (no ID column per D-05)
- `renderPage()` — htmlEscape applied to all four text fields; Roles shows "—" if empty
- `filterAndRender()` — debounced 300ms search across [name, category, roleValue, siteName]; no siteFilter (D-04)
- `initDashboard()` — calls `renderTargetGroupDropdown()` then `loadAllFixlets()` directly (no loadSitenames/loadRoleValues/loadCategoryOptions)

### Task 2: Detail Panel, Deployment Form, and API.Post Logic

All deploy-related JS functions added to the same file:

**buildTargetRelevance(groupName)** — Trim check returning `"true"` for blank; single-quote escape via `.replace(/'/g, "\\'")` before embedding in `member of bes computer group whose (name of it = '...')` relevance string (T-03-02-02, Pitfall 7).

**buildExpirationElement(days)** — Returns `<HasEndTime>true</HasEndTime><EndDateTimeLocalOffset>P{N}D</EndDateTimeLocalOffset>` (RESEARCH.md Pattern 6A).

**parseActionId(body)** — try/catch ActiveXObject block (silently fails in Node.js) followed by three regex fallback paths: `/\/api\/action\/(\d+)/i`, `/\bID=["']?(\d+)["']?/i`, `/<ID>(\d+)<\/ID>/i`.

**parseActions(xmlText)** — Parses DefaultAction and Action elements from fixlet XML, populates `parsedActions[]`, calls `renderActionDropdown()`.

**renderActionDropdown()** — Renders options with blank prompt first; sets `selectedActionId = ""` — no auto-selection per D-08.

**selectFixlet(i)** — `API.Get("fixlet/custom/...")` on radio selection; on success calls `parseDetailPanel(b)`; on error calls `setStatus()` (no alert).

**parseDetailPanel(xmlText)** — ActiveXObject parse; extracts Title, Category, Associated_Roles MIME field, action count; populates `detailName/Category/Roles/ActionCount` DOM spans; calls `parseActions()` + `updatePreview()`.

**buildDeployXml()** — Full SourcedFixletAction XML:
- Guard: returns `""` if `!sourceXml || !currentItem || !selectedActionId`
- `IsOffer>true</IsOffer>` in `<Settings>` block (Pitfall 3)
- `OfferDescriptionHTML` wrapped in `cdataStart() + xmlCDataSafe(desc) + cdataEnd()` (Pitfall 2, T-03-02-01)
- `<Relevance>` element with `xmlEscape(buildTargetRelevance(groupName))` (T-03-02-02/05)
- No `<Target>` element — Relevance-only group targeting per RESEARCH.md A1 (Pitfall 1)
- `EndDateTimeLocalOffset>P{N}D</EndDateTimeLocalOffset>` for expiry

**deployFixlet()** — Three input guards (no fixlet, no target group, no action selected) with `setStatus()` feedback; builds XML; calls `API.Post("actions", xml, cb)`; on 200/201 shows success banner with `parseActionId()` result and "Deploy Another" button; on error shows inline error div (no alert per D-11, T-03-02-04).

**HTML additions:**
- `<div id="detailPanel" style="display:none">` — shows after fixlet selection; contains name/category/roles/action-count spans and `<select id="actionSelect">`
- `<select id="targetGroupSelect">` populated by `renderTargetGroupDropdown()` from PORTAL_CONFIG
- `<input type="text" id="targetGroupFreetext">` — shown when "Other" selected (no `type="date"` per Pitfall 4)
- `<input type="text" id="expiryDaysInput" value="7">` — text input, not date (Pitfall 4)
- Live preview panel with `previewTitle/Category/Action/Target/Expiry` spans
- `<div id="deployError">` for inline error; `<div id="deployResult">` for success banner

## Verification Result

```
node -e "...all checks..." → All true (8/8 checks pass)
node tests/unit/dispatcher.test.js → 23 passed, 0 failed
```

All success criteria met:
- fixlet_dispatcher.ojo: 817 lines, valid BigFix Wizard XML
- "Dereso Fixlet Dispatcher" title appears twice
- PORTAL_CONFIG with defaultExpirationDays:7 and 4 targetGroups
- EvaluateRelevance scoped to "Dereso Software Portal"
- API.Post("actions", ...) for deployment
- IsOffer>true in Settings; CDATA-wrapped OfferDescriptionHTML; EndDateTimeLocalOffset P7D
- No <Target> element; Relevance-only group targeting
- No alert() in deploy/feedback paths; inline deployError/deployResult divs

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1 + 2 (atomic) | 3d9123c | Existing Dashboards/fixlet_dispatcher.ojo |

## Deviations from Plan

### Tasks 1 and 2 implemented atomically

- **Found during:** Task 1 execution
- **Issue:** The plan separates Task 1 (scaffold) and Task 2 (deploy logic) into sequential commits, but because both tasks modify the same file and Task 2 requires the helper functions from Task 1 to be verifiable together, implementing both in a single Write produced a cleaner, fully-functional file without an intermediate half-functional state.
- **Fix:** Both tasks implemented in one Write operation. Single commit covers both task scopes.
- **Classification:** [Rule 3 — Blocking] Intermediate file state (scaffold without deploy logic) does not satisfy Task 2's TDD behavior requirements, so atomic implementation is correct.

No other deviations. All acceptance criteria for both tasks satisfied.

## Known Stubs

None. All form elements are wired:
- targetGroupSelect populated from PORTAL_CONFIG.targetGroups
- actionSelect populated from parseActions() on fixlet selection
- previewTitle/Category/Action/Target/Expiry updated by updatePreview()
- deployResult/deployError populated by deployFixlet() callback
- All data flows from BigFix API responses — no hardcoded empty values flow to UI

## Threat Surface Scan

All mitigations from the plan's `<threat_model>` are implemented:

| Threat ID | Status | Implementation |
|-----------|--------|----------------|
| T-03-02-01 | Mitigated | cdataStart()/xmlCDataSafe()/cdataEnd() wraps OfferDescriptionHTML |
| T-03-02-02 | Mitigated | single-quote escape in buildTargetRelevance(); xmlEscape() on Relevance element |
| T-03-02-03 | Mitigated | htmlEscape() on all innerHTML in renderPage() and detail panel |
| T-03-02-04 | Mitigated | deployFixlet() validates getSelectedTargetGroup() non-empty before buildDeployXml() |
| T-03-02-05 | Mitigated | xmlEscape() on siteName, fixletId, actionId, category, title in buildDeployXml() |
| T-03-02-06 | Accepted | Credentials managed by BigFix console session; dispatcher does not store or log them |

No new threat surface beyond what the plan's threat model covers.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| Existing Dashboards/fixlet_dispatcher.ojo exists | FOUND |
| File size 29046 chars (>200 lines) | PASSED |
| "Dereso Fixlet Dispatcher" title present | PASSED |
| PORTAL_CONFIG with defaultExpirationDays:7 | PASSED |
| API.Post("actions") present | PASSED |
| IsOffer>true present | PASSED |
| SourcedFixletAction present | PASSED |
| buildTargetRelevance present | PASSED |
| EndDateTimeLocalOffset present | PASSED |
| No siteFilter | PASSED |
| Commit 3d9123c exists | FOUND |
| node tests/unit/dispatcher.test.js exits 0 | PASSED (23/0) |
