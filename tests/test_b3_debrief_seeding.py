"""B3 Task 8: debrief seeding — finalize response carries next_recommendation +
prefill_proposal. Needs seeded dev Postgres."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDebriefSeeding(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()   # interviewer (finalizes)
        cls.bob = TestClient(app)          # candidate
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = ANY(%s) ORDER BY email;",
                        (["a@yale.edu", "b@yale.edu"],))
            cls.aid, cls.bid = (r[0] for r in cur.fetchall())
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path) VALUES ('B3 Seed','b3 seed','DevSchool',2094,"
                " 'Technology','Profitability','Medium',5.0,2,'output/none.pdf') RETURNING id;")
            cls.case_id = cur.fetchone()[0]
        from webapp.repositories.rooms import get_or_create_room
        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        cls.room_id = get_or_create_room(cls.aid)["id"]
        rt_id = get_default_rubric_template_id(cls.case_id, cls.aid)
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO practice_sessions (room_id, interviewer_id, candidate_id,"
                " case_id, rubric_template_id, state, started_at) VALUES"
                " (%s,%s,%s,%s,%s,'debrief', NOW()) RETURNING id;",
                (cls.room_id, cls.aid, cls.bid, cls.case_id, rt_id))
            cls.sid = cur.fetchone()[0]
        for c, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
            s = create_session(uid, user_agent="b3", ip_address=None)
            c.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM burned WHERE case_id = %s;", (cls.case_id,))
            cur.execute("DELETE FROM feedback WHERE session_id = %s;", (cls.sid,))
            cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (cls.sid,))
            cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_finalize_seeds_next(self):
        r = self.alice.post(f"/api/practice/{self.sid}/finalize", json={"grade": 4.0})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("next_recommendation", body)
        self.assertIn("prefill_proposal", body)
        if body["prefill_proposal"] is not None:
            self.assertEqual(body["prefill_proposal"]["to_user_id"], self.aid)
            # next recommendation never re-recommends the just-burned case
            self.assertNotEqual(body["next_recommendation"]["case_id"], self.case_id)
