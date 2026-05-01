"""
SingleCaseParser — handles PDFs that are already one case per file.

Creates a single CaseBoundary spanning the entire document.
The title comes from the filename (cleaned up) or the first substantial
text block on page 1.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import List

import fitz

from models.case import CaseBoundary
from pipeline.parsers.base import BaseCasebookParser
from utils.pdf_utils import get_first_substantial_text

logger = logging.getLogger(__name__)


class SingleCaseParser(BaseCasebookParser):
    """
    Returns a single boundary spanning the whole document.

    Used for:
    - PDFs that were classified as single_case.
    - RocketBlocks-style sources where always_single_case = True.
    - Any document where all other parsers return empty results.
    """

    name = "already_single_case"

    def can_handle(self, doc: fitz.Document, config) -> bool:  # noqa: ARG002
        return True  # Always applicable as last-resort fallback

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        if total_pages == 0:
            return []

        title = self._extract_title(doc)
        start_text = get_first_substantial_text(doc, 0)[:200]

        boundary = CaseBoundary(
            title=title,
            page_start=0,
            page_end=total_pages - 1,
            confidence=0.85,
            detection_method="already_single_case",
            matched_start_page_text=start_text,
            matched_patterns=["single_file"],
            confidence_notes=["Entire PDF treated as one case"],
        )
        logger.debug("SingleCaseParser: '%s' (%d pages)", title, total_pages)
        return [boundary]

    # ── Internal ──────────────────────────────────────────────────────────────

    @staticmethod
    def _extract_title(doc: fitz.Document) -> str:
        """
        Try to get the case title from:
        1. The PDF's internal metadata title field.
        2. The first substantial text block on page 0.
        3. A generic fallback.
        """
        meta_title = (doc.metadata or {}).get("title", "").strip()
        if meta_title and len(meta_title) > 3:
            return meta_title

        page_title = get_first_substantial_text(doc, 0, min_chars=5)
        if page_title:
            # Keep only the first line if multiline
            return page_title.splitlines()[0].strip()

        return "Untitled Case"
