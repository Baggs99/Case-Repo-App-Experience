"""
Task 3: device-token registration under /api/v1 (repo + routes).

Needs the seeded dev Postgres — skips cleanly otherwise. Uses the same
login/cookie fixture idiom as tests/test_dashboard.py.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestApiV1Devices(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = %s;", ("a@yale.edu",))
                cls.aid = cur.fetchone()[0]

        session = create_session(cls.aid, user_agent="p3-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, session.id)

    @classmethod
    def tearDownClass(cls):
        from webapp.repositories.device_tokens import delete_token
        delete_token("abc123")
        cls._ctx.__exit__(None, None, None)

    def test_register_list_reregister_delete(self):
        from webapp.repositories.device_tokens import tokens_for_user

        r = self.alice.post("/api/v1/devices",
                             json={"token": "abc123", "platform": "ios"})
        self.assertEqual(r.status_code, 204, r.text)
        self.assertEqual(tokens_for_user(self.aid), ["abc123"])

        # Re-post the same token: upsert, still one row.
        r = self.alice.post("/api/v1/devices",
                             json={"token": "abc123", "platform": "ios"})
        self.assertEqual(r.status_code, 204, r.text)
        self.assertEqual(tokens_for_user(self.aid), ["abc123"])

        r = self.alice.delete("/api/v1/devices/abc123")
        self.assertEqual(r.status_code, 204, r.text)
        self.assertEqual(tokens_for_user(self.aid), [])

    def test_unauthenticated_post_rejected(self):
        from fastapi.testclient import TestClient
        from webapp.main import app

        r = TestClient(app).post("/api/v1/devices",
                                  json={"token": "xyz789", "platform": "ios"})
        self.assertEqual(r.status_code, 401)


if __name__ == "__main__":
    unittest.main()
