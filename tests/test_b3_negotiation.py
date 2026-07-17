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
