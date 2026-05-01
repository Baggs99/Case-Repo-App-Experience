"""
Manual-override parser for the Yale SOM Case Book 2024.

Trigger condition (enforced by orchestrator):
    source filename contains "Yale 2024"

Pages 1–37 are front matter (intro, index, frameworks, etc.) and are excluded.
Battery Co. (case 8) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_yale_2024"
    confidence          = 1.0
    needs_manual_review = False
"""

from __future__ import annotations

import logging
from typing import List

import fitz

from models.case import CaseBoundary
from pipeline.parsers.base import BaseCasebookParser

logger = logging.getLogger(__name__)

DETECTION_METHOD = "manual_override_yale_2024"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    ("Right Price Tea",         38,  45),
    ("Eye-to-Eye",              46,  55),
    ("How Do I Get Ranked?",    56,  65),
    ("Foreign Sounds",          66,  80),
    ("Spruce Up Fir Real",      81,  88),
    ("Plant-Powered Gains",     89, 100),
    ("Excellence Corporation", 101, 112),
    ("Battery Co.",            113, None),  # → last page
]

_EXPECTED_CASE_COUNT = 8
_FIRST_CASE_PAGE     = 38
_MIN_EXPECTED_PAGES  = 113


class Yale2024Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Yale SOM Case Book 2024."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Yale 2024 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Yale 2024 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Yale 2024 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Yale 2024 override: skipping '%s' — start p%d > end p%d after clamping.",
                    title, fitz_start + 1, fitz_end + 1,
                )
                continue

            boundaries.append(CaseBoundary(
                title=title,
                page_start=fitz_start,
                page_end=fitz_end,
                confidence=1.0,
                detection_method=DETECTION_METHOD,
                matched_toc_title=title,
                matched_patterns=["manual_ground_truth_index"],
                confidence_notes=["Ground-truth index: exact page ranges, no heuristics."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Yale 2024 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Yale 2024 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Yale 2024 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Yale 2024 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Yale 2024 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
