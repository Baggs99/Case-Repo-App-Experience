# Task 4 diff package (BASE 49e1639 .. HEAD)

## git log
293d41b Add dashboard.diagnostic() home block (cases done, strengths/weaknesses, trend)

## diff --stat
 tests/test_b7_diagnostic.py      | 124 +++++++++++++++++++++++++++++++++++++++
 webapp/repositories/dashboard.py |  59 +++++++++++++++++++
 2 files changed, 183 insertions(+)

## full diff
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
diff --git a/webapp/repositories/dashboard.py b/webapp/repositories/dashboard.py
index 762817e..0db0357 100644
--- a/webapp/repositories/dashboard.py
+++ b/webapp/repositories/dashboard.py
@@ -11,20 +11,21 @@ difficulty_score (DV-7).
 
 from __future__ import annotations
 
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
     sql = """
         SELECT ps.id, ps.ended_at, c.case_title, c.id AS case_id,
@@ -272,10 +273,68 @@ def recommendations(user_id: int, exclude_case_ids: list[int] = [],
                     seen.add(row["id"])
                     out.append({
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
