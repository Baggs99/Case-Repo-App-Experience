"""
Page routes — full HTML responses (vs HTMX fragments in routes/search.py).

All content routes are gated behind require_auth: the case repo is for
verified school-email accounts only. The auth routes (/signup, /login, /verify)
live in routes/auth.py and are public.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request

from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.repositories.case_votes import get_vote_state
from webapp.repositories.cases import (
    SearchFilters,
    get_case_by_id,
    get_filter_options,
    search_cases,
)
from webapp.templating import render


router = APIRouter()


@router.get("/")
def index(
    request: Request,
    q:          str | None = None,
    difficulty: str | None = None,
    industry:   str | None = None,
    case_type:  str | None = None,
    school:     str | None = None,
    user: User = Depends(require_auth),
):
    filters = SearchFilters.from_query(
        q=q, difficulty=difficulty, industry=industry, case_type=case_type, school=school,
    )
    settings = request.app.state.settings
    cases, total = search_cases(filters, limit=settings.search_result_limit)
    options = get_filter_options()

    return render(request, "index.html", {
        "filters": filters,
        "options": options,
        "cases":   cases,
        "total":   total,
        "total_cases": total if filters.is_empty() else _count_all_cases(),
    })


@router.get("/cases/{case_id}")
def case_detail(
    request: Request,
    case_id: int,
    user: User = Depends(require_auth),
):
    case = get_case_by_id(case_id)
    if case is None:
        raise HTTPException(status_code=404, detail="Case not found")

    raw_pc = case.get("page_count")
    try:
        preview_page_count = int(raw_pc) if raw_pc is not None else 0
    except (TypeError, ValueError):
        preview_page_count = 0

    vote_state = get_vote_state(case_id, user.id)

    return render(request, "case_detail.html", {
        "case": case,
        "preview_page_count": preview_page_count,
        "vote_state": vote_state,
    })


@router.get("/healthz")
def healthcheck():
    """Cheap liveness check — public, used by load balancers."""
    return {"status": "ok"}


# ── Internals ──────────────────────────────────────────────────────────────────

def _count_all_cases() -> int:
    from webapp.db import get_pool
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM cases;")
            return cur.fetchone()[0]
