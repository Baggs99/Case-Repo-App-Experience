# Task 5 — One-round counter + counter-accept

**Status:** COMPLETE. Committed on `bgap/b1-scheduling` as `193e09e`.

## What changed
- `webapp/repositories/proposals.py`
  - Added `counter_proposal(proposal_id, user_id, times)` — recipient-only, pending-only, one round; writes `state='countered'`, `counter_times_json`, `counter_by`, `countered_at`; returns the countered row (incl. `from_user_id` for the push). All SQL parameterized.
  - Replaced `respond(...)` with the extended version: `pending` → recipient acts; `countered` → original proposer acts with a `counter_time` that must be a member of the stored counter times (aware-datetime set membership via `datetime.fromisoformat`); DV-11 non-participant → 404 in the else-branch (participant sees 409 "already {state}"); case-less accept sets `session_id` NULL and returns `needs_negotiation=True`.
- `webapp/routes/proposals.py`
  - `RespondBody` gained `time: Optional[datetime]` (chosen counter time).
  - Added `CounterBody` (`times`, `min_length=1`, `max_length=repo.MAX_PROPOSED_TIMES` → 422 when >3).
  - `accept_proposal` handler body replaced from the `repo.respond(...)` line down; **kept the existing first line `repo.sweep_expired()`** (Task 6 expiry tests depend on accept sweeping first). Now handles the `session_id is None` case-less branch (returns `{"accepted": True, "session_id": None, "needs_negotiation": True}` + notifies the counterpart).
  - Added `POST /api/proposals/{proposal_id}/counter` route with `dependencies=_MUTATING` and `require_auth_api`; pushes `data.kind == "proposal_countered"` to `prop["from_user_id"]`.
- `tests/test_b1_proposals_open.py` — appended `class TestCounter` (7 tests, incl. `test_accept_case_less_scheduled_needs_negotiation`).

## Step 2 — RED (before implementation)
`pytest tests/test_b1_proposals_open.py::TestCounter -q`:
```
6 failed, 1 passed, 28 warnings in 0.99s
FAILED ...TestCounter::test_accept_case_less_scheduled_needs_negotiation
FAILED ...TestCounter::test_accept_of_counter_requires_a_listed_time
FAILED ...TestCounter::test_counter_times_capped_at_three
FAILED ...TestCounter::test_one_round_only
FAILED ...TestCounter::test_recipient_cannot_accept_countered
FAILED ...TestCounter::test_recipient_counters_then_proposer_accepts
```
(The 1 pass is `test_only_recipient_may_counter` — coincidental: the not-yet-defined counter route returns 404 for both callers, which matches the expected 404.)

## Step 4 — target files GREEN
`pytest tests/test_b1_proposals_open.py tests/test_queues_proposals.py -q`:
```
1 failed, 25 passed  (FAILED test_queues_proposals.py::...::test_accept_creates_session_and_ics)
```
This is the KNOWN pre-existing dev email-filename collision flake, confirmed NOT a regression: run in isolation the same test passes —
`pytest tests/test_queues_proposals.py::...::test_accept_creates_session_and_ics -q` → `1 passed`.
The full suite (below) is the source of truth and is fully green.

## Step 5 — FULL SUITE
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/ -q`:
```
380 passed, 382 warnings in 5.07s
```
Baseline 373 + 7 TestCounter tests = 380. Zero failures.

## Step 6 — Commit
```
193e09e8cca93051dd689c9113f94990c8f73dd8  Add one-round proposal counter + counter-accept flow
 3 files changed, 236 insertions(+), 26 deletions(-)
```
Staged exactly: `webapp/repositories/proposals.py webapp/routes/proposals.py tests/test_b1_proposals_open.py`. No push. Working tree clean.

## Concerns
None. The only red in the isolated 2-file pair is the documented email-filename collision flake, which passes in isolation and in the full suite.
