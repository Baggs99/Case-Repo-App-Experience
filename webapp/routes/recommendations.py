"""
Purpose: /api/v1/recommendations — the native "Next up for you" mouth of the
         single §4.8 recommendation engine (spec §7); list + why + exclude.
Inputs:  session cookie (require_auth_api); optional ?exclude=1,2,3 query.
Outputs: {"recommendations": [{case_id, title, case_type, difficulty, why, rule}]}.
Run:     GET /api/v1/recommendations?exclude=12,34  (Cookie: caseroom_session=…)
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from webapp.auth.dependencies import require_auth_api
from webapp.auth.users import User
from webapp.repositories import dashboard as dashboard_repo

router = APIRouter(prefix="/api/v1")


def _parse_exclude(raw: str | None) -> list[int]:
    """Comma-separated case ids → list[int]. Empty/absent → []. A non-integer
    token is a client error (400), not a silent drop — server-side validation."""
    if not raw:
        return []
    ids: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            ids.append(int(part))
        except ValueError:
            raise HTTPException(
                status_code=400,
                detail="exclude must be comma-separated integers")
    return ids


@router.get("/recommendations")
def list_recommendations(exclude: str | None = Query(default=None),
                         user: User = Depends(require_auth_api)):
    """Spec §7 mouth 1. Identity from the session (T9.3) — never a param;
    a user only ever sees their own recommendations. `exclude` powers the
    "Swap recommendation" affordance (client re-calls with the swapped id)."""
    exclude_ids = _parse_exclude(exclude)
    return {"recommendations": dashboard_repo.recommendations(user.id, exclude_ids)}
