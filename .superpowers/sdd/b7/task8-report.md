# Task 8 report — readiness-signal-seams doc (OD-B7-1 required deliverable)

**Status:** DONE
**Branch:** bgap/b7-timeline (worktree /Users/thomaskgould/dev/bgap-b7)
**Commit:** `ce7c3d74e90e0c42d339e6eac8b39583d08109cb` — "Add readiness-signal seams note (OD-B7-1 required deliverable)"
**File created (only file in the commit):** `docs/superpowers/notes/2026-07-17-readiness-signal-seams.md`
**No `.env` or stray files staged.** Working tree clean after commit.

## What the doc covers (5 sections, AS-BUILT)

1. **What the stand-in computes** — `readiness_signal`, constants `READINESS_THRESHOLD=3.0`,
   `READINESS_MIN_CASES=3`, `DIAGNOSTIC_WINDOW_DAYS=60`; AND-logic on-track rule (needs_work when
   recent<3 OR weakest avg<3.0 OR no data); explicitly flagged as OD-B7-1 STAND-IN and
   firm-independent; per-firm tag `on_track`/`focus`/`early` via `timeline_service._firm_tag`
   (`EARLY_DEADLINE_DAYS=75`, DV-B7-5).
2. **Swap-point signature** — `webapp/readiness.py:readiness_signal(user_id: int) -> dict` with the
   6-key return contract (`label, ready, focus_dimension, recent_case_count, threshold, min_cases`);
   every caller enumerated: `timeline_service.timeline_view` (direct), `timeline_service.next_deadline_summary`
   (transitive via timeline_view), `readiness.reweight_payload` (direct). Contract a replacement must
   preserve is stated.
3. **Reweight seam** — `reweight_payload` derivation: focus from the signal, `suggested_drill_type`
   → `webapp/drills.py:_TYPES`, `extra_cases` from `dashboard.recommendations(user_id, [], limit=2)`
   (item key `case_id`; title key `title`). Plug-in point flagged.
4. **Data access points** — table with correct `file:symbol` for each: dimension_averages, _recent_case_count,
   history, practice_sessions.get_practice_session/count_finalized, _grade_trend/diagnostic,
   drill_attempts.record_attempt/streak_days/attempted_today (note B8 migration 034 adds scored fields),
   user_firms.list_tracked/get (status enum + snooze_until + result_recorded_at), firms.all_deadlines,
   dashboard.recommendations.
5. **B5 notification-settings seam** — `webapp/maintenance.py:_deadline_notifications_allowed` fail-open
   behavior, `session_reminders` category mapping, post-merge double-guard note.

Decisions documented in the doc: DV-B7-3 (/5 scale, threshold 3.0), DV-B7-5 (per-firm tag derivation),
DV-B7-4 (consistent FOCUS), OD-B7-1 (stand-in + single swap-point invariant).

## Step 2 grep — proof every cited file:symbol resolves

Plan's required 14 symbols:

```
webapp/timeline_service.py:55:def _firm_tag(signal: dict, block: dict | None) -> str:
webapp/timeline_service.py:63:def timeline_view(user_id: int, as_of: datetime.date) -> dict:
webapp/timeline_service.py:97:def next_deadline_summary(user_id: int, as_of: datetime.date) -> dict:
webapp/readiness.py:22:def _recent_case_count(user_id: int, window_days: int = DIAGNOSTIC_WINDOW_DAYS) -> int:
webapp/readiness.py:33:def readiness_signal(user_id: int) -> dict:
webapp/readiness.py:55:def suggested_drill_type(dimension: str | None) -> str:
webapp/readiness.py:68:def reweight_payload(user_id: int) -> dict:
webapp/repositories/dashboard.py:59:def dimension_averages(user_id: int, window: int = TREND_WINDOW) -> list[dict]:
webapp/repositories/dashboard.py:285:def _grade_trend(cur, user_id: int) -> dict:
webapp/repositories/dashboard.py:317:def diagnostic(user_id: int) -> dict:
webapp/repositories/user_firms.py:67:def list_tracked(user_id: int) -> list[dict]:
webapp/repositories/user_firms.py:108:def firms_needing_prompt(as_of: datetime.date) -> list[dict]:
webapp/repositories/firms.py:32:def all_deadlines() -> list[dict]:
webapp/maintenance.py:37:def _deadline_notifications_allowed(user_id: int) -> bool:
```

Extra symbols cited in the doc (all resolve):

```
webapp/repositories/dashboard.py:26:def history(user_id: int, limit: int = HISTORY_LIMIT) -> list[dict]:
webapp/repositories/dashboard.py:245:def recommendations(user_id: int, exclude_case_ids: list[int] = [], ...
webapp/repositories/practice_sessions.py:101:def get_practice_session(session_id: int) -> Optional[dict]:
webapp/repositories/practice_sessions.py:228:def count_finalized(user_id: int) -> int:
webapp/repositories/drill_attempts.py:34:def record_attempt(
webapp/repositories/drill_attempts.py:56:def streak_days(user_id: int) -> int:
webapp/repositories/drill_attempts.py:88:def attempted_today(user_id: int) -> bool:
webapp/repositories/user_firms.py:57:def get(user_id: int, firm_id: int) -> dict | None:
webapp/maintenance.py:58:async def sweep_deadline_prompts(as_of: datetime.date | None = None) -> int:
webapp/drills.py:24:_TYPES = ("mental_math", "market_sizing", "framework_recall")
webapp/timeline_service.py:20:EARLY_DEADLINE_DAYS = 75
webapp/readiness.py:17-19:READINESS_THRESHOLD = 3.0 / READINESS_MIN_CASES = 3 / DIAGNOSTIC_WINDOW_DAYS = 60
webapp/repositories/dashboard.py:19:TREND_WINDOW = 10
```

## Citations corrected during writing

None. Every `file:symbol` was verified against AS-BUILT code before it went into the doc; all
resolved on the first grep. No corrections were needed.

## DEFERRED / ESCALATIONS

None.
