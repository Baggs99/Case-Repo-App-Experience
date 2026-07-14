"""
Task 5: starting-soon push loop (webapp/push/starting_soon.py).

Needs the seeded dev Postgres for session seeding — skips cleanly otherwise
(same idiom as tests/test_api_v1_devices.py). push_to_user is monkeypatched
so no real network call is involved.
"""

from __future__ import annotations

import json
import unittest
from unittest.mock import patch

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestNotifyStartingSoon(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()  # runs app startup so get_pool() is initialized

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.interviewer_id = ids["a@yale.edu"]
        cls.candidate_id = ids["b@yale.edu"]

        from webapp.repositories.practice_sessions import (
            get_default_rubric_template_id)
        from webapp.repositories.rooms import get_or_create_room

        room_id = get_or_create_room(cls.interviewer_id)["id"]

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title,"
                    " source_school, source_year, industry, case_type,"
                    " difficulty, difficulty_score, page_count, pdf_path)"
                    " VALUES ('T5 Starting Soon Case', 't5 starting soon case',"
                    " 'DevSchool', 2095, 'Technology', 'T5-Type', 'Easy', 2,"
                    " 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]

        cls.template_id = get_default_rubric_template_id(cls.case_id, cls.interviewer_id)
        cls.room_id = room_id

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def _seed_session(self, scheduled_at_sql: str) -> int:
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO practice_sessions (room_id, interviewer_id,"
                    " candidate_id, case_id, rubric_template_id, state,"
                    " scheduled_at)"
                    f" VALUES (%s, %s, %s, %s, %s, 'scheduled', {scheduled_at_sql})"
                    " RETURNING id;",
                    (self.room_id, self.interviewer_id, self.candidate_id,
                     self.case_id, self.template_id))
                return cur.fetchone()[0]

    def tearDown(self):
        import psycopg
        for sid in getattr(self, "_session_ids", []):
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (sid,))
        self._session_ids = []

    async def test_notifies_both_participants_for_imminent_session(self):
        from webapp.push import starting_soon

        sid = self._seed_session("now() + interval '10 minutes'")
        self._session_ids = [sid]

        calls = []

        async def recorder(user_id, *, title, body, data=None, interruption_level=None):
            calls.append((user_id, title, body, data, interruption_level))

        with patch.object(starting_soon, "push_to_user", recorder):
            count = await starting_soon.notify_starting_soon()

        self.assertEqual(count, 1)
        notified_users = sorted(c[0] for c in calls)
        self.assertEqual(notified_users, sorted([self.interviewer_id, self.candidate_id]))
        for _, title, body, data, interruption_level in calls:
            self.assertEqual(data, {"kind": "starting_soon", "session_id": sid})
            self.assertEqual(interruption_level, "time-sensitive")

    async def test_second_pass_is_idempotent(self):
        from webapp.push import starting_soon

        sid = self._seed_session("now() + interval '10 minutes'")
        self._session_ids = [sid]

        calls = []

        async def recorder(user_id, *, title, body, data=None, interruption_level=None):
            calls.append(user_id)

        with patch.object(starting_soon, "push_to_user", recorder):
            first = await starting_soon.notify_starting_soon()
            second = await starting_soon.notify_starting_soon()

        self.assertEqual(first, 1)
        self.assertEqual(second, 0)

    async def test_session_far_in_future_not_selected(self):
        from webapp.push import starting_soon

        sid = self._seed_session("now() + interval '2 hours'")
        self._session_ids = [sid]

        calls = []

        async def recorder(user_id, *, title, body, data=None, interruption_level=None):
            calls.append(user_id)

        with patch.object(starting_soon, "push_to_user", recorder):
            count = await starting_soon.notify_starting_soon()

        self.assertEqual(count, 0)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
