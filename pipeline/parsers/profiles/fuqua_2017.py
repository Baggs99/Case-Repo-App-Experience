"""
Manual-override parser for the Duke Fuqua Case Book 2017 (DMCC).

Trigger: source filename contains "Fuqua 2017" (orchestrator).

Ground-truth index from the printed TOC (cases start at human page 20;
TOC pages 17–19 are not included in individual case PDFs).

Human page 292 is a divider — not part of any case — between Mobilizing Your World
and Mission Eternity.

Offset check: when possible, page 20 text is probed for “YachtCo”.
"""

from __future__ import annotations

import logging
from typing import List

import fitz

from models.case import CaseBoundary
from pipeline.parsers.base import BaseCasebookParser

logger = logging.getLogger(__name__)

DETECTION_METHOD = "manual_override_fuqua_2017"

# (title, human_start_page, human_end_page_or_None, optional_file_slug)
_CASES: list[tuple[str, int, int | None, str | None]] = [
    ("YachtCo", 20, 28, "yahtco"),
    ("Dam It", 29, 36, None),
    ("Sam's Sushi", 37, 44, None),
    ("Swipe Right for Canoodle", 45, 54, None),
    ("Cackalacky Construction", 55, 63, None),
    ("Polar Bear Pool Float", 64, 74, None),
    ("Sardine Airlines", 75, 86, None),
    ("Run of the Mill", 87, 99, None),
    ("Critical Transportation", 100, 108, None),
    ("Dealer Jack's", 109, 117, None),
    ("Duck Island Beer Company", 118, 131, None),
    ("FoodXperts", 132, 138, None),
    ("NileKart", 139, 151, None),
    ("Fresher Breath", 152, 160, None),
    ("Off-Broadway Blues", 161, 168, None),
    ("Galatica's Epic Struggle", 169, 179, None),
    ("Thrill Park", 180, 192, None),
    ("Specialty Steel", 193, 200, None),
    ("Goodbye Horses", 201, 209, None),
    ("Game of Ligers", 210, 218, None),
    ("From Breakdowns to Make-Ups", 219, 231, None),
    ("Peaceful Energy", 232, 243, None),
    ("Make Airlines Great Again", 244, 256, None),
    ("Deloitte Case: DevCo", 257, 266, None),
    ("BCG Case: Pharma rare disease business growth", 267, 272, None),
    ("BCG Case: Consumer Products Strategy", 273, 279, None),
    ("Accenture Case: Surfboard Wax", 280, 285, None),
    ("Accenture Case: Mobilizing your world", 286, 291, None),
    ("Mission Eternity ('15-16)", 293, 303, None),
    ("Refinery in the Country of Georgia ('15-16)", 304, 315, None),
    ("Walter Black Industries ('15-16)", 316, 328, None),
    ("Activist Action ('15-16)", 329, 338, None),
    ("Buy Low, Sell High ('14-15)", 339, 348, None),
    ("Orange Yoga Studio ('14-15)", 349, 359, None),
    ("Coyotes ('14-15)", 360, 370, None),
    ("The Everything Retailer ('14-15)", 371, 378, None),
    ("Purple Pill Company ('14-15)", 379, 384, None),
]

_EXPECTED_CASE_COUNT = 37
_FIRST_CASE_PAGE = 20


class Fuqua2017Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Duke Fuqua Case Book 2017."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Fuqua 2017 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _FIRST_CASE_PAGE:
            logger.error(
                "Fuqua 2017: PDF has only %d pages — cannot reach first case at p%d.",
                total_pages, _FIRST_CASE_PAGE,
            )
            return []

        # Programmatic offset check (TOC page numbers == viewer indices)
        probe = doc.load_page(_FIRST_CASE_PAGE - 1).get_text()
        if "YachtCo" not in probe and "Yacht" not in probe:
            logger.warning(
                "Fuqua 2017: text on page %d does not look like YachtCo — "
                "verify PDF matches Yale/Fuqua 2017.pdf before trusting splits.",
                _FIRST_CASE_PAGE,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end, file_slug in _CASES:
            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end = (
                (total_pages - 1)
                if human_end is None
                else min(human_end - 1, total_pages - 1)
            )

            if fitz_start > fitz_end:
                logger.warning(
                    "Fuqua 2017: skipping %r — start p%d > end p%d after clamping.",
                    title, fitz_start + 1, fitz_end + 1,
                )
                continue

            boundaries.append(
                CaseBoundary(
                    title=title,
                    page_start=fitz_start,
                    page_end=fitz_end,
                    confidence=1.0,
                    detection_method=DETECTION_METHOD,
                    matched_toc_title=title,
                    matched_patterns=["manual_ground_truth_index"],
                    confidence_notes=["Ground-truth Fuqua 2017 TOC; page probe optional."],
                    needs_manual_review=False,
                    file_slug=file_slug,
                )
            )

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Fuqua 2017 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            msg = (
                f"Fuqua 2017 override: expected {_EXPECTED_CASE_COUNT} cases "
                f"but produced {len(boundaries)}."
            )
            logger.error(msg)
            raise ValueError(msg)

        by_title = {b.title: b for b in boundaries}

        def _human_span(title: str) -> tuple[int, int]:
            b = by_title[title]
            return b.page_start + 1, b.page_end + 1

        checks = [
            ("Off-Broadway Blues", 161, 168),
            ("Coyotes ('14-15)", 360, 370),
            ("Purple Pill Company ('14-15)", 379, 384),
        ]
        for title, want_start, want_end in checks:
            if title not in by_title:
                msg = f"Fuqua 2017 verify: missing case {title!r}"
                logger.error(msg)
                raise ValueError(msg)
            got_s, got_e = _human_span(title)
            if got_s != want_start or got_e != want_end:
                msg = (
                    f"Fuqua 2017 verify: {title!r} expected pages "
                    f"{want_start}–{want_end}, got {got_s}–{got_e}"
                )
                logger.error(msg)
                raise ValueError(msg)

        mob = by_title["Accenture Case: Mobilizing your world"]
        miss = by_title["Mission Eternity ('15-16)"]
        if mob.page_end + 2 != miss.page_start:
            msg = (
                "Fuqua 2017 verify: human page 292 must be excluded — "
                f"Mobilizing ends {mob.page_end + 1}, Mission starts {miss.page_start + 1}"
            )
            logger.error(msg)
            raise ValueError(msg)

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                msg = (
                    f"Fuqua 2017 overlap: {a.title!r} ends p{a.page_end + 1} "
                    f"but {b.title!r} starts p{b.page_start + 1}"
                )
                logger.error(msg)
                raise ValueError(msg)

        logger.info(
            "Fuqua 2017 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end + 1,
            total_pages,
        )
