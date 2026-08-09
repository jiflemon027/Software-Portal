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
  using the Dispatcher. The dashboard queries all available groups automatically at load time.

---

## Configuring the Dashboard

The `PORTAL_CONFIG` block at the top of `fixlet_dispatcher.ojo` is the only section admins
need to edit. Do not modify any code below this block.

```javascript
// ==========================================================================
// PORTAL CONFIGURATION -- Edit this block to change the default expiry.
// Do not modify any code below this section.
// ==========================================================================
var PORTAL_CONFIG = {
  defaultExpirationDays: 7
};
// ==========================================================================
// END PORTAL CONFIGURATION
// ==========================================================================
```

| Key | Type | Effect |
|-----|------|--------|
| `defaultExpirationDays` | integer | Default expiration for offer-type actions (in days). Admins can override this per deployment in the form. `7` means the offer expires after 7 days (`P7D` in ISO 8601 duration format). |

> **Note:** The target group list is loaded dynamically from BigFix at dashboard startup — no
> static configuration is required. The dashboard queries all existing BigFix computer groups
> (both site-based automatic groups and manual groups) via `EvaluateRelevance` and displays them
> in a searchable list with group name and site name. Groups are targeted using their numeric ID
> and site name, which ensures correct client-side targeting regardless of group name changes.

---

## Using the Dispatcher

### Step 1 — Open the Dashboard

Navigate to **BigFix Console → Dashboards → Dereso Fixlet Dispatcher**.

On load, the dashboard calls `initDashboard()`, which queries all BigFix computer groups
into the searchable Target Group list, then loads all fixlets from the "Dereso Software Portal"
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

Type in the **Search groups** box to filter the list by group name or site name. The list
shows all BigFix computer groups that exist at the time the dashboard loaded, displayed as
`Group Name  [Site Name]`. Click a row in the list to select it.

Targeting uses client-side BigFix relevance: `member of group <id> of site "<siteName>"`,
evaluated at action runtime on each endpoint. The group's numeric ID and site name are stored
from the `EvaluateRelevance` query, so targeting is not affected by group name changes after
deployment. If no group is selected, the action targets all computers.

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
| Target Group | Admin selection from dynamically-loaded group list |
| Expiration | `PORTAL_CONFIG.defaultExpirationDays` (overrideable per deployment) |

---

## Root Server Prefetch Staging (optional)

The Dispatcher can automatically stage a fixlet's prefetch file(s) on the BES root server
at deploy time, so clients pull the download from the local CustomRepository cache
(`http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/<sha1>/<file>`, per
`rewritePrefetchUrls()`) instead of racing the internet on first take. It also surfaces
whether the file is already cached and whether this fixlet already has an open deployment,
before you click Deploy.

**One-time setup required — none of this works until both steps are done:**

1. **Set `PORTAL_CONFIG.rootServerComputerId`** in `fixlet_dispatcher.ojo` to the BigFix
   Computer ID of the BES root server (find it via `GetRelevance("id of bes computer")` run
   against that computer, or the Computer ID column in the console). Leaving it blank disables
   staging entirely — the checkbox stays greyed out and both status indicators read "not
   configured."
2. **Import `Dashboard_4_samples/Dereso SWD Repository Cache.bes`** and assign it to the BES
   root server computer only. This Analysis reports which SHA1-named folders exist under
   `<wwwRootFolder>\Uploads\CustomRepository\SoftwarePortal` (read from the registry value
   `wwwRootFolder` at `HKLM:\SOFTWARE\Wow6432Node\BigFix\Enterprise Server`). The Dispatcher
   reads its "Cached SHA1 Directories" property to drive the Prefetch Cache indicator.
   **Requires the root server to be enrolled as a managed BES client** — if it isn't, this
   indicator will always read "Unknown."

**What happens on Deploy**, when the "Stage file on root server" checkbox (checked by
default whenever the selected action has a prefetch line) is left checked:

1. A second SingleAction is posted first, targeted at `rootServerComputerId` only. Its
   ActionScript `createfile`s a copy of `Invoke-PrefetchStage.ps1` (embedded verbatim in the
   dashboard as `PREFETCH_STAGE_SCRIPT_LINES` — keep the two in sync if you edit one) into the
   BES Client's `EC` folder, then runs it once per prefetch line found in the **original**
   (un-rewritten) action script — so it downloads from the real internet URL, not the local
   one. The script is idempotent: it skips the download if the file is already staged and its
   SHA1 matches.
2. The main deploy action (with the rewritten local prefetch URL) is posted regardless of
   whether staging succeeded — a failed staging POST does not block the deployment, it just
   gets called out in the result message and in `docs/dispatcher-admin-guide.md`'s
   troubleshooting table below.
3. The 3-retry / 15-minute-wait client retry on the main action (see the section above) gives
   the staging task a window to finish before the client gives up.

**Existing Deployment indicator** — before you deploy, the detail panel shows:
- *Any open action for this fixlet* — reliable (matches on Action Title + `Open` state).
- *Open deployment(s) targeting the selected group* — best effort: matches on Action Title
  **and** the `SmartRole_Source` MIME field's `targetGroup` value (added alongside `id`/
  `sitename` when this feature shipped — actions deployed before then won't be matched). If
  your BigFix version doesn't expose action MIME fields to session relevance, this line reads
  "Unknown" and only the reliable "any open action" line is meaningful.

| Symptom | Cause | Remediation |
|---------|-------|-------------|
| Staging checkbox always greyed out | `rootServerComputerId` blank, or selected action has no prefetch line | Set `PORTAL_CONFIG.rootServerComputerId`. If the action genuinely has no prefetch statement, there's nothing to stage — this is expected. |
| Prefetch Cache always shows "Unknown — Analysis not reporting yet" | `Dereso SWD Repository Cache.bes` not imported/assigned to the root server yet, or it hasn't evaluated since import (up to 5 min) | Import and assign the Analysis to the root server computer; wait for one evaluation cycle. |
| Existing Deployment "targeting group" line always "Unknown" | This BigFix version's session relevance doesn't support `mime field ... of it` on `bes actions` | Rely on the "any open action" line instead; this is a known best-effort fallback, not a bug to chase. |

---

## Troubleshooting

| Symptom | Cause | Remediation |
|---------|-------|-------------|
| No fixlets shown after clicking Load Fixlets | "Dereso Software Portal" site does not exist or contains no fixlets | Ensure the "Dereso Software Portal" custom site exists in BigFix. Use the Copier dashboard to import fixlets into it. |
| Deploy failed: 404 | BigFix REST API `/api/actions` endpoint is not accessible or the fixlet no longer exists | Confirm the BigFix REST API is accessible from the console machine (port 52311). Verify the selected fixlet still exists. |
| Action created but 0 relevant computers | The selected group has no member computers, or the group was deleted after the dashboard loaded | Re-open the dashboard to refresh the group list. Verify the group has members in BigFix Console → Computer Groups. If targeting a site-based group, confirm it is correctly defined (properties, relevance). |
| Offer not appearing in BigFix Self-Service App | `IsOffer` may not have been set, or BigFix client version does not support offers | Confirm the deployment was created with `IsOffer>true` by checking the action in BigFix Console → Actions. If offers still do not appear, verify the BigFix client version on endpoints meets the minimum requirement for self-service offers. |
| "Select a fixlet first" error on Deploy | Deploy was clicked without selecting a fixlet row | Click the radio button on a fixlet row to select it, then click Deploy. |
| "Select a target group" error on Deploy | No group has been clicked in the Target Group list | Click a row in the group list to select it, then click Deploy. |
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
