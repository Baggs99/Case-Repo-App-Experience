"""
Purpose: Per-user firm tracking + post-deadline prompt state (migration 027)
  for the B7 timeline.
Inputs:  user_id, firm_id, status/snooze values; user_firms + firms tables.
Outputs: dict rows; UPDATE/DELETE side effects on user_firms.
Run:     from webapp.repositories import user_firms; user_firms.track(uid, fid)
"""

from __future__ import annotations

import datetime

from psycopg.rows import dict_row

from webapp.db import get_pool

_ROW = "user_id, firm_id, status, added_at, result_recorded_at, snooze_until"


def track(user_id: int, firm_id: int) -> dict:
    """Start tracking a firm. Idempotent — a second track is a no-op that
    returns the existing row (a recorded result is never silently reset)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"INSERT INTO user_firms (user_id, firm_id) VALUES (%(u)s, %(f)s)"
                f" ON CONFLICT (user_id, firm_id) DO NOTHING RETURNING {_ROW};",
                {"u": user_id, "f": firm_id})
            row = cur.fetchone()
            if row is None:                      # already tracked
                cur.execute(
                    f"SELECT {_ROW} FROM user_firms"
                    f" WHERE user_id = %(u)s AND firm_id = %(f)s;",
                    {"u": user_id, "f": firm_id})
                row = cur.fetchone()
            return row


def untrack(user_id: int, firm_id: int) -> int:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM user_firms WHERE user_id = %(u)s AND firm_id = %(f)s;",
                {"u": user_id, "f": firm_id})
            return cur.rowcount


def is_tracked(user_id: int, firm_id: int) -> bool:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM user_firms WHERE user_id = %(u)s AND firm_id = %(f)s;",
                {"u": user_id, "f": firm_id})
            return cur.fetchone() is not None


def get(user_id: int, firm_id: int) -> dict | None:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT {_ROW} FROM user_firms"
                f" WHERE user_id = %(u)s AND firm_id = %(f)s;",
                {"u": user_id, "f": firm_id})
            return cur.fetchone()


def list_tracked(user_id: int) -> list[dict]:
    """Tracked firms with their firm name/slug, soonest deadline computed by
    the caller. Ordered by added_at for a stable list."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT uf.firm_id, f.name, f.slug, uf.status, uf.added_at,"
                "       uf.snooze_until, uf.result_recorded_at"
                " FROM user_firms uf JOIN firms f ON f.id = uf.firm_id"
                " WHERE uf.user_id = %(u)s ORDER BY uf.added_at;",
                {"u": user_id})
            return cur.fetchall()


def record_result(user_id: int, firm_id: int, status: str) -> dict | None:
    """Offer='offer' / No offer='rejected' — stamps result_recorded_at, clears
    any snooze. Returns None if the user doesn't track the firm (IDOR guard)."""
    if status not in ("offer", "rejected"):
        raise ValueError(f"record_result status must be offer|rejected, got {status!r}")
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"UPDATE user_firms SET status = %(s)s, result_recorded_at = NOW(),"
                f" snooze_until = NULL"
                f" WHERE user_id = %(u)s AND firm_id = %(f)s RETURNING {_ROW};",
                {"u": user_id, "f": firm_id, "s": status})
            return cur.fetchone()


def mark_waiting(user_id: int, firm_id: int, days: int = 7) -> dict | None:
    """Waiting → interviewed + re-ask in `days`. Returns None if untracked."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"UPDATE user_firms SET status = 'interviewed',"
                f" snooze_until = NOW() + make_interval(days => %(d)s)"
                f" WHERE user_id = %(u)s AND firm_id = %(f)s RETURNING {_ROW};",
                {"u": user_id, "f": firm_id, "d": days})
            return cur.fetchone()


def firms_needing_prompt(as_of: datetime.date) -> list[dict]:
    """Still-tracking firms whose deadline has passed and that aren't snoozed —
    the deadline-passed push targets. NOW() (not as_of) gates the snooze so a
    real-time snooze window is honored."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT DISTINCT uf.user_id, uf.firm_id, f.name AS firm_name"
                " FROM user_firms uf JOIN firms f ON f.id = uf.firm_id"
                " WHERE uf.status = 'tracking'"
                "   AND (uf.snooze_until IS NULL OR uf.snooze_until < NOW())"
                "   AND EXISTS (SELECT 1 FROM firm_deadlines d"
                "               WHERE d.firm_id = uf.firm_id"
                "                 AND d.deadline_date < %(as_of)s);",
                {"as_of": as_of})
            return cur.fetchall()


def mark_prompted(user_id: int, firm_id: int, snooze_until) -> None:
    """Throttle the auto prompt: set snooze_until (typically NOW()+7d)."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE user_firms SET snooze_until = %(s)s"
                " WHERE user_id = %(u)s AND firm_id = %(f)s;",
                {"u": user_id, "f": firm_id, "s": snooze_until})
