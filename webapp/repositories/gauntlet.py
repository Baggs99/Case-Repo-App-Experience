# webapp/repositories/gauntlet.py
"""
Purpose: Persist scored gauntlet submissions into drill_attempts (034 columns)
         and compute daily percentile, daily-score trend, and per-type accuracy.
Inputs:  user_id + a scored slot list; reads drill_attempts joined to users.
Outputs: writes one drill_attempts row per gauntlet slot; read helpers return
         dicts for the service layer. No side effects beyond the DB.
Run:     from webapp.repositories import gauntlet; gauntlet.has_submitted(1, "2026-07-17")
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.drills import _TYPES

#: Advisory-lock namespace (arbitrary constant) for serializing per-user
#: same-day submissions so the one-per-day guard is race-free without a schema
#: change (the 6 rows share (user_id, set_key), so a UNIQUE index can't express it).
_LOCK_NS: int = 0x6738_0B81


class AlreadySubmitted(Exception):
    """Raised when a user already has a gauntlet submission for the given day."""


def has_submitted(user_id: int, set_key: str) -> bool:
    with get_pool().connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT EXISTS (SELECT 1 FROM drill_attempts"
            " WHERE user_id = %(u)s AND set_key = %(k)s);",
            {"u": user_id, "k": set_key})
        return cur.fetchone()[0]


def record_submission(user_id: int, set_key: str, slots: list[dict]) -> None:
    """Insert one drill_attempts row per scored slot in a single transaction,
    guarded by a per-user advisory lock so a concurrent double-submit for the
    same day raises AlreadySubmitted rather than duplicating."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            # Serialize same-user submissions; released at txn end.
            cur.execute("SELECT pg_advisory_xact_lock(%s, %s);", (_LOCK_NS, user_id))
            cur.execute(
                "SELECT 1 FROM drill_attempts WHERE user_id = %(u)s AND set_key = %(k)s LIMIT 1;",
                {"u": user_id, "k": set_key})
            if cur.fetchone() is not None:
                raise AlreadySubmitted(set_key)
            cur.executemany(
                "INSERT INTO drill_attempts"
                " (user_id, drill_type, source, drill_key, correct, score, duration_ms, set_key)"
                " VALUES (%(u)s, %(t)s, 'server', %(k)s, %(c)s, %(sc)s, %(d)s, %(sk)s);",
                [{"u": user_id, "t": s["drill_type"], "k": s["drill_key"],
                  "c": s["correct"], "sc": s["score"], "d": s.get("duration_ms"),
                  "sk": set_key} for s in slots])


def submission_summary(user_id: int, set_key: str) -> dict | None:
    with get_pool().connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            "SELECT COALESCE(SUM(score), 0) AS score,"
            "       COUNT(*) FILTER (WHERE correct) AS slots_correct,"
            "       COUNT(*) AS slots"
            " FROM drill_attempts WHERE user_id = %(u)s AND set_key = %(k)s;",
            {"u": user_id, "k": set_key})
        row = cur.fetchone()
    if not row or row["slots"] == 0:
        return None
    return {"score": float(row["score"]), "slots_correct": int(row["slots_correct"]),
            "slots": int(row["slots"])}


def daily_percentile(user_id: int, set_key: str) -> float | None:
    """The user's percentile (percent_rank ×100, 1 dp) by run score among all
    NON-GUEST users who submitted the same day. None if the user didn't submit."""
    with get_pool().connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            "WITH day AS ("
            "  SELECT da.user_id, SUM(da.score) AS score"
            "  FROM drill_attempts da JOIN users u ON u.id = da.user_id"
            "  WHERE da.set_key = %(k)s AND NOT COALESCE(u.is_guest, FALSE)"
            "  GROUP BY da.user_id),"
            " ranked AS (SELECT user_id, 100.0 * percent_rank() OVER (ORDER BY score) AS pct FROM day)"
            " SELECT ROUND(pct::numeric, 1) AS pct FROM ranked WHERE user_id = %(u)s;",
            {"k": set_key, "u": user_id})
        row = cur.fetchone()
    return float(row["pct"]) if row else None


def daily_scores(user_id: int, days: int = 60) -> list[dict]:
    """[{date, score}] — the user's per-day gauntlet run score over the window,
    ascending. Powers the trend bars."""
    with get_pool().connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            "SELECT set_key AS date, SUM(score) AS score"
            " FROM drill_attempts"
            " WHERE user_id = %(u)s AND set_key IS NOT NULL"
            "   AND completed_at > now() - make_interval(days => %(d)s)"
            " GROUP BY set_key ORDER BY set_key;",
            {"u": user_id, "d": days})
        return [{"date": r["date"], "score": float(r["score"])} for r in cur.fetchall()]


def per_type_accuracy(user_id: int, days: int = 60) -> list[dict]:
    """Per drill type over the user's gauntlet rows in the window:
    [{drill_type, attempts, correct, accuracy}] (accuracy 0..1, 2 dp)."""
    with get_pool().connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            "SELECT drill_type, COUNT(*) AS attempts,"
            "       COUNT(*) FILTER (WHERE correct) AS correct"
            " FROM drill_attempts"
            " WHERE user_id = %(u)s AND set_key IS NOT NULL"
            "   AND completed_at > now() - make_interval(days => %(d)s)"
            " GROUP BY drill_type;",
            {"u": user_id, "d": days})
        rows = cur.fetchall()
    out = []
    for r in rows:
        attempts = int(r["attempts"])
        correct = int(r["correct"])
        out.append({"drill_type": r["drill_type"], "attempts": attempts,
                    "correct": correct,
                    "accuracy": round(correct / attempts, 2) if attempts else 0.0})
    return out


def weakest_type(user_id: int, days: int = 60) -> str | None:
    """The gauntlet drill type the user is weakest at (lowest accuracy, >=1
    attempt). Ties break by the canonical _TYPES order for determinism."""
    stats = [r for r in per_type_accuracy(user_id, days) if r["attempts"] > 0]
    if not stats:
        return None
    order = {t: i for i, t in enumerate(_TYPES)}
    stats.sort(key=lambda r: (r["accuracy"], order.get(r["drill_type"], 99)))
    return stats[0]["drill_type"]
