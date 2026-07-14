"""
Purpose: Fan out APNs pushes to a user's devices and schedule them fire-and-forget.
Inputs: user_id, title/body/data/interruption_level; APNS_* settings (webapp.settings.load_settings); device_tokens table.
Outputs: HTTPS pushes via webapp.push.apns.send_push; deletes dead (410) tokens.
Run: called from route handlers (via FastAPI BackgroundTasks) and webapp/routes/signal_ws.py (via notify()); no CLI entrypoint.
"""

from __future__ import annotations

import asyncio
import logging

import httpx

from webapp.push.apns import send_push
from webapp.repositories.device_tokens import delete_token, tokens_for_user
from webapp.settings import load_settings

logger = logging.getLogger(__name__)

# Keeps fire-and-forget tasks alive until they finish — asyncio only holds a
# weak reference to a task, so without this the GC can cancel it mid-flight.
_background_tasks: set[asyncio.Task] = set()


def push_enabled(settings) -> bool:
    """True iff all four APNs provider settings are present."""
    return bool(settings.apns_key_path and settings.apns_key_id
                and settings.apns_team_id and settings.apns_bundle_id)


async def push_to_user(user_id: int, *, title: str, body: str, data: dict | None = None,
                       interruption_level: str | None = None) -> None:
    """Push `title`/`body` to every device registered to user_id.

    No-op when APNs isn't configured (normal in dev). Deletes a token on a
    410 (dead token) response. Never raises — a push failure must not break
    the caller.
    """
    try:
        settings = load_settings()
        if not push_enabled(settings):
            return
        client = httpx.AsyncClient(http2=True, timeout=10.0)
        try:
            for token in tokens_for_user(user_id):
                status = await send_push(
                    token, title=title, body=body, data=data,
                    interruption_level=interruption_level,
                    settings=settings, client=client,
                )
                if status == 410:
                    delete_token(user_id, token)
        finally:
            await client.aclose()
    except Exception:
        logger.exception("Push fan-out failed for user_id=%s", user_id)


def notify(user_id: int, *, title: str, body: str, data: dict | None = None,
          interruption_level: str | None = None) -> None:
    """Fire-and-forget push from an async context with no BackgroundTasks
    (e.g. the WebSocket signaling loop). Schedules push_to_user and keeps a
    strong ref so it isn't garbage-collected before it completes.
    """
    task = asyncio.create_task(push_to_user(
        user_id, title=title, body=body, data=data,
        interruption_level=interruption_level,
    ))
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)
