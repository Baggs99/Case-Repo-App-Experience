"""
Tiny helper around Jinja2Templates that auto-injects `current_user` and
`flash` into every template context. Saves passing them explicitly from
every route handler.
"""

from __future__ import annotations

from typing import Any

from fastapi import Request
from fastapi.responses import HTMLResponse

_BROWSE_NO_STORE = {
    "Cache-Control": "no-store, must-revalidate",
    "Pragma": "no-cache",
}


def render(
    request: Request,
    template_name: str,
    context: dict[str, Any] | None = None,
    *,
    status_code: int = 200,
    response_headers: dict[str, str] | None = None,
) -> HTMLResponse:
    """Render a template with `current_user` and `current_user_is_admin`
    injected automatically."""
    ctx = dict(context or {})
    user = getattr(request.state, "user", None)
    ctx.setdefault("current_user", user)

    settings = getattr(request.app.state, "settings", None)
    is_admin = bool(settings and user and settings.is_admin(user.email))
    ctx.setdefault("current_user_is_admin", is_admin)

    if user:
        # Nav proposal badge (spec §4.7) — one indexed COUNT per page render.
        from webapp.repositories.proposals import pending_count
        try:
            ctx.setdefault("pending_proposal_count", pending_count(user.id))
        except Exception:
            ctx.setdefault("pending_proposal_count", 0)

    tr_kw: dict[str, Any] = {"status_code": status_code}
    if response_headers:
        tr_kw["headers"] = response_headers

    return request.app.state.templates.TemplateResponse(
        request, template_name, ctx, **tr_kw,
    )


def render_browse_page(
    request: Request, template_name: str, context: dict[str, Any] | None = None
) -> HTMLResponse:
    """Full browse shell (``/``, document ``/search``) — avoid stale filter HTML."""
    return render(request, template_name, context, response_headers=_BROWSE_NO_STORE)
