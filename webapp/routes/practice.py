"""
JSON API for practice sessions (CaseRoom spec §5, paths per INTEGRATION.md
DV-3: /api/practice/…).

Access model: participants only. Non-participants get 404 — session
existence is not disclosed (DV-11). Wrong-role participants get 403;
illegal transitions and consent gates get 409.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from webapp.auth.dependencies import require_auth, require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.practice_states import TransitionError
from webapp.push.live_activity import push_live_activity_update
from webapp.repositories.cases import get_case_by_id
from webapp.repositories import feedback as feedback_repo
from webapp.repositories import pairing_tokens as pairing_repo
from webapp.repositories import practice_sessions as repo
from webapp.routes.signal_ws import hub
from webapp.templating import render
from webapp.turn import mint_turn_credentials

router = APIRouter(tags=["practice"])

_MUTATING = [Depends(require_same_origin)]


class PracticeCreateBody(BaseModel):
    interviewer_id: int
    candidate_id: int
    case_id: int
    rubric_template_id: Optional[int] = None
    scheduled_at: Optional[datetime] = None


class ConsentBody(BaseModel):
    consent: bool


class PairCreateBody(BaseModel):
    case_id: int


class PairClaimBody(BaseModel):
    token: str


class StateBody(BaseModel):
    target: Literal["scheduled", "lobby", "live", "debrief", "finalized", "aborted"]


def _session_or_404(session_id: int, user_id: int) -> tuple[dict, str]:
    session = repo.get_practice_session(session_id)
    role = repo.role_of(session, user_id) if session else None
    if session is None or role is None:
        raise HTTPException(status_code=404, detail="No such session")
    return session, role


def _public(session: dict) -> dict:
    """Session as JSON — datetimes serialized by FastAPI; nothing here is
    role-secret (exhibit keys, rubric drafts, grades live elsewhere)."""
    return session


@router.post("/api/practice", dependencies=_MUTATING)
def create_practice(body: PracticeCreateBody, user: User = Depends(require_auth_api)):
    if user.id not in (body.interviewer_id, body.candidate_id):
        raise HTTPException(status_code=403, detail="You must be a participant")
    if body.interviewer_id == body.candidate_id:
        raise HTTPException(status_code=400, detail="Interviewer and candidate must differ")
    if get_case_by_id(body.case_id) is None:
        raise HTTPException(status_code=404, detail="Case not found")
    if feedback_repo.is_burned(body.candidate_id, body.case_id):
        # A6: the candidate has already received this case in a finalized
        # session — it's burned for them.
        raise HTTPException(status_code=409,
                            detail="This case is burned for the candidate")

    session = repo.create_practice_session(
        interviewer_id=body.interviewer_id,
        candidate_id=body.candidate_id,
        case_id=body.case_id,
        rubric_template_id=body.rubric_template_id,
        scheduled_at=body.scheduled_at,
    )
    return _public(session)


@router.get("/api/practice/{session_id}")
def get_practice(session_id: int, user: User = Depends(require_auth_api)):
    session, role = _session_or_404(session_id, user.id)
    return {**_public(session), "your_role": role}


@router.get("/session/{session_id}")
def session_page(session_id: int, request: Request,
                 user: User = Depends(require_auth)):
    """The call page (lobby → live → ended). Participants only (DV-11)."""
    session, role = _session_or_404(session_id, user.id)
    peer = session["candidate_name"] if role == "interviewer" else session["interviewer_name"]
    boot = {
        "sessionId": session["id"],
        "role": role,
        "state": session["state"],
        "selfConsent": session["consent_interviewer" if role == "interviewer"
                               else "consent_candidate"],
        "peerName": peer,
        "caseTitle": session["case_title"],
        "caseId": session["case_id"],
    }
    return render(request, "session.html", {
        "session": session,
        "your_role": role,
        "peer_label": f"You and {peer}",
        "boot": boot,
    })


@router.post("/api/practice/{session_id}/consent", dependencies=_MUTATING)
def post_consent(session_id: int, body: ConsentBody, background: BackgroundTasks,
                 user: User = Depends(require_auth_api)):
    _, role = _session_or_404(session_id, user.id)
    try:
        result = repo.set_consent(session_id, role, body.consent)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    background.add_task(hub.broadcast_session_update, session_id)
    return _public(result)


@router.post("/api/practice/{session_id}/state", dependencies=_MUTATING)
def post_state(session_id: int, body: StateBody, background: BackgroundTasks,
               user: User = Depends(require_auth_api)):
    try:
        result = repo.transition(session_id, user.id, body.target)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    background.add_task(hub.broadcast_session_update, session_id)
    # ActivityKit update push (P3 T9): state changes (lobby→live→debrief→
    # finalized) refresh the Live Activity; "end" dismisses it on finalize.
    event = "end" if body.target == "finalized" else "update"
    background.add_task(push_live_activity_update, session_id, event=event)
    return _public(result)


@router.post("/api/practice/pair/create", dependencies=_MUTATING)
def create_pair_token(body: PairCreateBody, user: User = Depends(require_auth_api)):
    """Mint a short-TTL pairing token for in-person QR pairing (§ pairing)."""
    if get_case_by_id(body.case_id) is None:
        raise HTTPException(status_code=404, detail="Case not found")
    return pairing_repo.mint_token(interviewer_id=user.id, case_id=body.case_id)


@router.post("/api/practice/pair/claim", dependencies=_MUTATING)
def claim_pair_token(body: PairClaimBody, user: User = Depends(require_auth_api)):
    """Claim a pairing token, creating the practice session (§ pairing)."""
    try:
        return pairing_repo.claim(token=body.token, candidate_id=user.id)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.get("/api/practice/pair/status/{token}")
def pair_token_status(token: str, user: User = Depends(require_auth_api)):
    """Interviewer polls this to discover the session created by a claim
    (§ pairing). 404 if the token doesn't exist or isn't owned by the caller."""
    try:
        session_id = pairing_repo.status(token=token, interviewer_id=user.id)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    return {"session_id": session_id}


@router.get("/api/practice/{session_id}/join-config")
async def join_config(session_id: int, request: Request,
                      user: User = Depends(require_auth_api)):
    """WS path + ICE servers for the call page. No HMAC token (DV-3): the
    WebSocket handshake authenticates with the same session cookie."""
    session, role = await run_in_threadpool(_session_or_404, session_id, user.id)
    if session["state"] not in ("scheduled", "lobby", "live"):
        raise HTTPException(status_code=409, detail="Session is not joinable")
    settings = request.app.state.settings
    ice_servers = list(settings.ice_servers)
    if session["mode"] == "remote":
        ice_servers += await mint_turn_credentials(settings)
    return {
        "session_id": session_id,
        "your_role": role,
        "mode": session["mode"],
        "ws_path": f"/ws/practice/{session_id}",
        "ice_servers": ice_servers,
    }
