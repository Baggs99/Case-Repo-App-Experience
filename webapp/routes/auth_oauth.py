"""
Purpose: Browser OAuth entry + callback for Google and LinkedIn (hand-rolled
         OIDC). Absent creds -> 503. The school-email registry gates account
         creation (OD-B5-2): an OAuth identity whose email domain isn't
         registered (and isn't already linked) is bounced to sign-up.
Inputs:  webapp.auth.oauth (config/PKCE/exchange/jwks/verify); users OAuth
         helpers; schools registry; session cookies. state/verifier/nonce ride
         a short-lived signed cookie.
Outputs: sets a session cookie on success; creates/links users; 302 redirects.
Run:     registered in webapp/main.py; e.g. GET /auth/google.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import time
from typing import Optional

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse
from starlette.concurrency import run_in_threadpool

from pipeline.storage import get_storage
from webapp.auth import oauth
from webapp.auth.sessions import _cookie_secure, attach_session_cookie, create_session
from webapp.auth.users import (
    create_school_user,
    get_user_by_email,
    get_user_by_oauth_sub,
    import_oauth_name,
    link_oauth_sub,
    mark_email_verified,
    normalize_email,
)
from webapp.repositories.profile import set_photo_key
from webapp.repositories.schools import domain_is_registered

logger = logging.getLogger(__name__)

router = APIRouter()

_PROVIDERS = ("google", "linkedin")
_STATE_COOKIE = "oauth_state_{provider}"
_STATE_MAX_AGE = 600  # 10 minutes
_AVATAR_EXT = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
_MAX_AVATAR_BYTES = 5 * 1024 * 1024


def _state_secret() -> Optional[bytes]:
    """The HMAC key for the OAuth state cookie. Returns None when
    WEBAPP_SESSION_SECRET is unset — the routes then treat OAuth as
    unconfigured (503) rather than fall back to a guessable constant, which
    would allow login-CSRF / state forgery."""
    secret = os.environ.get("WEBAPP_SESSION_SECRET", "").strip()
    return secret.encode() if secret else None


def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _b64u_dec(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def _oauth_ready(provider: str) -> bool:
    """OAuth is usable only when the provider creds AND the state secret exist."""
    return oauth.provider_config(provider) is not None and _state_secret() is not None


def _sign_state(payload: dict) -> str:
    """HMAC-SHA256 signed, tamper-evident cookie value (stdlib only, no deps).
    Caller guarantees the secret exists (route checked _oauth_ready)."""
    secret = _state_secret()
    assert secret is not None  # guarded by _oauth_ready in the routes
    payload = {**payload, "ts": int(time.time())}
    body = _b64u(json.dumps(payload).encode())
    sig = hmac.new(secret, body.encode(), hashlib.sha256).digest()
    return f"{body}.{_b64u(sig)}"


def _unsign_state(raw: str) -> Optional[dict]:
    """Return the payload iff the signature is valid and not older than
    _STATE_MAX_AGE; else None."""
    secret = _state_secret()
    if secret is None:
        return None
    try:
        body, sig = raw.split(".")
    except (ValueError, AttributeError):
        return None
    expected = hmac.new(secret, body.encode(), hashlib.sha256).digest()
    try:
        if not hmac.compare_digest(expected, _b64u_dec(sig)):
            return None
        data = json.loads(_b64u_dec(body))
    except (ValueError, KeyError):
        return None
    if int(time.time()) - int(data.get("ts", 0)) > _STATE_MAX_AGE:
        return None
    return data


def _download_avatar(url: str) -> Optional[tuple[bytes, str]]:
    """Best-effort fetch of a provider avatar. Returns (data, content_type) for
    a supported image within the size cap, else None. Never raises."""
    try:
        with httpx.Client(timeout=10.0, follow_redirects=True) as client:
            resp = client.get(url)
        if resp.status_code != 200:
            return None
        content_type = (resp.headers.get("content-type") or "").split(";")[0].strip().lower()
        if content_type not in _AVATAR_EXT:
            return None
        data = resp.content
        if not data or len(data) > _MAX_AVATAR_BYTES:
            return None
        return data, content_type
    except Exception:
        logger.exception("avatar download failed")
        return None


def _import_avatar(user_id: int, picture_url: str) -> None:
    """Import a provider avatar into storage on first link (best-effort). A
    failure here must never break sign-in."""
    fetched = _download_avatar(picture_url)
    if fetched is None:
        return
    data, content_type = fetched
    key = f"avatars/{user_id}.{_AVATAR_EXT[content_type]}"
    try:
        get_storage().write(key, data, content_type=content_type)
        set_photo_key(user_id, key)
    except Exception:
        logger.exception("avatar import failed for user_id=%s", user_id)


def _redirect_uri(request: Request, provider: str) -> str:
    base = str(request.base_url).rstrip("/")
    return f"{base}/auth/{provider}/callback"


def _domain(email: str) -> str:
    e = normalize_email(email)
    return e.split("@", 1)[1] if e.count("@") == 1 else ""


@router.get("/auth/{provider}")
def oauth_start(provider: str, request: Request):
    if provider not in _PROVIDERS:
        return JSONResponse({"detail": "unknown_provider"}, status_code=404)
    if not _oauth_ready(provider):
        return JSONResponse(
            {"detail": f"{provider} sign-in is not configured on this server "
                       "(set the client id/secret and WEBAPP_SESSION_SECRET)."},
            status_code=503,
        )

    state = oauth.make_state()
    verifier, challenge = oauth.make_pkce()
    nonce = oauth.make_state()
    url = oauth.authorize_url(
        provider, state=state, code_challenge=challenge,
        redirect_uri=_redirect_uri(request, provider), nonce=nonce)

    payload = _sign_state({"state": state, "verifier": verifier, "nonce": nonce})
    response = RedirectResponse(url, status_code=302)
    response.set_cookie(
        key=_STATE_COOKIE.format(provider=provider),
        value=payload, max_age=_STATE_MAX_AGE, httponly=True,
        samesite="lax", path="/", secure=_cookie_secure(),
    )
    return response


@router.get("/auth/{provider}/callback")
async def oauth_callback(provider: str, request: Request,
                         code: str = "", state: str = "", error: str = ""):
    if provider not in _PROVIDERS:
        return JSONResponse({"detail": "unknown_provider"}, status_code=404)
    if not _oauth_ready(provider):
        return JSONResponse(
            {"detail": f"{provider} sign-in is not configured on this server "
                       "(set the client id/secret and WEBAPP_SESSION_SECRET)."},
            status_code=503,
        )
    cfg = oauth.provider_config(provider)
    if error:
        # Provider-side denial (user cancelled / consent refused).
        return RedirectResponse("/login?oauth_error=denied", status_code=302)

    cookie_name = _STATE_COOKIE.format(provider=provider)
    raw = request.cookies.get(cookie_name)
    stored = _unsign_state(raw) if raw else None
    if stored is None:
        return RedirectResponse("/login?oauth_error=state", status_code=302)
    if not code or not state or state != stored.get("state"):
        return RedirectResponse("/login?oauth_error=state", status_code=302)

    try:
        tokens = await oauth.exchange_code(
            provider, code=code, code_verifier=stored["verifier"],
            redirect_uri=_redirect_uri(request, provider))
        id_token = tokens.get("id_token")
        if not id_token:
            raise oauth.OAuthError("no id_token in token response")
        jwks = await oauth.fetch_jwks(provider)
        claims = oauth.verify_id_token(
            provider, id_token, jwks, client_id=cfg.client_id,
            nonce=stored.get("nonce"))
    except oauth.OAuthError:
        logger.exception("%s OAuth callback failed", provider)
        return RedirectResponse("/login?oauth_error=verify", status_code=302)

    identity = oauth.identity_from_claims(claims)

    # 1) Already linked -> log in. The sub is the durable link; no re-check of
    #    the email is needed for an account we already vouched for.
    user = get_user_by_oauth_sub(provider, identity.sub)
    newly_linked = False

    if user is None:
        # SECURITY: linking to / creating from an email requires the provider to
        # assert email_verified. A provider can emit an UNVERIFIED email (Google
        # does for aliases / unconfirmed addresses); trusting it would let an
        # attacker link their OAuth identity to a victim's existing account or a
        # domain they don't control.
        if not identity.email or not identity.email_verified:
            return RedirectResponse("/login?oauth_error=needs_signup", status_code=302)

        # 2) Existing account by (verified) email -> link this provider.
        existing = get_user_by_email(identity.email)
        if existing is not None:
            link_oauth_sub(existing.id, provider, identity.sub)
            user, newly_linked = existing, True
        # 3) New identity on a registered domain -> create a school user.
        elif domain_is_registered(_domain(identity.email)):
            user = create_school_user(identity.email, display_name=identity.name)
            link_oauth_sub(user.id, provider, identity.sub)
            newly_linked = True
        # 4) New identity on an unregistered domain -> bounce to sign-up.
        else:
            return RedirectResponse("/login?oauth_error=needs_signup", status_code=302)

    # Import name + photo on first link only (idempotent; not re-run every login).
    if newly_linked:
        import_oauth_name(user.id, identity.name)
        if identity.picture:
            # best-effort, never raises
            await run_in_threadpool(_import_avatar, user.id, identity.picture)
    mark_email_verified(user.id)  # provider asserted the email (verified path only)

    session = create_session(user.id, user_agent=request.headers.get("user-agent"),
                             ip_address=None)
    response = RedirectResponse("/", status_code=302)
    attach_session_cookie(response, session)
    response.delete_cookie(cookie_name, path="/")
    return response
