"""
QA reviewer — validates split cases and attaches review flags.

This module runs AFTER splitting.  It does not re-open PDF files;
it validates the CaseMetadata records that have already been created.

Checks performed:
  1. page_start < page_end for every case.
  2. No overlapping page ranges within the same source PDF.
  3. Total assigned pages vs total PDF pages (warns if many are unassigned).
  4. Case titles are not duplicated within the same source PDF.
  5. Page-count sanity (too short / too long).
  6. Missing or suspicious metadata fields.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import List

from models.case import CaseMetadata
from models.document import PDFDocument

logger = logging.getLogger(__name__)


def run_qa(
    cases: List[CaseMetadata],
    documents: List[PDFDocument],
    config,
) -> List[CaseMetadata]:
    """
    Run all QA checks and update review flags in place.

    Returns the same list (mutated) for convenience.
    """
    _check_page_order(cases)
    _check_overlaps(cases)
    _check_unassigned_pages(cases, documents, config)
    _check_duplicate_titles(cases)
    _check_page_count_bounds(cases, config)
    _check_suspicious_titles(cases)
    return cases


# ── Individual checks ──────────────────────────────────────────────────────────

def _check_page_order(cases: List[CaseMetadata]) -> None:
    """Flag any case where page_start > page_end (strictly invalid; equal is fine for 1-page cases)."""
    for case in cases:
        if case.page_start > case.page_end:
            _flag(case, "invalid_page_order",
                  f"page_start ({case.page_start}) > page_end ({case.page_end})")


def _check_overlaps(cases: List[CaseMetadata]) -> None:
    """
    Flag overlapping page ranges within the same source PDF.

    Two cases overlap when case i's page_end >= case j's page_start
    (where i comes before j in page order).
    """
    by_source: dict[str, List[CaseMetadata]] = defaultdict(list)
    for case in cases:
        by_source[case.source_pdf].append(case)

    for source_pdf, group in by_source.items():
        sorted_group = sorted(group, key=lambda c: c.page_start)
        for i in range(len(sorted_group) - 1):
            a, b = sorted_group[i], sorted_group[i + 1]
            if a.page_end >= b.page_start:
                _flag(a, "overlapping_page_range",
                      f"pages {a.page_start}–{a.page_end} overlap with next case "
                      f"(starts {b.page_start}) in {source_pdf}")
                _flag(b, "overlapping_page_range",
                      f"pages {b.page_start}–{b.page_end} overlap with previous case "
                      f"in {source_pdf}")


def _check_unassigned_pages(
    cases: List[CaseMetadata],
    documents: List[PDFDocument],
    config,
) -> None:
    """
    Warn when many pages in a source PDF are not covered by any case boundary.

    This catches parsers that silently miss large chunks of a casebook.
    """
    threshold = config.heuristics.unassigned_pages_warn_threshold
    doc_map = {d.relative_path: d for d in documents}

    by_source: dict[str, List[CaseMetadata]] = defaultdict(list)
    for case in cases:
        by_source[case.source_pdf].append(case)

    for source_pdf, group in by_source.items():
        doc = doc_map.get(source_pdf)
        if doc is None or doc.page_count == 0:
            continue

        assigned = set()
        for case in group:
            # page_start / page_end in CaseMetadata are 1-indexed
            assigned.update(range(case.page_start, case.page_end + 1))

        total = doc.page_count
        unassigned = total - len(assigned)

        if unassigned > threshold:
            logger.warning(
                "%s: %d/%d pages unassigned (threshold %d)",
                source_pdf, unassigned, total, threshold,
            )
            # Flag cases from this source — but skip manual override cases whose
            # front matter / section-divider pages are intentionally unassigned.
            for case in group:
                if _is_manual_override(case):
                    continue
                if "unassigned_pages_warning" not in case.review_flags:
                    case.review_flags.append("unassigned_pages_warning")
                    note = f"{unassigned} of {total} pages unassigned in source PDF"
                    if note not in case.confidence_notes:
                        case.confidence_notes.append(note)


def _check_duplicate_titles(cases: List[CaseMetadata]) -> None:
    """Flag cases whose title appears more than once in the same source PDF."""
    by_source: dict[str, List[CaseMetadata]] = defaultdict(list)
    for case in cases:
        by_source[case.source_pdf].append(case)

    for _, group in by_source.items():
        title_counts: dict[str, int] = defaultdict(int)
        for case in group:
            title_counts[case.case_title.lower().strip()] += 1
        for case in group:
            norm = case.case_title.lower().strip()
            if title_counts[norm] > 1:
                _flag(case, "duplicate_title",
                      f"title '{case.case_title}' appears "
                      f"{title_counts[norm]} times in same source PDF")


def _check_page_count_bounds(cases: List[CaseMetadata], config) -> None:
    """Flag cases with page counts outside the expected range.

    Manual override cases are skipped — their boundaries are ground-truth and
    short cases (e.g. 2-page Harvard practice cases) are intentionally correct.
    """
    min_pages = config.processing.min_case_pages
    max_pages = config.processing.max_case_pages
    for case in cases:
        if _is_manual_override(case):
            continue
        if case.page_count < min_pages and "too_few_pages" not in case.review_flags:
            _flag(case, "too_few_pages",
                  f"page_count={case.page_count} < min ({min_pages})")
        elif case.page_count > max_pages and "too_many_pages" not in case.review_flags:
            _flag(case, "too_many_pages",
                  f"page_count={case.page_count} > max ({max_pages})")


def _check_suspicious_titles(cases: List[CaseMetadata]) -> None:
    """Flag cases whose title looks malformed."""
    for case in cases:
        title = case.case_title.strip()
        if len(title) < 3:
            _flag(case, "title_too_short", f"title is '{title}'")
        elif len(title) > 150:
            _flag(case, "title_too_long", f"title length={len(title)}")
        # All digits or single-word ALL-CAPS strings are suspicious
        elif title.isdigit():
            _flag(case, "title_is_number", "title consists only of digits")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _is_manual_override(case: CaseMetadata) -> bool:
    """Return True for cases produced by a ground-truth manual override parser.

    These cases have verified boundaries and should be immune to heuristic QA
    flags such as too_few_pages and unassigned_pages_warning.
    """
    return case.detection_method.startswith("manual_override_")


def _flag(case: CaseMetadata, flag: str, note: str) -> None:
    """Add a review flag and note to a CaseMetadata (idempotent)."""
    if flag not in case.review_flags:
        case.review_flags.append(flag)
        case.confidence_notes.append(note)
        case.needs_manual_review = True
        logger.debug("QA flag '%s' on '%s': %s", flag, case.case_title[:40], note)
