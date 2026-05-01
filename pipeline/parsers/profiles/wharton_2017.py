"""
Manual-override parser for the Wharton Casebook 2017.

Trigger condition (enforced by orchestrator):
    source filename contains "Wharton 2017"  OR  "Wharton Casebook 2017"

Only actual case pages (starting at page 9) are emitted.
Cover, TOC, and all intro material before page 9 are excluded.
The final case (Home Inspection Co) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method  = "manual_override_wharton_2017"
    confidence        = 1.0
    needs_manual_review = False
"""

from __future__ import annotations

import logging
from typing import List

import fitz

from models.case import CaseBoundary
from pipeline.parsers.base import BaseCasebookParser

logger = logging.getLogger(__name__)

DETECTION_METHOD = "manual_override_wharton_2017"

# ---------------------------------------------------------------------------
# Ground-truth page ranges — 1-indexed (human-readable), inclusive.
# The final entry uses None for page_end; replaced at runtime by last page.
# ---------------------------------------------------------------------------
_CASES: list[tuple[str, int, int | None]] = [
    ("Unicloth",                                              9,  17),
    ("Brazilian Highway Concessions",                        18,  26),
    ("Snacks Food Acquisitions",                             27,  33),
    ("US Manufacturing",                                     34,  41),
    ("Chicago Parking Meters",                               42,  54),
    ("High Engineer Attrition at SLS Oil Gas Services",      55,  67),
    ("Salt Lake City Airport",                               68,  76),
    ("Clothing Chain Acquisitions (Human Capital)",          77,  93),
    ("Pharma Outsourcing and Tech Adoption",                 94, 110),
    ("Mining Competitive Strategy",                         111, 120),
    ("Phighting Phillies",                                  121, 130),
    ("Insurance for the underserved in India",              131, 138),
    ("National Park Service",                               139, 146),
    ("Penn & Teller",                                       147, 160),
    ("Wellington Equestrian Festival",                      161, 168),
    ("Medical Devices Co",                                  169, 175),
    ("TV Screens",                                          176, 190),
    ("Home Inspection Co",                                  191, None),  # → last page
]

_EXPECTED_CASE_COUNT = 18
_FIRST_CASE_PAGE     = 9
_MIN_EXPECTED_PAGES  = 191


class Wharton2017Parser(BaseCasebookParser):
    """
    Hardcoded ground-truth parser for the Wharton Casebook 2017.

    Returns exactly 18 CaseBoundary objects starting at page 9.
    Nothing before page 9 is ever emitted.
    """

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Wharton 2017 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Wharton 2017 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Wharton 2017 override: BUG — '%s' starts at p%d which is before "
                    "the first allowed case page (%d). Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Wharton 2017 override: skipping '%s' — start p%d > end p%d "
                    "after clamping to %d-page PDF.",
                    title, fitz_start + 1, fitz_end + 1, total_pages,
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
                confidence_notes=["Ground-truth TOC: exact page ranges, no heuristics."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Wharton 2017 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Wharton 2017 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Wharton 2017 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Wharton 2017 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Wharton 2017 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
