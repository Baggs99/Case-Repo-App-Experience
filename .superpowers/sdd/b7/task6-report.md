# B7 Task 6 — Extend GET /api/v1/dashboard with diagnostic + timeline

**Status:** DONE
**Branch:** bgap/b7-timeline (worktree /Users/thomaskgould/dev/bgap-b7)
**Commit:** 53f5e826e4829498463f28161f5de62c26283db0

## What changed
- `tests/test_b7_timeline_api.py` — appended `TestDashboardTimelineKeys` class
  (verbatim from plan Task 6 Step 1). Existing `TestTimelineApi` class untouched.
- `webapp/routes/api_v1.py` — additive extension only:
  - `from webapp import timeline_service` (new import, in the `from webapp import` group).
  - Two new keys in the `dashboard` handler dict:
    `"diagnostic": dashboard_repo.diagnostic(user.id)` and
    `"timeline": timeline_service.next_deadline_summary(user.id, datetime.now(timezone.utc).date())`.
  - `datetime`/`timezone` were already imported (line 9, used by /drills/daily).

## TDD evidence

### Step 2 — RED (before implementation)
Command:
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 $PY -m pytest "tests/test_b7_timeline_api.py::TestDashboardTimelineKeys" -q`
Result: **1 failed** —
`AssertionError: 'diagnostic' not found in {'sessions_finalized': 0, ..., 'dimension_averages': [], 'recommendations': [...]}`
(fails at `self.assertIn("diagnostic", d)` as the plan predicted).

### Step 4 — GREEN (after implementation)
Same command → **1 passed, 9 warnings in 0.56s**.

### Step 5 — Regression guard
Command:
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 $PY -m pytest tests/test_api_v1_sessions.py tests/test_dashboard.py -q`
Result: **12 passed, 25 warnings in 0.70s** — existing dashboard assertions unaffected.

## Additive-only confirmation (contract §5)
`git diff` on webapp/routes/api_v1.py shows **only additions**: +1 import line and
+2 dict keys (with a 2-line comment). Zero deletions, zero modifications to any
other part of the file. `git commit` reported `2 files changed, 50 insertions(+)`
— no deletions. Auth guard (`require_auth_api` on `/dashboard`) unchanged.

## Notes / concerns
- Prerequisites verified present before starting: `dashboard.diagnostic` (dashboard.py:317)
  and `timeline_service.next_deadline_summary` (timeline_service.py:97).
- Only the two named files were staged/committed; `.env` was not committed.
- No deferred items.
