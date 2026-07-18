"""
Purpose: F10 Task 1/2 — the guest interviewer link-gate (canvas 8a `gIsGate`)
         and console-lite (`gIsLive`): zero-chrome pages for a claimed link
         through a running, finalized session.
Inputs:  GET/POST /g/claim/{claim_token}; GET /g/session/{session_id}; the
         open-proposal preview from webapp.repositories.proposals; the
         session row from webapp.repositories.practice_sessions.
Outputs: Renders templates/guest_gate.html, templates/guest_console.html; on
         a successful claim, 303s to /g/session/{id}; on finalize (client
         JS), the console 303s to the (not-yet-built) /g/session/{id}/keep.
Run:     included from webapp.main via app.include_router(guest_web_routes.router)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import RedirectResponse

from webapp.auth.guest import (
    discard_minted_guest,
    require_auth_or_mint_guest,
    require_session_participant,
)
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.practice_states import TransitionError
from webapp.repositories import proposals as proposals_repo
from webapp.repositories.case_exhibits import list_manifest
from webapp.routes.practice import _session_or_404
from webapp.templating import render

router = APIRouter(tags=["guest-web"])


@router.get("/g/claim/{claim_token}")
def guest_gate(claim_token: str, request: Request):
    """Public — the unguessable token is the capability, no auth dependency.
    404s a non-open/non-instant/claimed token with a neutral message (no
    existence disclosure beyond what the token holder already knows)."""
    prop = proposals_repo.get_open_by_claim_token(claim_token)
    if prop is None:
        return render(request, "guest_gate.html", {"gone": True}, status_code=404)
    return render(request, "guest_gate.html", {
        "gone": False,
        "from_name": prop["from_name"],
        "case_title": prop["case_title"],
        "claim_token": claim_token,
    })


@router.post("/g/claim/{claim_token}", dependencies=[Depends(require_same_origin)])
def guest_claim(claim_token: str, request: Request, response: Response,
               user: User = Depends(require_auth_or_mint_guest)):
    """'Continue as guest' / real-user claim. Re-checks the same open-instant-
    candidate-role gate the GET used — a token gone since the page loaded
    (raced/claimed/expired) 404s instead of falling through to
    claim_proposal's broader (scheduling-capable) semantics. Because the gate
    SQL restricts from_role='candidate', the claimer is always the
    interviewer here, so claim_proposal's RecapGateError path is unreachable
    on this route (it only fires when the claimer takes the candidate seat)."""
    prop = proposals_repo.get_open_by_claim_token(claim_token)
    if prop is None:
        discard_minted_guest(request)
        return render(request, "guest_gate.html", {"gone": True}, status_code=404)
    try:
        result = proposals_repo.claim_proposal(claim_token, user.id, is_guest=user.is_guest)
    except TransitionError as exc:
        discard_minted_guest(request)
        return render(request, "guest_gate.html", {
            "gone": False,
            "from_name": prop["from_name"],
            "case_title": prop["case_title"],
            "claim_token": claim_token,
            "error": exc.detail,
        }, status_code=409)

    # require_auth_or_mint_guest set the guest's Set-Cookie on the dependency-
    # shared `response`; FastAPI only auto-merges those headers when the
    # endpoint returns a plain value, not when it returns a Response subclass
    # (RedirectResponse here) directly — so copy them across explicitly.
    redirect = RedirectResponse(f"/g/session/{result['session_id']}", status_code=303)
    redirect.headers.raw.extend(response.headers.raw)
    return redirect


@router.get("/g/session/{session_id}")
def guest_console(session_id: int, request: Request,
                  user: User = Depends(require_session_participant)):
    """Console-lite (canvas 8a `gIsLive`). `require_session_participant`
    already 403s a guest on any session it does not participate in;
    `_session_or_404` (shared with webapp/routes/practice.py::session_page)
    404s a real non-participant the same way every other session endpoint
    does (DV-11). The candidate seat and post-call states have their own
    pages, so both redirect away rather than rendering here."""
    session, role = _session_or_404(session_id, user.id)
    if role != "interviewer":
        return RedirectResponse(f"/session/{session_id}", status_code=303)
    if session["state"] in ("finalized", "aborted", "missed"):
        return RedirectResponse(f"/g/session/{session_id}/keep", status_code=303)

    # First exhibit only (the console releases ONE); `id`->`exhibit_id`
    # aliased for the JS's /reveals payload (M2 — list_manifest's own key
    # is `id`, ambiguous once it sits next to the session's exhibit_id use).
    exhibits = [{"exhibit_id": e["id"], "idx": e["idx"]}
                for e in list_manifest(session["case_id"])][:1]
    boot = {
        "sessionId": session["id"],
        "caseId": session["case_id"],
        "caseTitle": session["case_title"],
        # case_type isn't one of get_practice_session's joined columns —
        # generic label rather than a second query for a kicker word (DV-F10-1).
        "caseType": session.get("case_type") or "CASE",
        "peerName": session["candidate_name"],
        "state": session["state"],
        "consentInterviewer": session["consent_interviewer"],
        "consentCandidate": session["consent_candidate"],
        "startedAt": session["started_at"].isoformat() if session["started_at"] else None,
        "exhibits": exhibits,
    }
    return render(request, "guest_console.html", {"session": session, "boot": boot})
