"""
Proposal endpoints + the .ics invite path (spec §4.7, T8.3/T8.4).

Accept creates the linked practice session and emails BOTH parties an
RFC 5545 invite through the repo's mail path. A mail failure never fails
the accept — the session exists either way and the .ics stays downloadable
at /ics/session-{id}.ics (participants only).
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel, Field

from webapp.auth.dependencies import require_auth_api
from webapp.auth.guest import (
    discard_minted_guest,
    require_auth_or_mint_guest,
    require_session_participant,
)
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.ics import build_session_ics
from webapp.practice_states import TransitionError
from webapp.push.events import push_to_user
from webapp.repositories import proposals as repo
from webapp.repositories.cases import get_case_by_id
from webapp.repositories.feedback import RecapGateError
from webapp.repositories.practice_sessions import get_practice_session
from webapp.routes.practice import _session_or_404

logger = logging.getLogger(__name__)

router = APIRouter(tags=["proposals"])

_MUTATING = [Depends(require_same_origin)]


class ProposalBody(BaseModel):
    to_user_id: Optional[int] = None
    case_id: Optional[int] = None
    from_role: str = Field(pattern="^(interviewer|candidate)$")
    message: Optional[str] = Field(default=None, max_length=500)
    proposed_times: list[datetime] = Field(default_factory=list,
                                           max_length=repo.MAX_PROPOSED_TIMES)


class RespondBody(BaseModel):
    scheduled_at: Optional[datetime] = None
    time: Optional[datetime] = None  # chosen counter time (counter-accept)


class CounterBody(BaseModel):
    times: list[datetime] = Field(min_length=1, max_length=repo.MAX_PROPOSED_TIMES)


@router.post("/api/proposals", dependencies=_MUTATING)
def create_proposal(body: ProposalBody, background: BackgroundTasks,
                    user: User = Depends(require_auth_api)):
    if body.case_id is not None and get_case_by_id(body.case_id) is None:
        raise HTTPException(status_code=404, detail="Case not found")
    try:
        proposal = repo.create_proposal(
            from_user_id=user.id, to_user_id=body.to_user_id,
            case_id=body.case_id, from_role=body.from_role,
            message=body.message, proposed_times=body.proposed_times,
        )
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)

    # Named-recipient proposals notify the recipient; open links have no
    # recipient yet (notified when someone claims, Task 4).
    if body.to_user_id is not None:
        sender_name = user.email.split("@")[0]
        background.add_task(
            push_to_user, body.to_user_id,
            title="New session proposal",
            body=f"{sender_name} proposed a case session",
            data={"kind": "proposal", "proposal_id": proposal["id"]},
        )
    return proposal


@router.get("/api/proposals/inbox")
def proposal_inbox(user: User = Depends(require_auth_api)):
    repo.sweep_expired()  # T8.3: page loads stand in for cron
    return {"proposals": repo.inbox(user.id)}


@router.post("/api/proposals/{proposal_id}/accept", dependencies=_MUTATING)
def accept_proposal(proposal_id: int, body: RespondBody, request: Request,
                    background: BackgroundTasks,
                    user: User = Depends(require_auth_api)):
    repo.sweep_expired()  # A3: an over-window proposal (now-ping >2h, or past its earliest start) must expire, not accept
    try:
        prop = repo.respond(proposal_id, user.id, accept=True,
                            scheduled_at=body.scheduled_at, counter_time=body.time)
    except RecapGateError as exc:
        raise HTTPException(status_code=409,
                            detail={"blocked_by_recap": exc.blocked_by_recap})
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)

    if prop.get("needs_negotiation"):
        # Negotiating session created; no case/time yet → no ICS invite. Notify
        # the counterpart the proposal was accepted (pre-negotiation).
        other = (prop["from_user_id"] if user.id == prop["to_user_id"]
                 else prop["to_user_id"])
        if other is not None:
            background.add_task(
                push_to_user, other, title="Proposal accepted",
                body="Your case session proposal was accepted — pick a case",
                data={"kind": "accepted", "proposal_id": prop["id"],
                      "session_id": prop["session_id"]})
        return {"accepted": True, "session_id": prop["session_id"],
                "needs_negotiation": True}

    # Case-set accept (unchanged from B1): ICS invite + accepted push.
    _send_invites(request, prop["session_id"])
    other = (prop["from_user_id"] if user.id == prop["to_user_id"]
             else prop["to_user_id"])
    background.add_task(
        push_to_user, other,
        title="Proposal accepted",
        body="Your case session proposal was accepted",
        data={"kind": "accepted", "session_id": prop["session_id"]},
    )
    return {"accepted": True, "session_id": prop["session_id"],
            "session_url": f"/session/{prop['session_id']}",
            "ics_url": f"/ics/session-{prop['session_id']}.ics"}


@router.post("/api/proposals/claim/{claim_token}", dependencies=_MUTATING)
def claim_proposal(claim_token: str, request: Request, background: BackgroundTasks,
                   user: User = Depends(require_auth_or_mint_guest)):
    """Claim an open 'send a link' proposal (spec §5.2). Any authed user except
    the creator; guests arrive in B2 by overriding require_auth_api."""
    try:
        result = repo.claim_proposal(claim_token, user.id, is_guest=user.is_guest)
    except RecapGateError as exc:
        discard_minted_guest(request)
        raise HTTPException(status_code=409,
                            detail={"blocked_by_recap": exc.blocked_by_recap})
    except TransitionError as exc:
        discard_minted_guest(request)
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)

    if result["session_id"] is not None and not result.get("needs_negotiation"):
        _send_invites(request, result["session_id"])
        background.add_task(
            push_to_user, result["from_user_id"],
            title="Your invite was claimed",
            body="Someone claimed your session link",
            data={"kind": "accepted", "session_id": result["session_id"]},
        )
    return result


@router.post("/api/proposals/{proposal_id}/decline", dependencies=_MUTATING)
def decline_proposal(proposal_id: int, user: User = Depends(require_auth_api)):
    try:
        repo.respond(proposal_id, user.id, accept=False, scheduled_at=None)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    return {"declined": True}


@router.post("/api/proposals/{proposal_id}/counter", dependencies=_MUTATING)
def counter_proposal(proposal_id: int, body: CounterBody, background: BackgroundTasks,
                     user: User = Depends(require_auth_api)):
    """Recipient's one-round "Suggest new time" (spec §5.2). Pushes
    proposal_countered to the proposer — the pattern B3 reuses for swap invites.
    """
    try:
        prop = repo.counter_proposal(proposal_id, user.id, body.times)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    background.add_task(
        push_to_user, prop["from_user_id"],
        title="New times suggested",
        body="Your proposal got a counter — pick a time",
        data={"kind": "proposal_countered", "proposal_id": prop["id"]},
    )
    return {"countered": True, "proposal_id": prop["id"],
            "counter_times": prop["counter_times_json"]}


@router.get("/ics/session-{session_id}.ics")
def session_ics(session_id: int, request: Request,
                user: User = Depends(require_session_participant)):
    """Download link for the invite (spec §4.7) — participants only."""
    session, _ = _session_or_404(session_id, user.id)
    ics = _build_ics_for(request, session)
    return Response(
        ics, media_type="text/calendar; charset=utf-8; method=REQUEST",
        headers={"Content-Disposition":
                 f'attachment; filename="caseroom-session-{session_id}.ics"'},
    )


def _build_ics_for(request: Request, session: dict) -> str:
    base_url = str(request.base_url).rstrip("/")
    host = request.base_url.hostname or "caseroom.local"
    emails = _participant_emails(session)
    return build_session_ics(
        session_id=session["id"],
        case_title=session["case_title"],
        starts_at=session["scheduled_at"],
        organizer_name=session["interviewer_name"],
        organizer_email=emails["interviewer"] or "guest@caseroom.invalid",
        attendee_name=session["candidate_name"],
        attendee_email=emails["candidate"] or "guest@caseroom.invalid",
        session_url=f"{base_url}/session/{session['id']}",
        host=host,
    )


def _participant_emails(session: dict) -> dict:
    from webapp.db import get_pool
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, email FROM users WHERE id = ANY(%s);",
                        ([session["interviewer_id"], session["candidate_id"]],))
            by_id = {row[0]: row[1] for row in cur.fetchall()}
    return {"interviewer": by_id.get(session["interviewer_id"]),
            "candidate": by_id.get(session["candidate_id"])}


def _send_invites(request: Request, session_id: int) -> None:
    """Email both parties; failures are logged, never raised (the session
    already exists and the .ics is downloadable)."""
    try:
        from webapp.auth.email_sender import get_email_sender
        session = get_practice_session(session_id)
        ics = _build_ics_for(request, session)
        emails = _participant_emails(session)
        base_url = str(request.base_url).rstrip("/")
        when = (session["scheduled_at"].strftime("%A %b %-d, %H:%M %Z")
                if session["scheduled_at"] else "now — join when ready")
        sender = get_email_sender()
        for role, addr in emails.items():
            if not addr:
                continue  # guest participant: no inbox to invite
            counterpart = (session["candidate_name"] if role == "interviewer"
                           else session["interviewer_name"])
            sender.send(
                to=addr,
                subject=f"Case practice scheduled: {session['case_title']}",
                text_body=(
                    f"Your case practice with {counterpart} is scheduled ({when}).\n\n"
                    f"Case: {session['case_title']}\n"
                    f"Your role: {role}\n"
                    f"Join: {base_url}/session/{session_id}\n\n"
                    "A calendar invite is attached."
                ),
                attachments=[("invite.ics", "text/calendar", ics.encode())],
            )
    except Exception:
        logger.exception("Failed to send session invite emails (session %s)",
                         session_id)
