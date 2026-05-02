"""
Tiny helper around Jinja2Templates that auto-injects `current_user` and
`flash` into every template context. Saves passing them explicitly from
every route handler.
"""

from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import HTMLResponse


def render(request: Request, template_name: str, context: dict[str, Any] | None = None) -> HTMLResponse:
    """Render a template with `current_user` and `current_user_is_admin`
    injected automatically."""
    ctx = dict(context or {})
    user = getattr(request.state, "user", None)
    ctx.setdefault("current_user", user)

    settings = getattr(request.app.state, "settings", None)
    is_admin = bool(settings and user and settings.is_admin(user.email))
    ctx.setdefault("current_user_is_admin", is_admin)

    return request.app.state.templates.TemplateResponse(
        request, template_name, ctx,
    )
