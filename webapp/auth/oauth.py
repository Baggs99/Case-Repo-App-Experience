"""
Purpose: Hand-rolled OIDC for Google + LinkedIn (no provider SDKs): PKCE, the
         authorize URL, code->token exchange (httpx), JWKS fetch, and RS256
         id_token verification via `cryptography`.
Inputs:  GOOGLE_CLIENT_ID/SECRET, LINKEDIN_CLIENT_ID/SECRET env; provider HTTP
         endpoints. Absent creds -> provider_config returns None (route 503s).
Outputs: no persistence; returns tokens/claims. Network only in exchange_code /
         fetch_jwks (both mocked in tests).
Run:     imported by webapp/routes/auth_oauth.py.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import time
from dataclasses import dataclass
from typing import Optional
from urllib.parse import urlencode

import httpx
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.exceptions import InvalidSignature


class OAuthError(Exception):
    """Any OIDC validation failure (bad signature, aud/iss/exp/nonce mismatch)."""


@dataclass(frozen=True)
class ProviderConfig:
    name: str
    authorize_endpoint: str
    token_endpoint: str
    jwks_uri: str
    issuer: str
    scope: str
    client_id: str
    client_secret: str


@dataclass(frozen=True)
class OAuthIdentity:
    sub: str
    email: Optional[str]
    email_verified: bool
    name: Optional[str]
    picture: Optional[str]


# Static provider metadata; client id/secret are read from env per-request.
_PROVIDER_META = {
    "google": {
        "authorize_endpoint": "https://accounts.google.com/o/oauth2/v2/auth",
        "token_endpoint": "https://oauth2.googleapis.com/token",
        "jwks_uri": "https://www.googleapis.com/oauth2/v3/certs",
        "issuer": "https://accounts.google.com",
        "scope": "openid email profile",
        "id_env": "GOOGLE_CLIENT_ID",
        "secret_env": "GOOGLE_CLIENT_SECRET",
    },
    "linkedin": {
        "authorize_endpoint": "https://www.linkedin.com/oauth/v2/authorization",
        "token_endpoint": "https://www.linkedin.com/oauth/v2/accessToken",
        "jwks_uri": "https://www.linkedin.com/oauth/openid/jwks",
        "issuer": "https://www.linkedin.com/oauth",
        "scope": "openid profile email",
        "id_env": "LINKEDIN_CLIENT_ID",
        "secret_env": "LINKEDIN_CLIENT_SECRET",
    },
}


def _meta(provider: str) -> dict:
    meta = _PROVIDER_META.get(provider)
    if meta is None:
        raise OAuthError(f"unknown provider: {provider!r}")
    return meta


def provider_config(provider: str) -> Optional[ProviderConfig]:
    """Return the provider config, or None if its client creds aren't set
    (dev). Routes translate None into a 503 with a clear message."""
    meta = _meta(provider)
    client_id = os.environ.get(meta["id_env"], "").strip()
    client_secret = os.environ.get(meta["secret_env"], "").strip()
    if not client_id or not client_secret:
        return None
    return ProviderConfig(
        name=provider,
        authorize_endpoint=meta["authorize_endpoint"],
        token_endpoint=meta["token_endpoint"],
        jwks_uri=meta["jwks_uri"],
        issuer=meta["issuer"],
        scope=meta["scope"],
        client_id=client_id,
        client_secret=client_secret,
    )


# Exposed for tests that need issuer/scope without env creds set.
class _MetaConfig:
    def __init__(self, meta):
        self.issuer = meta["issuer"]
        self.scope = meta["scope"]
        self.authorize_endpoint = meta["authorize_endpoint"]

PROVIDERS = {name: _MetaConfig(meta) for name, meta in _PROVIDER_META.items()}


def _b64u_encode(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _b64u_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)


def make_pkce() -> tuple[str, str]:
    """Return (code_verifier, code_challenge) with the S256 method."""
    verifier = _b64u_encode(secrets.token_bytes(32))
    challenge = _b64u_encode(hashlib.sha256(verifier.encode()).digest())
    return verifier, challenge


def make_state() -> str:
    return _b64u_encode(secrets.token_bytes(16))


def authorize_url(provider: str, *, state: str, code_challenge: str,
                  redirect_uri: str, nonce: str) -> str:
    meta = _meta(provider)
    params = {
        "response_type": "code",
        "client_id": os.environ.get(meta["id_env"], "").strip(),
        "redirect_uri": redirect_uri,
        "scope": meta["scope"],
        "state": state,
        "nonce": nonce,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    return f"{meta['authorize_endpoint']}?{urlencode(params)}"


async def exchange_code(provider: str, *, code: str, code_verifier: str,
                        redirect_uri: str) -> dict:
    """POST the authorization code to the token endpoint. Returns the token
    JSON (contains id_token). Mocked in tests."""
    cfg = provider_config(provider)
    if cfg is None:
        raise OAuthError(f"{provider} OAuth is not configured")
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirect_uri,
        "client_id": cfg.client_id,
        "client_secret": cfg.client_secret,
        "code_verifier": code_verifier,
    }
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.post(cfg.token_endpoint, data=data,
                                 headers={"Accept": "application/json"})
    if resp.status_code != 200:
        raise OAuthError(f"token exchange failed: {resp.status_code}")
    return resp.json()


async def fetch_jwks(provider: str) -> dict:
    """GET the provider's JWKS. Mocked in tests."""
    meta = _meta(provider)
    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(meta["jwks_uri"])
    if resp.status_code != 200:
        raise OAuthError(f"jwks fetch failed: {resp.status_code}")
    return resp.json()


def _rsa_key_from_jwk(jwk: dict) -> rsa.RSAPublicKey:
    n = int.from_bytes(_b64u_decode(jwk["n"]), "big")
    e = int.from_bytes(_b64u_decode(jwk["e"]), "big")
    return rsa.RSAPublicNumbers(e, n).public_key()


def verify_id_token(provider: str, id_token: str, jwks: dict, *,
                    client_id: str, nonce: Optional[str] = None) -> dict:
    """Verify an RS256 id_token against `jwks` and return its claims.

    Checks: signature, alg==RS256, iss matches the provider, aud==client_id,
    exp in the future, and nonce (if provided) matches.
    """
    try:
        header_b64, payload_b64, sig_b64 = id_token.split(".")
    except ValueError as exc:
        raise OAuthError("malformed id_token") from exc

    try:
        header = json.loads(_b64u_decode(header_b64))
    except Exception as exc:
        raise OAuthError("malformed id_token") from exc
    if header.get("alg") != "RS256":
        raise OAuthError(f"unexpected alg: {header.get('alg')}")

    kid = header.get("kid")
    jwk = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if jwk is None:
        raise OAuthError("no matching JWK for kid")

    pub = _rsa_key_from_jwk(jwk)
    signing_input = f"{header_b64}.{payload_b64}".encode()
    try:
        pub.verify(_b64u_decode(sig_b64), signing_input,
                   padding.PKCS1v15(), hashes.SHA256())
    except InvalidSignature as exc:
        raise OAuthError("bad id_token signature") from exc

    try:
        claims = json.loads(_b64u_decode(payload_b64))
    except Exception as exc:
        raise OAuthError("malformed id_token") from exc

    iss = claims.get("iss", "")
    expected_iss = _meta(provider)["issuer"]
    # Google also emits 'accounts.google.com' (no scheme); accept either form.
    if iss not in (expected_iss, expected_iss.replace("https://", "")):
        raise OAuthError("issuer mismatch")

    aud = claims.get("aud")
    if aud != client_id and (not isinstance(aud, list) or client_id not in aud):
        raise OAuthError("audience mismatch")

    try:
        exp = int(claims.get("exp", 0))
    except (ValueError, TypeError) as exc:
        raise OAuthError("bad exp") from exc
    if exp <= int(time.time()):
        raise OAuthError("id_token expired")

    if nonce is not None and claims.get("nonce") != nonce:
        raise OAuthError("nonce mismatch")

    return claims


def _coerce_bool(value) -> bool:
    """Coerce an OIDC claim that may be a real bool or a JSON string
    ('true'/'false', as LinkedIn emits) into a strict Python bool. Anything
    not clearly truthy is False — the safe default for email_verified."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in ("true", "1", "yes")
    return bool(value)


def identity_from_claims(claims: dict) -> OAuthIdentity:
    return OAuthIdentity(
        sub=str(claims["sub"]),
        email=(claims.get("email") or None),
        email_verified=_coerce_bool(claims.get("email_verified", False)),
        name=(claims.get("name") or None),
        picture=(claims.get("picture") or None),
    )
