# Dereso Fixlet Dispatcher — Admin User Guide

## Overview

The Fixlet Dispatcher is the third dashboard in the Dereso Software Portal suite (after the Copier
and Modifier). It lets BigFix administrators rapidly deploy role-aware fixlets from the
"Dereso Software Portal" custom site to target computer groups as **offer-type actions**.
When an admin clicks Deploy, the dashboard constructs a `SourcedFixletAction` XML document and
sends it to the BigFix REST API at `POST /api/actions`, auto-populating the offer title, category,
and description directly from the selected fixlet.

---

## Prerequisites

Before using the Dispatcher dashboard, ensure the following conditions are met:

- **BigFix admin credentials required.** You must be logged into BigFix Console with authoring
  rights. The dashboard uses the BigFix Console's built-in `API` object, which inherits your
  console session credentials — no separate login is required inside the dashboard.
- **"Dereso Software Portal" custom site must exist** and contain fixlets. Use the Copier
  dashboard to import fixlets into this site before running the Dispatcher.
- **Fixlets should have categories assigned.** The Dispatcher auto-derives the offer category
  from the fixlet's `<Category>` field (set via the Modifier dashboard). Fixlets without a
  category will produce offers with an empty category field.
- **Target BigFix computer groups must already exist.** The Dispatcher targets computers by
  group membership. Create the required groups in BigFix Console → Computer Groups before
  configuring `PORTAL_CONFIG.targetGroups`.

---

## Configuring the Dashboard

The `PORTAL_CONFIG` block at the top of `fixlet_dispatcher.ojo` is the only section admins
need to edit. Do not modify any code below this block.

```javascript
// ==========================================================================
// PORTAL CONFIGURATION -- Edit this block to add/remove target groups or
// change the default expiry. Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  defaultExpirationDays: 7,
  targetGroups: [
    "All Workstations",
    "IT Department",
    "Finance Department",
    "All Servers"
  ]
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```

| Key | Type | Effect |
|-----|------|--------|
| `defaultExpirationDays` | integer | Default expiration for offer-type actions (in days). Admins can override this per deployment in the form. `7` means the offer expires after 7 days (`P7D` in ISO 8601 duration format). |
| `targetGroups` | array of strings | List of target group names shown in the **Target Group** dropdown. Each string must exactly match a BigFix computer group name (case-sensitive). Add or remove entries to control which groups appear. Admins can always type a custom group name using the "Other" free-text fallback. |

---

## Using the Dispatcher

### Step 1 — Open the Dashboard

Navigate to **BigFix Console → Dashboards → Dereso Fixlet Dispatcher**.

On load, the dashboard calls `initDashboard()`, which populates the Target Group dropdown
from `PORTAL_CONFIG.targetGroups` and then loads all fixlets from the "Dereso Software Portal"
custom site.

### Step 2 — Find a Fixlet

The fixlet list displays four columns: **Fixlet Name, Category, Roles, Site**.

- Use the **Search** box to filter by name in real time (300 ms debounce).
- The **Roles** column shows the value of the `Associated_Roles` MIME field set by the Modifier
  dashboard. If no roles are assigned, the column shows "—".

### Step 3 — Select a Fixlet

Click the **radio button** on any row to select a fixlet. The dashboard:

1. Fetches the full fixlet XML from the BigFix REST API.
2. Populates the **detail panel** on the right: Fixlet Name, Category, Assigned Roles, and
   the number of actions defined on the fixlet.
3. Renders the **Action dropdown** listing all actions (`DefaultAction`, `Action1`, `Action2`,
   etc.) for admin selection.

### Step 4 — Choose an Action

Select which action to deploy from the **Action** dropdown. No action is pre-selected — the
deploy button is blocked until an explicit choice is made.

### Step 5 — Set the Target Group

Select a target group from the **Target Group** dropdown (populated from
`PORTAL_CONFIG.targetGroups`). If the required group is not in the list, select **Other** and
type the group name in the free-text field that appears.

Targeting is implemented via a BigFix relevance expression:
`member of bes computer group whose (name of it = '<group name>')`. If the group name field is
left blank, the relevance expression falls back to `true` (all computers).

### Step 6 — Review the Live Preview

The **Preview** panel updates as you fill in the form. Review:

- **Offer Title** — derived from the fixlet name
- **Offer Category** — derived from the fixlet category
- **Selected Action** — the action chosen in step 4
- **Target Group** — the group selected in step 5
- **Expiration** — number of days until the offer expires (defaults to `PORTAL_CONFIG.defaultExpirationDays`)

Adjust the **Expiration** field to override the default if needed.

### Step 7 — Deploy

Click **Deploy**. The dashboard:

1. Validates all required fields (fixlet selected, target group set, action chosen).
2. Builds the `SourcedFixletAction` XML with `<IsOffer>true</IsOffer>` and sends it to
   `POST /api/actions`.
3. On **success**: displays a green success banner with the returned deployment ID. Click
   **Deploy Another** to reset the form and start a new deployment.
4. On **failure**: displays an inline error message below the Deploy button with the HTTP
   status and response details.

---

## Deployment Parameters

The following table shows how each offer field is populated:

| Deployment Field | Source |
|-----------------|--------|
| Offer Title | Fixlet name |
| Offer Description | Fixlet `<Description>` content (copied as-is) |
| Offer Category | Fixlet `<Category>` value (auto-derived, FR-06) |
| Offer Type | Always `"offer"` (hardcoded via `<IsOffer>true</IsOffer>`) |
| Selected Action | Admin selection from Action dropdown |
| Target Group | Admin selection (PORTAL_CONFIG list or free-text) |
| Expiration | `PORTAL_CONFIG.defaultExpirationDays` (overrideable per deployment) |

---

## Troubleshooting

| Symptom | Cause | Remediation |
|---------|-------|-------------|
| No fixlets shown after clicking Load Fixlets | "Dereso Software Portal" site does not exist or contains no fixlets | Ensure the "Dereso Software Portal" custom site exists in BigFix. Use the Copier dashboard to import fixlets into it. |
| Deploy failed: 404 | BigFix REST API `/api/actions` endpoint is not accessible or the fixlet no longer exists | Confirm the BigFix REST API is accessible from the console machine (port 52311). Verify the selected fixlet still exists. |
| Action created but 0 relevant computers | Target group name in PORTAL_CONFIG does not exactly match the group name in BigFix | Group name matching is case-sensitive. Open BigFix Console → Computer Groups to verify the exact group name, then update `PORTAL_CONFIG.targetGroups` to match. |
| Offer not appearing in BigFix Self-Service App | `IsOffer` may not have been set, or BigFix client version does not support offers | Confirm the deployment was created with `IsOffer>true` by checking the action in BigFix Console → Actions. If offers still do not appear, verify the BigFix client version on endpoints meets the minimum requirement for self-service offers. |
| "Select a fixlet first" error on Deploy | Deploy was clicked without selecting a fixlet row | Click the radio button on a fixlet row to select it, then click Deploy. |
| "Select a target group" error on Deploy | Target Group field is empty | Choose a group from the dropdown or type a group name in the "Other" free-text field. |
| "Select an action" error on Deploy | No action was chosen from the Action dropdown | Select an action from the Action dropdown in the detail panel before clicking Deploy. |

---

## Related Dashboards

- **Dereso Fixlet Copier** (`fixlet_copier.ojo`) — Imports fixlets from external or internal BigFix sites into the "Dereso Software Portal" custom site. Start here when adding new software to the portal.
- **Dereso Fixlet Modifier** (`fixlet_modifier.ojo`) — Assigns user roles and software categories to fixlets in the portal; updates fixlet relevance rules to enforce role-based access. Run the Modifier after copying fixlets and before dispatching them.
- **Dereso Fixlet Dispatcher** (`fixlet_dispatcher.ojo`) — This dashboard. Deploys role-categorized fixlets as offer-type actions to target computer groups.

---

## Reference

- **Dashboard source:** `Existing Dashboards/fixlet_dispatcher.ojo`
- **Architecture details:** `docs/architecture.md`
- **API integration reference:** `docs/api-integration-guide.md`
- **BigFix REST API:** BigFix REST API documentation (port 52311, `https://bigfix.example.com:52311/api`)
