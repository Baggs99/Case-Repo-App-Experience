"""
PDF serving — speaks to the Storage abstraction so the same route
handles local filesystem, S3, R2, Supabase, etc.

Tracked entry points:

- ``GET /files/cases/{case_id}`` — inline PDF for reading (logs **view** where
  applicable). Used by PDF.js on the case detail page and “Open PDF in new tab”.
- ``GET /api/cases/{case_id}/download`` — **only** path that logs **download**
  (explicit save). The page “Download” button links here so counts stay exact.

Legacy ``GET /files/{key}`` does not write audit rows (no case id context).

Query ``?download=1`` on ``/files/cases/...`` redirects to the API route so
old bookmarks keep working without recording twice on the files handler.
"""

from __future__ import annotations

from typing import Literal, Optional
from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, RedirectResponse, Response

from pipeline.storage import get_storage, to_storage_key, validate_key
from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.repositories.case_access import record_case_access
from webapp.repositories.cases import get_case_by_id


router = APIRouter()


def _infer_case_pdf_access_kind(
    request: Request,
) -> Optional[Literal["view", "download"]]:
    """Classify this request for audit logging.

    **Downloads** are never inferred here — they use
    ``GET /api/cases/{case_id}/download`` only.

    Inline reading uses ``?embed=1`` (PDF.js loader + “Open PDF in new tab”).
    Progressive Range chunks from the viewer are skipped so we do not log each
    byte range.

    Returns ``None`` to skip logging entirely.
    """
    range_hdr = (request.headers.get("range") or "").strip()
    dest = (request.headers.get("sec-fetch-dest") or "").lower()
    mode = (request.headers.get("sec-fetch-mode") or "").lower()

    # Progressive PDF loads inside PDF.js / browser viewer (many Range GETs).
    if range_hdr and dest == "empty":
        return None

    embed_raw = request.query_params.get("embed")
    embed_true = embed_raw is not None and embed_raw.strip().lower() in (
        "1",
        "true",
        "yes",
    )
    if embed_true:
        return "view"

    if dest == "iframe":
        return "view"

    # Top-level “open PDF” navigation (e.g. bookmarked URL without ?embed=1).
    if dest == "document" and mode == "navigate":
        return "view"

    # Without ?embed=1 this is usually a direct save/navigation edge case — treat as view.
    return "view"


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


def _storage_pdf_response(key: str, filename: str, *, attachment: bool) -> Response:
    """Return inline file response or signed redirect — shared by view + download."""
    storage = get_storage()
    local = storage.local_path(key)
    if local is not None:
        return FileResponse(
            path=local,
            media_type="application/pdf",
            filename=filename if attachment else None,
            content_disposition_type="attachment" if attachment else "inline",
        )
    return RedirectResponse(
        url=storage.url(
            key,
            expires_in=3600,
            attachment_filename=filename if attachment else None,
        ),
        status_code=302,
    )


def _resolve_case_pdf(case_id: int) -> tuple[str, str]:
    """Return ``(storage_key, filename)`` or raise HTTPException."""
    case = get_case_by_id(case_id)
    if case is None:
        raise HTTPException(status_code=404, detail="Case not found")

    key = _pdf_storage_key(case.get("pdf_path"))
    if not key:
        raise HTTPException(status_code=404, detail="Case has no PDF")

    storage = get_storage()
    if not storage.exists(key):
        raise HTTPException(status_code=404, detail="PDF not found")

    filename = key.split("/")[-1]
    return key, filename


@router.get("/api/cases/{case_id}/download")
def api_download_case_pdf(
    case_id: int,
    user: User = Depends(require_auth),
):
    """Record exactly one **download** audit row, then stream the PDF as an attachment.

    All explicit downloads (the case-detail Download button) use this route so
    tracking stays accurate. The embedded reader uses PDF.js canvas rendering,
    which removes the browser PDF toolbar’s untrackable download control.
    """
    key, filename = _resolve_case_pdf(case_id)
    record_case_access(user.id, case_id, "download")
    return _storage_pdf_response(key, filename, attachment=True)


@router.get("/files/cases/{case_id}")
def serve_case_pdf(
    request: Request,
    case_id: int,
    download: bool = Query(False),
    user: User = Depends(require_auth),
):
    """Serve a case PDF for inline reading and log **view** events (not downloads)."""
    key, filename = _resolve_case_pdf(case_id)

    # Legacy / bookmarked ?download=1 — canonical tracking lives on /api/cases/.../download.
    if download:
        return RedirectResponse(
            url=f"/api/cases/{case_id}/download",
            status_code=302,
        )

    kind = _infer_case_pdf_access_kind(request)
    if kind is not None:
        record_case_access(user.id, case_id, kind)

    return _storage_pdf_response(key, filename, attachment=False)


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
