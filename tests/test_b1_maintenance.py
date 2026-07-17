"""
B1 Task 7: consolidated 60-s maintenance pass (webapp/maintenance.py). Seeds an
expired proposal + a missed session, patches push so no network fires, and
asserts one pass sweeps all of them. Needs seeded dev Postgres.
"""

from __future__ import annotations

import unittest
from unittest.mock import patch

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestMaintenancePass(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES ('B1 Maint Case', 'b1 maint case',"
                    " 'DevSchool', 2090, 'Technology', 'Profitability', 'Easy', 3.0,"
                    " 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]
        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        from webapp.repositories.rooms import get_or_create_room
        cls.room_id = get_or_create_room(cls.aid)["id"]
        cls.template_id = get_default_rubric_template_id(cls.case_id, cls.aid)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM proposals WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    async def test_one_pass_sweeps_expired_and_missed(self):
        import psycopg
        from webapp import maintenance
        from webapp.settings import load_settings

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO proposals (from_user_id, to_user_id, case_id, from_role,"
                    " proposed_times_json, state, created_at) VALUES"
                    " (%s, %s, %s, 'interviewer', '[]'::jsonb, 'pending',"
                    " NOW() - INTERVAL '3 hours') RETURNING id;",
                    (self.aid, self.bid, self.case_id))
                prop_id = cur.fetchone()[0]
                cur.execute(
                    "INSERT INTO practice_sessions (room_id, interviewer_id, candidate_id,"
                    " case_id, rubric_template_id, state, scheduled_at, state_changed_at)"
                    " VALUES (%s, %s, %s, %s, %s, 'scheduled', NOW() - INTERVAL '2 hours',"
                    " NOW()) RETURNING id;",
                    (self.room_id, self.aid, self.bid, self.case_id, self.template_id))
                sess_id = cur.fetchone()[0]

        async def _no_push(*a, **k):
            return None

        with patch("webapp.push.starting_soon.push_to_user", _no_push):
            counts = await maintenance.run_maintenance_pass(load_settings())

        self.assertGreaterEqual(counts["expired"], 1)
        self.assertGreaterEqual(counts["missed"], 1)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT state FROM proposals WHERE id = %s;", (prop_id,))
                self.assertEqual(cur.fetchone()[0], "expired")
                cur.execute("SELECT state FROM practice_sessions WHERE id = %s;", (sess_id,))
                self.assertEqual(cur.fetchone()[0], "missed")


if __name__ == "__main__":
    unittest.main()
