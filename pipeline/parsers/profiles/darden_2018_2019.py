"""
Manual-override parser for Darden School of Business Case Book 2018–2019.

This parser ignores all heuristic detection entirely and returns a fixed list of
CaseBoundary objects derived from the verified ground-truth case index.

Trigger condition (enforced by orchestrator):
    source filename contains "Darden 2019"  OR  "Darden 2018-2019"

IMPORTANT: only actual case pages (starting at page 48) are emitted.
Front matter, section dividers, and non-case pages are explicitly excluded.

Every produced boundary is tagged:
    detection_method  = "manual_override_darden_2018_2019"
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

DETECTION_METHOD = "manual_override_darden_2018_2019"

# ---------------------------------------------------------------------------
# Ground-truth page ranges — 1-indexed (human-readable), inclusive.
# Pages 1–47 are front matter / section dividers and are deliberately omitted.
# The final entry uses None for page_end; replaced at runtime by last page.
# ---------------------------------------------------------------------------
_CASES: list[tuple[str, int, int | None]] = [
    # ── New 2019 Darden Cases ────────────────────────────────────────────────
    ("National Express Trucking",    48,  57),
    ("Styrofoam Situation",          58,  67),
    ("North-South Pharma",           68,  82),
    ("Fire Proof Inc.",              83,  92),
    ("Quality Bottling Co.",         93, 104),
    ("Canyon Capital",              105, 113),
    # ── Updated Darden Cases ─────────────────────────────────────────────────
    ("Transportation Tech Co.",     114, 125),
    ("Lonely Gas Station",          126, 135),
    ("Copier Co.",                  136, 146),
    ("Maxicure",                    147, 155),
    ("To Automate or Not",          156, 166),
    ("Rubber Bumper Laboratories",  167, None),  # extends to last page of PDF
]

# Lowest human page number that must be present for boundaries to make sense.
_MIN_EXPECTED_PAGES = 167

# No case should ever start before this human page.
_FIRST_CASE_PAGE = 48


class Darden2018_2019Parser(BaseCasebookParser):
    """
    Hardcoded ground-truth parser for Darden School of Business Case Book 2018–2019.

    Returns exactly 12 CaseBoundary objects covering pages 48–EOF.
    Nothing before page 48 (cover, front matter, section dividers) is emitted.
    """

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Darden 2018-2019 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Darden 2018-2019 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            # Safety guard: never emit anything before the first case page.
            if human_start < _FIRST_CASE_PAGE:
                logger.error(
                    "Darden 2018-2019 override: BUG — '%s' starts at p%d which is "
                    "before the first allowed case page (%d). Skipping.",
                    title, human_start, _FIRST_CASE_PAGE,
                )
                continue

            fitz_start = human_start - 1
            fitz_end   = (total_pages - 1) if human_end is None else (human_end - 1)

            fitz_start = min(fitz_start, total_pages - 1)
            fitz_end   = min(fitz_end,   total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Darden 2018-2019 override: skipping '%s' — start p%d > end p%d "
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
            logger.warning("Darden 2018-2019 override: produced zero boundaries.")
            return

        expected = len(_CASES)
        if len(boundaries) != expected:
            logger.warning(
                "Darden 2018-2019 override: expected %d cases but produced %d.",
                expected, len(boundaries),
            )

        # Overlap check.
        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Darden 2018-2019 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        # Guard: no case before _FIRST_CASE_PAGE.
        for b in boundaries:
            if b.page_start + 1 < _FIRST_CASE_PAGE:
                logger.error(
                    "Darden 2018-2019 override: '%s' starts at p%d — before "
                    "the allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_CASE_PAGE,
                )

        first_p = boundaries[0].page_start + 1
        last_p  = boundaries[-1].page_end  + 1
        logger.info(
            "Darden 2018-2019 override: %d cases, pages %d–%d of %d total.",
            len(boundaries), first_p, last_p, total_pages,
        )
        if last_p < total_pages:
            logger.warning(
                "Darden 2018-2019 override: pages %d–%d are after the last case "
                "(likely appendix/back-matter — safe to ignore).",
                last_p + 1, total_pages,
            )
