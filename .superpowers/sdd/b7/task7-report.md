# B7 Task 7 report — Deadline-passed push from the maintenance loop (daily guard + B5 seam)

**Status:** COMPLETE — clean.
**Commit SHA:** `e56d529f08dc759aff8a5f1c4415c562fe2fba77`
**Branch:** `bgap/b7-timeline` (worktree `/Users/thomaskgould/dev/bgap-b7`)
**Files committed:** `webapp/maintenance.py` (rewrite, additive), `tests/test_b7_deadline_prompt.py` (new). No `.env` staged.

## What changed

`webapp/maintenance.py` rewritten per plan Task 7 Step 3 (full new contents):

- Extended 4-line header docblock (Purpose/Inputs/Outputs/Run) to mention §B7 deadline prompts.
- New imports: `datetime`, `webapp.db.get_pool`, `webapp.push.events.push_to_user`, `webapp.repositories.user_firms as user_firms_repo`.
- Module global `_deadline_prompt_last_date: datetime.date | None = None` (daily guard; tests reset to `None`).
- `_deadline_notifications_allowed(user_id)` — B5 seam via `to_regclass('notification_settings')`; parameterized `%(u)s` query on `session_reminders`; fail-open (`return True`) when table absent, when no row, and on ANY exception.
- `sweep_deadline_prompts(as_of=None) -> int` — async; iterates `user_firms_repo.firms_needing_prompt(as_of)`, awaits `push_to_user(...)` (imported into the maintenance namespace so the test patches `webapp.maintenance.push_to_user`), then `mark_prompted(...)` with a 7-day snooze; returns count pushed.
- `_guarded_deadline_prompts(as_of=None)` — daily guard; runs the sweep at most once per calendar day.
- `run_maintenance_pass(settings, *, as_of=None)` — keyword-only `as_of`; keeps the EXACT existing sweep order (expired → missed → aborted → starting_soon) and return keys, ADDING `deadline_prompts`.
- `maintenance_loop` unchanged.

## Commands + key output

### Step 2 — new test fails (red)
`DATABASE_URL=… $PY -m pytest tests/test_b7_deadline_prompt.py -q`
```
3 failed, 6 warnings in 0.74s
FAILED ... test_b5_seam_fails_open_without_settings_table
FAILED ... test_daily_guard_runs_once_per_day
FAILED ... test_push_fires_then_snoozes
```
Failure cause: `AttributeError: <module 'webapp.maintenance'> does not have the attribute 'push_to_user'` (and no `sweep_deadline_prompts` / `_deadline_notifications_allowed`) — module genuinely lacked all new attributes. Expected red per plan.

### Step 4 — new test passes (green)
`DATABASE_URL=… $PY -m pytest tests/test_b7_deadline_prompt.py -q`
```
3 passed, 6 warnings in 0.53s
```

### Step 5 — CRITICAL regression guard
`DATABASE_URL=… $PY -m pytest tests/test_b1_maintenance.py -q`
```
1 passed, 6 warnings in 0.53s
```
The existing test calls `run_maintenance_pass(load_settings())` positionally; the new keyword-only `as_of` defaults to `None`, so the positional call is unaffected. That test asserts DB rows, not the return dict, so the added `deadline_prompts` key is ignored.

### Step 6 — commit
Only `webapp/maintenance.py` + `tests/test_b7_deadline_prompt.py` staged; `git status` clean after commit.

## Fail-open confirmation (B5 seam)

Confirmed. `notification_settings` does not exist on this branch (B5 unmerged). `test_b5_seam_fails_open_without_settings_table` asserts `_deadline_notifications_allowed(aid)` returns `True` and passes. The seam returns `True` on three paths: (1) `to_regclass(...)` is NULL (table absent), (2) no settings row for the user, (3) any exception (logged via `logger.exception`, then `return True`). Parameterized query only (`%(u)s`).

## Deviations

None. File written verbatim from plan Task 7 Step 3; test written verbatim from Step 1.

## Notes

- `push_to_user` self-guards when APNs is unconfigured (no-op in dev/tests even if unpatched), so the sweep is safe to run against the shared dev DB.
- Correctness against double-push comes from the per-firm `snooze_until` throttle (verified by `test_push_fires_then_snoozes`: second sweep returns 0); the daily guard only avoids ~1440 needless scans/day (verified by `test_daily_guard_runs_once_per_day`).
