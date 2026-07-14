"""
Purpose: Push a "starting soon" alert to both participants of a practice
  session shortly before it begins.
Inputs: practice_sessions rows (state='scheduled', scheduled_at, starting_soon_pushed_at).
Outputs: APNs pushes via webapp.push.events.push_to_user; sets
  practice_sessions.starting_soon_pushed_at so a session is only pushed once.
Run: starting_soon_loop() is spawned as a background task from webapp.main's
  lifespan (when push is enabled); no CLI entrypoint.
"""

from __future__ import annotations

import asyncio
import logging

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.push.events import push_to_user

logger = logging.getLogger(__name__)

_CLAIM_SQL = """
    UPDATE practice_sessions
       SET starting_soon_pushed_at = now()
     WHERE state = 'scheduled'
       AND scheduled_at BETWEEN now() AND now() + make_interval(mins => %s)
       AND starting_soon_pushed_at IS NULL
    RETURNING id, interviewer_id, candidate_id;
"""


async def notify_starting_soon(window_minutes: int = 15) -> int:
    """One pass: claim due sessions and push both participants.

    The UPDATE...RETURNING claim is atomic, so two overlapping passes never
    double-push the same session.
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(_CLAIM_SQL, (window_minutes,))
            rows = cur.fetchall()

    for row in rows:
        for user_id in (row["interviewer_id"], row["candidate_id"]):
            await push_to_user(
                user_id,
                title="Your session starts soon",
                body="Your practice session starts soon.",
                data={"kind": "starting_soon", "session_id": row["id"]},
                interruption_level="time-sensitive",
            )

    return len(rows)


async def starting_soon_loop(interval_seconds: int = 60) -> None:
    """Call notify_starting_soon() every interval_seconds, forever.

    One bad pass must never kill the loop — exceptions are logged and
    swallowed. CancelledError propagates so shutdown can stop it cleanly.
    """
    while True:
        try:
            await notify_starting_soon()
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("starting_soon pass failed")
        await asyncio.sleep(interval_seconds)
