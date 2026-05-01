"""
Manual-override parser for Darden School of Business Case Book 2017.

This parser ignores all heuristic detection entirely and returns a fixed list of
CaseBoundary objects derived from the verified ground-truth case index.

Trigger condition (enforced by orchestrator):
    source filename contains "Darden 2017"

Every produced boundary is tagged:
    detection_method  = "manual_override_darden_2017"
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

DETECTION_METHOD = "manual_override_darden_2017"

# ---------------------------------------------------------------------------
# Ground-truth page ranges — 1-indexed (human-readable), inclusive.
# The final entry uses None for page_end; replaced at runtime by last page.
# ---------------------------------------------------------------------------
_CASES: list[tuple[str, int, int | None]] = [
    ("Bank Savings for Savings Bank CIO",  35,  42),
    ("To Automate or not?",               43,  53),
    ("Broche Laboratories",               54,  63),
    ("CEO of Your Favorite Company",      64,  66),
    ("Copier Co.",                        67,  75),
    ("Henry's Furniture",                 76,  84),
    ("CDC Pharmaceuticals",               85,  90),
    ("World Vision",                      91,  99),
    ("Maxicure",                         100, 105),
    ("Railroad Budget Blowout",           106, 114),
    ("Saving the Payphone Company",       115, 123),
    ("Selling Laylays in Bahrain",        124, 131),
    ("Starbucks' Ice Cream Dream",        132, 138),
    ("Transportation TechCo.",            139, None),  # extends to last page of PDF
]

_MIN_EXPECTED_PAGES = 139


class Darden2017Parser(BaseCasebookParser):
    """
    Hardcoded ground-truth parser for Darden School of Business Case Book 2017.

    Returns a fixed list of CaseBoundary objects — no heuristics are run.
    """

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Darden 2017 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Darden 2017 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            fitz_start = human_start - 1
            fitz_end   = (total_pages - 1) if human_end is None else (human_end - 1)

            fitz_start = min(fitz_start, total_pages - 1)
            fitz_end   = min(fitz_end,   total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Darden 2017 override: skipping '%s' — start p%d > end p%d "
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
                confidence_notes=["Ground-truth index: exact page ranges, no heuristics."],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Darden 2017 override: produced zero boundaries.")
            return

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Darden 2017 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        first_p = boundaries[0].page_start + 1
        last_p  = boundaries[-1].page_end  + 1
        logger.info(
            "Darden 2017 override: %d cases, pages %d–%d of %d total.",
            len(boundaries), first_p, last_p, total_pages,
        )
        if last_p < total_pages:
            logger.warning(
                "Darden 2017 override: pages %d–%d are after the last case "
                "(likely appendix/back-matter — safe to ignore).",
                last_p + 1, total_pages,
            )
