"""
Manual-override parser for the Booth School of Business Case Book 2021.

Trigger condition (enforced by orchestrator):
    source filename contains "Booth 2021"

Ground truth derivation
-----------------------
Page ranges come from the in-PDF "Case #N: <Title> (X/Y)" headers, which
are the canonical first/last-page-of-case markers printed on every page.
For each case, ``human_start`` is the page where ``(1/Y)`` appears and
``human_end`` is the page where ``(Y/Y)`` appears.

These match the printed TOC ("Index of Practice Cases") on pages 111-112
of the source PDF. The previous version of this table was reverse-derived
from a flaky text-search and was off by 1-3 pages on 40 of 42 cases — the
top page (case title, prompt, fit questions) was being clipped, so every
split case effectively started at "(2/Y)". The same scan also failed to
bound the final case, so Cruise Line Acquisition's split included 11
trailing pages of sponsor marketing. Both are fixed here.

Note: a few cases ((1/6), (1/5)) had the digits 6/5 mis-mapped to Greek
glyphs ϲ/ϱ in the embedded font, which is why the original automated
extraction missed them. We confirmed those cases by reading the surrounding
pages directly.

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

# (title, human_start, human_end)
# Verified against in-PDF "(1/Y)" and "(Y/Y)" headers on every page.
_CASES: list[tuple[str, int, int]] = [
    ("Army Hotel",                          113, 117),
    ("Breast Cancer Surgery",               118, 121),
    ("Burger Palace",                       122, 127),
    ("Chicken Pox Vaccine",                 128, 133),
    ("Cleaning Products",                   134, 138),
    ("Coffee and Tea Apparel",              139, 145),
    ("Commercial Vehicle OEM in China",     146, 150),
    ("Consumer Products Strategy",          151, 156),
    ("Contact Lenses",                      157, 165),
    ("Deepwater Inc.",                      166, 170),
    ("Electric Utility",                    171, 175),
    ("Elena's Electronics",                 176, 181),
    ("Finance Co",                          182, 187),
    ("French Beauty Co",                    188, 193),
    ("German Telecom",                      194, 198),
    ("Green Co",                            199, 204),
    ("GreenShield Health Insurance",        205, 210),
    ("Hawaiian Smoothies",                  211, 215),
    ("Heavy Attrition",                     216, 219),
    ("International Airlines",              220, 225),
    ("Katrina",                             226, 229),
    ("Linda's Great Burgers",               230, 234),
    ("Lola Lo's Zoo",                       235, 240),
    ("Lost Patent",                         241, 244),
    ("Midwest Machinery Co.",               245, 250),
    ("New Vaccine",                         251, 256),
    ("Payments Company",                    257, 262),
    ("Pharmaceutical Rare Disease",         263, 267),
    ("Project Gargoyle",                    268, 276),
    ("PyeongChang Winter Olympics",         277, 280),
    ("Quahog Public Schools",               281, 285),
    ("Retirement Apartment Complexes",      286, 291),
    ("Skylight Goods",                      292, 301),
    ("Smart Cards",                         302, 307),
    ("Student Health Insurance",            308, 318),
    ("Super Jr. Baby Formula",              319, 328),
    ("Apache Helicopter",                   329, 335),
    ("White Boards",                        336, 340),
    ("Telco Talks",                         341, 345),
    ("Yarmouth Yachts",                     346, 352),
    ("Sueno Mattress",                      353, 357),
    ("Cruise Line Acquisition",             358, 364),
]

_EXPECTED_CASE_COUNT = 42
_FIRST_CASE_PAGE     = 113
_MIN_EXPECTED_PAGES  = 364


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
            fitz_end   = min(human_end   - 1, total_pages - 1)

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
                confidence_notes=[
                    "Page ranges verified against in-PDF '(1/Y)' and '(Y/Y)' "
                    "case headers on every page.",
                ],
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
