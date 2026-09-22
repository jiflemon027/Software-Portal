---
phase: 07-automation
plan: 01
subsystem: infrastructure
tags: [bigfix-rest, computergroup, session-relevance, client-relevance, spike, production-verify]

requires: []
provides:
  - "07-SPIKE-RUNBOOK.ps1 — reusable parameterized BES-root-server spike/audit script"
  - "07-SPIKE-FINDINGS.md — recorded ground truth: accepted ComputerGroup element set, relevance dialect boundary, retired-pipeline audit, sqlite3.exe presence"
affects: [07-04, 07-07]

tech-stack:
  added: []
  patterns:
    - "Client relevance and session relevance are distinct dialects with different operator sets — `logged on users` is client-relevance-only, undefined under /api/query session relevance. Only validate an expression via the dialect it will actually run in."
    - "Invoke-WebRequest (PS 5.1) can return .Content as byte[] rather than a decoded string for some content-types; casting byte[] to [string] silently produces a space-joined byte-value dump, not text — always check the type and decode explicitly."
    - "A REST call's HTTP success (200/success=True) does not mean a BES query succeeded — BES wraps query-evaluation failures in a <Query>/<Error> element regardless of HTTP status; check for that element, not just the status code."

key-files:
  created:
    - .planning/phases/07-automation/07-SPIKE-RUNBOOK.ps1
    - .planning/phases/07-automation/07-SPIKE-FINDINGS.md
  modified: []

key-decisions:
  - "Task 2 (blocking human-verify checkpoint) was run for real against production gpbfs by the user, not simulated."
  - "The findings file's original Check B verdict (PASS) was incorrect — corrected post-hoc after decoding a byte-dump response body that actually contained a BES <Error> element. Root-caused to two runbook bugs (byte[]-to-string cast, narrow parse-error-only regex) and fixed directly in 07-SPIKE-RUNBOOK.ps1 so a future re-run reports correctly."
  - "Check B's real failure (logged on users undefined via session relevance) does not block 07-04: buildRoleGroupRelevance only ever emits this expression as client relevance inside <ComputerGroup> XML, never executed via /api/query. Check A (genuine REST create/round-trip/delete of a ComputerGroup using this exact relevance) is the authoritative validation for that context and is a clean PASS."

patterns-established:
  - "Accepted <ComputerGroup> element set (six-element: Title/Domain/JoinByIntersection/IsDynamic/EvaluateOnClient/SearchComponentRelevance) is now the confirmed contract for 07-04's buildComputerGroupXml."

requirements-completed: [NFR-02]

duration: "~15min (Task 1) + production checkpoint run by user + ~30min orchestrator correction/verification"
completed: 2026-09-22
---

# Phase 07 Plan 01: Ground Truth Spike Summary

**Production-verified ground truth for three unproven assumptions this phase's generator depends on: the accepted `<ComputerGroup>` REST element set, the relevance dialect boundary for `set of ("a";"b")` tuple syntax, and the retired Axonius-pipeline/sqlite3.exe state of the live root server — plus two bugs in the spike script itself, found and fixed while verifying the production run.**

## Performance

- **Task 1:** ~15 min (script authored, AST-parsed, dry-run tested against an unreachable host)
- **Task 2 (blocking human-verify checkpoint):** run by the user against production `gpbfs`
- **Orchestrator correction pass:** ~30 min (decoded a garbled evidence field, traced two real bugs, fixed both, re-verified against plan dependents)
- **Tasks:** 2/2 completed

## Accomplishments

- `07-SPIKE-RUNBOOK.ps1` (453 lines) — a parameterized, re-runnable PowerShell 5.1+ script covering four independently try/catch-wrapped checks (ComputerGroup element-set probe, session-relevance tuple-form probe, retired-pipeline audit, sqlite3.exe presence), each written as PASS/FAIL + evidence into `07-SPIKE-FINDINGS.md`.
- Production run against `gpbfs` completed by the user. Real results:
  - **Check A (PASS):** the **six-element** `<ComputerGroup>` body (Title/Domain/JoinByIntersection/IsDynamic/EvaluateOnClient/SearchComponentRelevance) was accepted; group created, round-tripped via GET with identical relevance text, and deleted cleanly.
  - **Check B (corrected to PARTIAL):** the literal `set of ("a";"b")` tuple form is valid in the **client relevance** dialect (proven by Check A) but the query as tested via `/api/query` **failed** with `The operator "logged on users" is not defined.` — `logged on users` is a client-relevance-only inspector, not available in session relevance. No current plan executes this expression via session relevance, so this has no downstream impact.
  - **Check C (PASS):** no live Axonius-era artefacts found on `gpbfs` — no `DeresoRoleIngest`/`DeresoRolePublish` scheduled tasks, no `RoleRef*` fixlets or computer groups.
  - **Check D (PASS):** `sqlite3.exe` present at the expected `SQLDir`, version 3.53.1.
- **Two real bugs found and fixed in the runbook itself** while verifying the production output (see Deviations/Issues below), so a future re-run of this script reports correctly rather than repeating a false PASS.

## Task Commits

1. **Task 1: Write the spike + audit runbook script** — `b255f7b` (feat)
2. **Task 2 (checkpoint) + orchestrator correction** — `79f6bb4` (fix: correct Check B false PASS, fix runbook byte-decoding and error-detection bugs, record corrected findings)

## Files Created/Modified

- `.planning/phases/07-automation/07-SPIKE-RUNBOOK.ps1` — spike/audit script (453 lines, later patched for the two bugs below)
- `.planning/phases/07-automation/07-SPIKE-FINDINGS.md` — production findings, with Check B corrected in place and the correction explained inline

## Decisions Made

- **Corrected the findings record rather than silently trusting the script's self-reported PASS.** The raw evidence for Check B was a garbled space-separated byte dump in the findings file — a red flag rather than illegible noise. Decoding it revealed a genuine `<Error>` from the server, contradicting the script's own "PASS" verdict.
- **Did not block Wave 2 on the Check B failure.** Traced every current-model plan (07-04, 07-05, 07-06, 07-08, 07-09) that references this relevance expression and confirmed it is always embedded as client relevance inside `<ComputerGroup>`/`SearchComponentRelevance` XML, never executed live via session relevance. Check A already independently and genuinely validates that exact context.
- **Fixed the runbook script itself**, not just the findings record, so the next person who re-runs it (e.g. for D-21 fleet-wide verification) gets a trustworthy result:
  1. `Invoke-BesRequest` now detects when `Invoke-WebRequest`'s `.Content` comes back as `byte[]` (which PS 5.1 does for some response content-types) and decodes it via UTF8 instead of casting it to `[string]` (which silently produces a space-joined byte-value dump).
  2. Check B's pass condition now checks for BES's generic `<Query>/<Error>` element instead of a narrow "parse error" text match, which missed non-parse query failures like an undefined operator.

## Deviations from Plan

- The plan's Task 2 acceptance criteria required the findings file to record an explicit outcome for each check — it did, but Check B's recorded outcome was **wrong** due to the two runbook bugs above. This was caught and corrected as part of closing out this plan, going beyond the plan's literal ask ("record an outcome") to also verify that outcome was accurate before it fed 07-04's implementation.

## Issues Encountered

- **Runbook bug 1:** `[string]$byteArrayContent` in PowerShell 5.1 does not decode bytes to text; it performs the default array-to-string join (space-separated numbers). `Invoke-WebRequest`'s `.Content` property returned as `byte[]` for the `/api/query` response, so the logged "evidence" was unreadable garbage that also broke the script's own regex-based pass/fail check silently. Fixed by explicit type-checking and UTF8 decoding.
- **Runbook bug 2:** the pass/fail regex for Check B only matched the phrase "parse error", missing BES's actual error for this case ("The operator ... is not defined."). Fixed by checking for the presence of BES's `<Error>` element generically, which is the correct, dialect-agnostic signal for any query-evaluation failure.

## User Setup Required

None further — the production checkpoint (host with `gpbfs` REST access, console-operator credentials) has already been completed by the user.

## Next Phase Readiness

- **07-04** (`buildComputerGroupXml`/`buildRoleGroupRelevance`) is unblocked: build the six-element `<ComputerGroup>` body; the `set of ("a";"b")` tuple form inside client-relevance `SearchComponentRelevance` is production-confirmed.
- **07-07** (Publish prerequisites) can rely on Check C: no leftover Axonius-era scheduled tasks or `RoleRef*` objects need to be reconciled against on `gpbfs`.
- If any future work needs to evaluate role-membership-style relevance via **session relevance** (e.g. a live dashboard preview/dry-run against the BES object model, distinct from Analysis-property client relevance), `logged on users` is NOT usable there — a different approach (e.g. reading `RoleAwareness.db` directly, as 07-09's Analysis tab already does) is required.

---
*Phase: 07-automation*
*Completed: 2026-09-22*

## Self-Check: PASSED

- FOUND: .planning/phases/07-automation/07-SPIKE-RUNBOOK.ps1
- FOUND: .planning/phases/07-automation/07-SPIKE-FINDINGS.md
- FOUND commit: b255f7b
- FOUND commit: 79f6bb4
