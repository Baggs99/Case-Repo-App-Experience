"""
B1 Task 6: A3 expiry (now/scheduled/countered proposals) and missed sessions.
Needs seeded dev Postgres. Seeds rows directly, calls the sweep repo fns, and
asserts state — no push/network involved.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
class TestExpiryAndMissed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()  # init pool
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES ('B1 Expiry Case', 'b1 expiry case',"
                    " 'DevSchool', 2091, 'Technology', 'Profitability', 'Easy', 3.0,"
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

    def _proposal(self, *, proposed=None, countered=None, state="pending", created_sql="NOW()"):
        import json
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO proposals (from_user_id, to_user_id, case_id, from_role,"
                    " proposed_times_json, counter_times_json, state, created_at)"
                    f" VALUES (%s, %s, %s, 'interviewer', %s, %s, %s, {created_sql})"
                    " RETURNING id;",
                    (self.aid, self.bid, self.case_id,
                     json.dumps(proposed) if proposed is not None else None,
                     json.dumps(countered) if countered is not None else None,
                     state))
                return cur.fetchone()[0]

    def _state(self, table, pid):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(f"SELECT state FROM {table} WHERE id = %s;", (pid,))
                return cur.fetchone()[0]

    def test_now_proposal_expires_after_window(self):
        from webapp.repositories.proposals import sweep_expired
        pid = self._proposal(proposed=[], created_sql="NOW() - INTERVAL '3 hours'")
        sweep_expired(now_expiry_min=120)
        self.assertEqual(self._state("proposals", pid), "expired")

    def test_fresh_now_proposal_survives(self):
        from webapp.repositories.proposals import sweep_expired
        pid = self._proposal(proposed=[])
        sweep_expired(now_expiry_min=120)
        self.assertEqual(self._state("proposals", pid), "pending")

    def test_scheduled_proposal_expires_at_earliest_start(self):
        from webapp.repositories.proposals import sweep_expired
        past = (datetime.now(timezone.utc).replace(microsecond=0)).isoformat()
        # earliest proposed time already elapsed
        pid = self._proposal(proposed=["2000-01-01T00:00:00+00:00", past])
        sweep_expired()
        self.assertEqual(self._state("proposals", pid), "expired")

    def test_future_scheduled_survives(self):
        from webapp.repositories.proposals import sweep_expired
        pid = self._proposal(proposed=["2999-01-01T00:00:00+00:00"])
        sweep_expired()
        self.assertEqual(self._state("proposals", pid), "pending")

    def test_countered_proposal_expires_at_earliest_counter(self):
        from webapp.repositories.proposals import sweep_expired
        pid = self._proposal(state="countered", countered=["2000-01-01T00:00:00+00:00"])
        sweep_expired()
        self.assertEqual(self._state("proposals", pid), "expired")

    def _session(self, *, state, scheduled_sql):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO practice_sessions (room_id, interviewer_id, candidate_id,"
                    " case_id, rubric_template_id, state, scheduled_at, state_changed_at)"
                    f" VALUES (%s, %s, %s, %s, %s, %s, {scheduled_sql}, NOW())"
                    " RETURNING id;",
                    (self.room_id, self.aid, self.bid, self.case_id, self.template_id, state))
                return cur.fetchone()[0]

    def test_session_missed_past_start_plus_window(self):
        from webapp.repositories.practice_sessions import sweep_missed
        sid = self._session(state="scheduled", scheduled_sql="NOW() - INTERVAL '2 hours'")
        n = sweep_missed(missed_after_min=60)
        self.assertGreaterEqual(n, 1)
        self.assertEqual(self._state("practice_sessions", sid), "missed")

    def test_session_not_missed_before_window(self):
        from webapp.repositories.practice_sessions import sweep_missed
        sid = self._session(state="scheduled", scheduled_sql="NOW() + INTERVAL '10 minutes'")
        sweep_missed(missed_after_min=60)
        self.assertEqual(self._state("practice_sessions", sid), "scheduled")

    def test_now_session_without_scheduled_at_not_missed(self):
        from webapp.repositories.practice_sessions import sweep_missed
        sid = self._session(state="scheduled", scheduled_sql="NULL")
        sweep_missed(missed_after_min=60)
        self.assertEqual(self._state("practice_sessions", sid), "scheduled")


if __name__ == "__main__":
    unittest.main()
