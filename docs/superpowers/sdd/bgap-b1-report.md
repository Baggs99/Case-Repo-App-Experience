# B1 — Scheduling Core: Phase Report

**Status: DONE** · Branch `bgap/b1-scheduling` · Head `56670a3` · Date 2026-07-17
Worktree: `/Users/thomaskgould/dev/bgap-b1` · DB: `caserepo_bgap_b1`

Delivered the proposal as the universal scheduling primitive: open (send-a-link) proposals, "interviewer decides" (case-less) proposals, one-round time counters, spec-accurate A3 expiry/missed lifecycle swept from the always-on 60-s loop, and 6-char pairing short-codes. All new behavior is API-driven and covered by tests.

## Suite counts

| | Passed | Failures |
|---|---|---|
| Baseline (before) | 360 | 0 |
| After B1 | **402** | 0 |

+42 tests (41 new + 1 net from the DD-2 expiry-test rewrite). Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 .venv/bin/python -m pytest tests/ -q` → `402 passed`. Migrations 020/021 re-applied cleanly (idempotent) after the run.

## Tasks (all reviewed clean)

| Task | Deliverable | Commits | Review |
|---|---|---|---|
| 1 | Migrations 020 & 021 | f1721cf..6a72e75 | CLEAN |
| 2 | Env-tunable expiry settings | ..ab30892 | CLEAN |
| 3 | Proposal create — nullable case/recipient + claim_token | ..62fb963 | CLEAN |
| 4 | Claim endpoint + `claim_proposal` | ..bcab307 | PASS |
| 5 | One-round counter + counter-accept | ..193e09e | CLEAN |
| 6 | A3 expiry sweeps + missed sessions | ..a7ba0b2 | PASS |
| 7 | Consolidate sweeps into 60-s loop | ..1002191 | CLEAN |
| 8 | Pairing short-codes + optional case + claim-by-code | ..f7e9846 | PASS |
| 9 | api_v1 proposals parity | ..c49cd82 | PASS |
| — | Final whole-branch review fixes | ..56670a3 | CLEAN (re-reviewed) |

Ledger: `.superpowers/sdd/progress.md`. Per-task evidence + diff packages under `.superpowers/sdd/`.

## New endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/proposals/claim/{claim_token}` | `require_auth_api` + `require_same_origin` (CSRF) | Any authed non-creator claims an open link. **Auth dependency left injectable** (plain `Depends(require_auth_api)`) so B2 can override for guests. IDOR: creator can't claim; keyed on the secret token; double-claim → 409. |
| POST | `/api/proposals/{id}/counter` | `require_auth_api` + `require_same_origin` | Recipient-only, pending-only, one round. Pushes `proposal_countered` to the proposer. |

### Modified endpoints (behavior/payload changed — additive)

| Method | Path | Change |
|---|---|---|
| POST | `/api/proposals` | Body `case_id`/`to_user_id` now optional; open-link (no `to_user_id`) response includes `claim_token`. Named-recipient flow unchanged. |
| POST | `/api/proposals/{id}/accept` | Body gains optional `time` (chosen counter time, proposer-side, for counter-accept). Case-less accept returns `{accepted, session_id: null, needs_negotiation: true}`. |
| POST | `/api/practice/pair/create` | Body `case_id` optional; response now carries `short_code` (6 chars). |
| POST | `/api/practice/pair/claim` | Accepts `{token}` **OR** `{short_code}`. Case-less token → 409 (DD-1). |
| GET | `/api/v1/proposals` | See PAYLOAD CHANGES below. |

## New migrations

- **020_proposals_scheduling.sql** — `proposals`: `case_id`/`to_user_id` DROP NOT NULL; `claim_token TEXT` (partial unique index when non-null); `counter_times_json JSONB`; `counter_by INTEGER REFERENCES users`; `countered_at TIMESTAMPTZ`; state CHECK gains `'countered'`.
- **021_missed_and_pairing_shortcode.sql** — `practice_sessions` state CHECK gains `'missed'`; `pairing_tokens.case_id` DROP NOT NULL; `pairing_tokens.short_code TEXT` (partial unique index when non-null).

Both idempotent (`ALTER COLUMN DROP NOT NULL` no-op, `ADD COLUMN IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS` + re-ADD preserving all prior states, `CREATE UNIQUE INDEX IF NOT EXISTS`). Note: `claim_token`/`short_code` uniqueness implemented as **partial unique indexes** (`WHERE ... IS NOT NULL`) rather than a plain `UNIQUE` column — behaviorally equivalent (Postgres UNIQUE already allows multiple NULLs) and idempotent.

## Interfaces delivered (later phases build against these)

- `claim_proposal(token: str, user_id: int) -> dict` — returns `{proposal_id, state, session_id (Optional), accepted, needs_negotiation, from_user_id}`. Parameter named `token` per the brief-pinned signature. **B2 consumes** (overrides the route's `require_auth_api` for guests).
- `counter_proposal(proposal_id: int, user_id: int, times: list[datetime]) -> dict` — recipient-only, pending-only. Push kind `"proposal_countered"` → proposer. **B3 reuses this counter/push pattern for swap invites.**
- `respond(proposal_id, user_id, *, accept, scheduled_at=None, counter_time=None) -> dict` — extended: `pending` → recipient; `countered` → proposer with `counter_time` from stored counter times; DV-11 non-participant → 404; case-less accept → session_id null + ephemeral `needs_negotiation=True`.
- `_resolve_roles(prop) -> (interviewer_id, candidate_id)` and `_create_session_within(cur, prop, scheduled_at) -> int` in `webapp/repositories/proposals.py`.
- `list_for_api(user_id) -> list[dict]` — received-pending ∪ sent-countered, with `direction`/`state`/`claim_token`/counter fields; `inbox()` now `LEFT JOIN cases`.
- **State `'missed'`** on `practice_sessions` (B3 consumes) and `'countered'` on `proposals`.
- `sweep_expired(now_expiry_min=120)` (A3 semantics), `sweep_missed(missed_after_min=60)` in the repos.
- `webapp/maintenance.py`: `run_maintenance_pass(settings) -> dict` (counts) and sleep-first `maintenance_loop(interval_seconds=60)` — spawned unconditionally from `main.py` lifespan.
- `settings.proposal_now_expiry_min` / `settings.session_missed_after_min` (env `PROPOSAL_NOW_EXPIRY_MIN` / `SESSION_MISSED_AFTER_MIN`).

## PAYLOAD CHANGES (iOS consumes these later)

- **`POST /api/proposals`** response: now includes `claim_token` (non-null only for open links); `case_id`/`to_user_id` may be null; counter fields present (null at creation).
- **`POST /api/proposals/claim/{token}`** (new) response: `{proposal_id, state, session_id (nullable), accepted, needs_negotiation, from_user_id}`.
- **`POST /api/proposals/{id}/accept`**: body gains optional `time`; case-less accept returns `{accepted, session_id: null, needs_negotiation: true}` (no `session_url`/`ics_url`).
- **`POST /api/proposals/{id}/counter`** (new): body `{times: [iso8601, ≤3]}`; response `{countered: true, proposal_id, counter_times}`.
- **`GET /api/v1/proposals`** items: **added** `direction` (`"received"`/`"sent"`), `state`, `claim_token`, `counter_times`, `counter_by`, `countered_at`; the list **now also returns sent-countered proposals** (so the proposer can accept a counter), not just received-pending; `case_title`/`case_type`/`difficulty` may be **null** for case-less proposals. iOS should key the counterparty off `direction`+`counter_by` — on a `sent` item, `from_name` is the caller's own name (see DEFERRED N-1).
- **`POST /api/practice/pair/create`**: response gains `short_code`; body `case_id` optional.
- **`POST /api/practice/pair/claim`**: body accepts `short_code` OR `token`.
- **Push**: new event kind `"proposal_countered"` → proposer.

## Design decisions (assumptions)

- **DD-1 — Sessions stay case-bound.** Migrations 020/021 do NOT relax `practice_sessions.case_id`/`rubric_template_id` (not in the pinned migration budget). B1 fully supports null `case_id` on **proposals and pairing tokens** (data model + create/claim/counter lifecycle). Any session-creating step on a case-less proposal returns `needs_negotiation: true` + `session_id: null` (proposal marked `accepted`, no session inserted); a case-less **pairing** claim returns **409** (pairing_tokens has no accepted-without-session representation). **No code path ever inserts a case-less `practice_session`** (verified in final review). → **B3 owns the pre-lobby `negotiating` session** (its migration 028 adds the state) built from these null-case entry points.
- **DD-2 — A3 expiry replaces the 7-day rule.** `sweep_expired` now expires now-proposals at `created_at + PROPOSAL_NOW_EXPIRY_MIN`, scheduled at earliest proposed start, countered at earliest counter time. Rewrote `tests/test_queues_proposals.py::test_expiry_sweep` → two A3 methods (net +1 test).
- **DD-3 — The 60-s loop runs unconditionally.** Previously spawned only when APNs was configured; now always (sleep-first, so short-lived test app lifespans never trigger a sweep). Push inside `notify_starting_soon` self-guards when APNs is absent.
- **DD-4 — `/api/v1/proposals` gains `state`.** Removed the now-invalid `assertNotIn("state", item)` from `tests/test_api_v1_sessions.py::test_proposals_inbox_curated_shape` (other exclusion guards kept). No test removed.

## Cross-phase notes for the orchestrator (before merging)

- **Shared files touched additively:** `webapp/settings.py` (2 fields on the `Settings` dataclass + `load_settings` — expect a merge touch with **B5** which also adds user fields), `webapp/main.py` (lifespan now spawns `maintenance_loop`; dropped the `push_enabled`-gated `starting_soon_loop` spawn + its imports), `webapp/routes/api_v1.py` (`list_proposals` rewritten to use `list_for_api`; the redundant page-load `sweep_expired()` there was dropped — the 60-s loop is authoritative), `webapp/routes/proposals.py`, `webapp/routes/practice.py`, `webapp/repositories/{proposals,practice_sessions,pairing_tokens}.py`, `webapp/push/starting_soon.py` (dead `starting_soon_loop` removed), `webapp/templates/room.html` (case_title guard).
- **New module:** `webapp/maintenance.py`. **B1 registers no new router** (claim/counter live in the already-registered `proposals` router) — no app-factory `include_router` line added, so no registration conflict.
- **Migrations 020/021** are the only B1 migrations; safe to apply in order after 018 (019 reserved).
- **B3 dependency:** consumes `claim_proposal`, `'missed'`/`'countered'` states, the counter/push pattern, and must complete the case-less negotiation seam (DD-1).

## DEFERRED (with reasons)

- **Case-less negotiating session** — the pre-lobby `negotiating` session created from null-case proposals/pairing is **B3** (DD-1; needs migration 028's `'negotiating'` state, outside B1's 020/021 budget).
- **N-1 (hygiene, for B2):** `claim_proposal` sets `to_user_id` but does not null `claim_token`, so `list_for_api` returns a now-dead token on the claimed/countered row. Not a leak (post-claim the token 409s; only the participant sees it). Recommend nulling `claim_token` on claim before B2 guests land.
- **N-2 (consistency):** the inline `sweep_expired()` calls in the web accept/inbox/room routes use the hardcoded default `120`, not `settings.proposal_now_expiry_min`. Harmless (the 60-s loop passes the tuned value and is authoritative); only diverges if tuned below 120 before the first loop pass.
- **m6d (latent):** `sweep_expired` casts stored ISO strings to `timestamptz`; a client sending an **offset-less** ISO time would resolve against the DB session `TimeZone` GUC. Pre-existing input-validation gap (same ambiguity already exists for `scheduled_at`); all current clients/tests send tz-aware. Recommend coercing/rejecting naive datetimes in `ProposalBody`/`CounterBody`.
- **m6b / m6c (test coverage):** `sweep_missed` `'live'`-stays-live and past-window `'lobby'`→missed branches, and a sweep idempotency re-run, are unasserted. The `WHERE` clauses were verified correct in review; no-op-on-rerun holds by construction.
- **m8a / m8b (cosmetic):** mint route doesn't wrap `TransitionError(500)` (reachable only on 5 consecutive short-code collisions in a ~1e9 space); pairing repo's defensive 400 vs the route's 422 for "neither token nor short_code" (route intercepts first).
- **Trivial:** `webapp/push/starting_soon.py` now has an unused module-level `logger` after the dead-code removal (module imports cleanly).

## ESCALATIONS

None. No Fable consults were made or are queued.
