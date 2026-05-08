"""
PDF and preview image serving — uses the Storage abstraction (local, S3, R2, …).

Audit logging (``case_access_events``):

- ``GET /api/cases/{case_id}/download`` — records **download** (explicit save).
- ``GET /api/cases/{case_id}/open-pdf`` — records **open_tab**, then redirects to
  the inline PDF. This avoids relying on ``/files/cases/...?open_tab=1``: Chrome’s
  PDF viewer often issues Range requests that were skipped by header heuristics,
  so **open_tab** never appeared in the admin dashboard.

**Does not** log: ``GET /files/cases/{case_id}/preview/{n}`` (PNG page previews).

Legacy ``GET /files/{key}`` has no case id context — no audit rows.

Query ``?download=1`` on ``/files/cases/...`` redirects to ``/api/cases/.../download``.
"""

from __future__ import annotations

import logging
from typing import Any, Optional
from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, RedirectResponse, Response

from pipeline.storage import get_storage, to_storage_key, validate_key
from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.previews import ensure_preview_png
from webapp.repositories.case_access import record_case_access
from webapp.repositories.cases import get_case_by_id


logger = logging.getLogger(__name__)

router = APIRouter()


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


def _resolve_case_pdf(case_id: int) -> tuple[dict[str, Any], str, str]:
    """Return ``(case_row, storage_key, filename)`` or raise HTTPException."""
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
    return case, key, filename


@router.get("/api/cases/{case_id}/download")
def api_download_case_pdf(
    case_id: int,
    user: User = Depends(require_auth),
):
    """Record exactly one **download** audit row, then stream the PDF as an attachment."""
    _case, key, filename = _resolve_case_pdf(case_id)
    if not record_case_access(user.id, case_id, "download"):
        logger.error(
            "download audit insert failed user_id=%s case_id=%s — check case_access_events.kind CHECK constraint",
            user.id,
            case_id,
        )
    return _storage_pdf_response(key, filename, attachment=True)


@router.get("/api/cases/{case_id}/open-pdf")
def api_open_case_pdf_tab(
    case_id: int,
    user: User = Depends(require_auth),
):
    """Record **open_tab** once, then redirect to the inline PDF route.

    The case-detail button targets this URL — not ``/files/cases/...?open_tab=1`` —
    because the browser’s first PDF fetch is often a chunked Range request that we
    deliberately do not audit on ``/files/cases/...``.
    """
    _resolve_case_pdf(case_id)
    if not record_case_access(user.id, case_id, "open_tab"):
        logger.error(
            "open_tab audit insert failed user_id=%s case_id=%s — apply "
            "db/migrations/005_case_access_kind_constraint_fix.sql on Postgres "
            "(kind CHECK must allow open_tab)",
            user.id,
            case_id,
        )
    return RedirectResponse(url=f"/files/cases/{case_id}", status_code=302)


@router.get("/api/cases/{case_id}/previews")
def api_case_previews_manifest(
    case_id: int,
    user: User = Depends(require_auth),
):
    """JSON list of authenticated preview image URLs (same-origin paths).

    Does not write audit rows — previews are not PDF downloads.
    """
    case, _key, _filename = _resolve_case_pdf(case_id)
    raw_count = case.get("page_count")
    if raw_count is None or int(raw_count) < 1:
        return {"case_id": case_id, "page_count": 0, "urls": []}
    n = int(raw_count)
    urls = [f"/files/cases/{case_id}/preview/{i}" for i in range(1, n + 1)]
    return {"case_id": case_id, "page_count": n, "urls": urls}


@router.get("/files/cases/{case_id}/preview/{page_num:int}")
def serve_case_preview_png(
    case_id: int,
    page_num: int,
    user: User = Depends(require_auth),
):
    """Serve one cached PNG page raster. Does **not** record case access."""
    case, key, _filename = _resolve_case_pdf(case_id)
    catalog_pages = case.get("page_count")
    if catalog_pages is None:
        raise HTTPException(status_code=404, detail="Case has no page count")
    cp = int(catalog_pages)
    if page_num < 1 or page_num > cp:
        raise HTTPException(status_code=404, detail="Page not found")

    try:
        path = ensure_preview_png(case_id, page_num, key)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e)) from e
    except Exception:
        logger.exception(
            "Preview raster failed case_id=%s page=%s",
            case_id,
            page_num,
        )
        raise HTTPException(
            status_code=503,
            detail="Preview unavailable",
        ) from None

    return FileResponse(
        path,
        media_type="image/png",
        # inline display — not an attachment download
        content_disposition_type="inline",
    )


@router.get("/files/cases/{case_id}")
def serve_case_pdf(
    case_id: int,
    download: bool = Query(False),
    user: User = Depends(require_auth),
):
    """Serve the case PDF inline. Audit rows for opens use ``/api/cases/.../open-pdf``."""
    _case, key, filename = _resolve_case_pdf(case_id)

    if download:
        return RedirectResponse(
            url=f"/api/cases/{case_id}/download",
            status_code=302,
        )

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
