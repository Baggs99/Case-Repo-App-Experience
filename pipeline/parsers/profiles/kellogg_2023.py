"""
Manual-override parser for the Kellogg School of Management Case Book 2023.

Trigger condition (enforced by orchestrator):
    source filename contains "Kellogg 2023"

Only actual case pages (starting at page 52) are emitted.
The final case (Lobster Woman) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method  = "manual_override_kellogg_2023"
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

DETECTION_METHOD = "manual_override_kellogg_2023"

_CASES: list[tuple[str, int, int | None]] = [
    ("Avalon",                      52,  61),
    ("Busch's Barber Shop",         62,  72),
    ("Bubbly LLC",                  73,  83),
    ("Chic Cosmetology",            84,  92),
    ("Chicoure Cycle",              93, 104),
    ("Dark Sky",                   105, 115),
    ("DigiBooks",                  116, 125),
    ("Events.com",                 126, 135),
    ("Garthwaite Healthcare",      136, 143),
    ("Health Coaches",             144, 153),
    ("Healthy Foods",              154, 164),
    ("High Q Plastics",            165, 176),
    ("Kellogg Capital",            177, 189),
    ("Kellogg in India",           190, 200),
    ("Kellogg Klogs",              201, 214),
    ("Maine Apples",               215, 220),
    ("Money Bank Call Center",     221, 227),
    ("Montoya Soup",               228, 239),
    ("Mustard Clinic",             240, 249),
    ("Orrington Office Supplies",  250, 259),
    ("Plastic World",              260, 268),
    ("Rotisserie Ranch",           269, 275),
    ("Salty Sole Shoe",            276, 285),
    ("Solsand Sports",             286, 293),
    ("Swagger Llamas",             294, 305),
    ("Tacotle",                    306, 321),
    ("Vitality Insurance",         322, 331),
    ("Wildcat Wings",              332, 341),
    ("Wine & Co",                  342, 351),
    ("Winter Olympics Bidding",    352, 359),
    ("Zephyr Beverages",           360, 366),
    ("Zoo Co",                     367, 375),
    ("Evanston Eagles",            376, 388),
    ("Lobster Woman",              389, None),  # → last page
]

_EXPECTED_CASE_COUNT = 34
_FIRST_CASE_PAGE     = 52
_MIN_EXPECTED_PAGES  = 389


class Kellogg2023Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Kellogg Case Book 2023."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Kellogg 2023 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Kellogg 2023 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Kellogg 2023 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Kellogg 2023 override: skipping '%s' — start p%d > end p%d after clamping.",
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
                confidence_notes=["Ground-truth TOC: exact page ranges, no heuristics."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Kellogg 2023 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Kellogg 2023 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Kellogg 2023 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Kellogg 2023 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Kellogg 2023 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
