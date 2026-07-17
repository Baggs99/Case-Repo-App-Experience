# Task 6 report — A3 expiry sweeps + missed sessions

**Status:** DONE
**Branch:** bgap/b1-scheduling
**Commit:** a7ba0b258d8ac5e2a9b1c7f28440301ea7117d6b — "Rework proposal expiry to A3 windows; add missed-session sweep"

## Files changed
- `webapp/repositories/proposals.py` — removed `EXPIRY_DAYS = 7`; rewrote `sweep_expired()` → `sweep_expired(now_expiry_min: int = 120)` with A3 semantics (now-proposals expire N min after creation; scheduled expire at earliest proposed start; countered expire at earliest counter time). All SQL parameterized (`make_interval(mins => %s)`, `jsonb_array_length`, `jsonb_array_elements_text`).
- `webapp/repositories/practice_sessions.py` — added `sweep_missed(missed_after_min: int = 60)` immediately after `sweep_stale_sessions`; marks `scheduled`/`lobby` sessions with `scheduled_at + N min < NOW()` → `'missed'` (skips NULL scheduled_at). Left `sweep_stale_sessions` untouched.
- `tests/test_b1_expiry_missed.py` — new, 8 tests (5 proposal-expiry + 3 missed-session), exact Task 6 Step 1 code.
- `tests/test_queues_proposals.py` — DD-2: replaced `test_expiry_sweep` with `test_expiry_sweep_scheduled_past_start` + `test_expiry_sweep_now_proposal`. No other method touched. Accept route already calls `sweep_expired()` with default 120 — no route change needed.

## Step 2 — fail before implementation
`DATABASE_URL=... $PY -m pytest tests/test_b1_expiry_missed.py -q`
```
7 failed, 1 passed, 6 warnings in 0.68s
E   ImportError: cannot import name 'sweep_missed' from 'webapp.repositories.practice_sessions'
FAILED ...test_countered_proposal_expires_at_earliest_counter
FAILED ...test_fresh_now_proposal_survives
FAILED ...test_now_proposal_expires_after_window
FAILED ...test_now_session_without_scheduled_at_not_missed
FAILED ...test_scheduled_proposal_expires_at_earliest_start
FAILED ...test_session_missed_past_start_plus_window
FAILED ...test_session_not_missed_before_window
```
(`test_future_scheduled_survives` incidentally passed under the old 7-day rule: fresh row with a future proposed time stays `pending`. Confirms the pre-implementation baseline was wrong for every case the new semantics govern.)

## Step 6 — pass after implementation
`DATABASE_URL=... $PY -m pytest tests/test_b1_expiry_missed.py tests/test_queues_proposals.py -q`
```
17 passed, 39 warnings in 1.01s
```

## Full suite (source of truth)
`DATABASE_URL=... $PY -m pytest tests/ -q`
```
389 passed, 384 warnings in 9.96s
```
Matches expected 389 (380 baseline + 8 new in test_b1_expiry_missed.py + net 1 from replacing test_expiry_sweep with two methods). Zero failures, zero skips.

## Concerns
None. sweep_missed function is implemented but not yet wired into the maintenance loop — Task 7 handles ordering (sweep_missed BEFORE sweep_stale_sessions). All SQL parameterized. Warnings are pre-existing `datetime.utcnow()` deprecations unrelated to this task.
