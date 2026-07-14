"""Cloudflare TURN credential minting for webapp/turn.py (no network)."""
import json
import unittest
from dataclasses import dataclass

import httpx

from webapp.turn import mint_turn_credentials


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


if __name__ == "__main__":
    unittest.main()
