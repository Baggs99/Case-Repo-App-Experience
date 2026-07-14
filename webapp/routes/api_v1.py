"""
/api/v1 router — the native-app API surface (iOS P1). Task 6-8 add more
routes here; keep this module's `router` a clean import point for them.
"""

from __future__ import annotations

import ipaddress
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
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
from webapp.repositories import device_tokens as repo

router = APIRouter(prefix="/api/v1")

_MUTATING = [Depends(require_same_origin)]


class DeviceTokenBody(BaseModel):
    token: str
    platform: Literal["ios"] = Field(default="ios")


class LoginBody(BaseModel):
    email: str
    password: str


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
