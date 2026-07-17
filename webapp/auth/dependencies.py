"""
FastAPI dependencies for accessing the current user / requiring auth.

Usage:
    @router.get("/profile")
    def profile(user: User = Depends(require_auth)):
        ...

    @router.get("/")
    def home(request: Request, user: User | None = Depends(get_current_user)):
        ...
"""

from __future__ import annotations

from typing import Optional

from fastapi import HTTPException, Request
from fastapi.responses import RedirectResponse

from webapp.auth.users import User


def get_current_user(request: Request) -> Optional[User]:
    """Return the user attached by SessionMiddleware, or None."""
    return getattr(request.state, "user", None)


class RedirectToLogin(Exception):
    """Raised by require_auth when the request has no valid session.

    Caught by the global exception handler in webapp/main.py, which turns
    it into a 302 redirect with `?next=<original_url>`.
    """
    def __init__(self, next_url: str):
        self.next_url = next_url


def require_auth_api(request: Request) -> User:
    """Like ``require_auth`` but returns **401 JSON** when unauthenticated.

    Use for ``/api/...`` routes consumed by ``fetch`` so clients get a machine-readable
    error instead of an HTML redirect.

    Guests (is_guest) are rejected with **403** here: this is the guard on
    every non-session /api route, so guests are automatically confined to the
    session-scoped endpoints (which use require_session_participant instead).
    """
    user = get_current_user(request)
    if user is None:
        raise HTTPException(status_code=401, detail="Authentication required")
    if user.is_guest:
        raise HTTPException(status_code=403, detail="Guests must create an account to do this")
    return user


def require_auth(request: Request) -> User:
    """Dependency for routes that need a logged-in user.

    Raises RedirectToLogin (303) for HTML page requests, which the global
    handler converts to a redirect. For HTMX / JSON requests it instead
    returns a plain 401 — HTMX should react by reloading the page.
    """
    user = get_current_user(request)
    if user is None:
        next_url = request.url.path
        if request.url.query:
            next_url += f"?{request.url.query}"
        raise RedirectToLogin(next_url=next_url)
    return user


def require_verified_user(request: Request) -> User:
    """Same as require_auth but also rejects unverified users.

    Use on routes that should only be accessible after email confirmation.
    Currently we set `email_verified_at` immediately on link click, so
    most paths already require verification implicitly — but this dep
    is the explicit check.
    """
    user = require_auth(request)
    if not user.is_verified:
        raise RedirectToLogin(next_url="/login?unverified=1")
    return user


def require_admin(request: Request) -> User:
    """Allow only admin-allowlisted users (per ADMIN_EMAILS env var).

    Returns 404 — not 403 — for non-admins. The goal is to make the admin
    surface invisible to logged-in non-admins: a 403 confirms the URL
    exists, a 404 doesn't. Anonymous visitors get the normal login redirect.
    """
    user = require_auth(request)
    settings = request.app.state.settings
    if not settings.is_admin(user.email):
        raise HTTPException(status_code=404, detail="Not Found")
    return user
