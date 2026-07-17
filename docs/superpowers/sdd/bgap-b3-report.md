# B3 — Session-flow additions: Phase Report

**Status: DONE** · Branch `bgap/b3-sessionflow` · Head `a33dcf3` · Base `a87ad7b` · Date 2026-07-17
Worktree: `/Users/thomaskgould/dev/bgap-b3` · DB: `caserepo_bgap_b3`

Delivered case negotiation (B1's case-less "interviewer decides" seams now create a real pre-lobby `negotiating` session, settled over new REST endpoints + the existing signaling WS), role swap (reversed-role rematch behind a `swap_invites` table), the feedback recap gate (a required 1–5 close-out rating clears it; blocks every candidate-seat entry oldest-first), debrief seeding (finalize seeds the candidate's next session), and per-case rating aggregates on the Library payloads. Sessions created WITH a case skip `negotiating` entirely — the ~200 existing session tests stayed green untouched.

## Suite counts

| | Passed | Failures |
|---|---|---|
| Baseline (before, seeded) | 545 | 0 |
| After B3 | **576** | 0 |

+31 net. Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b3 .venv/bin/python -m pytest tests/ -q` → `576 passed`. Migrations 028/029 re-apply idempotently (NOTICEs only). **Tests skip without the dev seed** (`scripts/seed_caseroom_dev.py`).

## Tasks (all reviewed clean)

| Task | Deliverable | Commit range | Review |
|---|---|---|---|
| Plan | Plan + Opus plan-review (2 Important fixed) | ceec220..2a55674 | APPROVED-after-fixes |
| 1 | Migrations 028 (negotiating state, nullable case/rubric, swapped_from, case_negotiations, swap_invites) + 029 (feedback recap columns) | 2a55674..e2551fe | CLEAN |
| 2 | State machine + repo plumbing (LEFT JOIN cases, create/stamp negotiating, sweep) | 52ad8b2..08e0eb6 | CLEAN |
| 3 | Recap gate core (candidate_gate/assert/list/viewed/close + RecapGateError) | 8ea0733..23e8863 | CLEAN |
| 4 | Convert case-less entries → negotiating + recap gate on 5 candidate seats | bc1a8f5..5352c59 | CLEAN |
| 5 | Negotiation endpoints + repo + WS broadcast + router registration | d614464..92fe948 | CLEAN |
| 6 | Recap endpoints (list / viewed / close) | 40c89b7..28da16f | CLEAN |
| 7 | Role swap (swaps.py + endpoints) | bebc7d5..62b2d65, race-fix ..25fdc3e | CHANGES→RESOLVED |
| 8 | Debrief seeding (finalize response + push) | 25fdc3e..9006dc5 | CLEAN |
| 9 | Case rating aggregates + open/done on Library payloads | 02e7216..10d2879 | CLEAN |
| Final | Whole-branch Opus review (edge cases driven end-to-end) | — | CLEAN |

Ledger + per-task diff packages under `.superpowers/sdd/b3/`.

## New endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/practice/{id}/negotiation` | `require_session_participant` | Current pick / counter / whose_turn / candidate_requested_case; `pick_sources` (interviewer-only). |
| POST | `/api/practice/{id}/negotiation/propose` | `require_session_participant` + CSRF | Interviewer opens (round 1); candidate one counter (round 2). Non-interviewer first propose → 403; over-round / wrong-turn → 409; burned-for-candidate → 409; unknown case → 404. |
| POST | `/api/practice/{id}/negotiation/accept` | `require_session_participant` + CSRF | `{case_id}` ∈ proposed set (409 else). Interviewer accepts any proposed case ("keep pick" or take counter); candidate accepts ONLY the interviewer's pick (403 else). Stamps case + rubric, → `lobby`, broadcasts `session_update`. |
| POST | `/api/practice/{id}/swap` | `require_session_participant` + CSRF | Interviewer-only, non-guest (403 for guest/candidate caller); `debrief`/`finalized` only (409); counterpart guest → 409; one pending invite/session (409). Pushes `swap_invite`. |
| POST | `/api/practice/{id}/swap/accept` | `require_session_participant` + CSRF | Invitee-only (404 else), non-guest (403). Recap gate on new candidate → 409 `{blocked_by_recap}`. Atomic `claim_invite` before session create (no double-accept). Pushes `swap_accepted`. |
| GET | `/api/v1/recaps` | `require_auth_api` (guest 403) | `{recaps: [...]}` unread finalized recaps as candidate, oldest-first. |
| POST | `/api/practice/{id}/recap/viewed` | `require_session_participant` + CSRF | Candidate-only (403 else); session must be `finalized` (409). Stamps `viewed_at`. |
| POST | `/api/practice/{id}/recap/close` | `require_session_participant` + CSRF | Candidate-only. Body `{case_rating: 1-5 REQUIRED, feedback_thumbs: bool\|null}`. Missing/out-of-range rating → 422. Thumbs stored only if interviewer non-guest. First-close-only (409 re-close). Clears the gate. **The debrief close-out IS this endpoint.** |

### Modified endpoints (payload / behavior changed — additive)

| Method | Path | Change |
|---|---|---|
| POST | `/api/proposals/{id}/accept` | Case-less accept now creates a **negotiating session** and returns `{accepted, session_id: <int>, needs_negotiation: true}` (was `session_id: null`); **no** ICS invite for negotiating. +409 `{blocked_by_recap}` when the accepting user is a gated candidate. |
| POST | `/api/proposals/claim/{token}` | Case-less "now" claim creates a negotiating session (real `session_id` + `needs_negotiation: true`; was `session_id: null`). No ICS for negotiating. +409 `{blocked_by_recap}` when claimer takes the candidate seat gated. |
| POST | `/api/practice/pair/claim` | Case-less token now returns `{session_id: <int>, needs_negotiation: true}` (was **409**). Guest + case-less → 409 (guests claim only instant links). +recap gate. |
| POST | `/api/practice` | +409 `{blocked_by_recap}` when the creator is a gated candidate (`user.id == candidate_id`), checked BEFORE the burned check. |
| POST | `/api/practice/{id}/finalize` | Response + feedback push `data` gain `next_recommendation` (B4 item shape or null) + `prefill_proposal {to_user_id, case_id}` (or null). Existing keys unchanged. |
| GET | `/api/v1/cases` | Each item gains `avg_rating` (float 1dp\|null), `run_count` (int), `done_for_you` (bool); response gains `open_count`, `done_count`. `total` + existing fields unchanged. |
| GET | `/api/v1/cases/{id}` | Gains `avg_rating`, `run_count`, `done_for_you`. |

## New migrations

- **028_negotiation_and_swap.sql** — `practice_sessions` state CHECK gains `'negotiating'` (preserves all prior states incl. `'missed'`); `case_id` + `rubric_template_id` DROP NOT NULL (negotiating sessions have no case yet — settled at accept); `swapped_from_session_id INTEGER REFERENCES practice_sessions ON DELETE SET NULL`; `case_negotiations` table (session_id FK CASCADE, proposed_case_id FK cases, by_user_id FK users, round, state CHECK pending/accepted/declined); `swap_invites` table (from_session_id FK CASCADE, initiator_id, invitee_id, state CHECK, new_session_id ON DELETE SET NULL, **partial unique index on one pending invite/session**).
- **029_recap_gate.sql** — `feedback` gains `viewed_at`, `closed_at`, `case_rating SMALLINT CHECK 1–5 nullable`, `feedback_thumbs BOOLEAN`; partial index `idx_feedback_open_recap` (finalized AND not-closed).

Both idempotent (ADD COLUMN IF NOT EXISTS; DROP NOT NULL no-op; DROP CONSTRAINT IF EXISTS + re-ADD; CREATE TABLE/INDEX IF NOT EXISTS).

**028 additions beyond the brief's literal 3 items (deliberate, within the 028 number budget):** `swap_invites` table (needed to persist the pending swap invite — the brief gave no other store) and the `DROP NOT NULL` on case_id/rubric_template_id (required for a `negotiating` session to exist — B1's DD-1 handed this seam to B3).

## Interfaces delivered (F3/F5 frontend + later phases consume — pinned)

**Recap-gate 409 contract (all five candidate entries):** HTTP 409 with body `{"detail": {"blocked_by_recap": <session_id>}}`. The client routes the user to that session's recap (GET `/api/practice/{sid}/feedback`), which they close via `/recap/close` to clear the gate. Never returned for interviewer seats, drills, or browsing.

**Negotiation `GET /api/practice/{id}/negotiation` payload:**
```
{session_id, session_state, your_role, whose_turn ('interviewer'|'candidate'|null),
 round_used (0|1|2),
 current_pick: {case_id, title, case_type, difficulty} | null,     // interviewer's round-1 pick
 candidate_counter: {case_id, title, case_type, difficulty} | null, // candidate's counter
 candidate_requested_case: {case_id, title, from_role} | null,      // ~always null (case-less origin)
 pick_sources?: {                                                   // interviewer-only
    recommended_for_candidate: [ {case_id, title, case_type, difficulty, why, rule} ],  // B4 shape
    interviewer_done_set:      [ {case_id, title, case_type, difficulty} ],
    library_allowed: true } }
```
`propose {case_id}` and `accept {case_id}` return the same negotiation view (accept returns the updated session row `{..., state:'lobby', case_id}`).

**Recap list `GET /api/v1/recaps`:** `{recaps: [ {session_id, case_id, case_title, interviewer_name, grade, finalized_at, viewed_at} ]}` oldest-first. **Close `POST /api/practice/{id}/recap/close`** body `{case_rating:1-5 REQUIRED, feedback_thumbs:bool|null}` → `{closed:true, gate_cleared:bool}`.

**Swap:** `POST /swap` → `{swap_invite_id, invitee_id}`. `POST /swap/accept` → `{accepted:true, session_id:<new negotiating session>, needs_negotiation:true}` (new interviewer = old candidate; new candidate = old interviewer; same mode; `swapped_from_session_id` set).

**Debrief seeding (finalize response + push `data`):** `next_recommendation` = B4 item `{case_id, title, case_type, difficulty, why, rule}` (excludes the just-burned case) or null; `prefill_proposal` = `{to_user_id: <interviewer_id>, case_id}` or null (the candidate schedules their next case with the same interviewer).

**Case aggregates (Library):** list items + detail carry `avg_rating` (float, 1 decimal, null if unrated), `run_count` (finalized sessions), `done_for_you` (burned for the caller). List response carries `open_count`/`done_count` over the filtered canonical set (render "4.1 · 12 runs" and the "DONE — YOURS TO INTERVIEW WITH" divider from these; §0.4). Legacy `case_votes` untouched.

**Repo interfaces (later phases):** `practice_sessions.create_negotiating_session(_within)`, `stamp_negotiated_case`; `feedback.candidate_gate(user_id)->Optional[int]`, `assert_candidate_gate_clear`, `RecapGateError.blocked_by_recap`, `list_unread_recaps`, `close_recap`; `case_stats.case_aggregates(case_ids, user_id)`; `cases.library_counts(filters, user_id)`; state `'negotiating'`; tables `case_negotiations`, `swap_invites`.

## Design decisions / deviations

- **DV-B3-SWAP (brief-literal):** the swap endpoint is **interviewer-initiated** ("authed interviewers only" — 403 for a guest or a candidate caller). New session reverses roles (new interviewer = old candidate, new candidate = old interviewer), same mode (A5). The recap gate is checked on the **new candidate (= old interviewer)** at accept. Spec §6.3 "both parties see the button" is superseded by the brief. Consequence (brief-literal, not a defect): the accepter (old candidate) can receive a 409 `{blocked_by_recap}` for the *initiator's* unread recap — the client should render this as "the other party has a recap to finish," not a raw recap link they can open.
- **Negotiation model:** round 1 = interviewer's opening pick (non-interviewer first-propose → 403); round 2 = candidate's single counter (round ≤ 2). The interviewer may accept any proposed case ("THEY KEPT THEIR PICK" = accept their own round-1 pick over a counter); the candidate may accept only the interviewer's pick. `negotiating→lobby` is driven ONLY by `stamp_negotiated_case` (atomic case+rubric) — the generic `/state` endpoint deliberately lacks that edge.
- **Recap close-out = required 1–5 rating** (design delta §0.5), NOT helpful-Yes/No; thumbs optional and authenticated-interviewer-only.
- **A scheduled case-less proposal** accepted early creates a `negotiating` session with a future `scheduled_at`. It is invisible to `list_upcoming_for_user` (which INNER-joins cases + filters scheduled/lobby/live) — acceptable for v1 (the accept response carries the `session_id`). Stale negotiating sessions are aborted by the 6-h `sweep_stale_sessions` (COALESCE(scheduled_at, created_at) window). See DEFERRED.

## Cross-phase notes for the orchestrator (before merging)

- **Shared files touched additively:** `webapp/main.py` (one `include_router(session_flow_routes.router)` + import — expect a merge touch with B6, which also adds routers), `webapp/routes/api_v1.py` (cases enrichment — expect a touch with sibling phases editing `/api/v1`), `webapp/routes/practice.py` / `proposals.py` / `practice_feedback.py`, `webapp/repositories/{proposals,pairing_tokens,practice_sessions,feedback,cases}.py`, `webapp/practice_states.py`.
- **New modules:** `webapp/routes/session_flow.py`, `webapp/repositories/{negotiations,swaps,case_stats}.py`. **New router registered once** in main.py.
- **Migrations 028/029** apply after 027; the only B3 migrations; `db/schema.sql` untouched.
- **Intentional existing-test changes (expect these diffs):** `test_b1_proposals_open.py` (two case-less methods now assert a real negotiating `session_id` + state), `test_b1_pairing_shortcode.py` (case-less pairing flips from 409 to 200 + negotiating). No other assertions weakened.

## DEFERRED

- **Negotiating sessions in Upcoming:** a scheduled case-less negotiating session does not surface in `GET /api/v1/sessions?scope=upcoming` / dashboard `next_session` (both INNER-join cases + filter scheduled/lobby/live). Rare path (scheduled + "interviewer decides"); the accept/claim response carries the session_id. Surfacing it needs a LEFT JOIN + `'negotiating'` in those queries — out of the case-set-happy-path scope.
- **Swap-accept crash residual (accepted caveat, mirrors `pairing_tokens.claim`):** `claim_invite` (atomic) runs before `create_negotiating_session`; a process crash between them leaves the invite `accepted` with `new_session_id` NULL and non-retryable. Rare crash window, low harm. Optional hardening: wrap claim+create+attach in one transaction with `SELECT … FOR UPDATE`.
- **Efficiency nits (non-blocking):** `library_counts` re-runs `_distinct_raw_industries` (already run by `search_cases` in the same request); `case_negotiations` has no `unique(session_id, round)` (safe — same-role self-race only, latest-wins, atomic settle).

## ESCALATIONS

None. No Fable consults were made or are queued.
