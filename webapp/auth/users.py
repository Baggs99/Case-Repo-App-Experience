"""
Users — domain object and the SQL that touches the `users` table.
"""

from __future__ import annotations

import logging
import secrets
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

import psycopg
from psycopg.rows import dict_row

from webapp.auth.passwords import (
    WeakPasswordError,
    hash_password,
    needs_rehash,
    validate_password,
    verify_password,
)
from webapp.db import get_pool

logger = logging.getLogger(__name__)


# Allowed domains now live in the `schools` registry (migration 023), enforced
# server-side. To add a school, INSERT a schools row — no code change (OD-B5-2).


@dataclass(frozen=True)
class User:
    id: int
    email: str
    email_verified_at: Optional[datetime]
    created_at: datetime
    last_login_at: Optional[datetime]

    @property
    def is_verified(self) -> bool:
        return self.email_verified_at is not None


# ── Domain errors ──────────────────────────────────────────────────────────────

class InvalidEmailDomain(ValueError):
    """Email isn't on an allowed school domain, isn't the lone Booth guest, or is malformed."""


class EmailAlreadyRegistered(ValueError):
    """Tried to create a user with an email that already exists."""


class InvalidCurrentPassword(ValueError):
    """Current password didn't match in a password-change attempt."""


class SamePasswordError(ValueError):
    """User tried to change their password to the same value as the current one.

    Not strictly a security issue, but rejecting saves the user from a
    confusing "did this work?" moment when nothing visible changes.
    """


# ── Validation ─────────────────────────────────────────────────────────────────

def normalize_email(email: str) -> str:
    """Lowercase + strip. Returns the canonical form."""
    return (email or "").strip().lower()


def domain_of(email: str) -> str:
    """Return the lowercase domain part of a normalized email ('' if malformed)."""
    e = normalize_email(email)
    return e.split("@", 1)[1] if e.count("@") == 1 else ""


def validate_email(email: str) -> str:
    """Return the normalized email iff its domain is in the schools registry.

    The registry IS the school allowlist (OD-B5-2): a domain is allowed exactly
    when a schools row exists for it. Verification of inbox control happens via
    the sign-up link / OTP code.

    Raises InvalidEmailDomain for a malformed address or an unregistered domain.
    """
    from webapp.repositories.schools import domain_is_registered  # avoid import cycle

    e = normalize_email(email)
    if "@" not in e or e.count("@") != 1:
        raise InvalidEmailDomain("Email address looks malformed.")
    local, domain = e.split("@", 1)
    if not local:
        raise InvalidEmailDomain("Email address is missing the local part.")
    if not domain_is_registered(domain):
        raise InvalidEmailDomain(
            "Sign-up is restricted to registered school email addresses."
        )
    return e


def school_id_for_email(email: str) -> Optional[int]:
    """Return the school id for the email's domain, or None if unregistered."""
    from webapp.repositories.schools import get_school_by_domain
    school = get_school_by_domain(domain_of(email))
    return school["id"] if school else None


# ── CRUD ───────────────────────────────────────────────────────────────────────

def _row_to_user(row: dict) -> User:
    return User(
        id=row["id"],
        email=row["email"],
        email_verified_at=row["email_verified_at"],
        created_at=row["created_at"],
        last_login_at=row["last_login_at"],
    )


def create_user(email: str, password: str) -> User:
    """Create a new user with a hashed password. Email must be allowed.

    Raises:
      InvalidEmailDomain — domain / guest rules violated
      WeakPasswordError  — password too short / long
      EmailAlreadyRegistered — email taken
    """
    e = validate_email(email)
    validate_password(password)
    pwd_hash = hash_password(password)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            try:
                cur.execute(
                    """
                    INSERT INTO users (email, password_hash)
                    VALUES (%s, %s)
                    RETURNING id, email, email_verified_at, created_at, last_login_at;
                    """,
                    (e, pwd_hash),
                )
            except psycopg.errors.UniqueViolation as exc:
                raise EmailAlreadyRegistered(
                    "An account with that email already exists."
                ) from exc
            row = cur.fetchone()

    logger.info("Created user id=%d email=%s", row["id"], row["email"])
    return _row_to_user(row)


def create_school_user(email: str, *, display_name: Optional[str] = None) -> User:
    """Create a user for a registry-whitelisted email with NO usable password.

    Used by OTP / OAuth / sign-up completion where the user proves control via a
    code or provider, not a password. The password hash is a random unguessable
    value so authenticate() can never match; the user can set a real password
    later via the reset flow. school_id is stamped from the email's domain.

    Raises InvalidEmailDomain if the domain isn't registered.
    """
    e = validate_email(email)
    school_id = school_id_for_email(e)
    unusable_hash = hash_password(secrets.token_urlsafe(32))

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            try:
                cur.execute(
                    """
                    INSERT INTO users (email, password_hash, display_name, school_id)
                    VALUES (%s, %s, %s, %s)
                    RETURNING id, email, email_verified_at, created_at, last_login_at;
                    """,
                    (e, unusable_hash, display_name, school_id),
                )
            except psycopg.errors.UniqueViolation as exc:
                raise EmailAlreadyRegistered(
                    "An account with that email already exists."
                ) from exc
            row = cur.fetchone()

    logger.info("Created school user id=%d email=%s", row["id"], row["email"])
    return _row_to_user(row)


def get_or_create_school_user(email: str, *, display_name: Optional[str] = None) -> User:
    """Return the existing user for `email`, or create a school user if the
    domain is registered. Raises InvalidEmailDomain if new + unregistered."""
    existing = get_user_by_email(email)
    if existing is not None:
        return existing
    return create_school_user(email, display_name=display_name)


def get_user_by_email(email: str) -> Optional[User]:
    e = normalize_email(email)
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, email, email_verified_at, created_at, last_login_at
                FROM users WHERE email = %s;
                """,
                (e,),
            )
            row = cur.fetchone()
    return _row_to_user(row) if row else None


def get_user_by_id(user_id: int) -> Optional[User]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, email, email_verified_at, created_at, last_login_at
                FROM users WHERE id = %s;
                """,
                (user_id,),
            )
            row = cur.fetchone()
    return _row_to_user(row) if row else None


def authenticate(email: str, password: str) -> Optional[User]:
    """Return the user iff (email, password) match. Returns None on any
    failure — we never reveal which check failed (prevents user enumeration).

    Side effect: re-hashes the password if `needs_rehash` is true (i.e. we
    tuned up the argon2 cost factor since this user signed up).
    """
    e = normalize_email(email)
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, email, email_verified_at, created_at,
                       last_login_at, password_hash
                FROM users WHERE email = %s;
                """,
                (e,),
            )
            row = cur.fetchone()
            if row is None:
                # Run a dummy verify so the timing matches a real check;
                # prevents an attacker from learning which emails exist
                # by observing response time.
                _ = verify_password(password, "$argon2id$v=19$m=65536,t=3,p=4$"
                                    "ZHVtbXlzYWx0$" + "X" * 43)
                return None

            if not verify_password(password, row["password_hash"]):
                return None

            if needs_rehash(row["password_hash"]):
                cur.execute(
                    "UPDATE users SET password_hash = %s WHERE id = %s;",
                    (hash_password(password), row["id"]),
                )
                logger.info("Re-hashed password for user id=%d", row["id"])

            cur.execute(
                "UPDATE users SET last_login_at = NOW() WHERE id = %s "
                "RETURNING last_login_at;",
                (row["id"],),
            )
            row["last_login_at"] = cur.fetchone()["last_login_at"]

    return _row_to_user(row)


def change_password(user_id: int, current_password: str, new_password: str) -> None:
    """Verify the current password, then rotate to a new hashed password.

    Done in a single transaction so the read-then-write can't race against
    a concurrent password change from another device.

    Raises:
      InvalidCurrentPassword — current_password didn't match the stored hash
      SamePasswordError      — new_password equals the current one
      WeakPasswordError      — new_password fails minimum strength rules
    """
    validate_password(new_password)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT password_hash FROM users WHERE id = %s FOR UPDATE;",
                (user_id,),
            )
            row = cur.fetchone()
            if row is None:
                raise InvalidCurrentPassword("User not found.")

            if not verify_password(current_password, row["password_hash"]):
                raise InvalidCurrentPassword("Current password is incorrect.")

            if verify_password(new_password, row["password_hash"]):
                raise SamePasswordError(
                    "New password must be different from your current password."
                )

            new_hash = hash_password(new_password)
            cur.execute(
                "UPDATE users SET password_hash = %s WHERE id = %s;",
                (new_hash, user_id),
            )

    logger.info("Password changed for user id=%d", user_id)


def set_password(user_id: int, new_password: str) -> None:
    """Force-set a user's password without checking the current one.

    Used by the password-reset flow, where the user proved control of
    their inbox via a single-use token instead of by knowing the old
    password. Do NOT expose this directly via a route — it's only safe
    when called after a fresh consume_password_reset_token() succeeds.
    """
    new_hash = hash_password(new_password)
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE users SET password_hash = %s WHERE id = %s;",
                (new_hash, user_id),
            )
    logger.info("Force-set password for user id=%d (post-reset)", user_id)


def mark_email_verified(user_id: int) -> None:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE users SET email_verified_at = NOW() "
                "WHERE id = %s AND email_verified_at IS NULL;",
                (user_id,),
            )
    logger.info("Marked user id=%d as email-verified", user_id)
