"""
Origin-check CSRF guard for state-changing CaseRoom endpoints.

The session cookie is SameSite=Lax, which already blocks cross-site POSTs in
modern browsers. This dependency is defense in depth (see INTEGRATION.md
DV-8): browsers attach an Origin header to every cross-site POST, and a
victim's browser cannot strip it — so "Origin present and wrong" is exactly
the CSRF signature. Requests with no Origin header (curl, same-origin
navigations in some older browsers) pass: a non-browser client carries no
ambient cookie authority to abuse.

Usage:
    @router.post("/api/practice/{id}/state",
                 dependencies=[Depends(require_same_origin)])
"""

from __future__ import annotations

from urllib.parse import urlsplit

from fastapi import HTTPException, Request


def require_same_origin(request: Request) -> None:
    """FastAPI dependency: 403 when an Origin header disagrees with Host."""
    origin = request.headers.get("origin")
    if origin is None:
        return
    # "null" arises from sandboxed iframes and data:/file: pages — all
    # cross-origin contexts as far as we're concerned.
    if origin == "null":
        raise HTTPException(status_code=403, detail="Cross-origin request rejected")

    origin_host = urlsplit(origin).netloc
    request_host = request.headers.get("host", "")
    if not origin_host or origin_host.lower() != request_host.lower():
        raise HTTPException(status_code=403, detail="Cross-origin request rejected")
