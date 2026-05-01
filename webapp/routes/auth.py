"""
Auth HTTP routes:

  GET  /signup           sign-up form
  POST /signup           create user, send verification email
  GET  /verify           peek token (no consume), render confirm form
  POST /verify           consume token, mark email verified
  GET  /login            login form
  POST /login            authenticate, set session cookie
  POST /logout           destroy session, clear cookie
  GET  /change-password  change-password form (login required)
  POST /change-password  rotate password, kill all sessions, force re-login
  GET  /forgot-password  request a password-reset link
  POST /forgot-password  email a reset link (always shows "check your email")
  GET  /reset-password   peek token (no consume), render new-password form
  POST /reset-password   consume token, set new password, kill all sessions

Design notes
------------
- We never tell the user which check failed in /login (email or password) —
  prevents email enumeration.
- We never tell the user during /signup whether an email is already taken
  by a real account vs free; instead we always show the same "check your
  email" message and silently skip the email if the address is taken.
  This matches industry best practice (1Password / GitHub style).
- /verify and /reset-password both use a two-step GET-then-POST flow.
  Microsoft Defender Safe Links (and other corporate URL scanners) pre-
  fetch every link in inbound email, which would burn a single-use token
  before the human ever clicks it. ATP follows GETs but never submits
  forms, so the actual consumption only happens on POST.
- The optional `?next=<url>` param on /login redirects users to where they
  were trying to go before being bounced to login.
"""

from __future__ import annotations

import logging
from typing import Optional
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from webapp.auth.dependencies import get_current_user, require_auth
from webapp.auth.email_sender import (
    build_password_reset_email,
    build_verification_email,
    get_email_sender,
)
from webapp.auth.email_verification import (
    VerificationResult,
    consume_verification_token,
    issue_verification_token,
    peek_verification_token,
)
from webapp.auth.password_reset import (
    consume_password_reset_token,
    issue_password_reset_token,
    verify_password_reset_token,
)
from webapp.auth.passwords import WeakPasswordError, validate_password
from webapp.auth.sessions import (
    SESSION_COOKIE_NAME,
    attach_session_cookie,
    clear_session_cookie,
    create_session,
    destroy_all_sessions_for_user,
    destroy_session,
)
from webapp.auth.users import (
    EmailAlreadyRegistered,
    InvalidCurrentPassword,
    InvalidEmailDomain,
    SamePasswordError,
    User,
    authenticate,
    change_password,
    create_user,
    get_user_by_email,
    set_password,
)
from webapp.templating import render

logger = logging.getLogger(__name__)

router = APIRouter()


# ── Helpers ────────────────────────────────────────────────────────────────────

def _safe_redirect(target: Optional[str], default: str = "/") -> str:
    """Only allow redirects to relative paths on our own site. Prevents
    open-redirect attacks where ?next=https://evil.com would silently
    funnel users to a phishing page after login."""
    if not target:
        return default
    parsed = urlparse(target)
    if parsed.scheme or parsed.netloc:
        return default
    if not target.startswith("/"):
        return default
    return target


# ── Sign up ────────────────────────────────────────────────────────────────────

@router.get("/signup", response_class=HTMLResponse)
def signup_form(request: Request, next: Optional[str] = None):
    if get_current_user(request):
        return RedirectResponse(_safe_redirect(next), status_code=303)
    return render(request, "signup.html", {"next": next, "values": {}, "error": None})


@router.post("/signup", response_class=HTMLResponse)
def signup_submit(
    request: Request,
    email: str = Form(""),
    password: str = Form(""),
    password_confirm: str = Form(""),
    next: Optional[str] = Form(None),
):
    values = {"email": email}

    if password != password_confirm:
        return render(request, "signup.html",
                      {"next": next, "values": values, "error": "Passwords don't match."})

    try:
        user = create_user(email, password)
    except InvalidEmailDomain as exc:
        return render(request, "signup.html",
                      {"next": next, "values": values, "error": str(exc)})
    except WeakPasswordError as exc:
        return render(request, "signup.html",
                      {"next": next, "values": values, "error": str(exc)})
    except EmailAlreadyRegistered:
        # Don't reveal the email is taken — still show "check your email".
        # Real owner of the address sees nothing new (they already have an
        # account); attacker can't enumerate.
        logger.info("Signup attempt for already-registered email; pretending success")
        return render(request, "verify_sent.html", {"email": email})

    raw_token = issue_verification_token(user.id)
    base_url = str(request.base_url).rstrip("/")
    verification_url = f"{base_url}/verify?token={raw_token}"

    subject, text_body, html_body = build_verification_email(
        recipient_email=user.email,
        verification_url=verification_url,
    )
    try:
        get_email_sender().send(
            to=user.email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
        )
    except Exception:
        logger.exception("Failed to send verification email; user can request resend")

    return render(request, "verify_sent.html", {"email": user.email})


# ── Verify email ───────────────────────────────────────────────────────────────
#
# Two-step flow (GET → POST) so URL scanners like Microsoft Defender's
# Safe Links — which pre-fetch every link in inbound email — can't burn
# the single-use token before the human ever sees the page. ATP follows
# GETs but never submits forms, so the actual consumption happens only
# when the user clicks the "Verify my email" button.

@router.get("/verify", response_class=HTMLResponse)
def verify_form(request: Request, token: Optional[str] = None):
    user_id = peek_verification_token(token or "")
    if user_id is None:
        result = VerificationResult(
            success=False,
            user_id=None,
            error="This verification link is invalid or has expired.",
        )
        return render(request, "verify_done.html", {"result": result})
    return render(request, "verify_confirm.html", {"token": token})


@router.post("/verify", response_class=HTMLResponse)
def verify_submit(request: Request, token: str = Form("")):
    result = consume_verification_token(token)
    return render(request, "verify_done.html", {"result": result})


# ── Login ──────────────────────────────────────────────────────────────────────

@router.get("/login", response_class=HTMLResponse)
def login_form(
    request: Request,
    next: Optional[str] = None,
    unverified: int = 0,
    password_changed: int = 0,
    password_reset: int = 0,
):
    if get_current_user(request):
        return RedirectResponse(_safe_redirect(next), status_code=303)

    error = None
    success = None
    if unverified:
        error = (
            "You need to verify your email before signing in. "
            "Check your inbox for the verification link."
        )
    if password_changed:
        success = (
            "Password changed successfully. Sign in with your new password."
        )
    if password_reset:
        success = (
            "Password reset successfully. Sign in with your new password."
        )
    return render(request, "login.html",
                  {"next": next, "values": {}, "error": error, "success": success})


@router.post("/login", response_class=HTMLResponse)
def login_submit(
    request: Request,
    email: str = Form(""),
    password: str = Form(""),
    next: Optional[str] = Form(None),
):
    user = authenticate(email, password)
    if user is None:
        return render(request, "login.html",
                      {"next": next, "values": {"email": email},
                       "error": "Invalid email or password."})

    if not user.is_verified:
        return render(request, "login.html",
                      {"next": next, "values": {"email": email},
                       "error": "Please verify your email before signing in. "
                                "Check your inbox for the verification link."})

    user_agent = request.headers.get("user-agent")
    ip = request.client.host if request.client else None
    session = create_session(user.id, user_agent=user_agent, ip_address=ip)

    response = RedirectResponse(_safe_redirect(next), status_code=303)
    attach_session_cookie(response, session)
    return response


# ── Logout ─────────────────────────────────────────────────────────────────────

@router.post("/logout")
def logout(request: Request):
    sid = request.cookies.get(SESSION_COOKIE_NAME)
    if sid:
        destroy_session(sid)

    response = RedirectResponse("/login", status_code=303)
    clear_session_cookie(response)
    return response


# ── Change password ────────────────────────────────────────────────────────────

@router.get("/change-password", response_class=HTMLResponse)
def change_password_form(request: Request, user: User = Depends(require_auth)):
    return render(request, "change_password.html", {"error": None})


@router.post("/change-password", response_class=HTMLResponse)
def change_password_submit(
    request: Request,
    current_password: str = Form(""),
    new_password: str = Form(""),
    new_password_confirm: str = Form(""),
    user: User = Depends(require_auth),
):
    if new_password != new_password_confirm:
        return render(request, "change_password.html",
                      {"error": "New passwords don't match."})

    try:
        change_password(user.id, current_password, new_password)
    except InvalidCurrentPassword:
        return render(request, "change_password.html",
                      {"error": "Current password is incorrect."})
    except SamePasswordError as exc:
        return render(request, "change_password.html",
                      {"error": str(exc)})
    except WeakPasswordError as exc:
        return render(request, "change_password.html",
                      {"error": str(exc)})

    # Force re-login on every device, including this one. Even though the
    # current session was authenticated by someone who knew both old and
    # new passwords, rotating sessions is the simplest way to guarantee
    # any session leaked or shared before the change is now useless.
    destroy_all_sessions_for_user(user.id)

    response = RedirectResponse("/login?password_changed=1", status_code=303)
    clear_session_cookie(response)
    return response


# ── Forgot password ────────────────────────────────────────────────────────────

@router.get("/forgot-password", response_class=HTMLResponse)
def forgot_password_form(request: Request):
    if get_current_user(request):
        # Already signed in — they don't need a reset link, they should
        # use the change-password form instead.
        return RedirectResponse("/change-password", status_code=303)
    return render(request, "forgot_password.html",
                  {"values": {}, "error": None})


@router.post("/forgot-password", response_class=HTMLResponse)
def forgot_password_submit(
    request: Request,
    email: str = Form(""),
):
    user = get_user_by_email(email)

    # Anti-enumeration: ALWAYS render the same "check your email" page,
    # whether the address exists or not. We only actually send mail when:
    #   - the account exists, AND
    #   - the email has been verified (so we know it really belongs to
    #     the human typing it). Unverified-but-existing accounts can't
    #     reset their password — they should just re-sign-up or wait for
    #     the original verification link.
    if user and user.is_verified:
        raw_token = issue_password_reset_token(user.id)
        base_url = str(request.base_url).rstrip("/")
        reset_url = f"{base_url}/reset-password?token={raw_token}"

        subject, text_body, html_body = build_password_reset_email(
            recipient_email=user.email,
            reset_url=reset_url,
        )
        try:
            get_email_sender().send(
                to=user.email,
                subject=subject,
                text_body=text_body,
                html_body=html_body,
            )
        except Exception:
            logger.exception("Failed to send password-reset email; user can retry")

    return render(request, "forgot_sent.html", {"email": email})


# ── Reset password ─────────────────────────────────────────────────────────────

@router.get("/reset-password", response_class=HTMLResponse)
def reset_password_form(request: Request, token: Optional[str] = None):
    user_id = verify_password_reset_token(token or "")
    if user_id is None:
        return render(request, "reset_invalid.html", {})
    return render(request, "reset_password.html",
                  {"token": token, "error": None})


@router.post("/reset-password", response_class=HTMLResponse)
def reset_password_submit(
    request: Request,
    token: str = Form(""),
    new_password: str = Form(""),
    new_password_confirm: str = Form(""),
):
    if new_password != new_password_confirm:
        return render(request, "reset_password.html",
                      {"token": token, "error": "Passwords don't match."})

    try:
        validate_password(new_password)
    except WeakPasswordError as exc:
        return render(request, "reset_password.html",
                      {"token": token, "error": str(exc)})

    user_id = consume_password_reset_token(token)
    if user_id is None:
        # Token was unknown / expired / already used. We don't fall back
        # to the form (token is gone — there's nothing the user can do
        # with it) — send them to the "request a new link" page.
        return render(request, "reset_invalid.html", {})

    set_password(user_id, new_password)
    destroy_all_sessions_for_user(user_id)

    response = RedirectResponse("/login?password_reset=1", status_code=303)
    clear_session_cookie(response)
    return response
