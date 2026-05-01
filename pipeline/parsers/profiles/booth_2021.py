"""
Manual-override parser for the Booth School of Business Case Book 2021.

Trigger condition (enforced by orchestrator):
    source filename contains "Booth 2021"

Ground-truth page ranges taken from the case book TOC, with one correction:
    Breast Cancer Surgery starts at p118 (not p120 — the TOC parser missed
    the two-page intro that precedes the main case header).

The final case (Cruise Line Acquisition) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_booth_2021"
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

DETECTION_METHOD = "manual_override_booth_2021"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    ("Army Hotel",                          114, 117),
    ("Breast Cancer Surgery",               118, 121),   # fixed: was 120
    ("Burger Palace",                       125, 127),
    ("Chicken Pox Vaccine",                 129, 133),
    ("Cleaning Products",                   135, 138),
    ("Coffee and Tea Apparel",              140, 145),
    ("Commercial Vehicle OEM in China",     148, 150),
    ("Consumer Products Strategy",          152, 156),
    ("Contact Lenses",                      158, 165),
    ("Deepwater Inc.",                      167, 170),
    ("Electric Utility",                    173, 175),
    ("Elena's Electronics",                 176, 181),
    ("Finance Co",                          183, 187),
    ("French Beauty Co",                    189, 193),
    ("German Telecom",                      195, 198),
    ("Green Co",                            200, 204),
    ("GreenShield Health Insurance",        206, 210),
    ("Hawaiian Smoothies",                  212, 215),
    ("Heavy Attrition",                     217, 219),
    ("International Airlines",              221, 225),
    ("Katrina",                             227, 229),
    ("Linda's Great Burgers",               230, 234),
    ("Lola Lo's Zoo",                       236, 240),
    ("Lost Patent",                         242, 244),
    ("Midwest Machinery Co.",               246, 250),
    ("New Vaccine",                         252, 256),
    ("Payments Company",                    258, 262),
    ("Pharmaceutical Rare Disease",         264, 267),
    ("Project Gargoyle",                    269, 276),
    ("PyeongChang Winter Olympics",         278, 280),
    ("Quahog Public Schools",               282, 285),
    ("Retirement Apartment Complexes",      287, 291),
    ("Skylight Goods",                      294, 301),
    ("Smart Cards",                         303, 307),
    ("Student Health Insurance",            309, 318),
    ("Super Jr. Baby Formula",              321, 328),
    ("Apache Helicopter",                   330, 335),
    ("White Boards",                        337, 340),
    ("Telco Talks",                         342, 345),
    ("Yarmouth Yachts",                     348, 352),
    ("Sueno Mattress",                      354, 357),
    ("Cruise Line Acquisition",             361, None),  # → last page
]

_EXPECTED_CASE_COUNT = 42
_FIRST_CASE_PAGE     = 114
_MIN_EXPECTED_PAGES  = 361


class Booth2021Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Booth Case Book 2021."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Booth 2021 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Booth 2021 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Booth 2021 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Booth 2021 override: skipping '%s' — start p%d > end p%d after clamping.",
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
                confidence_notes=["Ground-truth TOC with Breast Cancer Surgery start corrected to p118."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Booth 2021 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Booth 2021 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Booth 2021 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Booth 2021 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Booth 2021 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
