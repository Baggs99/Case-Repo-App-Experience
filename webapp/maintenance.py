"""
Purpose: Run every background sweep (proposal expiry, missed sessions, stale
  aborts), the starting-soon push, and the daily deadline-passed prompt on one
  60-s cadence, so app-only clients get correct lifecycle without page loads
  (roadmap §B1, §B7).
Inputs: Settings (proposal_now_expiry_min, session_missed_after_min); the
  practice_sessions / proposals / user_firms tables via the repos.
Outputs: state transitions (expired / missed / aborted), starting-soon pushes,
  and deadline-passed prompts ("Did you interview at …?").
Run: maintenance_loop() is spawned from webapp.main's lifespan; run one pass
  directly with run_maintenance_pass(load_settings()).
"""

from __future__ import annotations

import asyncio
import datetime
import logging

from webapp.db import get_pool
from webapp.push.events import push_to_user
from webapp.push.starting_soon import notify_starting_soon
from webapp.repositories import user_firms as user_firms_repo
from webapp.repositories.practice_sessions import sweep_missed, sweep_stale_sessions
from webapp.repositories.proposals import sweep_expired
from webapp.settings import load_settings

logger = logging.getLogger(__name__)

# Daily guard for the deadline-passed sweep (B7): the 60-s loop scans the
# user_firms deadline set at most once per calendar day. Correctness (no double
# push) comes from the per-firm snooze_until throttle; this only avoids 1440
# needless scans/day. Reset to None in tests to re-arm.
_deadline_prompt_last_date: datetime.date | None = None


def _deadline_notifications_allowed(user_id: int) -> bool:
    """B5 seam. If notification_settings exists (B5 merged) honor the user's
    session_reminders flag; otherwise (B5 unmerged, or any error) fail open so
    the prompt still fires. Post-merge B5's push choke-point double-guards —
    harmless (same result). Category mapping documented in the B7 report."""
    try:
        with get_pool().connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT to_regclass('notification_settings');")
                if cur.fetchone()[0] is None:
                    return True
                cur.execute(
                    "SELECT session_reminders FROM notification_settings"
                    " WHERE user_id = %(u)s;", {"u": user_id})
                row = cur.fetchone()
                return True if row is None else bool(row[0])
    except Exception:
        logger.exception("notification-settings seam failed; allowing push")
        return True


async def sweep_deadline_prompts(as_of: datetime.date | None = None) -> int:
    """Push "Did you interview at {firm}?" for each still-tracking firm whose
    deadline has passed and that isn't snoozed, then snooze it a week (weekly
    re-ask). push_to_user self-guards when APNs is unconfigured. Returns the
    number of prompts pushed."""
    now = datetime.datetime.now(datetime.timezone.utc)
    as_of = as_of or now.date()
    snooze_until = now + datetime.timedelta(days=7)
    sent = 0
    for row in user_firms_repo.firms_needing_prompt(as_of):
        if not _deadline_notifications_allowed(row["user_id"]):
            continue
        await push_to_user(
            row["user_id"],
            title="Did you interview?",
            body=f"Did you interview at {row['firm_name']}? Tap to record it.",
            data={"kind": "deadline_prompt", "firm_id": row["firm_id"]},
        )
        user_firms_repo.mark_prompted(row["user_id"], row["firm_id"], snooze_until)
        sent += 1
    return sent


async def _guarded_deadline_prompts(as_of: datetime.date | None = None) -> int:
    """Run sweep_deadline_prompts at most once per calendar day (daily guard)."""
    global _deadline_prompt_last_date
    today = as_of or datetime.datetime.now(datetime.timezone.utc).date()
    if _deadline_prompt_last_date == today:
        return 0
    count = await sweep_deadline_prompts(today)
    _deadline_prompt_last_date = today
    return count


async def run_maintenance_pass(settings, *, as_of: datetime.date | None = None) -> dict:
    """One sweep cycle. Order matters: sweep_missed marks past-start scheduled
    sessions 'missed' before sweep_stale_sessions could abort them at +6 h. The
    deadline prompt is daily-guarded (B7)."""
    expired = sweep_expired(now_expiry_min=settings.proposal_now_expiry_min)
    missed = sweep_missed(missed_after_min=settings.session_missed_after_min)
    aborted = sweep_stale_sessions()
    starting_soon = await notify_starting_soon()
    deadline_prompts = await _guarded_deadline_prompts(as_of)
    return {"expired": expired, "missed": missed, "aborted": aborted,
            "starting_soon": starting_soon, "deadline_prompts": deadline_prompts}


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
