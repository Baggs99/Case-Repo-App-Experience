"""
Admin routes — gated by ADMIN_EMAILS allowlist (see require_admin).

Non-admin users get a 404 (not 403) so the admin surface is invisible.
Anonymous visitors are redirected to /login as usual.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request

from webapp.auth.dependencies import require_admin
from webapp.auth.users import User, get_user_by_id
from webapp.repositories.case_access import list_case_access_for_user
from webapp.repositories.case_votes import ADMIN_SORT_SQL, list_cases_with_vote_stats
from webapp.repositories.users import get_user_stats, list_users
from webapp.templating import render


router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/cases")
def admin_cases(
    request: Request,
    sort: str = "title",
    user: User = Depends(require_admin),
):
    sort_key = sort if sort in ADMIN_SORT_SQL else "title"
    rows = list_cases_with_vote_stats(sort=sort_key, limit=3000)
    return render(request, "admin_cases.html", {
        "rows": rows,
        "sort": sort_key,
        "sort_options": list(ADMIN_SORT_SQL.keys()),
    })


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


@router.get("/users/{user_id}")
def admin_user_detail(
    request: Request,
    user_id: int,
    user: User = Depends(require_admin),
):
    target = get_user_by_id(user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="User not found")

    events = list_case_access_for_user(user_id, limit=300)
    now = datetime.now(timezone.utc)

    return render(request, "admin_user_detail.html", {
        "target": target,
        "events": events,
        "now":    now,
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
