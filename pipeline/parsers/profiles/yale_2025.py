"""
Manual-override parser for the Yale SOM Case Book 2025.

Trigger condition (enforced by orchestrator):
    source filename contains "Yale 2025"

PAGE NUMBERS
------------
Each case opens with a title page whose printed number N appears one page
*before* the Case Introduction page (printed N+1).  The user's original index
referenced the Case Introduction pages; the correct split must start at the
title page to avoid cutting off the first page of each case.

Page numbers below are 1-indexed PDF positions, verified directly against the
PDF (see _validate_spot_checks).  Convert to fitz (0-indexed) with fitz = pdf - 1.

Front matter occupies pdf pages 1-38 (fitz 0-37); all 14 cases run from
pdf page 39 to the end of the document (pdf 186 / fitz 185).

Every produced boundary is tagged:
    detection_method    = "manual_override_yale_2025"
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

DETECTION_METHOD = "manual_override_yale_2025"

# (title, pdf_start, pdf_end)
# pdf_start / pdf_end are 1-indexed PDF page positions, verified directly.
# pdf_end = None → last page of the document.
_CASES: list[tuple[str, int, int | None]] = [
    ("Right Price Tea",                       39,  46),
    ("A Case of the Cases",                   47,  53),
    ("Eye-to-Eye",                            54,  63),
    ("How Do I Get Ranked?",                  64,  73),
    ("Foreign Sounds",                        74,  88),
    ("Outsourcing Odyssey",                   89, 102),
    ("Spruce Up Fir Real",                   103, 110),
    ("Plant-Powered Gains",                  111, 122),
    ("Shale Co.",                            123, 130),
    ("Excellence Corporation",               131, 142),
    ("Breaking Brokers",                     143, 150),
    ("Pinus Strobus Timber Investments",     151, 160),
    ("Battery Co.",                          161, 172),
    ("SkyHigh Airlines",                     173, None),   # → last page
]

_EXPECTED_CASE_COUNT = 14
_FIRST_PDF_PAGE      = 39     # pdf p39 = fitz 38 = Right Price Tea title page
_MIN_PDF_PAGES       = 186    # expected total PDF length


# Spot-checks: (pdf_page_1indexed, expected_text_fragment)
# Verified from the actual PDF to ensure page positions are correct.
_SPOT_CHECKS: list[tuple[int, str]] = [
    (39,  "Right Price Tea"),               # Right Price Tea title page
    (64,  "How Do I Get"),                  # How Do I Get Ranked? title page
    (151, "Pinus Strobus"),                 # Pinus Strobus title page
    (161, "Battery Co"),                    # Battery Co. title page
    (173, "SkyHigh Airlines"),              # SkyHigh Airlines title page
]


def _validate_spot_checks(doc: fitz.Document) -> bool:
    """Return True if every spot-check passes; log errors otherwise."""
    ok = True
    for pdf_p, fragment in _SPOT_CHECKS:
        fitz_p = pdf_p - 1
        if fitz_p >= len(doc):
            logger.error(
                "Yale 2025 spot-check: pdf p%d (fitz %d) is beyond document length %d.",
                pdf_p, fitz_p, len(doc),
            )
            ok = False
            continue
        text = doc[fitz_p].get_text("text")
        if fragment.lower() not in text.lower():
            logger.error(
                "Yale 2025 spot-check FAILED: pdf p%d should contain '%s' "
                "but got: %r",
                pdf_p, fragment, text[:120],
            )
            ok = False
        else:
            logger.debug("Yale 2025 spot-check OK: pdf p%d contains '%s'.", pdf_p, fragment)
    return ok


class Yale2025Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Yale SOM Case Book 2025."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Yale 2025 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_PDF_PAGES:
            logger.warning(
                "Yale 2025 override: PDF has only %d pages; expected %d. "
                "Later ranges may be clipped.",
                total_pages, _MIN_PDF_PAGES,
            )

        if not _validate_spot_checks(doc):
            logger.error(
                "Yale 2025 override: one or more spot-checks FAILED — "
                "page ranges may be wrong. Proceeding anyway but review output carefully."
            )

        boundaries: List[CaseBoundary] = []

        for title, pdf_start, pdf_end in _CASES:
            if pdf_start < _FIRST_PDF_PAGE:
                logger.error(
                    "Yale 2025 override: BUG — '%s' pdf_start=%d < allowed minimum %d. Skipping.",
                    title, pdf_start, _FIRST_PDF_PAGE,
                )
                continue

            fitz_start = min(pdf_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if pdf_end is None else min(pdf_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Yale 2025 override: skipping '%s' — fitz start %d > end %d after clamping.",
                    title, fitz_start, fitz_end,
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
                    f"Verified PDF pages {pdf_start}–"
                    f"{'END' if pdf_end is None else pdf_end}."
                ],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Yale 2025 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Yale 2025 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Yale 2025 override: overlap — '%s' ends pdf p%d but '%s' starts pdf p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_PDF_PAGE:
                logger.error(
                    "Yale 2025 override: '%s' starts at pdf p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_PDF_PAGE,
                )

        logger.info(
            "Yale 2025 override: %d cases, pdf pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
