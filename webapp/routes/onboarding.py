"""
Purpose: /api/v1 onboarding entry — email+passcode OTP and the school-email
         sign-up gate. Neutral responses (no user enumeration) on all email
         inputs.
Inputs:  session-cookie auth infra; OTP module; schools registry; email
         verification infra.
Outputs: sends OTP / sign-up emails; may create school users; sets a session
         cookie on OTP verify.
Run:     registered in webapp/main.py; e.g. POST /api/v1/auth/otp/request.
"""

from __future__ import annotations

import ipaddress

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel

from webapp.auth import otp as otp_mod
from webapp.auth.sessions import attach_session_cookie, create_session
from webapp.auth.users import get_user_by_id
from webapp.csrf import require_same_origin

router = APIRouter(prefix="/api/v1")

_MUTATING = [Depends(require_same_origin)]


def _client_ip(request: Request) -> str | None:
    host = request.client.host if request.client else None
    try:
        ipaddress.ip_address(host)
    except (TypeError, ValueError):
        return None
    return host


class OtpRequestBody(BaseModel):
    email: str


class OtpVerifyBody(BaseModel):
    email: str
    code: str


def _user_json(user_id: int) -> dict:
    from webapp.routes.api_v1 import _user_json as api_user_json  # reuse the contract
    user = get_user_by_id(user_id)
    return api_user_json(user)


@router.post("/auth/otp/request", status_code=202, dependencies=_MUTATING)
def otp_request(body: OtpRequestBody):
    otp_mod.request_otp(body.email)   # ignore result — neutral response always
    return JSONResponse({"status": "ok"}, status_code=202)


@router.post("/auth/otp/verify", dependencies=_MUTATING)
def otp_verify(body: OtpVerifyBody, request: Request):
    user_id = otp_mod.verify_otp(body.email, body.code)
    if user_id is None:
        return JSONResponse({"detail": "invalid_code"}, status_code=401)
    session = create_session(user_id, user_agent=request.headers.get("user-agent"),
                             ip_address=_client_ip(request))
    response = JSONResponse({"user": _user_json(user_id)})
    attach_session_cookie(response, session)
    return response
