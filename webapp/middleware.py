"""
Session middleware — runs on every request, reads the session cookie,
stashes the User on `request.state.user` (or None if not logged in).

Routes don't have to opt in. Templates can read `current_user` (injected
by webapp.templating.render) to render header/nav state. Routes that
*require* a user use the require_auth() dependency in webapp.auth.dependencies.
"""

from __future__ import annotations

import logging

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from webapp.auth.sessions import SESSION_COOKIE_NAME, get_user_for_session

logger = logging.getLogger(__name__)


class SessionMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Default to unauthenticated; routes/templates check for None.
        request.state.user = None

        sid = request.cookies.get(SESSION_COOKIE_NAME)
        if sid:
            try:
                user = get_user_for_session(sid)
                if user is not None:
                    request.state.user = user
            except Exception:
                logger.exception("Session lookup failed; treating as logged out")

        return await call_next(request)
