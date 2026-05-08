"""
JSON API for case usefulness votes (logged-in users only).
"""

from __future__ import annotations

from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from psycopg.errors import UndefinedTable

from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.repositories.case_votes import apply_vote, get_vote_state
from webapp.repositories.cases import get_case_by_id


router = APIRouter(tags=["votes"])

_VOTE_MIGRATION_HINT = (
    "Voting requires database migration 007 (case_votes table). "
    "Apply db/migrations/007_case_votes.sql on Postgres."
)


class VotePostBody(BaseModel):
    vote_type: Optional[Literal["useful", "not_useful"]] = Field(
        default=None,
        description='Set to "useful" or "not_useful"; omit or null to clear your vote.',
    )


def _case_or_404(case_id: int) -> None:
    if get_case_by_id(case_id) is None:
        raise HTTPException(status_code=404, detail="Case not found")


@router.get("/api/cases/{case_id}/vote")
def api_get_case_vote(
    case_id: int,
    user: User = Depends(require_auth_api),
):
    """Current user's vote plus aggregate counts."""
    _case_or_404(case_id)
    return get_vote_state(case_id, user.id)


@router.post("/api/cases/{case_id}/vote")
def api_post_case_vote(
    case_id: int,
    body: VotePostBody,
    user: User = Depends(require_auth_api),
):
    """Create, update, toggle off, or clear a vote."""
    _case_or_404(case_id)
    try:
        return apply_vote(case_id, user.id, body.vote_type)
    except UndefinedTable:
        raise HTTPException(status_code=503, detail=_VOTE_MIGRATION_HINT)
