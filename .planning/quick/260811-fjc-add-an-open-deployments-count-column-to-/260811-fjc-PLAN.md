---
phase: quick/260811-fjc
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Existing Dashboards/fixlet_dispatcher.ojo
  - Existing Dashboards/fixlet_modifier.ojo
  - tests/unit/open_deployments.test.js
autonomous: false
requirements: [QUICK-260811-fjc]

must_haves:
  truths:
    - "Both dashboard grids show an 'Open Deployments' column with a per-fixlet count of currently-open BigFix actions"
    - "The count matches the number checkExistingDeployment() reports for that same fixlet when it is selected in the dispatcher"
    - "Clicking the 'Open Deployments' header sorts numerically (10 sorts after 9, not before it)"
    - "Loading the grid costs exactly two EvaluateRelevance calls total, not one per fixlet"
    - "A fixlet with zero open actions shows 0; if the count query fails the column shows a dash, never a misleading 0"
  artifacts:
    - path: "Existing Dashboards/fixlet_dispatcher.ojo"
      provides: "loadOpenDeploymentCounts() helper + openDeployments column wiring"
      contains: "loadOpenDeploymentCounts"
    - path: "Existing Dashboards/fixlet_modifier.ojo"
      provides: "loadOpenDeploymentCounts() helper + openDeployments column wiring"
      contains: "loadOpenDeploymentCounts"
    - path: "tests/unit/open_deployments.test.js"
      provides: "Pure-logic tests for the count map + numeric comparator, plus structural parity assertions across both .ojo files"
      contains: "buildOpenDeploymentMap"
  key_links:
    - from: "loadAllFixlets()"
      to: "loadOpenDeploymentCounts()"
      via: "called once before the allItems loop; result keyed by fixlet name"
      pattern: "loadOpenDeploymentCounts\\(\\)"
    - from: "addHeader()"
      to: "applySortToCurrentItems()"
      via: "makeSortHeader('openDeployments', ...) -> sortBy -> numeric branch"
      pattern: "openDeployments"
---

<objective>
Add a sortable "Open Deployments" count column to the fixlet grids in both
`fixlet_dispatcher.ojo` and `fixlet_modifier.ojo`. Each row shows how many
BigFix actions are currently in state "Open" whose name matches that fixlet's
name — the same match-by-Title rule already proven in the dispatcher's
`checkExistingDeployment()`.

Purpose: today an operator only learns a fixlet already has open deployments
after selecting it (dispatcher) or not at all (modifier). Surfacing the count
in the grid makes duplicate deployments visible before a selection is made.

Output: one new column in each grid, one shared helper function duplicated
verbatim into both files, and a Node unit test covering the counting logic and
cross-file wiring parity.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@.claude/skills/bigfix-relevance/SKILL.md

@Existing Dashboards/fixlet_dispatcher.ojo
@Existing Dashboards/fixlet_modifier.ojo
@tests/unit/dispatcher.test.js
</context>

<design_decision>
## Why NOT a correlated subquery inside the existing bulk tuple

The obvious approach — appending
`(number of bes actions whose (state of it = "Open" and name of it = name of it))`
as another `|||` field in the existing per-fixlet tuple — is **wrong and must
not be implemented**. Inside a `whose (...)` clause, BigFix session relevance
rebinds `it` to the item being filtered (the `bes action`). So
`name of it = name of it` is an action-name-equals-its-own-name self
comparison: always true.

Failure signature (important — it does not throw): every row renders the
**same** number, equal to the total count of all open actions server-wide.
Silent wrong data, not a crash.

BigFix session relevance has no variable binding, so an outer fixlet value
cannot be referenced from inside an inner `whose`. The only single-expression
workaround is a cartesian `(bes fixlets, bes actions)` tuple filtered on
`name of item 0 of it = name of item 1 of it`, which still needs a JS-side
group-by and is far more expensive server-side.

## What to implement instead

**One additional bulk query + a JavaScript hash-map join.** Total cost per grid
load is **two** `EvaluateRelevance()` calls — still O(1) in the number of
fixlets, which is the actual requirement ("one relevance evaluation for the
whole grid, not N queries").

```
(name of it) of bes actions whose (state of it = "Open")
```

This is the exact inspector shape already proven in `checkExistingDeployment()`
(`state of it = "Open"` + match on action `name`), minus the interpolated
`safeName` literal. Counting happens in JS.

Two side benefits worth noting: the new query interpolates **no** user or
server-derived string into the relevance text at all, so it has zero relevance
injection surface (unlike the `safeName` form); and matching stays
**case-sensitive**, byte-identical to `checkExistingDeployment()`, so the grid
count and the detail-panel indicator can never disagree.

A `unique values of` + `multiplicity of it` server-side group-by would shrink
the payload, but carries BigFix-version risk for no meaningful gain at
realistic open-action volumes. Do not use it.
</design_decision>

<shared_helper>
This exact code is duplicated **verbatim** into both `.ojo` files and into the
test file. Duplicating small helpers across dashboards is the established
convention in this codebase (`htmlEscape`, `xmlEscape`, `makeSortHeader` are
already duplicated). Keep all three copies byte-identical.

Pure counting logic (the part under test):

    function buildOpenDeploymentMap(names){
      var map = {}, i, key;
      for(i = 0; i < names.length; i++){
        key = String(names[i]);
        map[key] = (map[key] || 0) + 1;
      }
      return map;
    }

Relevance wrapper (not unit-testable — needs the console host):

    function loadOpenDeploymentCounts(){
      try {
        var rel  = '(name of it) of bes actions whose (state of it = "Open")';
        var data = EvaluateRelevance(rel);
        return buildOpenDeploymentMap(data || []);
      } catch(ex) {
        return null;
      }
    }

Contract notes for the executor:
- `null` return means "query failed" and is deliberately distinct from an empty
  map. An empty map means "queried fine, zero open actions".
- Keys are exact, case-sensitive fixlet/action names. Do **not** `toLowerCase()`
  or trim — that would drift from `checkExistingDeployment()`.
- `map` is a plain object used as a hash. Guard lookups with `|| 0`. Names like
  `"constructor"` or `"toString"` would collide with `Object.prototype`; accept
  this (real fixlet names do not collide) rather than adding a prefix scheme.
</shared_helper>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Unit-test the counting logic and the numeric comparator</name>
  <files>tests/unit/open_deployments.test.js</files>
  <behavior>
    - buildOpenDeploymentMap([]) returns {} (empty map, not null)
    - buildOpenDeploymentMap(["A","B","A"]) returns { A: 2, B: 1 }
    - Counting is case-sensitive: ["Adobe","adobe"] yields two distinct keys of 1 each
    - Lookup of an absent name via (map[name] || 0) yields 0
    - Numeric comparator sorts "10" after "9" ascending (proves it is not a string sort)
    - Numeric comparator treats "" and "—" as 0 rather than throwing or producing NaN ordering
    - Numeric comparator descending is the exact reverse of ascending
  </behavior>
  <action>
    Create tests/unit/open_deployments.test.js following the established pattern
    in tests/unit/dispatcher.test.js: "use strict", require("assert") only, no
    external packages, functions copied verbatim from the .ojo source under a
    clearly labelled "EXTRACTED FUNCTION IMPLEMENTATIONS" section, and a
    pass/fail counter that calls process.exit(failed > 0 ? 1 : 0).

    Copy buildOpenDeploymentMap verbatim from the plan's shared_helper section.
    Do not copy loadOpenDeploymentCounts — it calls EvaluateRelevance, which does
    not exist in Node; note that omission in the file header comment the same way
    dispatcher.test.js documents its buildDeployXml omission.

    Also copy in the comparator body that Tasks 2 and 3 will add to
    applySortToCurrentItems, as a standalone function so it can be exercised
    directly:

      function compareOpenDeployments(a, b, asc){
        var na = parseInt(String(a.openDeployments || ""), 10) || 0;
        var nb = parseInt(String(b.openDeployments || ""), 10) || 0;
        return asc ? na - nb : nb - na;
      }

    Reserve a section header comment "STRUCTURAL PARITY ASSERTIONS" at the end of
    the file with a note that Tasks 2 and 3 append to it. Leave it empty for now
    so this task ends green.
  </action>
  <verify>
    <automated>node tests/unit/open_deployments.test.js</automated>
  </verify>
  <done>Test file exists, exits 0, and all listed behaviors have an assertion.</done>
</task>

<task type="auto">
  <name>Task 2: Wire the Open Deployments column into fixlet_dispatcher.ojo</name>
  <files>Existing Dashboards/fixlet_dispatcher.ojo, tests/unit/open_deployments.test.js</files>
  <action>
    Edit `Existing Dashboards/fixlet_dispatcher.ojo` only through Claude's own
    file-writing tools — per the bigfix-relevance skill, .ojo files must never be
    saved from another editor while Claude has them open. Preserve
    IE9-compatible ES5 syntax throughout: `var` only, no arrow functions, no
    `let`/`const`, no `Array.prototype.forEach`/`map` on relevance results, no
    template literals.

    1. Globals (beside the existing block at ~lines 201-215, after
       `var sourcePrefetchLines = [];`): add
       `var openDeploymentCounts = null;`

    2. Helper: insert `buildOpenDeploymentMap` and `loadOpenDeploymentCounts`
       verbatim from the plan's shared_helper section, immediately above
       `loadAllFixlets()` (~line 273). Include a short comment explaining that
       the count is joined in JS because a correlated subquery inside a `whose`
       clause rebinds `it` to the action — cite the always-true self-comparison
       failure mode so this is not "simplified" back later.

    3. `loadAllFixlets()` (~lines 274-308): leave the existing relevance string
       and its `|||` tuple completely unchanged. Before the `for` loop, add
       `openDeploymentCounts = loadOpenDeploymentCounts();`. Inside the loop, add
       a field to the pushed object, after `itemType`:
       `openDeployments: (openDeploymentCounts === null ? "—" : String(openDeploymentCounts[p[1]] || 0))`
       (`p[1]` is the fixlet name in this file's tuple.)

    4. `addHeader()` (~lines 246-254): append a sixth header cell **last**, after
       the Site cell: `r.insertCell(-1).innerHTML = makeSortHeader("openDeployments", "Open Deployments");`
       Appending last keeps header and body cell order aligned without disturbing
       the existing Select/Name/Category/Roles/Site columns.

    5. `renderPage()` (~lines 348-370): append a sixth body cell last, matching
       the header order, and reuse the existing #cc6600 bold treatment already
       used by checkExistingDeployment for a non-zero count:

         var oc = item.openDeployments || "0";
         r.insertCell(-1).innerHTML = (parseInt(oc, 10) > 0)
           ? '<span style="color:#cc6600; font-weight:bold;">' + htmlEscape(oc) + '</span>'
           : htmlEscape(oc);

       Declare `oc` in the function's existing `var i, item, r;` declaration line
       rather than inside the loop body.

    6. `applySortToCurrentItems()` (~lines 401-413): this file currently
       string-sorts every column. Add a numeric branch as the first statement
       inside the sort callback, before the existing `va`/`vb` string path:

         if(col === "openDeployments"){
           na = parseInt(String(a[col] || ""), 10) || 0;
           nb = parseInt(String(b[col] || ""), 10) || 0;
           return asc ? na - nb : nb - na;
         }

       Extend the callback's `var va, vb;` declaration to `var va, vb, na, nb;`.
       This mirrors the branch fixlet_modifier.ojo already has for `id`.

    7. Do not touch `checkExistingDeployment()`, the Roles/`roleValue` logic, the
       search filter field list in `filterAndRender()`, or any deploy/staging code.

    8. Append dispatcher structural assertions to the STRUCTURAL PARITY
       ASSERTIONS section of tests/unit/open_deployments.test.js: read the .ojo
       with fs.readFileSync and assert the file contains
       `makeSortHeader("openDeployments"`, `loadOpenDeploymentCounts()`,
       `buildOpenDeploymentMap`, and `openDeployments:`; and assert it does NOT
       contain the forbidden correlated form `name of it = name of it`.
  </action>
  <verify>
    <automated>node tests/unit/open_deployments.test.js</automated>
  </verify>
  <done>
    Dispatcher grid renders six columns with Open Deployments last; the file
    passes all dispatcher structural assertions; no ES6 syntax introduced; the
    existing fixlet tuple relevance string is byte-identical to before.
  </done>
</task>

<task type="auto">
  <name>Task 3: Wire the same column into fixlet_modifier.ojo</name>
  <files>Existing Dashboards/fixlet_modifier.ojo, tests/unit/open_deployments.test.js</files>
  <action>
    Apply the identical change to `Existing Dashboards/fixlet_modifier.ojo`,
    keeping the helper byte-identical to the dispatcher copy. Same
    Claude-tools-only and ES5-only constraints as Task 2.

    1. Globals: add `var openDeploymentCounts = null;` after
       `var selectedKeys    = {};` (~line 85).

    2. Helper: insert `buildOpenDeploymentMap` + `loadOpenDeploymentCounts`
       verbatim, immediately above `loadAllFixlets()` (~line 195), with the same
       explanatory comment.

    3. `loadAllFixlets()` (~lines 195-233): leave the existing relevance string
       and tuple unchanged. Add `openDeploymentCounts = loadOpenDeploymentCounts();`
       before the `for` loop. Add to the pushed object after `itemType`:
       `openDeployments: (openDeploymentCounts === null ? "—" : String(openDeploymentCounts[p[1]] || 0))`
       (`p[1]` is the fixlet name here too — note this file's tuple has seven
       fields, p[0]..p[6], so the new JS field is derived, not a new p[7].)

    4. `addHeader()` (~lines 116-125): append a seventh header cell last, after
       the Roles cell:
       `r.insertCell(-1).innerHTML = makeSortHeader("openDeployments", "Open Deployments");`

    5. `renderPage()` (~lines 309-336): append the matching body cell last, using
       the same conditional #cc6600 markup as Task 2. Declare `oc` in the
       existing `var i, item, r, key, chk;` line.

    6. `applySortToCurrentItems()` (~lines 367-384): this file already has a
       numeric branch for `id`. Extend it rather than adding a second branch:
       change `if(col === "id"){` to
       `if(col === "id" || col === "openDeployments"){`.
       The existing body already does `parseInt(...) || 0` on `a[col]`/`b[col]`,
       which handles the "—" fallback as 0.

    7. Do not touch the Roles/`roleValue` column (confirmed out of scope), the
       site filter, `filterAndRender()`'s search field list, or the bulk-edit /
       PUT code paths.

    8. Append modifier structural assertions to the STRUCTURAL PARITY ASSERTIONS
       section: the same four required substrings plus the forbidden-form check,
       and one cross-file assertion that the `buildOpenDeploymentMap` function
       body extracted from each .ojo is identical between the two files
       (normalize line endings before comparing).
  </action>
  <verify>
    <automated>node tests/unit/open_deployments.test.js</automated>
  </verify>
  <done>
    Modifier grid renders seven columns with Open Deployments last; both files
    pass structural assertions; the helper is provably identical across both
    .ojo files; existing modifier tests still pass
    (`node tests/unit/modifier.test.js`).
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: Verify both grids in the BigFix console</name>
  <files>none — verification only, no files change in this task</files>
  <action>
    Pause and hand control to the developer. Claude has already automated
    everything automatable; the remaining checks require the BigFix console,
    which has no CLI equivalent. Present the what-built and how-to-verify content
    below, then wait for the resume signal. Do not modify any file during this
    task.
  </action>
  <what-built>
    An "Open Deployments" column, last in the grid, in both the Dereso Fixlet
    Dispatcher and Dereso Fixlet Modifier dashboards. It is populated by one
    extra bulk session-relevance query per grid load
    (`(name of it) of bes actions whose (state of it = "Open")`) joined to rows
    in JavaScript by exact fixlet name. Counts greater than zero render in the
    same orange bold already used by the dispatcher's existing-deployment
    indicator. The header sorts numerically.
  </what-built>
  <how-to-verify>
    1. Import both .ojo files into the BigFix console and open the Dispatcher
       dashboard. Confirm the grid loads and shows an "Open Deployments" column
       as the rightmost column.
    2. Pick a fixlet you know has at least one open action. Confirm its grid
       count is greater than zero and orange/bold.
    3. Select that same fixlet. Confirm the detail panel's existing
       "N open action(s) already exist for this fixlet" line reports the SAME
       number as the grid cell. A mismatch means the name-matching drifted.
    4. CRITICAL regression check: confirm different fixlets show DIFFERENT
       counts. If every row shows the same number, the correlated-subquery bug
       described in the plan's design_decision section has been reintroduced —
       reject and fix.
    5. Click the "Open Deployments" header. Confirm sorting is numeric: a row
       with 10 must sort after a row with 9 ascending, not before it. Click
       again and confirm the order reverses.
    6. Confirm fixlets with no open actions show 0 (plain, not orange).
    7. Open the Modifier dashboard, click Load Fixlets, and repeat steps 1, 4,
       5 and 6 there. Confirm the existing Roles column is unchanged.
    8. Confirm grid load time is not noticeably slower than before — there
       should be exactly two relevance round-trips, not one per row.
  </how-to-verify>
  <verify>
    <human-check>Developer confirms all eight steps above in the BigFix console</human-check>
  </verify>
  <done>Developer replies "approved", or reports defects that are then fixed and re-verified.</done>
  <resume-signal>Type "approved" or describe what rendered incorrectly</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| BES server -> dashboard JS | Action names returned by EvaluateRelevance are server-controlled strings, but a BigFix operator can create an action with an arbitrary Title, so treat them as untrusted content |
| dashboard JS -> innerHTML | New grid cell writes a value derived from that server data into the DOM |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-QT-01 | Tampering | new relevance string in `loadOpenDeploymentCounts()` | mitigate | The query is a fixed literal with no interpolated values, so there is no relevance-injection surface at all. Do not "improve" it by interpolating a fixlet name — that reintroduces the escaping burden the plan removed. |
| T-QT-02 | Information disclosure / XSS | new grid cell in `renderPage()` | mitigate | The cell value is a count string, and it is still passed through the existing `htmlEscape()` before insertion, inside the conditional orange-span branch as well as the plain branch. No raw action name is ever written to the DOM. |
| T-QT-03 | Denial of service | grid load path | mitigate | Exactly one extra `EvaluateRelevance` call per grid load, independent of row count. The per-row query pattern is explicitly rejected in design_decision. |
| T-QT-04 | Repudiation / wrong data | count join by name | accept | Match-by-Title can over-count if two distinct fixlets share a name, exactly as the existing `checkExistingDeployment()` already does. Consistency with the proven indicator is worth more than a stricter but less reliable source-fixlet match. |
| T-QT-SC | Tampering | npm/pip/cargo installs | n/a | No package installs occur. The test uses only Node's built-in `assert`, matching every existing test in `tests/unit/`. |
</threat_model>

<verification>
- `node tests/unit/open_deployments.test.js` exits 0
- `node tests/unit/dispatcher.test.js` exits 0 (no regression)
- `node tests/unit/modifier.test.js` exits 0 (no regression)
- Neither .ojo contains the string `name of it = name of it`
- Neither .ojo gained ES6 syntax: grep for `=>`, backtick, `const `, `let ` in
  the changed regions returns nothing new
- Both .ojo files' existing fixlet tuple relevance strings are unchanged in
  `git diff`
- Human checkpoint approved
</verification>

<success_criteria>
- Both grids show a rightmost "Open Deployments" column with a per-fixlet count
- Grid count equals the dispatcher detail panel's open-action count for the same
  fixlet
- Distinct fixlets show distinct counts (no uniform-count regression)
- Header click sorts numerically in both files
- Grid load performs exactly two relevance evaluations regardless of row count
- Roles column logic untouched in both files
- All unit tests green
</success_criteria>

<output>
Create `.planning/quick/260811-fjc-add-an-open-deployments-count-column-to-/260811-fjc-SUMMARY.md` when done
</output>
