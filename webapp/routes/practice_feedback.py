"""
Rubric drafts, finalize, and released feedback (CaseRoom spec Phase 7,
paths per DV-3: /api/practice/…).

Access model matches practice.py (DV-11): 404 non-participants, 403 wrong
role, 409 state gates. The rubric is interviewer-only until finalize;
after finalize the feedback endpoint serves both participants.
"""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, Field

from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.practice_states import TransitionError
from webapp.push.events import push_to_user
from webapp.push.live_activity import push_live_activity_update
from webapp.repositories import feedback as repo
from webapp.repositories import reveals as reveals_repo
from webapp.routes.practice import _session_or_404
from webapp.routes.signal_ws import hub

router = APIRouter(tags=["practice-feedback"])

_MUTATING = [Depends(require_same_origin)]


class RubricDraftBody(BaseModel):
    items: dict[str, Any] = Field(default_factory=dict)
    notes_md: str = ""


class FinalizeBody(BaseModel):
    grade: Optional[float] = Field(default=None, ge=0, le=5)


def _interviewer_or_403(session_id: int, user_id: int) -> dict:
    session, role = _session_or_404(session_id, user_id)
    if role != "interviewer":
        raise HTTPException(status_code=403, detail="Interviewer only")
    return session


@router.get("/api/practice/{session_id}/rubric")
def get_rubric(session_id: int, user: User = Depends(require_auth_api)):
    """Template + current draft + computed grade preview (T7.1)."""
    session = _interviewer_or_403(session_id, user.id)
    template_items = repo.get_template_items(session["rubric_template_id"])
    feedback = repo.get_feedback(session_id)
    draft = feedback["rubric_json"] if feedback else {"items": {}}
    return {
        "template_items": template_items,
        "items": draft.get("items", {}),
        "notes_md": (feedback or {}).get("notes_md") or "",
        "grade_preview": repo.compute_grade(draft, template_items),
        "grade": float(feedback["grade"]) if feedback and feedback["grade"] is not None else None,
        "finalized_at": feedback["finalized_at"] if feedback else None,
    }


@router.put("/api/practice/{session_id}/rubric", dependencies=_MUTATING)
def put_rubric(session_id: int, body: RubricDraftBody,
               user: User = Depends(require_auth_api)):
    """Debounced autosave of the draft. Allowed any time before finalize —
    prepping the rubric pre-call is legitimate; 'aborted' keeps it too
    (nothing is ever released for aborted sessions)."""
    session = _interviewer_or_403(session_id, user.id)
    if session["state"] == "finalized":
        raise HTTPException(status_code=409, detail="Feedback is finalized and read-only")
    template_items = repo.get_template_items(session["rubric_template_id"])
    draft = {"items": body.items, "notes_md": body.notes_md}
    try:
        repo.validate_draft(draft, template_items)
        saved = repo.save_draft(session_id, draft)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    return {
        "saved": True,
        "grade_preview": repo.compute_grade(saved["rubric_json"], template_items),
    }


@router.post("/api/practice/{session_id}/finalize", dependencies=_MUTATING)
def post_finalize(session_id: int, body: FinalizeBody, background: BackgroundTasks,
                  user: User = Depends(require_auth_api)):
    """T7.2: grade + finalized_at + burned + want-queue removal + state flip,
    one transaction. Optional body.grade overrides the computed score."""
    session, _ = _session_or_404(session_id, user.id)  # 404-existence before role/state checks
    try:
        feedback = repo.finalize(session_id, user.id, body.grade)
    except TransitionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)

    background.add_task(
        push_to_user, session["candidate_id"],
        title="Feedback released",
        body=f"Your feedback for {session['case_title']} is ready",
        data={"kind": "feedback", "session_id": session_id},
    )
    background.add_task(hub.broadcast_session_update, session_id)
    background.add_task(push_live_activity_update, session_id, event="end")
    return {
        "finalized": True,
        "grade": float(feedback["grade"]),
        "finalized_at": feedback["finalized_at"],
    }


@router.get("/api/practice/{session_id}/feedback")
def get_feedback(session_id: int, user: User = Depends(require_auth_api)):
    """T7.3: released feedback — both participants, post-finalize only."""
    session, _ = _session_or_404(session_id, user.id)
    if session["state"] != "finalized":
        raise HTTPException(status_code=409, detail="Feedback is not finalized yet")
    feedback = repo.get_feedback(session_id)
    template_items = repo.get_template_items(session["rubric_template_id"])
    drafted = feedback["rubric_json"].get("items", {}) if feedback else {}
    return {
        "grade": float(feedback["grade"]) if feedback and feedback["grade"] is not None else None,
        "finalized_at": feedback["finalized_at"] if feedback else None,
        "notes_md": (feedback or {}).get("notes_md") or "",
        "items": [
            {
                "id": item["id"],
                "label": item["label"],
                "dimension": item.get("dimension"),
                "max_points": item["max_points"],
                "points": drafted.get(item["id"], {}).get("points", 0),
                "note": drafted.get(item["id"], {}).get("note", ""),
            }
            for item in template_items
        ],
        "reveals": reveals_repo.list_reveals(session_id),
        "case_id": session["case_id"],
        "case_title": session["case_title"],
    }
