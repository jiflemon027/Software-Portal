---
phase: 07-automation
plan: 07
subsystem: ui
tags: [bigfix, ojo, relevance, actionscript, bes-xml, singleaction, prefetch, sha1, task, ie9]

# Dependency graph
requires:
  - phase: 07-automation (plan 07-04)
    provides: "fixlet_role_manager.ojo shell + PORTAL_CONFIG + buildRolePolicyTaskXml/buildRolePolicyActionXml/findBesObjectIdByTitle, and tests/unit/role_manager.test.js's 30-assertion baseline"
  - phase: 07-automation (plan 07-06)
    provides: "Roles tab UI, roleState/getRoleUsers/setRoleUsers interface, and the D-13-over-D-07 resolution that Save (not Publish) owns the one RolePublish.db write -- this plan must not add a second write"
provides:
  - "ASSIGN_ROLE_MAPPING_SCRIPT_LINES/ASSIGN_ROLE_MAPPING_SCRIPT: byte-identical, SHA1-pinned, LF-joined mirror of scripts/Assign-RoleMapping.ps1"
  - "buildEndpointScriptStagingActionXml/stageEndpointScript: ComputerID-targeted SingleAction + Prerequisites-panel UI that places the mirror at Uploads\\CustomRepository\\SoftwarePortal\\rolegroups\\Assign-RoleMapping.ps1 on the root server"
  - "ASSIGN_ROLE_TEMPLATE: literal, programmatically-extracted mirror of every field bes/Assign-RoleMapping.bes carries"
  - "ensureRoleTask(role, onDone): per-role Task find-or-create -- POST fixlets/custom/ on create, PUT fixlet/custom/<id> on update, onDone({taskId, taskFields, actionScript, relevance})"
  - "parseCreatedId: Task/Fixlet creation-response ID parser (mirrored from fixlet_copier.ojo), filling a gap the plan's own text miscited as parseActionId"
  - "tests/unit/role_manager.test.js extended to 87 assertions (59 -> 87): SHA1/SHA256/size prefetch-pin verification, bes-file-independent template-fidelity extraction, real-template Task-build coverage"
affects: ["07-08 (publishRole() calls ensureRoleTask() directly; Publish button itself remains a 07-08 stub, unchanged here)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generate-then-splice for large embedded-content additions: both ASSIGN_ROLE_MAPPING_SCRIPT_LINES (208-line PS1 mirror) and ASSIGN_ROLE_TEMPLATE (bes-file field mirror) were produced by one-off Node generator scripts that read the source file directly and emit ready-to-paste JS literal text, round-trip-verified (SHA1-compared, and for the template, re-extracted and diffed against the same regex logic the test suite uses independently) before insertion -- never hand-transcribed. The splice into fixlet_role_manager.ojo itself was also done via a verified Node script (anchor-text match + insertion), not manual Edit-tool retyping, to eliminate transcription risk in BigFix ActionScript's brace/quote-heavy syntax."
    - "Task-1/Task-2 atomic-commit split from a combined splice: because both tasks' code was generated and inserted in a single pass, a second small script re-derived a 'Task-1-only' intermediate .ojo (Task 2's contiguous block removed) so the two tasks could still be committed separately and atomically, each independently verified ([xml] cast + JS syntax) before its commit."

key-files:
  created: []
  modified:
    - "Existing Dashboards/fixlet_role_manager.ojo"
    - "tests/unit/role_manager.test.js"

key-decisions:
  - "Joiner convention differs per mirrored script, and must: scripts/Assign-RoleMapping.ps1 is LF-only (verified via byte scan -- 0 CRLF, 207 LF), so ASSIGN_ROLE_MAPPING_SCRIPT_LINES joins with a bare '\\n', NOT the '\\r\\n' ROLE_PUBLISH_SCRIPT (07-06, CRLF source) uses. Using the wrong joiner would silently break the SHA1 pin. Round-trip-verified: SHA1 of the joined string equals the pinned 69860a1239e4509dce483a07523ea07e26764279 before the array was ever pasted into the .ojo."
  - "DEVIATION (Rule 1 -- plan-text bug, corrected against the authoritative source): the plan's <interfaces>/acceptance criteria assumed bes/Assign-RoleMapping.bes's ActionScript carries a literal __USERNAME__ placeholder token that must survive unsubstituted. Grep-verified against the real file: no such token exists anywhere in the ActionScript. The endpoint's -UserName argument is instead bound directly to client relevance, parameter \"UserName\"=\"{name of current user as lowercase}\", resolved fresh on each endpoint when the action runs -- a strictly SAFER property than a token (there is no placeholder to ever leave substituted with a fixed username). ASSIGN_ROLE_TEMPLATE mirrors the real file byte-for-byte (not the plan's assumed shape); tests assert the client-relevance expression -- not __USERNAME__ -- survives untouched through buildRolePolicyTaskXml."
  - "DEVIATION (Rule 3 -- blocking bug in the plan's own text): the plan named parseActionId for extracting the new Task's ID after ensureRoleTask's POST-create path. parseActionId hunts for an <Action> XML element and is this codebase's established parser for BES Action creation responses (used correctly by stageEndpointScript here, which really does create an Action) -- it is the wrong parser for a Task/Fixlet creation response, which this codebase already has a distinct, established helper for (parseCreatedId, present verbatim in fixlet_copier.ojo/fixlet_console.ojo/fixlet_update_tracker.ojo). Added parseCreatedId verbatim rather than reusing parseActionId incorrectly."
  - "Task 1 and Task 2 were authored together in one generator/splice pass (both blocks depend on the same generate-then-splice tooling built for this plan), then mechanically re-split into two atomic commits via a second script that removed Task 2's contiguous block to reconstruct a valid, independently-verified Task-1-only intermediate state -- chosen over committing them together, to preserve the plan's one-task-one-commit contract without hand-editing a second time (which would reintroduce the transcription risk the generate-then-splice approach exists to avoid)."

patterns-established:
  - "Regex-based bes-file field extraction independent of the .ojo's own copy, established here for both the template generator AND the test suite (written independently, not sharing code) -- so a bug in one extraction path can't hide inside the other's blind spot. Reusable for any future plan that needs to mirror another bes/Fixlet template's fields into a dashboard."

requirements-completed: [FR-02, FR-03, NFR-02]

# Metrics
duration: ~45min
completed: 2026-09-22
---

# Phase 07 Plan 07: Publish Prerequisites (Endpoint-Script Staging + Per-Role Task) Summary

**SHA1-pinned staging of `Assign-RoleMapping.ps1` into the root server's Custom Repository via a ComputerID-targeted SingleAction, plus `ensureRoleTask()` -- a from-scratch, find-or-create per-role Task builder whose callback (`taskId`/`actionScript`/`relevance`) is the fixed interface plan 07-08's action deploy consumes directly.**

## Performance

- **Duration:** ~45 min
- **Completed:** 2026-09-22T21:25:27Z
- **Tasks:** 3/3
- **Files modified:** 2

## Accomplishments

- `Existing Dashboards/fixlet_role_manager.ojo`'s Roles tab gained a "Prerequisites" panel above the per-role panels: a one-line explanation, the pinned SHA1 (`69860a1239e4509dce483a07523ea07e26764279`) and size (`8877` bytes) as literal text, a "Stage endpoint script on root server" button, and dedicated result/error elements (no popup dialogs). `buildEndpointScriptStagingActionXml()` emits a `ComputerID`-targeted `SingleAction` (`Title -> Relevance -> ActionScript -> Settings -> Target`, `<IsOffer>false</IsOffer>`) whose ActionScript resolves the Custom Repository root from the `wwwRootFolder` registry value (no operator input reaches the destination path -- T-07-07-03), `createfile`-embeds the byte-identical `ASSIGN_ROLE_MAPPING_SCRIPT` mirror (one `createfile until _EOF_` / one `move __createfile`), and lands it at `Uploads\CustomRepository\SoftwarePortal\rolegroups\Assign-RoleMapping.ps1` -- the exact path `bes/Assign-RoleMapping.bes`'s prefetch block pins.
- `ASSIGN_ROLE_MAPPING_SCRIPT_LINES` is a 208-line, generator-produced, round-trip-verified mirror of `scripts/Assign-RoleMapping.ps1`, joined with `'\n'` (the file is LF-only -- confirmed by byte scan, unlike `ROLE_PUBLISH_SCRIPT`'s CRLF source from 07-06). SHA1 of the joined mirror equals the pinned `69860a1239e4509dce483a07523ea07e26764279` both at generation time and via the Task 3 unit assertion.
- `ASSIGN_ROLE_TEMPLATE` is a literal, programmatically-extracted mirror of every field `bes/Assign-RoleMapping.bes` carries (title, description, both `<Relevance>` bodies, category/source/sourceId/sourceReleaseDate/sourceSeverity/cveNames/sansId, the one MIMEField, domain, action description pre/link/postLink, and the full `<DefaultAction>` `<ActionScript>` CDATA) -- extracted via a standalone regex-based generator, independently re-verified byte-for-byte by the test suite's own separate regex extraction. `ensureRoleTask(role, onDone)` builds a from-scratch Task document via `buildRolePolicyTaskXml` (never mutates a fetched DOM -- T-07-07-04), POSTs `fixlets/custom/<site>` (plural) on create or PUTs `fixlet/custom/<site>/<id>` (singular) on update -- re-PUT unconditionally on every Publish so `__ASSIGNED_BY__` always reflects the current publisher (T-07-07-06) -- and calls back with `{ taskId, taskFields, actionScript, relevance }`, where `relevance` is both template `<Relevance>` bodies substituted and ANDed per SKILL.md S3.
- `tests/unit/role_manager.test.js` grew from 59 to 87 assertions: the endpoint-script SHA1/SHA256/size prefetch-pin verification (computes the real hash of `scripts/Assign-RoleMapping.ps1`, compares against tokens regex-parsed from `bes/Assign-RoleMapping.bes`'s prefetch line, and separately against the dashboard's own mirror -- spot-check confirmed a one-byte mutation to the `.ps1` fails the suite with the required "re-pin sha1/size/sha256" message, then restored, verified byte-identical to HEAD via `git diff`), the bes-file-independent `ASSIGN_ROLE_TEMPLATE` fidelity checks, real-template `buildRolePolicyTaskXml` coverage, and `buildEndpointScriptStagingActionXml` coverage (Settings-before-Target, `ComputerID` not `CustomRelevance`, brace-doubling against the real script's own braces, empty-`rootServerComputerId` guard).
- Full regression: all 10 `tests/unit/*.test.js` suites green (role_manager.test.js: 87/87), `Invoke-Pester -Path tests/pester -ExcludeTag Slow -CI` (run under `pwsh`, which carries Pester 5.7.1 -- the environment's default `powershell.exe` only has the built-in Pester 3.4.0 and cannot run this repo's `BeforeDiscovery`-based Pester 5 suites) reports 317 passed / 0 failed / 1 pre-existing unrelated NotRun, matching the 07-06 baseline exactly (no PowerShell files touched by this plan). `fixlet_role_manager.ojo` still casts cleanly to `[xml]`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Stage the endpoint script into the root server's Custom Repository** - `05bd97d` (feat)
2. **Task 2: Per-role Task find-or-create** - `001d91e` (feat)
3. **Task 3: SHA1 pin and template-fidelity unit coverage** - `b442710` (test)

**Plan metadata:** (this commit) `docs: complete 07-07 plan`

## Files Created/Modified

- `Existing Dashboards/fixlet_role_manager.ojo` - Publish Prerequisites section (`ASSIGN_ROLE_MAPPING_SCRIPT_LINES`/`SCRIPT`, `buildEndpointScriptStagingActionXml`, `stageEndpointScript`, `onStageEndpointScriptClick`, `updateStageEndpointScriptUI`, `ASSIGN_ROLE_TEMPLATE`, `parseCreatedId`, `ensureRoleTask`) inserted between `findBesObjectIdByTitle` and the Roles Tab section; Prerequisites UI panel added above `rolePanelsContainer`; `initDashboard()` now calls `updateStageEndpointScriptUI()` (578 lines added across Tasks 1-2)
- `tests/unit/role_manager.test.js` - 28 new assertions (59 -> 87): SHA1/SHA256/size pin verification, `ASSIGN_ROLE_MAPPING_SCRIPT_LINES` mirror fidelity, `ASSIGN_ROLE_TEMPLATE` fidelity against an independent bes-file regex extraction, real-template `buildRolePolicyTaskXml` coverage, `buildEndpointScriptStagingActionXml` coverage, source-level Task 1/2 assertions

## Decisions Made

See `key-decisions` in frontmatter. Summary:
- `ASSIGN_ROLE_MAPPING_SCRIPT_LINES` joins with `'\n'` (LF-only source), not the `'\r\n'` 07-06's `ROLE_PUBLISH_SCRIPT` uses (CRLF source) -- getting this wrong would silently break the SHA1 pin.
- Two deviations from the plan's own text, both corrected against the authoritative `bes/Assign-RoleMapping.bes` / this codebase's established conventions rather than followed literally -- see Deviations below.
- Task 1 and Task 2 were generated together but mechanically re-split into two atomic, independently-verified commits.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in plan text] `__USERNAME__` token does not exist in the real template**
- **Found during:** Task 2, while extracting `ASSIGN_ROLE_TEMPLATE`'s `actionScript` field from `bes/Assign-RoleMapping.bes`.
- **Issue:** The plan's `<interfaces>` and Task 2/3 acceptance criteria assume the real template's ActionScript contains a literal `__USERNAME__` placeholder token that must survive substitution unsubstituted (e.g. "at least one remaining `__USERNAME__`"). Grep-verified against the actual file: no such token exists anywhere in `bes/Assign-RoleMapping.bes`'s `<DefaultAction><ActionScript>` CDATA. The `-UserName` argument is instead bound directly to client relevance: `parameter "UserName"="{name of current user as lowercase}"`, resolved on each endpoint when the action runs.
- **Fix:** `ASSIGN_ROLE_TEMPLATE.actionScript` mirrors the real file byte-for-byte (proven by an independent regex extraction in the test suite, not shared code with the generator). Task 2/3 acceptance criteria assertions about `__USERNAME__` were reinterpreted as assertions that `{name of current user as lowercase}` -- the actual identity-resolution mechanism -- survives `buildRolePolicyTaskXml` untouched. This is a strictly safer property than what the plan assumed: there is no placeholder token to ever accidentally leave substituted with a fixed username, so T-07-07-05 (Elevation of Privilege) is mitigated by construction rather than by a `.replace()` exclusion.
- **Files modified:** `Existing Dashboards/fixlet_role_manager.ojo`, `tests/unit/role_manager.test.js`
- **Verification:** `node tests/unit/role_manager.test.js` asserts `bes/Assign-RoleMapping.bes`'s ActionScript has zero `__USERNAME__` occurrences (with a note to revisit this deviation if that ever changes) and that the client-relevance expression is present in both the raw bes file and the emitted Task XML.
- **Committed in:** `001d91e` (Task 2), `b442710` (Task 3 tests)

**2. [Rule 3 - Blocking bug in plan text] `parseActionId` is the wrong parser for a Task/Fixlet creation response**
- **Found during:** Task 2, implementing `ensureRoleTask`'s POST-create response handling.
- **Issue:** The plan's action-block text says "Parse the new id from the response with `parseActionId`." `parseActionId` (already present in this file, added in an earlier plan) hunts for an `<Action>` XML element -- the correct parser for a BES Action creation response (used correctly, unchanged, by `stageEndpointScript` in this same plan). A `POST fixlets/custom/<site>` response instead returns a `<Fixlet>` or `<Task>` element; using `parseActionId` against it would silently return an empty string, breaking `ensureRoleTask`'s `taskId` contract that plan 07-08 depends on.
- **Fix:** Added `parseCreatedId(body)` verbatim from this codebase's own established precedent (`fixlet_copier.ojo`, `fixlet_console.ojo`, `fixlet_update_tracker.ojo` all carry an identical copy) and used it in `ensureRoleTask`'s create path instead.
- **Files modified:** `Existing Dashboards/fixlet_role_manager.ojo`
- **Verification:** `node tests/unit/role_manager.test.js` asserts `parseCreatedId` is defined by exact name; manual trace confirms `ensureRoleTask`'s create branch calls `parseCreatedId`, not `parseActionId`.
- **Committed in:** `001d91e`

---

**Total deviations:** 2 auto-fixed (both Rule 1/Rule 3 corrections against the plan's own text, verified against the authoritative source file and this codebase's established conventions respectively)
**Impact on plan:** Both deviations were necessary for correctness -- following the plan's literal text in either case would have produced a Task builder that either couldn't be verified against the real template (case 1) or silently returned an empty `taskId` on every create (case 2), breaking plan 07-08's documented dependency on this plan's interface. No scope creep -- `ASSIGN_ROLE_TEMPLATE`'s actual field values were always going to be dictated by `bes/Assign-RoleMapping.bes` itself, not by the plan text's assumption about its shape.

## Issues Encountered

- Two acceptance-criteria greps are stricter than the pre-existing 07-06 baseline can literally satisfy (documented as a caveat, not "fixed," matching the pattern 07-06's own SUMMARY established): `grep -c 'replaceChild\|appendChild'` was specified to return 0, but `renderRolePanel`'s pre-existing HTML DOM table rendering (added in 07-06, unrelated to BES XML) already contains 7 such calls. This plan's own new code (`ensureRoleTask`, `parseCreatedId`, `buildEndpointScriptStagingActionXml`, `stageEndpointScript`) adds zero `appendChild`/`replaceChild` calls -- verified by isolating `ensureRoleTask`'s function body specifically in a dedicated unit assertion (which does pass with a scoped, not whole-file, check).
- The environment's default `powershell.exe` only carries the built-in Pester 3.4.0, which cannot run this repo's Pester-5-syntax suites (`BeforeDiscovery` etc.). Full Pester regression was run via `pwsh` (PowerShell 7, Pester 5.7.1 installed) instead -- noted here since a future executor session hitting the same `powershell.exe` default should switch to `pwsh` rather than concluding the suites are broken.

## Known Stubs

- The Publish button (`onPublishRoleClick`) remains the 07-06/07-08 stub -- unchanged by this plan, exactly per this plan's own scope (`<objective>` explicitly builds only the two Publish *prerequisites*, not the Publish flow itself; interfaces comment: "Plan 07-08's `publishRole()` calls `ensureRoleTask()`"). This plan adds no new stubs.

## User Setup Required

None - no external service configuration required. No live BigFix console verification was performed this session (staging the endpoint script and creating/updating a Task both require a running console against a real root server -- a later-plan/production-verification concern per this project's established pattern, see 07-01's live spike and the planned 07-12 production checkpoint). All new code is covered by the Node unit suite (87/87) and the `[xml]` cast check.

## Next Phase Readiness

- Plan 07-08 can call `ensureRoleTask(role, onDone)` directly and rely on its documented callback contract: `onDone(err, { taskId, taskFields, actionScript, relevance })`, where `actionScript`/`relevance` are already fully substituted (`__ROLE__`/`__ASSIGNED_BY__` replaced, both `<Relevance>` bodies ANDed per SKILL.md S3) and ready to feed directly into `buildRolePolicyActionXml` -- no re-fetch or re-parse of the Task is required. `taskId` is correctly populated on both the create path (via `parseCreatedId`) and the update path (via the pre-resolved `findBesObjectIdByTitle` id).
- The "Stage endpoint script on root server" button must be clicked at least once in a live console (against a real root server) before any role's policy action can succeed end-to-end -- this is a one-time (or re-run-on-script-change) manual step plan 07-08/07-12 should call out in its own verification checklist, since nothing in this plan's automated tests can confirm the live staging action actually executed against a real BigFix Client.
- No blockers. `fixlet_role_manager.ojo` has not yet been opened in a live BigFix console this session -- deferred to whichever plan first exercises the Prerequisites panel or a live Publish end-to-end (07-08/07-12).

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: `Existing Dashboards/fixlet_role_manager.ojo`
- FOUND: `tests/unit/role_manager.test.js`
- FOUND: `.planning/phases/07-automation/07-07-SUMMARY.md`
- FOUND commit: `05bd97d` (Task 1)
- FOUND commit: `001d91e` (Task 2)
- FOUND commit: `b442710` (Task 3)
