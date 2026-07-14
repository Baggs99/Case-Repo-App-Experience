"""
Task 3: pairing-token mint endpoint (POST /api/practice/pair/create).

Needs the seeded dev Postgres — skips cleanly otherwise. Uses the same
login/cookie fixture idiom as tests/test_api_v1_devices.py; case fixture
row follows the pattern in tests/test_api_v1_sessions.py.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestPairingTokenMint(unittest.TestCase):
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
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]

        session = create_session(cls.aid, user_agent="p3-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, session.id)

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('P3 Pairing Case', 'p3 pairing case', 'DevSchool', 2095,"
                    " 'Technology', 'P3-Type', 'Easy', 2, 2, 'output/none.pdf')"
                    " RETURNING id;")
                cls.case_id = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM pairing_tokens WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_mint_token_success(self):
        r = self.alice.post("/api/practice/pair/create",
                             json={"case_id": self.case_id})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("token", body)
        self.assertTrue(body["token"])
        self.assertIn("expires_at", body)
        expires_at = datetime.fromisoformat(body["expires_at"])
        if expires_at.tzinfo is None:
            expires_at = expires_at.replace(tzinfo=timezone.utc)
        self.assertGreater(expires_at, datetime.now(timezone.utc))

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT interviewer_id, case_id FROM pairing_tokens WHERE token = %s;",
                    (body["token"],))
                row = cur.fetchone()
        self.assertIsNotNone(row)
        self.assertEqual(row[0], self.aid)
        self.assertEqual(row[1], self.case_id)

    def test_nonexistent_case_returns_404(self):
        r = self.alice.post("/api/practice/pair/create", json={"case_id": 999999999})
        self.assertEqual(r.status_code, 404, r.text)

    def test_unauthenticated_returns_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).post("/api/practice/pair/create",
                                  json={"case_id": self.case_id})
        self.assertEqual(r.status_code, 401)


if __name__ == "__main__":
    unittest.main()
