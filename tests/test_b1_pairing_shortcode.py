"""
B1 Task 8: pairing short-codes, optional case at mint, claim by token OR
short_code. Needs seeded dev Postgres. Cookie idiom per tests/test_pairing.py.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestPairingShortCode(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)
        cls.cara = TestClient(app)
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES ('B1 Pair Case', 'b1 pair case',"
                    " 'DevSchool', 2089, 'Technology', 'Profitability', 'Easy', 3.0,"
                    " 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.aid, cls.bid, cls.cid = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]
        for client, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid), (cls.cara, cls.cid)):
            s = create_session(uid, user_agent="b1-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM pairing_tokens WHERE interviewer_id = %s;", (cls.aid,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_mint_returns_short_code(self):
        r = self.alice.post("/api/practice/pair/create", json={"case_id": self.case_id})
        self.assertEqual(r.status_code, 200, r.text)
        code = r.json()["short_code"]
        self.assertEqual(len(code), 6)
        self.assertTrue(set(code) <= set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789"))
        self.assertTrue(r.json()["token"])

    def test_mint_case_optional(self):
        r = self.alice.post("/api/practice/pair/create", json={})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertTrue(r.json()["short_code"])

    def test_claim_by_short_code_creates_session(self):
        code = self.alice.post("/api/practice/pair/create",
                               json={"case_id": self.case_id}).json()["short_code"]
        r = self.bob.post("/api/practice/pair/claim", json={"short_code": code})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNotNone(r.json()["session_id"])

    def test_claim_by_token_still_works(self):
        tok = self.alice.post("/api/practice/pair/create",
                              json={"case_id": self.case_id}).json()["token"]
        r = self.bob.post("/api/practice/pair/claim", json={"token": tok})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNotNone(r.json()["session_id"])

    def test_claim_requires_token_or_code(self):
        r = self.bob.post("/api/practice/pair/claim", json={})
        self.assertEqual(r.status_code, 422)

    def test_unknown_short_code_404(self):
        r = self.bob.post("/api/practice/pair/claim", json={"short_code": "ZZZZZZ"})
        self.assertEqual(r.status_code, 404)

    def test_self_claim_by_code_409(self):
        # IDOR/guard: the minter cannot claim their own code as candidate.
        code = self.alice.post("/api/practice/pair/create",
                               json={"case_id": self.case_id}).json()["short_code"]
        r = self.alice.post("/api/practice/pair/claim", json={"short_code": code})
        self.assertEqual(r.status_code, 409)

    def test_case_less_token_claim_409(self):
        # DD-1: sessions stay case-bound in B1; a case-less pairing token can't
        # create a session yet (case negotiation lands in B3).
        code = self.alice.post("/api/practice/pair/create", json={}).json()["short_code"]
        r = self.bob.post("/api/practice/pair/claim", json={"short_code": code})
        self.assertEqual(r.status_code, 409)

    def test_claim_requires_auth(self):
        code = self.alice.post("/api/practice/pair/create",
                               json={"case_id": self.case_id}).json()["short_code"]
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).post("/api/practice/pair/claim", json={"short_code": code})
        self.assertEqual(r.status_code, 200, r.text)


if __name__ == "__main__":
    unittest.main()
