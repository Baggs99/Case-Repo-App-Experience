"""
Task 4: push-events fan-out (webapp/push/events.py).

Needs the seeded dev Postgres for token seeding — skips cleanly otherwise
(same idiom as tests/test_api_v1_devices.py). send_push and load_settings
are monkeypatched so no real network call or real env is involved.
"""

from __future__ import annotations

import unittest
from dataclasses import dataclass
from unittest.mock import patch

from tests.test_ws_integration import _DB_URL, _READY


@dataclass
class _FakeSettings:
    apns_key_path: str | None = "/tmp/fake.p8"
    apns_key_id: str | None = "K"
    apns_team_id: str | None = "T"
    apns_bundle_id: str | None = "studio.ogee.caseroom"
    apns_use_sandbox: bool = True


_DISABLED_SETTINGS = _FakeSettings(
    apns_key_path=None, apns_key_id=None, apns_team_id=None, apns_bundle_id=None,
)


class TestPushEnabled(unittest.TestCase):
    def test_enabled_when_all_fields_present(self):
        from webapp.push.events import push_enabled
        self.assertTrue(push_enabled(_FakeSettings()))

    def test_disabled_when_any_field_missing(self):
        from webapp.push.events import push_enabled
        self.assertFalse(push_enabled(_DISABLED_SETTINGS))
        self.assertFalse(push_enabled(_FakeSettings(apns_bundle_id=None)))


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestPushToUser(unittest.IsolatedAsyncioTestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()  # runs app startup so get_pool() is initialized

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.uid = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        from webapp.repositories.device_tokens import upsert_token
        upsert_token(self.uid, "push-tok-1", "ios")
        upsert_token(self.uid, "push-tok-2", "ios")

    def tearDown(self):
        from webapp.repositories.device_tokens import delete_token
        delete_token(self.uid, "push-tok-1")
        delete_token(self.uid, "push-tok-2")

    async def test_pushes_all_tokens_when_enabled(self):
        from webapp.push import events

        calls = []

        async def recorder(token, *, title, body, data=None,
                           interruption_level=None, settings=None, client=None):
            calls.append(token)
            return 200

        with patch.object(events, "load_settings", lambda: _FakeSettings()), \
             patch.object(events, "send_push", recorder):
            await events.push_to_user(self.uid, title="t", body="b", data={"kind": "x"})

        self.assertEqual(sorted(calls), ["push-tok-1", "push-tok-2"])

    async def test_dead_token_deleted_on_410(self):
        from webapp.push import events
        from webapp.repositories.device_tokens import tokens_for_user

        async def recorder(token, *, title, body, data=None,
                           interruption_level=None, settings=None, client=None):
            return 410 if token == "push-tok-1" else 200

        with patch.object(events, "load_settings", lambda: _FakeSettings()), \
             patch.object(events, "send_push", recorder):
            await events.push_to_user(self.uid, title="t", body="b", data={"kind": "x"})

        self.assertEqual(tokens_for_user(self.uid), ["push-tok-2"])

    async def test_noop_when_push_disabled(self):
        from webapp.push import events

        calls = []

        async def recorder(token, *, title, body, data=None,
                           interruption_level=None, settings=None, client=None):
            calls.append(token)
            return 200

        with patch.object(events, "load_settings", lambda: _DISABLED_SETTINGS), \
             patch.object(events, "send_push", recorder):
            await events.push_to_user(self.uid, title="t", body="b", data={"kind": "x"})

        self.assertEqual(calls, [])

    async def test_interruption_level_passed_through(self):
        from webapp.push import events

        seen = {}

        async def recorder(token, *, title, body, data=None,
                           interruption_level=None, settings=None, client=None):
            seen["interruption_level"] = interruption_level
            return 200

        with patch.object(events, "load_settings", lambda: _FakeSettings()), \
             patch.object(events, "send_push", recorder):
            await events.push_to_user(self.uid, title="Knock", body="b",
                                       data={"kind": "knock"},
                                       interruption_level="time-sensitive")

        self.assertEqual(seen["interruption_level"], "time-sensitive")


if __name__ == "__main__":
    unittest.main()
