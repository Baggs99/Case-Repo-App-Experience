# webapp/routes/drills.py
"""
Purpose: /api/v1/drills gauntlet aggregation — today's global set, scored
         submission (one per user per day), percentile-first boards, and trends.
Inputs:  session cookie (require_auth_api); JSON submission; scope query.
Outputs: JSON payloads (percentiles-first; ranks+points only in joined-group
         scope); persists via the gauntlet service. The existing per-user drill
         endpoints (/drills/daily|templates|attempts) live in api_v1.py, untouched.
Run:     GET /api/v1/drills/gauntlet  (Cookie: caseroom_session=…)
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from webapp import drills
from webapp import gauntlet as gauntlet_service
from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.repositories import drill_attempts as drills_repo
from webapp.repositories import gauntlet as gauntlet_repo
from webapp.repositories import groups as groups_repo
from webapp.repositories import leaderboards

router = APIRouter(prefix="/api/v1")

_MUTATING = [Depends(require_same_origin)]


class GauntletSlotAnswer(BaseModel):
    slot: int = Field(ge=0, le=drills.GAUNTLET_SLOTS - 1)
    value: float | None = None
    choice_index: int | None = Field(default=None, ge=0)
    duration_ms: int | None = Field(default=None, ge=0, le=3_600_000)


class GauntletSubmission(BaseModel):
    answers: list[GauntletSlotAnswer] = Field(min_length=drills.GAUNTLET_SLOTS,
                                              max_length=drills.GAUNTLET_SLOTS)


def _today_key() -> str:
    return datetime.now(timezone.utc).date().isoformat()


@router.get("/drills/gauntlet")
def get_gauntlet(user: User = Depends(require_auth_api)):
    """Today's global gauntlet (same set for everyone), answers redacted. When
    the user has already submitted, `result` carries their percentile-first
    results so a refresh shows them."""
    day = datetime.now(timezone.utc).date()
    set_key = day.isoformat()
    submitted = gauntlet_repo.has_submitted(user.id, set_key)
    return {
        "date": set_key,
        "set_key": set_key,
        "provisional": True,
        "slots": [drills.public_drill(d) for d in drills.daily_set(day)],
        "streak": drills_repo.streak_days(user.id),
        "submitted": submitted,
        "result": gauntlet_service.results_for(user.id, set_key) if submitted else None,
    }


@router.post("/drills/gauntlet/attempts", dependencies=_MUTATING)
def submit_gauntlet(body: GauntletSubmission, user: User = Depends(require_auth_api)):
    """Score and record today's gauntlet — one submission per user per day."""
    answers = [a.model_dump() for a in body.answers]
    try:
        return gauntlet_service.submit(user.id, answers)
    except gauntlet_service.InvalidSubmission as exc:
        raise HTTPException(status_code=422, detail=str(exc))
    except gauntlet_repo.AlreadySubmitted:
        raise HTTPException(status_code=409,
                            detail={"error": "already_submitted", "set_key": _today_key()})


@router.get("/drills/boards")
def boards(scope: str = Query(...),
           group_id: int | None = Query(default=None),
           user: User = Depends(require_auth_api)):
    """Scoped board honoring the delta: literal ranks+points only for `group`;
    `school`/`global`/`schools` are percentiles / avg-percentile (no counts)."""
    if scope == "group":
        gid = group_id
        if gid is None:
            mine = groups_repo.list_my_groups(user.id)
            if not mine:
                return {"scope": "group", "group": None, "entries": []}
            gid = mine[0]["id"]
        if not groups_repo.is_member(gid, user.id):
            raise HTTPException(status_code=403, detail="Group membership required")
        grp = groups_repo.get_group(gid)
        return {"scope": "group", "group": {"id": gid, "name": grp["name"] if grp else None},
                "entries": leaderboards.group_leaderboard(gid)}
    if scope == "school":
        standing = leaderboards.my_school_standing(user.id)
        return {"scope": "school", **standing}
    if scope == "global":
        return {"scope": "global", "your_percentile": leaderboards.user_global_percentile(user.id)}
    if scope == "schools":
        return {"scope": "schools", "schools": leaderboards.school_standings()}
    raise HTTPException(status_code=422, detail="scope must be group|school|global|schools")


@router.get("/drills/trends")
def trends(user: User = Depends(require_auth_api)):
    """Daily gauntlet scores (last 60 d) + per-type accuracy + weakest type."""
    return gauntlet_service.trends(user.id)
