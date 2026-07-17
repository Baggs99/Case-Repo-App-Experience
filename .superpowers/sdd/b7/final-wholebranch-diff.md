# B7 whole-branch diff package (merge-base edce22c .. HEAD)

## Commits
724917a Ledger + Task 8 review/diff: complete, clean
ce7c3d7 Add readiness-signal seams note (OD-B7-1 required deliverable)
0b21950 Ledger + Task 7 review/diff: complete, clean
e56d529 Add daily-guarded deadline-passed push with B5 notification-settings seam
0a231b2 Ledger + Task 6 review/diff: complete, clean
53f5e82 Extend /api/v1/dashboard with diagnostic + timeline summary (additive)
40d9597 Ledger + Task 5 review/diff: complete, clean (IDOR verified)
9bd3e37 Add timeline router + assembly service (track, detail, post-deadline flow)
bbbe7c6 Ledger + Task 4 review/diff: complete, clean
293d41b Add dashboard.diagnostic() home block (cases done, strengths/weaknesses, trend)
49e1639 Ledger + Task 3 review/diff: complete, clean
a734e38 Add readiness swap-point (OD-B7-1 stand-in) and reweight payload
8d9b35e Ledger + Task 2 review/diff: complete, clean
afdd389 Add user_firms tracking table (migration 027) and repo
682acec Ledger + Task 1 review/diff: complete, clean
c0bfab5 Add firms + firm_deadlines reference table (migration 026) and read repo
e7e2c51 Address plan-review C1: seed all 5 rubric dims in readiness/diagnostic tests; robustness nits
05c4e9c Add B7 timeline & home diagnostic implementation plan + baseline ledger

## Files changed (excluding .superpowers review artifacts)
 db/migrations/026_firms_and_deadlines.sql          |  68 +++++++
 db/migrations/027_user_firms.sql                   |  23 +++
 .../notes/2026-07-17-readiness-signal-seams.md     | 174 ++++++++++++++++++
 tests/test_b7_deadline_prompt.py                   |  96 ++++++++++
 tests/test_b7_diagnostic.py                        | 124 +++++++++++++
 tests/test_b7_firms.py                             |  63 +++++++
 tests/test_b7_readiness.py                         | 136 ++++++++++++++
 tests/test_b7_timeline_api.py                      | 200 +++++++++++++++++++++
 tests/test_b7_user_firms.py                        | 108 +++++++++++
 webapp/main.py                                     |   2 +
 webapp/maintenance.py                              |  85 ++++++++-
 webapp/readiness.py                                |  79 ++++++++
 webapp/repositories/dashboard.py                   |  59 ++++++
 webapp/repositories/firms.py                       |  40 +++++
 webapp/repositories/user_firms.py                  | 133 ++++++++++++++
 webapp/routes/api_v1.py                            |   6 +
 webapp/routes/timeline.py                          |  96 ++++++++++
 webapp/timeline_service.py                         | 113 ++++++++++++
 18 files changed, 1597 insertions(+), 8 deletions(-)

## Full diff (code + migrations + seams doc)
diff --git a/db/migrations/026_firms_and_deadlines.sql b/db/migrations/026_firms_and_deadlines.sql
new file mode 100644
index 0000000..b267191
--- /dev/null
+++ b/db/migrations/026_firms_and_deadlines.sql
@@ -0,0 +1,68 @@
+-- ============================================================================
+-- 026 — firm reference table + curated interview deadlines (roadmap §B7)
+-- ----------------------------------------------------------------------------
+-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/026_firms_and_deadlines.sql
+-- Idempotent:  CREATE TABLE / INDEX IF NOT EXISTS; seed via ON CONFLICT DO NOTHING.
+--
+-- firm_deadlines dates are a CURATED 2026–27 US full-time stand-in (is_estimate
+-- = TRUE): no authoritative source was consulted. Thomas replaces these with
+-- real cycle dates before launch (see the B7 report).
+-- ============================================================================
+
+CREATE TABLE IF NOT EXISTS firms (
+    id    SERIAL PRIMARY KEY,
+    name  TEXT NOT NULL,
+    slug  TEXT NOT NULL UNIQUE
+);
+
+CREATE TABLE IF NOT EXISTS firm_deadlines (
+    id            SERIAL PRIMARY KEY,
+    firm_id       INTEGER NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
+    cycle_label   TEXT NOT NULL,
+    deadline_date DATE NOT NULL,
+    region        TEXT,
+    is_estimate   BOOLEAN NOT NULL DEFAULT TRUE,
+    CONSTRAINT firm_deadlines_unique UNIQUE (firm_id, cycle_label, region)
+);
+
+CREATE INDEX IF NOT EXISTS idx_firm_deadlines_firm
+    ON firm_deadlines (firm_id, deadline_date);
+
+-- ~12 curated firms: MBB + Big-4 strategy arms + common T2.
+INSERT INTO firms (name, slug) VALUES
+    ('McKinsey & Company',       'mckinsey'),
+    ('Boston Consulting Group',  'bcg'),
+    ('Bain & Company',           'bain'),
+    ('Deloitte',                 'deloitte'),
+    ('PwC Strategy&',            'strategyand'),
+    ('EY-Parthenon',             'ey-parthenon'),
+    ('KPMG',                     'kpmg'),
+    ('Kearney',                  'kearney'),
+    ('Oliver Wyman',             'oliver-wyman'),
+    ('L.E.K. Consulting',        'lek'),
+    ('Roland Berger',            'roland-berger'),
+    ('Accenture Strategy',       'accenture-strategy')
+ON CONFLICT (slug) DO NOTHING;
+
+-- Curated 2026–27 US full-time dates (is_estimate = TRUE). McKinsey/BCG/Bain
+-- match the design persona anchors (Sep 12 / Sep 30 / Oct 08); Roland Berger's
+-- Jul 02 is intentionally a PASSED deadline (design persona) so the post-
+-- deadline prompt has a fixture.
+INSERT INTO firm_deadlines (firm_id, cycle_label, deadline_date, region, is_estimate)
+SELECT f.id, v.cycle_label, v.deadline_date::date, 'US', TRUE
+FROM (VALUES
+    ('mckinsey',           '2026 Full-time', '2026-09-12'),
+    ('bcg',                '2026 Full-time', '2026-09-30'),
+    ('bain',               '2026 Full-time', '2026-10-08'),
+    ('deloitte',           '2026 Full-time', '2026-10-15'),
+    ('strategyand',        '2026 Full-time', '2026-10-20'),
+    ('ey-parthenon',       '2026 Full-time', '2026-10-22'),
+    ('kpmg',               '2026 Full-time', '2026-10-25'),
+    ('kearney',            '2026 Full-time', '2026-09-25'),
+    ('oliver-wyman',       '2026 Full-time', '2026-09-18'),
+    ('lek',                '2026 Full-time', '2026-10-05'),
+    ('roland-berger',      '2026 Full-time', '2026-07-02'),
+    ('accenture-strategy', '2026 Full-time', '2026-10-30')
+) AS v(slug, cycle_label, deadline_date)
+JOIN firms f ON f.slug = v.slug
+ON CONFLICT ON CONSTRAINT firm_deadlines_unique DO NOTHING;
diff --git a/db/migrations/027_user_firms.sql b/db/migrations/027_user_firms.sql
new file mode 100644
index 0000000..d40d6a2
--- /dev/null
+++ b/db/migrations/027_user_firms.sql
@@ -0,0 +1,23 @@
+-- ============================================================================
+-- 027 — per-user firm tracking + post-deadline prompt state (roadmap §B7)
+-- ----------------------------------------------------------------------------
+-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/027_user_firms.sql
+-- Idempotent:  CREATE TABLE IF NOT EXISTS.
+--
+-- status flow: 'tracking' (default) → Offer='offer' / No offer='rejected' /
+-- Waiting='interviewed'(+snooze_until). "Didn't interview" DELETEs the row
+-- (DV-B7-1: drops off the line). 'admitted' is a recordable status kept for
+-- B6 (data only — nothing in B7 gates on it). snooze_until (DV-B7-2) both
+-- re-asks Waiting in a week and throttles the auto deadline-prompt to weekly.
+-- ============================================================================
+
+CREATE TABLE IF NOT EXISTS user_firms (
+    user_id             INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
+    firm_id             INTEGER     NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
+    added_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
+    status              TEXT        NOT NULL DEFAULT 'tracking'
+        CHECK (status IN ('tracking', 'interviewed', 'offer', 'rejected', 'admitted')),
+    result_recorded_at  TIMESTAMPTZ,
+    snooze_until        TIMESTAMPTZ,
+    PRIMARY KEY (user_id, firm_id)
+);
diff --git a/docs/superpowers/notes/2026-07-17-readiness-signal-seams.md b/docs/superpowers/notes/2026-07-17-readiness-signal-seams.md
new file mode 100644
index 0000000..b3b3ede
--- /dev/null
+++ b/docs/superpowers/notes/2026-07-17-readiness-signal-seams.md
@@ -0,0 +1,174 @@
+# Readiness signal — stand-in + swap seams (B7 / OD-B7-1)
+
+**Status:** the readiness signal shipped in B7 is a **documented STAND-IN** (execution
+brief §6, OD-B7-1). Real usage data does not exist yet, so `readiness_signal` computes a
+crude rubric-vs-threshold heuristic. It is isolated behind **one swap-point function that
+every caller goes through**, so a smarter implementation can replace the body without
+touching any caller. This note is the swap map: what the stand-in computes, the contract
+a replacement must preserve, the reweight derivation, every data access point available in
+code today (`file:symbol` each), and the B5 notification-settings seam.
+
+All `file:symbol` references below are AS-BUILT and were verified with the Step 2 grep (see
+the report). Paths are repo-relative.
+
+---
+
+## 1. What the stand-in computes
+
+`webapp/readiness.py:readiness_signal(user_id)` — firm-independent, no usage data required.
+
+Constants (all in `webapp/readiness.py`, module scope):
+
+| Constant | Value | Meaning |
+| --- | --- | --- |
+| `READINESS_THRESHOLD` | `3.0` | Weakest-dimension floor, on the **/5** scale (DV-B7-3). |
+| `READINESS_MIN_CASES` | `3` | Minimum recent candidate-finalized cases to be "ready". |
+| `DIAGNOSTIC_WINDOW_DAYS` | `60` | Recent-case window (days) for the count below. |
+
+Logic (exact, AS-BUILT):
+
+- `dims = dashboard_repo.dimension_averages(user_id)` — per-dimension averages on the **/5**
+  scale, **ordered ascending** (weakest dimension first). `focus_dimension = dims[0]["dimension"]`
+  (or `None` when there are no scored dimensions).
+- `recent = _recent_case_count(user_id)` — candidate-finalized sessions in the last
+  `DIAGNOSTIC_WINDOW_DAYS` days.
+- `weakest_avg = float(dims[0]["avg_score"])` (or `None`).
+- **`on_track` is true only when ALL hold:** `recent >= READINESS_MIN_CASES` **AND**
+  `weakest_avg is not None` **AND** `weakest_avg >= READINESS_THRESHOLD`.
+- Therefore the result is **`needs_work` when** `recent_case_count < 3` **OR** the weakest
+  dimension average `< 3.0` **OR** there is no rubric data at all; else **`on_track`**.
+
+The signal is **firm-independent** by design (OD-B7-1). The per-firm display badge shown on the
+timeline is a thin **presentation** derivation layered on top of this signal — it is **not**
+part of the swap-point:
+
+- `webapp/timeline_service.py:_firm_tag(signal, block)` (DV-B7-5), constant
+  `webapp/timeline_service.py:EARLY_DEADLINE_DAYS = 75`.
+- Returns **`early`** when the firm's deadline is unpassed and `days_remaining > 75`;
+  otherwise **`on_track`** when `signal["ready"]` else **`focus`**.
+- The hand-authored persona tags (ON PACE / PUSH QUANT / EARLY) are illustrative — the code
+  emits `on_track` / `focus` / `early` and is not matched byte-for-byte.
+
+---
+
+## 2. The swap-point signature (the one seam)
+
+```
+webapp/readiness.py:readiness_signal(user_id: int) -> dict
+```
+
+Return shape (the **contract** a replacement MUST preserve — same keys, same types):
+
+| Key | Type | Notes |
+| --- | --- | --- |
+| `label` | `'on_track' \| 'needs_work'` | The bucket. |
+| `ready` | `bool` | `True` iff `label == 'on_track'`. Drives `_firm_tag`. |
+| `focus_dimension` | `str \| None` | Weakest rubric dimension; `None` when no data. |
+| `recent_case_count` | `int` | Candidate-finalized sessions in the 60-day window. |
+| `threshold` | `float` | Echoes `READINESS_THRESHOLD` (3.0) for the client. |
+| `min_cases` | `int` | Echoes `READINESS_MIN_CASES` (3) for the client. |
+
+**Every caller goes through this function** — swapping the body (e.g. a learned model) is
+transparent to all of them as long as the return keys above are unchanged:
+
+- `webapp/timeline_service.py:timeline_view` — calls `readiness.readiness_signal(user_id)`
+  directly (readiness.py invoked at timeline_service line 66); puts it at `payload["readiness"]`
+  and feeds it to `_firm_tag` per row.
+- `webapp/timeline_service.py:next_deadline_summary` — reaches the signal **transitively** by
+  calling `timeline_view(user_id, as_of)` and reusing its `firms[*].readiness_tag`; it does not
+  re-call `readiness_signal` itself.
+- `webapp/readiness.py:reweight_payload` — calls `readiness_signal(user_id)` directly for
+  `focus_dimension` (see §3).
+
+There is no other computation of the on-track / needs-work bucket anywhere in the codebase; a
+grep for `readiness_signal` finds only these call sites. That is the invariant OD-B7-1 requires.
+
+**Where a smarter implementation plugs in:** replace the body of `readiness_signal` only. It may
+draw on any of the §4 data access points (drill accuracy, grade trend, timeline outcomes, etc.).
+It must keep returning the six keys above. Callers, the timeline payload, and `_firm_tag` need no
+change. If a replacement wants firm-specific readiness, it should still return the firm-independent
+signal here and extend `_firm_tag` (the presentation layer), not fork the swap-point.
+
+---
+
+## 3. The reweight seam ("No offer → reweight")
+
+```
+webapp/readiness.py:reweight_payload(user_id: int) -> dict
+```
+
+Return shape: `{focus_dimension: str | None, suggested_drill_type: str, extra_cases: list[int]}`.
+This is the DESIGN DELTA "No offer → reweight response" — the post-deadline flow ends in plan
+reweighting, never a forum handoff.
+
+Derivation (AS-BUILT), each part a documented seam:
+
+1. **`focus_dimension`** — taken from `readiness_signal(user_id)["focus_dimension"]` (the weakest
+   `/5` dimension). Same source as readiness and the diagnostic, so FOCUS is consistent everywhere
+   (DV-B7-4).
+2. **`suggested_drill_type`** — `webapp/readiness.py:suggested_drill_type(focus_dimension)` maps a
+   rubric dimension name to exactly one of the **3 existing drill generators** in
+   `webapp/drills.py:_TYPES = ("mental_math", "market_sizing", "framework_recall")`. Substring
+   rules: `None` → `mental_math`; name contains `siz` → `market_sizing`; contains
+   `quant`/`math`/`numer` → `mental_math`; otherwise → `framework_recall`. Substring matching keeps
+   it robust to rubric renames.
+3. **`extra_cases`** — `[r["case_id"] for r in dashboard_repo.recommendations(user_id, [], limit=2)]`.
+   That is the B4 recommendation engine, `webapp/repositories/dashboard.py:recommendations`
+   (item key is `case_id`; the human-readable title key is `title`). `limit=2` = "two extra cases
+   before BCG" from the persona.
+
+**Where a smarter engine plugs in:** `suggested_drill_type` is a stand-in lookup — a real model
+would weight recent drill accuracy (drill_attempts, §4) and outcome history rather than a name
+substring. `extra_cases` already delegates to the real rec engine, so improving reweight case
+selection means improving `recommendations` (or passing a richer `exclude`/`limit`), not editing
+`reweight_payload`.
+
+---
+
+## 4. Data access points available today
+
+Every signal a future, smarter readiness computation could draw on already has a read path in the
+codebase. `file:symbol` each — all verified to resolve.
+
+| Signal | `file:symbol` | Shape / notes |
+| --- | --- | --- |
+| Rubric dimension averages | `webapp/repositories/dashboard.py:dimension_averages` | `[{dimension, avg_score, samples}]`, **/5**, **ascending** (weakest first); window = last `TREND_WINDOW=10` candidate-finalized sessions. Currently the sole input to the stand-in. |
+| Recent-case count | `webapp/readiness.py:_recent_case_count` | `int` candidate-finalized sessions in the last `DIAGNOSTIC_WINDOW_DAYS=60`. |
+| Session history | `webapp/repositories/dashboard.py:history` | Finalized sessions the user took part in, newest first, with `your_role`, `counterpart`, `grade`. |
+| Raw sessions | `webapp/repositories/practice_sessions.py:get_practice_session`, `webapp/repositories/practice_sessions.py:count_finalized` | Direct access to `candidate_id` / `interviewer_id` / `state` / `ended_at` columns for custom windows/filters. |
+| Grade trend | `webapp/repositories/dashboard.py:_grade_trend` (surfaced via `webapp/repositories/dashboard.py:diagnostic`) | `{recent_avg, previous_avg, delta, direction}` — mean grade of the last 5 candidate-finalized sessions vs the 5 before. |
+| Home diagnostic block | `webapp/repositories/dashboard.py:diagnostic` | `{cases_done_60d, dimensions, strengths, weaknesses, focus_dimension, trend}`; `strengths`=top 2, `weaknesses`=bottom 2. |
+| Drill attempts | `webapp/repositories/drill_attempts.py:record_attempt`, `webapp/repositories/drill_attempts.py:streak_days`, `webapp/repositories/drill_attempts.py:attempted_today` | Per-attempt `drill_type` / `source` / `drill_key` / `correct` / `completed_at`; per-type correctness is derivable today. **Scored/graded drill fields land later in B8 migration 034** — not available at B7. |
+| Timeline statuses | `webapp/repositories/user_firms.py:list_tracked`, `webapp/repositories/user_firms.py:get` | Per-firm `status ∈ {tracking, interviewed, offer, rejected, admitted}`, plus `snooze_until` and `result_recorded_at` — real interview outcomes to calibrate against. |
+| Firm deadlines | `webapp/repositories/firms.py:all_deadlines` | `[{firm_id, cycle_label, deadline_date, region, is_estimate}]` — pressure/urgency context (all currently `is_estimate=TRUE`). |
+| Recommendation engine | `webapp/repositories/dashboard.py:recommendations` | `[{case_id, title, case_type, difficulty, why, rule}]` — already consumed by `reweight_payload`; a readiness model could weight coverage gaps the same way. |
+
+---
+
+## 5. B5 notification-settings seam
+
+```
+webapp/maintenance.py:_deadline_notifications_allowed(user_id: int) -> bool
+```
+
+Gates the daily deadline-passed push ("Did you interview at {firm}?") emitted by
+`webapp/maintenance.py:sweep_deadline_prompts` (which targets
+`webapp/repositories/user_firms.py:firms_needing_prompt`).
+
+Behavior (AS-BUILT, **fail-open**):
+
+- `SELECT to_regclass('notification_settings')` — if the table does **not** exist (B5 unmerged),
+  return `True` (allow the push).
+- If it exists, read `session_reminders` for the user: row present → `bool(session_reminders)`;
+  no row → `True`.
+- Any exception is logged and returns `True`.
+
+**Category mapping:** the deadline-passed prompt is a session-adjacent reminder, so it maps to B5's
+**`session_reminders`** flag — a user who has muted session reminders gets no deadline prompt once
+B5 is merged.
+
+**Double-guard note:** post-merge, B5's own push choke-point re-checks the user's settings, so this
+seam and B5 both gate the same send. That is harmless (same result) and intentional — this local
+check just avoids doing prompt bookkeeping for a user who would be filtered downstream anyway. When
+B5 merges, this function needs no change; if the category should differ, edit only the column named
+in the `SELECT` here.
diff --git a/tests/test_b7_deadline_prompt.py b/tests/test_b7_deadline_prompt.py
new file mode 100644
index 0000000..75c741b
--- /dev/null
+++ b/tests/test_b7_deadline_prompt.py
@@ -0,0 +1,96 @@
+"""B7 Task 7: deadline-passed push from the maintenance loop — push fires once
+per passed-deadline firm, snoozes for a week, honors the daily guard, and the
+B5 notification-settings seam fails open when the table is absent."""
+
+from __future__ import annotations
+
+import datetime
+import unittest
+from unittest.mock import patch
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestDeadlinePrompt(unittest.IsolatedAsyncioTestCase):
+    @classmethod
+    def setUpClass(cls):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        from webapp.repositories import firms as firms_repo
+        cls._ctx = TestClient(app)
+        cls._ctx.__enter__()
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
+                cls.aid = cur.fetchone()[0]
+        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]
+
+    @classmethod
+    def tearDownClass(cls):
+        cls._ctx.__exit__(None, None, None)
+
+    def setUp(self):
+        import webapp.maintenance as m
+        m._deadline_prompt_last_date = None    # reset the daily guard
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (self.aid,))
+
+    def tearDown(self):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (self.aid,))
+
+    async def test_push_fires_then_snoozes(self):
+        from webapp import maintenance
+        from webapp.repositories import user_firms as uf
+        uf.track(self.aid, self.rb)            # Roland Berger deadline is passed
+        calls = []
+
+        async def _capture(user_id, **kw):
+            calls.append((user_id, kw))
+
+        with patch("webapp.maintenance.push_to_user", _capture):
+            sent = await maintenance.sweep_deadline_prompts(datetime.date(2026, 7, 17))
+            self.assertEqual(sent, 1)
+            self.assertEqual(calls[0][0], self.aid)
+            self.assertIn("Roland", calls[0][1]["body"])
+            # Snoozed now → second sweep sends nothing.
+            sent2 = await maintenance.sweep_deadline_prompts(datetime.date(2026, 7, 17))
+            self.assertEqual(sent2, 0)
+
+    async def test_daily_guard_runs_once_per_day(self):
+        from webapp import maintenance
+        from webapp.repositories import user_firms as uf
+        from webapp.settings import load_settings
+        uf.track(self.aid, self.rb)
+
+        async def _noop(user_id, **kw):
+            return None
+
+        async def _no_starting_soon(*a, **k):
+            return None
+
+        with patch("webapp.maintenance.push_to_user", _noop), \
+             patch("webapp.push.starting_soon.push_to_user", _no_starting_soon):
+            r1 = await maintenance.run_maintenance_pass(
+                load_settings(), as_of=datetime.date(2026, 7, 17))
+            r2 = await maintenance.run_maintenance_pass(
+                load_settings(), as_of=datetime.date(2026, 7, 17))
+        self.assertEqual(r1["deadline_prompts"], 1)   # first pass today runs it
+        self.assertEqual(r2["deadline_prompts"], 0)   # guard blocks the re-run
+
+    def test_b5_seam_fails_open_without_settings_table(self):
+        from webapp import maintenance
+        # notification_settings does not exist on this branch (B5 unmerged) →
+        # the seam must allow the push (fail-open).
+        self.assertTrue(maintenance._deadline_notifications_allowed(self.aid))
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/tests/test_b7_diagnostic.py b/tests/test_b7_diagnostic.py
new file mode 100644
index 0000000..6adf77c
--- /dev/null
+++ b/tests/test_b7_diagnostic.py
@@ -0,0 +1,124 @@
+"""B7 Task 4: dashboard.diagnostic() block. Reuses the test_dashboard fixture
+shape. Cara has 3 finalized-as-candidate sessions; grades 4.5/4.0/4.2 give a
+recent_avg over the last ≤5 and previous_avg=None (fewer than 6 sessions)."""
+
+from __future__ import annotations
+
+import json
+import unittest
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+# All FIVE generic-template dimensions must be seeded: dimension_averages
+# iterates the template's items and COALESCEs a missing dimension to 0, so an
+# unseeded dim (insight/synthesis) would score 0.0 and steal "weakest" from
+# quant. These values (mirroring tests/test_dashboard.py) make quant strictly
+# weakest (1.0/5) and communication strongest (4.33/5).
+_SESSIONS = [
+    {"grade": 4.5, "pts": {"structure": 4, "quant": 2, "insight": 3,
+                           "communication": 5, "synthesis": 1}},
+    {"grade": 4.0, "pts": {"structure": 3, "quant": 0, "insight": 4,
+                           "communication": 4, "synthesis": 2}},
+    {"grade": 4.2, "pts": {"structure": 5, "quant": 1, "insight": 4,
+                           "communication": 4, "synthesis": 3}},
+]
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestDiagnostic(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        # Enter the app lifespan so the shared connection pool is initialized
+        # (get_or_create_room / get_default_rubric_template_id and
+        # dashboard.diagnostic all go through webapp.db.get_pool()). Must precede
+        # any pool-backed call below. Matches test_b7_readiness.
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+
+        cls._ctx = TestClient(app)
+        cls._ctx.__enter__()
+
+        import psycopg
+        from webapp.repositories.practice_sessions import get_default_rubric_template_id
+        from webapp.repositories.rooms import get_or_create_room
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
+                            (["a@yale.edu", "c@yale.edu"],))
+                ids = dict(cur.fetchall())
+        cls.aid, cls.cid = ids["a@yale.edu"], ids["c@yale.edu"]
+        room_id = get_or_create_room(cls.aid)["id"]
+        cls.case_ids, cls.session_ids = [], []
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                for i in range(3):
+                    cur.execute(
+                        "INSERT INTO cases (case_title, normalized_title,"
+                        " source_school, source_year, industry, case_type,"
+                        " difficulty, difficulty_score, page_count, pdf_path)"
+                        " VALUES (%s, %s, 'DevSchool', 2097, 'Technology',"
+                        " 'B7-Dg', 'Easy', 3, 2, 'output/none.pdf') RETURNING id;",
+                        (f"B7 Dg Case {i}", f"b7 dg case {i}"))
+                    cls.case_ids.append(cur.fetchone()[0])
+                template_id = get_default_rubric_template_id(cls.case_ids[0], cls.aid)
+                for i, spec in enumerate(_SESSIONS):
+                    cur.execute(
+                        "INSERT INTO practice_sessions (room_id, interviewer_id,"
+                        " candidate_id, case_id, rubric_template_id, state,"
+                        " consent_interviewer, consent_candidate, started_at,"
+                        " ended_at, state_changed_at)"
+                        " VALUES (%s, %s, %s, %s, %s, 'finalized', TRUE, TRUE,"
+                        " NOW() - (%s + 1) * INTERVAL '1 day',"
+                        " NOW() - (%s + 1) * INTERVAL '1 day' + INTERVAL '45 min',"
+                        " NOW()) RETURNING id;",
+                        (room_id, cls.aid, cls.cid, cls.case_ids[i], template_id, i, i))
+                    sid = cur.fetchone()[0]
+                    cls.session_ids.append(sid)
+                    items = {d: {"points": p, "note": ""} for d, p in spec["pts"].items()}
+                    cur.execute(
+                        "INSERT INTO feedback (session_id, rubric_json, notes_md,"
+                        " grade, finalized_at) VALUES (%s, %s, 'fx', %s, NOW());",
+                        (sid, json.dumps({"items": items}), spec["grade"]))
+
+    @classmethod
+    def tearDownClass(cls):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
+                            (cls.session_ids,))
+                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
+        cls._ctx.__exit__(None, None, None)
+
+    def test_diagnostic_shape_and_values(self):
+        from webapp.repositories import dashboard
+        d = dashboard.diagnostic(self.cid)
+        self.assertEqual(d["cases_done_60d"], 3)
+        self.assertEqual(d["focus_dimension"], "quant")           # weakest
+        self.assertEqual(d["weaknesses"][0]["dimension"], "quant")  # lowest first
+        self.assertEqual(d["strengths"][0]["dimension"], "communication")  # highest first
+        self.assertLessEqual(len(d["strengths"]), 2)
+        self.assertLessEqual(len(d["weaknesses"]), 2)
+
+    def test_trend_recent_only_when_thin(self):
+        from webapp.repositories import dashboard
+        d = dashboard.diagnostic(self.cid)
+        # 3 grades → recent_avg = mean(4.5,4.0,4.2) ≈ 4.23; previous window empty.
+        self.assertAlmostEqual(d["trend"]["recent_avg"], 4.2333, places=2)
+        self.assertIsNone(d["trend"]["previous_avg"])
+        self.assertIsNone(d["trend"]["delta"])
+        self.assertIsNone(d["trend"]["direction"])
+
+    def test_diagnostic_empty_user(self):
+        from webapp.repositories import dashboard
+        d = dashboard.diagnostic(self.aid)   # no candidate sessions here
+        self.assertEqual(d["cases_done_60d"], 0)
+        self.assertIsNone(d["focus_dimension"])
+        self.assertEqual(d["strengths"], [])
+        self.assertEqual(d["weaknesses"], [])
+        self.assertIsNone(d["trend"]["recent_avg"])
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/tests/test_b7_firms.py b/tests/test_b7_firms.py
new file mode 100644
index 0000000..cd45197
--- /dev/null
+++ b/tests/test_b7_firms.py
@@ -0,0 +1,63 @@
+"""B7 Task 1: firms reference table + read repo. Needs seeded dev Postgres."""
+
+from __future__ import annotations
+
+import datetime
+import unittest
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestFirmsRepo(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        # Enter the app lifespan so the shared connection pool is initialized
+        # (repo functions go through webapp.db.get_pool()). Matches the harness
+        # note in the B7 plan's File Structure section.
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+
+        cls._ctx = TestClient(app)
+        cls._ctx.__enter__()
+
+    @classmethod
+    def tearDownClass(cls):
+        cls._ctx.__exit__(None, None, None)
+
+    def test_list_firms_has_mbb(self):
+        from webapp.repositories import firms as firms_repo
+        firms = firms_repo.list_firms()
+        slugs = {f["slug"] for f in firms}
+        self.assertGreaterEqual(len(firms), 12)
+        self.assertTrue({"mckinsey", "bcg", "bain"}.issubset(slugs))
+        for f in firms:
+            self.assertEqual(set(f), {"id", "name", "slug"})
+
+    def test_get_firm_by_id_and_missing(self):
+        from webapp.repositories import firms as firms_repo
+        first = firms_repo.list_firms()[0]
+        got = firms_repo.get_firm(first["id"])
+        self.assertEqual(got["slug"], first["slug"])
+        self.assertIsNone(firms_repo.get_firm(-1))
+
+    def test_all_deadlines_are_dates_flagged_estimate(self):
+        from webapp.repositories import firms as firms_repo
+        deadlines = firms_repo.all_deadlines()
+        self.assertGreaterEqual(len(deadlines), 12)
+        for d in deadlines:
+            self.assertIsInstance(d["deadline_date"], datetime.date)
+            self.assertTrue(d["is_estimate"])
+            self.assertEqual(d["region"], "US")
+
+    def test_roland_berger_deadline_is_in_the_past_fixture(self):
+        # The persona's passed deadline — powers the post-deadline prompt tests.
+        from webapp.repositories import firms as firms_repo
+        rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")
+        rb_dl = [d for d in firms_repo.all_deadlines() if d["firm_id"] == rb["id"]]
+        self.assertEqual(rb_dl[0]["deadline_date"], datetime.date(2026, 7, 2))
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/tests/test_b7_readiness.py b/tests/test_b7_readiness.py
new file mode 100644
index 0000000..f299ba7
--- /dev/null
+++ b/tests/test_b7_readiness.py
@@ -0,0 +1,136 @@
+"""B7 Task 3: the readiness swap-point (OD-B7-1 stand-in) + reweight payload.
+
+Uses the same finalized-session fixture shape as tests/test_dashboard.py:
+Cara (c@yale.edu) is the subject; 3 finalized-as-candidate sessions with a
+generic template make quant strictly weakest (avg 1.0/5) so the stand-in
+returns needs_work and focus_dimension='quant'.
+"""
+
+from __future__ import annotations
+
+import json
+import unittest
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+# All FIVE generic-template dimensions must be seeded: dimension_averages
+# iterates the template's items and COALESCEs a missing dimension to 0, so an
+# unseeded dim (insight/synthesis) would score 0.0 and steal "weakest" from
+# quant. These values (mirroring tests/test_dashboard.py) make quant strictly
+# weakest (1.0/5) and communication strongest (4.33/5).
+_SESSIONS = [
+    {"grade": 4.5, "pts": {"structure": 4, "quant": 2, "insight": 3,
+                           "communication": 5, "synthesis": 1}},
+    {"grade": 4.0, "pts": {"structure": 3, "quant": 0, "insight": 4,
+                           "communication": 4, "synthesis": 2}},
+    {"grade": 4.2, "pts": {"structure": 5, "quant": 1, "insight": 4,
+                           "communication": 4, "synthesis": 3}},
+]
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestReadiness(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        # Enter the app lifespan so the shared connection pool is initialized
+        # (get_or_create_room / get_default_rubric_template_id and the readiness
+        # functions all go through webapp.db.get_pool()). Must precede any
+        # pool-backed call below. Matches test_b7_firms / test_b7_user_firms.
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+
+        cls._ctx = TestClient(app)
+        cls._ctx.__enter__()
+
+        import psycopg
+        from webapp.repositories.practice_sessions import get_default_rubric_template_id
+        from webapp.repositories.rooms import get_or_create_room
+
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
+                            (["a@yale.edu", "c@yale.edu"],))
+                ids = dict(cur.fetchall())
+        cls.aid, cls.cid = ids["a@yale.edu"], ids["c@yale.edu"]
+        room_id = get_or_create_room(cls.aid)["id"]
+
+        cls.case_ids, cls.session_ids = [], []
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                for i in range(3):
+                    cur.execute(
+                        "INSERT INTO cases (case_title, normalized_title,"
+                        " source_school, source_year, industry, case_type,"
+                        " difficulty, difficulty_score, page_count, pdf_path)"
+                        " VALUES (%s, %s, 'DevSchool', 2096, 'Technology',"
+                        " 'B7-Rd', 'Easy', 3, 2, 'output/none.pdf') RETURNING id;",
+                        (f"B7 Rd Case {i}", f"b7 rd case {i}"))
+                    cls.case_ids.append(cur.fetchone()[0])
+                template_id = get_default_rubric_template_id(cls.case_ids[0], cls.aid)
+                for i, spec in enumerate(_SESSIONS):
+                    cur.execute(
+                        "INSERT INTO practice_sessions (room_id, interviewer_id,"
+                        " candidate_id, case_id, rubric_template_id, state,"
+                        " consent_interviewer, consent_candidate, started_at,"
+                        " ended_at, state_changed_at)"
+                        " VALUES (%s, %s, %s, %s, %s, 'finalized', TRUE, TRUE,"
+                        " NOW() - (%s + 1) * INTERVAL '1 day',"
+                        " NOW() - (%s + 1) * INTERVAL '1 day' + INTERVAL '45 min',"
+                        " NOW()) RETURNING id;",
+                        (room_id, cls.aid, cls.cid, cls.case_ids[i], template_id, i, i))
+                    sid = cur.fetchone()[0]
+                    cls.session_ids.append(sid)
+                    items = {d: {"points": p, "note": ""} for d, p in spec["pts"].items()}
+                    cur.execute(
+                        "INSERT INTO feedback (session_id, rubric_json, notes_md,"
+                        " grade, finalized_at) VALUES (%s, %s, 'fx', %s, NOW());",
+                        (sid, json.dumps({"items": items}), spec["grade"]))
+
+    @classmethod
+    def tearDownClass(cls):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
+                            (cls.session_ids,))
+                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
+        cls._ctx.__exit__(None, None, None)
+
+    def test_signal_needs_work_focus_quant(self):
+        from webapp import readiness
+        sig = readiness.readiness_signal(self.cid)
+        self.assertEqual(sig["label"], "needs_work")   # weakest quant 1.0 < 3.0
+        self.assertFalse(sig["ready"])
+        self.assertEqual(sig["focus_dimension"], "quant")
+        self.assertEqual(sig["recent_case_count"], 3)
+
+    def test_signal_no_data_is_needs_work(self):
+        from webapp import readiness
+        # Alice (a@yale.edu) has no finalized-as-candidate sessions here.
+        sig = readiness.readiness_signal(self.aid)
+        self.assertEqual(sig["label"], "needs_work")
+        self.assertIsNone(sig["focus_dimension"])
+        self.assertEqual(sig["recent_case_count"], 0)
+
+    def test_suggested_drill_type_mapping(self):
+        from webapp import readiness
+        self.assertEqual(readiness.suggested_drill_type("market_sizing"), "market_sizing")
+        self.assertEqual(readiness.suggested_drill_type("quant"), "mental_math")
+        self.assertEqual(readiness.suggested_drill_type("structure"), "framework_recall")
+        self.assertEqual(readiness.suggested_drill_type(None), "mental_math")
+
+    def test_reweight_payload_shape(self):
+        from webapp import readiness
+        rw = readiness.reweight_payload(self.cid)
+        self.assertEqual(set(rw), {"focus_dimension", "suggested_drill_type", "extra_cases"})
+        self.assertEqual(rw["focus_dimension"], "quant")
+        self.assertEqual(rw["suggested_drill_type"], "mental_math")
+        self.assertIsInstance(rw["extra_cases"], list)
+        self.assertLessEqual(len(rw["extra_cases"]), 2)
+        for cid in rw["extra_cases"]:
+            self.assertIsInstance(cid, int)
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/tests/test_b7_timeline_api.py b/tests/test_b7_timeline_api.py
new file mode 100644
index 0000000..9ea3912
--- /dev/null
+++ b/tests/test_b7_timeline_api.py
@@ -0,0 +1,200 @@
+"""B7 Task 5: timeline router — track/untrack, timeline-detail payload, the
+post-deadline result flow, auth + IDOR. Needs seeded dev Postgres + httpx."""
+
+from __future__ import annotations
+
+import unittest
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestTimelineApi(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
+        from webapp.repositories import firms as firms_repo
+
+        cls._ctx = TestClient(app)
+        cls.alice = cls._ctx.__enter__()
+        cls.bob = TestClient(app)
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
+                            (["a@yale.edu", "b@yale.edu"],))
+                ids = dict(cur.fetchall())
+        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]
+        for client, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
+            s = create_session(uid, user_agent="b7-test", ip_address=None)
+            client.cookies.set(SESSION_COOKIE_NAME, s.id)
+        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
+        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]
+
+    @classmethod
+    def tearDownClass(cls):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = ANY(%s);",
+                            ([cls.aid, cls.bid],))
+        cls._ctx.__exit__(None, None, None)
+
+    def tearDown(self):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = ANY(%s);",
+                            ([self.aid, self.bid],))
+
+    # ── auth ────────────────────────────────────────────────────────────────
+    def test_timeline_requires_auth(self):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        self.assertEqual(TestClient(app).get("/api/v1/timeline").status_code, 401)
+
+    def test_track_requires_auth(self):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        r = TestClient(app).post("/api/v1/timeline/firms", json={"firm_id": self.mck})
+        self.assertEqual(r.status_code, 401)
+
+    # ── track / list / untrack ───────────────────────────────────────────────
+    def test_track_untrack_and_catalog(self):
+        r = self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.mck})
+        self.assertEqual(r.status_code, 200, r.text)
+        self.assertEqual(r.json()["status"], "tracking")
+
+        cat = self.alice.get("/api/v1/timeline/firms").json()["firms"]
+        mck = next(f for f in cat if f["firm_id"] == self.mck)
+        self.assertTrue(mck["tracked"])
+        self.assertIsNotNone(mck["next_deadline"])
+
+        tl = self.alice.get("/api/v1/timeline").json()
+        self.assertEqual(len(tl["firms"]), 1)
+        self.assertIn(tl["firms"][0]["readiness_tag"], {"on_track", "focus", "early"})
+        self.assertEqual(tl["readiness"]["label"], "needs_work")  # Alice: no data
+
+        self.assertEqual(
+            self.alice.delete(f"/api/v1/timeline/firms/{self.mck}").status_code, 204)
+        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 0)
+
+    def test_track_unknown_firm_404(self):
+        r = self.alice.post("/api/v1/timeline/firms", json={"firm_id": -1})
+        self.assertEqual(r.status_code, 404)
+
+    # ── post-deadline result flow ─────────────────────────────────────────────
+    def test_passed_deadline_prompt_then_offer(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        tl = self.alice.get("/api/v1/timeline").json()
+        rb = next(f for f in tl["firms"] if f["firm_id"] == self.rb)
+        self.assertTrue(rb["deadline"]["passed"])
+        self.assertTrue(rb["prompt"]["show"])
+
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "offer"})
+        self.assertEqual(r.status_code, 200, r.text)
+        self.assertEqual(r.json()["status"], "offer")
+        # Prompt gone once resolved.
+        tl2 = self.alice.get("/api/v1/timeline").json()
+        rb2 = next(f for f in tl2["firms"] if f["firm_id"] == self.rb)
+        self.assertFalse(rb2["prompt"]["show"])
+        self.assertEqual(rb2["status"], "offer")
+
+    def test_no_offer_returns_reweight(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "no_offer"})
+        self.assertEqual(r.status_code, 200, r.text)
+        body = r.json()
+        self.assertEqual(body["status"], "rejected")
+        self.assertEqual(set(body["reweight"]),
+                         {"focus_dimension", "suggested_drill_type", "extra_cases"})
+
+    def test_waiting_snoozes(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "waiting"})
+        self.assertEqual(r.json()["status"], "interviewed")
+        self.assertIsNotNone(r.json()["snooze_until"])
+
+    def test_didnt_interview_drops_off(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "didnt_interview"})
+        self.assertTrue(r.json()["dropped"])
+        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 0)
+
+    def test_bad_outcome_400(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "nope"})
+        self.assertEqual(r.status_code, 400)
+
+    # ── IDOR: Bob cannot resolve or untrack a firm only Alice tracks ──────────
+    def test_result_on_untracked_firm_404(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.bob.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                          json={"outcome": "offer"})
+        self.assertEqual(r.status_code, 404)
+        # Alice's row is untouched.
+        tl = self.alice.get("/api/v1/timeline").json()
+        self.assertEqual(tl["firms"][0]["status"], "tracking")
+
+    def test_untrack_is_per_user(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        # Bob deleting the same firm_id only touches his own (absent) row.
+        self.assertEqual(
+            self.bob.delete(f"/api/v1/timeline/firms/{self.rb}").status_code, 204)
+        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 1)
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestDashboardTimelineKeys(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
+        from webapp.repositories import firms as firms_repo
+        cls._ctx = TestClient(app)
+        cls.alice = cls._ctx.__enter__()
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
+                cls.aid = cur.fetchone()[0]
+        s = create_session(cls.aid, user_agent="b7-dash", ip_address=None)
+        cls.alice.cookies.set(SESSION_COOKIE_NAME, s.id)
+        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
+
+    @classmethod
+    def tearDownClass(cls):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (cls.aid,))
+        cls._ctx.__exit__(None, None, None)
+
+    def test_dashboard_has_diagnostic_and_timeline(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.mck})
+        d = self.alice.get("/api/v1/dashboard").json()
+        # Additive — existing B4 keys still present.
+        self.assertIn("recommendations", d)
+        self.assertIn("dimension_averages", d)
+        # New B7 keys.
+        self.assertIn("diagnostic", d)
+        self.assertEqual(set(d["diagnostic"]) >= {
+            "cases_done_60d", "dimensions", "strengths", "weaknesses",
+            "focus_dimension", "trend"}, True)
+        self.assertIn("timeline", d)
+        self.assertEqual(d["timeline"]["tracked_count"], 1)
+        self.assertEqual(d["timeline"]["next_deadline"]["slug"], "mckinsey")
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/tests/test_b7_user_firms.py b/tests/test_b7_user_firms.py
new file mode 100644
index 0000000..a78c8e4
--- /dev/null
+++ b/tests/test_b7_user_firms.py
@@ -0,0 +1,108 @@
+"""B7 Task 2: per-user firm tracking repo. Needs seeded dev Postgres."""
+
+from __future__ import annotations
+
+import datetime
+import unittest
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestUserFirmsRepo(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        # Enter the app lifespan so the shared connection pool is initialized
+        # (repo functions go through webapp.db.get_pool()). Must precede any
+        # pool-backed call (firms_repo.list_firms below). Matches test_b7_firms.
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+
+        cls._ctx = TestClient(app)
+        cls._ctx.__enter__()
+
+        import psycopg
+        from webapp.repositories import firms as firms_repo
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
+                cls.uid = cur.fetchone()[0]
+        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
+        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]
+
+    @classmethod
+    def tearDownClass(cls):
+        cls._ctx.__exit__(None, None, None)
+
+    def tearDown(self):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (self.uid,))
+
+    def test_track_is_idempotent_and_listable(self):
+        from webapp.repositories import user_firms as uf
+        row = uf.track(self.uid, self.mck)
+        self.assertEqual(row["status"], "tracking")
+        uf.track(self.uid, self.mck)  # second track = no-op
+        tracked = uf.list_tracked(self.uid)
+        self.assertEqual(len(tracked), 1)
+        self.assertEqual(tracked[0]["slug"], "mckinsey")
+        self.assertTrue(uf.is_tracked(self.uid, self.mck))
+
+    def test_untrack_removes(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.mck)
+        self.assertEqual(uf.untrack(self.uid, self.mck), 1)
+        self.assertFalse(uf.is_tracked(self.uid, self.mck))
+        self.assertEqual(uf.untrack(self.uid, self.mck), 0)
+
+    def test_record_result_offer_and_rejected(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.mck)
+        row = uf.record_result(self.uid, self.mck, "offer")
+        self.assertEqual(row["status"], "offer")
+        self.assertIsNotNone(row["result_recorded_at"])
+        self.assertIsNone(row["snooze_until"])
+        row2 = uf.record_result(self.uid, self.mck, "rejected")
+        self.assertEqual(row2["status"], "rejected")
+
+    def test_record_result_untracked_returns_none(self):
+        from webapp.repositories import user_firms as uf
+        self.assertIsNone(uf.record_result(self.uid, self.mck, "offer"))
+
+    def test_mark_waiting_sets_snooze(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.mck)
+        row = uf.mark_waiting(self.uid, self.mck, days=7)
+        self.assertEqual(row["status"], "interviewed")
+        self.assertIsNotNone(row["snooze_until"])
+
+    def test_firms_needing_prompt_finds_passed_untouched(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.rb)          # Roland Berger deadline = 2026-07-02
+        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
+        mine = [r for r in rows if r["user_id"] == self.uid and r["firm_id"] == self.rb]
+        self.assertEqual(len(mine), 1)
+        self.assertIn("Roland", mine[0]["firm_name"])
+
+    def test_snoozed_firm_not_prompted(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.rb)
+        uf.mark_prompted(self.uid, self.rb,
+                         snooze_until=datetime.datetime.now(datetime.timezone.utc)
+                         + datetime.timedelta(days=7))
+        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
+        self.assertFalse([r for r in rows if r["firm_id"] == self.rb])
+
+    def test_non_tracking_status_not_prompted(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.rb)
+        uf.record_result(self.uid, self.rb, "offer")  # status='offer' → done
+        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
+        self.assertFalse([r for r in rows if r["firm_id"] == self.rb])
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/webapp/main.py b/webapp/main.py
index 33fbc9d..c98d9a8 100644
--- a/webapp/main.py
+++ b/webapp/main.py
@@ -58,16 +58,17 @@ from webapp.routes import practice as practice_routes
 from webapp.routes import practice_exhibits as practice_exhibits_routes
 from webapp.routes import practice_feedback as practice_feedback_routes
 from webapp.routes import practice_recordings as practice_recordings_routes
 from webapp.routes import proposals as proposals_routes
 from webapp.routes import queues as queues_routes
 from webapp.routes import recommendations as recommendations_routes
 from webapp.routes import rooms as rooms_routes
 from webapp.routes import search as search_routes
+from webapp.routes import timeline as timeline_routes
 from webapp.routes import signal_ws as signal_ws_routes
 from webapp.routes import votes as votes_routes
 from webapp.settings import load_settings
 
 
 logger = logging.getLogger(__name__)
 
 
@@ -140,16 +141,17 @@ def create_app() -> FastAPI:
     app.include_router(practice_exhibits_routes.router)
     app.include_router(practice_feedback_routes.router)
     app.include_router(practice_recordings_routes.router)
     app.include_router(queues_routes.router)
     app.include_router(proposals_routes.router)
     app.include_router(signal_ws_routes.router)
     app.include_router(exhibits_routes.router)
     app.include_router(recommendations_routes.router)
+    app.include_router(timeline_routes.router)
     app.include_router(api_v1_routes.router)
 
     return app
 
 
 def _safe_url(url: str) -> str:
     """Strip the password from a connection URL before logging."""
     try:
diff --git a/webapp/maintenance.py b/webapp/maintenance.py
index 38972ad..fdedae4 100644
--- a/webapp/maintenance.py
+++ b/webapp/maintenance.py
@@ -1,41 +1,110 @@
 """
 Purpose: Run every background sweep (proposal expiry, missed sessions, stale
-  aborts) plus the starting-soon push on one 60-s cadence, so app-only clients
-  get correct lifecycle without page loads (roadmap §B1).
+  aborts), the starting-soon push, and the daily deadline-passed prompt on one
+  60-s cadence, so app-only clients get correct lifecycle without page loads
+  (roadmap §B1, §B7).
 Inputs: Settings (proposal_now_expiry_min, session_missed_after_min); the
-  practice_sessions / proposals tables via the repos.
-Outputs: state transitions (expired / missed / aborted), starting-soon pushes.
+  practice_sessions / proposals / user_firms tables via the repos.
+Outputs: state transitions (expired / missed / aborted), starting-soon pushes,
+  and deadline-passed prompts ("Did you interview at …?").
 Run: maintenance_loop() is spawned from webapp.main's lifespan; run one pass
   directly with run_maintenance_pass(load_settings()).
 """
 
 from __future__ import annotations
 
 import asyncio
+import datetime
 import logging
 
+from webapp.db import get_pool
+from webapp.push.events import push_to_user
 from webapp.push.starting_soon import notify_starting_soon
+from webapp.repositories import user_firms as user_firms_repo
 from webapp.repositories.practice_sessions import sweep_missed, sweep_stale_sessions
 from webapp.repositories.proposals import sweep_expired
 from webapp.settings import load_settings
 
 logger = logging.getLogger(__name__)
 
+# Daily guard for the deadline-passed sweep (B7): the 60-s loop scans the
+# user_firms deadline set at most once per calendar day. Correctness (no double
+# push) comes from the per-firm snooze_until throttle; this only avoids 1440
+# needless scans/day. Reset to None in tests to re-arm.
+_deadline_prompt_last_date: datetime.date | None = None
 
-async def run_maintenance_pass(settings) -> dict:
+
+def _deadline_notifications_allowed(user_id: int) -> bool:
+    """B5 seam. If notification_settings exists (B5 merged) honor the user's
+    session_reminders flag; otherwise (B5 unmerged, or any error) fail open so
+    the prompt still fires. Post-merge B5's push choke-point double-guards —
+    harmless (same result). Category mapping documented in the B7 report."""
+    try:
+        with get_pool().connection() as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT to_regclass('notification_settings');")
+                if cur.fetchone()[0] is None:
+                    return True
+                cur.execute(
+                    "SELECT session_reminders FROM notification_settings"
+                    " WHERE user_id = %(u)s;", {"u": user_id})
+                row = cur.fetchone()
+                return True if row is None else bool(row[0])
+    except Exception:
+        logger.exception("notification-settings seam failed; allowing push")
+        return True
+
+
+async def sweep_deadline_prompts(as_of: datetime.date | None = None) -> int:
+    """Push "Did you interview at {firm}?" for each still-tracking firm whose
+    deadline has passed and that isn't snoozed, then snooze it a week (weekly
+    re-ask). push_to_user self-guards when APNs is unconfigured. Returns the
+    number of prompts pushed."""
+    now = datetime.datetime.now(datetime.timezone.utc)
+    as_of = as_of or now.date()
+    snooze_until = now + datetime.timedelta(days=7)
+    sent = 0
+    for row in user_firms_repo.firms_needing_prompt(as_of):
+        if not _deadline_notifications_allowed(row["user_id"]):
+            continue
+        await push_to_user(
+            row["user_id"],
+            title="Did you interview?",
+            body=f"Did you interview at {row['firm_name']}? Tap to record it.",
+            data={"kind": "deadline_prompt", "firm_id": row["firm_id"]},
+        )
+        user_firms_repo.mark_prompted(row["user_id"], row["firm_id"], snooze_until)
+        sent += 1
+    return sent
+
+
+async def _guarded_deadline_prompts(as_of: datetime.date | None = None) -> int:
+    """Run sweep_deadline_prompts at most once per calendar day (daily guard)."""
+    global _deadline_prompt_last_date
+    today = as_of or datetime.datetime.now(datetime.timezone.utc).date()
+    if _deadline_prompt_last_date == today:
+        return 0
+    count = await sweep_deadline_prompts(today)
+    _deadline_prompt_last_date = today
+    return count
+
+
+async def run_maintenance_pass(settings, *, as_of: datetime.date | None = None) -> dict:
     """One sweep cycle. Order matters: sweep_missed marks past-start scheduled
-    sessions 'missed' before sweep_stale_sessions could abort them at +6 h."""
+    sessions 'missed' before sweep_stale_sessions could abort them at +6 h. The
+    deadline prompt is daily-guarded (B7)."""
     expired = sweep_expired(now_expiry_min=settings.proposal_now_expiry_min)
     missed = sweep_missed(missed_after_min=settings.session_missed_after_min)
     aborted = sweep_stale_sessions()
     starting_soon = await notify_starting_soon()
-    return {"expired": expired, "missed": missed,
-            "aborted": aborted, "starting_soon": starting_soon}
+    deadline_prompts = await _guarded_deadline_prompts(as_of)
+    return {"expired": expired, "missed": missed, "aborted": aborted,
+            "starting_soon": starting_soon, "deadline_prompts": deadline_prompts}
 
 
 async def maintenance_loop(interval_seconds: int = 60) -> None:
     """Run run_maintenance_pass() every interval_seconds forever. Sleep-FIRST so
     a short-lived app lifespan (e.g. every TestClient(app) startup) never fires a
     sweep against the shared dev DB — the 60-s startup delay is harmless in prod.
     One bad pass is logged and swallowed; CancelledError propagates (including
     during the sleep) for clean shutdown."""
diff --git a/webapp/readiness.py b/webapp/readiness.py
new file mode 100644
index 0000000..c36e711
--- /dev/null
+++ b/webapp/readiness.py
@@ -0,0 +1,79 @@
+"""
+Purpose: The B7 readiness signal — ONE swap-point (OD-B7-1 stand-in) that every
+  caller goes through — plus the reweight payload derived from the diagnostic +
+  recommendation engine. See docs/superpowers/notes/2026-07-17-readiness-signal-seams.md.
+Inputs:  user_id; dashboard repo (dimension averages, recommendations);
+  practice_sessions (recent candidate-finalized count).
+Outputs: readiness_signal() / reweight_payload() dicts. No side effects.
+Run:     from webapp import readiness; readiness.readiness_signal(user_id)
+"""
+
+from __future__ import annotations
+
+from webapp.db import get_pool
+from webapp.repositories import dashboard as dashboard_repo
+
+# Stand-in thresholds (OD-B7-1, DV-B7-3). dimension_averages is a /5 scale.
+READINESS_THRESHOLD = 3.0
+READINESS_MIN_CASES = 3
+DIAGNOSTIC_WINDOW_DAYS = 60
+
+
+def _recent_case_count(user_id: int, window_days: int = DIAGNOSTIC_WINDOW_DAYS) -> int:
+    with get_pool().connection() as conn:
+        with conn.cursor() as cur:
+            cur.execute(
+                "SELECT COUNT(*) FROM practice_sessions"
+                " WHERE candidate_id = %(u)s AND state = 'finalized'"
+                "   AND ended_at >= NOW() - make_interval(days => %(w)s);",
+                {"u": user_id, "w": window_days})
+            return int(cur.fetchone()[0])
+
+
+def readiness_signal(user_id: int) -> dict:
+    """Stand-in readiness (OD-B7-1): needs_work if the user has fewer than
+    READINESS_MIN_CASES recent candidate sessions OR their weakest dimension
+    averages below READINESS_THRESHOLD; else on_track. Firm-independent — the
+    per-firm display tag is derived in timeline_service (DV-B7-5)."""
+    dims = dashboard_repo.dimension_averages(user_id)   # ascending, /5
+    recent = _recent_case_count(user_id)
+    focus = dims[0]["dimension"] if dims else None
+    weakest_avg = float(dims[0]["avg_score"]) if dims else None
+    on_track = (recent >= READINESS_MIN_CASES
+                and weakest_avg is not None
+                and weakest_avg >= READINESS_THRESHOLD)
+    return {
+        "label": "on_track" if on_track else "needs_work",
+        "ready": on_track,
+        "focus_dimension": focus,
+        "recent_case_count": recent,
+        "threshold": READINESS_THRESHOLD,
+        "min_cases": READINESS_MIN_CASES,
+    }
+
+
+def suggested_drill_type(dimension: str | None) -> str:
+    """Map a rubric dimension name to one of the 3 existing drill generators
+    (webapp/drills.py _TYPES). Substring match keeps it robust to naming."""
+    if not dimension:
+        return "mental_math"
+    d = dimension.lower()
+    if "siz" in d:
+        return "market_sizing"
+    if "quant" in d or "math" in d or "numer" in d:
+        return "mental_math"
+    return "framework_recall"
+
+
+def reweight_payload(user_id: int) -> dict:
+    """The 'No offer → reweight' response (DESIGN DELTA). focus_dimension +
+    drill from the diagnostic; extra_cases from the B4 rec engine (limit 2 —
+    'two extra cases before BCG'). Derivation is a documented seam."""
+    sig = readiness_signal(user_id)
+    focus = sig["focus_dimension"]
+    recs = dashboard_repo.recommendations(user_id, [], limit=2)
+    return {
+        "focus_dimension": focus,
+        "suggested_drill_type": suggested_drill_type(focus),
+        "extra_cases": [r["case_id"] for r in recs],
+    }
diff --git a/webapp/repositories/dashboard.py b/webapp/repositories/dashboard.py
index 762817e..0db0357 100644
--- a/webapp/repositories/dashboard.py
+++ b/webapp/repositories/dashboard.py
@@ -13,16 +13,17 @@ from __future__ import annotations
 
 from psycopg.rows import dict_row
 
 from webapp.db import get_pool
 
 HISTORY_LIMIT = 50
 TREND_WINDOW = 10          # last N finalized-as-candidate sessions
 LADDER_MIN_GRADE = 4.0     # §4.8 rule 2 threshold over the last 3 grades
+DIAGNOSTIC_WINDOW_DAYS = 60   # spec §4 "cases done (2 mo)"
 
 _LADDER = {"Easy": "Medium", "Medium": "Hard"}   # DV-7; Hard has no +1
 
 
 def history(user_id: int, limit: int = HISTORY_LIMIT) -> list[dict]:
     """Finalized sessions the user took part in, newest first. The grade is
     session-scoped and both participants already see it post-finalize (P7),
     so it appears for interviewer rows too."""
@@ -274,8 +275,66 @@ def recommendations(user_id: int, exclude_case_ids: list[int] = [],
                         "case_id": row["id"],
                         "title": row["case_title"],
                         "case_type": row["case_type"],
                         "difficulty": row["difficulty"],
                         "why": row["why"],
                         "rule": rule,
                     })
     return out
+
+
+def _grade_trend(cur, user_id: int) -> dict:
+    """Mean grade of the last 5 finalized-as-candidate sessions vs the 5 before
+    them. Nulls where a window has no grades (delta/direction need both)."""
+    cur.execute(
+        """
+        WITH g AS (
+            SELECT f.grade,
+                   row_number() OVER (ORDER BY ps.ended_at DESC) AS rn
+            FROM practice_sessions ps JOIN feedback f ON f.session_id = ps.id
+            WHERE ps.state = 'finalized' AND ps.candidate_id = %(u)s
+              AND f.grade IS NOT NULL
+        )
+        SELECT AVG(grade) FILTER (WHERE rn <= 5)             AS recent_avg,
+               AVG(grade) FILTER (WHERE rn > 5 AND rn <= 10) AS previous_avg,
+               COUNT(*)   FILTER (WHERE rn <= 5)             AS recent_n,
+               COUNT(*)   FILTER (WHERE rn > 5 AND rn <= 10) AS previous_n
+        FROM g;
+        """,
+        {"u": user_id},
+    )
+    row = cur.fetchone()
+    recent = float(row["recent_avg"]) if row["recent_avg"] is not None else None
+    previous = float(row["previous_avg"]) if row["previous_avg"] is not None else None
+    delta = direction = None
+    if recent is not None and previous is not None:
+        delta = round(recent - previous, 2)
+        direction = "up" if delta > 0.05 else "down" if delta < -0.05 else "flat"
+    return {"recent_avg": round(recent, 2) if recent is not None else None,
+            "previous_avg": round(previous, 2) if previous is not None else None,
+            "delta": delta, "direction": direction}
+
+
+def diagnostic(user_id: int) -> dict:
+    """§4 Home diagnostic block. Dimension bars reuse dimension_averages (last-N
+    candidate sessions) so FOCUS matches the rec engine + readiness (DV-B7-4);
+    cases_done_60d is the only 60-day-windowed figure."""
+    dims = dimension_averages(user_id)                 # ascending by avg_score
+    strengths = list(reversed(dims[-2:])) if dims else []
+    weaknesses = dims[:2]
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                "SELECT COUNT(*)::int AS n FROM practice_sessions"
+                " WHERE candidate_id = %(u)s AND state = 'finalized'"
+                "   AND ended_at >= NOW() - make_interval(days => %(w)s);",
+                {"u": user_id, "w": DIAGNOSTIC_WINDOW_DAYS})
+            cases_done = cur.fetchone()["n"]
+            trend = _grade_trend(cur, user_id)
+    return {
+        "cases_done_60d": cases_done,
+        "dimensions": dims,
+        "strengths": strengths,
+        "weaknesses": weaknesses,
+        "focus_dimension": dims[0]["dimension"] if dims else None,
+        "trend": trend,
+    }
diff --git a/webapp/repositories/firms.py b/webapp/repositories/firms.py
new file mode 100644
index 0000000..52ba9bd
--- /dev/null
+++ b/webapp/repositories/firms.py
@@ -0,0 +1,40 @@
+"""
+Purpose: Read-only access to the firm reference table + curated interview
+  deadlines (migration 026) for the B7 timeline.
+Inputs:  firm_id; the firms / firm_deadlines tables via the shared pool.
+Outputs: plain dict rows (no side effects).
+Run:     from webapp.repositories import firms; firms.list_firms()
+"""
+
+from __future__ import annotations
+
+from psycopg.rows import dict_row
+
+from webapp.db import get_pool
+
+
+def list_firms() -> list[dict]:
+    """All firms, alphabetical — the add-a-firm catalog source."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute("SELECT id, name, slug FROM firms ORDER BY name;")
+            return cur.fetchall()
+
+
+def get_firm(firm_id: int) -> dict | None:
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute("SELECT id, name, slug FROM firms WHERE id = %(id)s;",
+                        {"id": firm_id})
+            return cur.fetchone()
+
+
+def all_deadlines() -> list[dict]:
+    """Every firm deadline; the timeline service groups these by firm_id and
+    picks the relevant one (soonest upcoming, else latest passed) in Python."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                "SELECT firm_id, cycle_label, deadline_date, region, is_estimate"
+                " FROM firm_deadlines ORDER BY firm_id, deadline_date;")
+            return cur.fetchall()
diff --git a/webapp/repositories/user_firms.py b/webapp/repositories/user_firms.py
new file mode 100644
index 0000000..d8629cf
--- /dev/null
+++ b/webapp/repositories/user_firms.py
@@ -0,0 +1,133 @@
+"""
+Purpose: Per-user firm tracking + post-deadline prompt state (migration 027)
+  for the B7 timeline.
+Inputs:  user_id, firm_id, status/snooze values; user_firms + firms tables.
+Outputs: dict rows; UPDATE/DELETE side effects on user_firms.
+Run:     from webapp.repositories import user_firms; user_firms.track(uid, fid)
+"""
+
+from __future__ import annotations
+
+import datetime
+
+from psycopg.rows import dict_row
+
+from webapp.db import get_pool
+
+_ROW = "user_id, firm_id, status, added_at, result_recorded_at, snooze_until"
+
+
+def track(user_id: int, firm_id: int) -> dict:
+    """Start tracking a firm. Idempotent — a second track is a no-op that
+    returns the existing row (a recorded result is never silently reset)."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"INSERT INTO user_firms (user_id, firm_id) VALUES (%(u)s, %(f)s)"
+                f" ON CONFLICT (user_id, firm_id) DO NOTHING RETURNING {_ROW};",
+                {"u": user_id, "f": firm_id})
+            row = cur.fetchone()
+            if row is None:                      # already tracked
+                cur.execute(
+                    f"SELECT {_ROW} FROM user_firms"
+                    f" WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                    {"u": user_id, "f": firm_id})
+                row = cur.fetchone()
+            return row
+
+
+def untrack(user_id: int, firm_id: int) -> int:
+    with get_pool().connection() as conn:
+        with conn.cursor() as cur:
+            cur.execute(
+                "DELETE FROM user_firms WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id})
+            return cur.rowcount
+
+
+def is_tracked(user_id: int, firm_id: int) -> bool:
+    with get_pool().connection() as conn:
+        with conn.cursor() as cur:
+            cur.execute(
+                "SELECT 1 FROM user_firms WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id})
+            return cur.fetchone() is not None
+
+
+def get(user_id: int, firm_id: int) -> dict | None:
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"SELECT {_ROW} FROM user_firms"
+                f" WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id})
+            return cur.fetchone()
+
+
+def list_tracked(user_id: int) -> list[dict]:
+    """Tracked firms with their firm name/slug, soonest deadline computed by
+    the caller. Ordered by added_at for a stable list."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                "SELECT uf.firm_id, f.name, f.slug, uf.status, uf.added_at,"
+                "       uf.snooze_until, uf.result_recorded_at"
+                " FROM user_firms uf JOIN firms f ON f.id = uf.firm_id"
+                " WHERE uf.user_id = %(u)s ORDER BY uf.added_at;",
+                {"u": user_id})
+            return cur.fetchall()
+
+
+def record_result(user_id: int, firm_id: int, status: str) -> dict | None:
+    """Offer='offer' / No offer='rejected' — stamps result_recorded_at, clears
+    any snooze. Returns None if the user doesn't track the firm (IDOR guard)."""
+    if status not in ("offer", "rejected"):
+        raise ValueError(f"record_result status must be offer|rejected, got {status!r}")
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"UPDATE user_firms SET status = %(s)s, result_recorded_at = NOW(),"
+                f" snooze_until = NULL"
+                f" WHERE user_id = %(u)s AND firm_id = %(f)s RETURNING {_ROW};",
+                {"u": user_id, "f": firm_id, "s": status})
+            return cur.fetchone()
+
+
+def mark_waiting(user_id: int, firm_id: int, days: int = 7) -> dict | None:
+    """Waiting → interviewed + re-ask in `days`. Returns None if untracked."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"UPDATE user_firms SET status = 'interviewed',"
+                f" snooze_until = NOW() + make_interval(days => %(d)s)"
+                f" WHERE user_id = %(u)s AND firm_id = %(f)s RETURNING {_ROW};",
+                {"u": user_id, "f": firm_id, "d": days})
+            return cur.fetchone()
+
+
+def firms_needing_prompt(as_of: datetime.date) -> list[dict]:
+    """Still-tracking firms whose deadline has passed and that aren't snoozed —
+    the deadline-passed push targets. NOW() (not as_of) gates the snooze so a
+    real-time snooze window is honored."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                "SELECT DISTINCT uf.user_id, uf.firm_id, f.name AS firm_name"
+                " FROM user_firms uf JOIN firms f ON f.id = uf.firm_id"
+                " WHERE uf.status = 'tracking'"
+                "   AND (uf.snooze_until IS NULL OR uf.snooze_until < NOW())"
+                "   AND EXISTS (SELECT 1 FROM firm_deadlines d"
+                "               WHERE d.firm_id = uf.firm_id"
+                "                 AND d.deadline_date < %(as_of)s);",
+                {"as_of": as_of})
+            return cur.fetchall()
+
+
+def mark_prompted(user_id: int, firm_id: int, snooze_until) -> None:
+    """Throttle the auto prompt: set snooze_until (typically NOW()+7d)."""
+    with get_pool().connection() as conn:
+        with conn.cursor() as cur:
+            cur.execute(
+                "UPDATE user_firms SET snooze_until = %(s)s"
+                " WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id, "s": snooze_until})
diff --git a/webapp/routes/api_v1.py b/webapp/routes/api_v1.py
index f05a045..28e7993 100644
--- a/webapp/routes/api_v1.py
+++ b/webapp/routes/api_v1.py
@@ -21,16 +21,17 @@ from webapp.auth.sessions import (
     clear_session_cookie,
     create_session,
     destroy_session,
 )
 from webapp.auth.users import User, authenticate
 from webapp.csrf import require_same_origin
 from webapp.db import get_pool
 from webapp import drills
+from webapp import timeline_service
 from webapp.preview_urls import preview_page_urls
 from webapp.push.events import push_to_user
 from webapp.repositories import availability as availability_repo
 from webapp.repositories import dashboard as dashboard_repo
 from webapp.repositories import device_tokens as repo
 from webapp.repositories import drill_attempts as drills_repo
 from webapp.repositories import live_activity_tokens as live_activity_repo
 from webapp.repositories import practice_sessions as sessions_repo
@@ -369,9 +370,14 @@ def dashboard(user: User = Depends(require_auth_api)):
         "next_session": next_session,
         "streak_days": drills_repo.streak_days(user.id),
         "drill_done_today": drills_repo.attempted_today(user.id),
         # B4 §7 Home card: the recommendation engine's two candidate-facing
         # surfaces travel on the dashboard payload (dimension_averages =
         # existing web shape, recommendations = canonical item shape).
         "dimension_averages": dashboard_repo.dimension_averages(user.id),
         "recommendations": dashboard_repo.recommendations(user.id),
+        # B7 §4 Home: diagnostic block + timeline summary (next deadline across
+        # tracked firms). Additive — no existing key changes.
+        "diagnostic": dashboard_repo.diagnostic(user.id),
+        "timeline": timeline_service.next_deadline_summary(
+            user.id, datetime.now(timezone.utc).date()),
     }
diff --git a/webapp/routes/timeline.py b/webapp/routes/timeline.py
new file mode 100644
index 0000000..6ffdc25
--- /dev/null
+++ b/webapp/routes/timeline.py
@@ -0,0 +1,96 @@
+"""
+Purpose: /api/v1/timeline* — track/untrack firms, the timeline-detail payload,
+  and the post-deadline result flow (Offer / No offer→reweight / Waiting /
+  Didn't interview) for the B7 Home + Timeline-detail screens.
+Inputs:  session cookie (require_auth_api); firm_id path/body; outcome body.
+Outputs: JSON timeline payloads; user_firms writes (track/untrack/result).
+Run:     GET /api/v1/timeline  (Cookie: caseroom_session=…)
+"""
+
+from __future__ import annotations
+
+import datetime
+
+from fastapi import APIRouter, Depends, HTTPException
+from fastapi.responses import Response
+from pydantic import BaseModel
+
+from webapp import timeline_service
+from webapp.auth.dependencies import require_auth_api
+from webapp.auth.users import User
+from webapp.csrf import require_same_origin
+from webapp.readiness import reweight_payload
+from webapp.repositories import firms as firms_repo
+from webapp.repositories import user_firms as user_firms_repo
+
+router = APIRouter(prefix="/api/v1")
+_MUTATING = [Depends(require_same_origin)]
+
+_OUTCOMES = {"offer", "no_offer", "waiting", "didnt_interview"}
+
+
+def _today() -> datetime.date:
+    return datetime.datetime.now(datetime.timezone.utc).date()
+
+
+class TrackFirmBody(BaseModel):
+    firm_id: int
+
+
+class ResultBody(BaseModel):
+    outcome: str
+
+
+@router.get("/timeline")
+def get_timeline(user: User = Depends(require_auth_api)):
+    return timeline_service.timeline_view(user.id, _today())
+
+
+@router.get("/timeline/firms")
+def list_firms_catalog(user: User = Depends(require_auth_api)):
+    return {"firms": timeline_service.firm_catalog(user.id, _today())}
+
+
+@router.post("/timeline/firms", dependencies=_MUTATING)
+def track_firm(body: TrackFirmBody, user: User = Depends(require_auth_api)):
+    firm = firms_repo.get_firm(body.firm_id)
+    if firm is None:
+        raise HTTPException(status_code=404, detail="No such firm")
+    row = user_firms_repo.track(user.id, body.firm_id)
+    return {"firm_id": firm["id"], "name": firm["name"], "slug": firm["slug"],
+            "status": row["status"]}
+
+
+@router.delete("/timeline/firms/{firm_id}", status_code=204, dependencies=_MUTATING)
+def untrack_firm(firm_id: int, user: User = Depends(require_auth_api)):
+    # Idempotent: deleting an untracked firm is a 204 no-op (nothing leaked).
+    user_firms_repo.untrack(user.id, firm_id)
+    return Response(status_code=204)
+
+
+@router.post("/timeline/firms/{firm_id}/result", dependencies=_MUTATING)
+def record_result(firm_id: int, body: ResultBody, user: User = Depends(require_auth_api)):
+    """Post-deadline flow. outcome ∈ _OUTCOMES. A user can only resolve a firm
+    THEY track — an untracked firm_id is 404 (IDOR guard; identity is the
+    session, never a param)."""
+    if body.outcome not in _OUTCOMES:
+        raise HTTPException(status_code=400,
+                            detail=f"outcome must be one of {sorted(_OUTCOMES)}")
+    if not user_firms_repo.is_tracked(user.id, firm_id):
+        raise HTTPException(status_code=404, detail="Not tracking this firm")
+
+    if body.outcome == "offer":
+        row = user_firms_repo.record_result(user.id, firm_id, "offer")
+        return {"outcome": "offer", "status": "offer",
+                "result_recorded_at": row["result_recorded_at"].isoformat()}
+    if body.outcome == "no_offer":
+        user_firms_repo.record_result(user.id, firm_id, "rejected")
+        return {"outcome": "no_offer", "status": "rejected",
+                "reweight": reweight_payload(user.id)}
+    if body.outcome == "waiting":
+        row = user_firms_repo.mark_waiting(user.id, firm_id, days=7)
+        return {"outcome": "waiting", "status": "interviewed",
+                "snooze_until": row["snooze_until"].isoformat()}
+    # didnt_interview → drops off the line (DV-B7-1).
+    user_firms_repo.untrack(user.id, firm_id)
+    return {"outcome": "didnt_interview", "dropped": True}
diff --git a/webapp/timeline_service.py b/webapp/timeline_service.py
new file mode 100644
index 0000000..1c589ed
--- /dev/null
+++ b/webapp/timeline_service.py
@@ -0,0 +1,113 @@
+"""
+Purpose: Assemble tracked firms + curated deadlines + the readiness signal into
+  the B7 timeline payloads (GET /api/v1/timeline, /timeline/firms, and the
+  dashboard timeline summary).
+Inputs:  user_id, as_of (date, passed explicitly for determinism); firms +
+  user_firms repos; readiness swap-point.
+Outputs: plain dicts for the routers. No side effects.
+Run:     from webapp import timeline_service; timeline_service.timeline_view(uid, date.today())
+"""
+
+from __future__ import annotations
+
+import datetime
+
+from webapp import readiness
+from webapp.repositories import firms as firms_repo
+from webapp.repositories import user_firms as user_firms_repo
+
+# Far-out deadlines read as 'early' regardless of readiness (DV-B7-5).
+EARLY_DEADLINE_DAYS = 75
+
+
+def _deadlines_by_firm() -> dict[int, list[dict]]:
+    out: dict[int, list[dict]] = {}
+    for d in firms_repo.all_deadlines():
+        out.setdefault(d["firm_id"], []).append(d)
+    return out
+
+
+def _relevant_deadline(deadlines: list[dict], as_of: datetime.date) -> dict | None:
+    """Soonest upcoming deadline, else the latest passed one (the prompt anchor)."""
+    if not deadlines:
+        return None
+    upcoming = sorted((d for d in deadlines if d["deadline_date"] >= as_of),
+                      key=lambda d: d["deadline_date"])
+    if upcoming:
+        return upcoming[0]
+    return sorted(deadlines, key=lambda d: d["deadline_date"])[-1]
+
+
+def _deadline_block(d: dict | None, as_of: datetime.date) -> dict | None:
+    if d is None:
+        return None
+    days = (d["deadline_date"] - as_of).days
+    return {
+        "cycle_label": d["cycle_label"],
+        "deadline_date": d["deadline_date"].isoformat(),
+        "region": d["region"],
+        "is_estimate": d["is_estimate"],
+        "days_remaining": days,
+        "passed": days < 0,
+    }
+
+
+def _firm_tag(signal: dict, block: dict | None) -> str:
+    """Per-firm display tag over the firm-independent swap-point (DV-B7-5):
+    'early' when the deadline is far out, else on_track/focus from readiness."""
+    if block is not None and not block["passed"] and block["days_remaining"] > EARLY_DEADLINE_DAYS:
+        return "early"
+    return "on_track" if signal["ready"] else "focus"
+
+
+def timeline_view(user_id: int, as_of: datetime.date) -> dict:
+    """The 7b Timeline-detail payload: tracked firms + per-firm deadline +
+    readiness tag + post-deadline prompt state, plus the top-level signal."""
+    signal = readiness.readiness_signal(user_id)
+    by_firm = _deadlines_by_firm()
+    rows = []
+    for uf in user_firms_repo.list_tracked(user_id):
+        block = _deadline_block(_relevant_deadline(by_firm.get(uf["firm_id"], []), as_of), as_of)
+        rows.append({
+            "firm_id": uf["firm_id"],
+            "name": uf["name"],
+            "slug": uf["slug"],
+            "status": uf["status"],
+            "added_at": uf["added_at"].isoformat() if uf["added_at"] else None,
+            "deadline": block,
+            "readiness_tag": _firm_tag(signal, block),
+            # Prompt shows only for a still-tracking firm whose deadline passed.
+            "prompt": {"show": bool(block and block["passed"] and uf["status"] == "tracking")},
+        })
+    return {"as_of": as_of.isoformat(), "readiness": signal, "firms": rows}
+
+
+def firm_catalog(user_id: int, as_of: datetime.date) -> list[dict]:
+    """All firms with a tracked flag + next deadline — the add-a-firm picker."""
+    tracked_ids = {uf["firm_id"] for uf in user_firms_repo.list_tracked(user_id)}
+    by_firm = _deadlines_by_firm()
+    out = []
+    for f in firms_repo.list_firms():
+        block = _deadline_block(_relevant_deadline(by_firm.get(f["id"], []), as_of), as_of)
+        out.append({"firm_id": f["id"], "name": f["name"], "slug": f["slug"],
+                    "tracked": f["id"] in tracked_ids, "next_deadline": block})
+    return out
+
+
+def next_deadline_summary(user_id: int, as_of: datetime.date) -> dict:
+    """Dashboard timeline block: soonest UPCOMING deadline across tracked firms
+    + tracked_count. next_deadline is None when nothing is tracked or all
+    deadlines have passed."""
+    view = timeline_view(user_id, as_of)
+    upcoming = [f for f in view["firms"]
+                if f["deadline"] and not f["deadline"]["passed"]]
+    upcoming.sort(key=lambda f: f["deadline"]["days_remaining"])
+    nxt = None
+    if upcoming:
+        f = upcoming[0]
+        nxt = {"firm_id": f["firm_id"], "name": f["name"], "slug": f["slug"],
+               "cycle_label": f["deadline"]["cycle_label"],
+               "deadline_date": f["deadline"]["deadline_date"],
+               "days_remaining": f["deadline"]["days_remaining"],
+               "readiness_tag": f["readiness_tag"]}
+    return {"tracked_count": len(view["firms"]), "next_deadline": nxt}
