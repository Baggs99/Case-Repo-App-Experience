"""B3 Task 3 & 6: recap gate repo + endpoints. Needs seeded dev Postgres."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


def _seed_finalized_session(interviewer_id, candidate_id, case_title):
    """Insert a finalized session + feedback (closed_at NULL) using ONLY raw
    psycopg (no get_pool — works without an app context). rubric_template_id is
    left NULL (nullable after migration 028; unused by these tests). Returns
    (session_id, case_id)."""
    import psycopg
    with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO cases (case_title, normalized_title, source_school,"
            " source_year, industry, case_type, difficulty, difficulty_score,"
            " page_count, pdf_path) VALUES (%s,%s,'DevSchool',2094,'Technology',"
            " 'Profitability','Easy',3.0,2,'output/none.pdf') RETURNING id;",
            (case_title, case_title.lower()))
        case_id = cur.fetchone()[0]
        cur.execute("SELECT id FROM rooms WHERE owner_user_id = %s LIMIT 1;",
                    (interviewer_id,))
        r = cur.fetchone()
        if r is None:
            cur.execute("INSERT INTO rooms (owner_user_id, slug) VALUES (%s, %s)"
                        " RETURNING id;", (interviewer_id, f"rm-{interviewer_id}-{case_id}"))
            room_id = cur.fetchone()[0]
        else:
            room_id = r[0]
        cur.execute(
            "INSERT INTO practice_sessions (room_id, interviewer_id, candidate_id,"
            " case_id, rubric_template_id, state, ended_at) VALUES"
            " (%s,%s,%s,%s,NULL,'finalized', NOW()) RETURNING id;",
            (room_id, interviewer_id, candidate_id, case_id))
        session_id = cur.fetchone()[0]
        cur.execute(
            "INSERT INTO feedback (session_id, rubric_json, grade, finalized_at)"
            " VALUES (%s, '{\"items\":{}}', 4.0, NOW());", (session_id,))
    return session_id, case_id


def _purge_session(session_id):
    """Delete a practice_session and its NO-ACTION referencers, FK-safe."""
    import psycopg
    with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
        cur.execute("UPDATE proposals SET session_id = NULL WHERE session_id = %s;", (session_id,))
        cur.execute("DELETE FROM pairing_tokens WHERE claimed_session_id = %s;", (session_id,))
        cur.execute("DELETE FROM burned WHERE session_id = %s;", (session_id,))
        cur.execute("DELETE FROM live_activity_tokens WHERE session_id = %s;", (session_id,))
        cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (session_id,))


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx (TestClient inits the pool)")
class TestRecapGateRepo(unittest.TestCase):
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
        cls.sid, cls.case_id = _seed_finalized_session(cls.aid, cls.bid, "B3 Gate Case")

    @classmethod
    def tearDownClass(cls):
        import psycopg
        _purge_session(cls.sid)
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_candidate_gate_blocks_open_recap(self):
        from webapp.repositories import feedback as repo
        self.assertEqual(repo.candidate_gate(self.bid), self.sid)   # candidate blocked
        self.assertIsNone(repo.candidate_gate(self.aid))            # interviewer never gated

    def test_close_recap_clears_gate(self):
        from webapp.repositories import feedback as repo
        repo.close_recap(self.sid, case_rating=5, feedback_thumbs=True, record_thumbs=True)
        self.assertIsNone(repo.candidate_gate(self.bid))
        # thumbs recorded because record_thumbs=True
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT case_rating, feedback_thumbs, closed_at FROM feedback"
                        " WHERE session_id = %s;", (self.sid,))
            rating, thumbs, closed = cur.fetchone()
        self.assertEqual(rating, 5)
        self.assertTrue(thumbs)
        self.assertIsNotNone(closed)

    def test_list_unread_recaps_oldest_first(self):
        # fresh open recap for this test
        sid2, cid2 = _seed_finalized_session(self.aid, self.bid, "B3 Gate Case 2")
        self.addCleanup(self._drop, sid2, cid2)
        from webapp.repositories import feedback as repo
        recaps = repo.list_unread_recaps(self.bid)
        self.assertTrue(all(r["session_id"] != self.sid for r in recaps))  # closed one gone
        self.assertIn(sid2, [r["session_id"] for r in recaps])

    def test_assert_gate_raises_recap_error(self):
        # Runs before test_close_recap_clears_gate (alphabetical), so cls.sid is
        # still the oldest open recap → assert_candidate_gate_clear points at it.
        from webapp.repositories import feedback as repo
        with self.assertRaises(repo.RecapGateError) as ctx:
            repo.assert_candidate_gate_clear(self.bid)
        self.assertEqual(ctx.exception.blocked_by_recap, self.sid)
        self.assertEqual(ctx.exception.status_code, 409)

    def _drop(self, sid, cid):
        import psycopg
        _purge_session(sid)
        if cid:
            with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
                cur.execute("DELETE FROM cases WHERE id = %s;", (cid,))


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestRecapGateEndpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()   # interviewer
        cls.bob = TestClient(app)          # candidate (gated)
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = ANY(%s) ORDER BY email;",
                        (["a@yale.edu", "b@yale.edu"],))
            cls.aid, cls.bid = (r[0] for r in cur.fetchall())
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path) VALUES ('B3 Entry Case','b3 entry case',"
                " 'DevSchool',2094,'Technology','Profitability','Easy',3.0,2,"
                " 'output/none.pdf') RETURNING id;")
            cls.case_id = cur.fetchone()[0]
        for c, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
            s = create_session(uid, user_agent="b3-test", ip_address=None)
            c.cookies.set(SESSION_COOKIE_NAME, s.id)
        # Bob has an open recap (as candidate) → gated.
        cls.gate_sid, cls.gate_case = _seed_finalized_session(cls.aid, cls.bid, "B3 Entry Gate")

    @classmethod
    def tearDownClass(cls):
        import psycopg
        # Blocked candidate entries create no session; only gate_sid exists.
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
            extra = [r[0] for r in cur.fetchall()]
        for sid in [cls.gate_sid, *extra]:
            _purge_session(sid)
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM proposals WHERE from_user_id = ANY(%s)"
                        " OR to_user_id = ANY(%s);", ([cls.aid, cls.bid], [cls.aid, cls.bid]))
            cur.execute("DELETE FROM cases WHERE id = ANY(%s);", ([cls.case_id, cls.gate_case],))
        cls._ctx.__exit__(None, None, None)

    def test_create_practice_as_candidate_blocked(self):
        r = self.bob.post("/api/practice", json={
            "interviewer_id": self.aid, "candidate_id": self.bid,
            "case_id": self.case_id})
        self.assertEqual(r.status_code, 409, r.text)
        self.assertEqual(r.json()["detail"]["blocked_by_recap"], self.gate_sid)

    def test_proposal_accept_as_candidate_blocked(self):
        # Alice (interviewer) proposes to Bob (candidate) with a case.
        pid = self.alice.post("/api/proposals", json={
            "to_user_id": self.bid, "case_id": self.case_id,
            "from_role": "interviewer"}).json()["id"]
        r = self.bob.post(f"/api/proposals/{pid}/accept", json={})
        self.assertEqual(r.status_code, 409, r.text)
        self.assertEqual(r.json()["detail"]["blocked_by_recap"], self.gate_sid)


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestRecapEndpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()   # interviewer
        cls.bob = TestClient(app)          # candidate
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = ANY(%s) ORDER BY email;",
                        (["a@yale.edu", "b@yale.edu"],))
            cls.aid, cls.bid = (r[0] for r in cur.fetchall())
        for c, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
            s = create_session(uid, user_agent="b3", ip_address=None)
            c.cookies.set(SESSION_COOKIE_NAME, s.id)
        cls.sid, cls.case_id = _seed_finalized_session(cls.aid, cls.bid, "B3 Recap Ep")

    @classmethod
    def tearDownClass(cls):
        import psycopg
        _purge_session(cls.sid)
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_recaps_list_shows_open_recap(self):
        # Seed a fresh open recap: unittest runs methods alphabetically, so
        # test_close_requires_rating_and_clears closes cls.sid before this test.
        # Own recap keeps the assertion order-independent (sibling-test pattern).
        sid_r, cid_r = _seed_finalized_session(self.aid, self.bid, "B3 Recap Ep List")
        self.addCleanup(self._drop, sid_r, cid_r)
        r = self.bob.get("/api/v1/recaps")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn(sid_r, [x["session_id"] for x in r.json()["recaps"]])

    def test_close_requires_rating_and_clears(self):
        # missing rating → 422
        r = self.bob.post(f"/api/practice/{self.sid}/recap/close", json={})
        self.assertEqual(r.status_code, 422, r.text)
        # valid rating → cleared, gone from list
        r = self.bob.post(f"/api/practice/{self.sid}/recap/close",
                          json={"case_rating": 4, "feedback_thumbs": True})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertNotIn(self.sid,
                         [x["session_id"] for x in self.bob.get("/api/v1/recaps").json()["recaps"]])

    def test_interviewer_cannot_close_candidate_recap(self):
        sid2, cid2 = _seed_finalized_session(self.aid, self.bid, "B3 Recap Ep 2")
        self.addCleanup(self._drop, sid2, cid2)
        r = self.alice.post(f"/api/practice/{sid2}/recap/close", json={"case_rating": 3})
        self.assertEqual(r.status_code, 403, r.text)

    def test_viewed_stamps(self):
        sid3, cid3 = _seed_finalized_session(self.aid, self.bid, "B3 Recap Ep 3")
        self.addCleanup(self._drop, sid3, cid3)
        r = self.bob.post(f"/api/practice/{sid3}/recap/viewed")
        self.assertEqual(r.status_code, 200, r.text)

    def test_gate_clears_then_entry_succeeds(self):
        # Fresh open recap gates Bob; close it, then a candidate entry works.
        gsid, gcid = _seed_finalized_session(self.aid, self.bid, "B3 Recap Gate Clear")
        self.addCleanup(self._drop, gsid, gcid)
        # Burn gcid for Bob too: the gate MUST win over is_burned — a dict-detail
        # {blocked_by_recap} (not the burned string 409) proves the gate is
        # checked before create_practice's is_burned check.
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("INSERT INTO burned (user_id, case_id, session_id)"
                        " VALUES (%s,%s,%s) ON CONFLICT DO NOTHING;",
                        (self.bid, gcid, gsid))
        blocked = self.bob.post("/api/practice", json={
            "interviewer_id": self.aid, "candidate_id": self.bid, "case_id": gcid})
        self.assertEqual(blocked.status_code, 409)
        self.assertEqual(blocked.json()["detail"]["blocked_by_recap"], gsid)
        self.bob.post(f"/api/practice/{gsid}/recap/close", json={"case_rating": 4})
        # Now a case-less open link claimed by Bob creates a negotiating session.
        tok = self.alice.post("/api/proposals", json={
            "case_id": None, "from_role": "interviewer"}).json()["claim_token"]
        r = self.bob.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIsNotNone(r.json()["session_id"])
        self.addCleanup(self._drop, r.json()["session_id"], None)

    def _drop(self, sid, cid):
        import psycopg
        _purge_session(sid)
        if cid:
            with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
                cur.execute("DELETE FROM cases WHERE id = %s;", (cid,))
