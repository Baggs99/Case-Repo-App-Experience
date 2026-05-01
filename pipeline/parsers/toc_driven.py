"""
TOC-driven parser — the primary boundary detector.

Strategy
--------
1. Find pages that look like a Table of Contents (first N pages).
2. Extract (title, printed_page_number) entries from those pages using
   multiple regex patterns to handle different formatting styles.
3. Detect the offset between printed page numbers and fitz 0-indexed
   page indices (many PDFs have unnumbered front-matter pages).
4. Build CaseBoundary objects: each entry starts at its printed page
   (adjusted by offset) and ends just before the next entry starts.
5. Validate every boundary: check that the start page actually contains
   text resembling the expected title; flag mismatches for manual review.

This parser produces the highest-confidence boundaries when a clean TOC
is available.  Fall back to HeaderPatternParser when it isn't.
"""

from __future__ import annotations

import logging
import re
from collections import Counter
from typing import List, Optional, Tuple

import fitz

from models.case import CaseBoundary
from pipeline.parsers.base import BaseCasebookParser
from utils.pdf_utils import extract_page_text, extract_page_blocks

logger = logging.getLogger(__name__)


# ── TOC entry regex patterns ───────────────────────────────────────────────────
#
# We try four patterns that cover the most common TOC formatting styles.
# Each pattern has exactly two capture groups:
#   group(1) → title text
#   group(2) → printed page number (digits only)
#
# The title group intentionally allows digits so cases like
# "9Lives Pet Food" or "7-Eleven Market Entry" are captured correctly.

# ── IMPORTANT: use [^\n] (not [\w\W]) in the title group so the match
# cannot span multiple lines.  MULTILINE mode makes ^ and $ match at
# line boundaries, but [\w\W] would still allow the lazy quantifier to
# consume newlines and produce spurious cross-line matches.

# The separator character class covers:
#   \.    — ASCII period (dot leader)
#   \u2026 — Unicode HORIZONTAL ELLIPSIS (…) — used by Booth and others
#   \u00b7 — MIDDLE DOT
#   \u2022 — BULLET
_SEP_CHARS = r"[.\u2026\u00b7\u2022]"

# Style 1: "Big Ten Bivalves.........23"  or  "Big Ten Bivalves………23"
_DOT_LEADER = re.compile(
    rf"^([\w\(][^\n]{{2,100}}?)\s*{_SEP_CHARS}{{2,}}\s*(\d{{1,4}})\s*$",
    re.MULTILINE,
)

# Style 2: "Big Ten Bivalves         23"  (3+ spaces as separator)
_SPACE_SEP = re.compile(
    r"^([\w\(][^\n]{2,100}?)\s{3,}(\d{1,4})\s*$",
    re.MULTILINE,
)

# Style 3: "Big Ten Bivalves\t23"  (tab-separated)
_TAB_SEP = re.compile(
    r"^([\w\(][^\n]{2,100}?)\t+(\d{1,4})\s*$",
    re.MULTILINE,
)

# Style 4: "Big Ten Bivalves  page 23"
_PAGE_KEYWORD = re.compile(
    r"^([\w\(][^\n]{2,100}?)\s+(?:page|pg\.?|p\.)\s*(\d{1,4})\s*$",
    re.MULTILINE | re.IGNORECASE,
)

# Style 5: dash leaders "Big Ten Bivalves---23"
_DASH_LEADER = re.compile(
    r"^([\w\(][^\n]{2,100}?)\s*-{3,}\s*(\d{1,4})\s*$",
    re.MULTILINE,
)

# Style 6: split-line TOC — title with trailing separator on one line,
#           page number alone on the very next line.
# Example (Booth 2021 guide TOC):
#   "Overview………………………………………………………\n4"
#   "Interview Prep……………………………………….. 10"  ← also caught by style 1
_SPLIT_LINE = re.compile(
    rf"^([\w\(][^\n]{{2,100}}?)\s*{_SEP_CHARS}{{2,}}\s*\n\s*(\d{{1,4}})\s*$",
    re.MULTILINE,
)

# Style 7: table-format TOC — page number, then case number, then title,
#           each on its own line (common in Booth case index tables).
# Example (Booth 2021 "Index of Practice Cases"):
#   "113\n1\nArmy Hotel\n..."
#   "118\n2\nBreast Cancer Surgery\n..."
# Captures: group(1) = page_num, group(2) = case_num (discarded), group(3) = title
_TABLE_FORMAT = re.compile(
    r"^(\d{1,3})\n(\d{1,2})\n([A-Z][^\n]{2,80})\n",
    re.MULTILINE,
)

# Each tuple: (compiled_pattern, title_capture_group, page_capture_group)
# All patterns except _TABLE_FORMAT have (title=1, page=2).
# _TABLE_FORMAT has (title=3, page=1) because the page number leads the line.
ALL_TOC_PATTERNS: list[tuple] = [
    (_DOT_LEADER,    1, 2),
    (_SPLIT_LINE,    1, 2),
    (_SPACE_SEP,     1, 2),
    (_TAB_SEP,       1, 2),
    (_PAGE_KEYWORD,  1, 2),
    (_DASH_LEADER,   1, 2),
    (_TABLE_FORMAT,  3, 1),
]

# Prefixes that indicate the match is NOT a case title (exhibit refs, etc.)
_SKIP_PREFIX = re.compile(
    r"^\s*(exhibit|figure|table|appendix|chart|graph|note|page|section)\b",
    re.IGNORECASE,
)

# TOC page indicator phrases (lowercase for matching)
_TOC_PHRASES = [
    "table of contents",
    "contents",
    "cases in this guide",
    "cases in this casebook",
    "index of cases",
    "case list",
    "case index",
    "list of cases",
    "index of practice cases",
    "practice case index",
    "case compendium",
]


class TocDrivenParser(BaseCasebookParser):
    """
    Detect case boundaries using an explicit Table of Contents.

    This parser is tried first for all multi-case documents.  It calls
    can_handle() before parse() so the orchestrator can skip it quickly
    when no TOC is present.
    """

    name = "toc"

    # ── Public interface ──────────────────────────────────────────────────────

    def can_handle(self, doc: fitz.Document, config) -> bool:
        """Return True when the document appears to have a TOC."""
        toc_pages = self._find_toc_pages(doc, config)
        return len(toc_pages) > 0

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        """Full TOC-driven boundary detection pipeline."""
        total_pages = len(doc)
        logger.info("TocDrivenParser: %d-page document", total_pages)

        # Step 1 — locate TOC page(s)
        toc_pages = self._find_toc_pages(doc, config)
        if not toc_pages:
            logger.warning("TocDrivenParser: no TOC pages found")
            return []
        logger.info("TOC page(s): %s", [p + 1 for p in toc_pages])

        # Step 2 — extract entries from all TOC pages
        regular_entries, table_entries = self._extract_entries(
            doc, toc_pages, config, total_pages
        )

        if not regular_entries and not table_entries:
            logger.warning("TocDrivenParser: no entries extracted from TOC")
            return []

        logger.info(
            "Extracted %d regular + %d table-format TOC entries",
            len(regular_entries), len(table_entries),
        )

        # When a casebook has an explicit case index (table-format entries)
        # alongside a prep-guide TOC (regular entries), the table entries are
        # the actual practice cases.  Use them exclusively so that guide sections
        # (Overview, Case Math, Industry Summaries …) are not emitted as cases.
        # If no table-format index exists, fall back to the regular TOC entries.
        if table_entries:
            entries = table_entries
            if regular_entries:
                logger.info(
                    "Case index found — using %d table-format entries; "
                    "skipping %d guide-section entries",
                    len(table_entries), len(regular_entries),
                )
        else:
            entries = regular_entries

        for title, pnum in entries:
            logger.debug("  entry: '%s' → page %d", title, pnum)

        # Step 3 — detect page-number offset (probe against the combined list
        # so short casebooks with only a few table entries still find a good match)
        all_entries = regular_entries + table_entries
        all_entries.sort(key=lambda e: e[1])
        offset = self._detect_offset(doc, all_entries, total_pages)
        logger.info("Page-number offset: %d", offset)

        # Step 4 — build boundaries
        boundaries = self._build_boundaries(doc, entries, offset, total_pages, config)
        logger.info("Built %d boundaries", len(boundaries))

        # Step 5 — validate + QA flag
        boundaries = self._validate(doc, boundaries, config)

        # Final safety pass
        boundaries = self._clamp_boundaries(boundaries, total_pages)
        boundaries = self._sort_boundaries(boundaries)
        return boundaries

    # ── Step 1: find TOC pages ─────────────────────────────────────────────────

    def _find_toc_pages(self, doc: fitz.Document, config) -> List[int]:
        """
        Return 0-indexed page indices that appear to be part of the TOC.

        Detection is intentionally permissive; false positives are filtered
        later when entries are extracted.
        """
        max_pages = min(len(doc), config.processing.max_toc_search_pages)
        min_numeric_lines = config.heuristics.min_toc_entries
        toc_pages: List[int] = []

        for idx in range(max_pages):
            text = extract_page_text(doc, idx)
            text_lower = text.lower()

            # Primary: explicit TOC heading
            if any(phrase in text_lower for phrase in _TOC_PHRASES):
                toc_pages.append(idx)
                logger.debug("TOC heading found on page %d", idx + 1)
                continue

            # Secondary: multiple lines ending in a number suggest a TOC
            lines = text.splitlines()
            lines_with_num = sum(
                1
                for line in lines
                if line.strip() and line.strip()[-1].isdigit() and len(line.strip()) > 6
            )
            if lines_with_num >= min_numeric_lines:
                toc_pages.append(idx)
                logger.debug(
                    "TOC candidate (numeric lines=%d) on page %d",
                    lines_with_num, idx + 1,
                )
                continue

            # Tertiary: table-format TOC — the page must have several
            # _TABLE_FORMAT matches whose printed page numbers are in
            # ascending order.  This guards against false positives from
            # case scoring-rubric pages (which have rows of "1", "2", "1"…
            # but not ascending sequential page references).
            tf_matches = _TABLE_FORMAT.findall(text)
            if len(tf_matches) >= 4:
                pg_nums = [int(m[0]) for m in tf_matches]
                # At least half the consecutive pairs must be ascending
                ascending = sum(1 for a, b in zip(pg_nums, pg_nums[1:]) if b > a)
                if len(pg_nums) < 2 or ascending >= len(pg_nums) // 2:
                    toc_pages.append(idx)
                    logger.debug(
                        "Table-format TOC candidate (%d TABLE_FORMAT matches) on page %d",
                        len(tf_matches), idx + 1,
                    )

        # Keep only runs of ≤ 10 consecutive pages
        # (some schools have 2-page case indexes, others have longer guide TOCs)
        return _filter_toc_page_runs(toc_pages, max_run=10)

    # ── Step 2: extract entries ────────────────────────────────────────────────

    def _extract_entries(
        self,
        doc: fitz.Document,
        toc_pages: List[int],
        config,
        total_pages: int,
    ) -> Tuple[List[Tuple[str, int]], List[Tuple[str, int]]]:
        """
        Return ``(regular_entries, table_format_entries)``, each a deduplicated,
        sorted list of ``(title, printed_page_number)``.

        *regular_entries*     — entries extracted by dot/space/tab/dash/keyword
                                patterns (guide TOCs, traditional casebook TOCs).
        *table_format_entries* — entries extracted by the table-format pattern
                                (e.g. Booth "Index of Practice Cases" where the
                                page number leads a three-line block).

        Keeping the two sets separate lets ``parse()`` prefer the explicit case
        index when one exists, rather than mixing guide-section entries with
        actual case entries.
        """
        min_title = config.heuristics.title_min_length
        max_title = config.heuristics.title_max_length

        seen_regular: set[str] = set()
        seen_table: set[str] = set()
        regular: List[Tuple[str, int]] = []
        table_fmt: List[Tuple[str, int]] = []

        for page_idx in toc_pages:
            text = extract_page_text(doc, page_idx)

            for pattern, title_grp, page_grp in ALL_TOC_PATTERNS:
                is_table_pattern = pattern is _TABLE_FORMAT
                for match in pattern.finditer(text):
                    raw_title = match.group(title_grp).strip()
                    page_num = int(match.group(page_grp))

                    # Reject obvious non-case lines
                    if _SKIP_PREFIX.match(raw_title):
                        continue
                    if len(raw_title) < min_title or len(raw_title) > max_title:
                        continue
                    if page_num <= 0 or page_num > total_pages + 30:
                        continue

                    title = raw_title
                    norm = title.lower().strip()

                    if is_table_pattern:
                        if norm not in seen_table:
                            seen_table.add(norm)
                            table_fmt.append((title, page_num))
                    else:
                        if norm not in seen_regular:
                            seen_regular.add(norm)
                            regular.append((title, page_num))

        regular.sort(key=lambda e: e[1])
        table_fmt.sort(key=lambda e: e[1])
        return regular, table_fmt

    # ── Step 3: detect offset ──────────────────────────────────────────────────

    def _detect_offset(
        self,
        doc: fitz.Document,
        entries: List[Tuple[str, int]],
        total_pages: int,
    ) -> int:
        """
        Compute fitz_page_idx = (printed_page_number - 1) + offset.

        Strategy: for the first few entries, search pages near the expected
        position for text that matches the title.  The most common offset
        found across all probes is returned.

        Returns 0 when detection fails (no offset assumed).
        """
        offsets: List[int] = []

        # Prefer longer, more specific titles for probing — short generic
        # words (e.g. "overview", "resources") often appear in running headers
        # on every page, which would produce a wildly wrong offset.
        # Sort by title length descending and probe the most specific ones first.
        probe_candidates = sorted(
            ((title, printed) for title, printed in entries if len(title.split()) >= 2),
            key=lambda t: len(t[0]),
            reverse=True,
        )[:8]  # Up to 8 probes

        # Fall back to unsorted entries if none have ≥ 2 words
        if not probe_candidates:
            probe_candidates = entries[:5]

        for title, printed in probe_candidates:
            expected_idx = printed - 1  # naive 0-indexed
            # Title fragment: first 30 non-whitespace chars, lowercased
            # Strip trailing punctuation so "Fast Food Co." matches headings
            # like "Case # 7 - Fast Food Co" (no trailing period).
            fragment = re.sub(r"\s+", " ", title[:30]).lower().strip().rstrip(".,;:!?")
            if len(fragment) < 6:
                continue

            # Search ±6 pages around expected position.
            # Iterate closest-to-expected first so that when a title also
            # appears in the TOC listing itself (which would be far from
            # the expected position), we prefer the actual case page.
            lo = max(0, expected_idx - 6)
            hi = min(total_pages, expected_idx + 7)
            # Sort by proximity to expected position so the actual case page
            # is found before a far-away TOC listing of the same title.
            search_order = sorted(range(lo, hi), key=lambda x: abs(x - expected_idx))
            for page_idx in search_order:
                page_text = extract_page_text(doc, page_idx).lower()
                if fragment not in page_text:
                    continue
                offset = page_idx - (printed - 1)
                offsets.append(offset)
                logger.debug(
                    "Offset probe: '%s' → found page %d, printed %d, offset %d",
                    fragment, page_idx + 1, printed, offset,
                )
                break  # One confirmation per entry is enough

        if not offsets:
            logger.debug("Offset detection: no probes succeeded; using 0")
            return 0

        mode_offset, count = Counter(offsets).most_common(1)[0]
        logger.debug(
            "Offset mode=%d (from %d/%d probes)", mode_offset, count, len(offsets)
        )
        return mode_offset

    # ── Step 4: build boundaries ───────────────────────────────────────────────

    def _build_boundaries(
        self,
        doc: fitz.Document,
        entries: List[Tuple[str, int]],
        offset: int,
        total_pages: int,
        config,
    ) -> List[CaseBoundary]:
        """
        Convert (title, printed_page_num) pairs into CaseBoundary objects.

        Case i starts at its printed page (converted to fitz index via offset)
        and ends on the page before case i+1 begins.
        The last case ends on the final page of the document.
        """
        min_pages = config.processing.min_case_pages
        boundaries: List[CaseBoundary] = []

        for i, (title, printed) in enumerate(entries):
            # Convert to 0-indexed
            page_start = (printed - 1) + offset
            page_start = max(0, min(page_start, total_pages - 1))

            if i + 1 < len(entries):
                next_printed = entries[i + 1][1]
                page_end = (next_printed - 1) + offset - 1
            else:
                page_end = total_pages - 1

            page_end = max(page_start, min(page_end, total_pages - 1))

            page_count = page_end - page_start + 1
            start_text = extract_page_text(doc, page_start)[:200]

            # ── Base confidence ───────────────────────────────────────────────
            confidence = 0.90
            notes: List[str] = []
            flags: List[str] = []

            if offset != 0:
                notes.append(f"page-number offset {offset:+d} applied")
                confidence -= 0.04

            if page_count < min_pages:
                notes.append(f"short case ({page_count} pages)")
                flags.append("too_few_pages")
                confidence -= 0.15
            elif page_count > config.processing.max_case_pages:
                notes.append(f"long case ({page_count} pages)")
                flags.append("too_many_pages")
                confidence -= 0.10

            boundary = CaseBoundary(
                title=title,
                page_start=page_start,
                page_end=page_end,
                confidence=max(0.0, min(1.0, confidence)),
                detection_method="toc",
                matched_toc_title=title,
                matched_start_page_text=start_text,
                matched_patterns=["toc_entry"],
                confidence_notes=notes,
                needs_manual_review=bool(flags),
                review_flags=flags,
            )
            boundaries.append(boundary)

        return boundaries

    # ── Step 5: validate ──────────────────────────────────────────────────────

    # A title fragment that appears within the first N characters of a page is
    # considered "prominently placed" (title-page criterion).  If it only appears
    # further in the text it is likely a running header and the boundary is wrong.
    _TITLE_PROMINENT_CHARS = 150
    _SLIDE = 3  # pages to search in each direction for auto-correction

    def _validate(
        self,
        doc: fitz.Document,
        boundaries: List[CaseBoundary],
        config,
    ) -> List[CaseBoundary]:
        """
        Cross-check each boundary against the actual page content.

        Strategy: the case title should appear *prominently* on its start page
        (within the first ~150 chars), not only as a running header buried deep
        in the text.  When the title is absent or non-prominent on the computed
        start page, a ±3-page search finds the page where it appears earliest
        and auto-corrects the boundary.  The previous boundary's end page is
        closed accordingly so no pages are orphaned.

        Remaining checks: overlaps, low overall confidence.
        """
        low_conf = config.confidence.low_confidence_threshold
        total_pages = len(doc)

        for i, b in enumerate(boundaries):
            # Strip trailing punctuation so "Fast Food Co." matches headings
            # like "Case # 7 - Fast Food Co" (no trailing period).
            fragment = re.sub(r"\s+", " ", b.title[:20]).lower().strip().rstrip(".,;:!?")
            if not fragment:
                continue

            # Position of the title fragment on the computed start page.
            start_text = extract_page_text(doc, b.page_start)
            pos_on_start = start_text.lower().find(fragment)
            is_prominent = 0 <= pos_on_start < self._TITLE_PROMINENT_CHARS

            if not is_prominent:
                # Search ±_SLIDE pages for the page where the fragment appears
                # most prominently (smallest character offset = closest to top).
                best_page: Optional[int] = None
                best_pos: float = pos_on_start if pos_on_start >= 0 else float("inf")

                lo = max(0, b.page_start - self._SLIDE)
                hi = min(total_pages, b.page_start + self._SLIDE + 1)
                for candidate in range(lo, hi):
                    if candidate == b.page_start:
                        continue
                    ctext = extract_page_text(doc, candidate).lower()
                    cpos = ctext.find(fragment)
                    if 0 <= cpos < best_pos:
                        best_pos = cpos
                        best_page = candidate

                if best_page is not None and best_pos < self._TITLE_PROMINENT_CHARS:
                    old = b.page_start
                    b.page_start = best_page
                    b.confidence_notes.append(
                        f"boundary auto-corrected p{old+1}→p{best_page+1} "
                        f"(title prominent at pos {int(best_pos)}, "
                        f"was pos {pos_on_start} on p{old+1})"
                    )
                    logger.debug(
                        "Boundary '%s': corrected start p%d→p%d (title pos %d→%d)",
                        b.title, old + 1, best_page + 1, pos_on_start, int(best_pos),
                    )
                    # Close the gap in the preceding boundary.
                    if i > 0 and boundaries[i - 1].page_end >= best_page:
                        boundaries[i - 1].page_end = best_page - 1

                    # Re-evaluate prominence on the corrected page
                    pos_on_start = int(best_pos)
                    is_prominent = pos_on_start < self._TITLE_PROMINENT_CHARS

                if not is_prominent and pos_on_start < 0:
                    b.confidence -= 0.20
                    b.confidence_notes.append(
                        f"title fragment '{fragment[:15]}' not found on start page"
                    )
                    b.review_flags.append("title_mismatch_on_start_page")
                    b.needs_manual_review = True
                elif not is_prominent:
                    # Fragment found only as a running header; no better page in window.
                    b.confidence -= 0.10
                    b.confidence_notes.append(
                        f"title appears only in running header (pos={pos_on_start})"
                    )
                    b.review_flags.append("title_mismatch_on_start_page")
                    b.needs_manual_review = True

            # Overlap check (after any correction above)
            if i + 1 < len(boundaries):
                nxt = boundaries[i + 1]
                if b.page_end >= nxt.page_start:
                    b.review_flags.append("overlapping_page_range")
                    b.needs_manual_review = True
                    b.confidence -= 0.25

            # Flag low overall confidence
            b.confidence = max(0.0, min(1.0, b.confidence))
            if b.confidence < low_conf and "low_confidence" not in b.review_flags:
                b.review_flags.append("low_confidence")
                b.needs_manual_review = True

        return boundaries


# ── Module-level helpers ───────────────────────────────────────────────────────

def _filter_toc_page_runs(pages: List[int], max_run: int = 5) -> List[int]:
    """
    Remove isolated numeric-heuristic pages that are too far from a TOC heading.

    We keep all explicitly identified TOC-heading pages and any numerically
    identified page that is within max_run pages of a heading page.

    This prevents single pages deep in the document from being mistaken for TOC.
    """
    if not pages:
        return []
    # Simple approach: keep contiguous runs of ≤ max_run pages
    result: List[int] = []
    run: List[int] = [pages[0]]
    for p in pages[1:]:
        if p - run[-1] <= 2:  # allow small gaps within a multi-page TOC
            run.append(p)
        else:
            if len(run) <= max_run:
                result.extend(run)
            run = [p]
    if len(run) <= max_run:
        result.extend(run)
    return result
