"""
Manual-override parser for the Duke Fuqua Case Book 2026.

Trigger condition (enforced by orchestrator):
    source filename contains "Fuqua 2026"

Pages 1–30 are front matter and are excluded.
Swift Business (case 18) extends to the last page of the PDF.

Section 1 (cases 1–9):  New / original cases → is_duplicate_case = False
Section 2 (cases 10–18): Classic / reused cases → is_duplicate_case = True

Every produced boundary is tagged:
    detection_method    = "manual_override_fuqua_2026"
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

DETECTION_METHOD = "manual_override_fuqua_2026"

# (title, human_start, human_end)  — None → last page of PDF
_CASES: list[tuple[str, int, int | None]] = [
    # ── Section 1: New Cases ──────────────────────────────────────────────────
    ("MedTech Co.",                  31,  41),
    ("The Grass is Greener",         42,  52),
    ("BioPharma LOE",                53,  63),
    ("Breaking out of Boston",       64,  71),
    ("Big Fat Greek Problem",        72,  82),
    ("Fasten your Seatbelts",        83,  93),
    ("Tiny Ripples Coffee Co.",      94, 102),
    ("Pet Paws",                    103, 113),
    ("AI in the Clouds",            114, 124),
    # ── Section 2: Classic Cases (duplicates) ─────────────────────────────────
    ("Lactose King",                125, 134),
    ("Born for Beauty",             135, 144),
    ("MotherTech",                  145, 155),
    ("Bumpers R Us",                156, 164),
    ("A-Plus School District",      165, 174),
    ("Sardine Airlines",            175, 185),
    ("Goodbye Horses",              186, 194),
    ("Scrub Strategy",              195, 204),
    ("Swift Business",              205, None),  # → last page
]

_EXPECTED_CASE_COUNT = 18
_FIRST_CASE_PAGE     = 31
_MIN_EXPECTED_PAGES  = 205


class Fuqua2026Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Duke Fuqua Case Book 2026."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Fuqua 2026 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Fuqua 2026 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Fuqua 2026 override: BUG — '%s' starts at p%d < allowed minimum p%d. Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if human_end is None else min(human_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Fuqua 2026 override: skipping '%s' — start p%d > end p%d after clamping.",
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
            logger.warning("Fuqua 2026 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Fuqua 2026 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Fuqua 2026 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Fuqua 2026 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        logger.info(
            "Fuqua 2026 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
