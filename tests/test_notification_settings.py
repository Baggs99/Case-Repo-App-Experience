"""
Purpose: notification_settings repo (defaults, upsert) + push choke point that
         skips a category the user disabled.
Inputs:  seeded dev Postgres via tests.test_ws_integration (_DB_URL/_READY);
         user b@yale.edu. send_push + load_settings are monkeypatched.
Outputs: writes b@yale.edu's notification_settings + a device token; cleans up.
Run:     .venv/bin/python -m pytest tests/test_notification_settings.py -q
"""

from __future__ import annotations

import unittest
from dataclasses import dataclass
from unittest.mock import patch

import psycopg

from tests.test_ws_integration import _DB_URL, _READY


@dataclass
class _EnabledSettings:
    apns_key_path: str | None = "/tmp/fake.p8"
    apns_key_id: str | None = "K"
    apns_team_id: str | None = "T"
    apns_bundle_id: str | None = "study.mycase"
    apns_use_sandbox: bool = True


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestNotificationSettingsRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'b@yale.edu';")
                cls.uid = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM notification_settings WHERE user_id = %s;",
                            (cls.uid,))
        cls._ctx.__exit__(None, None, None)

    def _clean(self):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM notification_settings WHERE user_id = %s;",
                            (self.uid,))

    def test_defaults_all_true_when_no_row(self):
        from webapp.repositories.notification_settings import get_settings
        self._clean()
        s = get_settings(self.uid)
        self.assertEqual(s, {"proposals": True, "session_reminders": True,
                             "feedback": True, "free_now": True, "community": True})

    def test_update_upserts_and_returns_full(self):
        from webapp.repositories.notification_settings import update_settings, get_settings
        self._clean()
        s = update_settings(self.uid, community=False, free_now=False)
        self.assertFalse(s["community"])
        self.assertFalse(s["free_now"])
        self.assertTrue(s["proposals"])
        self.assertFalse(get_settings(self.uid)["community"])

    def test_notifications_allowed(self):
        from webapp.repositories.notification_settings import update_settings, notifications_allowed
        self._clean()
        update_settings(self.uid, community=False)
        self.assertFalse(notifications_allowed(self.uid, "community"))
        self.assertTrue(notifications_allowed(self.uid, "proposals"))
        self.assertTrue(notifications_allowed(self.uid, "unknown_category"))


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestPushChokePoint(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'b@yale.edu';")
                cls.uid = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        from webapp.repositories.device_tokens import delete_token
        delete_token(cls.uid, "choke-token")
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM notification_settings WHERE user_id = %s;",
                            (cls.uid,))
        cls._ctx.__exit__(None, None, None)

    async def _run(self, *, category, disable):
        from webapp.push import events
        from webapp.repositories.device_tokens import upsert_token
        from webapp.repositories.notification_settings import update_settings
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM notification_settings WHERE user_id = %s;",
                            (self.uid,))
        upsert_token(self.uid, "choke-token", "ios")
        if disable:
            update_settings(self.uid, **{category: False})
        sent = []

        async def _fake_send(token, **kwargs):
            sent.append(token)
            return 200

        with patch.object(events, "load_settings", return_value=_EnabledSettings()), \
             patch.object(events, "send_push", _fake_send):
            await events.push_to_user(self.uid, title="t", body="b", category=category)
        return sent

    async def test_disabled_category_not_sent(self):
        sent = await self._run(category="community", disable=True)
        self.assertEqual(sent, [])

    async def test_enabled_category_sent(self):
        sent = await self._run(category="community", disable=False)
        self.assertEqual(sent, ["choke-token"])

    async def test_no_category_always_sent(self):
        from webapp.push import events
        from webapp.repositories.device_tokens import upsert_token
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE notification_settings SET community = FALSE "
                            "WHERE user_id = %s;", (self.uid,))
        upsert_token(self.uid, "choke-token", "ios")
        sent = []

        async def _fake_send(token, **kwargs):
            sent.append(token)
            return 200

        with patch.object(events, "load_settings", return_value=_EnabledSettings()), \
             patch.object(events, "send_push", _fake_send):
            await events.push_to_user(self.uid, title="t", body="b")  # category=None
        self.assertEqual(sent, ["choke-token"])


if __name__ == "__main__":
    unittest.main()
