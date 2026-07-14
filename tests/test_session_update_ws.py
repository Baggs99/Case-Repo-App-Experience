"""
Unit tests for SignalingHub.broadcast_session_update — pushing a
state/consent change notice to BOTH connected participants over the
signaling WS, no DB or ASGI stack involved.
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


class TestBroadcastSessionUpdate(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.hub = SignalingHub()
        self.ivr = FakeSocket("ivr")
        self.cand = FakeSocket("cand")

    async def test_broadcasts_to_both_connected_participants(self):
        await self.hub.connect(1, "interviewer", "Alice", self.ivr)
        await self.hub.connect(1, "candidate", "Bob", self.cand)

        result = await self.hub.broadcast_session_update(1)

        self.assertEqual(result, 2)
        self.assertIn({"type": "session-update"}, self.ivr.sent)
        self.assertIn({"type": "session-update"}, self.cand.sent)

    async def test_no_call_returns_zero(self):
        result = await self.hub.broadcast_session_update(999)
        self.assertEqual(result, 0)

    async def test_no_call_does_not_raise(self):
        try:
            await self.hub.broadcast_session_update(999)
        except Exception as exc:  # pragma: no cover - failure path
            self.fail(f"broadcast_session_update raised: {exc}")


if __name__ == "__main__":
    unittest.main()
