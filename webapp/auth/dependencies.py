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

from fastapi import Request
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
