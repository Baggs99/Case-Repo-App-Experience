"""
Search route — HTMX fragment endpoint. Auth-gated.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request

from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.repositories.cases import SearchFilters, search_cases
from webapp.templating import render


router = APIRouter()


@router.get("/search")
def search(
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

    return render(request, "_search_results.html", {
        "cases": cases, "total": total, "filters": filters,
    })
