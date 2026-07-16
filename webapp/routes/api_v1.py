"""
/api/v1 router — the native-app API surface (iOS P1). Task 6-8 add more
routes here; keep this module's `router` a clean import point for them.
"""

from __future__ import annotations

import ipaddress
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Request
from fastapi.responses import JSONResponse, Response
from psycopg.rows import dict_row
from pydantic import BaseModel, Field

from webapp.auth.dependencies import require_auth_api
from webapp.auth.sessions import (
    SESSION_COOKIE_NAME,
    attach_session_cookie,
    clear_session_cookie,
    create_session,
    destroy_session,
)
from webapp.auth.users import User, authenticate
from webapp.csrf import require_same_origin
from webapp.db import get_pool
from webapp import drills
from webapp.preview_urls import preview_page_urls
from webapp.push.events import push_to_user
from webapp.repositories import availability as availability_repo
from webapp.repositories import dashboard as dashboard_repo
from webapp.repositories import device_tokens as repo
from webapp.repositories import drill_attempts as drills_repo
from webapp.repositories import live_activity_tokens as live_activity_repo
from webapp.repositories import practice_sessions as sessions_repo
from webapp.repositories import proposals as proposals_repo
from webapp.repositories.cases import SearchFilters, get_case_by_id, search_cases

router = APIRouter(prefix="/api/v1")

_MUTATING = [Depends(require_same_origin)]


class DeviceTokenBody(BaseModel):
    token: str
    platform: Literal["ios"] = Field(default="ios")


class LoginBody(BaseModel):
    email: str
    password: str


class LiveActivityBody(BaseModel):
    session_id: int
    push_token: str


class DrillAttemptBody(BaseModel):
    drill_type: Literal["market_sizing", "mental_math", "framework_recall"]
    source: Literal["on_device", "server"]
    drill_key: str | None = Field(default=None, max_length=200)
    correct: bool


class AvailabilityBody(BaseModel):
    minutes: int = Field(ge=5, le=240)


def _user_json(user: User) -> dict:
    """User JSON shape shared by login and /me — the contract for the iOS
    User model. `name` falls back to the email's local part when no
    display_name is set (see db/migrations/011_caseroom.sql)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT COALESCE(display_name, split_part(email::text, '@', 1)) AS name
                FROM users WHERE id = %s;
                """,
                (user.id,),
            )
            row = cur.fetchone()
    return {"id": user.id, "email": user.email, "name": row["name"]}


def _push_display_name(user: User) -> str:
    """The toggling user's name for the free-now push — display_name, else
    the full email (the brief's `display_name or email`)."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT display_name FROM users WHERE id = %s;", (user.id,))
            row = cur.fetchone()
    return (row[0] if row else None) or user.email


def _client_ip(request: Request) -> str | None:
    """request.client.host, or None if it isn't a real IP (e.g. TestClient's
    synthetic "testclient" host, which the sessions.ip_address INET column
    would otherwise reject)."""
    host = request.client.host if request.client else None
    try:
        ipaddress.ip_address(host)
    except (TypeError, ValueError):
        return None
    return host


@router.post("/auth/login", dependencies=_MUTATING)
def login(body: LoginBody, request: Request):
    user = authenticate(body.email, body.password)
    if user is None:
        raise HTTPException(status_code=401, detail="invalid_credentials")

    user_agent = request.headers.get("user-agent")
    session = create_session(user.id, user_agent=user_agent, ip_address=_client_ip(request))

    response = JSONResponse({"user": _user_json(user)})
    attach_session_cookie(response, session)
    return response


@router.post("/auth/logout", status_code=204, dependencies=_MUTATING)
def logout(request: Request):
    sid = request.cookies.get(SESSION_COOKIE_NAME)
    if sid:
        destroy_session(sid)

    response = Response(status_code=204)
    clear_session_cookie(response)
    return response


@router.get("/me")
def me(user: User = Depends(require_auth_api)):
    return _user_json(user)


@router.post("/devices", status_code=204, dependencies=_MUTATING)
def register_device(body: DeviceTokenBody, user: User = Depends(require_auth_api)):
    repo.upsert_token(user.id, body.token, body.platform)
    return Response(status_code=204)


@router.delete("/devices/{token}", status_code=204, dependencies=_MUTATING)
def unregister_device(token: str, user: User = Depends(require_auth_api)):
    repo.delete_token(user.id, token)
    return Response(status_code=204)


@router.post("/live-activity", status_code=204, dependencies=_MUTATING)
def register_live_activity(body: LiveActivityBody, user: User = Depends(require_auth_api)):
    session = sessions_repo.get_practice_session(body.session_id)
    role = sessions_repo.role_of(session, user.id) if session else None
    if session is None or role is None:
        # Non-participant: existence not disclosed (DV-11), same as /api/practice.
        raise HTTPException(status_code=404, detail="No such session")
    live_activity_repo.upsert_token(body.session_id, user.id, body.push_token)
    return Response(status_code=204)


@router.post("/drills/attempts", status_code=204, dependencies=_MUTATING)
def record_drill_attempt(body: DrillAttemptBody, user: User = Depends(require_auth_api)):
    drills_repo.record_attempt(
        user.id,
        drill_type=body.drill_type,
        source=body.source,
        drill_key=body.drill_key,
        correct=body.correct,
    )
    return Response(status_code=204)


@router.get("/drills/daily")
def daily_drill(user: User = Depends(require_auth_api)):
    # Determinism: pass UTC today explicitly; generation never reads the clock.
    today = datetime.now(timezone.utc).date()
    return {"drill": drills.daily_drill(user.id, today), "date": today.isoformat()}


@router.get("/drills/templates")
def drill_templates(user: User = Depends(require_auth_api)):
    # The raw bank JSON ({version, templates}) — device offline cache for the FM engine.
    return drills.bank_document()


@router.put("/availability", dependencies=_MUTATING)
def set_availability(body: AvailabilityBody, background: BackgroundTasks,
                     user: User = Depends(require_auth_api)):
    result = availability_repo.set_free(user.id, body.minutes)
    others = availability_repo.list_free(exclude_user_id=user.id)
    # Instant-match push ONLY on a fresh toggle-on (was_free false) — an
    # extend/refresh while already free must stay silent.
    if not result["was_free"]:
        name = _push_display_name(user)
        for other in others:
            background.add_task(
                push_to_user, other["user_id"],
                title="Free now",
                body=f"{name} is free for a case now",
                data={"kind": "free_now", "user_id": user.id, "name": name},
            )
    return {"free_until": result["free_until"], "others": others}


@router.delete("/availability", status_code=204, dependencies=_MUTATING)
def clear_availability(user: User = Depends(require_auth_api)):
    availability_repo.clear_free(user.id)
    return Response(status_code=204)


@router.get("/availability")
def get_availability(user: User = Depends(require_auth_api)):
    # Lazy expiry: list_free already filters free_until > now(). One query
    # yields both the caller's own window and everyone else's.
    free = availability_repo.list_free()
    mine = next((r for r in free if r["user_id"] == user.id), None)
    others = [r for r in free if r["user_id"] != user.id]
    return {"free_until": mine["free_until"] if mine else None, "others": others}


@router.get("/cases")
def list_cases(
    q: str | None = None,
    difficulty: str | None = None,
    industry: str | None = None,
    case_type: str | None = None,
    school: str | None = None,
    limit: int = Query(100, ge=1, le=200),
    user: User = Depends(require_auth_api),
):
    filters = SearchFilters.from_query(
        q=q, difficulty=difficulty, industry=industry, case_type=case_type, school=school,
    )
    rows, total = search_cases(filters, limit=limit)
    # rows carry internal columns (e.g. pdf_path) from the repository layer —
    # strip them before they reach the client; the list is a summary with no
    # PDF field at all.
    cases = []
    for row in rows:
        row = dict(row)
        row.pop("pdf_path", None)
        cases.append(row)
    return {"cases": cases, "total": total}


_CASE_DETAIL_FIELDS = (
    "id", "case_title", "source_school", "source_year", "industry", "case_type",
    "difficulty", "difficulty_score", "firm", "page_count",
    "industry_raw", "industry_display",
)


@router.get("/cases/{case_id}")
def get_case(case_id: int, request: Request, user: User = Depends(require_auth_api)):
    case = get_case_by_id(case_id)
    if case is None:
        raise HTTPException(status_code=404, detail="Case not found")

    case = dict(case)
    settings = request.app.state.settings
    page_count = case.get("page_count") or 0
    preview_urls = preview_page_urls(
        case_id=case_id, case_row=case, page_count=int(page_count), settings=settings,
    )
    pdf_url = f"{settings.pdf_route_prefix}/cases/{case_id}"

    # get_case_by_id() selects internal/admin columns (preview_public_slug,
    # is_duplicate_case, unique_case_count_eligible, normalized_title,
    # interviewer_led, created_at, updated_at) not meant for the iOS API
    # contract — trim to the same field set the list endpoint ships, plus
    # the two detail-only additions.
    result = {field: case.get(field) for field in _CASE_DETAIL_FIELDS}
    result["preview_urls"] = preview_urls
    result["pdf_url"] = pdf_url
    return result


def _upcoming_session_json(row: dict) -> dict:
    """Unified SessionSummary shape (Task 10 iOS contract) for a
    list_upcoming_for_user() row — scheduled_at/state filled, ended_at/grade
    null since the session hasn't happened yet."""
    return {
        "id": row["id"],
        "role": row["your_role"],
        "other_user": row["counterpart"],
        "case_title": row["case_title"],
        "scheduled_at": row["scheduled_at"],
        "state": row["state"],
        "ended_at": None,
        "grade": None,
    }


def _recent_session_json(row: dict) -> dict:
    """Unified SessionSummary shape for a dashboard_repo.history() row —
    ended_at/grade filled, scheduled_at/state null since the session is over."""
    return {
        "id": row["id"],
        "role": row["your_role"],
        "other_user": row["counterpart"],
        "case_title": row["case_title"],
        "scheduled_at": None,
        "state": None,
        "ended_at": row["ended_at"],
        "grade": row["grade"],
    }


@router.get("/proposals")
def list_proposals(user: User = Depends(require_auth_api)):
    proposals_repo.sweep_expired()  # T8.3: page loads stand in for cron
    rows = proposals_repo.inbox(user.id)
    # Curated subset of the inbox row — to_user_id/session_id/responded_at/
    # state are internal bookkeeping the iOS inbox view has no use for.
    proposals = [
        {
            "id": row["id"],
            "from_name": row["from_name"],
            "from_role": row["from_role"],
            "case_id": row["case_id"],
            "case_title": row["case_title"],
            "case_type": row["case_type"],
            "difficulty": row["difficulty"],
            "message": row["message"],
            "proposed_times": row["proposed_times_json"],
            "created_at": row["created_at"],
        }
        for row in rows
    ]
    return {"proposals": proposals}


@router.get("/sessions")
def list_sessions(
    scope: Literal["upcoming", "recent"] = "upcoming",
    user: User = Depends(require_auth_api),
):
    if scope == "recent":
        sessions = [_recent_session_json(row) for row in dashboard_repo.history(user.id)]
    else:
        sessions = [_upcoming_session_json(row)
                    for row in sessions_repo.list_upcoming_for_user(user.id)]
    return {"sessions": sessions}


@router.get("/dashboard")
def dashboard(user: User = Depends(require_auth_api)):
    stats = sessions_repo.public_stats(user.id)
    upcoming = sessions_repo.list_upcoming_for_user(user.id)
    # list_upcoming_for_user already orders soonest-first (scheduled_at NULLS
    # FIRST — an unscheduled "now" session is the most urgent, then earliest
    # scheduled_at); the first row is the soonest.
    next_session = _upcoming_session_json(upcoming[0]) if upcoming else None
    return {
        "sessions_finalized": stats["sessions_finalized"],
        "streak_weeks": stats["streak_weeks"],
        "next_session": next_session,
        "streak_days": drills_repo.streak_days(user.id),
        "drill_done_today": drills_repo.attempted_today(user.id),
    }
