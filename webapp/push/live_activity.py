"""
Purpose: Fan out ActivityKit Live Activity update pushes to a session's registered devices.
Inputs: session_id, event ("update"/"end"); APNS_* settings; live_activity_tokens + practice_sessions tables.
Outputs: HTTPS pushes via webapp.push.apns.send_live_activity_push; deletes dead (410) tokens.
Run: called from webapp/routes/practice.py (via FastAPI BackgroundTasks) after session transitions; no CLI entrypoint.
"""

from __future__ import annotations

import logging
import time

import httpx
from starlette.concurrency import run_in_threadpool

from webapp.push.apns import send_live_activity_push
from webapp.push.events import push_enabled
from webapp.repositories.live_activity_tokens import delete_token, tokens_for_session
from webapp.repositories.practice_sessions import get_practice_session
from webapp.settings import load_settings

logger = logging.getLogger(__name__)


def _iso(dt) -> str | None:
    return dt.replace(microsecond=0).isoformat() if dt is not None else None


def _content_state(session: dict, user_id: int) -> dict:
    """Per-recipient content-state. Keys (Task 10 iOS ContentState must
    Codable-match these exactly):
      state           - session state string (scheduled/lobby/live/debrief/finalized/aborted)
      role            - recipient's own role ("interviewer"|"candidate")
      counterpart_name - the OTHER participant's display name
      scheduled_at    - ISO-8601 string or null
      started_at      - ISO-8601 string or null
    """
    if user_id == session["interviewer_id"]:
        role, counterpart_name = "interviewer", session["candidate_name"]
    else:
        role, counterpart_name = "candidate", session["interviewer_name"]
    return {
        "state": session["state"],
        "role": role,
        "counterpart_name": counterpart_name,
        "scheduled_at": _iso(session["scheduled_at"]),
        "started_at": _iso(session["started_at"]),
    }


async def push_live_activity_update(session_id: int, *, event: str = "update",
                                     settings=None) -> None:
    """Push an ActivityKit update (or "end") to every device registered for
    session_id's Live Activity. No-op when APNs isn't configured (normal in
    dev). Deletes a token on a 410 (dead token) response. Never raises — a
    push failure must not break the caller (mirrors webapp.push.events).
    """
    try:
        if settings is None:
            settings = load_settings()
        if not push_enabled(settings):
            return
        tokens = await run_in_threadpool(tokens_for_session, session_id)
        if not tokens:
            return
        session = await run_in_threadpool(get_practice_session, session_id)
        if session is None:
            return
        timestamp = int(time.time())
        client = httpx.AsyncClient(http2=True, timeout=10.0)
        try:
            for row in tokens:
                content_state = _content_state(session, row["user_id"])
                try:
                    status = await send_live_activity_push(
                        row["push_token"], event=event, content_state=content_state,
                        timestamp=timestamp, settings=settings, client=client,
                    )
                except Exception:
                    # One token's transient failure must not block the others.
                    logger.exception(
                        "Live Activity push failed for session_id=%s token=%s",
                        session_id, row["push_token"])
                    continue
                if status == 410:
                    await run_in_threadpool(delete_token, row["push_token"])
        finally:
            await client.aclose()
    except Exception:
        logger.exception("Live Activity push fan-out failed for session_id=%s", session_id)
