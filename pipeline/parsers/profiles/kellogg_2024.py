"""
Manual-override parser for the Kellogg School of Management Case Book 2024.

Trigger condition (enforced by orchestrator):
    source filename contains "Kellogg 2024"

Only actual case pages (starting at page 65) are emitted.
The final case (Pandora) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_kellogg_2024"
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

DETECTION_METHOD = "manual_override_kellogg_2024"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    ("Avalon",                      65,  74),
    ("Busch's Barber Shop",         75,  85),
    ("Bubbly LLC",                  86,  96),
    ("Chic Cosmetology",            97, 105),
    ("Chicouver Cycle",            106, 117),
    ("Dark Sky",                   118, 128),
    ("DigiBooks",                  129, 138),
    ("Evanston Eagles",            139, 151),
    ("Events.com",                 152, 161),
    ("Garthwaite Healthcare",      162, 169),
    ("Health Coaches",             170, 179),
    ("Healthy Foods",              180, 190),
    ("High Q Plastics",            191, 202),
    ("Kellogg Capital",            203, 215),
    ("Kellogg in India",           216, 226),
    ("Kellogg Klogs",              227, 240),
    ("Lobster Woman",              241, 253),
    ("Maine Apples",               254, 259),
    ("Money Bank Call Center",     260, 266),
    ("Montoya Soup",               267, 278),
    ("Mustard Clinic",             279, 288),
    ("Orrington Office Supplies",  289, 298),
    ("Plastic World",              299, 307),
    ("Rotisserie Ranch",           308, 314),
    ("Salty Sole Shoe",            315, 324),
    ("Sosland Sports",             325, 332),
    ("Swagger Llamas",             333, 344),
    ("Tacotle",                    345, 360),
    ("Vitality Insurance",         361, 370),
    ("Wildcat Wings",              371, 380),
    ("Wine & Co",                  381, 390),
    ("Winter Olympics Bidding",    391, 398),
    ("Zephyr Beverages",           399, 405),
    ("Zoo Co",                     406, 414),
    ("Andrew's Simple Delights",   415, 426),
    ("Pandora",                    427, None),   # → last page
]

_EXPECTED_CASE_COUNT = 36
_FIRST_CASE_PAGE     = 65
_MIN_EXPECTED_PAGES  = 427


class Kellogg2024Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Kellogg Case Book 2024."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Kellogg 2024 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Kellogg 2024 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Kellogg 2024 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Kellogg 2024 override: skipping '%s' — start p%d > end p%d after clamping.",
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
            logger.warning("Kellogg 2024 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Kellogg 2024 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Kellogg 2024 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Kellogg 2024 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Kellogg 2024 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
