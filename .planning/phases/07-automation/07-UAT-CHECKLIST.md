---
phase: 07-automation
plan: 12
type: uat-checklist
status: awaiting-operator
manual_only_source: .planning/phases/07-automation/07-VALIDATION.md (Manual-Only Verifications table)
guide: docs/role-manager-admin-guide.md
supersedes: .planning/phases/07-automation/07-05-UAT-CHECKLIST.md (retired 2026-09-21 — Axonius reference-DB pipeline model, never executed against production)
---

# Phase 7 — Production UAT Checklist (07-12)

**Operator-Role-Group model, end to end against the real BigFix environment.** Everything up
to this plan is proven by unit (`tests/unit/role_manager.test.js`, 127/127) and Pester (183
passed / 0 failed excl. Slow) suites against fixtures and mocks — none of it has touched a
production endpoint. `07-01`'s live spike already confirmed the six-element `<ComputerGroup>`
REST body is accepted on `gpbfs` and that no live Axonius-era artefact remains; this checklist
closes the five behaviours `07-VALIDATION.md` classifies as manual-only.

Work through the sections **strictly in order** — each later section genuinely depends on the
one before it:

- **A** — root-server prerequisites (nothing below this works without them)
- **B** — retired-pipeline teardown (confirms the tree is clean before anything new is deployed)
- **C** — task 787's D-18 `Map` migration redeploy (the hard prerequisite: without this,
  *every* `Assign-RoleMapping.ps1` run on a real endpoint fails with "no such column")
- **D** — the Generator and Publish flow, live, against `gpbfs`
- **E** — end-to-end pilot mapping (a real user, a real endpoint, a real `RoleAwareness.db` row)

Each item below is a small table: **Precondition** (what must already be true), **Steps**
(literal commands or exact console navigation — not paraphrase), **Expected** (what a pass
looks like), and blank **Actual** / **Result** fields for the operator to fill in. **Result**
must be `PASS`, `FAIL`, or `N/A` — never left blank.

**Console:** BigFix Console → Dashboards → **Dereso Role Manager** (`fixlet_role_manager.ojo`).
**Root server:** `gpbfs`. **Custom site:** `Dereso Software Portal`
(`PORTAL_CONFIG.siteName`). **Guide:** `docs/role-manager-admin-guide.md`.

---

## Section A — Root-server prerequisites

### UAT-01: `sqlite3.exe` present and pinned on `gpbfs`

| Field | Value |
|---|---|
| Precondition | None — first item. |
| Steps | On `gpbfs`, run `sqlite3.exe -version` from the configured `SQLDir` (the same path `07-SPIKE-RUNBOOK.ps1` Check D already probed: `C:\Program Files (x86)\BigFix Enterprise\BES Client\EC\sqlite\sqlite3.exe -version`). 07-01's spike already recorded this as **PASS** at version `3.53.1` on 2026-09-21/22 — this item re-confirms it is still true now, immediately before Section C's audit-store and D-18 work depend on it. |
| Expected | `sqlite3.exe -version` reports `3.53.1` (or later, pinned build). If absent: stage it via the same `unzip.exe` + Custom Repository mechanism task 787 already uses for endpoints (`sqlite-tools-win-x64-3530100.zip`) as a one-time root-server prerequisite step (07-RESEARCH § Environment Availability, item A5) before continuing to any other section. |
| Actual | |
| Result | |

### UAT-02: Custom site name matches `PORTAL_CONFIG.siteName` exactly

| Field | Value |
|---|---|
| Precondition | None. |
| Steps | In the BigFix Console, confirm the exact, case-sensitive name of the custom site the Copier/Dispatcher/Role Manager dashboards target. Compare against `PORTAL_CONFIG.siteName` in `Existing Dashboards/fixlet_role_manager.ojo` (must read `Dereso Software Portal`). |
| Expected | The live custom site's name is byte-identical to `Dereso Software Portal` — every `fixlets/custom/<site>` and `computergroups/custom/<site>` REST call in Sections D/E depends on this matching exactly (a mismatch produces a 404, not a wrong-but-working result). |
| Actual | |
| Result | |

### UAT-03: `Dereso SWD.bes` Analysis is imported and has reported

| Field | Value |
|---|---|
| Precondition | None. |
| Steps | Confirm `Dashboard_4_samples/Dereso SWD.bes` is imported into the BigFix Console as an Analysis and is activated. Open the Analysis in the console and confirm at least one computer has reported non-empty results for `mapped_users in r.db`, `map_source in r.db`, and `map_region in r.db`. |
| Expected | The Analysis is active and has at least one reporting computer. The Roles-tab D-02 username autocomplete and the entire Analysis tab (Section D-16 reconciliation) both depend on this — without it, the dashboard degrades to "Analysis not reporting yet" and username autocomplete falls back to freeform-only entry. |
| Actual | |
| Result | |

### UAT-04: Console operator has sufficient rights

| Field | Value |
|---|---|
| Precondition | None. |
| Steps | Confirm the console operator account that will run Sections D and E has rights to: create computer groups, create/edit custom-site fixlets (Tasks), and deploy actions. The dashboard elevates nothing on the operator's behalf (V4 — no privilege escalation built into `fixlet_role_manager.ojo`). |
| Expected | The operator can perform all three operation types in the console directly, independent of the dashboard. |
| Actual | |
| Result | |

---

## Section B — Retired-pipeline teardown

### UAT-05: No live Axonius-era pipeline artefacts remain on `gpbfs`

| Field | Value |
|---|---|
| Precondition | Section A complete. |
| Steps | `07-10-SUMMARY.md`'s `LIVE ARTEFACTS TO REMOVE` list reads **"None"** — re-confirming 07-01's Check C (production spike, 2026-09-21). Re-run that same confirmation now, since the source files have since moved to `archive/` (07-10) and every live reference was stripped (07-11): on `gpbfs`, run `schtasks /query /TN DeresoRoleIngest` and `schtasks /query /TN DeresoRolePublish` (both should report "not found"); REST `GET computergroups/custom/Dereso Software Portal` and `GET fixlets/custom/Dereso Software Portal` and confirm no `RoleRef*`-titled objects exist. |
| Expected | Both scheduled tasks report "not found"; zero `RoleRef*` fixlets or computer groups exist. If anything IS found (meaning an untracked manual test run left something behind after all): stop it/delete it now, and record exactly what was removed in the Actual column below — do not proceed to Section C with any leftover Axonius-era object live. |
| Actual | |
| Result | |

---

## Section C — Task 787 D-18 redeploy (the hard prerequisite)

> Without this section, **every** `Assign-RoleMapping.ps1` run in Sections D/E fails with
> "no such column" on any endpoint whose `RoleAwareness.db` predates the D-18 migration.

### UAT-06: Import and deploy task 787 to a **pilot group first**

| Field | Value |
|---|---|
| Precondition | Section B complete (nothing from the retired pipeline is live to conflict). |
| Steps | Import the edited `Dashboard_4_samples/Init  Current User and UserRole DB.bes` into the console (this is task 787, already live from Phase 5/FR-08 — this redeploys it with the 07-02 D-18 fix). Deploy the action to a **pilot group only** — a small, deliberately chosen set of endpoints, NOT the full fleet. |
| Expected | The action deploys successfully to the pilot group; no wider targeting is selected at this stage. |
| Actual | |
| Result | |

### UAT-07: `PRAGMA table_info(Map)` shows all four D-18 columns on a pilot endpoint

| Field | Value |
|---|---|
| Precondition | UAT-06 complete; choose one pilot endpoint that already had a **pre-migration** `RoleAwareness.db` (i.e. it was initialised by task 787 before this redeploy). |
| Steps | On that endpoint, run: `sqlite3.exe "<SWPDir>\RoleAwareness.db" "PRAGMA table_info(Map);"` |
| Expected | The column list includes all four D-18 columns: `Source_Type`, `Source_Value`, `Region`, `Assigned_By` — in addition to the pre-existing columns (`UserID`, `Role`, `Active`, `Valid_to`, etc.). |
| Actual | |
| Result | |

### UAT-08: `Map` row count is unchanged before and after the migration

| Field | Value |
|---|---|
| Precondition | Same pilot endpoint as UAT-07. Ideally capture the "before" count immediately before UAT-06's deploy reaches this endpoint; if that was not captured live, compare against the endpoint's last known `Map` row count from any prior audit. |
| Steps | `sqlite3.exe "<SWPDir>\RoleAwareness.db" "SELECT COUNT(*) FROM Map;"` — run before task 787 redeploys to this endpoint, then again after. |
| Expected | The `Map` row count after the migration equals the count before it. The `ALTER TABLE ... ADD COLUMN` migration is additive-only (`PRAGMA table_info`-gated, per `Dashboard_4_samples/Initialize-RoleDb.ps1`) — it must never drop or duplicate existing rows. |
| Actual | |
| Result | |

### UAT-09: A known row's `Active`/`Locked_by_Override`/`Created_on` are untouched

| Field | Value |
|---|---|
| Precondition | Same pilot endpoint; identify one specific pre-existing `Map` row (by `UserID`/`Role`) before the migration runs. |
| Steps | `sqlite3.exe "<SWPDir>\RoleAwareness.db" "SELECT UserID, Role, Active, Locked_by_Override, Created_on FROM Map WHERE UserID='<known user>' AND Role='<known role>';"` — run before and after the migration. |
| Expected | `Active`, `Locked_by_Override`, and `Created_on` are byte-identical before and after (the D-12 discipline this migration must not disturb). |
| Actual | |
| Result | |

### UAT-10: `RoleDB_Maintenance` now has exactly **one** action, invoking `Initialize-RoleDb.ps1` only

| Field | Value |
|---|---|
| Precondition | Same pilot endpoint, after the migration has run at least once (logon or task run). |
| Steps | `schtasks /query /TN RoleDB_Maintenance /XML` and inspect the `<Actions>` block. |
| Expected | Exactly one `<Exec>` action, invoking `Initialize-RoleDb.ps1` (per 07-02's Pattern-6 fix — the retired `Reconcile-LocalRoles.ps1` second action must be gone). If the task still shows **two** actions, the `Unregister-ScheduledTask` guard did not take — stop and report; this points back at plan 07-02. |
| Actual | |
| Result | |

### UAT-11: No `Reconcile-LocalRoles.ps1` file and no `\roleref` folder exist

| Field | Value |
|---|---|
| Precondition | Same pilot endpoint. |
| Steps | Confirm no `Reconcile-LocalRoles.ps1` file exists under `<SWPDir>`, and no `\roleref` subfolder exists under `<SWPDir>`. |
| Expected | Neither exists — both were retired artefacts of the Axonius pipeline (D-15) that task 787's corrected `.bes` must never (re-)create. |
| Actual | |
| Result | |

### UAT-12: FR-08 logon behaviour survives — `Users.LastSeen` updates

| Field | Value |
|---|---|
| Precondition | Same pilot endpoint. |
| Steps | Log on to the endpoint (or trigger a logoff/logon cycle). Then: `sqlite3.exe "<SWPDir>\RoleAwareness.db" "SELECT UserID, LastSeen FROM Users WHERE UserID='<logged-on user>';"` |
| Expected | `LastSeen` reflects the just-completed logon (current timestamp). FR-08's pre-existing logon-tracking behaviour must survive the D-18 migration unchanged. |
| Actual | |
| Result | |

### UAT-13: Deploy task 787 to the rest of the fleet

| Field | Value |
|---|---|
| Precondition | **UAT-06 through UAT-12 all PASS.** Do not proceed if any Section C item above failed — a task-787 failure means the Pattern 6 diff was wrong and plan 07-02 needs revisiting before anything else in this checklist continues. |
| Steps | Widen task 787's deployment target from the pilot group to the full fleet. |
| Expected | Deployment succeeds fleet-wide with no reported action failures beyond the normal baseline (offline machines, etc.). |
| Actual | |
| Result | |

---

## Section D — Generator and Publish, live

### UAT-14: Dereso Role Manager dashboard loads with no script error

| Field | Value |
|---|---|
| Precondition | Section C complete (fleet-wide task 787 redeploy done). |
| Steps | Open **BigFix Console → Dashboards → Dereso Role Manager**. Confirm both tabs (**Roles**, **Analysis**) render without a script error dialog or a blank panel. |
| Expected | Both tabs render their real content (not the old "built in plan 07-0x" placeholder text) with no IE9 script error. |
| Actual | |
| Result | |

### UAT-15: Stage endpoint script on root server — SHA1 and size match the pin

| Field | Value |
|---|---|
| Precondition | UAT-14 complete. |
| Steps | On the Roles tab's Prerequisites panel, click **Stage endpoint script on root server**. Confirm the action completes. Then on `gpbfs`: `Get-FileHash -Algorithm SHA1 "<wwwRootFolder>\Uploads\CustomRepository\SoftwarePortal\rolegroups\Assign-RoleMapping.ps1"` |
| Expected | The action completes successfully; the file exists at that exact path; its SHA1 is `69860a1239e4509dce483a07523ea07e26764279` and its size is `8877` bytes — this is the one-time (or re-run-on-script-change) prerequisite every role's policy action depends on to succeed end-to-end. |
| Actual | |
| Result | |

### UAT-16: Save a test username — `RolePublishRun`/`RoleUsers` rows appear, console unchanged

| Field | Value |
|---|---|
| Precondition | UAT-15 complete. Pick one **test** username to add to one role — do not use a real production role assignment for this test. |
| Steps | On the Roles tab, add the test username to one role's list and click **Save**. On `gpbfs`, query `RolePublish.db`: `sqlite3.exe RolePublish.db "SELECT * FROM RolePublishRun ORDER BY RunID DESC LIMIT 1;"` and the matching `RoleUsers` rows for that `RunID`. |
| Expected | A new `RolePublishRun` row and matching `RoleUsers` rows appear, reflecting the current full username list for that role (D-05 append-only audit write). Nothing in the console has changed yet — no new Computer Group, no new Task, no new action (Save is D-13 step 1 only; it touches zero BES objects). |
| Actual | |
| Result | |

### UAT-17: Publish — all four step statuses, and the resulting BES objects are correct

| Field | Value |
|---|---|
| Precondition | UAT-16 complete, same role. |
| Steps | Click **Publish**. Record all four step statuses verbatim (`[1/4 Group]`, `[2/4 Task]`, `[3/4 Action]`, `[4/4 Stop]`). In the console, confirm: the Computer Group `DSP Role - <role>` exists with the expected "exactly one of N logged on" relevance text; the Task `Assign Role Mapping - <role>` exists in the custom site with **two** `<Relevance>` clauses; exactly **one** Open action `DSP RoleMap - <role>` exists; its settings show reapply-while-relevant at 1 day, no end time, and `IsOffer` false. |
| Expected | All four steps report success. The Computer Group, Task, and Action all exist with the exact properties above. |
| Actual | |
| Result | |

### UAT-18: Publish the same role a **second** time — still exactly one Open action

| Field | Value |
|---|---|
| Precondition | UAT-17 complete, same role, no username-list changes needed. |
| Steps | Click **Publish** again on the same role (no edits since UAT-17). Confirm the count of Open actions titled `DSP RoleMap - <role>`. |
| Expected | Still exactly **one** Open action afterward — this is the create-new-then-stop-old contract (T-07-12-06): a second Publish must not leave two actions accumulating. |
| Actual | |
| Result | |

### UAT-19: Empty-username-list role — group relevance is exactly `false`, 0 members

| Field | Value |
|---|---|
| Precondition | Use a role you can safely empty for this test (or a dedicated test role), NOT one with real production members you need preserved without first recording them. |
| Steps | Empty that role's username list, **Save**, then **Publish**. In the console, inspect the resulting Computer Group `DSP Role - <role>`'s relevance and its live member count. |
| Expected | The group's relevance is **exactly** the literal string `false`, and its member count is **0** — the T-07-12-01 fleet-wide-match guard, verified for real. **If the group instead matches every computer, stop immediately and report it** — this is the single highest-impact failure mode this checklist tests for (an accidental fleet-wide role match). |
| Actual | |
| Result | |

---

## Section E — End-to-end pilot mapping

### UAT-20: Log the test user into a pilot endpoint — correct `Map` row appears

| Field | Value |
|---|---|
| Precondition | Section D complete; the test user from UAT-16/17 is Published to a real (non-empty) role. |
| Steps | Log the test user into a **non-root** pilot endpoint (not the root server, not a relay). Confirm the endpoint joins the role's Computer Group, the policy action becomes relevant and runs, then: `sqlite3.exe "<SWPDir>\RoleAwareness.db" "SELECT * FROM Map WHERE UserID='<test user>';"` |
| Expected | A `Map` row exists with the correct `UserID`, `Role`, `Assigned_By`, and `Active = 1`. |
| Actual | |
| Result | |

### UAT-21: `Locked_by_Override = 1` is respected across a reapply

| Field | Value |
|---|---|
| Precondition | UAT-20's `Map` row exists on the pilot endpoint. |
| Steps | Manually set `Locked_by_Override = 1` on that row (`sqlite3.exe "<SWPDir>\RoleAwareness.db" "UPDATE Map SET Locked_by_Override=1 WHERE UserID='<test user>' AND Role='<role>';"`). Force the policy action to reapply (re-run it, or wait for the next daily reapply cycle). Re-query the row. |
| Expected | The row is **not** overwritten — `Locked_by_Override = 1` still holds and the row's other values are unchanged from before the forced reapply. The D-12 discipline, verified on a real endpoint. |
| Actual | |
| Result | |

### UAT-22: D-04 — same user, two roles, both `Map` rows exist

| Field | Value |
|---|---|
| Precondition | Test user already mapped to one role (UAT-20). |
| Steps | Add the same test user to a **second** role, Save, Publish. Confirm the endpoint from UAT-20 picks up the second role's Computer Group and policy action too. Query `Map` for that `UserID`. |
| Expected | **Both** `Map` rows exist for the test user (one per role) — `UNIQUE(UserID, Role)` allows multiple roles per user by design. |
| Actual | |
| Result | |

### UAT-23: D-12 accepted gap — two same-role holders sharing a machine map to neither

| Field | Value |
|---|---|
| Precondition | Two distinct test users who both hold the **same** role. |
| Steps | Log both users into **one** shared machine simultaneously. Confirm the machine's membership in that role's Computer Group and whether the policy action runs. |
| Expected | The machine **leaves** (or never joins) the group, and **neither** user gets mapped there. This is expected, accepted behaviour (D-12: "exactly one of N logged on" deliberately fails closed on ambiguity) — **record this as PASS**, not a defect. |
| Actual | |
| Result | |

### UAT-24: Different roles sharing a machine — both map independently

| Field | Value |
|---|---|
| Precondition | One `IT Operations`-role holder and one `Business Operations`-role holder (or equivalent two distinct roles), both real test identities. |
| Steps | Log both users into one shared machine simultaneously. Confirm each role's Computer Group evaluates independently. |
| Expected | **Both** roles map correctly on that machine — each role's own "exactly one of N" check passes against its own username list, independent of the other role's list (unlike UAT-23, which is same-role contention). |
| Actual | |
| Result | |

### UAT-25: Analysis tab reflects the new mapping and catches a typo

| Field | Value |
|---|---|
| Precondition | UAT-20 (or later) has produced at least one real `Map` row. |
| Steps | Open the **Analysis** tab. Confirm the new mapping appears with `Configured? = Yes`. Separately, add a deliberately **mistyped** username to a role's list, Save (do not need to Publish), and confirm it appears in the **"Configured but never mapped"** reconciliation panel. |
| Expected | The real mapping shows `Configured? = Yes` in the main table. The mistyped username appears under **"Configured but never mapped"** — the exact typo-catching purpose D-16 exists for. |
| Actual | |
| Result | |

### UAT-26: `DeresoRoleGroupSync` drift-check corrects a hand-introduced drift

| Field | Value |
|---|---|
| Precondition | Section D complete (at least one role Published, so at least one Computer Group exists to drift-check). Confirm `PipelineConfig.AKeylessSecretPath` resolves (`/gpc/infra/bigfixsecurity/BigFix-RoleSync-Operator`) and `PipelineConfig.BESOperatorUser` is set to the live service-account username (seeded blank per 07-05 — must be set before this item, not left default). |
| Steps | Register `DeresoRoleGroupSync` on the root server: `scripts/Register-AutomationTasks.ps1` (installs `config/task-DeresoRoleGroupSync.xml`, Daily@04:00). Confirm the AKeyless secret resolves for the service account. Hand-edit one Published role's Computer Group relevance directly in the console (introduce a deliberate drift — e.g. change one character in the relevance text). Run the `DeresoRoleGroupSync` task once manually rather than waiting for 04:00. Re-inspect the group's relevance. |
| Expected | The task runs, detects the drift, corrects the group's relevance back to what `RolePublish.db`'s current membership snapshot specifies, and logs the correction as `[DRIFT-FIXED]` (Windows Event 8050 / script log). |
| Actual | |
| Result | |

---

## Sign-off

- [ ] Section A (UAT-01..UAT-04) — every item recorded, PASS or N/A.
- [ ] Section B (UAT-05) — recorded; confirms nothing live from the retired Axonius pipeline
      remains on `gpbfs`.
- [ ] Section C (UAT-06..UAT-13) — every item recorded; UAT-13 (fleet-wide task 787 deploy)
      only proceeds once UAT-06 through UAT-12 all PASS on the pilot endpoint. Any FAIL here
      points back at plan **07-02**.
- [ ] Section D (UAT-14..UAT-19) — every item recorded. UAT-19's empty-list guard is the
      single highest-risk item in this checklist (T-07-12-01) — do not sign off with it
      unresolved. A relevance-shape FAIL points at **07-04**; a Publish-sequencing FAIL points
      at **07-08**; an audit-store FAIL points at **07-03**.
- [ ] Section E (UAT-20..UAT-26) — every item recorded. A drift-job FAIL points at **07-05**.
- [ ] No item in Sections C, D, or E is left as FAIL without a follow-up recorded (either here,
      inline, or escalated into `07-12-SUMMARY.md` naming the plan that must be revisited).

**Operator:** _____________________  **Date:** _____________________

Reply **"approved"** to the execution checkpoint (with each section's results) once every box
above is ticked, or describe the specific failure and which UAT item it occurred on.
