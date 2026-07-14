"""
Session-time exhibit serving + the reveal system (CaseRoom spec §4.4,
Phase 6). Candidate preloads ciphertext only; keys travel interviewer→
candidate over the ctrl DataChannel (fast path) or via the reveal-gated
fallback endpoint. POST /reveals is the system of record.

Access model matches webapp/routes/practice.py (DV-11): 404 for
non-participants, 403 for wrong-role participants, 409 for state gates.
"""

from __future__ import annotations

import base64

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.practice_states import TransitionError
from webapp.repositories import case_exhibits
from webapp.repositories import reveals as reveals_repo
from webapp.routes.practice import _session_or_404
from webapp.routes.signal_ws import hub

router = APIRouter(tags=["practice-exhibits"])


class RevealBody(BaseModel):
    exhibit_id: int


def _b64(raw: bytes) -> str:
    return base64.b64encode(bytes(raw)).decode()


def _exhibit_or_404(session: dict, exhibit_id: int) -> dict:
    exhibit = case_exhibits.get_exhibit(session["case_id"], exhibit_id)
    if exhibit is None:
        raise HTTPException(status_code=404, detail="No such exhibit")
    return exhibit


@router.get("/api/practice/{session_id}/exhibits")
def exhibit_manifest(session_id: int, user: User = Depends(require_auth_api)):
    """Manifest for preload — no keys (spec §4.4 step 1)."""
    session, _ = _session_or_404(session_id, user.id)
    return {"exhibits": [
        {
            "exhibit_id": e["id"],
            "idx": e["idx"],
            "source_pages": e["source_pages"],
            "width": e["width"],
            "height": e["height"],
            "bytes": e["bytes"],
            "iv_b64": _b64(e["enc_iv"]),
        }
        for e in case_exhibits.list_manifest(session["case_id"])
    ]}


@router.get("/api/practice/{session_id}/exhibit-blob/{exhibit_id}")
async def exhibit_blob(session_id: int, exhibit_id: int,
                       user: User = Depends(require_auth_api)):
    """Encrypted blob for preload. Ciphertext only — safe to serve to either
    participant in any state (INV-6 holds at the key layer)."""
    session, _ = _session_or_404(session_id, user.id)
    exhibit = _exhibit_or_404(session, exhibit_id)
    blob = await run_in_threadpool(case_exhibits.read_blob, exhibit["enc_blob_path"])
    return Response(blob, media_type="application/octet-stream",
                    headers={"Cache-Control": "private, max-age=3600"})


@router.get("/api/practice/{session_id}/exhibit-keys")
def exhibit_keys(session_id: int, user: User = Depends(require_auth_api)):
    """All keys at call start — interviewer only (spec §4.4 step 2)."""
    session, role = _session_or_404(session_id, user.id)
    if role != "interviewer":
        raise HTTPException(status_code=403, detail="Interviewer only")
    return {"keys": [
        {"exhibit_id": k["id"], "key_b64": _b64(k["enc_key"]), "iv_b64": _b64(k["enc_iv"])}
        for k in case_exhibits.list_keys(session["case_id"])
    ]}


@router.post("/api/practice/{session_id}/reveals",
             dependencies=[Depends(require_same_origin)])
def post_reveal(session_id: int, body: RevealBody, background: BackgroundTasks,
                user: User = Depends(require_auth_api)):
    """Log a reveal (system of record; the DataChannel key message is only
    the fast path). Idempotent per (session, exhibit). Also broadcasts the
    key over the signaling WS so exhibits work with no WebRTC peer
    connection (in-person / video-off sessions)."""
    session, role = _session_or_404(session_id, user.id)
    if role != "interviewer":
        raise HTTPException(status_code=403, detail="Interviewer only")
    _exhibit_or_404(session, body.exhibit_id)
    try:
        result = reveals_repo.create_reveal(session_id, body.exhibit_id)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    key = case_exhibits.key_for_exhibit(body.exhibit_id)
    background.add_task(
        hub.broadcast_reveal, session_id, body.exhibit_id, base64.b64encode(key).decode())
    return result


@router.get("/api/practice/{session_id}/reveals")
def list_reveals(session_id: int, user: User = Depends(require_auth_api)):
    """Reveal timeline — reconcile path (DV-4) and debrief view (T6.4)."""
    _session_or_404(session_id, user.id)
    return {"reveals": reveals_repo.list_reveals(session_id)}


@router.get("/api/practice/{session_id}/exhibit-key/{exhibit_id}")
def exhibit_key(session_id: int, exhibit_id: int,
                user: User = Depends(require_auth_api)):
    """Fallback key path (spec §4.4 step 5): key IFF a reveal row exists.
    Candidate only — the interviewer has /exhibit-keys."""
    session, role = _session_or_404(session_id, user.id)
    if role != "candidate":
        raise HTTPException(status_code=403, detail="Candidate only")
    exhibit = _exhibit_or_404(session, exhibit_id)
    if reveals_repo.get_reveal(session_id, exhibit_id) is None:
        raise HTTPException(status_code=404, detail="Not revealed")
    return {
        "exhibit_id": exhibit_id,
        "key_b64": _b64(exhibit["enc_key"]),
        "iv_b64": _b64(exhibit["enc_iv"]),
    }
