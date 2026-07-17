"""B6 Task 6: leaderboards API — school standing, schools board, school-leader
rollup. Auth + role gating + NO population counts. Needs seeded Postgres + httpx."""

from __future__ import annotations

import unittest

from tests.test_b6_connections_api import _assert_no_counts  # shared no-count auditor
from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestLeaderboardsApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute("SELECT school_id FROM users WHERE id = %s;", (ids["a@yale.edu"],))
                cls.sid = cur.fetchone()[0]
        cls.a, cls.b = ids["a@yale.edu"], ids["b@yale.edu"]
        for client, uid in ((cls.alice, cls.a), (cls.bob, cls.b)):
            s = create_session(uid, user_agent="b6-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM school_leaders WHERE user_id = ANY(%s);",
                            ([self.a, self.b],))

    def test_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        self.assertEqual(TestClient(app).get("/api/v1/leaderboards/schools").status_code, 401)

    def test_schools_board_no_counts(self):
        r = self.alice.get("/api/v1/leaderboards/schools")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertIn("schools", body)
        _assert_no_counts(self, body)
        if body["schools"]:
            self.assertIn("campus_city", body["schools"][0])
            self.assertIn("avg_member_percentile", body["schools"][0])

    def test_my_school_standing_no_counts(self):
        r = self.alice.get("/api/v1/leaderboards/school")
        self.assertEqual(r.status_code, 200)
        _assert_no_counts(self, r.json())

    def test_school_leader_rollup_gated(self):
        # Not a leader -> 403
        self.assertEqual(
            self.alice.get(f"/api/v1/leaderboards/schools/{self.sid}/groups").status_code, 403)
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO school_leaders (school_id, user_id) VALUES (%s,%s)"
                            " ON CONFLICT DO NOTHING;", (self.sid, self.a))
        r = self.alice.get(f"/api/v1/leaderboards/schools/{self.sid}/groups")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("groups", r.json())
        _assert_no_counts(self, r.json())
        # bob (not a leader) still 403
        self.assertEqual(
            self.bob.get(f"/api/v1/leaderboards/schools/{self.sid}/groups").status_code, 403)
