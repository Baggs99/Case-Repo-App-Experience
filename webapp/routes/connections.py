"""
Purpose: /api/v1/connections* — mutual friend requests + connection cards
         (with free-now + swap-invite decorations) for B6 Community.
Inputs:  session cookie (require_auth_api); to_user_id body; user_id path.
Outputs: JSON connection cards; connections table writes; community push.
Run:     GET /api/v1/connections  (Cookie: caseroom_session=…)
"""

from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from pipeline.storage import get_storage
from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.db import get_pool
from webapp.push.events import push_to_user
from webapp.repositories import connections as repo

router = APIRouter(prefix="/api/v1")
_MUTATING = [Depends(require_same_origin)]


class ConnectRequestBody(BaseModel):
    to_user_id: int


def _photo_url(photo_key):
    return get_storage().url(photo_key) if photo_key else None


def _card(row: dict, *, with_decor: bool = False) -> dict:
    out = {"user_id": row["user_id"], "display_name": row["display_name"],
           "photo_url": _photo_url(row["photo_key"]), "bio": row["bio"]}
    if with_decor:
        out["free_now"] = bool(row["free_now"])
        # B3 (session swap) is unmerged — no swap table exists on this branch.
        # This decoration lights up only once B3 lands a swap-invite table.
        out["swap_invite_pending"] = False
    return out


def _user_exists(user_id: int) -> bool:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM users WHERE id = %s;", (user_id,))
            return cur.fetchone() is not None


@router.get("/connections")
def list_connections(user: User = Depends(require_auth_api)):
    return {"connections": [_card(r, with_decor=True) for r in repo.list_accepted(user.id)]}


@router.get("/connections/requests")
def list_requests(user: User = Depends(require_auth_api)):
    return {"incoming": [_card(r) for r in repo.list_incoming(user.id)],
            "outgoing": [_card(r) for r in repo.list_outgoing(user.id)]}


@router.post("/connections/requests", dependencies=_MUTATING)
def create_request(body: ConnectRequestBody, background: BackgroundTasks,
                   user: User = Depends(require_auth_api)):
    if body.to_user_id == user.id:
        raise HTTPException(status_code=400, detail="Cannot connect to yourself")
    if not _user_exists(body.to_user_id):
        raise HTTPException(status_code=404, detail="No such user")
    result = repo.request(user.id, body.to_user_id)
    if result["state"] == "pending" and result.get("created"):
        name = user.email.split("@")[0]
        background.add_task(
            push_to_user, body.to_user_id,
            title="New connection request",
            body=f"{name} wants to connect on myCase.",
            data={"kind": "connection_request", "from_user_id": user.id},
            category="community")
    return result


@router.post("/connections/{user_id}/accept", dependencies=_MUTATING)
def accept_request(user_id: int, user: User = Depends(require_auth_api)):
    if not repo.accept(user_id, user.id):
        raise HTTPException(status_code=404, detail="No pending request from that user")
    return {"state": "accepted"}


@router.post("/connections/{user_id}/decline", dependencies=_MUTATING,
             status_code=204)
def decline_request(user_id: int, user: User = Depends(require_auth_api)):
    if not repo.decline(user_id, user.id):
        raise HTTPException(status_code=404, detail="No pending request from that user")
    return Response(status_code=204)


@router.delete("/connections/{user_id}", dependencies=_MUTATING, status_code=204)
def remove_connection(user_id: int, user: User = Depends(require_auth_api)):
    repo.remove(user.id, user_id)
    return Response(status_code=204)
