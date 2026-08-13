---
phase: quick/260813-fjc
tags: [fixlet-console, bigfix-relevance, ojo-dashboard, ssa-dashboard, follow-up]
status: pending-human-verification
---

# Follow-ups: Fixlet Console + SSA Dashboard (2026-08-13)

Picking this back up? Start here. Nothing below is broken as far as static
analysis / unit tests / live read-only relevance checks can tell — the
remaining gap is entirely "needs eyes in the actual BigFix console/SSA",
which no tool available to Claude Code can substitute for.

## 1. `Existing Dashboards/fixlet_console.ojo` — new unified dashboard

Built this session: merges the catalog/search/filter grid, the deploy engine
(fixlet_dispatcher.ojo), the edit engine (fixlet_modifier.ojo), and the
update-scan engine (fixlet_update_tracker.ojo) into one dashboard, plus two
new capabilities (Open Offers drift view, per-row Stop). Never rendered in
an actual BigFix console — do that before relying on it.

**Verification checklist (do this first):**
- [ ] Import into the BigFix console, open the dashboard, confirm it loads
      with no JS errors and the site selector defaults to "Dereso Software
      Portal".
- [ ] Catalog tab: search, category filter, sort, pagination all work; the
      layout fix (Search on its own row) actually looks right at your
      screen width.
- [ ] Select a fixlet → Edit sub-tab: category + roles editor populates
      correctly, Save works, **Delete Fixlet** works (test on a throwaway
      fixlet first — it's irreversible).
- [ ] Deploy sub-tab: group targeting, action select, deploy actually
      creates an action with the right SmartRole_Source/Associated_Roles/
      OfferCategory MIME fields (spot-check via GET on the new action).
- [ ] Open Offers tab (site-wide): shows real open offers, category/role
      drift highlighting fires correctly on a fixlet you've edited since it
      was deployed, **Stop** button actually stops the action
      (`POST action/{id}/stop` — verify this is really the right endpoint
      path on your BigFix version; it was never live-tested this session).
- [ ] Detail panel's "This Fixlet's Open Offers" sub-tab shows the same data
      filtered to one fixlet.
- [ ] Check for Updates tab: scan, Updates/New Arrivals, Copy Selected, and
      the resulting new fixlet actually lands in the currently selected
      site (not hardcoded to Dereso Software Portal anymore — confirm this
      works when a *different* site is selected too).
- [ ] Root-server prefetch staging: deploy something with a prefetch line,
      confirm the staging action's own status (Fixed/Failed) now reflects
      real precache success — this is the new `SuccessCriteria` relevance
      (see item 2 below), the one piece of relevance in this file that
      couldn't be verified live.

## 2. Precache `SuccessCriteria` relevance — the one unverified relevance string

`buildPrecacheSuccessRelevance()` / `buildRepoRootRelevance()` in
fixlet_console.ojo. The registry-path portion is copied verbatim from this
project's own proven `Dashboard_4_samples/Dereso SWD Repository Cache.bes`
(a test asserts byte-identity, so it can't silently drift), but the
*SuccessCriteria mechanism itself* — whether BigFix accepts
`<SuccessCriteria Option="CustomRelevance"><CustomRelevance>...` in a
`SingleAction` the way it does in a Fixlet's `DefaultAction`, and whether the
`exists file "x" of folder "sha1" of folder (...)` per-file check actually
evaluates true once the file lands — was never live-tested. Session
relevance (what Claude's BigFix MCP tool can dry-run) can't evaluate
client-side SuccessCriteria; only the real BES Client agent on the root
server can, when the staging action actually runs.

**Do:** deploy something with a prefetch line, stage it, and watch the
staging action's status in the console go Fixed/Failed and confirm it
matches whether the file is really there.

## 3. `CATEGORY_MAP` in fixlet_console.ojo is a trimmed starter

Only ~35 entries copied across, vs. the full ~450-entry map already
maintained in `fixlet_update_tracker.ojo`. It only affects the *suggested*
category shown for a brand-new arrival in the Check for Updates tab — never
blocks a scan or hides a result — but should be brought to full parity.

**Do:** copy `CATEGORY_MAP` from fixlet_update_tracker.ojo into
fixlet_console.ojo verbatim (or better: extract it to a single shared
source both files pull from, via `scripts/generate_category_map.js`, so it
stops needing to be kept in sync by hand across three files).

## 4. `SSA_Addendum/dashboard/_dashboard.html` — stall-highlight feature

Also shipped this session: highlights an offer still "Waiting to start"
past 75 minutes (amber row + badge), and removed the temporary raw-tag
diagnostic panel. The underlying SQL/regex changes were verified against the
real sample DBs in `SSA_Addendum/` and `SSA_Addendum/Offer_progress/`
(including a real 24h-stale AnyDesk offer that matches the original ask
exactly), but the page itself hasn't been reloaded in the actual SSA client
UI since these edits.

**Do:** reload `_dashboard.html` in the real Self-Service Application and
confirm the amber highlight renders as expected on a genuinely stalled
offer, and that removing the diagnostic panel didn't leave any dangling
references (there shouldn't be any — grep confirmed none — but worth an
eyeball).

## Not yet started

Nothing else outstanding from this session as of 2026-08-13 — the above is
the complete list.
