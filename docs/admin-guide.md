# Dereso Fixlet Copier — Admin User Guide

## Prerequisites

Before using the Fixlet Copier dashboard, ensure the following conditions are met:

- **"Dereso Software Portal" custom site must exist** in your BigFix instance. This site is the
  target for all copied fixlets in Phase 1. Create it via BigFix Console → Sites → New Custom
  Site before running the dashboard for the first time.
- **BigFix admin credentials required.** You must be logged into BigFix Console with authoring
  rights for the target custom site. The copier uses the BigFix Console's built-in `API` object,
  which inherits your console session credentials automatically — no separate login is required
  inside the dashboard.
- **Source site accessibility.** The site containing the fixlets you want to copy must be
  visible to your console account. External and operator sites are listed alongside custom sites
  in the Sites filter.

---

## Opening the Dashboard

Navigate to **BigFix Console → Dashboards → Dereso Fixlet Copier**.

On load, the dashboard calls `initDashboard()`, which:
1. Clears the fixlet table.
2. Displays "Ready." in the status bar.
3. Calls `loadSitenames()`, which uses `EvaluateRelevance` to query all BigFix sites
   (external, operator, master, and custom) and populate the **Sites** filter (multi-select)
   and the **Target Site** dropdown (custom sites only).

If either dropdown is empty after load, your account may lack visibility to the relevant sites.
Check site membership settings in BigFix Console.

---

## Step-by-Step Workflow

### Step 1 — Load Fixlets

Click the **Load Fixlets** button. The dashboard queries all fixlets visible in your BigFix
instance using `EvaluateRelevance` and displays them in the grid.

**Filtering before loading:**
- **Sites** — A multi-select list shows all sites. Hold Ctrl and click to select multiple sites.
  Only fixlets belonging to the selected sites will appear in the grid. If nothing is selected,
  all sites are included (equivalent to "All Sites").
- **Search** — Type any text in the Search box to filter the grid by name, fixlet ID, category,
  or severity. Filtering is applied in real time with a short debounce delay.
- **Page size** — Use the page-size selector to control how many rows are displayed per page
  (10, 25, 50, 100, or All).

**Sorting:** Click any column header in the grid to sort by that column. Click again to reverse
direction. Fixlet ID is sorted numerically; all other columns are sorted alphabetically.

---

### Step 2 — Select a Source Fixlet

Click the **radio button** on any row in the grid. The copier:
1. Sets the selected fixlet as the current source.
2. Calls `API.Get` with the path `fixlet/{siteType}/{siteName}/{id}` to retrieve the full
   fixlet XML from the BigFix REST API.
3. Populates the **Title** and **Category** fields from the fetched XML.
4. Extracts action scripts from the XML and lists them in the **Actions** panel.
5. Displays "Loaded source XML from {path}" in the status bar.

> Only one fixlet can be selected at a time. Selecting a new row replaces the previous
> selection and re-fetches all fields.

---

### Step 3 — Review and Edit

After selecting a source fixlet, review the pre-populated fields before cloning:

- **Title** — Defaults to the source fixlet's name. Edit it to give the copy a distinct name
  in the target site. Leaving this blank results in a fixlet with an empty title.
- **Category** — Defaults to the source fixlet's category. Modify as needed.
- **Description** — Check the "Use Description" checkbox to copy the source description into
  the cloned fixlet. If unchecked, the description defaults to `<Cloned from dashboard>`.
- **Relevance** — Check the "Use Relevance" checkbox to carry over the source relevance
  statements. If unchecked, the cloned fixlet defaults to `true` (always relevant).
- **ActionScript** — The selected action's script appears in the ActionScript editor. You can
  edit this text before cloning. Changes apply only to the cloned fixlet — the original is
  not modified.

Hidden metadata fields (Source, SourceID, Domain, etc.) are carried over from the source fixlet
by default via the "Use …" checkboxes. Leave these at their default values unless you have a
specific reason to change them.

---

### Step 4 — Choose a Clone Mode

The **Clone Mode** selector determines how action scripts are handled in the cloned fixlet:

| Mode | Description | When to Use |
|------|-------------|-------------|
| Single Action | Creates one `DefaultAction` from the currently selected script. All other actions from the source are discarded. | When you want a clean, minimal copy with only the action you selected. |
| Full Copy | Preserves all actions from the source fixlet. The currently selected action is promoted to `DefaultAction`; all others are retained as secondary `Action` elements. | When the original fixlet has multiple action variants that are all needed in the copy. |

> If you are unsure which mode to use, **Single Action** is the safer default for most
> installation fixlet copying scenarios.

---

### Step 5 — Choose a Target Site

Select the destination custom site from the **Target Site** dropdown. This dropdown shows
only custom sites (operator and master sites are excluded, as the BigFix API only allows
creating fixlets in custom sites via the `fixlets/custom/{siteName}` endpoint).

For Phase 1 of the Software Portal, select **"Dereso Software Portal"**.

> If the Target Site dropdown is empty, the "Dereso Software Portal" custom site has not been
> created yet. Create it in BigFix Console → Sites before proceeding.

---

### Step 6 — Clone

Click **Clone Selected Fixlet**. The copier:

1. Checks three preconditions (see Troubleshooting for guard messages).
2. Builds the BES/Fixlet XML from all current field values.
3. Calls `API.Post("fixlets/custom/{siteName}", xml, callback)` to create the fixlet.
4. On success: displays the new Fixlet ID in the status bar and shows an alert confirming
   the creation. The grid is automatically refreshed and filtered to the new fixlet ID.
5. On failure: shows an alert with the HTTP status code and error details, and updates the
   status bar with the failure message.

---

## Verifying Success

After a successful clone operation:

- **Status bar** displays: `Created via fixlets/custom/{site} ID={newId}`
- **Alert box** shows: `Created successfully` followed by the new Fixlet ID.
- The fixlet grid is **automatically filtered** to the new fixlet ID so you can confirm it
  appears in the list.

If the new fixlet does not appear immediately, click **Load Fixlets** again — BigFix may
have a brief propagation delay before new fixlets are visible across all consoles.

You can also click **Open Created Fixlet** (if the button is enabled) to jump directly to
the newly created fixlet in the filtered grid.

---

## Testing API Connectivity

Click **Test REST** to verify that the dashboard can reach the BigFix REST API.

- **Expected result:** Alert displays `API OK` and the status bar shows `API OK`.
- **If "FAIL" is shown:** Check the following:
  - Network access from the BigFix console machine to the BigFix REST API port (default: 52311).
  - Your BigFix console credentials are valid and have not expired.
  - The BigFix server is running and the REST API service is enabled.

Run this test first if you experience any connectivity issues before loading fixlets or cloning.

---

## Troubleshooting

### Common Error Messages

| Error | Cause | Remediation |
|-------|-------|-------------|
| "Select a source Fixlet first." | Clone was clicked before a fixlet row was selected | Click the radio button on a fixlet row to select a source fixlet, then click Clone. |
| "Enter a target custom site." | No site was chosen in the Target Site dropdown | Select a custom site from the Target Site dropdown before clicking Clone. |
| "No actions available." | The source fixlet has no ActionScript blocks | Check the source fixlet in its original site — it may lack a DefaultAction or Action element. Select a different source fixlet that has at least one action. |
| HTTP 401 | Invalid or expired BigFix credentials | Re-open BigFix Console and re-authenticate. The API object uses your console session, so re-logging in resets the credential. |
| HTTP 404 | Source fixlet not found at the API path | Verify the fixlet still exists in the selected source site. It may have been deleted or moved. Click Load Fixlets to refresh the list and re-select. |
| HTTP 500 | BigFix server-side error | Check BigFix server logs for details. Wait a few minutes and try again. If the error persists, contact your BigFix administrator. |
| Empty Title in cloned fixlet | Title field was blank at clone time | Always fill in the Title field before clicking Clone. The copier does not validate for an empty title before submitting. |

### Dropdowns Are Empty After Load

If the **Sites** dropdown or **Target Site** dropdown is empty:

- Your console account may not have visibility to any sites. Check site membership settings
  in BigFix Console → Sites.
- The **"Dereso Software Portal"** custom site has not been created. This site must exist
  before it appears in the Target Site dropdown. Create it via BigFix Console → Sites →
  New Custom Site.

### Fixlet Not Appearing After Clone

BigFix may take a few seconds to propagate a newly created fixlet. If the grid is empty
after cloning:
1. Wait a few seconds.
2. Click **Load Fixlets** again to refresh the full list.
3. Clear the search box if it was automatically filtered to the new ID and the fixlet
   hasn't propagated yet.

---

## Reference

- **Dashboard source:** `Existing Dashboards/fixlet_copier.ojo`
- **Architecture details:** `docs/architecture.md`
- **API integration reference:** `docs/api-integration-guide.md`
- **BigFix REST API:** BigFix REST API documentation (port 52311, `https://bigfix.example.com:52311/api`)
