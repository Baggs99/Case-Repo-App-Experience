"""B3 Task 9: per-case rating aggregates on Library payloads. Needs seeded dev Postgres."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
from tests.test_b3_recap_gate import _seed_finalized_session, _purge_session


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestCaseAggregates(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.bob = cls._ctx.__enter__()   # candidate (burned on the case)
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = ANY(%s) ORDER BY email;",
                        (["a@yale.edu", "b@yale.edu"],))
            cls.aid, cls.bid = (r[0] for r in cur.fetchall())
        s = create_session(cls.bid, user_agent="b3", ip_address=None)
        cls.bob.cookies.set(SESSION_COOKIE_NAME, s.id)
        # Finalized+closed session on a fresh case, rated 5, burned for Bob.
        cls.sid, cls.case_id = _seed_finalized_session(cls.aid, cls.bid, "B3 Agg Case")
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("UPDATE feedback SET case_rating = 5, closed_at = NOW()"
                        " WHERE session_id = %s;", (cls.sid,))
            cur.execute("INSERT INTO burned (user_id, case_id, session_id)"
                        " VALUES (%s,%s,%s) ON CONFLICT DO NOTHING;",
                        (cls.bid, cls.case_id, cls.sid))

    @classmethod
    def tearDownClass(cls):
        import psycopg
        _purge_session(cls.sid)   # also deletes the burned row
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_detail_has_aggregates(self):
        r = self.bob.get(f"/api/v1/cases/{self.case_id}")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["avg_rating"], 5.0)
        self.assertEqual(body["run_count"], 1)
        self.assertTrue(body["done_for_you"])

    def test_list_has_counts_and_flags(self):
        r = self.bob.get("/api/v1/cases?q=B3 Agg Case")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("open_count", body)
        self.assertIn("done_count", body)
        rows = {c["id"]: c for c in body["cases"]}
        self.assertTrue(rows[self.case_id]["done_for_you"])
        self.assertEqual(rows[self.case_id]["avg_rating"], 5.0)
