"""
Manual-override parser for the Harvard Business School Case Book 2002.

Trigger condition (enforced by orchestrator):
    source filename contains "Harvard 2002"

CRITICAL PAGE OFFSET
--------------------
The index uses printed page numbers.  The actual PDF page numbers are shifted:

    PDF page = printed page + 4

    printed 34 → pdf 38   (first case)
    printed 109 → pdf 113  (last case start)

This is validated at import time: if the offset is inconsistent the module
raises ValueError immediately.

Harvard 2002 does not provide structured metadata (case_type, industry,
difficulty).  All such fields are left null; only page splits and titles are
ground-truth.

Every produced boundary is tagged:
    detection_method    = "manual_override_harvard_2002"
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

DETECTION_METHOD = "manual_override_harvard_2002"

# PDF page = printed page + this offset
_PAGE_OFFSET: int = 4

# (title, printed_start, printed_end)  — None → last page of PDF
# printed_end = next printed_start - 1; last case uses None → END_OF_DOCUMENT
_CASES: list[tuple[str, int, int | None]] = [
    ("Practice Case 1 (Retailer)",                      34,  35),
    ("Practice Case 2 (Butcher Shop)",                  36,  38),
    ("Practice Case 3 (Juice Producer)",                39,  40),
    ("Practice Case 4 (Chemical Manufacturer)",         41,  42),
    ("Practice Case 5 (Viettel)",                       43,  44),
    ("Practice Case 6 (World View)",                    45,  46),
    ("Practice Case 7 (Le Seine)",                      47,  48),
    ("Practice Case 8 (Beer Brew)",                     49,  50),
    ("Practice Case 9 (Wheeler Dealer)",                51,  52),
    ("Practice Case 10 (Travel Agency)",                53,  54),
    ("Practice Case 11 (Hospital)",                     55,  57),
    ("Practice Case 12 (E-Grocery)",                    58,  60),
    ("Practice Case 13 (Formula Producer)",             61,  63),
    ("Practice Case 14 (Pharmaceutical Company)",       64,  69),
    ("Practice Case 15 (Scotch Manufacturer)",          70,  78),
    ("Practice Case 16 (Regional Jet Corporation)",     79,  86),
    ("Practice Case 17 (British Times)",                87,  90),
    ("Practice Case 18 (Children Clothes E-Retailer)",  91,  95),
    ("Practice Case 19 (Consumer Products)",            96,  97),
    ("Practice Case 20 (The Video Store)",              98, 101),
    ("Practice Case 21 (The English Church)",          102, 103),
    ("Practice Case 22 (HBS as a Business)",           104, 105),
    ("Practice Case 23 (Fast Food Restaurant)",        106, 108),
    ("Practice Case 24 (Automobile Producer)",         109, None),  # → last page
]

_EXPECTED_CASE_COUNT  = 24
_FIRST_PRINTED_PAGE   = 34     # first printed page that contains case content
_FIRST_PDF_PAGE       = _FIRST_PRINTED_PAGE + _PAGE_OFFSET   # = 38
_MIN_EXPECTED_PDF_PAGE = 109   + _PAGE_OFFSET                 # = 113


def _validate_offset() -> None:
    """
    Confirm that every hardcoded PDF page equals its printed page + _PAGE_OFFSET.
    Raises ValueError on any mismatch so bugs are caught at import time.
    """
    spot_checks = [
        (34, 38),   # first case
        (36, 40),   # second case
        (109, 113), # last case start
    ]
    for printed, expected_pdf in spot_checks:
        computed = printed + _PAGE_OFFSET
        if computed != expected_pdf:
            raise ValueError(
                f"Harvard 2002 page offset mismatch: "
                f"printed {printed} + {_PAGE_OFFSET} = {computed}, "
                f"expected pdf {expected_pdf}.  "
                f"Fix _PAGE_OFFSET in harvard_2002.py."
            )

    # Also verify the _CASES table is self-consistent
    for title, p_start, p_end in _CASES:
        pdf_start = p_start + _PAGE_OFFSET
        if pdf_start < _FIRST_PDF_PAGE:
            raise ValueError(
                f"Harvard 2002: '{title}' printed_start={p_start} → "
                f"pdf_start={pdf_start} < allowed minimum {_FIRST_PDF_PAGE}."
            )


_validate_offset()   # runs once on import


class Harvard2002Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the Harvard Business School Case Book 2002."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using Harvard 2002 manual override parser (%d pages in PDF)", total_pages
        )

        if total_pages < _MIN_EXPECTED_PDF_PAGE:
            logger.warning(
                "Harvard 2002 override: PDF has only %d pages but the ground-truth "
                "index requires PDF page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PDF_PAGE,
            )

        boundaries: List[CaseBoundary] = []

        for title, printed_start, printed_end in _CASES:
            # Convert printed → PDF page numbers
            pdf_start = printed_start + _PAGE_OFFSET
            pdf_end   = (None if printed_end is None else printed_end + _PAGE_OFFSET)

            if pdf_start < _FIRST_PDF_PAGE:
                logger.error(
                    "Harvard 2002 override: BUG — '%s' pdf_start=%d < minimum %d. Skipping.",
                    title, pdf_start, _FIRST_PDF_PAGE,
                )
                continue

            # Convert 1-indexed human PDF pages → 0-indexed fitz pages
            fitz_start = min(pdf_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if pdf_end is None else min(pdf_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "Harvard 2002 override: skipping '%s' — fitz_start %d > fitz_end %d.",
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
                    f"Printed pages {printed_start}–"
                    f"{'END' if printed_end is None else printed_end}; "
                    f"PDF offset +{_PAGE_OFFSET}."
                ],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("Harvard 2002 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "Harvard 2002 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "Harvard 2002 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_PDF_PAGE:
                logger.error(
                    "Harvard 2002 override: '%s' starts at pdf p%d — before minimum pdf p%d!",
                    b.title, b.page_start + 1, _FIRST_PDF_PAGE,
                )

        # Confirm Practice Case 1 lands on pdf page 38
        first = boundaries[0]
        if first.page_start + 1 != _FIRST_PDF_PAGE:
            logger.error(
                "Harvard 2002 override: Practice Case 1 expected to start on pdf p%d "
                "but starts on p%d — check _PAGE_OFFSET.",
                _FIRST_PDF_PAGE, first.page_start + 1,
            )

        logger.info(
            "Harvard 2002 override: %d cases, pdf pages %d–%d of %d total. "
            "(printed pages %d–END, offset +%d)",
            len(boundaries),
            boundaries[0].page_start  + 1,
            boundaries[-1].page_end   + 1,
            total_pages,
            _FIRST_PRINTED_PAGE,
            _PAGE_OFFSET,
        )
