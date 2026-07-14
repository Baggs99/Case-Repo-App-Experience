"""
Pairing-token repository — ad-hoc in-person pairing (db/migrations/014).

An interviewer mints a short-TTL token bound to a chosen case; the scanner
(candidate) later claims it, which creates the practice session.
"""

from __future__ import annotations

import secrets

from psycopg.rows import dict_row

from webapp.db import get_pool


def mint_token(interviewer_id: int, case_id: int, ttl_minutes: int = 10) -> dict:
    token = secrets.token_urlsafe(24)
    sql = """
        INSERT INTO pairing_tokens (token, interviewer_id, case_id, expires_at)
        VALUES (%s, %s, %s, now() + make_interval(mins => %s))
        RETURNING token, expires_at;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (token, interviewer_id, case_id, ttl_minutes))
            return cur.fetchone()
