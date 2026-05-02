"""
Admin routes — gated by ADMIN_EMAILS allowlist (see require_admin).

Non-admin users get a 404 (not 403) so the admin surface is invisible.
Anonymous visitors are redirected to /login as usual.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Request

from webapp.auth.dependencies import require_admin
from webapp.auth.users import User
from webapp.repositories.users import get_user_stats, list_users
from webapp.templating import render


router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/users")
def admin_users(
    request: Request,
    user: User = Depends(require_admin),
):
    stats = get_user_stats()
    rows = list_users(limit=500)
    now = datetime.now(timezone.utc)

    return render(request, "admin_users.html", {
        "stats": stats,
        "rows":  rows,
        "now":   now,
        "humanize": _humanize_delta,
    })


def _humanize_delta(when: Optional[datetime], now: datetime) -> str:
    """Return a short relative string like '3h ago' or 'never'."""
    if when is None:
        return "never"

    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)

    delta = now - when
    seconds = int(delta.total_seconds())
    if seconds < 60:
        return "just now"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m ago"
    hours = minutes // 60
    if hours < 24:
        return f"{hours}h ago"
    days = hours // 24
    if days < 30:
        return f"{days}d ago"
    months = days // 30
    if months < 12:
        return f"{months}mo ago"
    years = days // 365
    return f"{years}y ago"
