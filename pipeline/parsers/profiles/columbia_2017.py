"""
Manual-override parser for Columbia MCA Case Book 2017.

This parser ignores all heuristic detection entirely and returns a fixed list of
CaseBoundary objects derived from the verified ground-truth case index.

Trigger condition (enforced by orchestrator):
    source filename contains "Columbia 2017"  OR  "MCA Case Book 2017"

Every produced boundary is tagged:
    detection_method  = "manual_override_columbia_2017"
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

DETECTION_METHOD = "manual_override_columbia_2017"

# ---------------------------------------------------------------------------
# Ground-truth page ranges — 1-indexed (human-readable), inclusive.
# The final entry uses None for page_end; it will be replaced at runtime
# by the last page of the actual PDF so we never hard-code a stale value.
# ---------------------------------------------------------------------------
_CASES: list[tuple[str, int, int | None]] = [
    ("Alkaline Ash",                    28,  35),
    ("Boston Office Supplies",          36,  41),
    ("California Parking Lot",          42,  50),
    ("Car Wash Chain",                  51,  58),
    ("Carbon Fiber Manufacturer",       59,  64),
    ("Cow Dairy Milk",                  65,  69),
    ("Fast Food Co.",                   70,  74),
    ("Frozen Food Co.",                 75,  82),
    ("Grocery Store",                   83,  90),
    ("Hotel Ocho",                      91,  97),
    ("Ice Cream Co.",                   98, 103),
    ("Life Insurance Merger",          104, 109),
    ("Lubricant Manufacturer",         110, 115),
    ("Oil and Gas Acquisition",        116, 120),
    ("Outsourced School Food Service", 121, 125),
    ("Personal Care Company",          126, 130),
    ("Pharma Co.",                     131, 136),
    ("Population Health Management",   137, 141),
    ("Portable Sanitation",            142, 147),
    ("Pre-K Education",                148, 156),
    ("Rock Band",                      157, 164),
    ("Soda Ash Producer",              165, 173),
    ("Tristar Home Appliances",        174, 183),
    ("Veratech",                       184, None),  # extends to last page of PDF
]

# Lowest human page number that must exist for the ranges to make sense.
_MIN_EXPECTED_PAGES = 184


class Columbia2017Parser(BaseCasebookParser):
    """
    Hardcoded ground-truth parser for Columbia MCA Case Book 2017.

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
            "Using Columbia 2017 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "Columbia 2017 override: PDF has only %d pages but the ground-truth "
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
                    "Columbia 2017 override: skipping '%s' — start p%d > end p%d "
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
            logger.warning("Columbia 2017 override: produced zero boundaries.")
            return

        # Check for overlapping adjacent ranges.
        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Columbia 2017 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        # Report coverage.
        first_p = boundaries[0].page_start + 1
        last_p  = boundaries[-1].page_end  + 1
        logger.info(
            "Columbia 2017 override: %d cases, pages %d–%d of %d total.",
            len(boundaries), first_p, last_p, total_pages,
        )
        if last_p < total_pages:
            logger.warning(
                "Columbia 2017 override: pages %d–%d are after the last case "
                "(likely appendix/back-matter — safe to ignore).",
                last_p + 1, total_pages,
            )
