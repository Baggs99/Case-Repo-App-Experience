# Readiness signal — stand-in + swap seams (B7 / OD-B7-1)

**Status:** the readiness signal shipped in B7 is a **documented STAND-IN** (execution
brief §6, OD-B7-1). Real usage data does not exist yet, so `readiness_signal` computes a
crude rubric-vs-threshold heuristic. It is isolated behind **one swap-point function that
every caller goes through**, so a smarter implementation can replace the body without
touching any caller. This note is the swap map: what the stand-in computes, the contract
a replacement must preserve, the reweight derivation, every data access point available in
code today (`file:symbol` each), and the B5 notification-settings seam.

All `file:symbol` references below are AS-BUILT and were verified with the Step 2 grep (see
the report). Paths are repo-relative.

---

## 1. What the stand-in computes

`webapp/readiness.py:readiness_signal(user_id)` — firm-independent, no usage data required.

Constants (all in `webapp/readiness.py`, module scope):

| Constant | Value | Meaning |
| --- | --- | --- |
| `READINESS_THRESHOLD` | `3.0` | Weakest-dimension floor, on the **/5** scale (DV-B7-3). |
| `READINESS_MIN_CASES` | `3` | Minimum recent candidate-finalized cases to be "ready". |
| `DIAGNOSTIC_WINDOW_DAYS` | `60` | Recent-case window (days) for the count below. |

Logic (exact, AS-BUILT):

- `dims = dashboard_repo.dimension_averages(user_id)` — per-dimension averages on the **/5**
  scale, **ordered ascending** (weakest dimension first). `focus_dimension = dims[0]["dimension"]`
  (or `None` when there are no scored dimensions).
- `recent = _recent_case_count(user_id)` — candidate-finalized sessions in the last
  `DIAGNOSTIC_WINDOW_DAYS` days.
- `weakest_avg = float(dims[0]["avg_score"])` (or `None`).
- **`on_track` is true only when ALL hold:** `recent >= READINESS_MIN_CASES` **AND**
  `weakest_avg is not None` **AND** `weakest_avg >= READINESS_THRESHOLD`.
- Therefore the result is **`needs_work` when** `recent_case_count < 3` **OR** the weakest
  dimension average `< 3.0` **OR** there is no rubric data at all; else **`on_track`**.

The signal is **firm-independent** by design (OD-B7-1). The per-firm display badge shown on the
timeline is a thin **presentation** derivation layered on top of this signal — it is **not**
part of the swap-point:

- `webapp/timeline_service.py:_firm_tag(signal, block)` (DV-B7-5), constant
  `webapp/timeline_service.py:EARLY_DEADLINE_DAYS = 75`.
- Returns **`early`** when the firm's deadline is unpassed and `days_remaining > 75`;
  otherwise **`on_track`** when `signal["ready"]` else **`focus`**.
- The hand-authored persona tags (ON PACE / PUSH QUANT / EARLY) are illustrative — the code
  emits `on_track` / `focus` / `early` and is not matched byte-for-byte.

---

## 2. The swap-point signature (the one seam)

```
webapp/readiness.py:readiness_signal(user_id: int) -> dict
```

Return shape (the **contract** a replacement MUST preserve — same keys, same types):

| Key | Type | Notes |
| --- | --- | --- |
| `label` | `'on_track' \| 'needs_work'` | The bucket. |
| `ready` | `bool` | `True` iff `label == 'on_track'`. Drives `_firm_tag`. |
| `focus_dimension` | `str \| None` | Weakest rubric dimension; `None` when no data. |
| `recent_case_count` | `int` | Candidate-finalized sessions in the 60-day window. |
| `threshold` | `float` | Echoes `READINESS_THRESHOLD` (3.0) for the client. |
| `min_cases` | `int` | Echoes `READINESS_MIN_CASES` (3) for the client. |

**Every caller goes through this function** — swapping the body (e.g. a learned model) is
transparent to all of them as long as the return keys above are unchanged:

- `webapp/timeline_service.py:timeline_view` — calls `readiness.readiness_signal(user_id)`
  directly (readiness.py invoked at timeline_service line 66); puts it at `payload["readiness"]`
  and feeds it to `_firm_tag` per row.
- `webapp/timeline_service.py:next_deadline_summary` — reaches the signal **transitively** by
  calling `timeline_view(user_id, as_of)` and reusing its `firms[*].readiness_tag`; it does not
  re-call `readiness_signal` itself.
- `webapp/readiness.py:reweight_payload` — calls `readiness_signal(user_id)` directly for
  `focus_dimension` (see §3).

There is no other computation of the on-track / needs-work bucket anywhere in the codebase; a
grep for `readiness_signal` finds only these call sites. That is the invariant OD-B7-1 requires.

**Where a smarter implementation plugs in:** replace the body of `readiness_signal` only. It may
draw on any of the §4 data access points (drill accuracy, grade trend, timeline outcomes, etc.).
It must keep returning the six keys above. Callers, the timeline payload, and `_firm_tag` need no
change. If a replacement wants firm-specific readiness, it should still return the firm-independent
signal here and extend `_firm_tag` (the presentation layer), not fork the swap-point.

---

## 3. The reweight seam ("No offer → reweight")

```
webapp/readiness.py:reweight_payload(user_id: int) -> dict
```

Return shape: `{focus_dimension: str | None, suggested_drill_type: str, extra_cases: list[int]}`.
This is the DESIGN DELTA "No offer → reweight response" — the post-deadline flow ends in plan
reweighting, never a forum handoff.

Derivation (AS-BUILT), each part a documented seam:

1. **`focus_dimension`** — taken from `readiness_signal(user_id)["focus_dimension"]` (the weakest
   `/5` dimension). Same source as readiness and the diagnostic, so FOCUS is consistent everywhere
   (DV-B7-4).
2. **`suggested_drill_type`** — `webapp/readiness.py:suggested_drill_type(focus_dimension)` maps a
   rubric dimension name to exactly one of the **3 existing drill generators** in
   `webapp/drills.py:_TYPES = ("mental_math", "market_sizing", "framework_recall")`. Substring
   rules: `None` → `mental_math`; name contains `siz` → `market_sizing`; contains
   `quant`/`math`/`numer` → `mental_math`; otherwise → `framework_recall`. Substring matching keeps
   it robust to rubric renames.
3. **`extra_cases`** — `[r["case_id"] for r in dashboard_repo.recommendations(user_id, [], limit=2)]`.
   That is the B4 recommendation engine, `webapp/repositories/dashboard.py:recommendations`
   (item key is `case_id`; the human-readable title key is `title`). `limit=2` = "two extra cases
   before BCG" from the persona.

**Where a smarter engine plugs in:** `suggested_drill_type` is a stand-in lookup — a real model
would weight recent drill accuracy (drill_attempts, §4) and outcome history rather than a name
substring. `extra_cases` already delegates to the real rec engine, so improving reweight case
selection means improving `recommendations` (or passing a richer `exclude`/`limit`), not editing
`reweight_payload`.

---

## 4. Data access points available today

Every signal a future, smarter readiness computation could draw on already has a read path in the
codebase. `file:symbol` each — all verified to resolve.

| Signal | `file:symbol` | Shape / notes |
| --- | --- | --- |
| Rubric dimension averages | `webapp/repositories/dashboard.py:dimension_averages` | `[{dimension, avg_score, samples}]`, **/5**, **ascending** (weakest first); window = last `TREND_WINDOW=10` candidate-finalized sessions. Currently the sole input to the stand-in. |
| Recent-case count | `webapp/readiness.py:_recent_case_count` | `int` candidate-finalized sessions in the last `DIAGNOSTIC_WINDOW_DAYS=60`. |
| Session history | `webapp/repositories/dashboard.py:history` | Finalized sessions the user took part in, newest first, with `your_role`, `counterpart`, `grade`. |
| Raw sessions | `webapp/repositories/practice_sessions.py:get_practice_session`, `webapp/repositories/practice_sessions.py:count_finalized` | Direct access to `candidate_id` / `interviewer_id` / `state` / `ended_at` columns for custom windows/filters. |
| Grade trend | `webapp/repositories/dashboard.py:_grade_trend` (surfaced via `webapp/repositories/dashboard.py:diagnostic`) | `{recent_avg, previous_avg, delta, direction}` — mean grade of the last 5 candidate-finalized sessions vs the 5 before. |
| Home diagnostic block | `webapp/repositories/dashboard.py:diagnostic` | `{cases_done_60d, dimensions, strengths, weaknesses, focus_dimension, trend}`; `strengths`=top 2, `weaknesses`=bottom 2. |
| Drill attempts | `webapp/repositories/drill_attempts.py:record_attempt`, `webapp/repositories/drill_attempts.py:streak_days`, `webapp/repositories/drill_attempts.py:attempted_today` | Per-attempt `drill_type` / `source` / `drill_key` / `correct` / `completed_at`; per-type correctness is derivable today. **Scored/graded drill fields land later in B8 migration 034** — not available at B7. |
| Timeline statuses | `webapp/repositories/user_firms.py:list_tracked`, `webapp/repositories/user_firms.py:get` | Per-firm `status ∈ {tracking, interviewed, offer, rejected, admitted}`, plus `snooze_until` and `result_recorded_at` — real interview outcomes to calibrate against. |
| Firm deadlines | `webapp/repositories/firms.py:all_deadlines` | `[{firm_id, cycle_label, deadline_date, region, is_estimate}]` — pressure/urgency context (all currently `is_estimate=TRUE`). |
| Recommendation engine | `webapp/repositories/dashboard.py:recommendations` | `[{case_id, title, case_type, difficulty, why, rule}]` — already consumed by `reweight_payload`; a readiness model could weight coverage gaps the same way. |

---

## 5. B5 notification-settings seam

```
webapp/maintenance.py:_deadline_notifications_allowed(user_id: int) -> bool
```

Gates the daily deadline-passed push ("Did you interview at {firm}?") emitted by
`webapp/maintenance.py:sweep_deadline_prompts` (which targets
`webapp/repositories/user_firms.py:firms_needing_prompt`).

Behavior (AS-BUILT, **fail-open**):

- `SELECT to_regclass('notification_settings')` — if the table does **not** exist (B5 unmerged),
  return `True` (allow the push).
- If it exists, read `session_reminders` for the user: row present → `bool(session_reminders)`;
  no row → `True`.
- Any exception is logged and returns `True`.

**Category mapping:** the deadline-passed prompt is a session-adjacent reminder, so it maps to B5's
**`session_reminders`** flag — a user who has muted session reminders gets no deadline prompt once
B5 is merged.

**Double-guard note:** post-merge, B5's own push choke-point re-checks the user's settings, so this
seam and B5 both gate the same send. That is harmless (same result) and intentional — this local
check just avoids doing prompt bookkeeping for a user who would be filtered downstream anyway. When
B5 merges, this function needs no change; if the category should differ, edit only the column named
in the `SELECT` here.
