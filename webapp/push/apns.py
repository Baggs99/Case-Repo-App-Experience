"""
Purpose: Send APNs pushes over HTTP/2 with an ES256 provider JWT.
Inputs: APNS_* settings (key path/id, team id, bundle id, sandbox flag); device token.
Outputs: HTTPS POST to api(.sandbox).push.apple.com; returns status code.
Run: awaited via send_push() from webapp/push/events.py; no CLI entrypoint.
"""
import base64, json, time
import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

_JWT_TTL = 45 * 60  # Apple: refresh 20–60 min
_jwt_cache: dict[tuple[str, str, str], tuple[str, float]] = {}


def _b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def make_provider_jwt(key_pem: bytes, key_id: str, team_id: str, now: float) -> str:
    header = _b64url(json.dumps({"alg": "ES256", "kid": key_id}).encode())
    claims = _b64url(json.dumps({"iss": team_id, "iat": int(now)}).encode())
    signing_input = f"{header}.{claims}".encode()
    key = serialization.load_pem_private_key(key_pem, password=None)
    der_sig = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    # JWT wants raw r||s (64 bytes), not DER
    r, s = utils.decode_dss_signature(der_sig)
    raw = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{header}.{claims}.{_b64url(raw)}"


def _cached_jwt(settings) -> str:
    key_id = settings.apns_key_id
    cache_key = (key_id, settings.apns_team_id, settings.apns_key_path)
    tok, born = _jwt_cache.get(cache_key, ("", 0.0))
    if time.time() - born > _JWT_TTL:
        pem = open(settings.apns_key_path, "rb").read()
        tok = make_provider_jwt(pem, key_id, settings.apns_team_id, time.time())
        _jwt_cache[cache_key] = (tok, time.time())
    return tok


async def send_push(token, *, title, body, data=None, interruption_level: str | None = None,
                     settings=None, client=None) -> int:
    if settings is None:
        from webapp.settings import load_settings
        settings = load_settings()
    host = ("https://api.sandbox.push.apple.com" if settings.apns_use_sandbox
            else "https://api.push.apple.com")
    payload = {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
    if interruption_level is not None:
        payload["aps"]["interruption-level"] = interruption_level
    payload.update(data or {})
    headers = {
        "authorization": f"bearer {_cached_jwt(settings)}",
        "apns-topic": settings.apns_bundle_id,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    owns = client is None
    if owns:
        client = httpx.AsyncClient(http2=True, timeout=10.0)
    try:
        resp = await client.post(f"{host}/3/device/{token}", json=payload, headers=headers)
        return resp.status_code
    finally:
        if owns:
            await client.aclose()
