"""
Unit tests for SignalingHub.broadcast_reveal — pushing the exhibit key over
the signaling WS on reveal, no DB or ASGI stack involved.
"""

from __future__ import annotations

import unittest

from webapp.signaling import SignalingHub


class FakeSocket:
    def __init__(self, name: str = "?"):
        self.name = name
        self.sent: list[dict] = []
        self.closed_with: int | None = None

    async def send_json(self, data: dict) -> None:
        if self.closed_with is not None:
            raise RuntimeError("send on closed socket")
        self.sent.append(data)

    async def close(self, code: int = 1000) -> None:
        self.closed_with = code


class TestBroadcastReveal(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.hub = SignalingHub()
        self.ivr = FakeSocket("ivr")
        self.cand = FakeSocket("cand")

    async def test_broadcasts_to_connected_candidate(self):
        await self.hub.connect(1, "interviewer", "Alice", self.ivr)
        await self.hub.connect(1, "candidate", "Bob", self.cand)

        result = await self.hub.broadcast_reveal(1, exhibit_id=5, key_b64="AAAA")

        self.assertTrue(result)
        self.assertIn(
            {"type": "reveal", "exhibit_id": 5, "key_b64": "AAAA"},
            self.cand.sent,
        )

    async def test_no_call_returns_false(self):
        result = await self.hub.broadcast_reveal(999, exhibit_id=5, key_b64="AAAA")
        self.assertFalse(result)

    async def test_no_candidate_connected_returns_false(self):
        await self.hub.connect(1, "interviewer", "Alice", self.ivr)
        result = await self.hub.broadcast_reveal(1, exhibit_id=5, key_b64="AAAA")
        self.assertFalse(result)


if __name__ == "__main__":
    unittest.main()
