"""
Exhibit authoring: mark pages of a library case as exhibits (DV-2).

Any verified user may author a case's exhibit set (community authoring —
exhibits.created_by records who; admins can re-author). Rendering happens
server-side; blobs are stored encrypted. Session-time serving of blobs and
keys is Phase 6 and lives with the practice routes — nothing here exposes
plaintext or keys.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from pipeline.storage import get_storage, to_storage_key
from webapp.auth.dependencies import require_verified_user
from webapp.auth.guest import require_auth_no_guest
from webapp.auth.users import User
from webapp.csrf import require_same_origin
from webapp.exhibits_render import page_count, render_exhibit_webp, render_page_thumb
from webapp.repositories import case_exhibits as repo
from webapp.repositories.cases import get_case_by_id
from webapp.templating import render

router = APIRouter(tags=["exhibits"])

MAX_EXHIBITS = 12


class ExhibitPage(BaseModel):
    page: int = Field(ge=1, le=500)
    source_pages: str = Field(default="", max_length=60)


class ExhibitSetBody(BaseModel):
    pages: list[ExhibitPage] = Field(max_length=MAX_EXHIBITS)


def _case_pdf_bytes(case_id: int) -> tuple[dict, bytes]:
    case = get_case_by_id(case_id)
    if case is None:
        raise HTTPException(status_code=404, detail="Case not found")
    key = to_storage_key(case["pdf_path"]) or case["pdf_path"]
    storage = get_storage()
    if not storage.exists(key):
        raise HTTPException(status_code=409, detail="Case PDF unavailable in storage")
    with storage.open(key) as fh:
        return case, fh.read()


@router.get("/cases/{case_id}/exhibits")
def authoring_page(case_id: int, request: Request,
                   user: User = Depends(require_auth_no_guest)):
    case, pdf = _case_pdf_bytes(case_id)
    return render(request, "exhibits.html", {
        "case": case,
        "n_pages": page_count(pdf),
        "existing": repo.list_for_case(case_id),
    })


@router.get("/api/cases/{case_id}/page-thumb/{page}")
async def page_thumb(case_id: int, page: int,
                     user: User = Depends(require_auth_no_guest)):
    _, pdf = _case_pdf_bytes(case_id)
    try:
        jpeg = await run_in_threadpool(render_page_thumb, pdf, page)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    return Response(jpeg, media_type="image/jpeg",
                    headers={"Cache-Control": "private, max-age=3600"})


@router.get("/api/cases/{case_id}/exhibits")
def list_exhibits(case_id: int, user: User = Depends(require_auth_no_guest)):
    if get_case_by_id(case_id) is None:
        raise HTTPException(status_code=404, detail="Case not found")
    return {"exhibits": repo.list_for_case(case_id)}


@router.post("/api/cases/{case_id}/exhibits",
             dependencies=[Depends(require_same_origin)])
async def set_exhibits(case_id: int, body: ExhibitSetBody,
                       user: User = Depends(require_verified_user)):
    """Replace the case's exhibit set with the given pages, in order."""
    if not body.pages:
        raise HTTPException(status_code=400, detail="Select at least one page")
    case, pdf = _case_pdf_bytes(case_id)
    n = page_count(pdf)

    rendered = []
    for item in body.pages:
        if item.page > n:
            raise HTTPException(status_code=400,
                                detail=f"Page {item.page} beyond {n} pages")
        webp, w, h = await run_in_threadpool(render_exhibit_webp, pdf, item.page)
        rendered.append({
            "webp": webp,
            "source_pages": item.source_pages or str(item.page),
            "width": w, "height": h,
        })

    try:
        exhibits = await run_in_threadpool(repo.replace_for_case, case_id,
                                           user.id, rendered)
    except repo.ExhibitsInUseError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return {"exhibits": exhibits}
