---
phase: 06-update-tracker
plan: 02
subsystem: Existing Dashboards
tags: [bigfix, dashboard, ojo, ie9, fixlet-update, copy-engine, category-map]

dependency_graph:
  requires:
    - "06-01: CATEGORY_MAP generation script and output"
  provides:
    - "Existing Dashboards/fixlet_update_tracker.ojo — complete Fixlet Update Tracker dashboard"
  affects:
    - "BigFix Console admin workflow for portal fixlet updates"

tech_stack:
  added: []
  patterns:
    - "IE9 BigFix dashboard (OJO XML + CDATA + language=javascript)"
    - "MSXML ActiveX DOM with XPath SelectionLanguage property"
    - "4-step recursive sequential callback (GET portal, GET source, POST copy, PUT supersede)"
    - "EvaluateRelevance for client-side fixlet scanning with setTimeout repaint yield"
    - "Embedded CATEGORY_MAP constant (build-time generated, 786 entries)"
    - "Two-tab div show/hide UI (Updates + New Arrivals)"
    - "Checkbox multi-select batch copy flow with editable preview panel"

key_files:
  created:
    - path: "Existing Dashboards/fixlet_update_tracker.ojo"
      description: "Complete Fixlet Update Tracker BigFix dashboard (1771 lines)"
  modified: []

decisions:
  - "D-01 implemented: manual scan trigger via Scan for Updates button (no auto-scan)"
  - "D-02 implemented: live status via setStatus + setTimeout(scanNextSite, 0) yield between site iterations"
  - "D-03 implemented: portalItems, scanSourceResults, updateRows, arrivalRows reset on each startScan call"
  - "D-04 implemented: stripVersion uses / v\\ d[\\ d.]+/g regex (ONE-or-more after first digit preserves v2 family tokens)"
  - "D-05 implemented: PORTAL_CONFIG.sourceSites array with BigFix Software Installer Library for Windows"
  - "D-06 implemented: buildScanResults shows all newer versions per product"
  - "D-07 implemented: buildScanResults shows all source-site matches (no deduplication)"
  - "D-08 implemented: buildSupersededXml strips then adds X-Superseded-By MIME field; API.Put updates old portal fixlet"
  - "D-09 implemented: New Arrivals tab with suggestedCategory from CATEGORY_MAP; roles left blank"
  - "D-10 implemented: scan results populate tables directly (no intermediate approval step)"
  - "D-11 implemented: two-step flow — checkboxes, Copy Selected, preview panel, Confirm"
  - "D-12 implemented: copyNextItem always recurses in error branches (partial failure model)"
  - "D-13 implemented: showPreviewPanel renders editable Category dropdown and Roles text field"
  - "D-14 implemented: updates table with checkbox, portalName, sourceName, siteName, category, roles columns"
  - "D-15 implemented: two tabs with updateTabBadges displaying counts after scan"
  - "D-16 implemented: lookupCategory prefers portal Category element; falls back to CATEGORY_MAP"
  - "D-17 implemented: Associated_Roles MIME field transferred from old portal fixlet via buildCopyXml"
  - "D-18 implemented: CATEGORY_MAP embedded constant (786 entries) immediately after PORTAL_CONFIG"
  - "Plan design rationale for D-14: updates table uses 6 columns (checkbox + 5 data); Action role fulfilled at panel level by Copy Selected button rather than per-row"

metrics:
  duration: "~45 minutes"
  completed: "2026-07-08"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
  lines_written: 1771
---

# Phase 6 Plan 02: Fixlet Update Tracker Dashboard Summary

**One-liner:** Complete BigFix dashboard (OJO) implementing all 18 locked decisions — scan engine with per-site progress, two-tab comparison UI with checkbox batch copy, 4-step sequential API callback (GET portal + GET source + POST copy + PUT supersede), X-Superseded-By MIME field stamp, New Arrivals tab, embedded 786-entry CATEGORY_MAP, and editable preview panel.

## What Was Built

`Existing Dashboards/fixlet_update_tracker.ojo` — a complete, importable BigFix dashboard delivering the Fixlet Update Tracker feature. The file is 1771 lines and contains:

**Task 1 (scaffold, scan engine, tab UI):**
- OJO XML wrapper with Head and HTML CDATA sections, IE9 meta tag
- Shared CSS copied from existing dashboards plus tab-specific classes (`.tabBtn`, `.tabActive`, `.tabPanel`)
- `PORTAL_CONFIG` with `sourceSites` array (D-05) and updated 13-item categories list matching CATEGORY_MAP values
- Embedded `CATEGORY_MAP` constant (786 key-value pairs, auto-generated from `software_categorized.csv`)
- Pure logic functions copied verbatim from the Wave 1 test file: `stripVersion`, `extractVersion`, `compareVersions`, `lookupCategory`, `buildScanResults`
- Utility functions: `htmlEscape`, `xmlEscape`, CDATA helpers, `setStatus`, `parseCreatedId`, `makeSortHeader`
- Scan engine: `startScan`, `scanNextSite` (with `setTimeout(scanNextSite, 0)` yield for D-02 progress), `processScanResults`, `loadPortalFixlets`
- Table rendering: `renderUpdatesTable`, `renderUpdateRow`, `renderArrivalsTable`
- Checkbox helpers: `toggleSelectAll`, `getSelectedUpdateRows`
- Tab UI: `switchTab`, `updateTabBadges`
- Sort helpers: `applySortToUpdateRows`, `sortBy`
- HTML body: scan panel, tab bar, Updates tab, New Arrivals tab, preview panel, results panel

**Task 2 (copy engine):**
- `buildCopyXml`: strips `Associated_Roles` via regex, sets `<Category>`, adds new `Associated_Roles` MIME field before `<Domain>` (D-16, D-17)
- `buildSupersededXml`: strips `X-Superseded-By` via regex, adds new `X-Superseded-By` MIME field (D-08)
- `copyNextItem`: 4-step sequential callback — GET portal fixlet, GET source fixlet, POST copy (plural `fixlets/custom/` path), PUT supersede on old fixlet; always recurses in error branches (D-12)
- `copyArrival`: simplified 2-step flow for New Arrivals (GET source + POST only; no PUT)
- `onCopyArrival`: per-row Copy button handler for arrivals table
- `showPreviewPanel`: builds editable Category dropdown + Roles text field per selected item (D-13)
- `onCopySelected` / `onConfirmCopy`: two-step batch copy flow (D-11)
- `onAllCopiesDone` / `renderResultsPanel`: per-item success/fail display

## Decisions Made

All 18 locked decisions D-01 through D-18 implemented. See frontmatter `decisions` section for full detail.

**Notable design choices:**
- Updates table uses 6 columns (not 7) — Action role fulfilled at panel level by "Copy Selected" button rather than per-row, consistent with the D-11 two-step flow (documented in plan objective)
- `_rowData` property stored directly on `<tr>` DOM elements (Assumption A5) for `getSelectedUpdateRows()`; if IE9 doesn't support this, a parallel `rowData[]` array indexed by row number is the documented fallback
- `previewPanel._selectedRows` used to pass selection state from `showPreviewPanel` to `onConfirmCopy`; IE9 allows arbitrary properties on DOM elements
- Sort state shared via module-level `sortColumn`/`sortAsc` variables (Updates table only); arrivals table has no sort to keep code simple

## Security Controls Applied

All threat mitigations from the plan's STRIDE register were implemented:

| Threat | Mitigation | Verification |
|--------|-----------|-------------|
| T-06-02-XSS | `htmlEscape()` applied to all values before `.innerHTML` in `renderUpdateRow`, `renderArrivalsTable`, `renderResultsPanel`, `showPreviewPanel` | Verified in acceptance criteria |
| T-06-02-XML | `xmlEscape()` available; MSXML `.text` DOM assignment provides native entity escaping for MIME field values | `xmlEscape` function present |
| T-06-02-MIME | MIME field values assigned via `.text = value` DOM property (auto-escapes) | DOM pattern matches modifier.ojo |
| T-06-02-COPY | Admin must review fixlet content; verbatim copy is by design | Accepted risk |
| T-06-02-SC | No new packages installed | No npm/pip/cargo installs |

## IE9 Constraints Enforced

- `var` everywhere — no `let` or `const`
- Named functions only — no arrow functions (`=>`)
- String concatenation — no template literals (no backticks)
- `for` loops — no `forEach`, no `Array.from`
- `getElementsByTagName`/`getElementById`/`selectSingleNode` — no `querySelector`
- `setProperty("SelectionLanguage", "XPath")` before all `selectSingleNode` calls (Pitfall 4)
- `EvaluateRelevance` results wrapped in `String(data[i])` before `.split("|||")`
- POST uses `"fixlets"` plural path; GET/PUT use `"fixlet"` singular (Pitfall 2)
- All API success checks: `s === 200 || s === 201` (Pitfall 6)

## Deviations from Plan

None — plan executed exactly as written.

The `onCopyArrival` function referenced in Task 1's `renderArrivalsTable` onclick handler was designed to be defined in Task 2; this cross-task reference is intentional per the plan structure (JS loads the complete file before any user interaction, so the function is in scope at call time).

## Self-Check

Files created:
- `G:/Gits/Software Portal/.claude/worktrees/agent-a6f1bea84c60479e6/Existing Dashboards/fixlet_update_tracker.ojo` — FOUND (verified by node -e checks)

Commits:
- `4af32f2` feat(06-02): Task 1 scaffold — FOUND (git log confirmed)
- `07717e4` feat(06-02): Task 2 copy engine — FOUND (git log confirmed)

All 26 Task 1 acceptance checks: PASSED
All 27 Task 2 acceptance checks: PASSED
Full post-completion verification (26 checks): PASSED
Stub scan: No stubs detected

## Self-Check: PASSED
