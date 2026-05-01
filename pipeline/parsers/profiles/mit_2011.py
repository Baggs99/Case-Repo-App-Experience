"""
Manual-override parser for the MIT Sloan Case Book 2011.

Trigger condition (enforced by orchestrator):
    source filename contains "MIT 2011"

PAGE OFFSET — CRITICAL:
    The casebook's printed page numbers differ from PDF page numbers.
    Offset: pdf_page = printed_page - 50
    Example: printed page 56 → PDF page 6

    This parser operates exclusively on PDF page numbers.
    Printed page numbers are recorded in confidence_notes for traceability but
    are NOT used for PDF extraction.

Pages 1–5 (printed 51–55) are front matter / chapter headers and are excluded.
Dairy Farm (case 25) extends to the last page of the PDF.

Every produced boundary is tagged:
    detection_method    = "manual_override_mit_2011"
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

DETECTION_METHOD = "manual_override_mit_2011"

_PAGE_OFFSET = 50  # pdf_page = printed_page - _PAGE_OFFSET

# (title, pdf_start, pdf_end, printed_start, printed_end)
# pdf_end = None → last page of PDF
# All pdf_* values are 1-indexed (converted to 0-indexed in parse()).
_CASES: list[tuple[str, int, int | None, int, int | None]] = [
    ("Antidepressant Pricing (BCG, Round 1)",                6,   9,  56,  59),
    ("Media and Operations (BCG, Round 1)",                 10,  12,  60,  62),
    ("Zippy Snowmobiles (McKinsey, Round 1)",               13,  16,  63,  66),
    ("Bicycle Part Manufacturer (Bain, Round 1)",           17,  19,  67,  69),
    ("Pharmacy in Supermarket (Bain, Round 1)",             20,  23,  70,  73),
    ("Megabank Under-penetration (McKinsey, Round 1)",      24,  26,  74,  76),
    ("Moldovian Coffins (McKinsey, Round 1)",               27,  30,  77,  80),
    ("Fast Food Probability (McKinsey, Mock Case)",         31,  32,  81,  82),
    ("Always Fresh (BCG, Mock Case)",                       33,  36,  83,  86),
    ("Learjet (Bain, Mock Case)",                           37,  40,  87,  90),
    ("Luxury Cruise (Booz, Round 1)",                       41,  43,  91,  93),
    ("Rental Cars & Frequent Flyer Miles (BCG, Round 1)",  44,  46,  94,  96),
    ("Spanish Trains (McKinsey, Round 1)",                  47,  49,  97,  99),
    ("Store Tissue Label Manufacturer (BCG, Round 1)",      50,  51, 100, 101),
    ("Fruit Juice (Bain, Round 1)",                         52,  54, 102, 104),
    ("Art Museum (McKinsey, Round 1)",                      55,  56, 105, 106),
    ("Broadband Internet Service Provider (Bain, Round 1)", 57,  58, 107, 108),
    ("Industrial Tools Manufacturer (Bain, Round 1)",       59,  61, 109, 111),
    ("Toothpaste Company (Bain, Round 1)",                  62,  63, 112, 113),
    ("Recreational Aircraft (Bain, Round 1)",               64,  66, 114, 116),
    ("Consumer Packaged Goods (Bain, Round 1)",             67,  69, 117, 119),
    ("Domino's Pizza (Bain, Round 1)",                      70,  72, 120, 122),
    ("Credit Card Company (Bain, Round 1)",                 73,  74, 123, 124),
    ("Utility Company (Bain, Round 1)",                     75,  78, 125, 128),
    ("Dairy Farm (Bain, Round 1)",                          79, None, 129, None),
]

_EXPECTED_CASE_COUNT = 25
_FIRST_PDF_PAGE      = 6   # printed page 56
_MIN_EXPECTED_PAGES  = 79


def _validate_offset() -> None:
    """Assert that every hardcoded pdf_page equals printed_page - _PAGE_OFFSET."""
    errors = []
    for title, pdf_start, pdf_end, printed_start, printed_end in _CASES:
        expected_pdf_start = printed_start - _PAGE_OFFSET
        if pdf_start != expected_pdf_start:
            errors.append(
                f"  '{title}': pdf_start={pdf_start} but printed_start={printed_start} "
                f"- {_PAGE_OFFSET} = {expected_pdf_start}"
            )
        if pdf_end is not None and printed_end is not None:
            expected_pdf_end = printed_end - _PAGE_OFFSET
            if pdf_end != expected_pdf_end:
                errors.append(
                    f"  '{title}': pdf_end={pdf_end} but printed_end={printed_end} "
                    f"- {_PAGE_OFFSET} = {expected_pdf_end}"
                )
    if errors:
        raise ValueError(
            "MIT 2011 override: page-offset validation FAILED — "
            "hardcoded pdf_pages do not match printed_pages - 50:\n" + "\n".join(errors)
        )


# Validate at import time so any bug is caught immediately.
_validate_offset()


class MIT2011Parser(BaseCasebookParser):
    """Hardcoded ground-truth parser for the MIT Sloan Case Book 2011."""

    def can_handle(self, doc: fitz.Document, config) -> bool:
        return True

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info(
            "Using MIT 2011 manual override parser (%d pages in PDF, offset=%d)",
            total_pages, _PAGE_OFFSET,
        )

        if total_pages < _MIN_EXPECTED_PAGES:
            logger.warning(
                "MIT 2011 override: PDF has only %d pages but the ground-truth "
                "index extends to PDF page %d — later ranges may be clipped.",
                total_pages, _MIN_EXPECTED_PAGES,
            )

        boundaries: List[CaseBoundary] = []

        for title, pdf_start, pdf_end, printed_start, printed_end in _CASES:
            if pdf_start < _FIRST_PDF_PAGE:
                logger.error(
                    "MIT 2011 override: BUG — '%s' starts at PDF p%d < allowed minimum p%d. Skipping.",
                    title, pdf_start, _FIRST_PDF_PAGE,
                )
                continue

            fitz_start = min(pdf_start - 1, total_pages - 1)
            fitz_end   = (total_pages - 1) if pdf_end is None else min(pdf_end - 1, total_pages - 1)

            if fitz_start > fitz_end:
                logger.warning(
                    "MIT 2011 override: skipping '%s' — start p%d > end p%d after clamping.",
                    title, fitz_start + 1, fitz_end + 1,
                )
                continue

            printed_note = (
                f"Printed pages {printed_start}–{printed_end if printed_end else 'END'}; "
                f"offset = printed - {_PAGE_OFFSET}."
            )

            boundaries.append(CaseBoundary(
                title=title,
                page_start=fitz_start,
                page_end=fitz_end,
                confidence=1.0,
                detection_method=DETECTION_METHOD,
                matched_toc_title=title,
                matched_patterns=["manual_ground_truth_index"],
                confidence_notes=[
                    "Ground-truth TOC: exact page ranges, no heuristics.",
                    printed_note,
                ],
                needs_manual_review=False,
            ))

        self._validate(boundaries, total_pages)
        return boundaries

    @staticmethod
    def _validate(boundaries: List[CaseBoundary], total_pages: int) -> None:
        if not boundaries:
            logger.warning("MIT 2011 override: produced zero boundaries.")
            return

        if len(boundaries) != _EXPECTED_CASE_COUNT:
            logger.warning(
                "MIT 2011 override: expected %d cases but produced %d.",
                _EXPECTED_CASE_COUNT, len(boundaries),
            )

        for i in range(len(boundaries) - 1):
            a, b = boundaries[i], boundaries[i + 1]
            if a.page_end >= b.page_start:
                logger.warning(
                    "MIT 2011 override: overlap — '%s' ends p%d but '%s' starts p%d",
                    a.title, a.page_end + 1, b.title, b.page_start + 1,
                )

        for b in boundaries:
            if b.page_start + 1 < _FIRST_PDF_PAGE:
                logger.error(
                    "MIT 2011 override: '%s' starts at PDF p%d — before allowed minimum p%d!",
                    b.title, b.page_start + 1, _FIRST_PDF_PAGE,
                )

        logger.info(
            "MIT 2011 override: %d cases, PDF pages %d–%d of %d total.",
            len(boundaries),
            boundaries[0].page_start + 1,
            boundaries[-1].page_end  + 1,
            total_pages,
        )
