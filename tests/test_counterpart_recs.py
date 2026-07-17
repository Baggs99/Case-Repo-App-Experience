"""
B4 Task 4: the recommendation "travels with the candidate" (spec §7.2) —
an interviewer sees the candidate's top-3 recs on join-config and pair
status; a candidate and a non-participant never do (IDOR/role guard).

Alice interviews Cara. A dedicated '00-…' eligible case guarantees Cara's
coverage-gap rule fires, so counterpart_recommendations is deterministically
non-empty. Skips cleanly without the seeded dev Postgres.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestCounterpartRecs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()          # interviewer; pool live
        cls.cara = TestClient(app)                # candidate
        cls.bob = TestClient(app)                 # non-participant prober

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid, cls.cid = (ids["a@yale.edu"], ids["b@yale.edu"],
                                     ids["c@yale.edu"])
        for client, uid in ((cls.alice, cls.aid), (cls.cara, cls.cid),
                            (cls.bob, cls.bid)):
            s = create_session(uid, user_agent="b4-cp-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

        def new_case(cur, title, ctype):
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path)"
                " VALUES (%s, %s, 'DevSchool', 2095, 'Technology', %s,"
                " 'Easy', 2, 2, 'output/none.pdf') RETURNING id;",
                (title, title.lower(), ctype))
            return cur.fetchone()[0]

        from webapp.repositories.practice_sessions import (
            get_default_rubric_template_id)
        from webapp.repositories.rooms import get_or_create_room
        room_id = get_or_create_room(cls.aid)["id"]

        cls.case_ids = []
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # '00-…' zero-count type → deterministic coverage-gap rec for Cara.
                cls.gap_case = new_case(cur, "B4CP Gap Case", "00-B4CP-Gap")
                cls.join_case = new_case(cur, "B4CP Join Case", "B4CP-Join")
                cls.token_case = new_case(cur, "B4CP Token Case", "B4CP-Token")
                cls.case_ids = [cls.gap_case, cls.join_case, cls.token_case]

                # Joinable session (lobby, in_person → no TURN mint): Alice
                # interviews Cara. rubric_template_id is NOT NULL — resolve the
                # generic default the same way claim()/create_practice_session do.
                template_id = get_default_rubric_template_id(cls.join_case, cls.aid)
                cur.execute(
                    "INSERT INTO practice_sessions (room_id, interviewer_id,"
                    " candidate_id, case_id, rubric_template_id, state, mode,"
                    " consent_interviewer, consent_candidate, state_changed_at)"
                    " VALUES (%s, %s, %s, %s, %s, 'lobby', 'in_person', TRUE,"
                    " TRUE, NOW()) RETURNING id;",
                    (room_id, cls.aid, cls.cid, cls.join_case, template_id))
                cls.join_session_id = cur.fetchone()[0]

        # Pairing token: Alice mints, Cara claims → status returns session_id.
        from webapp.repositories import pairing_tokens as pairing_repo
        cls.token = pairing_repo.mint_token(interviewer_id=cls.aid,
                                            case_id=cls.token_case)["token"]
        cls.pair_session_id = pairing_repo.claim(
            token=cls.token, candidate_id=cls.cid)["session_id"]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM pairing_tokens WHERE token = %s;",
                            (cls.token,))
                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
                            ([cls.join_session_id, cls.pair_session_id],))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    def _expected_ids(self):
        from webapp.repositories import dashboard as repo
        return [rec["case_id"] for rec in repo.recommendations(self.cid, limit=3)]

    # ── join-config ─────────────────────────────────────────────────────────

    def test_interviewer_join_config_has_counterpart_recs(self):
        r = self.alice.get(f"/api/practice/{self.join_session_id}/join-config")
        self.assertEqual(r.status_code, 200, r.text)
        recs = r.json()["counterpart_recommendations"]
        self.assertTrue(recs)
        self.assertLessEqual(len(recs), 3)
        for rec in recs:
            self.assertEqual(set(rec), {"case_id", "title", "case_type",
                                        "difficulty", "why", "rule"})
        self.assertEqual([rec["case_id"] for rec in recs], self._expected_ids())
        # Cara has no finalized sessions here → only the coverage-gap rule
        # fires; pins a real deterministic value (not just engine-echo).
        self.assertEqual(recs[0]["rule"], "coverage-gap")

    def test_candidate_join_config_omits_counterpart_recs(self):
        r = self.cara.get(f"/api/practice/{self.join_session_id}/join-config")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertNotIn("counterpart_recommendations", r.json())

    def test_nonparticipant_join_config_404(self):
        r = self.bob.get(f"/api/practice/{self.join_session_id}/join-config")
        self.assertEqual(r.status_code, 404, r.text)

    # ── pair status ─────────────────────────────────────────────────────────

    def test_interviewer_pair_status_has_counterpart_recs(self):
        r = self.alice.get(f"/api/practice/pair/status/{self.token}")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["session_id"], self.pair_session_id)
        recs = body["counterpart_recommendations"]
        self.assertTrue(recs)
        self.assertLessEqual(len(recs), 3)
        self.assertEqual([rec["case_id"] for rec in recs], self._expected_ids())
        self.assertEqual(recs[0]["rule"], "coverage-gap")

    def test_nonowner_pair_status_404_no_recs(self):
        r = self.bob.get(f"/api/practice/pair/status/{self.token}")
        self.assertEqual(r.status_code, 404, r.text)
        self.assertNotIn("counterpart_recommendations", r.json())


if __name__ == "__main__":
    unittest.main()
