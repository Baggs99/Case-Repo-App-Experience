"""
Server-side sessions.

Why server-side (vs JWT):
  - Logout is instant — just delete the row. JWTs would still validate
    until they expire unless you maintain a revocation list anyway.
  - The cookie carries only an opaque random ID, so leaking the cookie
    alone (without the database) is useless.
  - Easier mental model for someone learning auth for the first time.

Cookie shape:
  Name:     case_repo_session
  Value:    32 random bytes, URL-safe base64 (~43 chars)
  HttpOnly: true        (JS cannot read it)
  SameSite: Lax         (sent on top-level GETs, not third-party POSTs)
  Secure:   true in prod, false in dev (HTTP localhost has no Secure)
  Path:     /
  Max-Age:  30 days
"""

from __future__ import annotations

import logging
import os
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from psycopg.rows import dict_row

from webapp.auth.users import User, get_user_by_id
from webapp.db import get_pool

logger = logging.getLogger(__name__)


SESSION_COOKIE_NAME = "case_repo_session"
SESSION_DURATION = timedelta(days=30)
SESSION_ID_BYTES = 32


def _cookie_secure() -> bool:
    """True iff cookies should be marked Secure (HTTPS-only).

    Toggle via WEBAPP_SECURE_COOKIES=true in production. Default False so
    dev-on-http://localhost works without browsers silently dropping the
    cookie.
    """
    return os.environ.get("WEBAPP_SECURE_COOKIES", "false").lower() in ("1", "true", "yes")


@dataclass(frozen=True)
class Session:
    id: str
    user_id: int
    created_at: datetime
    expires_at: datetime


def _new_session_id() -> str:
    return secrets.token_urlsafe(SESSION_ID_BYTES)


def create_session(
    user_id: int,
    *,
    user_agent: str | None = None,
    ip_address: str | None = None,
) -> Session:
    """Insert a new session row and return it. The ID is the value to set
    in the cookie."""
    sid = _new_session_id()
    expires = datetime.utcnow() + SESSION_DURATION

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                INSERT INTO sessions (id, user_id, expires_at, user_agent, ip_address)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, user_id, created_at, expires_at;
                """,
                (sid, user_id, expires, user_agent, ip_address),
            )
            row = cur.fetchone()

    logger.debug("Created session for user_id=%d", user_id)
    return Session(
        id=row["id"],
        user_id=row["user_id"],
        created_at=row["created_at"],
        expires_at=row["expires_at"],
    )


def get_user_for_session(session_id: str) -> Optional[User]:
    """Look up a session by ID, return the associated User if the session
    is valid (exists, not expired). Returns None otherwise.

    Lazy cleanup: expired sessions are deleted on access. This keeps the
    table small without a separate cron job — and it's free since we
    were already doing the lookup.
    """
    if not session_id:
        return None

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT user_id, expires_at FROM sessions
                WHERE id = %s;
                """,
                (session_id,),
            )
            row = cur.fetchone()

            if row is None:
                return None

            if row["expires_at"] < datetime.utcnow().replace(tzinfo=row["expires_at"].tzinfo):
                cur.execute("DELETE FROM sessions WHERE id = %s;", (session_id,))
                logger.debug("Garbage-collected expired session")
                return None

            return get_user_by_id(row["user_id"])


def destroy_session(session_id: str) -> None:
    """Delete a session — the user is now logged out on that device."""
    if not session_id:
        return
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sessions WHERE id = %s;", (session_id,))


def destroy_all_sessions_for_user(user_id: int) -> int:
    """Delete every session row for a user. Returns count deleted.

    Use this after a password change to force re-authentication on every
    device — a stolen session cookie becomes useless the moment its user's
    password rotates.
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sessions WHERE user_id = %s;", (user_id,))
            count = cur.rowcount
    logger.info("Destroyed %d sessions for user_id=%d", count, user_id)
    return count


# ── FastAPI cookie helpers ─────────────────────────────────────────────────────

def attach_session_cookie(response, session: Session) -> None:
    """Set the session cookie on a Response. Call after creating a session."""
    response.set_cookie(
        key=SESSION_COOKIE_NAME,
        value=session.id,
        max_age=int(SESSION_DURATION.total_seconds()),
        httponly=True,
        secure=_cookie_secure(),
        samesite="lax",
        path="/",
    )


def clear_session_cookie(response) -> None:
    """Tell the browser to drop the session cookie."""
    response.delete_cookie(
        key=SESSION_COOKIE_NAME,
        path="/",
    )
