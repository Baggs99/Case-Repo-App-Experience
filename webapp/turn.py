"""
Purpose: Mint short-lived TURN credentials (Cloudflare Calls) for WebRTC NAT traversal.
Inputs: TURN_* settings (provider, key id, token); ttl_seconds.
Outputs: HTTPS POST to rtc.live.cloudflare.com; returns normalized ICE-server dict list.
Run: awaited via mint_turn_credentials() from the /join-config route handler (Task 3).
"""
import logging

import httpx

logger = logging.getLogger(__name__)


async def mint_turn_credentials(settings, *, ttl_seconds: int = 3600, client=None) -> list[dict]:
    if not settings.turn_enabled:
        return []
    if settings.turn_provider != "cloudflare":
        logger.warning("Unsupported TURN_PROVIDER=%r; STUN-only degrade", settings.turn_provider)
        return []

    url = f"https://rtc.live.cloudflare.com/v1/turn/keys/{settings.turn_key_id}/credentials/generate"
    headers = {"Authorization": f"Bearer {settings.turn_token}"}
    owns = client is None
    if owns:
        client = httpx.AsyncClient(timeout=10.0)
    try:
        resp = await client.post(url, json={"ttl": ttl_seconds}, headers=headers)
        resp.raise_for_status()
        body = resp.json()
        ice = body["iceServers"]
        urls = ice["urls"]
        if isinstance(urls, str):  # Cloudflare may return a bare string
            urls = [urls]
        return [{"urls": urls, "username": ice["username"], "credential": ice["credential"]}]
    except Exception:
        logger.exception("TURN credential mint failed; falling back to STUN-only")
        return []
    finally:
        if owns:
            await client.aclose()
