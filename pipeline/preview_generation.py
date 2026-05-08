"""
Offline rasterisation of case PDFs to JPEG previews for the web app.

Run via ``python main.py generate-previews`` — **not** during HTTP requests.
Keeps the web tier CPU/memory flat on Render.
"""

from __future__ import annotations

from pathlib import Path

import fitz

PREVIEW_MAX_WIDTH_PX = 1200
PREVIEW_TARGET_MAX_BYTES = 150 * 1024


def preview_dir(repo_root: Path, case_id: int) -> Path:
    d = repo_root / "output" / "previews" / str(case_id)
    d.mkdir(parents=True, exist_ok=True)
    return d


def preview_jpeg_filename(page_num: int) -> str:
    return f"page-{page_num:03d}.jpg"


def _save_pixmap_jpeg_under_budget(pix: fitz.Pixmap, dest: Path, max_bytes: int) -> None:
    """Write JPEG, lowering quality until under ``max_bytes`` (best-effort)."""
    tmp = dest.with_suffix(".tmp.jpg")
    for quality in range(88, 47, -6):
        pix.save(str(tmp), output="jpeg", jpg_quality=quality)
        if tmp.stat().st_size <= max_bytes:
            tmp.replace(dest)
            return
    pix.save(str(tmp), output="jpeg", jpg_quality=46)
    tmp.replace(dest)


def rasterize_pdf_bytes_to_preview_dir(
    *,
    case_id: int,
    pdf_bytes: bytes,
    catalog_page_count: int,
    dest_root: Path,
    max_width_px: int = PREVIEW_MAX_WIDTH_PX,
    max_bytes_per_page: int = PREVIEW_TARGET_MAX_BYTES,
) -> int:
    """Render each page to ``dest_root/page-NNN.jpg``. Returns pages written.

    Pages are processed **sequentially** with one ``Document`` handle to limit
    peak memory.
    """
    out_dir = preview_dir(dest_root, case_id)
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    written = 0
    try:
        n_pdf = doc.page_count
        n = min(catalog_page_count, n_pdf) if catalog_page_count > 0 else n_pdf
        for page_num in range(1, n + 1):
            page = doc.load_page(page_num - 1)
            rect = page.rect
            if rect.width <= 0 or rect.height <= 0:
                continue
            # Fit max width; never upscale small pages (saves memory vs blowing up tiny PDFs).
            zw = min(max_width_px / rect.width, 1.0)
            mat = fitz.Matrix(zw, zw)
            pix = page.get_pixmap(matrix=mat, alpha=False)
            try:
                dest = out_dir / preview_jpeg_filename(page_num)
                _save_pixmap_jpeg_under_budget(pix, dest, max_bytes_per_page)
                written += 1
            finally:
                del pix
    finally:
        doc.close()
    return written
