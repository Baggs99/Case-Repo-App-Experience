"""
Manual-override parser for the Ross School of Business Case Book 2022.

Trigger condition (enforced by orchestrator):
    source filename contains "Ross 2022"

Only actual case pages (starting at page 26) are emitted.
Pages 1–25 are front matter (TOC, admin guides, etc.) and are excluded.
New England Trucks extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method  = "manual_override_ross_2022"
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

DETECTION_METHOD = "manual_override_ross_2022"

_CASES: list[tuple[str, int, int | None]] = [
    ("Gaming Challenges",          26,  36),
    ("Household Cleaners Growth",  37,  43),
    ("Little Bud Co.",             44,  49),
    ("GasCo Goes the Distance",    50,  58),
    ("Rubicon Co.",                59,  71),
    ("Spice Up Your Life",         72,  82),
    ("Apogee Bank",                83,  94),
    ("Attack Helicopter",          95, 101),
    ("FLC Sports League",         102, 110),
    ("Marie's Café",              111, 120),
    ("Midwest Hospital",          121, 131),
    ("EuroRail",                  132, 139),
    ("DoWork",                    140, 151),
    ("Banana Heaven",             152, 158),
    ("One Tree Hill",             159, 168),
    ("Alternative Milk",          169, 176),
    ("Jab We Profit",             177, 186),
    ("New England Trucks",        187, None),  # → last page
]

_EXPECTED_CASE_COUNT = 18
_FIRST_CASE_PAGE     = 26
_MIN_EXPECTED_PAGES  = 187


class Ross2022Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Ross School of Business Case Book 2022."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Ross 2022 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Ross 2022 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Ross 2022 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Ross 2022 override: skipping '%s' — start p%d > end p%d after clamping.",
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
            logger.warning("Ross 2022 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Ross 2022 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Ross 2022 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Ross 2022 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Ross 2022 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
