"""
Manual-override parser for the Kellogg School of Management Case Book 2016.

Trigger condition (enforced by orchestrator):
    source filename contains "Kellogg 2016"

Only actual case pages (starting at page 25) are emitted.
All intro / framework / TOC material before page 25 is excluded.
The final case (After School Programming) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method  = "manual_override_kellogg_2016"
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

DETECTION_METHOD = "manual_override_kellogg_2016"

# ---------------------------------------------------------------------------
# Ground-truth page ranges — 1-indexed (human-readable), inclusive.
# The final entry uses None for page_end; replaced at runtime by last page.
# Starred entries (*) are interviewer-led cases — stored in enrichment module.
# ---------------------------------------------------------------------------
_CASES: list[tuple[str, int, int | None]] = [
    ("Maine Apples",                25,  29),
    ("Kellogg in India",            30,  36),
    ("Rotisserie Ranch",            37,  43),   # * interviewer-led
    ("Tarrant Fixtures",            44,  47),
    ("Portkey Inc.",                48,  51),
    ("Salty Sole Shoe Co",          52,  58),
    ("Money Bank Call Center",      59,  64),
    ("Zephyr Beverages",            65,  68),
    ("Shermer Pharma",              69,  76),
    ("Orange Retailer",             77,  82),
    ("Vitality Insurance",          83,  89),
    ("Realty Seattle",              90,  96),
    ("Dark Sky",                    97, 104),
    ("Healthy Foods Co",           105, 111),
    ("Plastic World",              112, 118),
    ("GoNet",                      119, 123),
    ("Orrington Office Supplies",  124, 131),
    ("Winter Olympics Bidding",    132, 136),
    ("Vindaloo Corporation",       137, 144),
    ("DigiBooks",                  145, 150),
    ("Health Coaches",             151, 156),
    ("High Q Plastics",            157, 164),
    ("Zoo Co",                     165, 170),
    ("Syzygy Supercomputers",      171, 177),
    ("Thompson Healthcare",        178, 186),   # * interviewer-led
    ("Rock Energy",                187, 191),
    ("Chic Cosmetology",           192, 198),
    ("Tacotle",                    199, 211),
    ("Wine and Co",                212, 218),
    ("A+ Airline Co",              219, 224),
    ("Bell Computer",              225, 231),
    ("Montoya Soup",               232, 240),
    ("After School Programming",   241, None),  # * interviewer-led → last page
]

_EXPECTED_CASE_COUNT = 33
_FIRST_CASE_PAGE     = 25
_MIN_EXPECTED_PAGES  = 241


class Kellogg2016Parser(BaseCasebookParser):
    """
    Hardcoded ground-truth parser for the Kellogg School of Management Case Book 2016.

    Returns exactly 33 CaseBoundary objects starting at page 25.
    Nothing before page 25 is ever emitted.
    """

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Kellogg 2016 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Kellogg 2016 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Kellogg 2016 override: BUG — '%s' starts at p%d which is before "
                    "the first allowed case page (%d). Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Kellogg 2016 override: skipping '%s' — start p%d > end p%d "
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
            logger.warning("Kellogg 2016 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Kellogg 2016 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Kellogg 2016 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Kellogg 2016 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Kellogg 2016 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
