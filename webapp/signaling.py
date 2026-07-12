"""
In-process signaling hub for practice calls (spec §4.2 as adapted by
INTEGRATION.md DV-3: same protocol, cookie auth instead of HMAC tokens,
FastAPI WebSocket route instead of a standalone Node service).

Rules enforced here:
  - at most one socket per (session, role); a newer socket replaces the old
    one (reconnect support) — the old socket is closed with CLOSE_REPLACED
  - knock comes only from the candidate; admit/deny only from the interviewer
  - sdp/ice are relayed only after admit, only between the two participants
  - unknown or unauthorized message types are dropped, never fatal
  - message CONTENT is never logged — types and ids only (spec §4.2)

Server→client additions beyond the spec's list: `peer-joined` / `peer-left`
presence pings and an `admitted` flag in `ok`, so a reconnecting client can
restore state without re-knocking. Within the spec's intent.

Heartbeat: clients ping every 30 s; the route replies pong and closes any
socket silent for HEARTBEAT_TIMEOUT. (Client-driven, so the server needs no
per-socket timer task.)

Deploy constraint (INTEGRATION.md §2): the hub is process-local state — run
the app as a single worker process.
"""

from __future__ import annotations

import logging
from typing import Optional, Protocol

logger = logging.getLogger(__name__)

HEARTBEAT_TIMEOUT = 60.0   # seconds of silence before a socket is presumed dead

CLOSE_REPLACED = 4000      # a newer socket for the same (session, role) took over
CLOSE_UNAUTHORIZED = 4401  # no/invalid session cookie
CLOSE_FORBIDDEN = 4403     # not a participant, or session not joinable


class PeerSocket(Protocol):
    """What the hub needs from a websocket — lets tests use plain fakes."""
    async def send_json(self, data: dict) -> None: ...
    async def close(self, code: int = 1000) -> None: ...


def peer_role(role: str) -> str:
    return "candidate" if role == "interviewer" else "interviewer"


async def _safe_send(socket: PeerSocket, data: dict) -> None:
    # A peer's socket can die between our liveness check and the send;
    # its own receive loop will clean it up — never let that kill ours.
    try:
        await socket.send_json(data)
    except Exception:
        logger.debug("send to dead socket dropped (type=%s)", data.get("type"))


class _Call:
    __slots__ = ("sockets", "names", "admitted")

    def __init__(self) -> None:
        self.sockets: dict[str, PeerSocket] = {}   # role -> live socket
        self.names: dict[str, str] = {}            # role -> display name
        self.admitted = False


class SignalingHub:
    def __init__(self) -> None:
        self._calls: dict[int, _Call] = {}

    async def connect(self, session_id: int, role: str, display_name: str,
                      socket: PeerSocket) -> dict:
        """Register a socket; returns the `ok` message to send to it."""
        call = self._calls.setdefault(session_id, _Call())

        old = call.sockets.get(role)
        if old is not None:
            await old.close(CLOSE_REPLACED)

        call.sockets[role] = socket
        call.names[role] = display_name

        peer = call.sockets.get(peer_role(role))
        if peer is not None:
            await _safe_send(peer, {"type": "peer-joined", "role": role})

        return {
            "type": "ok",
            "role": role,
            "peer_present": peer is not None,
            "admitted": call.admitted,
        }

    async def disconnect(self, session_id: int, role: str,
                         socket: PeerSocket) -> None:
        """Unregister a socket. No-op if this socket was already replaced."""
        call = self._calls.get(session_id)
        if call is None or call.sockets.get(role) is not socket:
            return

        del call.sockets[role]
        peer = call.sockets.get(peer_role(role))
        if peer is not None:
            await _safe_send(peer, {"type": "peer-left"})
        if not call.sockets:
            del self._calls[session_id]

    async def handle(self, session_id: int, role: str, socket: PeerSocket,
                     msg: dict) -> None:
        """Route one inbound client message per the §4.2 rules."""
        call = self._calls.get(session_id)
        if call is None or call.sockets.get(role) is not socket:
            return  # stale socket that lost a reconnect race

        mtype = msg.get("type")
        peer = call.sockets.get(peer_role(role))

        if mtype == "ping":
            await _safe_send(socket, {"type": "pong"})

        elif mtype == "pong":
            pass  # liveness handled by the route's receive timeout

        elif mtype == "knock" and role == "candidate":
            if peer is not None:
                await _safe_send(peer, {
                    "type": "knock",
                    "display_name": call.names[role],
                })

        elif mtype in ("admit", "deny") and role == "interviewer":
            if mtype == "admit":
                call.admitted = True
            if peer is not None:
                await _safe_send(peer, {"type": mtype})

        elif mtype in ("sdp", "ice") and call.admitted:
            if peer is not None:
                key = "description" if mtype == "sdp" else "candidate"
                await _safe_send(peer, {"type": mtype, key: msg.get(key)})

        elif mtype == "bye":
            if peer is not None:
                await _safe_send(peer, {"type": "peer-left"})

        else:
            # Unknown type, wrong role, or sdp/ice before admit: drop.
            logger.debug("dropped message type=%r sid=%s role=%s",
                         mtype, session_id, role)
