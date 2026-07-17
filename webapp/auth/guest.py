"""
Purpose: Guest-interviewer identity — mint scoped guest users, convert them
         to real accounts in place, and the FastAPI dependency guests use.
Inputs:  users table (via get_pool); the current request's request.state.user.
Outputs: guest users rows (is_guest=TRUE, NULL email/password); in-place
         upgrades (is_guest→FALSE + real email/password). No files written.
Run:     from webapp.auth.guest import mint_guest_user, upgrade_guest, require_guest, require_auth_or_mint_guest
"""

from __future__ import annotations

import logging

import psycopg
from fastapi import HTTPException, Request, Response
from psycopg.rows import dict_row

from webapp.auth.dependencies import get_current_user
from webapp.auth.passwords import hash_password, validate_password
from webapp.auth.sessions import attach_session_cookie, create_session, destroy_session
from webapp.auth.users import (
    EmailAlreadyRegistered,
    User,
    _row_to_user,
    validate_email,
)
from webapp.db import get_pool

logger = logging.getLogger(__name__)

_USER_COLS = "id, email, email_verified_at, created_at, last_login_at, is_guest"


class GuestUpgradeConflict(Exception):
    """The row targeted for upgrade is not a guest (already upgraded / not guest)."""


def mint_guest_user(display_name: str = "Guest") -> User:
    """Insert a guest users row (is_guest=TRUE, NULL email/password) and return it.
    display_name renders wherever the session UI shows a participant name — the
    session name query COALESCEs to it since guest email is NULL."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"""
                INSERT INTO users (email, password_hash, is_guest, display_name)
                VALUES (NULL, NULL, TRUE, %s)
                RETURNING {_USER_COLS};
                """,
                (display_name,),
            )
            row = cur.fetchone()
    logger.info("Minted guest user id=%d", row["id"])
    return _row_to_user(row)


def upgrade_guest(user_id: int, email: str, password: str) -> User:
    """Convert a guest row to a real account in place — same id, so every FK
    (session history, feedback, recordings) stays attached.

    Race-safe: the UPDATE is guarded by `is_guest = TRUE`, so a concurrent
    second upgrade updates zero rows and raises GuestUpgradeConflict. Left
    unverified (email_verified_at stays NULL) to match a fresh password
    signup — inbox control is proven later by the normal verification flow.

    Raises: InvalidEmailDomain, WeakPasswordError, EmailAlreadyRegistered,
    GuestUpgradeConflict.
    """
    e = validate_email(email)          # school-domain gate (raises InvalidEmailDomain)
    validate_password(password)        # raises WeakPasswordError
    pwd_hash = hash_password(password)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            try:
                cur.execute(
                    f"""
                    UPDATE users
                    SET email = %s, password_hash = %s, is_guest = FALSE
                    WHERE id = %s AND is_guest = TRUE
                    RETURNING {_USER_COLS};
                    """,
                    (e, pwd_hash, user_id),
                )
            except psycopg.errors.UniqueViolation as exc:
                raise EmailAlreadyRegistered(
                    "An account with that email already exists."
                ) from exc
            row = cur.fetchone()
            if row is None:
                raise GuestUpgradeConflict(
                    "This account is not an unclaimed guest (already upgraded)."
                )
    logger.info("Upgraded guest user id=%d to real account", user_id)
    return _row_to_user(row)


def require_guest(request: Request) -> User:
    """Dependency for the upgrade endpoint: the caller must be a guest.
    401 when unauthenticated, 403 when a real (non-guest) user."""
    user = get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Authentication required")
    if not user.is_guest:
        raise HTTPException(status_code=403, detail="Only guests can upgrade")
    return user


def require_auth_or_mint_guest(request: Request, response: Response) -> User:
    """Auth dependency for the claim endpoints. Returns the current real user
    unchanged; when the request is unauthenticated, mints a guest user + server
    session and sets the session cookie on the response, returning the guest.

    A user who is *already a guest* is rejected (403): a guest is scoped to the
    single session it claimed — claiming again would accrue cross-session
    history before upgrade, which the design forbids.
    """
    user = get_current_user(request)
    if user is not None:
        if user.is_guest:
            raise HTTPException(
                status_code=403,
                detail="Guests are limited to one session. Create an account to continue.",
            )
        return user
    guest = mint_guest_user()
    session = create_session(guest.id, user_agent=request.headers.get("user-agent"))
    attach_session_cookie(response, session)
    # Stash so a failed claim can reap the just-minted guest (below): an
    # unauthenticated bad-token POST must not leave an orphan users/sessions row.
    request.state.b2_minted_guest = guest
    request.state.b2_minted_guest_session = session
    return guest


def discard_minted_guest(request: Request) -> None:
    """Delete a guest + session minted for THIS request when the claim it was
    minted for did not succeed. Closes the unauthenticated row-creation vector:
    a bad / expired / already-claimed token leaves no orphan guest behind. A
    real (pre-authenticated) user request has nothing stashed, so this is a
    no-op for them."""
    guest = getattr(request.state, "b2_minted_guest", None)
    if guest is None:
        return
    session = getattr(request.state, "b2_minted_guest_session", None)
    request.state.b2_minted_guest = None
    request.state.b2_minted_guest_session = None
    if session is not None:
        destroy_session(session.id)
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM users WHERE id = %s AND is_guest = TRUE;", (guest.id,))
