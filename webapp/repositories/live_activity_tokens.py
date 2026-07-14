"""
Purpose: Repository for per-session ActivityKit Live Activity push tokens (db/migrations/016).
Inputs: session_id, user_id, push_token.
Outputs: reads/writes the live_activity_tokens table.
Run: called from webapp/routes/api_v1.py and webapp/push/live_activity.py; no CLI entrypoint.
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool


def upsert_token(session_id: int, user_id: int, push_token: str) -> None:
    sql = """
        INSERT INTO live_activity_tokens (session_id, user_id, push_token)
        VALUES (%s, %s, %s)
        ON CONFLICT (session_id, user_id) DO UPDATE
            SET push_token = EXCLUDED.push_token, created_at = now();
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (session_id, user_id, push_token))


def tokens_for_session(session_id: int) -> list[dict]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT user_id, push_token FROM live_activity_tokens"
                " WHERE session_id = %s;",
                (session_id,),
            )
            return cur.fetchall()


def delete_token(push_token: str) -> None:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM live_activity_tokens WHERE push_token = %s;",
                (push_token,),
            )
