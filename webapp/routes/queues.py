"""
Queue endpoints (spec §4.7, T8.1): want/give membership per user.

Low-stakes personal lists — any authed user, own queues only. The 'give
requires confirming you read the case' rule is a client-side honesty check
by spec; the server does not police it.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.repositories import queues as repo
from webapp.repositories.cases import get_case_by_id

router = APIRouter(tags=["queues"])

_MUTATING = [Depends(require_same_origin)]


def _validated(kind: str, case_id: int) -> None:
    if kind not in ("want", "give"):
        raise HTTPException(status_code=400, detail="Queue kind must be want|give")
    if get_case_by_id(case_id) is None:
        raise HTTPException(status_code=404, detail="Case not found")


@router.get("/api/queues")
def my_queues(user: User = Depends(require_auth_api)):
    return {"want": repo.list_for_user(user.id, "want"),
            "give": repo.list_for_user(user.id, "give")}


@router.post("/api/queues/{kind}/{case_id}", dependencies=_MUTATING)
def add_to_queue(kind: str, case_id: int, user: User = Depends(require_auth_api)):
    _validated(kind, case_id)
    repo.add(user.id, kind, case_id)
    return {"ok": True, **repo.membership(user.id, case_id)}


@router.delete("/api/queues/{kind}/{case_id}", dependencies=_MUTATING)
def remove_from_queue(kind: str, case_id: int, user: User = Depends(require_auth_api)):
    _validated(kind, case_id)
    repo.remove(user.id, kind, case_id)
    return {"ok": True, **repo.membership(user.id, case_id)}
