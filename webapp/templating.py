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
    """Render a template with `current_user` injected automatically."""
    ctx = dict(context or {})
    ctx.setdefault("current_user", getattr(request.state, "user", None))

    return request.app.state.templates.TemplateResponse(
        request, template_name, ctx,
    )
