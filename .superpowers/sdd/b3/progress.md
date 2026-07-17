# B3 Session-flow — progress ledger

Branch: bgap/b3-sessionflow · DB: caserepo_bgap_b3
Baseline: 545 passed, 0 failures (finish line = 545 + N new tests)

## Bootstrap
- DB created, schema + migrations 020-027 applied, .env pointed at caserepo_bgap_b3 (gitignored), seeded a/b/c@yale.edu. Baseline 545 green — evidence: `pytest tests/ -q` -> `545 passed`.

## Key findings (exploration, pre-plan)
- Entry contract (DD-1): `proposals.respond` + `proposals.claim_proposal` case-less → currently return session_id=None+needs_negotiation; `pairing.claim` case-less → 409. B3 converts all three to create a `negotiating` practice_session.
- `get_practice_session` INNER JOINs cases → negotiating (case_id NULL) rows vanish. MUST switch to LEFT JOIN cases.
- practice_sessions.case_id + rubric_template_id are NOT NULL → migration 028 must DROP NOT NULL on both (necessary for negotiating sessions).
- state CHECK today: scheduled|lobby|live|debrief|finalized|aborted|missed. mode: remote|in_person (default remote). feedback: session_id UNIQUE, +rubric_json/grade/notes_md/finalized_at.
- WS: `hub.broadcast_session_update(session_id)` (webapp/signaling.py) via BackgroundTasks — reuse.
- require_session_participant (webapp/auth/guest.py) + _session_or_404 (practice.py) gate all session endpoints; is_guest surfaced as interviewer_is_guest/candidate_is_guest.
- Tests: import _DB_URL/_HTTPX/_READY from tests/test_ws_integration.py; TestClient + create_session cookie; no CSRF header needed. Intentionally update: test_b1_proposals_open.py::test_claim_case_less_now_needs_negotiation + ::test_accept_case_less_scheduled_needs_negotiation; test_b1_pairing_shortcode.py case-less pairing.

## Locked decisions
- Migration 028 also adds `swap_invites` table (needed for pending-swap persistence; within 028 number budget).
- Negotiation: round1=interviewer opening pick; round2=candidate one counter (round<=2). accept(case_id): interviewer may accept any proposed case (keep pick or take counter); candidate may accept ONLY the interviewer's pick. On accept: stamp case_id+rubric_template_id, state->lobby, broadcast. pick_sources interviewer-only.
- Swap (DV-B3-SWAP, brief-literal): initiator=session interviewer, non-guest (403 guest/non-interviewer); state debrief/finalized; counterpart non-guest. New session reverses roles (new interviewer=old candidate, new candidate=old interviewer), same mode (A5), swapped_from set, state negotiating. Recap gate on new candidate(=old interviewer) at accept.
- Recap gate: candidate_gate(user_id)->Optional[sid]=oldest feedback finalized AND closed_at IS NULL where user is candidate. Enforce 409 {blocked_by_recap:sid} on: create_practice(as candidate), proposal accept(as candidate), proposal claim(as candidate), pair claim, swap accept. RecapGateError(subclass TransitionError) raised in repo; routes emit structured body.
- Recap close: case_rating REQUIRED 1-5; thumbs only if interviewer non-guest; candidate-only; close once. Debrief close-out == same endpoint.
- Case aggregates: avg case_rating(1dp)+run_count+done_for_you per case on api_v1 list/detail; open_count/done_count on list. New repo case_stats + cases.library_counts (dedup CTE).
- Debrief seeding: post_finalize response + feedback push gain next_recommendation (B4 shape, exclude burned case) + prefill_proposal {to_user_id: interviewer_id, case_id: rec}.

## Tasks (plan: docs/superpowers/plans/2026-07-17-bgap-b3-plan.md)
- T1 migrations 028/029
- T2 state machine + practice_sessions plumbing (LEFT JOIN, create/stamp negotiating)
- T3 recap gate core (feedback repo)
- T4 convert case-less entries -> negotiating + gate on 5 candidate entries
- T5 negotiation endpoints + repo + WS
- T6 recap endpoints (list/viewed/close)
- T7 role swap (swap_invites)
- T8 debrief seeding (finalize + push)
- T9 case rating aggregates on Library payloads

Status: plan written + self-reviewed + Opus plan-review (CHANGES-REQUESTED, 0 Critical / 2 Important) — both fixed (gate-error test assertion; claim-route ICS guard for negotiating), minors folded (dead code, gate-before-burned placement, expanded accept tail). Commit 2a55674. Executing tasks.

## Task ledger (per subagent-driven-development)
- Task 1: complete (2a55674..e2551fe, review CLEAN) — migrations 028/029 applied+idempotent, 4 tests green.
- Task 2: complete (52ad8b2..08e0eb6, review CLEAN + header-doc minor fixed) — STATES/edges, LEFT JOIN cases, create/stamp negotiating helpers, sweep. 17+30 tests green.
- Task 3: complete (8ea0733..23e8863, review CLEAN) — recap gate repo (candidate_gate/assert/list/viewed/close + RecapGateError). 4+5 green. Minor logged: list oldest-first test under-covers ordering (correct SQL; later tests cover).
- Task 4: complete (bc1a8f5..5352c59, review CLEAN + 2 stale-docstring minors fixed) — DD-1 conversion (respond/claim_proposal/pairing.claim -> negotiating) + recap gate on 5 candidate entries (dict 409 {blocked_by_recap}, RecapGateError before TransitionError, gate-before-burned). Full suite 558 green.
- Task 5: complete (d614464..92fe948, review CLEAN) — negotiation repo+endpoints (GET/propose/accept), pick_sources interviewer-only, round<=2, candidate-can't-self-counter (403), WS broadcast on propose+accept, router registered. 9+14 green. Impl fixed a 403/409 plan contradiction (candidate-before-pick=403); plan sample synced. Minor logged: no unique idx on case_negotiations(session_id,round) — harmless (self-race only, latest-wins, atomic settle).
- Task 6: complete (40c89b7..28da16f, review CLEAN) — recap endpoints (GET /api/v1/recaps require_auth_api; recap/viewed + recap/close candidate-only, required 1-5, thumbs guest-guarded, first-close). Impl fixed another plan test-ordering bug (list test seeds own recap). 11 + 17 green.
- Task 7: complete (bebc7d5..62b2d65 + race-fix 25fdc3e, review CHANGES-REQUESTED->RESOLVED) — role swap (swaps.py + endpoints). DV-B3-SWAP: interviewer-initiated non-guest, reversed roles, same mode, swapped_from, gate on new candidate (old interviewer). FIX: concurrent double-accept race closed via atomic claim_invite before session create (test_claim_invite_single_winner). 4 swap tests green. Residual (non-blocking, mirrors pairing.claim caveat): rare crash between claim+create -> invite accepted, new_session_id NULL, non-retryable.
- Task 8: complete (25fdc3e..9006dc5, review CLEAN + docstring minor fixed) — debrief seeding: finalize response + push gain next_recommendation (excl burned) + prefill_proposal {to_user_id: interviewer}. 6 green.
- Task 9: complete (02e7216..10d2879, review CLEAN) — case_stats.case_aggregates + cases.library_counts; api_v1 list/detail enriched (avg_rating 1dp, run_count, done_for_you, open_count/done_count). case_votes untouched. 2+38 green. Minor: _distinct_raw_industries called twice/req (non-blocking).
