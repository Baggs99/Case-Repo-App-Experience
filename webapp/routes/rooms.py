"""
Room pages: /room redirects to your own (auto-creating it), /room/{slug}
is the public room view. Phase 2 ships the shell — queues, history, and
intersections land in Phases 8/9 into the placeholder panels.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse

from webapp.auth.dependencies import require_auth_api
from webapp.auth.guest import require_auth_no_guest
from webapp.auth.users import User
from webapp.repositories import dashboard as dashboard_repo
from webapp.repositories import proposals as proposals_repo
from webapp.repositories import queues as queues_repo
from webapp.repositories.practice_sessions import (
    list_upcoming_for_user,
    public_stats,
    sweep_stale_sessions,
)
from webapp.repositories.rooms import get_or_create_room, get_room_by_slug
from webapp.templating import render

router = APIRouter(tags=["rooms"])


@router.get("/room")
def my_room(request: Request, user: User = Depends(require_auth_no_guest)):
    room = get_or_create_room(user.id)
    return RedirectResponse(url=f"/room/{room['slug']}", status_code=303)


@router.get("/api/dashboard")
def dashboard(user: User = Depends(require_auth_api)):
    """Spec §5: own history, trends, recommendations — never anyone else's
    (T9.3: the user id comes from the session, not a parameter)."""
    return {
        "history": dashboard_repo.history(user.id),
        "dimension_averages": dashboard_repo.dimension_averages(user.id),
        "recommendations": dashboard_repo.recommendations(user.id),
    }


@router.get("/room/{slug}")
def room_page(slug: str, request: Request, user: User = Depends(require_auth_no_guest)):
    sweep_stale_sessions()          # A4: page loads stand in for cron
    proposals_repo.sweep_expired()  # T8.3: same treatment for proposals
    room = get_room_by_slug(slug)
    if room is None:
        raise HTTPException(status_code=404, detail="Room not found")

    is_own = room["owner_user_id"] == user.id
    ctx = {
        "room": room,
        "is_own_room": is_own,
        "stats": public_stats(room["owner_user_id"]),
    }
    if is_own:
        ctx.update({
            "upcoming": list_upcoming_for_user(user.id),
            "inbox": proposals_repo.inbox(user.id),
            "queue_want": queues_repo.list_for_user(user.id, "want"),
            "queue_give": queues_repo.list_for_user(user.id, "give"),
            "hist": dashboard_repo.history(user.id),
            "trends": dashboard_repo.dimension_averages(user.id),
            "recommended": dashboard_repo.recommendations(user.id),
        })
    else:
        ctx["intersections"] = queues_repo.intersections(user.id,
                                                         room["owner_user_id"])
    return render(request, "room.html", ctx)
