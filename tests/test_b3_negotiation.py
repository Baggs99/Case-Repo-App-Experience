"""B3 Tasks 2 & 5: case negotiation — repo plumbing + endpoints. Needs seeded
dev Postgres; skips otherwise. Login/cookie idiom of tests/test_b1_proposals_open.py."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx (TestClient inits the pool)")
class TestNegotiatingSessionRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()   # run the app lifespan → init the DB pool
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = ANY(%s) ORDER BY email;",
                        (["a@yale.edu", "b@yale.edu"],))
            cls.aid, cls.bid = (r[0] for r in cur.fetchall())
        cls._created = []   # session ids
        cls._cases = []     # case ids (dropped AFTER sessions — FK order)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            if cls._created:
                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
                            (cls._created,))
            if cls._cases:
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls._cases,))
        cls._ctx.__exit__(None, None, None)

    def test_create_negotiating_session_has_null_case_and_state(self):
        from webapp.repositories import practice_sessions as repo
        sess = repo.create_negotiating_session(
            interviewer_id=self.aid, candidate_id=self.bid, mode="remote")
        self._created.append(sess["id"])
        self.assertEqual(sess["state"], "negotiating")
        self.assertIsNone(sess["case_id"])
        self.assertIsNone(sess["rubric_template_id"])

    def test_get_practice_session_returns_negotiating(self):
        from webapp.repositories import practice_sessions as repo
        sess = repo.create_negotiating_session(
            interviewer_id=self.aid, candidate_id=self.bid, mode="remote")
        self._created.append(sess["id"])
        got = repo.get_practice_session(sess["id"])
        self.assertIsNotNone(got)               # LEFT JOIN keeps case_id-NULL rows
        self.assertIsNone(got["case_title"])
        self.assertEqual(got["interviewer_id"], self.aid)

    def test_stamp_negotiated_case_moves_to_lobby(self):
        import psycopg
        from webapp.repositories import practice_sessions as repo
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path) VALUES ('B3 Nego Case','b3 nego case',"
                " 'DevSchool',2094,'Technology','Profitability','Easy',3.0,2,"
                " 'output/none.pdf') RETURNING id;")
            case_id = cur.fetchone()[0]
        self._cases.append(case_id)
        sess = repo.create_negotiating_session(
            interviewer_id=self.aid, candidate_id=self.bid)
        self._created.append(sess["id"])
        tmpl = repo.get_default_rubric_template_id(case_id, self.aid)
        out = repo.stamp_negotiated_case(sess["id"], case_id, tmpl)
        self.assertEqual(out["state"], "lobby")
        self.assertEqual(out["case_id"], case_id)


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestNegotiationEndpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()   # interviewer
        cls.bob = TestClient(app)          # candidate
        cls.cara = TestClient(app)         # non-participant
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = ANY(%s) ORDER BY email;",
                        (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
            cls.aid, cls.bid, cls.cid = (r[0] for r in cur.fetchall())
            cls.case_ids = []
            for i in range(2):
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES (%s,%s,'DevSchool',2094,'Technology',"
                    " 'Profitability','Easy',3.0,2,'output/none.pdf') RETURNING id;",
                    (f"B3 Nego Ep {i}", f"b3 nego ep {i}"))
                cls.case_ids.append(cur.fetchone()[0])
        for c, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid), (cls.cara, cls.cid)):
            s = create_session(uid, user_agent="b3", ip_address=None)
            c.cookies.set(SESSION_COOKIE_NAME, s.id)
        cls._sessions = []

    @classmethod
    def tearDownClass(cls):
        import psycopg
        from tests.test_b3_recap_gate import _purge_session
        for sid in cls._sessions:
            _purge_session(sid)   # nulls the originating proposal + drops the session
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM proposals WHERE from_user_id = %s;", (cls.aid,))
            cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    def _new_negotiating(self):
        # Alice (interviewer) opens a case-less link, Bob claims → negotiating.
        tok = self.alice.post("/api/proposals", json={
            "case_id": None, "from_role": "interviewer"}).json()["claim_token"]
        sid = self.bob.post(f"/api/proposals/claim/{tok}").json()["session_id"]
        self._sessions.append(sid)
        return sid

    def test_interviewer_pick_then_candidate_accepts(self):
        sid = self._new_negotiating()
        r = self.alice.post(f"/api/practice/{sid}/negotiation/propose",
                            json={"case_id": self.case_ids[0]})
        self.assertEqual(r.status_code, 200, r.text)
        # Candidate accepts the interviewer's pick → lobby.
        r = self.bob.post(f"/api/practice/{sid}/negotiation/accept",
                          json={"case_id": self.case_ids[0]})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["state"], "lobby")
        self.assertEqual(r.json()["case_id"], self.case_ids[0])

    def test_candidate_cannot_pick_first(self):
        sid = self._new_negotiating()
        r = self.bob.post(f"/api/practice/{sid}/negotiation/propose",
                          json={"case_id": self.case_ids[0]})
        self.assertEqual(r.status_code, 403, r.text)

    def test_candidate_counter_then_interviewer_keeps_pick(self):
        sid = self._new_negotiating()
        self.alice.post(f"/api/practice/{sid}/negotiation/propose",
                        json={"case_id": self.case_ids[0]})
        self.bob.post(f"/api/practice/{sid}/negotiation/propose",
                      json={"case_id": self.case_ids[1]})   # candidate counter
        # Interviewer keeps their pick (accepts case 0, not the counter).
        r = self.alice.post(f"/api/practice/{sid}/negotiation/accept",
                            json={"case_id": self.case_ids[0]})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["case_id"], self.case_ids[0])

    def test_round_cap_two(self):
        sid = self._new_negotiating()
        self.alice.post(f"/api/practice/{sid}/negotiation/propose",
                        json={"case_id": self.case_ids[0]})
        self.bob.post(f"/api/practice/{sid}/negotiation/propose",
                      json={"case_id": self.case_ids[1]})
        # A third propose (candidate again) → 409.
        r = self.bob.post(f"/api/practice/{sid}/negotiation/propose",
                          json={"case_id": self.case_ids[0]})
        self.assertEqual(r.status_code, 409, r.text)

    def test_non_participant_404(self):
        sid = self._new_negotiating()
        r = self.cara.get(f"/api/practice/{sid}/negotiation")
        self.assertEqual(r.status_code, 404)

    def test_pick_sources_interviewer_only(self):
        sid = self._new_negotiating()
        ai = self.alice.get(f"/api/practice/{sid}/negotiation").json()
        bi = self.bob.get(f"/api/practice/{sid}/negotiation").json()
        self.assertIn("pick_sources", ai)
        self.assertNotIn("pick_sources", bi)
