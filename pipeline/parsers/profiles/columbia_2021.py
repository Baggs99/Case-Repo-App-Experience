"""
Manual-override parser for Columbia Business School Case Book 2021.

This parser ignores all heuristic detection entirely and returns a fixed list of
CaseBoundary objects derived from the verified ground-truth case index.

Trigger condition (enforced by orchestrator):
    source filename contains "Columbia 2021"

Every produced boundary is tagged:
    detection_method  = "manual_override_columbia_2021"
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

DETECTION_METHOD = "manual_override_columbia_2021"

# ---------------------------------------------------------------------------
# Ground-truth page ranges — 1-indexed (human-readable), inclusive.
# The final entry uses None for page_end; it will be replaced at runtime
# by the last page of the actual PDF so we never hard-code a stale value.
# ---------------------------------------------------------------------------
_CASES: list[tuple[str, int, int | None]] = [
    ("Ban the Box",                    21,  28),
    ("Cheers",                         29,  35),
    ("Combating Climate Change",       36,  43),
    ("Co-V(id)accinated",              44,  58),
    ("Dam Dam Dam",                    59,  66),
    ("Dizzy Fruits",                   67,  75),
    ("Dust Cloud",                     76,  83),
    ("Echo Yankee Game",               84,  89),
    ("EduCo",                          90,  99),
    ("Explorer Bank",                 100, 107),
    ("Fintech Startup",               108, 119),
    ("Funeral Homes",                 120, 128),
    ("Grocer Prepared Foods",         129, 136),
    ("Housing Authority Goes Green",  137, 146),
    ("Insta-Famous",                  147, 154),
    ("MTA Subway",                    155, 160),
    ("NeuroNow",                      161, 169),
    ("Optic-Eye",                     170, 178),
    ("Packaging Cost Reduction",      179, 184),
    ("PanDan Diplomacy",              185, 193),
    ("Pay Me My Money, In Cash",      194, 200),
    ("Race to 270",                   201, 211),
    ("SeaBag Marina",                 212, 219),
    ("Sparkle Co.",                   220, 229),
    ("ST Boat Sale",                  230, 235),
    ("The Greatest Show on Earth",    236, 243),
    ("The Home of Gnome",             244, 252),
    ("Timeless Watches",              253, 260),
    ("TriBeCa Branding",              261, 268),
    ("Alkaline Ash",                  269, 275),
    ("Car Wash Chain",                276, 283),
    ("Lion King Bank",                284, 290),
    ("Madecasse",                     291, 298),
    ("Pre-K Education",               299, 305),
    ("Swedish Death Metal",           306, 312),
    ("Timber Crisis",                 313, 317),
    ("Traditional Toy Maker",         318, 324),
    ("Tristar Home Appliances",       325, None),  # extends to last page of PDF
]

# Lowest human page number that must exist for the ranges to make sense.
_MIN_EXPECTED_PAGES = 325


class Columbia2021Parser(BaseCasebookParser):
    """
    Hardcoded ground-truth parser for Columbia Business School Case Book 2021.

    Returns a fixed list of CaseBoundary objects — no heuristics are run.
    The parser still validates the resulting list (overlap check, page-count
    sanity) and logs any anomalies so they surface immediately.
    """

    def can_handle(self, doc: fitz.Document, config) -> bool:
        """Always True — the orchestrator only invokes this parser intentionally."""
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Columbia 2021 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Columbia 2021 override: PDF has only %d pages but the ground-truth "
                "index extends to page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, human_start, human_end in _CASES:
            # Convert 1-indexed human pages → 0-indexed fitz pages.
            fitz_start = human_start - 1
            fitz_end   = (total_pages - 1) if human_end is None else (human_end - 1)

            # Clamp to actual document length in case the PDF was truncated.
            fitz_start = min(fitz_start, total_pages - 1)
            fitz_end   = min(fitz_end,   total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Columbia 2021 override: skipping '%s' — start p%d > end p%d "
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

    # ── Internal helpers ──────────────────────────────────────────────────────

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        """Log warnings for overlaps and coverage gaps; does not mutate boundaries."""
        if not boundaries:
            logger.warning("Columbia 2021 override: produced zero boundaries.")
            return

        # Check for overlapping adjacent ranges.
        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Columbia 2021 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        # Report coverage.
        first_p = boundaries[0].page_start + 1
        last_p  = boundaries[-1].page_end  + 1
        logger.info(
            "Columbia 2021 override: %d cases, pages %d–%d of %d total.",
            len(boundaries), first_p, last_p, total_pages,
        )
        if last_p < total_pages:
            logger.warning(
                "Columbia 2021 override: pages %d–%d are after the last case "
                "(likely appendix/back-matter — safe to ignore).",
                last_p + 1, total_pages,
            )
