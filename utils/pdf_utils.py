"""
PDF utility functions built on PyMuPDF (fitz).

All page indices throughout this module are 0-based (fitz convention).
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import List, Optional, Tuple

import fitz  # PyMuPDF

logger = logging.getLogger(__name__)


# ── Opening ───────────────────────────────────────────────────────────────────

def open_pdf_safely(path: Path) -> Tuple[Optional[fitz.Document], Optional[str]]:
    """
    Open a PDF file and return (document, None) or (None, error_message).

    Handles encrypted, corrupted, and missing files gracefully so the
    pipeline can continue processing other PDFs.
    """
    try:
        doc = fitz.open(str(path))
    except fitz.FileDataError as exc:
        return None, f"Corrupted PDF: {exc}"
    except Exception as exc:
        return None, f"Cannot open PDF: {exc}"

    if doc.is_encrypted:
        # Try the empty-string password (covers many "owner-locked" PDFs)
        if not doc.authenticate(""):
            doc.close()
            return None, "PDF is password-protected"

    return doc, None


# ── Text extraction ───────────────────────────────────────────────────────────

def extract_page_text(doc: fitz.Document, page_idx: int) -> str:
    """
    Return the plain-text content of a single page.

    Returns an empty string on any error rather than raising, so callers
    can treat missing text as a soft failure.
    """
    try:
        return doc.load_page(page_idx).get_text("text")
    except Exception as exc:
        logger.debug("text extraction failed page %d: %s", page_idx, exc)
        return ""


def extract_page_blocks(doc: fitz.Document, page_idx: int) -> List[dict]:
    """
    Return text blocks from a page, each as a dict with keys:
        x0, y0, x1, y1, text, block_no, block_type

    Only text blocks (block_type == 0) are returned.
    Image blocks are silently dropped.
    """
    try:
        raw = doc.load_page(page_idx).get_text("blocks")
        return [
            {
                "x0": b[0], "y0": b[1],
                "x1": b[2], "y1": b[3],
                "text": b[4].strip(),
                "block_no": b[5],
                "block_type": b[6],
            }
            for b in raw
            if b[6] == 0 and b[4].strip()  # text blocks only, non-empty
        ]
    except Exception as exc:
        logger.debug("block extraction failed page %d: %s", page_idx, exc)
        return []


def get_first_substantial_text(
    doc: fitz.Document,
    page_idx: int,
    min_chars: int = 5,
) -> str:
    """
    Return the text of the topmost block on a page that has ≥ min_chars.

    Useful for detecting titles that appear at the top of title pages.
    Returns "" when no qualifying block is found.
    """
    blocks = sorted(extract_page_blocks(doc, page_idx), key=lambda b: b["y0"])
    for block in blocks:
        if len(block["text"]) >= min_chars:
            return block["text"]
    return ""


def get_page_height(doc: fitz.Document, page_idx: int) -> float:
    """Return the height of a page in points (0 on error)."""
    try:
        return doc.load_page(page_idx).rect.height
    except Exception:
        return 0.0


# ── Splitting ─────────────────────────────────────────────────────────────────

def save_pdf_pages(
    source_doc: fitz.Document,
    page_start: int,
    page_end: int,
    output_path: Path,
) -> None:
    """
    Write pages [page_start, page_end] (0-indexed, inclusive) from
    source_doc into a new PDF at output_path.

    Parent directories are created automatically.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    new_doc = fitz.open()
    try:
        new_doc.insert_pdf(source_doc, from_page=page_start, to_page=page_end)
        new_doc.save(str(output_path))
        logger.debug(
            "saved pages %d–%d → %s",
            page_start + 1, page_end + 1, output_path,
        )
    finally:
        new_doc.close()


# ── Counting helpers ──────────────────────────────────────────────────────────

def count_pages_with_any_pattern(
    doc: fitz.Document,
    patterns: List[str],
    max_pages: Optional[int] = None,
) -> int:
    """
    Count pages that contain at least one string from *patterns* (case-insensitive).

    Used to detect how many pages in a PDF carry known case-section headers,
    which is a signal of a multi-case document.
    """
    patterns_lower = [p.lower() for p in patterns]
    limit = min(len(doc), max_pages) if max_pages else len(doc)
    count = 0
    for idx in range(limit):
        text_lower = extract_page_text(doc, idx).lower()
        if any(p in text_lower for p in patterns_lower):
            count += 1
    return count
