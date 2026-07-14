"""
WebSocket endpoint for practice-call signaling: /ws/practice/{session_id}.

Auth caveat: SessionMiddleware is a BaseHTTPMiddleware and never runs for
WebSocket connections, so the cookie is verified here directly. Same session
cookie, same server-side lookup — just invoked manually.

DB lookups run in the threadpool (they're sync psycopg) so the event loop —
which is relaying every live call in the process — never blocks on them.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import suppress

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from starlette.concurrency import run_in_threadpool

from webapp.auth.sessions import SESSION_COOKIE_NAME, get_user_for_session
from webapp.repositories.practice_sessions import get_practice_session, role_of
from webapp.signaling import (
    CLOSE_FORBIDDEN,
    CLOSE_UNAUTHORIZED,
    HEARTBEAT_TIMEOUT,
    SignalingHub,
)

logger = logging.getLogger(__name__)

router = APIRouter()

# Process-wide singleton — one hub relays every live call (single-worker
# deploy constraint, INTEGRATION.md §2).
hub = SignalingHub()

_JOINABLE_STATES = ("scheduled", "lobby", "live")


@router.websocket("/ws/practice/{session_id}")
async def practice_ws(websocket: WebSocket, session_id: int):
    cookie = websocket.cookies.get(SESSION_COOKIE_NAME)
    user = await run_in_threadpool(get_user_for_session, cookie) if cookie else None
    if user is None:
        await websocket.close(code=CLOSE_UNAUTHORIZED)
        return

    session = await run_in_threadpool(get_practice_session, session_id)
    role = role_of(session, user.id) if session else None
    if session is None or role is None or session["state"] not in _JOINABLE_STATES:
        # Non-participants get the same close as a missing session (DV-11).
        await websocket.close(code=CLOSE_FORBIDDEN)
        return

    await websocket.accept()
    # A `live` session means the call was already admitted; pass that so a
    # reconnect after a server restart restores admit state (FM-1) rather than
    # forcing a re-knock and gating sdp/ice relay.
    ok = await hub.connect(
        session_id, role, session[f"{role}_name"], websocket,
        admitted=session["state"] == "live",
    )
    await websocket.send_json(ok)

    try:
        while True:
            try:
                msg = await asyncio.wait_for(
                    websocket.receive_json(), timeout=HEARTBEAT_TIMEOUT
                )
            except asyncio.TimeoutError:
                logger.info("ws heartbeat timeout sid=%s role=%s", session_id, role)
                break
            except ValueError:
                continue  # malformed JSON frame — drop it, keep the socket
            await hub.handle(session_id, role, websocket, msg)
    except WebSocketDisconnect:
        pass
    finally:
        await hub.disconnect(session_id, role, websocket)
        with suppress(Exception):
            await websocket.close()
