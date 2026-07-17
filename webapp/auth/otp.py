"""
Purpose: Email+passcode (OTP) login. 6-digit code, SHA-256 hashed at rest,
         10-min expiry, <=3 verify attempts. New emails are provisioned only
         when their domain is in the schools registry (OD-B5-2).
Inputs:  login_otp_codes table; schools registry; email sender; users repo.
Outputs: INSERTs login_otp_codes rows; may create a school user on verify;
         sends the code via the existing email sender.
Run:     imported by webapp/routes/onboarding.py.
"""

from __future__ import annotations

import logging
import secrets
from datetime import datetime, timedelta
from typing import Optional

from psycopg.rows import dict_row

from webapp.auth.email_sender import get_email_sender
from webapp.auth.tokens import constant_time_equals, hash_token
from webapp.auth.users import (
    get_or_create_school_user,
    get_user_by_email,
    mark_email_verified,
    normalize_email,
)
from webapp.db import get_pool
from webapp.repositories.schools import domain_is_registered

logger = logging.getLogger(__name__)

OTP_LENGTH = 6
OTP_LIFETIME = timedelta(minutes=10)
MAX_ATTEMPTS = 3


def _generate_code() -> str:
    """A zero-padded 6-digit numeric code."""
    return f"{secrets.randbelow(10 ** OTP_LENGTH):0{OTP_LENGTH}d}"


def _domain(email: str) -> str:
    e = normalize_email(email)
    return e.split("@", 1)[1] if e.count("@") == 1 else ""


def request_otp(email: str) -> bool:
    """Issue and email a code, but ONLY for an existing user or a
    registry-whitelisted domain. Returns whether a code was issued.

    The route always answers 202 regardless of this value (no enumeration).
    """
    e = normalize_email(email)
    if "@" not in e:
        return False
    is_existing = get_user_by_email(e) is not None
    if not is_existing and not domain_is_registered(_domain(e)):
        return False  # unknown person on an unregistered domain: send nothing

    code = _generate_code()
    expires_at = datetime.utcnow() + OTP_LIFETIME
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO login_otp_codes (email, code_hash, expires_at) "
                "VALUES (%s, %s, %s);",
                (e, hash_token(code), expires_at),
            )

    subject = "Your myCase sign-in code"
    text_body = (
        f"Your myCase sign-in code is {code}\n\n"
        f"It expires in 10 minutes and can be used once. If you didn't request\n"
        f"it, you can ignore this email.\n"
    )
    try:
        get_email_sender().send(to=e, subject=subject, text_body=text_body,
                                html_body=None)
    except Exception:
        logger.exception("Failed to send OTP email to %s", e)
    return True


def verify_otp(email: str, code: str) -> Optional[int]:
    """Return the user_id on a valid code, else None. Provisions a school user
    for a new registry-whitelisted email. Enforces expiry + attempt cap."""
    e = normalize_email(email)
    code = (code or "").strip()

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, code_hash, expires_at, attempts, consumed_at
                FROM login_otp_codes
                WHERE email = %s AND consumed_at IS NULL
                ORDER BY id DESC LIMIT 1
                FOR UPDATE;
                """,
                (e,),
            )
            row = cur.fetchone()
            if row is None:
                return None
            now = datetime.utcnow().replace(tzinfo=row["expires_at"].tzinfo)
            if row["expires_at"] < now or row["attempts"] >= MAX_ATTEMPTS:
                return None
            if not constant_time_equals(row["code_hash"], hash_token(code)):
                cur.execute(
                    "UPDATE login_otp_codes SET attempts = attempts + 1 WHERE id = %s;",
                    (row["id"],),
                )
                return None
            cur.execute(
                "UPDATE login_otp_codes SET consumed_at = NOW() WHERE id = %s;",
                (row["id"],),
            )

    # Valid code: get-or-create the school user, mark verified.
    user = get_or_create_school_user(e)
    mark_email_verified(user.id)
    return user.id
