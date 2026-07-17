"""
Purpose: /api/v1/timeline* — track/untrack firms, the timeline-detail payload,
  and the post-deadline result flow (Offer / No offer→reweight / Waiting /
  Didn't interview) for the B7 Home + Timeline-detail screens.
Inputs:  session cookie (require_auth_api); firm_id path/body; outcome body.
Outputs: JSON timeline payloads; user_firms writes (track/untrack/result).
Run:     GET /api/v1/timeline  (Cookie: caseroom_session=…)
"""

from __future__ import annotations

import datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from webapp import timeline_service
from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.readiness import reweight_payload
from webapp.repositories import firms as firms_repo
from webapp.repositories import user_firms as user_firms_repo

router = APIRouter(prefix="/api/v1")
_MUTATING = [Depends(require_same_origin)]

_OUTCOMES = {"offer", "no_offer", "waiting", "didnt_interview"}


def _today() -> datetime.date:
    return datetime.datetime.now(datetime.timezone.utc).date()


class TrackFirmBody(BaseModel):
    firm_id: int


class ResultBody(BaseModel):
    outcome: str


@router.get("/timeline")
def get_timeline(user: User = Depends(require_auth_api)):
    return timeline_service.timeline_view(user.id, _today())


@router.get("/timeline/firms")
def list_firms_catalog(user: User = Depends(require_auth_api)):
    return {"firms": timeline_service.firm_catalog(user.id, _today())}


@router.post("/timeline/firms", dependencies=_MUTATING)
def track_firm(body: TrackFirmBody, user: User = Depends(require_auth_api)):
    firm = firms_repo.get_firm(body.firm_id)
    if firm is None:
        raise HTTPException(status_code=404, detail="No such firm")
    row = user_firms_repo.track(user.id, body.firm_id)
    return {"firm_id": firm["id"], "name": firm["name"], "slug": firm["slug"],
            "status": row["status"]}


@router.delete("/timeline/firms/{firm_id}", status_code=204, dependencies=_MUTATING)
def untrack_firm(firm_id: int, user: User = Depends(require_auth_api)):
    # Idempotent: deleting an untracked firm is a 204 no-op (nothing leaked).
    user_firms_repo.untrack(user.id, firm_id)
    return Response(status_code=204)


@router.post("/timeline/firms/{firm_id}/result", dependencies=_MUTATING)
def record_result(firm_id: int, body: ResultBody, user: User = Depends(require_auth_api)):
    """Post-deadline flow. outcome ∈ _OUTCOMES. A user can only resolve a firm
    THEY track — an untracked firm_id is 404 (IDOR guard; identity is the
    session, never a param)."""
    if body.outcome not in _OUTCOMES:
        raise HTTPException(status_code=400,
                            detail=f"outcome must be one of {sorted(_OUTCOMES)}")
    if not user_firms_repo.is_tracked(user.id, firm_id):
        raise HTTPException(status_code=404, detail="Not tracking this firm")

    if body.outcome == "offer":
        row = user_firms_repo.record_result(user.id, firm_id, "offer")
        return {"outcome": "offer", "status": "offer",
                "result_recorded_at": row["result_recorded_at"].isoformat()}
    if body.outcome == "no_offer":
        user_firms_repo.record_result(user.id, firm_id, "rejected")
        return {"outcome": "no_offer", "status": "rejected",
                "reweight": reweight_payload(user.id)}
    if body.outcome == "waiting":
        row = user_firms_repo.mark_waiting(user.id, firm_id, days=7)
        return {"outcome": "waiting", "status": "interviewed",
                "snooze_until": row["snooze_until"].isoformat()}
    # didnt_interview → drops off the line (DV-B7-1).
    user_firms_repo.untrack(user.id, firm_id)
    return {"outcome": "didnt_interview", "dropped": True}
