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


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestClaim(unittest.TestCase):
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
                    " page_count, pdf_path) VALUES ('B1 Claim Case', 'b1 claim case',"
                    " 'DevSchool', 2093, 'Technology', 'Profitability', 'Easy', 3.0,"
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
                cur.execute("DELETE FROM proposals WHERE case_id = %s OR "
                            "(case_id IS NULL AND from_user_id = %s);", (cls.case_id, cls.aid))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def _mk_open(self, client, **overrides):
        payload = {"case_id": self.case_id, "from_role": "interviewer"}
        payload.update(overrides)
        return client.post("/api/proposals", json=payload).json()["claim_token"]

    def test_creator_cannot_claim(self):
        tok = self._mk_open(self.alice)
        self.assertEqual(self.alice.post(f"/api/proposals/claim/{tok}").status_code, 409)

    def test_unknown_token_404(self):
        self.assertEqual(self.bob.post("/api/proposals/claim/nope-nope").status_code, 404)

    def test_requires_auth(self):
        tok = self._mk_open(self.alice)
        anon = self.__class__._ctx.__class__  # unused; explicit anon client below
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 401)

    def test_claim_now_with_case_auto_accepts_and_creates_session(self):
        tok = self._mk_open(self.alice)  # no proposed_times -> "now"
        r = self.bob.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertTrue(body["accepted"])
        self.assertIsNotNone(body["session_id"])
        self.assertFalse(body["needs_negotiation"])
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT interviewer_id, candidate_id FROM practice_sessions"
                            " WHERE id = %s;", (body["session_id"],))
                ivr, cand = cur.fetchone()
        self.assertEqual((ivr, cand), (self.aid, self.bid))  # from_role=interviewer

    def test_claim_scheduled_stays_pending(self):
        when = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        tok = self._mk_open(self.alice, proposed_times=[when])
        r = self.bob.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["state"], "pending")
        self.assertIsNone(r.json()["session_id"])
        # to_user_id now bound to the claimer -> shows in Bob's inbox.
        inbox = self.bob.get("/api/proposals/inbox").json()["proposals"]
        self.assertIn(r.json()["proposal_id"], [p["id"] for p in inbox])

    def test_claim_case_less_now_needs_negotiation(self):
        tok = self._mk_open(self.alice, case_id=None)
        r = self.bob.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertTrue(r.json()["accepted"])
        self.assertIsNone(r.json()["session_id"])
        self.assertTrue(r.json()["needs_negotiation"])

    def test_double_claim_409(self):
        tok = self._mk_open(self.alice)
        self.assertEqual(self.bob.post(f"/api/proposals/claim/{tok}").status_code, 200)
        self.assertEqual(self.cara.post(f"/api/proposals/claim/{tok}").status_code, 409)


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestCounter(unittest.TestCase):
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
                    " page_count, pdf_path) VALUES ('B1 Counter Case', 'b1 counter case',"
                    " 'DevSchool', 2092, 'Technology', 'Profitability', 'Easy', 3.0,"
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
                cur.execute("DELETE FROM proposals WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def _propose_to_bob(self):
        when = (datetime.now(timezone.utc) + timedelta(days=1)).replace(microsecond=0)
        return self.alice.post("/api/proposals", json={
            "to_user_id": self.bid, "case_id": self.case_id,
            "from_role": "interviewer", "proposed_times": [when.isoformat()],
        }).json()["id"]

    def test_recipient_counters_then_proposer_accepts(self):
        pid = self._propose_to_bob()
        t1 = (datetime.now(timezone.utc) + timedelta(days=2)).replace(microsecond=0)
        r = self.bob.post(f"/api/proposals/{pid}/counter", json={"times": [t1.isoformat()]})
        self.assertEqual(r.status_code, 200, r.text)
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT state, counter_by FROM proposals WHERE id = %s;", (pid,))
                state, counter_by = cur.fetchone()
        self.assertEqual(state, "countered")
        self.assertEqual(counter_by, self.bid)
        # Original proposer (Alice) accepts a counter time -> session created.
        r = self.alice.post(f"/api/proposals/{pid}/accept", json={"time": t1.isoformat()})
        self.assertEqual(r.status_code, 200, r.text)
        sid = r.json()["session_id"]
        self.assertIsNotNone(sid)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT scheduled_at FROM practice_sessions WHERE id = %s;", (sid,))
                sched = cur.fetchone()[0]
        self.assertEqual(sched.astimezone(timezone.utc), t1)

    def test_only_recipient_may_counter(self):
        pid = self._propose_to_bob()
        t1 = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
        # Proposer cannot counter their own proposal; existence undisclosed -> 404.
        self.assertEqual(self.alice.post(f"/api/proposals/{pid}/counter",
                                         json={"times": [t1]}).status_code, 404)
        # Third party cannot either.
        self.assertEqual(self.cara.post(f"/api/proposals/{pid}/counter",
                                        json={"times": [t1]}).status_code, 404)

    def test_one_round_only(self):
        pid = self._propose_to_bob()
        t1 = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
        self.assertEqual(self.bob.post(f"/api/proposals/{pid}/counter",
                                       json={"times": [t1]}).status_code, 200)
        # A second counter (from 'countered') is rejected — one round only.
        self.assertEqual(self.bob.post(f"/api/proposals/{pid}/counter",
                                       json={"times": [t1]}).status_code, 409)

    def test_counter_times_capped_at_three(self):
        pid = self._propose_to_bob()
        times = [(datetime.now(timezone.utc) + timedelta(days=d)).isoformat()
                 for d in range(2, 6)]  # 4 times
        self.assertEqual(self.bob.post(f"/api/proposals/{pid}/counter",
                                       json={"times": times}).status_code, 422)

    def test_accept_of_counter_requires_a_listed_time(self):
        pid = self._propose_to_bob()
        t1 = (datetime.now(timezone.utc) + timedelta(days=2)).replace(microsecond=0)
        self.bob.post(f"/api/proposals/{pid}/counter", json={"times": [t1.isoformat()]})
        bogus = (datetime.now(timezone.utc) + timedelta(days=9)).isoformat()
        r = self.alice.post(f"/api/proposals/{pid}/accept", json={"time": bogus})
        self.assertEqual(r.status_code, 409)

    def test_recipient_cannot_accept_countered(self):
        pid = self._propose_to_bob()
        t1 = (datetime.now(timezone.utc) + timedelta(days=2)).replace(microsecond=0)
        self.bob.post(f"/api/proposals/{pid}/counter", json={"times": [t1.isoformat()]})
        # Only the original proposer accepts from 'countered'; Bob gets 404.
        r = self.bob.post(f"/api/proposals/{pid}/accept", json={"time": t1.isoformat()})
        self.assertEqual(r.status_code, 404)

    def test_accept_case_less_scheduled_needs_negotiation(self):
        # DD-1: a case-less ("interviewer decides") scheduled proposal accepted
        # via POST /accept marks accepted with no session (B3 negotiation).
        when = (datetime.now(timezone.utc) + timedelta(days=1)).replace(microsecond=0)
        pid = self.alice.post("/api/proposals", json={
            "to_user_id": self.bid, "case_id": None,
            "from_role": "interviewer", "proposed_times": [when.isoformat()],
        }).json()["id"]
        r = self.bob.post(f"/api/proposals/{pid}/accept",
                          json={"scheduled_at": when.isoformat()})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNone(r.json()["session_id"])
        self.assertTrue(r.json()["needs_negotiation"])


if __name__ == "__main__":
    unittest.main()
