"""
Manual-override parser for the NYU Stern Case Book 2025.

Trigger condition (enforced by orchestrator):
    source filename contains "Stern 2025"

Pages 1–40 are front matter (intro, frameworks, casing contents, etc.) and are excluded.
Game On (case 30) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_stern_2025"
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

DETECTION_METHOD = "manual_override_stern_2025"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    ("One Man's Trash",                      41,  47),
    ("The Pricing Games",                    48,  57),
    ("Stance at a Distance",                 58,  71),
    ("Drinks Gone Flat",                     72,  79),
    ("Apple of My Eye",                      80,  87),
    ("Tres Burritos",                        88,  96),
    ("Men's Extra Comfortable Essentials",   97, 106),
    ("Adventure Capital",                   107, 114),
    ("All Night Long",                      115, 122),
    ("GGC Health",                          123, 131),
    ("Gassy Convenience",                   132, 141),
    ("The Rats Don't Run This City",        142, 150),
    ("Nook Co.",                            151, 162),
    ("Apartment Co.",                       163, 173),
    ("Sternofil",                           174, 180),
    ("Cups",                                181, 195),
    ("Fungicide",                           196, 205),
    ("Hybrid Work Model",                   206, 215),
    ("Toto Foundation",                     216, 225),
    ("WiFi in the Sky",                     226, 235),
    ("Take Your Pills",                     236, 245),
    ("Great Burger",                        246, 256),
    ("Uranus Co.",                          257, 267),
    ("Green Dreamz",                        268, 282),
    ("Dr. Stern's Botanicals",              283, 290),
    ("Mord Motor Co",                       291, 300),
    ("Curling and Careers",                 301, 308),
    ("Center Stage",                        309, 319),
    ("Pharmageddon",                        320, 329),
    ("Game On",                             330, None),  # → last page
]

_EXPECTED_CASE_COUNT = 30
_FIRST_CASE_PAGE     = 41
_MIN_EXPECTED_PAGES  = 330


class Stern2025Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the NYU Stern Case Book 2025."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Stern 2025 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Stern 2025 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Stern 2025 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Stern 2025 override: skipping '%s' — start p%d > end p%d after clamping.",
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
                confidence_notes=["Ground-truth Casing Contents: exact page ranges, no heuristics."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Stern 2025 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Stern 2025 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Stern 2025 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Stern 2025 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Stern 2025 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
