"""
Manual-override parser for the Booth School of Business Case Book 2026.

Trigger condition (enforced by orchestrator):
    source filename contains "Booth 2026"

Pages 1–81 are front matter (intro, index pages, frameworks, etc.) and are excluded.
Cases are derived from the "Index of Practice Cases (1 of 3), (2 of 3), (3 of 3)" pages.
Telecom Co. (case 45) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_booth_2026"
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

DETECTION_METHOD = "manual_override_booth_2026"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    ("Army Hotel",                           82,  86),
    ("Breast Cancer Surgery",                87,  90),
    ("Burger Palace",                        91,  96),
    ("Chicken Pox Vaccine",                  97, 102),
    ("Cleaning Products",                   103, 107),
    ("Coffee and Tea Apparel",              108, 114),
    ("Commercial Vehicle OEM in China",     115, 119),
    ("Consumer Products Strategy",          120, 125),
    ("Contact Lenses",                      126, 134),
    ("Deepwater Inc.",                      135, 139),
    ("Electric Utility",                    140, 144),
    ("Elena's Electronics",                 145, 150),
    ("Finance Co",                          151, 156),
    ("French Beauty Co",                    157, 161),
    ("German Telecom",                      162, 166),
    ("Green Co",                            167, 172),
    ("GreenShield Health Insurance",        173, 178),
    ("Hawaiian Smoothies",                  179, 183),
    ("Heavy Attrition",                     184, 187),
    ("International Airlines",              188, 193),
    ("Katrina",                             194, 197),
    ("Linda's Great Burgers",               198, 202),
    ("Lola Lo's Zoo",                       203, 208),
    ("Lost Patent",                         209, 212),
    ("Midwest Machinery Co.",               213, 224),
    ("New Vaccine",                         225, 230),
    ("Payments Company",                    231, 237),
    ("Pharmaceutical Rare Disease",         238, 245),
    ("Project Gargoyle",                    246, 248),
    ("PyeongChang Winter Olympics",         249, 253),
    ("Quahog Public Schools",               254, 259),
    ("Retirement Apartment Complex",        260, 269),
    ("Skylight Goods",                      270, 273),
    ("Smart Cards",                         274, 275),
    ("Student Health Insurance",            276, 286),
    ("Super Jr. Baby Formula",              287, 296),
    ("Apache Helicopter",                   297, 303),
    ("White Boards",                        304, 307),
    ("Telco Talks",                         308, 313),
    ("Warmouth Yachts",                     314, 320),
    ("Sueno Mattress",                      321, 325),
    ("Cruise Line Acquisition",             326, 332),
    ("Shoe Co.",                            333, 339),
    ("Craft Co.",                           340, 344),
    ("Telecom Co.",                         345, None),  # → last page
]

_EXPECTED_CASE_COUNT = 45
_FIRST_CASE_PAGE     = 82
_MIN_EXPECTED_PAGES  = 345


class Booth2026Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Booth School of Business Case Book 2026."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Booth 2026 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Booth 2026 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Booth 2026 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Booth 2026 override: skipping '%s' — start p%d > end p%d after clamping.",
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
                confidence_notes=["Ground-truth Index of Practice Cases: exact page ranges, no heuristics."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Booth 2026 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Booth 2026 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Booth 2026 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Booth 2026 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Booth 2026 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
