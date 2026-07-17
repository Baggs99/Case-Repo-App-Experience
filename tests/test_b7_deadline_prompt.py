"""B7 Task 7: deadline-passed push from the maintenance loop — push fires once
per passed-deadline firm, snoozes for a week, honors the daily guard, and the
B5 notification-settings seam fails open when the table is absent."""

from __future__ import annotations

import datetime
import unittest
from unittest.mock import patch

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDeadlinePrompt(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.repositories import firms as firms_repo
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.aid = cur.fetchone()[0]
        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        import webapp.maintenance as m
        m._deadline_prompt_last_date = None    # reset the daily guard
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (self.aid,))

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (self.aid,))

    async def test_push_fires_then_snoozes(self):
        from webapp import maintenance
        from webapp.repositories import user_firms as uf
        uf.track(self.aid, self.rb)            # Roland Berger deadline is passed
        calls = []

        async def _capture(user_id, **kw):
            calls.append((user_id, kw))

        with patch("webapp.maintenance.push_to_user", _capture):
            sent = await maintenance.sweep_deadline_prompts(datetime.date(2026, 7, 17))
            self.assertEqual(sent, 1)
            self.assertEqual(calls[0][0], self.aid)
            self.assertIn("Roland", calls[0][1]["body"])
            # Snoozed now → second sweep sends nothing.
            sent2 = await maintenance.sweep_deadline_prompts(datetime.date(2026, 7, 17))
            self.assertEqual(sent2, 0)

    async def test_daily_guard_runs_once_per_day(self):
        from webapp import maintenance
        from webapp.repositories import user_firms as uf
        from webapp.settings import load_settings
        uf.track(self.aid, self.rb)

        async def _noop(user_id, **kw):
            return None

        async def _no_starting_soon(*a, **k):
            return None

        with patch("webapp.maintenance.push_to_user", _noop), \
             patch("webapp.push.starting_soon.push_to_user", _no_starting_soon):
            r1 = await maintenance.run_maintenance_pass(
                load_settings(), as_of=datetime.date(2026, 7, 17))
            r2 = await maintenance.run_maintenance_pass(
                load_settings(), as_of=datetime.date(2026, 7, 17))
        self.assertEqual(r1["deadline_prompts"], 1)   # first pass today runs it
        self.assertEqual(r2["deadline_prompts"], 0)   # guard blocks the re-run

    def test_b5_seam_fails_open_without_settings_table(self):
        from webapp import maintenance
        # notification_settings does not exist on this branch (B5 unmerged) →
        # the seam must allow the push (fail-open).
        self.assertTrue(maintenance._deadline_notifications_allowed(self.aid))


if __name__ == "__main__":
    unittest.main()
