"""
Unit tests for webapp.signaling — the §4.2 routing rules against fake
sockets, no DB or ASGI stack involved.
"""

from __future__ import annotations

import unittest

from webapp.signaling import CLOSE_REPLACED, SignalingHub


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

    def types(self) -> list[str]:
        return [m["type"] for m in self.sent]


class HubTestCase(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.hub = SignalingHub()
        self.ivr = FakeSocket("ivr")
        self.cand = FakeSocket("cand")

    async def _join_both(self):
        ok_i = await self.hub.connect(1, "interviewer", "Alice", self.ivr)
        ok_c = await self.hub.connect(1, "candidate", "Bob", self.cand)
        return ok_i, ok_c


class TestConnect(HubTestCase):
    async def test_first_join_sees_no_peer(self):
        ok = await self.hub.connect(1, "interviewer", "Alice", self.ivr)
        self.assertEqual(ok, {"type": "ok", "role": "interviewer",
                              "peer_present": False, "admitted": False})

    async def test_second_join_sees_peer_and_notifies(self):
        _, ok_c = await self._join_both()
        self.assertTrue(ok_c["peer_present"])
        self.assertIn({"type": "peer-joined", "role": "candidate"}, self.ivr.sent)

    async def test_reconnect_replaces_old_socket(self):
        await self._join_both()
        newer = FakeSocket("cand2")
        ok = await self.hub.connect(1, "candidate", "Bob", newer)
        self.assertEqual(self.cand.closed_with, CLOSE_REPLACED)
        self.assertTrue(ok["peer_present"])
        # Stale socket's messages are ignored after replacement.
        await self.hub.handle(1, "candidate", self.cand, {"type": "knock"})
        self.assertNotIn("knock", self.ivr.types())

    async def test_admitted_flag_survives_reconnect(self):
        await self._join_both()
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "admit"})
        newer = FakeSocket("cand2")
        ok = await self.hub.connect(1, "candidate", "Bob", newer)
        self.assertTrue(ok["admitted"])

    async def test_admitted_hint_rebuilds_state_after_restart(self):
        # FM-1: the hub is process-local, so a server restart forgets the
        # admit. A fresh hub (a restarted process) rebuilds admitted=True from
        # the DB session state on reconnect — the reconnecting clients see
        # admitted (no re-knock) and sdp/ice relay works with no new 'admit'.
        ok_i = await self.hub.connect(1, "interviewer", "Alice", self.ivr, admitted=True)
        ok_c = await self.hub.connect(1, "candidate", "Bob", self.cand, admitted=True)
        self.assertTrue(ok_i["admitted"])
        self.assertTrue(ok_c["admitted"])
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "sdp", "description": "offer"})
        self.assertIn({"type": "sdp", "description": "offer"}, self.cand.sent)


class TestKnockAdmitDeny(HubTestCase):
    async def test_candidate_knock_reaches_interviewer_with_name(self):
        await self._join_both()
        await self.hub.handle(1, "candidate", self.cand, {"type": "knock"})
        self.assertIn({"type": "knock", "display_name": "Bob"}, self.ivr.sent)

    async def test_interviewer_knock_dropped(self):
        await self._join_both()
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "knock"})
        self.assertNotIn("knock", self.cand.types())

    async def test_candidate_admit_dropped(self):
        await self._join_both()
        await self.hub.handle(1, "candidate", self.cand, {"type": "admit"})
        self.assertNotIn("admit", self.ivr.types())
        # And the room must NOT become admitted by a candidate's attempt.
        await self.hub.handle(1, "candidate", self.cand, {"type": "sdp", "description": "x"})
        self.assertNotIn("sdp", self.ivr.types())

    async def test_deny_relayed_without_admitting(self):
        await self._join_both()
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "deny"})
        self.assertIn("deny", self.cand.types())
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "sdp", "description": "x"})
        self.assertNotIn("sdp", self.cand.types())


class TestRelayRules(HubTestCase):
    async def test_sdp_ice_blocked_before_admit(self):
        await self._join_both()
        await self.hub.handle(1, "candidate", self.cand, {"type": "sdp", "description": "offer"})
        await self.hub.handle(1, "candidate", self.cand, {"type": "ice", "candidate": "c"})
        self.assertNotIn("sdp", self.ivr.types())
        self.assertNotIn("ice", self.ivr.types())

    async def test_sdp_ice_relayed_after_admit_both_directions(self):
        await self._join_both()
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "admit"})
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "sdp", "description": "offer"})
        await self.hub.handle(1, "candidate", self.cand, {"type": "ice", "candidate": "cand-ice"})
        self.assertIn({"type": "sdp", "description": "offer"}, self.cand.sent)
        self.assertIn({"type": "ice", "candidate": "cand-ice"}, self.ivr.sent)

    async def test_relay_strips_extra_fields(self):
        await self._join_both()
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "admit"})
        await self.hub.handle(1, "candidate", self.cand,
                              {"type": "sdp", "description": "o", "evil": "x"})
        relayed = [m for m in self.ivr.sent if m["type"] == "sdp"][0]
        self.assertEqual(set(relayed), {"type", "description"})

    async def test_unknown_type_dropped(self):
        await self._join_both()
        baseline = self.ivr.types()  # peer-joined from the candidate joining
        await self.hub.handle(1, "candidate", self.cand, {"type": "shutdown"})
        await self.hub.handle(1, "candidate", self.cand, {"no_type": True})
        self.assertEqual(self.ivr.types(), baseline)

    async def test_ping_gets_pong(self):
        await self.hub.connect(1, "candidate", "Bob", self.cand)
        await self.hub.handle(1, "candidate", self.cand, {"type": "ping"})
        self.assertEqual(self.cand.types(), ["pong"])


class TestDisconnect(HubTestCase):
    async def test_peer_left_on_disconnect(self):
        await self._join_both()
        await self.hub.disconnect(1, "candidate", self.cand)
        self.assertIn("peer-left", self.ivr.types())

    async def test_bye_notifies_peer(self):
        await self._join_both()
        await self.hub.handle(1, "candidate", self.cand, {"type": "bye"})
        self.assertIn("peer-left", self.ivr.types())

    async def test_replaced_socket_disconnect_keeps_room(self):
        await self._join_both()
        newer = FakeSocket("cand2")
        await self.hub.connect(1, "candidate", "Bob", newer)
        # The OLD socket unwinding must not evict the newer one.
        await self.hub.disconnect(1, "candidate", self.cand)
        await self.hub.handle(1, "candidate", newer, {"type": "knock"})
        self.assertIn({"type": "knock", "display_name": "Bob"}, self.ivr.sent)

    async def test_dead_peer_send_does_not_raise(self):
        await self._join_both()
        await self.cand.close()
        # Relay to a closed socket is swallowed, not raised.
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "admit"})

    async def test_room_gc_when_empty(self):
        await self._join_both()
        await self.hub.disconnect(1, "candidate", self.cand)
        await self.hub.disconnect(1, "interviewer", self.ivr)
        self.assertEqual(self.hub._calls, {})


class TestSessionIsolation(HubTestCase):
    async def test_messages_never_cross_sessions(self):
        await self._join_both()
        other = FakeSocket("other-ivr")
        await self.hub.connect(2, "interviewer", "Cara", other)
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "admit"})
        await self.hub.handle(1, "interviewer", self.ivr, {"type": "sdp", "description": "o"})
        self.assertEqual(other.sent, [])


if __name__ == "__main__":
    unittest.main()
