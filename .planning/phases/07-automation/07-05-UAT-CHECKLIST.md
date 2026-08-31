---
phase: 07-automation
plan: 05
type: uat-checklist
status: awaiting-operator
manual_only_source: .planning/phases/07-automation/07-VALIDATION.md (Manual-Only Verifications table)
guide: docs/automation-admin-guide.md
---

# Phase 7 — Production-Fleet UAT Checklist (07-05 Task 4)

Everything that can be tested against fixtures and mocks is already green. This checklist
is the **five behaviours that cannot be faked** without the production fleet — the
MCP-connected BigFix server is a nine-computer lab, not `gpbfs` (~40k). Work through the
sections **in order**. Each section has the same shape:

- **Steps** — exactly what to do (references a `docs/automation-admin-guide.md` step).
- **Pass** — the observation that counts as a pass.
- **Fail** — the observation that counts as a fail.
- **Recorded outcome** — fill this in verbatim: the endpoints, the users, the values seen.
- **Mitigation** — what to do on a fail.

**Do NOT enable a second region, and do NOT turn on content auto-approve, until every
section below has a recorded outcome and the Pilot section is signed off.** An **A1** or
**A2** fail means applying the mitigation and returning to this checklist for a re-test —
not proceeding.

---

## Section A1 — `name of current user` is the interactive console user

**Assumption:** RESEARCH A1 / Pitfall 2. The whole reconcile assigns roles keyed on the
console user's bare lower-cased `sAMAccountName`. If `name of current user` (client
relevance) returns SYSTEM, blank, or a machine account on the real fleet, the pipeline
silently assigns nothing (or assigns to the wrong account). **This is the single
highest-risk item in the phase and a STOP gate before any region goes live.**

**Steps** (guide Step 6 precedes this; this is the check before guide Step 7 "Pilot"):

1. Pick **at least three** pilot endpoints that each have a **known** interactive user
   logged in (record the machine name and the expected bare lower-cased `sAMAccountName`
   for each).
2. Add a **temporary** BigFix Analysis property to those three computers returning
   `name of current user` alongside the existing `names of logged on users`
   (`fixlet_modifier.ojo` already uses the plural form — compare against it).
3. Let the property report, then read all three values.
4. Compare `name of current user` (lower-cased) against the known bare lower-cased
   `sAMAccountName` for each endpoint.

**Pass:** `name of current user` equals the bare lower-cased `sAMAccountName` on **all
three** endpoints.

**Fail:** on any endpoint it returns `SYSTEM`, blank, a machine account
(`MACHINE$`), or a value that differs from the known SAM.

**Recorded outcome:**

| Endpoint | Known SAM (lower-cased) | `name of current user` observed | `names of logged on users` observed | Match? |
|----------|------------------------|--------------------------------|-------------------------------------|--------|
| _(fill in)_ | | | | |
| _(fill in)_ | | | | |
| _(fill in)_ | | | | |

Overall A1 result: _(pass / fail — if the mitigation was applied, state that it was
re-tested and passed)_

**Mitigation (on fail):** Set **`PipelineConfig.ConsoleUserRelevance`** — the single
one-line seam — to `names of logged on users` (or an item-zero form of that plural list,
e.g. `item 0 of (names of logged on users)`). Re-run
`scripts/Publish-RoleSnapshot.ps1` so the per-region **policy Fixlet ActionScript**
picks up the new substitution. Re-run this section. Do not proceed until A1 passes.

---

## Section A2 — the `127.0.0.1:52311` Custom Repository prefetch reaches a non-root endpoint

**Assumption:** RESEARCH A2 / Pitfall 4. `Publish-RoleSnapshot.ps1` and the policy Fixlet
use `http://127.0.0.1:52311/Uploads/CustomRepository/SoftwarePortal/roleref/…`. That is the
web root on the **root server**; on an ordinary endpoint `127.0.0.1` is the endpoint
itself. The Dispatcher uses this shape fleet-wide (Phase 3 UAT) but that staged files on
the root server — the per-region snapshot must reach **every** endpoint.

**Steps** (guide Step 7, "Pilot" row — do this *after* Section 787):

1. Publish **one** pilot region (guide "Pilot enablement package" below).
2. Run that region's policy action on a **non-root** pilot endpoint (not the root server,
   not a relay).
3. On that endpoint, check the BES client log and the filesystem.

**Pass:** the client downloads `roleref-<region>-latest.json` and the file appears under
the endpoint's `…\BES Client\EC\SoftwarePortal\roleref\`.

**Fail:** the client log shows a download failure or a `prefetch` hash mismatch for
`roleref-<region>-latest.json`, and no file lands under `EC\SoftwarePortal\roleref\`.

**Recorded outcome:** _(endpoint name; did the `127.0.0.1` URL work, or was a fallback
needed, and which one)_

**Mitigation (on fail):** Switch `PipelineConfig.SnapshotUrlBase` to the
**relay-qualified** form (`http://<relay>:52311/Uploads/CustomRepository/SoftwarePortal/roleref`),
**or** fall back to the documented `Invoke-WebRequest` GET of `…latest.json` inside the
reconcile. Re-run this section. **Record which mechanism the pilot ended up using.**

---

## Section D-21 — live `GPC_Sub_Name` values match the 13-value Region seed

**Assumption:** RESEARCH D-21 / Pitfall — the region gate is a **lower-cased exact string
comparison** in client relevance. A spelling or case difference between a live
`GPC_Sub_Name` value and its `Region` seed row silently targets **zero** endpoints.

**Seed (13 values, exact spelling):**
`UAP`, `MOT`, `APAC`, `APAC-MOT`, `APAC-M&A`, `AAG-DE`, `AAG-FR`, `AAG-UK`, `AAG-ES`,
`AAG-BLX`, `AAG-PL`, `AAG-PT`, `GPC`.

**Steps** (guide Step 3 / Step 7 "Widen" — do this before publishing each affected region):

1. Add a **temporary** retrieved property or Analysis returning
   `value of setting "GPC_Sub_Name" of client` across the production fleet
   (07-RESEARCH Open Question 4 recommends exactly this).
2. Enumerate the **distinct** values, preserving spelling and case.
3. Compare every distinct live value against the 13 seed rows — **an exact match,
   including case**.

**Pass:** every distinct live `GPC_Sub_Name` value matches a `Region` seed row exactly
(same characters, same case). No live value is absent from the seed.

**Fail:** any live value is absent from the seed, or differs from its intended seed row in
spelling or case (e.g. `aag-uk` vs `AAG-UK`, `APAC M&A` vs `APAC-M&A`).

**Recorded outcome:**

| Distinct live `GPC_Sub_Name` | Matches a seed row exactly (incl. case)? | Seed row it maps to | Correction made |
|------------------------------|------------------------------------------|---------------------|-----------------|
| _(fill in — one row per distinct live value)_ | | | |

Region-table corrections made: _(list any `Region` rows added or edited, or "none")_

**Mitigation (on fail):** Add or correct `Region` rows **before publishing that region**.
The comparison is lower-cased on the endpoint side, so a *case* difference is tolerated
only if both sides lower-case identically — a *spelling* difference is not. Do not publish
a region whose live value has no exact seed match.

---

## Section 787 — task 787 redeploy actually updates `RoleDB_Maintenance` on provisioned endpoints

**Assumption:** RESEARCH Pitfall 5 / Runtime State. The live `Action1` of task 787 still
registers `RoleDB_Maintenance` running **only** `Initialize-RoleDb.ps1`, and the
re-registration is gated on "task does not exist" — so simply redeploying the updated
`.bes` does **not** change the command line on an endpoint that already has the task.

**Steps** (guide Step 6):

1. Push the committed `Dashboard_4_samples\Init  Current User and UserRole DB.bes` to
   **task 787** in `custom/Dereso Software Portal` (REST `PUT /api/task/custom/<site>/787`
   or console replace). Confirm the new `Action1` body on the server.
2. Run the task on **one already-provisioned** endpoint (one that already had
   `RoleDB_Maintenance` from the old version).
3. Open Task Scheduler on that endpoint and inspect `RoleDB_Maintenance`.
4. Do a logoff/logon cycle and confirm both scripts run.

**Pass:** `RoleDB_Maintenance` now shows **two** actions — `Initialize-RoleDb.ps1` **and**
`Reconcile-LocalRoles.ps1` — and a logoff/logon runs both.

**Fail:** `RoleDB_Maintenance` still shows the **single** old action
(`Initialize-RoleDb.ps1` only) — the `Unregister-ScheduledTask` before the re-register
guard did not take.

**Recorded outcome:** _(endpoint name; number of actions on `RoleDB_Maintenance` after
redeploy; did a logoff/logon run both scripts)_

**Mitigation (on fail):** Confirm the redeployed `.bes` contains
`Unregister-ScheduledTask -TaskName RoleDB_Maintenance -Confirm:$false` **before** the
`not (exists (scheduled tasks …))` guard. Unregister the task **manually** on the pilot
endpoints and re-run task 787, then fix the gating before the fleet.

---

## Section Pilot — one region end to end

**Assumption:** everything upstream is verified; this proves a **real** role lands in a
**real** endpoint's database and the downstream consumers still read it. FR-03 and FR-09
depend on the `RoleAwareness.db` `Map` contract being intact after the endpoint `Map`
migration.

**Steps** (guide Step 7 "Pilot" + the "Pilot enablement package"):

1. With **one** region published and its policy action enabled, wait for a pilot endpoint
   in that region to reconcile (policy action evaluation or next logon).
2. On that pilot endpoint, query `RoleAwareness.db`:
   - the expected role for a **real** user appears in `Map`;
   - `Assigned_By = 'AxoniousSync'`;
   - `Valid_to` is roughly `ValidityMonths` (default 6) in the future;
   - `Source_Value` is populated (pipe-joined if the user got the role from >1 group);
   - `Region` equals the endpoint's own `GPC_Sub_Name`;
   - a row with `Locked_by_Override = 1`, if any, is **unchanged**;
   - the `roleref_<region>_applied` client setting was written.
3. Confirm the downstream consumers still read roles correctly:
   `fixlet_modifier.ojo` role relevance, `fixlet_console.ojo`, and the SSA
   `_dashboard.html` role panel.

**Pass:** all of the bullets in step 2 hold, **and** the three downstream consumers still
resolve roles correctly.

**Fail:** the expected role is absent from `Map`; or `Assigned_By` is not `AxoniousSync`;
or a `Locked_by_Override = 1` row was modified; or `Source_Value` / `Region` is blank; or
a downstream consumer no longer resolves roles.

**Recorded outcome:**

| Field | Observed |
|-------|----------|
| Pilot region | |
| Pilot endpoint | |
| User | |
| Role | |
| `Assigned_By` | |
| `Valid_to` | |
| `Region` | |
| `Source_Value` | |
| `Locked_by_Override = 1` row unchanged? | |
| `roleref_<region>_applied` setting written? | |
| `fixlet_modifier.ojo` / `fixlet_console.ojo` / SSA role panel still resolve roles? | |

Overall Pilot result: _(pass / fail)_

**Mitigation (on fail):** Diagnose with the run-book Troubleshooting table (symptom-keyed).
Common causes: A1 not actually settled (→ re-do Section A1), the policy Fixlet's prefetch
`sha1:` stale (→ confirm `DeresoRolePublish` re-`PUT` ran), or a `Match_On` mismatch in the
`GroupRoleMap` rules (→ Role Admin **Test Pattern**). Do **not** widen past the pilot until
this section passes.

---

## Sign-off

- [ ] Section A1 — recorded outcome present; passed (or mitigation applied and re-tested).
- [ ] Section A2 — recorded outcome present; records which URL mechanism the pilot used.
- [ ] Section D-21 — recorded outcome lists every distinct live `GPC_Sub_Name` and any
      `Region` corrections.
- [ ] Section 787 — recorded outcome confirms `RoleDB_Maintenance` runs both scripts on a
      previously-provisioned endpoint.
- [ ] Section Pilot — recorded outcome table filled; a real role is in a real endpoint's
      `RoleAwareness.db` with `Assigned_By = 'AxoniousSync'`.
- [ ] **Exactly one region is enabled.** No second region; content pipeline still in
      `-WhatIf` or live with auto-approve OFF.

**Operator:** _____________________  **Date:** _____________________

Reply **"approved"** to the execution checkpoint once every box above is ticked.
