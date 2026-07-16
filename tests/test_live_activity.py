"""
Task 9: ActivityKit Live Activity push token registration + update pushes
(webapp/repositories/live_activity_tokens.py, webapp/push/apns.py's
send_live_activity_push, webapp/push/live_activity.py).

Needs the seeded dev Postgres for the token-repo/session fixtures — skips
cleanly otherwise (same idiom as tests/test_push_events.py). send_push-style
network calls go through httpx.MockTransport (tests/test_apns.py pattern);
no real APNs traffic.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from dataclasses import dataclass
from unittest.mock import patch

import httpx
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization

from tests.test_ws_integration import _DB_URL, _READY


def _test_key_pem() -> bytes:
    key = ec.generate_private_key(ec.SECP256R1())
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )


@dataclass
class _FakeSettings:
    pem_bytes: bytes
    apns_key_id: str = "K"
    apns_team_id: str = "T"
    apns_bundle_id: str = "studio.ogee.caseroom"
    apns_use_sandbox: bool = True

    def __post_init__(self):
        f = tempfile.NamedTemporaryFile(suffix=".pem", delete=False)
        f.write(self.pem_bytes)
        f.close()
        self.apns_key_path = f.name


_DISABLED_SETTINGS = _FakeSettings(
    b"", apns_key_id=None, apns_team_id=None, apns_bundle_id=None,
)


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestTokenUpsert(unittest.TestCase):
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
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]

        from webapp.repositories.practice_sessions import create_practice_session

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('T9 Case', 't9 case', 'DevSchool', 2095, 'Technology',"
                    " 'T9-Type', 'Easy', 2, 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]

        cls.session = create_practice_session(
            interviewer_id=cls.aid, candidate_id=cls.bid, case_id=cls.case_id,
        )
        cls.session_id = cls.session["id"]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM live_activity_tokens WHERE session_id = %s;",
                            (cls.session_id,))
                cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (cls.session_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def test_upsert_then_reregister_replaces_token(self):
        from webapp.repositories.live_activity_tokens import (
            tokens_for_session, upsert_token,
        )

        upsert_token(self.session_id, self.aid, "tok-v1")
        rows = tokens_for_session(self.session_id)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["user_id"], self.aid)
        self.assertEqual(rows[0]["push_token"], "tok-v1")

        # Re-register (e.g. app relaunch): same (session, user) replaces the
        # token, still one row.
        upsert_token(self.session_id, self.aid, "tok-v2")
        rows = tokens_for_session(self.session_id)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["push_token"], "tok-v2")

        # A second user in the same session gets its own row.
        upsert_token(self.session_id, self.bid, "tok-bob")
        rows = tokens_for_session(self.session_id)
        self.assertEqual(len(rows), 2)
        by_user = {r["user_id"]: r["push_token"] for r in rows}
        self.assertEqual(by_user, {self.aid: "tok-v2", self.bid: "tok-bob"})

    def test_delete_token_is_scoped_to_user(self):
        import psycopg
        from webapp.repositories.live_activity_tokens import (
            delete_token, tokens_for_session, upsert_token,
        )
        # Isolate from other tests in this class that share the session.
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM live_activity_tokens WHERE session_id = %s;",
                            (self.session_id,))

        upsert_token(self.session_id, self.aid, "tok-alice")
        upsert_token(self.session_id, self.bid, "tok-bob")

        # A mismatched user_id must NOT delete another user's row.
        delete_token(self.bid, "tok-alice")
        remaining = {r["user_id"]: r["push_token"]
                     for r in tokens_for_session(self.session_id)}
        self.assertEqual(remaining, {self.aid: "tok-alice", self.bid: "tok-bob"})

        # Correct (user_id, push_token) pair deletes exactly that row.
        delete_token(self.aid, "tok-alice")
        remaining = {r["user_id"]: r["push_token"]
                     for r in tokens_for_session(self.session_id)}
        self.assertEqual(remaining, {self.bid: "tok-bob"})

        # Leave the session clean for sibling tests sharing this fixture.
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM live_activity_tokens WHERE session_id = %s;",
                            (self.session_id,))


class TestIso(unittest.TestCase):
    def test_truncates_microseconds(self):
        from datetime import datetime, timezone

        from webapp.push.live_activity import _iso

        dt = datetime(2026, 7, 14, 12, 0, 0, 123456, tzinfo=timezone.utc)
        result = _iso(dt)

        self.assertNotIn(".", result)

    def test_none_passthrough(self):
        from webapp.push.live_activity import _iso

        self.assertIsNone(_iso(None))


class TestSendLiveActivityPush(unittest.IsolatedAsyncioTestCase):
    async def test_liveactivity_push_shape(self):
        from webapp.push.apns import send_live_activity_push

        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["path"] = request.url.path
            seen["topic"] = request.headers["apns-topic"]
            seen["push_type"] = request.headers["apns-push-type"]
            seen["priority"] = request.headers["apns-priority"]
            seen["payload"] = json.loads(request.content)
            return httpx.Response(200)

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            status = await send_live_activity_push(
                "ff00" * 16, event="update",
                content_state={"state": "live", "role": "interviewer",
                               "counterpart_name": "Bob", "scheduled_at": None,
                               "started_at": "2026-07-14T12:00:00+00:00"},
                timestamp=1752494400,
                settings=_FakeSettings(_test_key_pem()), client=client,
            )
        finally:
            await client.aclose()

        self.assertEqual(status, 200)
        self.assertEqual(seen["path"], "/3/device/" + "ff00" * 16)
        self.assertEqual(seen["push_type"], "liveactivity")
        self.assertEqual(seen["topic"], "studio.ogee.caseroom.push-type.liveactivity")
        self.assertEqual(seen["priority"], "10")
        self.assertEqual(seen["payload"]["aps"]["timestamp"], 1752494400)
        self.assertEqual(seen["payload"]["aps"]["event"], "update")
        self.assertEqual(seen["payload"]["aps"]["content-state"]["state"], "live")
        self.assertEqual(seen["payload"]["aps"]["content-state"]["counterpart_name"], "Bob")
        self.assertNotIn("dismissal-date", seen["payload"]["aps"])

    async def test_end_event_sets_dismissal_date(self):
        from webapp.push.apns import send_live_activity_push

        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["payload"] = json.loads(request.content)
            return httpx.Response(200)

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            await send_live_activity_push(
                "ff00" * 16, event="end",
                content_state={"state": "finalized"},
                timestamp=1752494400,
                settings=_FakeSettings(_test_key_pem()), client=client,
            )
        finally:
            await client.aclose()

        self.assertEqual(seen["payload"]["aps"]["event"], "end")
        self.assertEqual(seen["payload"]["aps"]["dismissal-date"], 1752494400)


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestPushLiveActivityUpdate(unittest.IsolatedAsyncioTestCase):
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
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]

        from webapp.repositories.practice_sessions import create_practice_session

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('T9 Case 2', 't9 case 2', 'DevSchool', 2095, 'Technology',"
                    " 'T9-Type', 'Easy', 2, 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]

        cls.session = create_practice_session(
            interviewer_id=cls.aid, candidate_id=cls.bid, case_id=cls.case_id,
        )
        cls.session_id = cls.session["id"]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM live_activity_tokens WHERE session_id = %s;",
                            (cls.session_id,))
                cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (cls.session_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        from webapp.repositories.live_activity_tokens import upsert_token
        upsert_token(self.session_id, self.aid, "la-tok-a")
        upsert_token(self.session_id, self.bid, "la-tok-b")

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM live_activity_tokens WHERE session_id = %s;",
                            (self.session_id,))

    async def test_pushes_all_tokens_with_per_user_content_state(self):
        from webapp.push import live_activity

        calls = []

        async def recorder(token, *, event, content_state, timestamp=None,
                           settings=None, client=None):
            calls.append((token, event, content_state))
            return 200

        with patch.object(live_activity, "send_live_activity_push", recorder):
            await live_activity.push_live_activity_update(
                self.session_id, event="update", settings=_FakeSettings(_test_key_pem()))

        self.assertEqual(len(calls), 2)
        by_token = {tok: cs for tok, ev, cs in calls}
        self.assertEqual(by_token["la-tok-a"]["role"], "interviewer")
        self.assertEqual(by_token["la-tok-b"]["role"], "candidate")
        # Each recipient's counterpart is the OTHER participant.
        self.assertNotEqual(by_token["la-tok-a"]["counterpart_name"],
                             by_token["la-tok-b"]["counterpart_name"])
        for _, ev, _ in calls:
            self.assertEqual(ev, "update")

    async def test_dead_token_deleted_on_410(self):
        from webapp.push import live_activity
        from webapp.repositories.live_activity_tokens import tokens_for_session

        async def recorder(token, *, event, content_state, timestamp=None,
                           settings=None, client=None):
            return 410 if token == "la-tok-a" else 200

        with patch.object(live_activity, "send_live_activity_push", recorder):
            await live_activity.push_live_activity_update(
                self.session_id, settings=_FakeSettings(_test_key_pem()))

        remaining = {r["push_token"] for r in tokens_for_session(self.session_id)}
        self.assertEqual(remaining, {"la-tok-b"})

    async def test_noop_when_push_disabled(self):
        from webapp.push import live_activity

        calls = []

        async def recorder(token, *, event, content_state, timestamp=None,
                           settings=None, client=None):
            calls.append(token)
            return 200

        with patch.object(live_activity, "send_live_activity_push", recorder):
            await live_activity.push_live_activity_update(
                self.session_id, settings=_DISABLED_SETTINGS)

        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
