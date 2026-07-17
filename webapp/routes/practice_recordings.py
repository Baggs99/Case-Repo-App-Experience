"""
Recording upload + download endpoints (spec §4.6, Phase 10; paths per DV-3).

Chunks arrive as multipart (seq, mime, blob) every 60 s during the call and
once more at debrief; INV-5 limits and chunk-0 container sniffing come from
webapp.upload_limits (Phase 1). Downloads are an authed passthrough for the
two participants only — the files themselves are never web-served (T10.4).
A9: nothing here is load-bearing for the call; failures surface as errors
to the uploader and the call goes on.
"""

from __future__ import annotations

import os

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from starlette.concurrency import run_in_threadpool

from webapp.auth.dependencies import require_auth_api
from webapp.auth.guest import require_session_participant
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.practice_states import TransitionError
from webapp.repositories import recordings as repo
from webapp.routes.practice import _session_or_404
from webapp.upload_limits import (
    DEFAULT_REC_CHUNK_MB,
    DEFAULT_REC_TOTAL_MB,
    check_chunk_size,
    check_first_chunk_container,
    check_total_size,
)

router = APIRouter(tags=["practice-recordings"])

_MUTATING = [Depends(require_same_origin)]

_ALLOWED_MIME = ("audio/webm", "audio/mp4")


def _limits() -> tuple[int, int]:
    return (int(os.environ.get("MAX_REC_CHUNK_MB", DEFAULT_REC_CHUNK_MB)),
            int(os.environ.get("MAX_REC_TOTAL_MB", DEFAULT_REC_TOTAL_MB)))


@router.post("/api/practice/{session_id}/recordings/chunk",
             dependencies=_MUTATING)
async def upload_chunk(session_id: int,
                       seq: int = Form(ge=0),
                       mime: str = Form(),
                       blob: UploadFile = File(),
                       user: User = Depends(require_session_participant)):
    session, role = _session_or_404(session_id, user.id)
    if session["state"] not in ("live", "debrief"):
        # The final flush lands right after End (state already debrief).
        raise HTTPException(status_code=409,
                            detail="Recording chunks only during or right after the call")
    if mime not in _ALLOWED_MIME:
        raise HTTPException(status_code=415, detail="mime must be audio/webm or audio/mp4")

    data = await blob.read()
    chunk_mb, total_mb = _limits()
    check_chunk_size(len(data), chunk_mb)
    if seq == 0:
        check_first_chunk_container(data, mime)
    existing = repo.get_recording(session_id, user.id)
    check_total_size(existing["bytes"] if existing else 0, len(data), total_mb)

    try:
        row = await run_in_threadpool(
            repo.append_chunk, session_id=session_id, user_id=user.id,
            role=role, seq=seq, mime=mime, data=data)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    return {"ok": True, "chunks": row["chunks"], "bytes": row["bytes"]}


@router.post("/api/practice/{session_id}/recordings/complete",
             dependencies=_MUTATING)
def complete_recording(session_id: int, user: User = Depends(require_session_participant)):
    _session_or_404(session_id, user.id)
    try:
        row = repo.complete(session_id, user.id)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    return {"completed": True, "chunks": row["chunks"], "bytes": row["bytes"]}


@router.get("/api/practice/{session_id}/recordings")
def list_recordings(session_id: int, user: User = Depends(require_session_participant)):
    _session_or_404(session_id, user.id)
    return {"recordings": repo.list_for_session(session_id)}


@router.get("/api/practice/{session_id}/recordings/{target_user_id}")
def download_recording(session_id: int, target_user_id: int,
                       user: User = Depends(require_session_participant)):
    """Authed passthrough — either participant may fetch either side
    (spec §5: 'the two participants')."""
    session, _ = _session_or_404(session_id, user.id)
    if target_user_id not in (session["interviewer_id"], session["candidate_id"]):
        raise HTTPException(status_code=404, detail="No such recording")
    row = repo.get_recording(session_id, target_user_id)
    if row is None:
        raise HTTPException(status_code=404, detail="No such recording")
    path = repo.read_file(row["path"])
    if not path.exists():
        raise HTTPException(status_code=404, detail="Recording file missing")
    ext = "webm" if row["mime"] == "audio/webm" else "m4a"
    return FileResponse(
        path, media_type=row["mime"],
        filename=f"caseroom-session-{session_id}-{row['role']}.{ext}",
    )
