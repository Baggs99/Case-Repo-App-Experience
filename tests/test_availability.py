"""
Task 3 (P4): free-now availability — repo + /api/v1/availability endpoints
and the fresh-toggle instant-match push.

Needs the seeded dev Postgres — skips cleanly otherwise. Uses the same
login/cookie fixture idiom as tests/test_api_v1_devices.py; the push
assertion monkeypatches api_v1's imported push_to_user (patched where it's
used) mirroring tests/test_push_events.py.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestAvailability(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()  # runs app startup so get_pool() is ready
        cls.bob = TestClient(app)  # separate cookie jar

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid = ids["a@yale.edu"]
        cls.bid = ids["b@yale.edu"]

        session = create_session(cls.aid, user_agent="p4-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, session.id)
        bob_session = create_session(cls.bid, user_agent="p4-test", ip_address=None)
        cls.bob.cookies.set(SESSION_COOKIE_NAME, bob_session.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def _clean(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM availability WHERE user_id = ANY(%s);",
                            ([self.aid, self.bid],))

    def setUp(self):
        self._clean()

    def tearDown(self):
        self._clean()

    # ── PUT: sets free window, row present, others excludes self ────────────

    def test_put_sets_window_and_excludes_self(self):
        import psycopg

        r = self.alice.put("/api/v1/availability", json={"minutes": 60})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("free_until", body)
        self.assertIn("others", body)
        self.assertIsInstance(body["others"], list)

        free_until = datetime.fromisoformat(body["free_until"])
        expected = datetime.now(timezone.utc) + timedelta(minutes=60)
        self.assertLess(abs((free_until - expected).total_seconds()), 120)

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT free_until > now() FROM availability WHERE user_id = %s;",
                            (self.aid,))
                row = cur.fetchone()
        self.assertIsNotNone(row)
        self.assertTrue(row[0])

        # Bob free too; Alice re-PUTs (extends) — others carries Bob, never self.
        self.assertEqual(self.bob.put("/api/v1/availability", json={"minutes": 30}).status_code, 200)
        r = self.alice.put("/api/v1/availability", json={"minutes": 60})
        self.assertEqual(r.status_code, 200, r.text)
        others = r.json()["others"]
        ids = {o["user_id"] for o in others}
        self.assertIn(self.bid, ids)
        self.assertNotIn(self.aid, ids)
        for o in others:
            self.assertEqual(set(o), {"user_id", "name", "free_until"})

    # ── Lazy expiry: an expired row reads as not-free, no sweep ─────────────

    def test_expiry_is_lazy(self):
        import psycopg
        from webapp.repositories import availability as avail_repo

        self.assertEqual(self.alice.put("/api/v1/availability", json={"minutes": 60}).status_code, 200)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE availability SET free_until = now() - INTERVAL '1 minute'"
                            " WHERE user_id = %s;", (self.aid,))

        r = self.alice.get("/api/v1/availability")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNone(r.json()["free_until"])

        free_ids = {row["user_id"] for row in avail_repo.list_free()}
        self.assertNotIn(self.aid, free_ids)

    # ── DELETE clears availability ──────────────────────────────────────────

    def test_delete_clears(self):
        self.assertEqual(self.alice.put("/api/v1/availability", json={"minutes": 60}).status_code, 200)
        r = self.alice.delete("/api/v1/availability")
        self.assertEqual(r.status_code, 204, r.text)
        self.assertIsNone(self.alice.get("/api/v1/availability").json()["free_until"])

    # ── minutes clamp (5–240) ───────────────────────────────────────────────

    def test_minutes_clamp(self):
        self.assertEqual(self.alice.put("/api/v1/availability", json={"minutes": 3}).status_code, 422)
        self.assertEqual(self.alice.put("/api/v1/availability", json={"minutes": 500}).status_code, 422)

    # ── Push fires only on a fresh toggle-on ────────────────────────────────

    def test_push_only_on_fresh_toggle(self):
        from unittest.mock import patch
        from webapp.routes import api_v1

        calls: list[dict] = []

        def recorder(user_id, *, title=None, body=None, data=None,
                     interruption_level=None):
            calls.append({"user_id": user_id, "title": title,
                          "body": body, "data": data})

        with patch.object(api_v1, "push_to_user", recorder):
            # Bob free first — nobody else free, so no push.
            self.assertEqual(self.bob.put("/api/v1/availability", json={"minutes": 60}).status_code, 200)
            self.assertEqual([c for c in calls if c["user_id"] == self.bid], [])

            # Alice toggles free — exactly one push to Bob.
            self.assertEqual(self.alice.put("/api/v1/availability", json={"minutes": 60}).status_code, 200)
            to_bob = [c for c in calls if c["user_id"] == self.bid]
            self.assertEqual(len(to_bob), 1)
            push = to_bob[0]
            self.assertEqual(push["title"], "Free now")
            self.assertEqual(push["body"], "Alice Dev is free for a case now")
            self.assertEqual(push["data"]["kind"], "free_now")
            self.assertEqual(push["data"]["user_id"], self.aid)
            self.assertEqual(push["data"]["name"], "Alice Dev")

            # Alice extends while still free — no new push.
            self.assertEqual(self.alice.put("/api/v1/availability", json={"minutes": 90}).status_code, 200)
            self.assertEqual(len([c for c in calls if c["user_id"] == self.bid]), 1)

    # ── Auth guard ──────────────────────────────────────────────────────────

    def test_unauthenticated_returns_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        self.assertEqual(TestClient(app).get("/api/v1/availability").status_code, 401)
        self.assertEqual(
            TestClient(app).put("/api/v1/availability", json={"minutes": 60}).status_code, 401)


if __name__ == "__main__":
    unittest.main()
