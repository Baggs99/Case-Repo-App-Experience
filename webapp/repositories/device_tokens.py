"""
Device-token repository — APNs push registration (db/migrations/013).

A device can change owners on re-login (same phone, different account), so
registration is an upsert keyed on the token itself.
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool


def upsert_token(user_id: int, token: str, platform: str = "ios") -> None:
    sql = """
        INSERT INTO device_tokens (user_id, token, platform)
        VALUES (%s, %s, %s)
        ON CONFLICT (token) DO UPDATE
            SET user_id = EXCLUDED.user_id, last_seen_at = now();
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (user_id, token, platform))


def tokens_for_user(user_id: int) -> list[str]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT token FROM device_tokens WHERE user_id = %s;",
                (user_id,),
            )
            return [row["token"] for row in cur.fetchall()]


def delete_token(user_id: int, token: str) -> None:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM device_tokens WHERE token = %s AND user_id = %s;",
                (token, user_id),
            )
