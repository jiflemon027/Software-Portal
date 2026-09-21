# Deferred Items — Phase 07 Automation

Out-of-scope issues discovered during plan execution but not fixed, per the executor's
scope-boundary rule ("only auto-fix issues DIRECTLY caused by the current task's changes").

## 2026-09-21 — Plan 07-02 (Task 787 Reconcile-LocalRoles strip)

Full-estate run (`Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI`) surfaced 11 failures
in `tests/pester/Upsert-RolePublish.Tests.ps1` and 1 `NotRun` in
`tests/pester/Import-AxoniousExport.Tests.ps1`, all pre-existing and unrelated to the 07-02
Task 1 `.bes` diff (confirmed by running `Upsert-RolePublish.Tests.ps1` in isolation with the
07-02 commits present — same failures reproduce; the file touches neither task 787's `.bes` nor
`scripts/Reconcile-LocalRoles.ps1`).

- **`Upsert-RolePublish.ps1 - schema and writes.*`** (10 failures) + **`Upsert-RolePublish.ps1 -
  source guarantees.contains no dynamic type loading...`** (1 failure) — every DB-backed test in
  this suite fails with `sqlite3.exe failed (exit=1): Parse error near line 3: no such table:
  RoleUsers`. The DDL/schema wiring in `scripts/Upsert-RolePublish.ps1` (07-03 Root-Server Audit
  Store plan, commits `f86db89`/`6476860`) appears to not create the `RoleUsers` table the test
  fixture expects, or the fixture/test setup has drifted from the script's actual DDL. Needs
  investigation under a 07-03 follow-up or the relevant future plan in the new 12-plan
  structure — not touched by this plan.
- **`Import-AxoniousExport.ps1 - runtime.A7 runtime profile against the full anonymised
  export.ingests the full export and records a wall-clock time`** — reports `NotRun` (not
  `Skipped`) under `-ExcludeTag Slow`. Likely a tag-scoping mismatch (e.g. the tag is applied at
  a nested `Context`/`It` level Pester's discovery doesn't propagate the same way `Describe`-level
  tags do) rather than a real functional bug. Also unrelated to 07-02; not investigated further.

Both are inherited from prior-wave work (07-01/07-03) and predate this plan's execution.
