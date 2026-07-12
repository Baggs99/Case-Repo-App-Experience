"""
Reveals repository — the server-side system of record for exhibit reveals
(spec §4.4 step 3b). A reveal row is what entitles the candidate to an
exhibit's key (the fallback endpoint serves a key IFF a row exists here);
the DataChannel message is only the fast path.

t_offset_ms is computed in SQL from practice_sessions.started_at at insert
time, inside the same statement that re-checks state='live' — no window
between a route-level state check and the write.
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.practice_states import TransitionError

_INSERT = """
    INSERT INTO reveals (session_id, exhibit_id, t_offset_ms)
    SELECT ps.id, %(exhibit_id)s,
           GREATEST(0, (EXTRACT(EPOCH FROM (NOW() - ps.started_at)) * 1000))::int
    FROM practice_sessions ps
    WHERE ps.id = %(session_id)s
      AND ps.state = 'live' AND ps.started_at IS NOT NULL
    ON CONFLICT (session_id, exhibit_id) DO NOTHING
    RETURNING exhibit_id, revealed_at, t_offset_ms;
"""

_GET = """
    SELECT exhibit_id, revealed_at, t_offset_ms
    FROM reveals WHERE session_id = %s AND exhibit_id = %s;
"""


def create_reveal(session_id: int, exhibit_id: int) -> dict:
    """Log a reveal. Idempotent: re-revealing an exhibit (double click,
    reconnect replay) returns the original row. Raises TransitionError 409
    if the session is not live (and the exhibit was never revealed)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(_INSERT, {"session_id": session_id, "exhibit_id": exhibit_id})
            row = cur.fetchone()
            if row is not None:
                return {**row, "already_revealed": False}
            cur.execute(_GET, (session_id, exhibit_id))
            existing = cur.fetchone()
            if existing is not None:
                return {**existing, "already_revealed": True}
            raise TransitionError(409, "Exhibits can only be revealed during a live call")


def get_reveal(session_id: int, exhibit_id: int) -> dict | None:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(_GET, (session_id, exhibit_id))
            return cur.fetchone()


def list_reveals(session_id: int) -> list[dict]:
    """Reveal timeline for a session, with each exhibit's display index."""
    sql = """
        SELECT r.exhibit_id, ce.idx, r.revealed_at, r.t_offset_ms
        FROM reveals r
        JOIN case_exhibits ce ON ce.id = r.exhibit_id
        WHERE r.session_id = %s
        ORDER BY r.t_offset_ms, r.id;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (session_id,))
            return cur.fetchall()
