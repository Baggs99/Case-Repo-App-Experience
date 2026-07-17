"""
Purpose: /api/v1/groups* — create/join/leave/transfer groups, group detail with
         a points leaderboard, and admin-only member progress for B6 Community.
Inputs:  session cookie (require_auth_api); name / invite_code / user_id bodies;
         group id path.
Outputs: JSON group payloads; group table writes; community push on join.
Run:     POST /api/v1/groups  {"name":"Cohort C-14"}
"""

from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, field_validator

from pipeline.storage import get_storage
from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.push.events import push_to_user
from webapp.repositories import groups as repo
from webapp.repositories import leaderboards as boards

router = APIRouter(prefix="/api/v1")
_MUTATING = [Depends(require_same_origin)]


class CreateGroupBody(BaseModel):
    name: str

    @field_validator("name")
    @classmethod
    def _name_nonblank(cls, v: str) -> str:
        v = v.strip()
        if not v or len(v) > 100:
            raise ValueError("name must be 1–100 chars")
        return v


class JoinBody(BaseModel):
    invite_code: str


class TransferBody(BaseModel):
    user_id: int


def _photo_url(photo_key):
    return get_storage().url(photo_key) if photo_key else None


def _require_member(group_id: int, user_id: int) -> str:
    role = repo.member_role(group_id, user_id)
    if role is None:
        raise HTTPException(status_code=404, detail="No such group")
    return role


@router.get("/groups")
def my_groups(user: User = Depends(require_auth_api)):
    return {"groups": repo.list_my_groups(user.id)}


@router.post("/groups", dependencies=_MUTATING)
def create_group(body: CreateGroupBody, user: User = Depends(require_auth_api)):
    return repo.create_group(body.name, user.id)


@router.post("/groups/join", dependencies=_MUTATING)
def join_group(body: JoinBody, background: BackgroundTasks,
               user: User = Depends(require_auth_api)):
    result = repo.join_by_code(body.invite_code, user.id)
    if result is None:
        raise HTTPException(status_code=404, detail="Unknown invite code")
    if not result["already_member"]:
        name = user.email.split("@")[0]
        for admin_id in repo.admin_ids(result["id"]):
            if admin_id != user.id:
                background.add_task(
                    push_to_user, admin_id,
                    title="New group member",
                    body=f"{name} joined {result['name']}.",
                    data={"kind": "group_join", "group_id": result["id"],
                          "user_id": user.id},
                    category="community")
    return result


@router.get("/groups/{group_id}")
def group_detail(group_id: int, user: User = Depends(require_auth_api)):
    _require_member(group_id, user.id)
    g = repo.get_group(group_id)
    members = [{"user_id": m["user_id"], "display_name": m["display_name"],
                "photo_url": _photo_url(m["photo_key"]), "role": m["role"]}
               for m in repo.list_members(group_id)]
    board = [{"user_id": r["user_id"], "display_name": r["display_name"],
              "photo_url": _photo_url(r["photo_key"]), "points": r["points"],
              "rank": r["rank"], "streak": r["streak"]}
             for r in boards.group_leaderboard(group_id)]
    return {"group": {"id": g["id"], "name": g["name"], "school_id": g["school_id"],
                      "invite_code": g["invite_code"]},
            "members": members, "leaderboard": board}


@router.post("/groups/{group_id}/leave", dependencies=_MUTATING, status_code=204)
def leave_group(group_id: int, user: User = Depends(require_auth_api)):
    _require_member(group_id, user.id)
    try:
        repo.leave_group(group_id, user.id)
    except PermissionError:
        raise HTTPException(status_code=409,
                            detail="Transfer admin before leaving the group")
    return Response(status_code=204)


@router.post("/groups/{group_id}/transfer", dependencies=_MUTATING)
def transfer_admin(group_id: int, body: TransferBody,
                   user: User = Depends(require_auth_api)):
    role = _require_member(group_id, user.id)
    if role != "admin":
        raise HTTPException(status_code=403, detail="Only an admin can transfer leadership")
    if body.user_id == user.id:
        raise HTTPException(status_code=400, detail="You are already the admin")
    if not repo.transfer_admin(group_id, user.id, body.user_id):
        raise HTTPException(status_code=404, detail="Target is not a group member")
    return {"status": "transferred"}


@router.get("/groups/{group_id}/progress")
def group_progress(group_id: int, user: User = Depends(require_auth_api)):
    role = _require_member(group_id, user.id)
    if role != "admin":
        raise HTTPException(status_code=403, detail="Member progress is admin-only")
    return {"members": boards.group_progress(group_id)}
