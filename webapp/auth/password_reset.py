"""
Password reset — issue, verify, and consume password reset tokens.

Flow:
  1. User clicks "Forgot password" on the login page and submits their email.
  2. We generate (raw, hash). Store hash + expiry. Send raw in an email link.
  3. User clicks link → GET /reset-password?token=<raw>.
       - We validate WITHOUT consuming so URL scanners (Microsoft Safe Links,
         Gmail's preview fetcher, antivirus link-checkers) can pre-fetch the
         link without burning the token before the user actually clicks.
  4. User submits new password → POST /reset-password.
       - We consume the token AND set the new password atomically (a row
         lock prevents two concurrent submits from both succeeding).
  5. All sessions for the user are destroyed (handled by the route).

Security properties:
  - Tokens are 32 random bytes (URL-safe base64 = 43 chars), not guessable.
  - We store the SHA-256 hash, not the raw token, so a DB leak alone
    doesn't grant attackers usable reset links.
  - One-shot: each token can only be consumed once.
  - Time-limited: 1 hour. Shorter than email verification (24h) because
    an unauthorised reset is a higher-impact event than an unverified
    signup.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Optional

from psycopg.rows import dict_row

from webapp.auth.tokens import generate_token, hash_token
from webapp.db import get_pool

logger = logging.getLogger(__name__)


PASSWORD_RESET_TOKEN_LIFETIME = timedelta(hours=1)


def issue_password_reset_token(user_id: int) -> str:
    """Create a fresh reset token for `user_id` and return the RAW token.

    Caller must email the raw token to the user immediately and must
    never store or log the raw value.
    """
    raw, token_hash = generate_token()
    expires_at = datetime.utcnow() + PASSWORD_RESET_TOKEN_LIFETIME

    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
                VALUES (%s, %s, %s);
                """,
                (user_id, token_hash, expires_at),
            )

    logger.info("Issued password-reset token for user_id=%d", user_id)
    return raw


def verify_password_reset_token(raw_token: str) -> Optional[int]:
    """Return user_id iff the token exists, isn't consumed, and isn't expired.

    Does NOT consume the token. The route uses this on GET to render the
    new-password form, so URL scanners that pre-fetch the link don't burn
    the token before the human ever sees the form.
    """
    if not raw_token:
        return None

    token_hash = hash_token(raw_token)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT user_id, expires_at, consumed_at
                FROM password_reset_tokens
                WHERE token_hash = %s;
                """,
                (token_hash,),
            )
            row = cur.fetchone()

    if row is None:
        return None
    if row["consumed_at"] is not None:
        return None

    now_aware = datetime.utcnow().replace(tzinfo=row["expires_at"].tzinfo)
    if row["expires_at"] < now_aware:
        return None

    return row["user_id"]


def consume_password_reset_token(raw_token: str) -> Optional[int]:
    """Atomically consume the token and return the associated user_id.

    Returns None for unknown / already-used / expired tokens. The
    `FOR UPDATE` row lock guarantees that two concurrent POSTs with the
    same token can't both succeed.
    """
    if not raw_token:
        return None

    token_hash = hash_token(raw_token)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, user_id, expires_at, consumed_at
                FROM password_reset_tokens
                WHERE token_hash = %s
                FOR UPDATE;
                """,
                (token_hash,),
            )
            row = cur.fetchone()

            if row is None:
                logger.info("Password-reset attempt with unknown token")
                return None

            if row["consumed_at"] is not None:
                logger.info("Password-reset attempt with already-used token, user_id=%d", row["user_id"])
                return None

            now_aware = datetime.utcnow().replace(tzinfo=row["expires_at"].tzinfo)
            if row["expires_at"] < now_aware:
                logger.info("Password-reset attempt with expired token, user_id=%d", row["user_id"])
                return None

            cur.execute(
                "UPDATE password_reset_tokens SET consumed_at = NOW() WHERE id = %s;",
                (row["id"],),
            )

    logger.info("Consumed password-reset token for user_id=%d", row["user_id"])
    return row["user_id"]
