"""
Page routes — full HTML responses (vs HTMX fragments in routes/search.py).

All content routes are gated behind require_auth: the case repo is for
verified school-email accounts only. The auth routes (/signup, /login, /verify)
live in routes/auth.py and are public.
"""

from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request

from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.preview_urls import preview_knit_url
from webapp.repositories.case_votes import (
    get_vote_state_safe,
    get_vote_stats_for_cases_safe,
)
from webapp.repositories.cases import (
    SearchFilters,
    count_all_cases,
    get_case_by_id,
    get_filter_options,
    search_cases,
)
from webapp.templating import render, render_browse_page


router = APIRouter()

# Default destination for "← Back to results" when no return_to is provided.
DEFAULT_BACK_URL = "/search"


@router.get("/")
def index(
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
    _attach_vote_stats(cases)
    options = get_filter_options()

    return render_browse_page(request, "index.html", {
        "filters": filters,
        "options": options,
        "cases":   cases,
        "total":   total,
        "total_cases": total if filters.is_empty() else _count_all_cases(
            include_duplicates=filters.include_duplicates,
        ),
        # Mirrors the URL the home page would render at; lets templated case
        # links carry a return_to back to the same filtered view.
        "return_url": filters.to_search_url(),
    })


@router.get("/cases/{case_id}")
def case_detail(
    request: Request,
    case_id: int,
    return_to: Optional[str] = None,
    user: User = Depends(require_auth),
):
    case = get_case_by_id(case_id)
    if case is None:
        raise HTTPException(status_code=404, detail="Case not found")

    vote_state = get_vote_state_safe(case_id, user.id)

    knit_u = preview_knit_url(case_row=dict(case), settings=request.app.state.settings)

    from webapp.repositories.queues import membership
    return render(request, "case_detail.html", {
        "case": case,
        "preview_knit_url": knit_u,
        "vote_state": vote_state,
        "back_url": _safe_back_url(return_to),
        "queue_state": membership(user.id, case_id),
    })


@router.get("/healthz")
def healthcheck():
    """Cheap liveness check — public, used by load balancers."""
    return {"status": "ok"}


# ── Internals ──────────────────────────────────────────────────────────────────

def _count_all_cases(*, include_duplicates: bool = False) -> int:
    """Wrapper kept private to this module so the demo server can monkey-patch
    the symbol (``presentation/demo_server.py`` overrides this for its CSV-only
    standalone preview). Real implementation lives in ``cases`` repo."""
    return count_all_cases(include_duplicates=include_duplicates)


def _attach_vote_stats(rows: list[dict]) -> None:
    """Decorate each search row with public vote aggregates.

    Adds ``useful_count``, ``not_useful_count``, ``total_votes``, and
    ``useful_percentage`` keys (the last is ``None`` when there are no votes
    yet, so templates can branch cleanly). One bulk query, idempotent on
    empty lists, tolerates a missing ``case_votes`` table.
    """
    if not rows:
        return
    ids = [int(r["id"]) for r in rows if r.get("id") is not None]
    stats = get_vote_stats_for_cases_safe(ids)
    for r in rows:
        s = stats.get(int(r["id"]), {
            "useful_count": 0,
            "not_useful_count": 0,
            "total_votes": 0,
            "useful_percentage": None,
        })
        r["useful_count"] = s["useful_count"]
        r["not_useful_count"] = s["not_useful_count"]
        r["total_votes"] = s["total_votes"]
        r["useful_percentage"] = s["useful_percentage"]


def _safe_back_url(candidate: Optional[str]) -> str:
    """Accept only same-origin paths; otherwise fall back to DEFAULT_BACK_URL.

    Rejects ``//evil.example`` (protocol-relative), absolute URLs, and any
    value that doesn't start with a single ``/``. This keeps the link from
    being abused as an open-redirect vector.
    """
    if not candidate:
        return DEFAULT_BACK_URL
    if not candidate.startswith("/") or candidate.startswith("//"):
        return DEFAULT_BACK_URL
    return candidate
