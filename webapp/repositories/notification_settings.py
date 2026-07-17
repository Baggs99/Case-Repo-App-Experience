"""
Purpose: Per-user notification category toggles + the fail-open predicate the
         push fan-out consults. Missing row means all categories enabled.
Inputs:  notification_settings table (migration 024); DATABASE_URL pool.
Outputs: UPSERTs a user's notification_settings row.
Run:     imported by webapp/push/events.py and webapp/routes/profile.py.
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool

CATEGORIES = ("proposals", "session_reminders", "feedback", "free_now", "community")
_DEFAULTS = {c: True for c in CATEGORIES}


def get_settings(user_id: int) -> dict:
    """Return all five category flags. Defaults to all-True with no row."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT proposals, session_reminders, feedback, free_now, community "
                "FROM notification_settings WHERE user_id = %s;",
                (user_id,),
            )
            row = cur.fetchone()
    if row is None:
        return dict(_DEFAULTS)
    return {c: bool(row[c]) for c in CATEGORIES}


def update_settings(user_id: int, **flags: bool) -> dict:
    """Upsert the given category flags for user_id. Unknown keys are ignored.

    Returns the full settings dict after the update.
    """
    valid = {k: bool(v) for k, v in flags.items() if k in CATEGORIES}
    if not valid:
        return get_settings(user_id)

    current = get_settings(user_id)
    merged = {**current, **valid}
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO notification_settings
                    (user_id, proposals, session_reminders, feedback, free_now, community)
                VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (user_id) DO UPDATE SET
                    proposals = EXCLUDED.proposals,
                    session_reminders = EXCLUDED.session_reminders,
                    feedback = EXCLUDED.feedback,
                    free_now = EXCLUDED.free_now,
                    community = EXCLUDED.community;
                """,
                (user_id, merged["proposals"], merged["session_reminders"],
                 merged["feedback"], merged["free_now"], merged["community"]),
            )
    return merged


def notifications_allowed(user_id: int, category: str) -> bool:
    """True iff `category` is enabled for the user. Unknown categories -> True
    (fail-open: an uncategorized push is never silently dropped)."""
    if category not in CATEGORIES:
        return True
    return get_settings(user_id)[category]
