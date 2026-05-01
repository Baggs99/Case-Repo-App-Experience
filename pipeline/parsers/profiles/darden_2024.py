"""
Manual-override parser for the Darden School of Business Case Book 2024.

Trigger condition (enforced by orchestrator):
    source filename contains "Darden 2024" OR "Darden 2023-24 Casebook"

Pages 1–23 are front matter and are excluded.
News Co. (case 12) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_darden_2024"
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

DETECTION_METHOD = "manual_override_darden_2024"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    ("Sticky Surfactants",              24,  32),
    ("Pedal Pals",                      33,  42),
    ("Seven Flags",                     43,  52),
    ("Weasley's Wizarding Warehouse",   53,  63),
    ("Jane Darden's Ranch",             64,  73),
    ("PharmaCo",                        74,  81),
    ("Circle Bubble",                   82,  91),
    ("Shisha: Just Blowing Smoke?",     92, 102),
    ("Entertainment Co.",              103, 114),
    ("Robots Inc.",                    115, 125),
    ("Opus Two",                       126, 134),
    ("News Co.",                       135, None),  # → last page
]

_EXPECTED_CASE_COUNT = 12
_FIRST_CASE_PAGE     = 24
_MIN_EXPECTED_PAGES  = 135


class Darden2024Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Darden School of Business Case Book 2024."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Darden 2024 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Darden 2024 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Darden 2024 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Darden 2024 override: skipping '%s' — start p%d > end p%d after clamping.",
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
            logger.warning("Darden 2024 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Darden 2024 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Darden 2024 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Darden 2024 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Darden 2024 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
