"""
Purpose: /api/v1/leaderboards* — percentile-based school standing, school-vs-
         school board, and the school-leader per-group rollup for B6 Community.
         Percentiles only; NO population counts.
Inputs:  session cookie (require_auth_api); school_id path.
Outputs: JSON standing/board payloads; no writes.
Run:     GET /api/v1/leaderboards/schools  (Cookie: caseroom_session=…)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.repositories import groups as groups_repo
from webapp.repositories import leaderboards as repo

router = APIRouter(prefix="/api/v1")


@router.get("/leaderboards/school")
def my_school_standing(user: User = Depends(require_auth_api)):
    return repo.my_school_standing(user.id)


@router.get("/leaderboards/schools")
def schools_board(user: User = Depends(require_auth_api)):
    return {"schools": repo.school_standings()}


@router.get("/leaderboards/schools/{school_id}/groups")
def school_group_rollup(school_id: int, user: User = Depends(require_auth_api)):
    if not groups_repo.is_school_leader(user.id, school_id):
        raise HTTPException(status_code=403, detail="School-leader access required")
    return {"groups": repo.school_group_rollup(school_id)}
