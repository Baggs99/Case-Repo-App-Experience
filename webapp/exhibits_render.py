"""
Server-side exhibit rendering (INTEGRATION.md DV-2): case PDF page →
WebP bytes via PyMuPDF + Pillow. Replaces the spec's client-side pdf.js
path — the server already has the PDF and the libraries.

Spec §4.4 params: 2× scale, longest edge ≤ 1800 px, WebP quality ~82.
"""

from __future__ import annotations

import io

import fitz  # PyMuPDF
from PIL import Image

MAX_EDGE = 1800
THUMB_EDGE = 320
WEBP_QUALITY = 82


def _pixmap(pdf_bytes: bytes, page_number: int, max_edge: int) -> Image.Image:
    """Render one 1-based page, scaled so the longest edge fits max_edge."""
    with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
        if not 1 <= page_number <= doc.page_count:
            raise ValueError(f"page {page_number} out of range 1..{doc.page_count}")
        page = doc[page_number - 1]
        rect = page.rect
        scale = min(2.0, max_edge / max(rect.width, rect.height))
        pix = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
        return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def render_exhibit_webp(pdf_bytes: bytes, page_number: int) -> tuple[bytes, int, int]:
    """Full-quality exhibit image. Returns (webp_bytes, width, height)."""
    img = _pixmap(pdf_bytes, page_number, MAX_EDGE)
    buf = io.BytesIO()
    img.save(buf, format="WEBP", quality=WEBP_QUALITY)
    return buf.getvalue(), img.width, img.height


def render_page_thumb(pdf_bytes: bytes, page_number: int) -> bytes:
    """Small JPEG thumb for the authoring page grid (rendered on demand —
    authoring traffic is tiny, so no preview-pipeline dependency)."""
    img = _pixmap(pdf_bytes, page_number, THUMB_EDGE)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=70)
    return buf.getvalue()


def page_count(pdf_bytes: bytes) -> int:
    with fitz.open(stream=pdf_bytes, filetype="pdf") as doc:
        return doc.page_count
