"""
B1 Tasks 3-5: open (send-a-link) proposals, case-less proposals, claim, and
one-round counter. Needs the seeded dev Postgres — skips cleanly otherwise.
Follows the login/cookie idiom of tests/test_queues_proposals.py.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestOpenProposals(unittest.TestCase):
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
                cls.case_ids = []
                for i in range(1, 4):
                    cur.execute(
                        "INSERT INTO cases (case_title, normalized_title,"
                        " source_school, source_year, industry, case_type,"
                        " difficulty, difficulty_score, page_count, pdf_path)"
                        " VALUES (%s, %s, 'DevSchool', 2094, 'Technology',"
                        " 'Profitability', 'Easy', 3.0, 2, 'output/none.pdf')"
                        " RETURNING id;",
                        (f"B1 Open Case {i}", f"b1 open case {i}"))
                    cls.case_ids.append(cur.fetchone()[0])
        cls.aid, cls.bid, cls.cid = (ids["a@yale.edu"], ids["b@yale.edu"],
                                     ids["c@yale.edu"])
        for client, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid), (cls.cara, cls.cid)):
            s = create_session(uid, user_agent="b1-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM proposals WHERE case_id = ANY(%s) OR case_id IS NULL"
                            " AND from_user_id = ANY(%s);", (cls.case_ids, [cls.aid, cls.bid, cls.cid]))
                cur.execute("DELETE FROM proposals WHERE from_user_id = ANY(%s);",
                            ([cls.aid, cls.bid, cls.cid],))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = ANY(%s);", (cls.case_ids,))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    def _open_link(self, **overrides):
        payload = {"case_id": self.case_ids[0], "from_role": "interviewer"}
        payload.update(overrides)
        return self.alice.post("/api/proposals", json=payload)

    def test_open_link_returns_claim_token(self):
        r = self._open_link()  # to_user_id omitted -> open link
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertTrue(body["claim_token"])
        self.assertIsNone(body["to_user_id"])

    def test_case_less_proposal_allowed(self):
        r = self._open_link(case_id=None)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNone(r.json()["case_id"])

    def test_named_recipient_has_no_claim_token(self):
        r = self._open_link(to_user_id=self.bid)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNone(r.json()["claim_token"])
        self.assertEqual(r.json()["to_user_id"], self.bid)

    def test_bad_case_still_404(self):
        r = self._open_link(case_id=999999)
        self.assertEqual(r.status_code, 404)


if __name__ == "__main__":
    unittest.main()
