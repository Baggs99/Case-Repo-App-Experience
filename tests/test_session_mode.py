"""
Task 1 (iOS-P3): session `mode` (remote vs in-person) — migration 015.

Needs the seeded dev Postgres — skips cleanly otherwise. Case fixture row
follows the pattern in tests/test_api_v1_sessions.py; pairing-claim fixture
follows tests/test_pairing.py.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestSessionMode(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app).__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]

        a_session = create_session(cls.aid, user_agent="mode-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, a_session.id)
        b_session = create_session(cls.bid, user_agent="mode-test", ip_address=None)
        cls.bob.cookies.set(SESSION_COOKIE_NAME, b_session.id)

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('Mode Test Case', 'mode test case', 'DevSchool', 2098,"
                    " 'Technology', 'Mode-Type', 'Easy', 2, 2, 'output/none.pdf')"
                    " RETURNING id;")
                cls.case_id = cur.fetchone()[0]

        from webapp.repositories.practice_sessions import create_practice_session
        cls.remote_session = create_practice_session(
            interviewer_id=cls.aid, candidate_id=cls.bid, case_id=cls.case_id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM pairing_tokens WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)
        cls.bob.__exit__(None, None, None)

    def _claim_in_person_session(self) -> int:
        r = self.alice.post("/api/practice/pair/create", json={"case_id": self.case_id})
        self.assertEqual(r.status_code, 200, r.text)
        token = r.json()["token"]
        r = self.bob.post("/api/practice/pair/claim", json={"token": token})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["session_id"]

    def test_directly_created_session_mode_is_remote(self):
        self.assertEqual(self.remote_session["mode"], "remote")

    def test_pairing_claimed_session_mode_is_in_person(self):
        session_id = self._claim_in_person_session()
        r = self.alice.get(f"/api/practice/{session_id}")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["mode"], "in_person")

    def test_session_detail_returns_mode(self):
        session_id = self.remote_session["id"]
        r = self.alice.get(f"/api/practice/{session_id}")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["mode"], "remote")

    def test_join_config_returns_mode(self):
        session_id = self.remote_session["id"]
        r = self.alice.get(f"/api/practice/{session_id}/join-config")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["mode"], "remote")


if __name__ == "__main__":
    unittest.main()
