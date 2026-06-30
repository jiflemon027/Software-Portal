---
phase: 05-robustness
created: 2026-06-29
status: planning
---

# Phase 5: Robustness — Context & Decisions

## Phase Goal

Harden the Role Awareness system for production: automatic Users table maintenance
(FR-08, delivered) and a consolidated Web Report tying all role-aware fixlets and
their deployed actions into one operator-scoped view (FR-09).

---

## Deliverable 1: Logon Scheduled Task (FR-08) — COMPLETE

Implemented as a post-Phase-4 improvement; committed in `2895ef3`. The init BES task
now registers `Dereso\UpdateUserOnLogon` on each endpoint. Details in
`docs/role-assigner-admin-guide.md`.

---

## Deliverable 2: Role-Aware Web Report (FR-09) — PLANNING

### Decision Log

#### D-01: Filter — Operator Scope
**Decision:** Show only actions where at least one targeted/applied computer is within
the Web Reports logged-in operator's assigned computer scope.

**Rationale:** Uses BigFix's native operator permissions model. No additional role-to-user
lookup is required; operators already see the subset of computers they are responsible for.

**Implementation:** Session relevance on the actions query includes a `whose` clause that
checks `bes computers of it` against the operator's assigned computers. Fixlets are shown
unfiltered — an operator sees all role-aware fixlets in the site, but only actions that
touch their own estate.

---

#### D-02: Layout — Fixlet-Grouped, Nested (expandable)
**Decision:** Each fixlet is a summary row (click to expand); child rows show actions
scoped to the operator's computers. Fixlets with zero scoped actions still appear, with
a "No actions affecting your devices" message on expand.

**Rationale:** Preserves fixlet visibility (operator can see what software is in the
portal even if they have not yet deployed it), while keeping the per-action detail
subordinate.

---

#### D-03: Data Source — `Relevance()` Async JavaScript API  *(revised from `<Relevance>` tag approach)*
**Decision:** Use the BigFix Web Reports built-in `Relevance(queryString, callbackObject)`
JavaScript function to retrieve data asynchronously after page load.

```javascript
Relevance(relevanceString, {
  success: function(results) { /* results: string[] — one entry per matched item */ },
  failure: function(xhr, textStatus, errorThrown) { /* error handling */ }
});
```

**Rationale:** Confirmed from `Dashboard_4_samples/webreport_sample.txt`. The sample uses
this API pattern exclusively. Each call returns an array of strings (one per matched item).
Fields are `|`-delimited within each string (`result.split('|')`). This is the established
pattern for this Web Reports environment.

**Delimiter:** `|` (single pipe) — same as sample's action query. Field values (role names,
fixlet names) in this project do not contain `|`, so this is safe.

---

#### D-04: BLOCKED — Awaiting Session Relevance Strings
**Status:** BLOCKED. User will provide the session relevance expressions for:

1. **Fixlet query** — returns tuples of `(id, name, sitename, associated_role)` for all
   role-aware fixlets in the Dereso Software Portal site
2. **Action query** — returns tuples of `(action_id, action_name, roles, source_fixlet_id,
   source_sitename)` for all actions spawned from role-aware fixlets, using the MIME fields
   added to action XML by the Role Assigner and Modifier dashboards
3. **Operator scope** — session relevance expression for the operator's assigned computers,
   used as the `whose` filter on the action query

Until these strings are provided, Plan 05-01 can be executed to the point of scaffolding
the `.beswrpt` file but the live data queries cannot be wired.

---

#### D-05: Username Format Consistency
The Web Report is read-only and does not query `RoleAwareness.db` directly.
Username-format consistency (SAM account name, no domain prefix) is enforced by FR-08
at write time. The report reads from BigFix Analysis properties if any user-level
cross-referencing is needed in a future iteration.

---

#### D-06: Action Status Column
Actions will show their current BigFix status (Open, Expired, Stopped, etc.) retrieved
from session relevance alongside the other action fields. This lets operators see at a
glance whether a role-assignment action is still active.

---

#### D-07: Table Rendering — DataTables with Local Resources
**Decision:** Use DataTables + jQuery loaded from the BigFix Web Reports server's own
`/JavaScript/datatables/` path. No CDN dependency.

**CSS links** (from sample):
```
/JavaScript/datatables/css/bootstrap.min.css
/JavaScript/datatables/css/dataTables.bootstrap.min.css
/JavaScript/datatables/css/buttons.dataTables.css
/JavaScript/datatables/css/select.dataTables.css
/JavaScript/datatables/css/jquery.dataTables.min.1.10.25.css
/JavaScript/datatables/css/searchBuilder.dataTables.min.1.1.0.css
/JavaScript/datatables/css/searchPanes.dataTables.min.1.3.0.css
/JavaScript/datatables/css/select.dataTables.min.1.3.3.css
/JavaScript/datatables/css/dataTables.dateTime.min.1.1.0.css
```

**JS scripts** (from sample, load order matters):
```
/JavaScript/datatables/js/jquery-3.5.1.js
/JavaScript/datatables/js/jquery.dataTables.min.1.10.25.js
/JavaScript/datatables/js/jszip.js
/JavaScript/datatables/js/pdfmake.js
/JavaScript/datatables/js/vfs_fonts.js
/JavaScript/datatables/js/dataTables.buttons.js
/JavaScript/datatables/js/buttons.colVis.js
/JavaScript/datatables/js/buttons.html5.js
/JavaScript/datatables/js/buttons.print.js
/JavaScript/datatables/js/dataTables.select.js
/JavaScript/datatables/js/dataTables.bootstrap.min.js
/JavaScript/datatables/js/dataTables.searchBuilder.min.1.1.10.js
/JavaScript/datatables/js/dataTables.searchPanes.min.1.3.0.js
/JavaScript/datatables/js/dataTables.select.min.1.3.3.js
/JavaScript/datatables/js/dataTables.dateTime.min.1.1.0.js
/JavaScript/datatables/js/moment.min.2.8.4.js
/JavaScript/datatables/js/datetime-moment.1.10.19.js
```

#### D-08: Fixlet Grouping — DataTables `drawCallback` with `.group` row injection
**Decision:** Use the standard DataTables row-grouping pattern (matching the sample's
`.group` / `.group:hover` CSS): sort rows by fixlet name, then inject `<tr class="group">`
header rows in `drawCallback` whenever the fixlet name changes.

```javascript
drawCallback: function(settings) {
  var api = this.api();
  var rows = api.rows({ page: 'current' }).nodes();
  var last = null;
  api.column(0, { page: 'current' }).data().each(function(group, i) {
    if (last !== group) {
      $(rows).eq(i).before(
        '<tr class="group"><td colspan="N"><b>' + group + '</b> — <span class="fixlet-roles">...</span></td></tr>'
      );
      last = group;
    }
  });
}
```

Group header shows fixlet name + fixlet roles. Action rows underneath show action-level fields.

---

### Architecture Summary

```
.beswrpt file (XML)
  └─ <Main> CDATA
       ├─ DataTables CSS <link> tags  (/JavaScript/datatables/css/*)
       ├─ DataTables JS <script> tags (/JavaScript/datatables/js/*)
       ├─ PORTAL_CONFIG (JS const — roles, site name)
       ├─ $(document).ready → DataTable('#srch') init (empty)
       ├─ SearchForData() → Relevance(fixletQuery, fixletCb)
       │     fixletCb.success → stores fixletMap[], calls Relevance(actionQuery, actionCb)
       │     actionCb.success → joins fixlet+action data, calls z.rows.add(rows).draw()
       └─ drawCallback injects <tr class="group"> fixlet header rows
```

**Data flow:**
1. Page loads; empty DataTable initialised on `$(document).ready`
2. `SearchForData()` fires `Relevance(fixletQuery, fixletCb)` async
3. `fixletCb.success` stores fixlet array, then fires `Relevance(actionQuery, actionCb)` async
4. `actionCb.success` joins actions to their source fixlet, builds flat DataTable row array
5. `z.rows.add(rows).draw()` populates the table
6. DataTables `drawCallback` inserts `.group` header rows between fixlet groups

---

### Open Questions

| # | Question | Owner | Status |
|---|----------|-------|--------|
| OQ-1 | Session relevance for fixlet query (id, name, sitename, role) | User | **ANSWERED** |
| OQ-2 | Session relevance for action query | User | **ANSWERED** — no explicit operator scope clause needed (see OQ-2 note) |
| OQ-3 | MIME field names on actions | User | **ANSWERED** — derived from OQ-1/OQ-2: `Associated_Roles` + `SmartRole_Source` |
| OQ-4 | BigFix Web Reports server version — affects `<Relevance>` tag support | User | OPEN (non-blocking) |

---

### OQ-1 Answer — Fixlet Session Relevance

**Provided by user:**
```
((item 0 of it as string,
  item 1 of it as string,
  item 2 of it as string,
  item 3 of it as string)
of
  (id of it,
   name of it,
   name of site of it,
   (if (exists mime fields whose (name of it = "Associated_Roles") of it)
    then ((if (exists value whose (not(it = "")) of it)
           then (concatenation " | " of values of it)
           else "Nulled Role")
          of mime fields whose (name of it = "Associated_Roles") of it)
    else "General Access")
  )
of ((bes fixlets) whose ((exists fixlet flag of it)
     and (exists site whose (name of it contains "Dereso Software Portal") of it))))
```

**Key notes:**
- MIME field: `Associated_Roles` (multi-value; roles joined with ` | `)
- `"General Access"` — field absent (fixlet not modified by Modifier dashboard)
- `"Nulled Role"` — field present but all values empty
- Filter: `exists fixlet flag of it` ensures Fixlets only (not Tasks or Analyses)

**Adapted for BESWRPT** — single `|||`-delimited line per fixlet (same logic):
```
((item 0 of it as string & "|||" & item 1 of it as string & "|||" & item 2 of it as string & "|||" & item 3 of it as string)
of (id of it, name of it, name of site of it,
    (if (exists mime fields whose (name of it = "Associated_Roles") of it)
     then ((if (exists value whose (not(it = "")) of it)
            then (concatenation " | " of values of it) else "Nulled Role")
           of mime fields whose (name of it = "Associated_Roles") of it)
     else "General Access"))
of ((bes fixlets) whose ((exists fixlet flag of it)
     and (exists site whose (name of it contains "Dereso Software Portal") of it))))
```

**JS parse:** split on `\n`, then each line on `|||` → `{ id, name, site, roles[] }` (roles split on ` | `)

---

### OQ-2 Answer — Action Session Relevance

**Provided by user:**
```
((item 0 of it as string,
  item 1 of it as string,
  item 2 of it as string,
  (value of key "id"       of json of item 3 of it) as string,
  (value of key "sitename" of json of item 3 of it) as string)
of
  (id of it,
   name of it,
   (if (exists MIME Field whose (name of it = "Associated_Roles") of it)
    then (concatenation "" of values of MIME Fields whose (name of it = "Associated_Roles") of it)
    else "General Access") of it,
   (if (exists MIME Field whose (name of it = "SmartRole_Source") of it)
    then (concatenation "" of values of MIME Fields whose (name of it = "SmartRole_Source") of it)
    else ("{%22id%22:%22%22,%22sitename%22:%22%22}")) of it
  )
of (bes actions whose (
     (exists offer flag of it) and
     (exists MIME Field whose (name of it = "Associated_Roles") of it) and
     (exists MIME Field whose (name of it = "SmartRole_Source") of it))))
```

**Key notes:**
- MIME fields on actions: `Associated_Roles` (role name) + `SmartRole_Source` (JSON: `{"id":"…","sitename":"…"}`)
- `SmartRole_Source` default fallback is URL-encoded `{"id":"","sitename":""}` — decodes at parse time
- `concatenation ""` on `Associated_Roles` — no separator between values. Each action targets exactly one role (Role Assigner deploys one action per role), so single-value is the expected case
- `SmartRole_Source` links back to the source fixlet: `value of key "id"` → fixlet ID string; `value of key "sitename"` → site name string
- Filter: `exists offer flag` + both MIME fields present — identifies Dereso-managed offer actions
- **Operator scope filter: HANDLED NATIVELY by Web Reports engine** — session relevance in Web Reports evaluates in the context of the logged-in operator; `bes computers` is already scoped to that operator's visible estate. No explicit `whose` clause is required. The relevance as provided is complete.

**MIME field names confirmed (OQ-3):**
| Field | Carrier | Content |
|-------|---------|---------|
| `Associated_Roles` | Fixlets + Actions | Role name(s). On fixlets: multiple values joined ` | `. On actions: single value, no separator |
| `SmartRole_Source` | Actions only | JSON string `{"id":"<fixletId>","sitename":"<site>"}` linking action back to source fixlet |

**Adapted for BESWRPT** — single `|||`-delimited line per action (5 fields, no operator scope clause needed):
```
((item 0 of it as string & "|||" & item 1 of it as string & "|||" & item 2 of it as string & "|||" & (value of key "id" of json of item 3 of it) as string & "|||" & (value of key "sitename" of json of item 3 of it) as string)
of (id of it, name of it,
    (if (exists MIME Field whose (name of it = "Associated_Roles") of it)
     then (concatenation "" of values of MIME Fields whose (name of it = "Associated_Roles") of it)
     else "General Access") of it,
    (if (exists MIME Field whose (name of it = "SmartRole_Source") of it)
     then (concatenation "" of values of MIME Fields whose (name of it = "SmartRole_Source") of it)
     else ("{%22id%22:%22%22,%22sitename%22:%22%22}")) of it)
of (bes actions whose (
     (exists offer flag of it) and
     (exists MIME Field whose (name of it = "Associated_Roles") of it) and
     (exists MIME Field whose (name of it = "SmartRole_Source") of it))))
```

**JS parse:** split on `\n`, then each line on `|||` → `{ actionId, name, role, sourceFixletId, sourceSite }`
URL-decode the `SmartRole_Source` fallback value to handle `%22`-encoded JSON.
