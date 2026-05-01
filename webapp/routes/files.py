"""
PDF serving — speaks to the Storage abstraction so the same route
handles local filesystem, S3, R2, Supabase, etc.

Local backend → FileResponse (uses sendfile syscall, very fast)
Cloud backend → 302 redirect to a signed URL
"""

from __future__ import annotations

from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse, RedirectResponse

from pipeline.storage import get_storage, validate_key
from webapp.auth.dependencies import require_auth
from webapp.auth.users import User


router = APIRouter()


@router.get("/files/{key:path}")
def serve_pdf(key: str, user: User = Depends(require_auth)):
    """Serve the PDF identified by `key` (a Storage layer key).

    URL paths are URL-encoded by browsers; Starlette decodes them but if
    a key contains literal `%` we still need to be careful. We use
    `validate_key` to defend against path traversal and other shenanigans.
    """
    decoded = unquote(key)

    try:
        validate_key(decoded)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    storage = get_storage()
    if not storage.exists(decoded):
        raise HTTPException(status_code=404, detail=f"PDF not found: {decoded}")

    local = storage.local_path(decoded)
    if local is not None:
        return FileResponse(
            path=local,
            media_type="application/pdf",
            filename=local.name,
        )

    return RedirectResponse(
        url=storage.url(decoded, expires_in=3600),
        status_code=302,
    )
