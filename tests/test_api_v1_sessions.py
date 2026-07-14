"""
Task 8: JSON proposals inbox, sessions, and dashboard endpoints under
/api/v1 (the final P1 iOS backend surface).

Needs the seeded dev Postgres — skips cleanly otherwise. Uses the same
login/cookie fixture idiom as tests/test_api_v1_cases.py; case/session/
feedback fixture rows follow the pattern in tests/test_dashboard.py.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestApiV1Sessions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]

        session = create_session(cls.aid, user_agent="p8-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, session.id)

        def new_case(cur, title):
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path)"
                " VALUES (%s, %s, 'DevSchool', 2095, 'Technology', 'P8-Type',"
                " 'Easy', 2, 2, 'output/none.pdf') RETURNING id;",
                (title, title.lower()))
            return cur.fetchone()[0]

        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        from webapp.repositories.rooms import get_or_create_room
        from webapp.repositories import proposals as proposals_repo

        room_id = get_or_create_room(cls.aid)["id"]

        cls.future_time = datetime.now(timezone.utc) + timedelta(days=3)

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cls.proposal_case = new_case(cur, "P8 Proposal Case")
                cls.upcoming_case = new_case(cur, "P8 Upcoming Case")
                cls.recent_case = new_case(cur, "P8 Recent Case")
                cls.case_ids = [cls.proposal_case, cls.upcoming_case, cls.recent_case]

        # Pending proposal FROM Bob TO Alice — Alice's inbox.
        cls.proposal = proposals_repo.create_proposal(
            from_user_id=cls.bid, to_user_id=cls.aid, case_id=cls.proposal_case,
            from_role="interviewer", message="Let's practice this one",
            proposed_times=[cls.future_time],
        )

        template_id = get_default_rubric_template_id(cls.upcoming_case, cls.aid)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # Upcoming: Alice is the interviewer, scheduled in the future.
                cur.execute(
                    "INSERT INTO practice_sessions (room_id, interviewer_id,"
                    " candidate_id, case_id, rubric_template_id, state,"
                    " consent_interviewer, consent_candidate, scheduled_at)"
                    " VALUES (%s, %s, %s, %s, %s, 'scheduled', FALSE, FALSE, %s)"
                    " RETURNING id;",
                    (room_id, cls.aid, cls.bid, cls.upcoming_case, template_id,
                     cls.future_time))
                cls.upcoming_session_id = cur.fetchone()[0]

                # Recent: Alice is the candidate, finalized with a grade.
                recent_template_id = get_default_rubric_template_id(
                    cls.recent_case, cls.aid)
                cur.execute(
                    "INSERT INTO practice_sessions (room_id, interviewer_id,"
                    " candidate_id, case_id, rubric_template_id, state,"
                    " consent_interviewer, consent_candidate, started_at,"
                    " ended_at, state_changed_at)"
                    " VALUES (%s, %s, %s, %s, %s, 'finalized', TRUE, TRUE,"
                    " NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day'"
                    " + INTERVAL '45 min', NOW()) RETURNING id;",
                    (room_id, cls.bid, cls.aid, cls.recent_case,
                     recent_template_id))
                cls.recent_session_id = cur.fetchone()[0]
                cur.execute(
                    "INSERT INTO feedback (session_id, rubric_json, notes_md,"
                    " grade, finalized_at)"
                    " VALUES (%s, %s, 'fixture', %s, NOW());",
                    (cls.recent_session_id, '{"items": {}}', 4.2))

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM proposals WHERE id = %s;",
                            (cls.proposal["id"],))
                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
                            ([cls.upcoming_session_id, cls.recent_session_id],))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    # ── proposals ─────────────────────────────────────────────────────────

    def test_proposals_inbox_curated_shape(self):
        r = self.alice.get("/api/v1/proposals")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("proposals", body)
        mine = [p for p in body["proposals"] if p["id"] == self.proposal["id"]]
        self.assertEqual(len(mine), 1)
        item = mine[0]
        for key in ("id", "from_name", "from_role", "case_id", "case_title",
                    "case_type", "difficulty", "message", "proposed_times",
                    "created_at"):
            self.assertIn(key, item)
        self.assertNotIn("to_user_id", item)
        self.assertNotIn("session_id", item)
        self.assertNotIn("responded_at", item)
        self.assertNotIn("state", item)
        self.assertEqual(item["case_id"], self.proposal_case)
        self.assertEqual(item["case_title"], "P8 Proposal Case")
        self.assertEqual(len(item["proposed_times"]), 1)

    def test_unauthenticated_proposals_returns_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).get("/api/v1/proposals")
        self.assertEqual(r.status_code, 401)

    # ── sessions ──────────────────────────────────────────────────────────

    def test_sessions_upcoming_shape(self):
        r = self.alice.get("/api/v1/sessions", params={"scope": "upcoming"})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("sessions", body)
        mine = [s for s in body["sessions"] if s["id"] == self.upcoming_session_id]
        self.assertEqual(len(mine), 1)
        item = mine[0]
        for key in ("id", "role", "other_user", "case_title", "scheduled_at",
                    "state", "ended_at", "grade"):
            self.assertIn(key, item)
        self.assertEqual(item["role"], "interviewer")
        self.assertEqual(item["other_user"], "Bob Dev")
        self.assertIsNotNone(item["scheduled_at"])
        self.assertEqual(item["state"], "scheduled")
        self.assertIsNone(item["ended_at"])
        self.assertIsNone(item["grade"])

    def test_sessions_recent_shape(self):
        r = self.alice.get("/api/v1/sessions", params={"scope": "recent"})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        mine = [s for s in body["sessions"] if s["id"] == self.recent_session_id]
        self.assertEqual(len(mine), 1)
        item = mine[0]
        for key in ("id", "role", "other_user", "case_title", "scheduled_at",
                    "state", "ended_at", "grade"):
            self.assertIn(key, item)
        self.assertEqual(item["role"], "candidate")
        self.assertEqual(item["other_user"], "Bob Dev")
        self.assertIsNotNone(item["ended_at"])
        self.assertEqual(item["grade"], 4.2)
        self.assertIsNone(item["scheduled_at"])
        self.assertIsNone(item["state"])

    def test_sessions_default_scope_is_upcoming(self):
        r = self.alice.get("/api/v1/sessions")
        self.assertEqual(r.status_code, 200, r.text)
        ids = {s["id"] for s in r.json()["sessions"]}
        self.assertIn(self.upcoming_session_id, ids)
        self.assertNotIn(self.recent_session_id, ids)

    def test_unauthenticated_sessions_returns_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).get("/api/v1/sessions")
        self.assertEqual(r.status_code, 401)

    # ── dashboard ─────────────────────────────────────────────────────────

    def test_dashboard_shape(self):
        r = self.alice.get("/api/v1/dashboard")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        for key in ("sessions_finalized", "streak_weeks", "next_session"):
            self.assertIn(key, body)
        self.assertIsInstance(body["sessions_finalized"], int)
        self.assertIsInstance(body["streak_weeks"], int)
        self.assertGreaterEqual(body["sessions_finalized"], 1)
        self.assertIsNotNone(body["next_session"])
        self.assertEqual(body["next_session"]["id"], self.upcoming_session_id)
        self.assertEqual(body["next_session"]["role"], "interviewer")
        self.assertEqual(body["next_session"]["other_user"], "Bob Dev")

    def test_unauthenticated_dashboard_returns_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).get("/api/v1/dashboard")
        self.assertEqual(r.status_code, 401)


if __name__ == "__main__":
    unittest.main()
