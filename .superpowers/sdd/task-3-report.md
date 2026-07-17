# Task 3 — Proposal create: nullable case/recipient + claim_token

**Status:** COMPLETE. All steps done under strict TDD (red → green → commit).

**Commit:** `62fb963` — "Add open-link and case-less proposals with claim_token"
Branch: `bgap/b1-scheduling` (worktree `/Users/thomaskgould/dev/bgap-b1`).

## Files changed
- `webapp/repositories/proposals.py` — `import secrets`; extended `_COLS`
  (adds `p.claim_token, p.counter_times_json, p.counter_by, p.countered_at`);
  rewrote `create_proposal` (nullable `to_user_id`/`case_id`, mints
  `secrets.token_urlsafe(24)` claim_token iff `to_user_id is None`, burned-check
  deferred when case or candidate unknown).
- `webapp/routes/proposals.py` — `ProposalBody.to_user_id`/`case_id` now
  `Optional[int] = None`; handler skips the case-404 lookup when `case_id is
  None` and only pushes the recipient notification for named-recipient proposals.
- `tests/test_b1_proposals_open.py` (created) — Task 3 `TestOpenProposals` only
  (file is appended to in Tasks 4/5).

## Step 2 — RED (before impl)
`DATABASE_URL=... $PY -m pytest tests/test_b1_proposals_open.py -q`
```
4 failed, 13 warnings in 0.70s
FAILED ...test_bad_case_still_404
FAILED ...test_case_less_proposal_allowed
FAILED ...test_named_recipient_has_no_claim_token
FAILED ...test_open_link_returns_claim_token
```
Representative failure: `AssertionError: 422 != 200 : {"detail":[{"type":"missing","loc":["body","to_user_id"],"msg":"Field required",...}]}` — old `ProposalBody` required `to_user_id`.

## Step 5 — GREEN (after impl)
Task 3 tests: `tests/test_b1_proposals_open.py` → **4 passed in 0.57s**
Regression (existing named-recipient flow): `tests/test_queues_proposals.py` → **8 passed in 0.71s** (unchanged).

## Full suite
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/ -q`
```
366 passed in 4.45s
```
Baseline 362 + 4 new = 366. Zero failures.

## Self-review
- Parameterized SQL only: the `create_proposal` INSERT binds all 7 values via
  `%s`. The sole f-string is `_COLS.replace('p.', '')`, a fixed column list
  (no user data). Confirmed.
- Additive/no reformatting: only the three targeted regions in the repo and two
  in the route changed; unrelated code untouched (verified via `git diff`).

## Concerns
None. Later tasks (4/5) append `TestClaim`/`TestCounter` to the same test file
and extend `respond`/routes; deferred as designed.
