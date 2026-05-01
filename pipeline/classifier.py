"""
Classify each PDF as one of:
  "multi_case"  — a casebook containing multiple individual cases
  "single_case" — already a single-case PDF
  "unknown"     — cannot determine; will be treated as multi_case with low confidence

The classifier is intentionally conservative: when uncertain it leans
toward "multi_case" so the parser has a chance to find boundaries,
rather than silently skipping a document.
"""

from __future__ import annotations

import logging
from typing import List, Tuple

import fitz

from models.document import PDFDocument
from utils.pdf_utils import extract_page_text, count_pages_with_any_pattern

logger = logging.getLogger(__name__)


# ── Public interface ──────────────────────────────────────────────────────────

def classify_pdf(
    doc: fitz.Document,
    config,
    filename: str,
    source_school: str = "unknown",
) -> Tuple[str, float, List[str]]:
    """
    Classify the document and return (classification, confidence, notes).

    classification : "multi_case" | "single_case" | "unknown"
    confidence     : 0.0 – 1.0
    notes          : human-readable list of signals that drove the decision
    """
    notes: List[str] = []
    page_count = len(doc)
    min_pages = config.processing.likely_casebook_min_pages
    max_single = config.processing.max_case_pages
    section_headers = list(config.section_headers.primary)
    toc_indicators = [t.lower() for t in config.section_headers.toc_indicators]

    # ── Signal 0: school/filename (checked first so it can veto everything) ───
    school_score = _school_filename_score(source_school, filename, notes)

    # Known single-case source: short-circuit before expensive PDF analysis.
    if source_school == "rocketblocks":
        return "single_case", 0.90, notes

    # ── Signal 1: page count ──────────────────────────────────────────────────
    if page_count >= min_pages:
        page_score = 0.55
        notes.append(f"page_count={page_count} ≥ multi-case threshold ({min_pages})")
    elif page_count <= max_single:
        page_score = -0.45
        notes.append(f"page_count={page_count} ≤ max single-case ({max_single})")
    else:
        page_score = 0.1
        notes.append(f"page_count={page_count} is ambiguous")

    # ── Signal 2: table of contents ───────────────────────────────────────────
    toc_found, toc_page = _detect_toc(doc, config, toc_indicators)
    if toc_found:
        notes.append(f"TOC detected on page {toc_page + 1}")
        # A TOC is nearly definitive evidence of a multi-case document.
        # Short-circuit rather than letting page-count penalties outweigh it.
        return "multi_case", 0.85, notes

    # ── Signal 3: repeated section headers ───────────────────────────────────
    # Each case tends to have a "Prompt" section, a "Clarifying Information"
    # section, etc.  Counting pages that carry any of these headers gives a
    # rough lower bound on case count.
    header_pages = count_pages_with_any_pattern(doc, section_headers)
    if header_pages >= 8:
        header_score = 0.75
        notes.append(f"{header_pages} pages carry case-section headers (strong multi-case signal)")
    elif header_pages >= 4:
        header_score = 0.55
        notes.append(f"{header_pages} pages carry case-section headers")
    elif header_pages == 2 or header_pages == 3:
        header_score = 0.30
        notes.append(f"{header_pages} pages carry case-section headers (weak signal)")
    elif header_pages == 1:
        header_score = -0.15
        notes.append("Only 1 page with a section header — likely single case")
    else:
        header_score = 0.0

    # ── Combine signals ────────────────────────────────────────────────────────
    # Any single signal above a moderate threshold is enough to call multi_case,
    # since misses are cheaper than silent skips for multi-case books.
    if page_score >= 0.50 or header_score >= 0.50:
        # Only override if school/filename doesn't strongly suggest single-case
        if school_score > -0.50:
            confidence = max(page_score, header_score)
            return "multi_case", min(confidence, 1.0), notes

    # Weighted combination for ambiguous cases
    combined = (
        header_score * 0.45
        + page_score  * 0.35
        + school_score * 0.20
    )

    logger.debug(
        "classify '%s': header=%.2f page=%.2f school=%.2f → %.2f",
        filename, header_score, page_score, school_score, combined,
    )

    if combined >= 0.25:
        return "multi_case", min(combined, 1.0), notes
    elif combined <= -0.15:
        return "single_case", min(abs(combined), 1.0), notes
    else:
        # Borderline: use page count as the tiebreaker
        if page_count <= max_single:
            notes.append("Borderline — defaulting to single_case by page count")
            return "single_case", 0.5, notes
        notes.append("Borderline — defaulting to multi_case by page count")
        return "multi_case", 0.5, notes


def classify_document(doc_record: PDFDocument, doc: fitz.Document, config) -> PDFDocument:
    """
    Run classify_pdf() and store results back into *doc_record* (mutates in place).

    Returns the same record for convenience.
    """
    classification, confidence, notes = classify_pdf(
        doc,
        config,
        filename=doc_record.filename,
        source_school=doc_record.source_school,
    )
    doc_record.classification = classification
    doc_record.classification_confidence = confidence
    doc_record.classification_notes = notes
    return doc_record


# ── Internal helpers ──────────────────────────────────────────────────────────

def _detect_toc(
    doc: fitz.Document,
    config,
    toc_indicators: List[str],
) -> Tuple[bool, int]:
    """
    Return (found, page_idx) for the first TOC-like page in the document.
    Searches only the first max_toc_search_pages pages.
    """
    max_pages = min(len(doc), config.processing.max_toc_search_pages)
    min_numeric_lines = config.heuristics.min_toc_entries

    for idx in range(max_pages):
        text_lower = extract_page_text(doc, idx).lower()

        # Primary check: explicit TOC indicator phrase
        if any(ind in text_lower for ind in toc_indicators):
            return True, idx

        # Secondary check: multiple lines ending with a page number
        # (covers TOC pages that lack a "Table of Contents" heading)
        lines = text_lower.splitlines()
        numeric_lines = sum(
            1 for line in lines
            if line.strip() and line.strip()[-1].isdigit() and len(line.strip()) > 6
        )
        if numeric_lines >= min_numeric_lines:
            return True, idx

    return False, -1


def _school_filename_score(school: str, filename: str, notes: List[str]) -> float:
    """
    Produce a small score adjustment based on school identity and filename patterns.

    RocketBlocks files are almost always already single-case.
    Descriptive case-type keywords in the filename also suggest single-case.
    """
    fn_lower = filename.lower()

    # RocketBlocks is a known single-case source
    if school == "rocketblocks":
        notes.append("RocketBlocks source → strong single-case signal")
        return -0.70

    # Filename contains case-type keywords → likely already named/single
    single_case_keywords = [
        "profitability", "market-entry", "market_entry",
        "merger", "acquisition", "growth", "pricing", "operations",
    ]
    if any(kw in fn_lower for kw in single_case_keywords):
        notes.append(f"Filename contains case-type keyword → single-case signal")
        return -0.35

    # Filename contains "casebook" or year → likely multi-case
    multi_keywords = ["casebook", "cases", "guide", "packet"]
    if any(kw in fn_lower for kw in multi_keywords):
        notes.append("Filename contains multi-case keyword")
        return 0.25

    return 0.0
