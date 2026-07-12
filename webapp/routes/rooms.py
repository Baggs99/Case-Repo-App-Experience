"""
Room pages: /room redirects to your own (auto-creating it), /room/{slug}
is the public room view. Phase 2 ships the shell — queues, history, and
intersections land in Phases 8/9 into the placeholder panels.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import RedirectResponse

from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.repositories.practice_sessions import sweep_stale_sessions
from webapp.repositories.rooms import get_or_create_room, get_room_by_slug
from webapp.templating import render

router = APIRouter(tags=["rooms"])


@router.get("/room")
def my_room(request: Request, user: User = Depends(require_auth)):
    room = get_or_create_room(user.id)
    return RedirectResponse(url=f"/room/{room['slug']}", status_code=303)


@router.get("/room/{slug}")
def room_page(slug: str, request: Request, user: User = Depends(require_auth)):
    sweep_stale_sessions()  # A4: page loads stand in for cron
    room = get_room_by_slug(slug)
    if room is None:
        raise HTTPException(status_code=404, detail="Room not found")
    return render(request, "room.html", {
        "room": room,
        "is_own_room": room["owner_user_id"] == user.id,
    })
