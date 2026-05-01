"""
Manual-override parser for the NYU Stern Case Book 2021.

Trigger condition (enforced by orchestrator):
    source filename contains "Stern 2021"

Pages 1–42 are front matter (intro, frameworks, list of cases, etc.) and are excluded.
Cups (case 25) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_stern_2021"
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

DETECTION_METHOD = "manual_override_stern_2021"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    ("The Pricing Games",                    43,  52),
    ("Kungide",                              53,  62),
    ("Men's Extra Comfortable Essentials",   63,  72),
    ("Dirty (Hot) Dogs",                     73,  81),
    ("WiFi in the Sky",                      82,  91),
    ("Tres Burritos",                        92, 100),
    ("FlashPro",                            101, 110),
    ("Uranus Co.",                          111, 121),
    ("Stance at a Distance",               122, 135),
    ("Grad-U-Date",                         136, 145),
    ("Get-Health",                          146, 153),
    ("Hook Co.",                            154, 165),
    ("Chocolate",                           166, 170),
    ("Royal Cinema",                        171, 180),
    ("Adventure Capital",                   181, 188),
    ("Steel Co.",                           189, 197),
    ("All Night Long",                      198, 203),
    ("Is Teleconferencing a Good Call?",    204, 212),
    ("Apple of My Eye",                     213, 220),
    ("Jimmy's Dilemma",                     221, 231),
    ("Apartment Co.",                       232, 242),
    ("Great Burger",                        243, 253),
    ("Drinks Gone Flat",                    254, 261),
    ("Tofu Foundation",                     262, 271),
    ("Cups",                                272, None),  # → last page
]

_EXPECTED_CASE_COUNT = 25
_FIRST_CASE_PAGE     = 43
_MIN_EXPECTED_PAGES  = 272


class Stern2021Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the NYU Stern Case Book 2021."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Stern 2021 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Stern 2021 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Stern 2021 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Stern 2021 override: skipping '%s' — start p%d > end p%d after clamping.",
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
                confidence_notes=["Ground-truth list of cases: exact page ranges, no heuristics."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Stern 2021 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Stern 2021 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Stern 2021 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Stern 2021 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Stern 2021 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
