# Task 9 — api_v1 proposals parity

**Status:** COMPLETE
**Commit:** c49cd82 — "api_v1 proposals parity: claim_token, counter fields, countered-sent"
**Branch:** bgap/b1-scheduling

## Files changed
- `webapp/repositories/proposals.py` — `inbox()` `JOIN cases` → `LEFT JOIN cases`; added `list_for_api(user_id)`.
- `webapp/routes/api_v1.py` — `list_proposals` rewritten to use `list_for_api`, emits new item shape, drops `sweep_expired()` call.
- `tests/test_b1_api_v1_proposals.py` — new (2 tests).
- `tests/test_api_v1_sessions.py` — DD-4: removed `assertNotIn("state", item)`; added `assertIn("state")` + `assertIn("direction")`.

## Step 2 — fail-first (before impl)
```
E   AssertionError: 'claim_token' not found in {'id': 311, 'from_name': 'Alice Dev',
    'from_role': 'interviewer', 'case_id': 484, 'case_title': 'B1 V1 Case', ...}
FAILED tests/test_b1_api_v1_proposals.py::...::test_proposer_sees_countered_proposal
FAILED tests/test_b1_api_v1_proposals.py::...::test_received_pending_has_counter_and_claim_fields
2 failed, 13 warnings in 0.57s
```
- `test_received_pending_has_counter_and_claim_fields`: curated inbox item lacked claim_token/state/counter_times/direction.
- `test_proposer_sees_countered_proposal`: inbox() only returned received-pending, so the proposer never saw her own countered proposal (0 matches).

## Step 6 — targeted pass (after impl)
`tests/test_b1_api_v1_proposals.py tests/test_api_v1_sessions.py tests/test_queues_proposals.py`
```
19 passed, 52 warnings in 0.80s
```

## Full suite
```
401 passed, 407 warnings in 5.31s
```
399 baseline + 2 new = 401. Zero failures, zero previously-green regressions.

## PAYLOAD CHANGES — /api/v1/proposals item shape (iOS consumes these)
Fields ADDED to each proposal item:
- `direction` — string, `"received"` (to_user_id = caller, pending) or `"sent"` (from_user_id = caller, countered).
- `state` — string, `"pending"` or `"countered"` (previously excluded per old curated shape).
- `claim_token` — string|null; non-null only for open "send-a-link" proposals not yet claimed.
- `counter_times` — array[iso8601]|null; the recipient's one-round counter times (from `counter_times_json`).
- `counter_by` — int|null; user id who countered.
- `countered_at` — iso8601|null; when the counter was made.

Fields UNCHANGED (still present): `id`, `from_name`, `from_role`, `case_id`, `case_title`, `case_type`, `difficulty`, `message`, `proposed_times`, `created_at`.

New rows NOW RETURNED: sent-countered proposals (from_user_id = caller AND state = 'countered'). Previously the list was received-pending only. `case_title`/`case_type`/`difficulty` may be `null` for case-less ("interviewer decides") proposals — LEFT JOIN cases keeps the row instead of dropping it.

Behavior change: the redundant page-load `sweep_expired()` was removed from this handler (sweeps run on the 60-s maintenance loop as of Task 7).

## Concerns
None. All SQL parameterized (`%(u)s` named param). The existing test_api_v1_sessions proposal (Bob→Alice, pending) still returns for Alice as `direction="received"`, so the curated-shape test remains valid under the new list_for_api source.
