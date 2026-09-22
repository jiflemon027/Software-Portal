---
phase: 07-automation
plan: 06
subsystem: ui
tags: [bigfix, ojo, relevance, actionscript, bes-xml, singleaction, sqlite, ie9, json]

# Dependency graph
requires:
  - phase: 07-automation (plan 07-04)
    provides: "fixlet_role_manager.ojo shell + PORTAL_CONFIG + buildRoleGroupRelevance/buildComputerGroupXml/buildRolePolicyTaskXml/buildRolePolicyActionXml/findBesObjectIdByTitle, and tests/unit/role_manager.test.js's 30-assertion baseline"
  - phase: 07-automation (plan 07-05)
    provides: "scripts/Upsert-RolePublish.ps1 (the D-07 audit-write script this plan mirrors byte-for-byte) and tests/fixtures/phase-07/role-group-relevance.golden.txt (the cross-language relevance contract this plan's Node suite also asserts against)"
provides:
  - "Roles tab UI: per-role username editor, D-02 autocomplete, D-10 scope selector, Save/Publish buttons (Publish is a 07-07 stub)"
  - "roleState/roleBySlug/knownUsers module state + getRoleUsers/setRoleUsers/renderRolePanel/loadKnownUsers/suggestUsernames (the fixed interface 07-07/07-08 build on)"
  - "buildRolePublishPayload/buildAuditWriteActionScript/buildAuditWriteActionXml/saveRole -- D-13 step 1 (Save writes the RolePublishRun/RoleUsers audit row via a root-server ComputerID-targeted SingleAction, touches no BES object)"
  - "ROLE_PUBLISH_SCRIPT_LINES -- byte-identical, CI-pinned mirror of scripts/Upsert-RolePublish.ps1"
  - "tests/unit/role_manager.test.js extended to 59 assertions (30 -> 59), including the mirror-fidelity and cross-language golden-fixture checks"
affects: ["07-07 (per-role Publish flow reads getRoleUsers()/roleState, must not add a second audit write)", "07-08 (Analysis tab)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Slug-only inline event handlers: every onclick/onkeyup attribute in the Roles tab passes only roleSlug(role) (matches /^[A-Za-z0-9_]*$/, cannot break out of an HTML attribute or JS string literal); the handler resolves slug -> role via roleBySlug before touching state. Username values are NEVER embedded in inline attribute strings -- Remove-button and suggestion-row handlers are always bound via DOM closures (element.onclick = function(){...}) instead."
    - "innerText/DOM-property assignment for pure user-controlled text nodes (username table cells, suggestion rows) instead of htmlEscape+innerHTML -- matches fixlet_dispatcher.ojo's renderGroupSelect precedent (opt.text = ...) and is structurally immune to HTML injection since no string is ever HTML-parsed. htmlEscape+innerHTML is still used for the one config-trusted value rendered that way (the role heading)."
    - "Generate-then-paste for a large embedded-script mirror: ROLE_PUBLISH_SCRIPT_LINES was produced by a one-off Node generator script (never hand-typed) from scripts/Upsert-RolePublish.ps1, then round-trip-verified before pasting -- avoids the transcription-error risk of manually copying a 300-line file into a JS array literal."

key-files:
  created: []
  modified:
    - "Existing Dashboards/fixlet_role_manager.ojo"
    - "tests/unit/role_manager.test.js"

key-decisions:
  - "D-10 scope-group resolution: onScopeChange resolves the selected target-group NAME to a BES group ID via findBesObjectIdByTitle at selection time (not deferred to Publish), storing the resolved id in roleState[role].scopeGroupId/scopeSiteName. If resolution fails, a non-blocking status message is shown -- Save itself never depends on scope resolution succeeding, only Publish (07-07) will."
  - "D-02 known-users cache is a case-insensitive, alphabetically-sorted array populated once in initDashboard() by loadKnownUsers(); suggestUsernames() re-sorts its own matches independently (does not rely on cache order) so it behaves correctly even against an out-of-order cache (verified by the Task 3 unit test, which seeds the cache unsorted)."
  - "getRoleUsers/setRoleUsers/suggestUsernames are pure enough to unit-test directly under Node by stubbing renderRolePanel as a no-op in the test file's extracted twin -- the one DOM side effect setRoleUsers has."
  - "ROLE_PUBLISH_SCRIPT_LINES's mirror-fidelity test extracts the array literal from the .ojo source via eval() of the literal text (never a second hand-copy in the test file) -- a ~300-line hand-duplicated string would itself be a drift risk this plan is specifically trying to eliminate for the .ojo's own copy."
  - "Added a T-07-06-01 threat-model assertion (a username containing the literal _EOF_ cannot terminate the createfile block early) that the plan's threat register named explicitly but the Task 3 action-block checklist omitted -- added per Rule 2 after the initial Task 3 commit; see Deviations."

patterns-established:
  - "Slug-only inline handlers + DOM-closure-bound handlers for any user-controlled value, established here for future BigFix .ojo dashboards in this family that render per-item Remove/Edit controls over user-supplied text."

requirements-completed: [FR-02, NFR-03, NFR-04, NFR-05]

# Metrics
duration: ~19min
completed: 2026-09-22
---

# Phase 07 Plan 06: Roles Tab UI + D-13 Save (Audit-Store Write) Summary

**Roles tab with per-role username editor, D-02 autocomplete, and D-13 step-1 Save that stages a role's full username snapshot into the root-server RolePublish.db audit store via a ComputerID-targeted SingleAction carrying a byte-identical embedded mirror of `Upsert-RolePublish.ps1` -- touches zero BES objects.**

## Performance

- **Duration:** ~19 min
- **Completed:** 2026-09-22T21:02:52Z
- **Tasks:** 3/3 (+ 1 deviation fix)
- **Files modified:** 2

## Accomplishments

- `Existing Dashboards/fixlet_role_manager.ojo`'s `tabRoles` panel is now a working per-role editor: username table with Remove buttons, an Add-username input with D-02 autocomplete (onkeyup, IE9-safe, degrades to a visible "Analysis not reporting yet" hint with freeform entry still working), a D-10 optional scope-to-group selector, and Save/Publish buttons. Every element id is derived from a sanitized `roleSlug`; every inline event-handler attribute passes only that slug, never raw role or username text -- Remove-button and suggestion-row click handlers are bound via DOM closures instead, so a username containing a quote/ampersand/brace cannot corrupt the DOM.
- `saveRole(role)` implements D-13 step 1 exactly: builds the 07-03 JSON payload (`buildRolePublishPayload`, hand-rolled JSON escaper since IE9 has no reliable `JSON.stringify` in this host), embeds it plus a byte-identical mirror of `scripts/Upsert-RolePublish.ps1` (`ROLE_PUBLISH_SCRIPT_LINES`) into a two-`createfile`-block ActionScript (`buildAuditWriteActionScript`), and POSTs a `ComputerID`-targeted `SingleAction` (`buildAuditWriteActionXml`, `<Target>` after `<Settings>`, `IsOffer=false`) to the root server. Grep-verified: `saveRole`'s body contains zero references to `computergroup`/`fixlets?/custom` -- it never touches a live BES object.
- `tests/unit/role_manager.test.js` grew from 30 to 59 assertions: mirror-fidelity (extracts `ROLE_PUBLISH_SCRIPT_LINES` from the `.ojo` source itself via `eval()` of the literal, asserts it round-trips byte-identically to `scripts/Upsert-RolePublish.ps1` -- spot-checked that a one-space mutation to that file fails the suite, then restored), the cross-language relevance contract (reads `tests/fixtures/phase-07/role-group-relevance.golden.txt` from disk, asserts `buildRoleGroupRelevance` reproduces all three golden lines -- spot-checked that mutating the fixture fails the suite, then restored), payload/action-script/action-xml coverage including brace-doubling and byte-identity of the `parameter "SWPDir"=` line against `bes/Assign-RoleMapping.bes`, and `getRoleUsers`/`setRoleUsers`/`suggestUsernames` behavior (case-insensitive dedup, D-04 cross-role independence, prefix-match sort/cap).
- Full regression: all 10 `tests/unit/*.test.js` suites green, `Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI` reports 317 passed / 0 failed / 1 pre-existing unrelated NotRun, `fixlet_role_manager.ojo` still casts cleanly to `[xml]`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Roles tab UI, role state, and D-02 autocomplete** - `ea50593` (feat)
2. **Task 2: Audit-store Save via a root-server SingleAction** - `16020bb` (feat)
3. **Task 3: Extend tests/unit/role_manager.test.js** - `c4f0913` (test)
4. **Deviation fix: T-07-06-01 _EOF_-in-username threat-model assertion** - `f4094bd` (test)

**Plan metadata:** (this commit) `docs: complete 07-06 plan`

## Files Created/Modified

- `Existing Dashboards/fixlet_role_manager.ojo` - Roles tab UI (username editor, autocomplete, scope selector, Save/Publish buttons) + D-07 audit-write builders (`buildRolePublishPayload`, `buildAuditWriteActionScript`, `buildAuditWriteActionXml`, `saveRole`) + `ROLE_PUBLISH_SCRIPT_LINES` mirror (830 lines added across Tasks 1-2)
- `tests/unit/role_manager.test.js` - 29 new assertions (30 -> 59): mirror fidelity, cross-language golden-fixture contract, payload/action-script/action-xml coverage, role-state function coverage, plus the T-07-06-01 deviation-fix assertion

## Decisions Made

See `key-decisions` in frontmatter. Summary:
- D-10 scope-group name-to-ID resolution happens at selection time (`onScopeChange`), not deferred to Publish.
- `suggestUsernames` re-sorts its own filtered matches rather than trusting cache order, so it stays correct even if `knownUsers` is ever populated out of order.
- `ROLE_PUBLISH_SCRIPT_LINES` was generated by a one-off Node script from `scripts/Upsert-RolePublish.ps1` (never hand-typed), then round-trip-verified before pasting into the `.ojo` file -- and the Task 3 mirror-fidelity test extracts it back out of the `.ojo` source (via `eval()` of the literal) rather than hard-copying it a second time into the test file.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added the T-07-06-01 `_EOF_`-in-username threat-model assertion**
- **Found during:** Post-Task-3 review of the plan's `<threat_model>` register against what Task 3's own `<action>` checklist actually enumerated.
- **Issue:** The threat register's mitigation text for T-07-06-01 explicitly says "assert this case explicitly in the payload round-trip test" (a username containing the literal `_EOF_` must not be able to terminate the `createfile` block early), but Task 3's action-block bullet list never named this specific assertion, so the initial Task 3 commit shipped without it.
- **Fix:** Added two assertions: (1) a username containing `_EOF_` round-trips unchanged through `JSON.parse` (confirms it stays JSON data, not raw text), and (2) `buildAuditWriteActionScript`'s output still contains exactly two lines that are bare `_EOF_` (the two real terminators) when fed a payload containing that username -- proving the payload's single-line JSON encoding can never produce a spurious third terminator.
- **Files modified:** `tests/unit/role_manager.test.js`
- **Verification:** Both assertions pass against the current implementation (no code change to `fixlet_role_manager.ojo` was needed -- the existing design was already safe, this closes a test-coverage gap named by the threat model).
- **Committed in:** `f4094bd`

---

**Total deviations:** 1 auto-fixed (1 missing critical test, Rule 2)
**Impact on plan:** No functional code changed -- this closes a coverage gap the threat model explicitly named but the task action-block prose omitted. No scope creep.

## Issues Encountered

Two acceptance-criteria greps in the plan text are stricter than the pre-existing 07-04 baseline can literally satisfy, both discovered during Task 1/verification and left as documented caveats rather than "fixed" (fixing either would mean editing out-of-scope 07-04 content):

- **`grep -c 'users in r\.db'` was specified to return exactly 1**, but `PORTAL_CONFIG.props.mappedUsers` (`"mapped_users in r.db"`, added in 07-04) already substring-matches that pattern, so the baseline count was 2 before this plan touched anything. This plan's own new code references the property only via `PORTAL_CONFIG.props.knownUsers` (no second literal), so the count is unchanged by this plan (verified: still 2, not increased).
- **`grep -c 'logged on users whose' tests/unit/role_manager.test.js` was specified to return 0 outside the extracted `buildRoleGroupRelevance` stub**, but three pre-existing 07-04 assertions (added in plan 07-04, testing `buildRoleGroupRelevance`'s own dedup/escaping behavior) already hardcode the full relevance string and were not touched here (out of scope for this plan). This plan's own new golden-fixture assertions read `tests/fixtures/phase-07/role-group-relevance.golden.txt` from disk via `fs.readFileSync` and never hardcode a golden line (verified via the spot-check: mutating the fixture fails the suite).

## Known Stubs

- The Publish button (`onPublishRoleClick`) is an intentional 07-07 stub per this plan's own scope: it calls `setStatus("Publish is wired in 07-07")` and does nothing else. The DOM contract (`id="publishRole_" + slug`) exists for 07-07 to bind to.
- `tabAnalysis` is still the plan-07-04 placeholder (`built in plan 07-08`) -- unchanged, out of this plan's scope.

## User Setup Required

None - no external service configuration required. No live BigFix console verification was performed this session (this plan adds a `POST actions` call for the first time in this dashboard, but exercising it live requires a running console against a real root server, which is a later-plan/production-verification concern per this project's established pattern -- see 07-01's live spike and 07-12's planned production checkpoint). All new code is covered by the Node unit suite and the `[xml]` cast check.

## Next Phase Readiness

- Plan 07-07 (per-role Publish) can call `getRoleUsers(role)` / read `roleState[role]` directly by the interface this plan pins, and must build its own Computer Group + policy-action REST calls without adding a second `RolePublish.db` write -- Save (this plan) already owns that write, per the plan's own D-13-over-D-07 resolution.
- Plan 07-08 (Analysis tab) has no new dependency from this plan beyond the existing `PORTAL_CONFIG.props`/`getRelevanceSafe` helpers already present since 07-04.
- No blockers. `fixlet_role_manager.ojo` has not yet been opened in a live BigFix console this session (no UI content existed to verify before this plan) -- that verification is expected to happen naturally once 07-07 completes the Publish flow and the Roles tab becomes fully exercisable end-to-end.

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: `Existing Dashboards/fixlet_role_manager.ojo`
- FOUND: `tests/unit/role_manager.test.js`
- FOUND: `.planning/phases/07-automation/07-06-SUMMARY.md`
- FOUND commit: `ea50593` (Task 1)
- FOUND commit: `16020bb` (Task 2)
- FOUND commit: `c4f0913` (Task 3)
- FOUND commit: `f4094bd` (deviation fix)
