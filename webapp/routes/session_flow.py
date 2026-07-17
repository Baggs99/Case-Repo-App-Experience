"""
Purpose: B3 session-flow endpoints — case negotiation, feedback recap gate
         close-out, and role swap — all session-scoped over the existing
         participant guard + signaling WS.
Inputs:  practice_sessions/feedback/negotiations/swaps repos; request cookies.
Outputs: JSON; broadcasts session_update on the signaling hub; APNs pushes.
Run:     registered in webapp/main.py via include_router(session_flow.router).
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, Field

from webapp.auth.dependencies import require_auth_api
from webapp.auth.guest import require_session_participant
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.practice_states import TransitionError
from webapp.repositories import dashboard as dashboard_repo
from webapp.repositories import feedback as feedback_repo
from webapp.repositories import negotiations as nego_repo
from webapp.repositories import practice_sessions as sessions_repo
from webapp.repositories.cases import get_case_by_id
from webapp.repositories.feedback import is_burned
from webapp.routes.practice import _session_or_404
from webapp.routes.signal_ws import hub

router = APIRouter(tags=["session-flow"])

_MUTATING = [Depends(require_same_origin)]


class ProposeBody(BaseModel):
    case_id: int


class AcceptCaseBody(BaseModel):
    case_id: int


def _case_brief(row: Optional[dict]) -> Optional[dict]:
    if row is None:
        return None
    return {"case_id": row["proposed_case_id"], "title": row.get("case_title"),
            "case_type": row.get("case_type"), "difficulty": row.get("difficulty")}


def _nego_view(session: dict, role: str) -> dict:
    sid = session["id"]
    pick = nego_repo.interviewer_pick(sid)
    counter = nego_repo.candidate_counter(sid)
    if pick is None:
        whose_turn = "interviewer"
    elif counter is None:
        whose_turn = "candidate"   # candidate may accept or counter once
    else:
        whose_turn = "interviewer"  # interviewer resolves (keep or take counter)
    out = {
        "session_id": sid,
        "session_state": session["state"],
        "your_role": role,
        "whose_turn": whose_turn if session["state"] == "negotiating" else None,
        "round_used": 2 if counter else (1 if pick else 0),
        "current_pick": _case_brief(pick),
        "candidate_counter": _case_brief(counter),
        "candidate_requested_case": nego_repo.originating_requested_case(sid),
    }
    if role == "interviewer":
        out["pick_sources"] = {
            "recommended_for_candidate": dashboard_repo.recommendations(
                session["candidate_id"], limit=3),
            "interviewer_done_set": nego_repo.interviewer_done_set(
                session["interviewer_id"]),
            "library_allowed": True,
        }
    return out


@router.get("/api/practice/{session_id}/negotiation")
def get_negotiation(session_id: int,
                    user: User = Depends(require_session_participant)):
    session, role = _session_or_404(session_id, user.id)
    return _nego_view(session, role)


@router.post("/api/practice/{session_id}/negotiation/propose", dependencies=_MUTATING)
def propose_case(session_id: int, body: ProposeBody, background: BackgroundTasks,
                 user: User = Depends(require_session_participant)):
    session, role = _session_or_404(session_id, user.id)
    if session["state"] != "negotiating":
        raise HTTPException(status_code=409, detail="Session is not in negotiation")
    if get_case_by_id(body.case_id) is None:
        raise HTTPException(status_code=404, detail="Case not found")
    if is_burned(session["candidate_id"], body.case_id):
        raise HTTPException(status_code=409,
                            detail="That case is burned for the candidate")
    pick = nego_repo.interviewer_pick(session_id)
    counter = nego_repo.candidate_counter(session_id)
    if role == "interviewer":
        if pick is not None:
            raise HTTPException(status_code=409,
                                detail="You already picked — accept or await a counter")
        row = nego_repo.record_proposal(session_id, user.id, body.case_id, 1)
    else:  # candidate
        if pick is None:
            raise HTTPException(status_code=403,
                                detail="The interviewer picks first")
        if counter is not None:
            raise HTTPException(status_code=409, detail="You already countered once")
        row = nego_repo.record_proposal(session_id, user.id, body.case_id, 2)
    background.add_task(hub.broadcast_session_update, session_id)
    return _nego_view(*_session_or_404(session_id, user.id))


@router.post("/api/practice/{session_id}/negotiation/accept", dependencies=_MUTATING)
def accept_case(session_id: int, body: AcceptCaseBody, background: BackgroundTasks,
                user: User = Depends(require_session_participant)):
    session, role = _session_or_404(session_id, user.id)
    if session["state"] != "negotiating":
        raise HTTPException(status_code=409, detail="Session is not in negotiation")
    pick = nego_repo.interviewer_pick(session_id)
    counter = nego_repo.candidate_counter(session_id)
    proposed = {r["proposed_case_id"] for r in (pick, counter) if r}
    if body.case_id not in proposed:
        raise HTTPException(status_code=409,
                            detail="Choose a case that was proposed in this negotiation")
    if role == "candidate" and (pick is None or body.case_id != pick["proposed_case_id"]):
        raise HTTPException(status_code=403,
                            detail="You may only accept the interviewer's pick")
    if is_burned(session["candidate_id"], body.case_id):
        raise HTTPException(status_code=409,
                            detail="That case is burned for the candidate")
    template_id = sessions_repo.get_default_rubric_template_id(
        body.case_id, session["interviewer_id"])
    try:
        result = sessions_repo.stamp_negotiated_case(session_id, body.case_id, template_id)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    nego_repo.mark_accepted(session_id, body.case_id)
    background.add_task(hub.broadcast_session_update, session_id)
    return result


# --- Recap gate close-out ------------------------------------------------


class RecapCloseBody(BaseModel):
    case_rating: int = Field(ge=1, le=5)
    feedback_thumbs: Optional[bool] = None


@router.get("/api/v1/recaps")
def list_recaps(user: User = Depends(require_auth_api)):
    """Unread finalized recaps where the caller was candidate, oldest-first."""
    return {"recaps": feedback_repo.list_unread_recaps(user.id)}


def _candidate_or_403(session_id: int, user_id: int) -> dict:
    session, role = _session_or_404(session_id, user_id)
    if role != "candidate":
        raise HTTPException(status_code=403, detail="Only the candidate can do this")
    return session


@router.post("/api/practice/{session_id}/recap/viewed", dependencies=_MUTATING)
def recap_viewed(session_id: int,
                 user: User = Depends(require_session_participant)):
    session = _candidate_or_403(session_id, user.id)
    if session["state"] != "finalized":
        raise HTTPException(status_code=409, detail="Feedback is not finalized yet")
    feedback_repo.mark_recap_viewed(session_id)
    return {"viewed": True}


@router.post("/api/practice/{session_id}/recap/close", dependencies=_MUTATING)
def recap_close(session_id: int, body: RecapCloseBody,
                user: User = Depends(require_session_participant)):
    """Close-out: required 1-5 case_rating clears the gate; feedback_thumbs is
    recorded only when the interviewer was a real (non-guest) user."""
    session = _candidate_or_403(session_id, user.id)
    record_thumbs = not session.get("interviewer_is_guest", False)
    try:
        feedback_repo.close_recap(
            session_id, case_rating=body.case_rating,
            feedback_thumbs=body.feedback_thumbs, record_thumbs=record_thumbs)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    return {"closed": True, "gate_cleared": feedback_repo.candidate_gate(user.id) is None}
