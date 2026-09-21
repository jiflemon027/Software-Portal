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

- **RESOLVED 2026-09-21** — **`Upsert-RolePublish.ps1 - schema and writes.*`** (10 failures) +
  **`Upsert-RolePublish.ps1 - source guarantees.contains no dynamic type loading...`** (1
  failure). Two independent root causes, both fixed directly on the orchestrator's main tree
  (not a subagent — contained, well-understood fix) and verified via full reproduction:
  1. **Real bug in the script**: PS 5.1's `ConvertFrom-Json` collapses a single-element JSON
     array (`"users":["alice"]`) to a bare scalar, identical to a genuine invalid scalar
     payload (`"users":"alice"`). The array-type check in `Upsert-RolePublish.ps1` rejected
     every single-user Publish with exit 5410 before ever creating the schema — hence the
     cascading "no such table: RoleUsers"/"RolePublishRun" errors in later tests. Fixed by
     falling back to a raw-JSON-text check (`"users"\s*:\s*\[`) only in the ambiguous scalar
     case, preserving the existing rejection of genuine string payloads.
  2. **Test bug, not a script bug**: the source-guarantees test's comment-stripping only
     handled `#`-prefixed line comments, not the script's `<# ... #>` block comment (its
     comment-based help), so the doc comment's own sentence "no System.Data.SQLite" tripped
     the negative-match assertion it was explicitly designed to survive. Fixed the test's
     stripping regex to also remove `<# ... #>` blocks.
  Full-estate regression (`Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI`): 285
  passed / 0 failed / 1 NotRun (the second item below, unchanged).
- **`Import-AxoniousExport.ps1 - runtime.A7 runtime profile against the full anonymised
  export.ingests the full export and records a wall-clock time`** — reports `NotRun` (not
  `Skipped`) under `-ExcludeTag Slow`. Likely a tag-scoping mismatch (e.g. the tag is applied at
  a nested `Context`/`It` level Pester's discovery doesn't propagate the same way `Describe`-level
  tags do) rather than a real functional bug. Also unrelated to 07-02; not investigated further.

Both are inherited from prior-wave work (07-01/07-03) and predate this plan's execution.
