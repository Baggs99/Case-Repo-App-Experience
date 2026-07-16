"""
Purpose: Repository for P4 "free now" availability (db/migrations/018) — the
         substrate iOS instant-match builds on. Lazy expiry: every read filters
         free_until > now(); there is NO sweep and NO background task.
Inputs:  user_id, minutes (5–240, clamped by the caller); joins users for names.
Outputs: reads/writes the availability table; no side effects beyond the DB.
Run:     called from webapp/routes/api_v1.py (the /api/v1/availability endpoints); no CLI.
"""

from __future__ import annotations

from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool


def set_free(user_id: int, minutes: int) -> dict:
    """Upsert the user's window to now()+minutes; return
    {"free_until": dt, "was_free": bool}.

    was_free is whether a live window (free_until > now()) already existed,
    read FOR UPDATE in the SAME transaction as the upsert so the fresh-toggle
    push gate can't be raced by two concurrent PUTs.
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT free_until > now() AS free FROM availability"
                " WHERE user_id = %(u)s FOR UPDATE;",
                {"u": user_id},
            )
            row = cur.fetchone()
            was_free = bool(row and row["free"])
            cur.execute(
                "INSERT INTO availability (user_id, free_until, updated_at)"
                " VALUES (%(u)s, now() + make_interval(mins => %(m)s), now())"
                " ON CONFLICT (user_id) DO UPDATE"
                "   SET free_until = EXCLUDED.free_until, updated_at = now()"
                " RETURNING free_until;",
                {"u": user_id, "m": minutes},
            )
            return {"free_until": cur.fetchone()["free_until"], "was_free": was_free}


def clear_free(user_id: int) -> None:
    """Remove the user's availability row (toggle off)."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM availability WHERE user_id = %(u)s;",
                        {"u": user_id})


def list_free(exclude_user_id: Optional[int] = None) -> list[dict]:
    """Currently-free users as {user_id, name, free_until}, newest window
    first. The `free_until > now()` filter IS the expiry — nothing sweeps."""
    sql = (
        "SELECT a.user_id, u.display_name AS name, a.free_until"
        " FROM availability a JOIN users u ON u.id = a.user_id"
        " WHERE a.free_until > now()"
    )
    params: dict = {}
    if exclude_user_id is not None:
        sql += " AND a.user_id <> %(x)s"
        params["x"] = exclude_user_id
    sql += " ORDER BY a.free_until DESC;"
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, params)
            return cur.fetchall()
