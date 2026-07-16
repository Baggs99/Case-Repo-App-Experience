"""
Purpose: Repository for P4 solo drill attempts (db/migrations/017) and the
         daily habit streak they power (DF-1: streak counts drill days OR
         finalized-session days).
Inputs:  user_id plus attempt fields; reads drill_attempts and practice_sessions.
Outputs: reads/writes the drill_attempts table; no side effects beyond the DB.
Run:     called from webapp/routes/api_v1.py (attempts endpoint + dashboard); no CLI.
"""

from __future__ import annotations

from datetime import timedelta

from psycopg.rows import dict_row

from webapp.db import get_pool

# Distinct UTC calendar days on which the user did ≥1 drill OR closed ≥1
# finalized session — the union that DF-1 counts toward the daily streak.
# Capped at 400 rows: far more than any real consecutive run.
_DAYS_SQL = """
SELECT DISTINCT day FROM (
    SELECT (completed_at AT TIME ZONE 'UTC')::date AS day
      FROM drill_attempts WHERE user_id = %(u)s
    UNION
    SELECT (ended_at AT TIME ZONE 'UTC')::date AS day
      FROM practice_sessions
     WHERE state = 'finalized' AND ended_at IS NOT NULL
       AND (interviewer_id = %(u)s OR candidate_id = %(u)s)
) d ORDER BY day DESC LIMIT 400;
"""


def record_attempt(
    user_id: int,
    *,
    drill_type: str,
    source: str,
    drill_key: str | None,
    correct: bool,
) -> dict:
    """Insert one completed-drill row and return it. drill_type/source are
    constrained by CHECKs in the migration; callers validate before this."""
    sql = """
        INSERT INTO drill_attempts (user_id, drill_type, source, drill_key, correct)
        VALUES (%(u)s, %(t)s, %(s)s, %(k)s, %(c)s)
        RETURNING id, user_id, drill_type, source, drill_key, correct, completed_at;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, {"u": user_id, "t": drill_type, "s": source,
                              "k": drill_key, "c": correct})
            return cur.fetchone()


def streak_days(user_id: int) -> int:
    """Consecutive UTC days ending today-or-yesterday on which the user has ≥1
    drill attempt OR ≥1 finalized session (DF-1). A still-empty today doesn't
    break a run that reached yesterday; any older-only activity is a broken
    streak (0)."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(_DAYS_SQL, {"u": user_id})
            days = [row[0] for row in cur.fetchall()]  # date objs, newest first
            cur.execute("SELECT (now() AT TIME ZONE 'UTC')::date;")
            today = cur.fetchone()[0]

    if not days:
        return 0
    # Anchor the run at today, or at yesterday if today has no activity yet.
    if days[0] == today:
        expected = today
    elif days[0] == today - timedelta(days=1):
        expected = today - timedelta(days=1)
    else:
        return 0

    streak = 0
    for day in days:
        if day == expected:
            streak += 1
            expected -= timedelta(days=1)
        else:  # a gap (day < expected; distinct+desc rules out day > expected)
            break
    return streak


def attempted_today(user_id: int) -> bool:
    """Whether the user recorded a drill attempt on the current UTC day."""
    sql = """
        SELECT EXISTS (
            SELECT 1 FROM drill_attempts
            WHERE user_id = %(u)s
              AND (completed_at AT TIME ZONE 'UTC')::date
                  = (now() AT TIME ZONE 'UTC')::date
        );
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, {"u": user_id})
            return cur.fetchone()[0]
