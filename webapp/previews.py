"""
On-disk PNG previews for case PDFs (one image per page).

Used by ``GET /files/cases/{case_id}/preview/{n}`` so the case detail page can
show page images without loading a PDF in the browser (no untracked toolbar
download). Previews are **not** audit-logged.

PNG files live under ``output/previews/{case_id}/page-001.png`` (002, …) and are
created on first request via PyMuPDF.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

import fitz

from pipeline.storage import get_storage

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]
PREVIEWS_ROOT = REPO_ROOT / "output" / "previews"

_preview_lock = threading.Lock()


def preview_png_path(case_id: int, page_num: int) -> Path:
    """Absolute path to the cached PNG for ``page_num`` (1-based)."""
    d = PREVIEWS_ROOT / str(case_id)
    d.mkdir(parents=True, exist_ok=True)
    return d / f"page-{page_num:03d}.png"


def ensure_preview_png(case_id: int, page_num: int, storage_key: str) -> Path:
    """Return path to the PNG, rasterizing from the PDF if the file is missing."""
    out = preview_png_path(case_id, page_num)
    if out.exists() and out.stat().st_size > 0:
        return out

    with _preview_lock:
        if out.exists() and out.stat().st_size > 0:
            return out

        storage = get_storage()
        with storage.open(storage_key) as fp:
            pdf_bytes = fp.read()

        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        try:
            if page_num < 1 or page_num > doc.page_count:
                raise ValueError(
                    f"page {page_num} out of range for case {case_id} (1–{doc.page_count})"
                )
            page = doc.load_page(page_num - 1)
            mat = fitz.Matrix(2.0, 2.0)
            pix = page.get_pixmap(matrix=mat, alpha=False)
            tmp = out.with_suffix(".tmp.png")
            pix.save(str(tmp))
            tmp.replace(out)
        finally:
            doc.close()

    return out
