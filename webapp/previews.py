"""
Case page preview images on disk under ``output/previews/{case_id}/``.

Files are **JPEG** (``page-001.jpg``, …) produced offline by
``python main.py generate-previews``. The HTTP handler does **not** rasterize
PDFs — it only serves existing files (optional legacy ``page-NNN.png``).
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[1]
PREVIEWS_ROOT = REPO_ROOT / "output" / "previews"


def existing_preview_file(case_id: int, page_num: int) -> Optional[Path]:
    """Return path to an on-disk preview, or None if not generated yet."""
    base = PREVIEWS_ROOT / str(case_id)
    jpg = base / f"page-{page_num:03d}.jpg"
    if jpg.is_file() and jpg.stat().st_size > 0:
        return jpg
    png = base / f"page-{page_num:03d}.png"
    if png.is_file() and png.stat().st_size > 0:
        return png
    return None


def preview_media_type(path: Path) -> str:
    suf = path.suffix.lower()
    if suf in (".jpg", ".jpeg"):
        return "image/jpeg"
    return "image/png"
