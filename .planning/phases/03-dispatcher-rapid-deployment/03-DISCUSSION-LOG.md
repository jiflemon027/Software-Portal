# Phase 3: Dispatcher (Rapid Deployment) — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-14
**Phase:** 3-Dispatcher (Rapid Deployment)
**Areas discussed:** Starting point, FR-04 scope, Fixlet filtering & list, Deployment parameters

---

## Starting Point

### Q1 — Structural base

| Option | Description | Selected |
|--------|-------------|----------|
| Scaffold from modifier.ojo | Strip role/category logic, keep fixlet list + detail panel + action button scaffold | ✓ |
| Scaffold from copier.ojo | Simpler wizard-step flow, more UX deviation | |
| Build fresh | Start from skeleton pattern without copying either file | |

**User's choice:** Scaffold from modifier.ojo
**Notes:** Modifier is the closest structural match — fixlet list, detail panel, action buttons all reuse cleanly.

---

### Q2 — Filename & title

| Option | Description | Selected |
|--------|-------------|----------|
| fixlet_dispatcher.ojo / 'Dereso Fixlet Dispatcher' | Matches copier/modifier naming convention | ✓ |
| fixlet_deployer.ojo / 'Dereso Fixlet Deployer' | Emphasises "deploy" over "dispatch" | |
| You decide | Claude picks clearest name | |

**User's choice:** `fixlet_dispatcher.ojo` / `Dereso Fixlet Dispatcher`

---

### Q3 — PORTAL_CONFIG contents

| Option | Description | Selected |
|--------|-------------|----------|
| Expiration days + target groups | defaultExpirationDays: 7, targetGroups list | ✓ |
| Expiration days only | Keep minimal; target groups fetched live from API | |
| You decide | Claude chooses most useful config structure | |

**User's choice:** Expiration days + target groups
**Notes:** `{ defaultExpirationDays: 7, targetGroups: [...] }` — same inline JSON pattern as modifier's roles/categories.

---

### Q4 — Detail panel content (free-text)

**User's choice:** Name, category, assigned roles, existing action count + deployment form
**Notes:** Sequential top-to-bottom: "what is this fixlet" → "how to deploy it".

---

### Q5 — Action selection when multiple actions exist

| Option | Description | Selected |
|--------|-------------|----------|
| Default action (action ID 1) always | Simple, predictable | |
| Most recently added action | Highest action ID per FR-07 "most recent available" | |
| Admin selects from dropdown | Explicit choice; shows all actions | ✓ |

**User's choice:** Admin selects from dropdown
**Notes:** The action count visible in the detail panel contextualises the dropdown.

---

## FR-04 Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — as pre-deploy step in Dispatcher | Updates description + DefaultActionScript before deploy | |
| Yes — as separate 'Update Fixlet' button | Explicit separate action before deploying | |
| No — defer FR-04 to Phase 4 | Phase 3 handles FR-05/06/07 only | ✓ |

**User's choice:** Defer to Phase 4
**Notes:** Phase 3 scope strictly = deployment. FR-04 was deferred from Phase 2 → Phase 3; now deferred again to Phase 4.

---

## Fixlet Filtering & List

### Q1 — Which fixlets to show

| Option | Description | Selected |
|--------|-------------|----------|
| Only fixlets with roles assigned | Filter to Associated_Roles MIME field present | |
| All fixlets in the portal | Show everything in "Dereso Software Portal" | ✓ |
| You decide | Safest, least confusing list | |

**User's choice:** All fixlets in the portal

---

### Q2 — List columns

| Option | Description | Selected |
|--------|-------------|----------|
| Name, Category, Roles, Site | Full context columns | ✓ |
| Name, Category only | Simpler, mirrors BigFix console defaults | |
| You decide | Best context for confident selection | |

**User's choice:** Name, Category, Roles, Site
**Notes:** Roles column reads `Associated_Roles` MIME field; shows "—" if unset.

---

### Q3 — Search/filter bar

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — same search bar as modifier | Live name-filter, scaffolds for free | ✓ |
| No search — scrollable list only | Simpler, works for small portal sets | |
| You decide | Include if portal size warrants it | |

**User's choice:** Yes — same live name-search bar as modifier.ojo

---

## Deployment Parameters

### Q1 — Target group source

| Option | Description | Selected |
|--------|-------------|----------|
| PORTAL_CONFIG list (already decided) | Consistent with modifier config pattern | |
| Live API fetch from BigFix | GET /computergroups, always current | |
| Both — PORTAL_CONFIG default + free-text fallback | Common targets in config, one-off via text input | ✓ |

**User's choice:** PORTAL_CONFIG dropdown + free-text fallback input

---

### Q2 — Confirmation UX

| Option | Description | Selected |
|--------|-------------|----------|
| Preview panel + single 'Deploy' button | Live-updating offer summary; one button fires POST | ✓ |
| Confirm dialog after 'Deploy' click | Modal safety check before irreversible POST | |
| Both — preview panel + confirm dialog | Belt and suspenders | |

**User's choice:** Preview panel + single "Deploy" button (no confirm dialog)

---

### Q3 — Post-deployment feedback

| Option | Description | Selected |
|--------|-------------|----------|
| Success: deployment ID + 'Deploy another'. Fail: inline error | Stays in dashboard, informative | ✓ |
| Success: alert + clear form. Fail: alert | Simpler, BigFix console style | |
| You decide | Match other dashboards, give actionable error info | |

**User's choice:** Success = deployment ID + "Deploy another" button. Failure = inline error message.

---

### Q4 — Offer field transposition (free-text)

**User's response:** "When deploying as an 'offer' I want to ensure that both the current description and its category are transposed into the Offer description/category."
**Decision:** Offer description ← fixlet `<Description>` (copied as-is). Offer category ← fixlet `<Category>`.

---

### Q5 — Offer field mapping completeness

| Option | Description | Selected |
|--------|-------------|----------|
| That's the complete mapping | Description + category + type + action + target + expiry | |
| Also include fixlet name as offer title | Offer title = fixlet name for recognisability | ✓ |
| You decide | Include fields that make offer identifiable in BigFix console | |

**User's choice:** Also include fixlet name as offer title
**Final offer mapping:** Title = fixlet name, Description = fixlet description, Category = fixlet category, Type = "offer", Action = admin dropdown, Target group = config/free-text, Expiration = config default

---

## Claude's Discretion

- Exact `POST /fixlet-deployments` request body schema (research BigFix REST API docs)
- Whether to add a "Reset" button alongside "Deploy Another" in success state
- Column widths and panel proportions (follow modifier.ojo proportions)
- Whether to include a page-size selector in the fixlet list

## Deferred Ideas

- **FR-04 (Phase 4):** Role-context `<DIV>` in fixlet description + `DefaultActionScript` defaults block. See `.planning/phases/02-modifier/02-CONTEXT.md` §deferred for specific ideas.
