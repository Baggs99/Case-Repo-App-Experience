# Task 4 — Claim endpoint + `claim_proposal` repo fn

**Status:** COMPLETE
**Branch:** bgap/b1-scheduling
**Commit:** bcab3070d32c66dea5034303db904cc8a2597228 — "Add proposal claim endpoint and claim_proposal repo fn"

## What changed
- `webapp/repositories/proposals.py` — added `_resolve_roles(prop)`, `_create_session_within(cur, prop, scheduled_at)`, and `claim_proposal(token, user_id)` (parameter named `token` per brief-pinned signature). All SQL parameterized; SELECT ... FOR UPDATE locks the proposal row.
- `webapp/routes/proposals.py` — added `POST /api/proposals/claim/{claim_token}` (auth guard `require_auth_api`, CSRF `_MUTATING`), calls `repo.claim_proposal(claim_token, user.id)` positionally.
- `tests/test_b1_proposals_open.py` — appended `class TestClaim` (7 tests); existing `TestOpenProposals` intact.

## TDD evidence

### Step 2 — RED (TestClaim before implementation)
`$PY -m pytest tests/test_b1_proposals_open.py::TestClaim -q`
```
6 failed, 1 passed, 21 warnings in 0.77s
FAILED ...TestClaim::test_creator_cannot_claim
FAILED ...TestClaim::test_requires_auth
FAILED ...TestClaim::test_claim_now_with_case_auto_accepts_and_creates_session
FAILED ...TestClaim::test_claim_scheduled_stays_pending
FAILED ...TestClaim::test_claim_case_less_now_needs_negotiation
FAILED ...TestClaim::test_double_claim_409
```
(the lone pass, `test_unknown_token_404`, was vacuous — no route means a genuine 404, matching the expected 404). Confirms the claim route/repo fn were absent.

### Step 5 — GREEN (after Steps 3+4)
Each file on its own:
```
tests/test_b1_proposals_open.py  ...........  11 passed   (4 TestOpenProposals + 7 TestClaim)
tests/test_queues_proposals.py   ........      8 passed   (unchanged flow)
```

### Full suite
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/ -q`
```
373 passed in 4.64s
```
Matches the plan target exactly: 366 (Tasks 1–3) + 7 (TestClaim) = 373, zero failures, zero skips.

## Behaviour verified
- Creator claiming own link → 409 (`user_id == from_user_id`).
- Double-claim → 409 (second claimer sees `to_user_id` already set).
- Unauthenticated claim → 401 (auth guard).
- Unknown token → 404.
- "now" proposal with a case → auto-accepts, creates a session, roles resolved from `from_role` (interviewer=creator).
- Scheduled proposal → stays `pending`, `session_id` None, claimer bound as `to_user_id` (appears in claimer inbox).
- Case-less "now" proposal → accepted, `session_id` None, `needs_negotiation` True, NO session created (DD-1: sessions stay case-bound).

## Concerns
- **Two-file-pair ordering artifact (not a product bug, not fixed here):** running ONLY `pytest tests/test_b1_proposals_open.py tests/test_queues_proposals.py` together fails `test_queues_proposals.py::test_accept_creates_session_and_ics` with `0 != 2` email files. Root cause: `TestClaim` is the first B1 class to create a session and its `tearDownClass` exits the app lifespan (`cls._ctx.__exit__`); the queues test's background `_send_invites` then hits the shut-down global connection pool and its broad `except Exception: logger.exception(...)` swallows the error, so zero email files are written. In the FULL suite other test files run between the two (alphabetical), the pool is healthy by the time queues runs, and the assertion passes → 373 green. The repo/route code for Task 4 is unaffected; the fragility is pre-existing test-isolation coupling around the module-level pool + lifespan shutdown. No test removed, nothing to change for Task 4.

## Deferred
- None.
