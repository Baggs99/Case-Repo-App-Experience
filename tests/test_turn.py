"""Cloudflare TURN credential minting for webapp/turn.py (no network)."""
import json
import unittest
from dataclasses import dataclass

import httpx

from webapp.turn import mint_turn_credentials
from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@dataclass
class _FakeSettings:
    turn_provider: str = "cloudflare"
    turn_key_id: str | None = "KEY1"
    turn_token: str | None = "TOK1"

    @property
    def turn_enabled(self) -> bool:
        return bool(self.turn_key_id and self.turn_token)


class TestMintTurnCredentials(unittest.IsolatedAsyncioTestCase):
    async def test_mint_returns_normalized_ice_servers(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["path"] = request.url.path
            seen["auth"] = request.headers["Authorization"]
            seen["body"] = json.loads(request.content)
            return httpx.Response(200, json={
                "iceServers": {
                    "urls": ["turn:foo:3478?transport=udp", "turn:foo:3478?transport=tcp"],
                    "username": "u123",
                    "credential": "c456",
                }
            })

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            result = await mint_turn_credentials(_FakeSettings(), client=client)
        finally:
            await client.aclose()

        self.assertEqual(result, [{
            "urls": ["turn:foo:3478?transport=udp", "turn:foo:3478?transport=tcp"],
            "username": "u123",
            "credential": "c456",
        }])
        self.assertEqual(seen["path"], "/v1/turn/keys/KEY1/credentials/generate")
        self.assertEqual(seen["auth"], "Bearer TOK1")
        self.assertEqual(seen["body"], {"ttl": 3600})

    async def test_mint_passes_custom_ttl(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["body"] = json.loads(request.content)
            return httpx.Response(200, json={
                "iceServers": {
                    "urls": ["turn:foo:3478?transport=udp", "turn:foo:3478?transport=tcp"],
                    "username": "u123",
                    "credential": "c456",
                }
            })

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            await mint_turn_credentials(_FakeSettings(), ttl_seconds=120, client=client)
        finally:
            await client.aclose()

        self.assertEqual(seen["body"], {"ttl": 120})

    async def test_mint_returns_empty_when_turn_disabled(self):
        def handler(request: httpx.Request) -> httpx.Response:
            self.fail("no network call should happen when TURN is disabled")

        settings = _FakeSettings(turn_key_id=None, turn_token=None)
        self.assertFalse(settings.turn_enabled)

        result = await mint_turn_credentials(settings)
        self.assertEqual(result, [])

    async def test_mint_returns_empty_on_provider_error(self):
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(500)

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            result = await mint_turn_credentials(_FakeSettings(), client=client)
        finally:
            await client.aclose()

        self.assertEqual(result, [])

    async def test_mint_returns_empty_on_malformed_body(self):
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json={"unexpected": "shape"})

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        try:
            result = await mint_turn_credentials(_FakeSettings(), client=client)
        finally:
            await client.aclose()

        self.assertEqual(result, [])


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestJoinConfigTurn(unittest.TestCase):
    """Task 3: /join-config merges minted TURN creds into ice_servers for
    remote sessions only (setup mirrors tests/test_session_mode.py)."""

    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app).__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]

        a_session = create_session(cls.aid, user_agent="turn-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, a_session.id)
        b_session = create_session(cls.bid, user_agent="turn-test", ip_address=None)
        cls.bob.cookies.set(SESSION_COOKIE_NAME, b_session.id)

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('Turn Test Case', 'turn test case', 'DevSchool', 2098,"
                    " 'Technology', 'Turn-Type', 'Easy', 2, 2, 'output/none.pdf')"
                    " RETURNING id;")
                cls.case_id = cur.fetchone()[0]

        from webapp.repositories.practice_sessions import create_practice_session
        cls.remote_session = create_practice_session(
            interviewer_id=cls.aid, candidate_id=cls.bid, case_id=cls.case_id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM pairing_tokens WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)
        cls.bob.__exit__(None, None, None)

    def _claim_in_person_session(self) -> int:
        r = self.alice.post("/api/practice/pair/create", json={"case_id": self.case_id})
        self.assertEqual(r.status_code, 200, r.text)
        token = r.json()["token"]
        r = self.bob.post("/api/practice/pair/claim", json={"token": token})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["session_id"]

    def test_remote_session_join_config_includes_minted_turn(self):
        canned = [{"urls": ["turn:turn.example:3478"], "username": "u", "credential": "c"}]

        async def fake_mint(settings, **kwargs):
            return canned

        import webapp.routes.practice as practice_mod
        original = practice_mod.mint_turn_credentials
        practice_mod.mint_turn_credentials = fake_mint
        try:
            session_id = self.remote_session["id"]
            r = self.alice.get(f"/api/practice/{session_id}/join-config")
        finally:
            practice_mod.mint_turn_credentials = original

        self.assertEqual(r.status_code, 200, r.text)
        ice_servers = r.json()["ice_servers"]
        self.assertIn(canned[0], ice_servers)

    def test_in_person_session_join_config_excludes_turn(self):
        canned = [{"urls": ["turn:turn.example:3478"], "username": "u", "credential": "c"}]

        async def fake_mint(settings, **kwargs):
            return canned

        import webapp.routes.practice as practice_mod
        original = practice_mod.mint_turn_credentials
        practice_mod.mint_turn_credentials = fake_mint
        try:
            session_id = self._claim_in_person_session()
            r = self.alice.get(f"/api/practice/{session_id}/join-config")
        finally:
            practice_mod.mint_turn_credentials = original

        self.assertEqual(r.status_code, 200, r.text)
        ice_servers = r.json()["ice_servers"]
        self.assertNotIn(canned[0], ice_servers)
        for server in ice_servers:
            self.assertNotIn("turn:", json.dumps(server))

    def test_remote_session_join_config_stun_only_when_turn_unconfigured(self):
        """No monkeypatch: real mint_turn_credentials runs against whatever
        TURN_* env is set in this environment; dev env has TURN unset, so
        this asserts the STUN-only degrade never 500s."""
        session_id = self.remote_session["id"]
        r = self.alice.get(f"/api/practice/{session_id}/join-config")
        self.assertEqual(r.status_code, 200, r.text)
        ice_servers = r.json()["ice_servers"]
        for server in ice_servers:
            self.assertNotIn("turn:", json.dumps(server))


if __name__ == "__main__":
    unittest.main()
