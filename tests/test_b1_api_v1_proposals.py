"""
B1 Task 9: /api/v1/proposals parity — claim_token + counter fields, and the
proposer sees their countered proposals (so they can accept the counter).
Needs seeded dev Postgres.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestApiV1ProposalsParity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES ('B1 V1 Case', 'b1 v1 case',"
                    " 'DevSchool', 2088, 'Technology', 'Profitability', 'Easy', 3.0,"
                    " 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]
        for client, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
            s = create_session(uid, user_agent="b1-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM proposals WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_received_pending_has_counter_and_claim_fields(self):
        when = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        self.alice.post("/api/proposals", json={
            "to_user_id": self.bid, "case_id": self.case_id,
            "from_role": "interviewer", "proposed_times": [when]})
        items = self.bob.get("/api/v1/proposals").json()["proposals"]
        self.assertTrue(items)
        item = items[0]
        for key in ("claim_token", "state", "counter_times", "counter_by",
                    "countered_at", "direction"):
            self.assertIn(key, item)
        self.assertEqual(item["direction"], "received")

    def test_proposer_sees_countered_proposal(self):
        when = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        pid = self.alice.post("/api/proposals", json={
            "to_user_id": self.bid, "case_id": self.case_id,
            "from_role": "interviewer", "proposed_times": [when]}).json()["id"]
        t2 = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
        self.bob.post(f"/api/proposals/{pid}/counter", json={"times": [t2]})
        # Countered proposal drops out of Bob's pending inbox but appears for
        # Alice (the proposer) so she can accept the counter.
        alice_items = self.alice.get("/api/v1/proposals").json()["proposals"]
        match = [p for p in alice_items if p["id"] == pid]
        self.assertEqual(len(match), 1)
        self.assertEqual(match[0]["state"], "countered")
        self.assertEqual(match[0]["direction"], "sent")
        self.assertIsNotNone(match[0]["counter_times"])


if __name__ == "__main__":
    unittest.main()
