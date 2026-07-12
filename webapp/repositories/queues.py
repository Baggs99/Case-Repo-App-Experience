"""
Queue repository — queue_want / queue_give (spec §4.7, T8.1).

Want = cases the user hopes to RECEIVE as candidate; Give = cases they are
prepped to deliver as interviewer. The kind string is validated against a
whitelist before it ever reaches SQL (table names cannot be parameterized).
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool

_TABLES = {"want": "queue_want", "give": "queue_give"}


def _table(kind: str) -> str:
    table = _TABLES.get(kind)
    if table is None:
        raise ValueError(f"Unknown queue kind {kind!r}")
    return table


def add(user_id: int, kind: str, case_id: int) -> None:
    sql = (f"INSERT INTO {_table(kind)} (user_id, case_id) VALUES (%s, %s)"
           " ON CONFLICT DO NOTHING;")
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (user_id, case_id))


def remove(user_id: int, kind: str, case_id: int) -> None:
    sql = f"DELETE FROM {_table(kind)} WHERE user_id = %s AND case_id = %s;"
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (user_id, case_id))


def list_for_user(user_id: int, kind: str) -> list[dict]:
    sql = f"""
        SELECT c.id, c.case_title, c.case_type, c.difficulty, q.added_at
        FROM {_table(kind)} q
        JOIN cases c ON c.id = q.case_id
        WHERE q.user_id = %s
        ORDER BY q.added_at DESC;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (user_id,))
            return cur.fetchall()


def membership(user_id: int, case_id: int) -> dict:
    """{'want': bool, 'give': bool} for the case-page buttons."""
    sql = """
        SELECT EXISTS(SELECT 1 FROM queue_want WHERE user_id = %(u)s AND case_id = %(c)s) AS want,
               EXISTS(SELECT 1 FROM queue_give WHERE user_id = %(u)s AND case_id = %(c)s) AS give;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, {"u": user_id, "c": case_id})
            return cur.fetchone()


def intersections(viewer_id: int, owner_id: int) -> dict:
    """§4.7 room-visit lists, one join each, excluding cases burned for the
    would-be candidate:
      give_to_them:      viewer.give ∩ owner.want, minus owner's burns
      receive_from_them: viewer.want ∩ owner.give, minus viewer's burns
    """
    sql = """
        SELECT c.id, c.case_title, c.case_type, c.difficulty
        FROM queue_give g
        JOIN queue_want w ON w.case_id = g.case_id
        JOIN cases c ON c.id = g.case_id
        WHERE g.user_id = %(giver)s AND w.user_id = %(wanter)s
          AND NOT EXISTS (SELECT 1 FROM burned b
                          WHERE b.user_id = %(wanter)s AND b.case_id = c.id)
        ORDER BY c.case_title;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, {"giver": viewer_id, "wanter": owner_id})
            give_to_them = cur.fetchall()
            cur.execute(sql, {"giver": owner_id, "wanter": viewer_id})
            receive_from_them = cur.fetchall()
    return {"give_to_them": give_to_them, "receive_from_them": receive_from_them}
