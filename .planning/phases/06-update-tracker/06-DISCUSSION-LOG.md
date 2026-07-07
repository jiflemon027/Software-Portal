# Phase 6: Fixlet Update Tracker — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 06-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-01
**Phase:** 06-update-tracker
**Areas discussed:** Pre-discussion Q&A, Scan trigger & freshness, Multi-version handling, Match review & confirmation, Dashboard layout

---

## Pre-Discussion Q&A (before formal discuss-phase)

| Question | Options | Selected |
|----------|---------|----------|
| Which source sites to scan? | Configurable list / All external sites / Same sites as Copier | Configurable list in PORTAL_CONFIG |
| What happens to old version? | Keep + mark superseded / Delete automatically / Keep unchanged | Keep old, mark as superseded (X-Superseded-By MIME field) |
| Version matching approach? | Strip version from name / Use MIME field X-Product-Name | Strip version from name (regex) |
| Net-new products? | Separate 'New Arrivals' section / Suggest category from CSV / Ignore | Suggest category from CSV (shortlist), no roles |

---

## Scan Trigger & Freshness

| Option | Description | Selected |
|--------|-------------|----------|
| Manual button only | Admin clicks 'Scan for Updates' — no auto-scan | ✓ |
| Auto-scan on load | Scan runs when dashboard opens | |
| Both — auto + manual refresh | Auto on load plus manual refresh button | |

**User's choice:** Manual button only

---

| Option | Description | Selected |
|--------|-------------|----------|
| Status message with counts | "Scanning site X of Y… N fixlets checked" | ✓ |
| Simple spinner | Loading spinner until all results ready | |
| You decide | Let Claude choose | |

**User's choice:** Status message with counts during scan

---

| Option | Description | Selected |
|--------|-------------|----------|
| No — results clear on close | Each visit starts fresh | ✓ |
| Yes — cache in sessionStorage | Persist results within BigFix Console session | |

**User's choice:** Results clear on close (no caching)

---

## Multi-version Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Latest only | Only show the single newest version per product | |
| All newer versions | Show every version newer than the portal copy | ✓ |

**User's choice:** All newer versions

---

| Option | Description | Selected |
|--------|-------------|----------|
| Show all, grouped by product | Show all matches with source site visible | ✓ |
| Deduplicate, prefer specific sites | Priority list in PORTAL_CONFIG | |

**User's choice:** Show all, grouped by product, with source site column visible
**Notes:** User clarified: "show all, grouped by product, and show the source site"

---

## Match Review & Confirmation

| Option | Description | Selected |
|--------|-------------|----------|
| Direct — show in Updates table | Matches appear immediately without pre-approval | ✓ |
| Review step — confirm each match | Admin approves/rejects each matched pair first | |

**User's choice:** Direct — matches shown in Updates table without a review step

---

| Option | Description | Selected |
|--------|-------------|----------|
| Single-click, all-in-one | One button copies, transfers, marks superseded | |
| Two-step: preview then confirm | Preview panel shows planned changes; admin confirms | ✓ |

**User's choice:** Two-step: preview panel + confirm

---

| Option | Description | Selected |
|--------|-------------|----------|
| One at a time only | Select one fixlet, preview, confirm | |
| Batch — select many, then confirm all | Checkboxes + "Copy Selected" + summary panel | ✓ |

**User's choice:** Batch — select multiple, review summary, confirm all

---

## Dashboard Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Comparison table | Columns: checkbox, Current, Available Update, Source Site, Category, Roles, Action | ✓ |
| Existing pattern (list + side panel) | Same as Copier/Modifier — list left, detail right | |

**User's choice:** Comparison table layout

---

| Option | Description | Selected |
|--------|-------------|----------|
| Two tabs: Updates and New Arrivals | Tab bar switches between the two tables | ✓ |
| Two sections on one page | Both tables on single scrollable page | |
| Updates only — skip New Arrivals | Only show existing portal fixlets with updates | |

**User's choice:** Two tabs — "Updates" and "New Arrivals"

---

| Option | Description | Selected |
|--------|-------------|----------|
| Summary table + editable fields | Editable category (dropdown) and roles in preview | ✓ |
| Summary table, read-only | Read-only preview; edits via Modifier dashboard post-copy | |

**User's choice:** Summary table with editable category dropdown (pre-filled) and editable roles (pre-filled)

---

## Claude's Discretion

- Version regex exact form — `/\s+v\d[\d.]*(?:\.\d+)*/i` (handles `v26.01`, `v11.0.31.11`, `v25.0.3.9`)
- Tab count badge format after scan — "Updates (12)  New Arrivals (4)"
- `X-Superseded-By` field value — store new fixlet ID (integer as string)
- IE9-safe JavaScript patterns (no `let`/`const`, no arrow functions, no template literals, MSXML DOM API)

## Deferred Ideas

- Auto-deploy of newly copied fixlets — out of scope; admin uses existing Dispatcher
- Rollback / revert of superseded fixlets — future phase
- Localization & multi-language support — original Phase 6 placeholder; future Phase 7
- Site priority ordering for deduplication — deferred; current approach is to show all matches
