"""
PDF serving — speaks to the Storage abstraction so the same route
handles local filesystem, S3, R2, Supabase, etc.

Preferred entry point for case PDFs: ``GET /files/cases/{case_id}``, which
logs per-user view/download events for the admin dashboard.

Legacy ``GET /files/{key}`` remains for backward compatibility but does
not write audit rows (no case id context).
"""

from __future__ import annotations

from typing import Literal, Optional
from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, RedirectResponse

from pipeline.storage import get_storage, to_storage_key, validate_key
from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.repositories.case_access import record_case_access
from webapp.repositories.cases import get_case_by_id


router = APIRouter()


def _infer_case_pdf_access_kind(
    request: Request,
    *,
    download_query: bool,
) -> Optional[Literal["view", "download"]]:
    """Classify this request for audit logging.

    We tag **inline reading** URLs with ``?embed=1`` (iframe + “Open in new tab”).

    The browser’s built-in PDF toolbar **Save / Download** typically issues a
    fresh GET **without** ``embed`` or ``download`` — that counts as **download**
    so admin stats match the white Download button.

    Range requests with ``Sec-Fetch-Dest: empty`` are progressive viewer chunks;
    they are skipped so we do not flood the audit table.

    Returns ``None`` to skip logging entirely.
    """
    if download_query:
        return "download"

    range_hdr = (request.headers.get("range") or "").strip()
    dest = (request.headers.get("sec-fetch-dest") or "").lower()
    mode = (request.headers.get("sec-fetch-mode") or "").lower()

    # Progressive PDF loads inside the viewer (many Range GETs); never audit each chunk.
    if range_hdr and dest == "empty":
        return None

    embed_raw = request.query_params.get("embed")
    if embed_raw is not None and embed_raw.strip().lower() in (
        "1", "true", "yes",
    ):
        return "view"

    if dest == "iframe":
        return "view"

    # Top-level “open PDF” navigation (e.g. bookmarked URL without ?embed=1).
    if dest == "document" and mode == "navigate":
        return "view"

    # Built-in viewer Save/Download: GET without ?embed=1 / ?download=1.
    return "download"

def _pdf_storage_key(raw: str | None) -> Optional[str]:
    """Derive a storage key from a catalog ``pdf_path`` (absolute or relative)."""
    if not raw:
        return None
    key = to_storage_key(raw)
    if key:
        return key
    p = raw.replace("\\", "/").strip().lstrip("/")
    if not p.endswith(".pdf") or ".." in p.split("/"):
        return None
    try:
        validate_key(p)
    except ValueError:
        return None
    return p


@router.get("/files/cases/{case_id}")
def serve_case_pdf(
    request: Request,
    case_id: int,
    download: bool = Query(False),
    user: User = Depends(require_auth),
):
    """Serve a case PDF after recording a view or download event."""
    case = get_case_by_id(case_id)
    if case is None:
        raise HTTPException(status_code=404, detail="Case not found")

    key = _pdf_storage_key(case.get("pdf_path"))
    if not key:
        raise HTTPException(status_code=404, detail="Case has no PDF")

    storage = get_storage()
    if not storage.exists(key):
        raise HTTPException(status_code=404, detail="PDF not found")

    kind = _infer_case_pdf_access_kind(request, download_query=download)
    if kind is not None:
        record_case_access(user.id, case_id, kind)

    filename = key.split("/")[-1]
    local = storage.local_path(key)
    if local is not None:
        return FileResponse(
            path=local,
            media_type="application/pdf",
            filename=filename if download else None,
            content_disposition_type="attachment" if download else "inline",
        )

    return RedirectResponse(
        url=storage.url(
            key,
            expires_in=3600,
            attachment_filename=filename if download else None,
        ),
        status_code=302,
    )


@router.get("/files/{key:path}")
def serve_pdf(key: str, user: User = Depends(require_auth)):
    """Serve the PDF identified by `key` (a Storage layer key).

    URL paths are URL-encoded by browsers; Starlette decodes them but if
    a key contains literal `%` we still need to be careful. We use
    `validate_key` to defend against path traversal and other shenanigans.

    No audit logging — prefer ``/files/cases/{case_id}`` for tracked access.
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
            content_disposition_type="inline",
        )

    return RedirectResponse(
        url=storage.url(decoded, expires_in=3600),
        status_code=302,
    )
