# Phase 4: Role Assigner Dashboard - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-27
**Phase:** 4-role-assigner
**Areas discussed:** Write-back mechanism, Assignment model, Admin UI pattern, Phase 4 scope

---

## Write-back Mechanism

| Question | Options | Selected |
|----------|---------|----------|
| MAG structure per computer | One action per computer (all roles bundled) / One action per (user, computer) pair / One action per computer with embedded CSV fragment | (Overridden by free-text — see notes) |
| Matrix encoding | JSON { computers[], users[] } B64 chunked / Pipe-delimited B64 chunked / You decide | JSON { computers[], users[] } B64 chunked |
| B64 chunking strategy | Multiple parameters (chunk0, chunk1...) / Single parameter with sentinel delimiter / You decide | Multiple parameters (chunk0, chunk1...) |
| Action relevance | Explicit computer ID list only / DB-exists relevance only / Both (double guard) | Both — target by computer ID list AND require DB to exist |
| Action 2 (remove) behaviour | Set Active=0 (soft delete) / DELETE row (hard delete) / Active=0 + Valid_to=now | Set Active=0 AND Valid_to=now |
| Action 1 (add/update) upsert | INSERT OR IGNORE + UPDATE if Active=0 (D-12) / INSERT OR REPLACE / INSERT OR IGNORE only | INSERT OR IGNORE + UPDATE if Active=0, preserve Locked_by_Override |
| MAG vs per-action API | API.Post("actions/multi") with MAG XML / API.Post("actions") once per action | API.Post("actions") once per action — simpler, role count kept low |

**User's key free-text input:** "The dashboard will accept a CSV file. Using the data in this CSV it will generate a Multi-Action-Group containing some actions which will update the roleawareness.db on the endpoints. The MAG is structured with two actions per role — Action 1 adds/updates the map, Action 2 removes. Each action contains a matrix of computer IDs where position corresponds to index position in a user list. The matrix should be compressed and transferred in B64 (note ~4000 char BigFix agent string limit, so longer B64 strings may need concatenation)."

**Resolution:** User later confirmed simpler per-action approach (no MAG). Role count is kept low to manage actionsite saturation.

**Notes:** Action structure follows `Init Current User and UserRole DB.bes` pattern. Action naming: `Dereso_[Role] Assign_[suffix]` / `Dereso_[Role] Revoke_[suffix]`. Suffix defaults to selected group name.

---

## Assignment Model

| Question | Options | Selected |
|----------|---------|----------|
| Computer_ID column meaning | Targeting only (role is user-global) / Machine-scope (role is per-machine, schema change needed) / Delivery vehicle (same as targeting-only) | Per-client scope — each client's Map table records assignments for users on that machine |
| Remove list source | Analysis data in dashboard / Separate revoke CSV / Not in Phase 4 | Analysis data — admin queries mapped_users from Analysis and selects what to revoke |

**User's key free-text input (Computer_ID clarification):** "From the example CSV, I would expect three actions. Action A targets computers containing ID 123450 and maps user 511555 to IT Support. Action B targets 123450 and maps 511555 to IT Developer. Action C targets [971163450, 97316345] and maps wgoose on 971163450 and dholliday on 97316345 to IT Operations."

**Resolution:** One action per unique role. Matrix = parallel arrays where index i = one (computer, user) pair for that role. Computer_ID column renamed from `computer` to `Computer_ID`.

**Additional requirements surfaced:**
- Top-level group selector (same as Dispatcher's PORTAL_CONFIG.targetGroups) — informational context, not a hard filter
- Geo-suffix input: admin adds region text above Deploy button; defaults to selected group name if blank
- Action naming format: `Dereso_[Role] Assign_[suffix]`

---

## Admin UI Pattern

| Question | Options | Selected |
|----------|---------|----------|
| Primary layout | Two-panel (state + action) / Tabbed / Single-page vertical flow | Single-page vertical flow: group selector → suffix → CSV upload → preview → deploy |
| CSV preview | Parsed table with validation errors / Summary only (N users, M computers, K roles) / Action preview (role + computer count) | Parsed table: User, Computer_ID, Role columns, row count, validation errors highlighted |
| Post-deploy feedback | Success banner per action with ID / Single summary banner / Deploy log panel | Success banner per action with ID (same as Dispatcher) |
| Revoke UI | Filterable table from Analysis + multi-select revoke / Role-first dropdown then user list / Read-only in Phase 4 | Read-only in Phase 4 — shows current mappings, no action generated |
| Geo-suffix placement | Above Deploy button (per-import text field) / In PORTAL_CONFIG (config-level) / Fourth CSV column | Above Deploy button — labelled "Region / suffix (optional)" |
| Group selector behaviour | Filters CSV preview to group members / Informational label only / Hard intersection filter | Informational — follows Dispatcher pattern (PORTAL_CONFIG.targetGroups dropdown) |
| PORTAL_CONFIG contents | targetGroups + roles + actionNamePrefix / targetGroups only (dynamic roles) / targetGroups + prefix only | targetGroups + roles + actionNamePrefix |
| CSV validation | Block unknown role + blank fields; warn duplicates / Block everything / Warn only | Block: unknown role, blank User, blank Computer_ID. Warn: duplicates. |
| Analysis view columns | User, Role, Computer Count / Role, Users (comma-joined) / Computer, User, Role | Computer Name, User, Role — one row per mapping per reporting computer |

**Notes:** PORTAL_CONFIG.roles is the single source of truth for the role list. Management will change roles (current examples: IT Developer/Support → IT Operations; adding Finance, HR). Admin updates PORTAL_CONFIG.roles only. Analysis view populated from `mapped_users in r.db` property via GetRelevance. DB-not-initialised warning shown if a CSV Computer_ID is absent from Analysis results.

---

## Phase 4 Scope

| Question | Options | Selected |
|----------|---------|----------|
| DB initialisation in scope | In scope (deploy Init task from dashboard) / Out of scope / Partial (warn if not initialised) | Partially in scope — warn if target computer's DB isn't initialised; don't deploy init |
| Override management | Out of scope / Read-only view only | Out of scope — DB schema supports it, UI deferred |
| Dereso SWD Analysis | Part of Phase 4 deliverable / Pre-existing dependency | Part of Phase 4 — finalise the BES file alongside the ojo |

**Notes:** Naming convention for ojo not explicitly asked — inferred as `fixlet_role_assigner.ojo` to match existing naming convention.

---

## Claude's Discretion

- Analysis view table column format (Computer Name | User | Role) — inferred from `gpbfs_analysis_results.txt` sample; user confirmed by providing the file.
- Remove action naming (`Dereso_[Role] Revoke_[suffix]`) — extrapolated from user-stated add naming convention.
- ojo filename: `fixlet_role_assigner.ojo` — follows existing naming pattern; not explicitly confirmed.

## Deferred Ideas

- Revoke UI (Phase 5) — Analysis-driven selection of mappings to revoke, generating `Dereso_[Role] Revoke_[suffix]` actions.
- Override management (Phase 5) — UI for creating/viewing/expiring Overrides table entries.
- DB init from dashboard (Phase 5) — One-click "Initialise DB" button.
- Group overlap indicator — non-required in Phase 4; visual check of CSV Computer_IDs vs selected group members.
- Multi-Action-Group — reconsidered and deferred; revisit if role count grows.
