---
phase: 04-role-assigner
fixed_at: 2026-06-28T00:00:00Z
review_path: .planning/phases/04-role-assigner/04-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 4: Code Review Fix Report

**Fixed at:** 2026-06-28T00:00:00Z
**Source review:** .planning/phases/04-role-assigner/04-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (4 Critical, 5 Warning)
- Fixed: 9
- Skipped: 0

## Fixed Issues

### CR-01: Block blank role in validateRows

**Files modified:** `Existing Dashboards/fixlet_role_assigner.ojo`, `tests/unit/role_assigner.test.js`
**Commit:** 18a2f0c
**Applied fix:** Changed the role validation condition from `if (row.role && ...)` to a two-branch check that explicitly pushes `{ field: 'role', msg: 'Role is blank' }` when `!row.role`, and falls through to the unknown-role check otherwise. Applied to both the OJO dashboard file and the identical copy in the test file.

---

### CR-02/CR-04: Remove xmlEscape from ActionScript parameter "Role"

**Files modified:** `Existing Dashboards/fixlet_role_assigner.ojo`
**Commit:** 9565343
**Applied fix:** Removed `xmlEscape()` wrapper from the `parameter "Role"` ActionScript line in `buildAssignActionScript`. The role value is already validated against `PORTAL_CONFIG.roles` at lines 397 and 450 (allowlist gate), so no escaping is needed. Using `xmlEscape` was architecturally wrong: ActionScript parameter values are plain string literals, not XML text nodes, so XML entity encoding corrupted role names containing `&`, `<`, `>`, `"`, or `'` when stored and retrieved by the BigFix agent.

---

### CR-03: Add blank-role fixture and test

**Files modified:** `tests/fixtures/phase-04/invalid-blank-role.csv` (new), `tests/unit/role_assigner.test.js`
**Commit:** f65a089
**Applied fix:** Created `tests/fixtures/phase-04/invalid-blank-role.csv` (CRLF line endings, consistent with other phase-04 fixtures) containing a single data row with a blank role field. Added a `validateRows: blank role produces BLOCK error with field=role` test case in the validateRows section of the unit test file. The new test reads the fixture via `fs.readFileSync`, parses it, validates against `PORTAL_CONFIG.roles`, and asserts that at least one error with `field === 'role'` is present. Test count advanced from 31 to 32.

---

### WR-01: Remove dead psChunkArgs variable

**Files modified:** `Existing Dashboards/fixlet_role_assigner.ojo`
**Commit:** e688cd7
**Applied fix:** Removed the `var psChunkArgs = "";` declaration and the `psChunkArgs += ' -chunk' + ci + ...` accumulation line from the loop inside `buildAssignActionScript`. The `psChunkArgs` variable was built but never referenced — the `waithidden` line builds its chunk arguments inline via a separate loop (`ci2`). Removing the dead variable eliminates the misleading suggestion that two parallel code paths exist for building the args.

---

### WR-02: Sanitise suffix — cap length and strip CRLF

**Files modified:** `Existing Dashboards/fixlet_role_assigner.ojo`
**Commit:** 42346ba
**Applied fix:** Added three sanitisation lines after the existing suffix fallback chain in `deployAll()`: (1) truncate to 60 characters if longer, (2) replace `\r`, `\n`, and `\t` with spaces and trim, (3) fall back to `'Import'` if the result is empty after trimming. This prevents pathological group names from producing oversized or control-character-containing BigFix action titles.

---

### WR-03: Strip RFC 4180 quoted fields in parseCsv

**Files modified:** `Existing Dashboards/fixlet_role_assigner.ojo`, `tests/unit/role_assigner.test.js`
**Commit:** 4b90789
**Applied fix:** Added a `parts.map()` call immediately after `line.split(',')` in `parseCsv` (in both the OJO dashboard and the test file's identical copy). The map strips surrounding double-quotes from each field value and unescapes `""` to `"` per RFC 4180. Fields without surrounding quotes are returned unchanged (after `.trim()`). This allows Excel-exported CSVs with quoted fields (e.g. `"Finance, North"`) to parse correctly instead of silently corrupting subsequent columns.

---

### WR-04: Remove ActiveXObject from Node.js parseActionId

**Files modified:** `tests/integration/role_assigner.integration.test.js`
**Commit:** 7f184ba
**Applied fix:** Replaced the full `parseActionId` function (which contained a `try { new ActiveXObject(...) } catch {}` block that always silently throws a `ReferenceError` in Node.js) with the regex-only version. The replacement uses two regex patterns: `/\/api\/action\/(\d+)/i` and `/<ID>(\d+)<\/ID>/i`. The function comment now explicitly notes that `ActiveXObject` is unavailable in Node.js and why it was removed.

---

### WR-05: Use SQLite || concatenation instead of concat() in BES Analysis

**Files modified:** `Dashboard_4_samples/Dereso SWD.bes`
**Commit:** e24f9f8
**Applied fix:** Changed Property ID 3 (`mapped_users in r.db`) SQL from `select concat (UserID,', ', Role) from  map where Active  = 1` to `select UserID || ', ' || Role from map where Active = 1`. SQLite does not implement `concat()` — it uses the `||` operator for string concatenation. The prior query would raise a SQL error at evaluation time, causing the Analysis property to fail silently (BigFix reports an error state, the dashboard `loadAnalysisView()` shows "Analysis not available").

---

## Skipped Issues

None — all in-scope findings were fixed.

---

_Fixed: 2026-06-28T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
