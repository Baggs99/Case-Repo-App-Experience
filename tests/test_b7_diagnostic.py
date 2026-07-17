"""B7 Task 4: dashboard.diagnostic() block. Reuses the test_dashboard fixture
shape. Cara has 3 finalized-as-candidate sessions; grades 4.5/4.0/4.2 give a
recent_avg over the last ≤5 and previous_avg=None (fewer than 6 sessions)."""

from __future__ import annotations

import json
import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

# All FIVE generic-template dimensions must be seeded: dimension_averages
# iterates the template's items and COALESCEs a missing dimension to 0, so an
# unseeded dim (insight/synthesis) would score 0.0 and steal "weakest" from
# quant. These values (mirroring tests/test_dashboard.py) make quant strictly
# weakest (1.0/5) and communication strongest (4.33/5).
_SESSIONS = [
    {"grade": 4.5, "pts": {"structure": 4, "quant": 2, "insight": 3,
                           "communication": 5, "synthesis": 1}},
    {"grade": 4.0, "pts": {"structure": 3, "quant": 0, "insight": 4,
                           "communication": 4, "synthesis": 2}},
    {"grade": 4.2, "pts": {"structure": 5, "quant": 1, "insight": 4,
                           "communication": 4, "synthesis": 3}},
]


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDiagnostic(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Enter the app lifespan so the shared connection pool is initialized
        # (get_or_create_room / get_default_rubric_template_id and
        # dashboard.diagnostic all go through webapp.db.get_pool()). Must precede
        # any pool-backed call below. Matches test_b7_readiness.
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()

        import psycopg
        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        from webapp.repositories.rooms import get_or_create_room
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.cid = ids["a@yale.edu"], ids["c@yale.edu"]
        room_id = get_or_create_room(cls.aid)["id"]
        cls.case_ids, cls.session_ids = [], []
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                for i in range(3):
                    cur.execute(
                        "INSERT INTO cases (case_title, normalized_title,"
                        " source_school, source_year, industry, case_type,"
                        " difficulty, difficulty_score, page_count, pdf_path)"
                        " VALUES (%s, %s, 'DevSchool', 2097, 'Technology',"
                        " 'B7-Dg', 'Easy', 3, 2, 'output/none.pdf') RETURNING id;",
                        (f"B7 Dg Case {i}", f"b7 dg case {i}"))
                    cls.case_ids.append(cur.fetchone()[0])
                template_id = get_default_rubric_template_id(cls.case_ids[0], cls.aid)
                for i, spec in enumerate(_SESSIONS):
                    cur.execute(
                        "INSERT INTO practice_sessions (room_id, interviewer_id,"
                        " candidate_id, case_id, rubric_template_id, state,"
                        " consent_interviewer, consent_candidate, started_at,"
                        " ended_at, state_changed_at)"
                        " VALUES (%s, %s, %s, %s, %s, 'finalized', TRUE, TRUE,"
                        " NOW() - (%s + 1) * INTERVAL '1 day',"
                        " NOW() - (%s + 1) * INTERVAL '1 day' + INTERVAL '45 min',"
                        " NOW()) RETURNING id;",
                        (room_id, cls.aid, cls.cid, cls.case_ids[i], template_id, i, i))
                    sid = cur.fetchone()[0]
                    cls.session_ids.append(sid)
                    items = {d: {"points": p, "note": ""} for d, p in spec["pts"].items()}
                    cur.execute(
                        "INSERT INTO feedback (session_id, rubric_json, notes_md,"
                        " grade, finalized_at) VALUES (%s, %s, 'fx', %s, NOW());",
                        (sid, json.dumps({"items": items}), spec["grade"]))

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
                            (cls.session_ids,))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    def test_diagnostic_shape_and_values(self):
        from webapp.repositories import dashboard
        d = dashboard.diagnostic(self.cid)
        self.assertEqual(d["cases_done_60d"], 3)
        self.assertEqual(d["focus_dimension"], "quant")           # weakest
        self.assertEqual(d["weaknesses"][0]["dimension"], "quant")  # lowest first
        self.assertEqual(d["strengths"][0]["dimension"], "communication")  # highest first
        self.assertLessEqual(len(d["strengths"]), 2)
        self.assertLessEqual(len(d["weaknesses"]), 2)

    def test_trend_recent_only_when_thin(self):
        from webapp.repositories import dashboard
        d = dashboard.diagnostic(self.cid)
        # 3 grades → recent_avg = mean(4.5,4.0,4.2) ≈ 4.23; previous window empty.
        self.assertAlmostEqual(d["trend"]["recent_avg"], 4.2333, places=2)
        self.assertIsNone(d["trend"]["previous_avg"])
        self.assertIsNone(d["trend"]["delta"])
        self.assertIsNone(d["trend"]["direction"])

    def test_diagnostic_empty_user(self):
        from webapp.repositories import dashboard
        d = dashboard.diagnostic(self.aid)   # no candidate sessions here
        self.assertEqual(d["cases_done_60d"], 0)
        self.assertIsNone(d["focus_dimension"])
        self.assertEqual(d["strengths"], [])
        self.assertEqual(d["weaknesses"], [])
        self.assertIsNone(d["trend"]["recent_avg"])


if __name__ == "__main__":
    unittest.main()
