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
from webapp.auth.email_sender import build_verification_email, get_email_sender
from webapp.auth.email_verification import issue_verification_token
from webapp.auth.sessions import attach_session_cookie, create_session
from webapp.auth.users import (
    EmailAlreadyRegistered,
    InvalidEmailDomain,
    get_or_create_school_user,
    get_user_by_id,
    normalize_email,
)
from webapp.csrf import require_same_origin
from webapp.repositories.schools import domain_is_registered

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


class SignupRequestBody(BaseModel):
    email: str


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


@router.post("/signup/request", status_code=202, dependencies=_MUTATING)
def signup_request(body: SignupRequestBody, request: Request):
    """Gate: only a registered school domain gets a sign-up link, sent via the
    EXISTING email-verification infra (OD-B5-2). Always 202 (no enumeration)."""
    e = normalize_email(body.email)
    domain = e.split("@", 1)[1] if e.count("@") == 1 else ""
    if domain and domain_is_registered(domain):
        try:
            user = get_or_create_school_user(e)
            raw_token = issue_verification_token(user.id)
            base_url = str(request.base_url).rstrip("/")
            verification_url = f"{base_url}/verify?token={raw_token}"
            subject, text_body, html_body = build_verification_email(
                recipient_email=user.email, verification_url=verification_url)
            get_email_sender().send(to=user.email, subject=subject,
                                    text_body=text_body, html_body=html_body)
        except (InvalidEmailDomain, EmailAlreadyRegistered):
            pass  # never surfaces to the caller (neutral response)
        except Exception:  # email/token failure must not leak via status
            import logging
            logging.getLogger(__name__).exception("signup link issue failed")
    return JSONResponse({"status": "ok"}, status_code=202)
