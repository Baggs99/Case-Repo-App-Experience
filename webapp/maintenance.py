"""
Purpose: Run every background sweep (proposal expiry, missed sessions, stale
  aborts) plus the starting-soon push on one 60-s cadence, so app-only clients
  get correct lifecycle without page loads (roadmap §B1).
Inputs: Settings (proposal_now_expiry_min, session_missed_after_min); the
  practice_sessions / proposals tables via the repos.
Outputs: state transitions (expired / missed / aborted), starting-soon pushes.
Run: maintenance_loop() is spawned from webapp.main's lifespan; run one pass
  directly with run_maintenance_pass(load_settings()).
"""

from __future__ import annotations

import asyncio
import logging

from webapp.push.starting_soon import notify_starting_soon
from webapp.repositories.practice_sessions import sweep_missed, sweep_stale_sessions
from webapp.repositories.proposals import sweep_expired
from webapp.settings import load_settings

logger = logging.getLogger(__name__)


async def run_maintenance_pass(settings) -> dict:
    """One sweep cycle. Order matters: sweep_missed marks past-start scheduled
    sessions 'missed' before sweep_stale_sessions could abort them at +6 h."""
    expired = sweep_expired(now_expiry_min=settings.proposal_now_expiry_min)
    missed = sweep_missed(missed_after_min=settings.session_missed_after_min)
    aborted = sweep_stale_sessions()
    starting_soon = await notify_starting_soon()
    return {"expired": expired, "missed": missed,
            "aborted": aborted, "starting_soon": starting_soon}


async def maintenance_loop(interval_seconds: int = 60) -> None:
    """Run run_maintenance_pass() every interval_seconds forever. Sleep-FIRST so
    a short-lived app lifespan (e.g. every TestClient(app) startup) never fires a
    sweep against the shared dev DB — the 60-s startup delay is harmless in prod.
    One bad pass is logged and swallowed; CancelledError propagates (including
    during the sleep) for clean shutdown."""
    while True:
        await asyncio.sleep(interval_seconds)
        try:
            await run_maintenance_pass(load_settings())
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("maintenance pass failed")
