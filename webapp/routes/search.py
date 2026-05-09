"""
Search route — HTMX fragment endpoint. Auth-gated.

Direct GET ``/search?q=…`` (browser navigation / refresh after ``hx-push-url``)
returns the full browse page so users never see a bare fragment without layout.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request

from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.repositories.cases import (
    SearchFilters,
    count_all_cases,
    get_filter_options,
    search_cases,
)
from webapp.templating import render


router = APIRouter()


def _is_htmx(request: Request) -> bool:
    return request.headers.get("HX-Request", "").strip().lower() == "true"


@router.get("/search")
def search(
    request: Request,
    q:          str | None = None,
    difficulty: str | None = None,
    industry:   str | None = None,
    case_type:  str | None = None,
    school:     str | None = None,
    include_duplicates: str | None = None,
    user: User = Depends(require_auth),
):
    filters = SearchFilters.from_query(
        q=q, difficulty=difficulty, industry=industry, case_type=case_type, school=school,
        include_duplicates=include_duplicates,
    )
    settings = request.app.state.settings
    cases, total = search_cases(filters, limit=settings.search_result_limit)
    return_url = filters.to_search_url()

    if not _is_htmx(request):
        options = get_filter_options()
        response = render(request, "index.html", {
            "filters": filters,
            "options": options,
            "cases": cases,
            "total": total,
            "total_cases": total if filters.is_empty() else count_all_cases(
                include_duplicates=filters.include_duplicates,
            ),
            "return_url": return_url,
        })
        # Vary on both branches so any HTTP cache keys the layout-less
        # fragment separately from the full page at the same URL.
        response.headers["Vary"] = "HX-Request"
        return response

    response = render(request, "_search_results.html", {
        "cases": cases, "total": total, "filters": filters,
        "return_url": return_url,
    })
    # Browsers must not serve this layout-less fragment when the user later
    # navigates back to /search?... as a full document — that's what produced
    # the "unstyled page after Back" bug. Vary tells caches the fragment is
    # specific to HTMX requests; no-store skips the cache entirely as belt
    # and suspenders against intermediaries that ignore Vary.
    response.headers["Vary"] = "HX-Request"
    response.headers["Cache-Control"] = "no-store"
    return response
