"""
Manual-override parser for Darden School of Business Case Book 2021.

This parser ignores all heuristic detection entirely and returns a fixed list of
CaseBoundary objects derived from the verified ground-truth table of contents.

Trigger condition (enforced by orchestrator):
    source filename contains "Darden 2021"

IMPORTANT: only actual case pages (34–183) are emitted.
Front matter, industry overviews, and the Acknowledgements page (184) are
explicitly excluded — nothing before page 34 or after page 183 is emitted.

Every produced boundary is tagged:
    detection_method  = "manual_override_darden_2021"
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

DETECTION_METHOD = "manual_override_darden_2021"

# ---------------------------------------------------------------------------
# Ground-truth page ranges — 1-indexed (human-readable), inclusive.
# Pages 1–33 are front matter; page 184 is Acknowledgements.
# All 12 cases have explicit end pages — none extends to end-of-document.
# ---------------------------------------------------------------------------
_CASES: list[tuple[str, int, int]] = [
    ("Alpha Aviation",               34,  50),
    ("Back It On Up",                51,  62),
    ("The Big Shot",                 63,  77),
    ("Contagion Containment",        78,  89),
    ("Food Frenzy",                  90, 101),
    ("A Hairy Ordeal",              102, 115),
    ("Lizard Insurance",            116, 129),
    ("Met With Problems",           130, 139),
    ("A Messi Decision",            140, 150),
    ("New Rubber Plant Investment",  151, 160),
    ("PubU",                         161, 170),
    ("Whale Hotel",                  171, 183),  # page 184 = Acknowledgements — excluded
]

_EXPECTED_CASE_COUNT = 12
_FIRST_CASE_PAGE = 34
_LAST_CASE_PAGE  = 183   # Acknowledgements at 184 must not be included


class Darden2021Parser(BaseCasebookParser):
    """
    Hardcoded ground-truth parser for Darden School of Business Case Book 2021.

    Returns exactly 12 CaseBoundary objects covering pages 34–183.
    Nothing before page 34 or after page 183 is emitted.
    """

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Darden 2021 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _LAST_CASE_PAGE:
            logger.warning(
                "Darden 2021 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _LAST_CASE_PAGE,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Darden 2021 override: BUG — '%s' starts at p%d which is before "
                    "the first allowed case page (%d). Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            if human_end > _LAST_CASE_PAGE:
                logger.error(
                    "Darden 2021 override: BUG — '%s' ends at p%d which is after "
                    "the last allowed case page (%d). Skipping.",
                    title, human_end, _LAST_CASE_PAGE,
                )
                continue

            fitz_start = min(human_start - 1, total_pages - 1)
            fitz_end   = min(human_end   - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Darden 2021 override: skipping '%s' — start p%d > end p%d "
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
            logger.warning("Darden 2021 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Darden 2021 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Darden 2021 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Darden 2021 override: '%s' starts at p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )
            if b.page_end + 1 > _LAST_CASE_PAGE:
                logger.error(
                    "Darden 2021 override: '%s' ends at p%d — after allowed maximum p%d!",
                    b.title, b.page_end + 1, _LAST_CASE_PAGE,
                )

        logger.info(
            "Darden 2021 override: %d cases, pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
