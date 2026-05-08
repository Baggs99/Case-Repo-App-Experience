"""
PDF serving — speaks to the Storage abstraction so the same route
handles local filesystem, S3, R2, Supabase, etc.

Preferred entry point for case PDFs: ``GET /files/cases/{case_id}``, which
logs per-user view/download events for the admin dashboard.

Legacy ``GET /files/{key}`` remains for backward compatibility but does
not write audit rows (no case id context).
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal, Optional
from urllib.parse import unquote

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, RedirectResponse

from pipeline.storage import get_storage, to_storage_key, validate_key
from webapp.auth.dependencies import require_auth
from webapp.auth.users import User
from webapp.repositories.case_access import (
    get_last_case_access_event,
    record_case_access,
)
from webapp.repositories.cases import get_case_by_id


router = APIRouter()

# ``?embed=1`` full GET after a ``view`` row: likely toolbar Save (same URL as iframe).
# Too wide → false “download” on a quick return visit; too narrow → missed toolbar saves.
_EMBED_VIEW_TO_DOWNLOAD_SEC = 300
# Chrome sometimes issues another ``?embed=1`` full GET within seconds after a toolbar
# ``download``. Keep this tight: opening the iframe shortly after the white Download
# button also follows a ``download`` row and must log ``view``.
_EMBED_REPEAT_DOWNLOAD_SEC = 25


def _seconds_since_utc(ts: datetime) -> float:
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - ts).total_seconds()


def _infer_case_pdf_access_kind(
    request: Request,
    *,
    user_id: int,
    case_id: int,
    download_query: bool,
) -> Optional[Literal["view", "download"]]:
    """Classify this request for audit logging.

    We tag **inline reading** URLs with ``?embed=1`` (iframe + “Open in new tab”).

    Chrome’s embedded PDF viewer often **reuses that same ``?embed=1`` URL** when
    the user clicks its toolbar Download — after we’ve already logged the first
    load as **view**. We look at the **latest** audit row: a fresh ``view`` within
    a reading window → **download**; a **recent** ``download`` → another toolbar
    save; otherwise this fetch is a new **view** (e.g. returning after saving).

    Toolbar saves that issue a GET **without** ``embed`` still count as **download**.

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
    embed_true = embed_raw is not None and embed_raw.strip().lower() in (
        "1", "true", "yes",
    )
    if embed_true:
        # Second full fetch with the iframe URL (same ?embed=1) is usually toolbar Save.
        if range_hdr:
            return "view"
        last = get_last_case_access_event(user_id, case_id)
        if last is None:
            return "view"
        kind, ts = last
        try:
            age = _seconds_since_utc(ts)
        except (TypeError, ValueError, OSError):
            age = 0.0

        # Another full ``?embed=1`` immediately after a toolbar ``download`` row (chained saves).
        if kind == "download" and age <= _EMBED_REPEAT_DOWNLOAD_SEC:
            return "download"
        # Inline load was logged as view; next full ?embed=1 fetch is often Save.
        if kind == "view" and age <= _EMBED_VIEW_TO_DOWNLOAD_SEC:
            return "download"
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

    kind = _infer_case_pdf_access_kind(
        request,
        user_id=user.id,
        case_id=case_id,
        download_query=download,
    )
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
