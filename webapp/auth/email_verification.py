"""
Email verification — issue, peek, and consume one-time verification tokens.

Flow:
  1. User signs up.
  2. We generate (raw, hash). Store hash in DB. Send raw in email link.
  3. User clicks link → GET /verify?token=<raw>.
       - We peek (validate WITHOUT consuming) so URL scanners
         (Microsoft Safe Links, Gmail preview, antivirus link-checkers)
         can pre-fetch the link without burning the token before the
         human ever sees the confirm page.
  4. User clicks "Verify my email" on the confirm page → POST /verify.
       - We consume the token AND set email_verified_at atomically
         (a row lock prevents two concurrent submits from both winning).

Security properties:
  - Tokens are 32 random bytes (URL-safe base64 = 43 chars), not guessable.
  - We store the SHA-256 hash, not the raw token, so a DB leak is useless.
  - One-shot: each token can only be consumed once.
  - Time-limited: defaults to 24 hours.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from psycopg.rows import dict_row

from webapp.auth.tokens import generate_token, hash_token
from webapp.auth.users import mark_email_verified
from webapp.db import get_pool

logger = logging.getLogger(__name__)


VERIFICATION_TOKEN_LIFETIME = timedelta(hours=24)


@dataclass(frozen=True)
class VerificationResult:
    success: bool
    user_id: Optional[int]
    error: Optional[str]


def issue_verification_token(user_id: int) -> str:
    """Create a fresh verification token for `user_id` and return the RAW token.

    The caller must email the raw token to the user immediately and must
    never store or log the raw value.
    """
    raw, token_hash = generate_token()
    expires_at = datetime.utcnow() + VERIFICATION_TOKEN_LIFETIME

    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO email_verification_tokens (user_id, token_hash, expires_at)
                VALUES (%s, %s, %s);
                """,
                (user_id, token_hash, expires_at),
            )

    logger.info("Issued verification token for user_id=%d", user_id)
    return raw


def peek_verification_token(raw_token: str) -> Optional[int]:
    """Return user_id iff the token exists, isn't consumed, and isn't expired.

    Does NOT consume the token. The route uses this on GET to render the
    confirm-verification page, so URL scanners that pre-fetch the link
    don't burn the token before the human ever sees the form.
    """
    if not raw_token:
        return None

    token_hash = hash_token(raw_token)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT user_id, expires_at, consumed_at
                FROM email_verification_tokens
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


def consume_verification_token(raw_token: str) -> VerificationResult:
    """Validate `raw_token` and mark the associated user as email-verified.

    Returns VerificationResult; check `.success`. Reasons it might fail:
      - token doesn't exist (typo'd or never issued)
      - token already consumed
      - token expired

    Uses `FOR UPDATE` to prevent two concurrent POSTs (or a double-click)
    from both succeeding.
    """
    if not raw_token:
        return VerificationResult(False, None, "Missing token.")

    token_hash = hash_token(raw_token)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, user_id, expires_at, consumed_at
                FROM email_verification_tokens
                WHERE token_hash = %s
                FOR UPDATE;
                """,
                (token_hash,),
            )
            row = cur.fetchone()

            if row is None:
                logger.info("Verification attempt with unknown token")
                return VerificationResult(False, None, "Invalid verification link.")

            if row["consumed_at"] is not None:
                logger.info("Verification attempt with already-used token, user_id=%d", row["user_id"])
                return VerificationResult(False, None, "This link has already been used.")

            now_aware = datetime.utcnow().replace(tzinfo=row["expires_at"].tzinfo)
            if row["expires_at"] < now_aware:
                logger.info("Verification attempt with expired token, user_id=%d", row["user_id"])
                return VerificationResult(False, None, "This link has expired. Please request a new one.")

            cur.execute(
                "UPDATE email_verification_tokens SET consumed_at = NOW() WHERE id = %s;",
                (row["id"],),
            )

    mark_email_verified(row["user_id"])
    logger.info("Verified email for user_id=%d", row["user_id"])
    return VerificationResult(True, row["user_id"], None)
