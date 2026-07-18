"""
Purpose: F10 Task 1 — the guest interviewer link-gate (canvas 8a `gIsGate`),
         a zero-chrome public page: "Continue as guest" or "Log in".
Inputs:  GET/POST /g/claim/{claim_token}; the open-proposal preview from
         webapp.repositories.proposals.get_open_by_claim_token.
Outputs: Renders templates/guest_gate.html; on a successful claim, 303s to
         the (not-yet-built) /g/session/{id} console.
Run:     included from webapp.main via app.include_router(guest_web_routes.router)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import RedirectResponse

from webapp.auth.guest import discard_minted_guest, require_auth_or_mint_guest
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.practice_states import TransitionError
from webapp.repositories import proposals as proposals_repo
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
