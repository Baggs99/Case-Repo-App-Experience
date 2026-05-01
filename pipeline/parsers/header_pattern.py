"""
Header-pattern parser — fallback boundary detector for casebooks without a TOC.

Strategy
--------
For each page, compute a "title-page score" based on layout and content signals:
  + Very little text on the page (title pages are sparse)
  + First text block is near the top and looks like a title
  + Page contains metadata-like labels (Industry:, Type:, etc.)
  + The page does NOT contain mid-case section headers
  + At least one of the following few pages carries known section headers

Pages that exceed the score threshold become case-start candidates.
Candidates that are too close together (< min_case_pages apart) are
pruned so we don't produce many tiny fragments.

The end of each case is the page before the next case starts; the last
case ends on the final page of the document.

This parser is less reliable than TocDrivenParser.  Expect more
needs_manual_review flags in its output.
"""

from __future__ import annotations

import logging
import re
from typing import List, Optional, Tuple

import fitz

from models.case import CaseBoundary
from pipeline.parsers.base import BaseCasebookParser
from utils.pdf_utils import extract_page_text, extract_page_blocks

logger = logging.getLogger(__name__)

# Minimum score for a page to be considered a case-title page
_SCORE_THRESHOLD = 0.42

# Section headers whose presence CONFIRMS a page is mid-case content
_MID_CASE_MARKERS = {
    "prompt",
    "background",
    "case background",
    "clarifying information",
    "clarifying questions",
    "additional information",
    "exhibit",
    "conclusion",
    "suggested framework",
    "sample framework",
    "potential framework",
    "case information",
    "interviewer guide",
    "candidate handout",
    "answer",
    "solution",
    "overview",
    "question",
    "case overview",
    "framework",
}

# Regex for "Label: value" metadata fields on title pages
_METADATA_RE = re.compile(
    r"(industry|sector|type|case type|difficulty|style|interviewer|level)"
    r"[\s:]+\S",
    re.IGNORECASE,
)


class HeaderPatternParser(BaseCasebookParser):
    """
    Detect case boundaries by identifying 'title-like' pages via layout scoring.

    Always applicable (can_handle returns True) so it acts as the fallback
    when TocDrivenParser finds nothing useful.
    """

    name = "header_pattern"

    def can_handle(self, doc: fitz.Document, config) -> bool:  # noqa: ARG002
        return True  # Universal fallback

    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        total_pages = len(doc)
        logger.info("HeaderPatternParser: scanning %d pages", total_pages)

        # Detect repeating navigation bars / running headers that appear on
        # many pages.  These inflate page-text length and confuse the sparse-
        # text score.  We strip them before any other analysis.
        boilerplate = self._detect_boilerplate(doc)
        if boilerplate:
            logger.info(
                "HeaderPatternParser: detected %d boilerplate phrase(s) to strip",
                len(boilerplate),
            )

        # Pre-compute which pages have known section headers — used for scoring
        section_pages = self._find_section_header_pages(doc, boilerplate)

        # Score every page
        candidates = self._score_all_pages(doc, section_pages, config, boilerplate)
        logger.info("Found %d title-page candidates", len(candidates))

        if not candidates:
            logger.warning("HeaderPatternParser: no candidates found")
            return []

        # Prune candidates that are too close together
        confirmed = self._prune_close_candidates(candidates, config)
        logger.info("Confirmed %d case starts after pruning", len(confirmed))

        if not confirmed:
            return []

        boundaries = self._build_boundaries(doc, confirmed, total_pages, config)
        boundaries = self._clamp_boundaries(boundaries, total_pages)
        return self._sort_boundaries(boundaries)

    # ── Helpers ────────────────────────────────────────────────────────────────

    def _detect_boilerplate(self, doc: fitz.Document) -> set[str]:
        """
        Find short text phrases (≤ 6 words) that appear on a large fraction
        of pages — these are running headers / navigation bars that should be
        stripped before page-sparseness scoring.

        Strategy: sample up to 40 evenly-spaced pages, extract each non-empty
        text block, count how many sampled pages contain each phrase.  Any
        phrase found on > 60 % of sampled pages is boilerplate.
        """
        total = len(doc)
        sample_size = min(40, total)
        step = max(1, total // sample_size)
        sample_pages = list(range(0, total, step))[:sample_size]

        phrase_counts: dict[str, int] = {}
        for idx in sample_pages:
            blocks = extract_page_blocks(doc, idx)
            seen_this_page: set[str] = set()
            for b in blocks:
                phrase = b["text"].strip()
                # Only consider short phrases (nav-bar items are short)
                if phrase and len(phrase.split()) <= 8 and phrase not in seen_this_page:
                    phrase_counts[phrase] = phrase_counts.get(phrase, 0) + 1
                    seen_this_page.add(phrase)

        threshold = len(sample_pages) * 0.60
        boilerplate = {p for p, c in phrase_counts.items() if c >= threshold}
        return boilerplate

    def _find_section_header_pages(
        self, doc: fitz.Document, boilerplate: set[str] = None
    ) -> set[int]:
        """
        Return a set of page indices that contain at least one mid-case marker.
        Boilerplate phrases are stripped before checking.
        """
        boilerplate = boilerplate or set()
        result: set[int] = set()
        for idx in range(len(doc)):
            text = self._stripped_text(doc, idx, boilerplate).lower()
            if any(h in text for h in _MID_CASE_MARKERS):
                result.add(idx)
        return result

    @staticmethod
    def _stripped_text(doc: fitz.Document, page_idx: int, boilerplate: set[str]) -> str:
        """
        Return page text with boilerplate phrases removed.
        Falls back to full text when boilerplate is empty.
        """
        if not boilerplate:
            return extract_page_text(doc, page_idx)
        blocks = extract_page_blocks(doc, page_idx)
        lines = [b["text"] for b in blocks if b["text"].strip() not in boilerplate]
        return "\n".join(lines)

    def _score_all_pages(
        self,
        doc: fitz.Document,
        section_pages: set[int],
        config,
        boilerplate: set[str] = None,
    ) -> List[Tuple[int, str, float]]:
        """
        Return (page_idx, title_text, score) for every page above the threshold,
        sorted by page_idx ascending.
        """
        boilerplate = boilerplate or set()
        total = len(doc)
        results: List[Tuple[int, str, float]] = []

        for idx in range(total):
            score, title = self._score_page(doc, idx, section_pages, total, boilerplate)
            if score >= _SCORE_THRESHOLD and title:
                results.append((idx, title, score))
                logger.debug(
                    "  candidate p%d score=%.2f '%s'", idx + 1, score, title[:40]
                )

        return results

    def _score_page(
        self,
        doc: fitz.Document,
        page_idx: int,
        section_pages: set[int],
        total_pages: int,
        boilerplate: set[str] = None,
    ) -> Tuple[float, Optional[str]]:
        """
        Score a single page as a potential case title page (0.0 – 1.0).

        Returns (score, title_candidate).  title_candidate is None when the
        page should not be used even if it scores high.

        Boilerplate phrases (repeating nav bars, running headers) are stripped
        before scoring so they don't inflate text length or block detection.
        """
        boilerplate = boilerplate or set()
        page_text = self._stripped_text(doc, page_idx, boilerplate)
        all_blocks = extract_page_blocks(doc, page_idx)
        blocks = [b for b in all_blocks if b["text"].strip() not in boilerplate]

        if not page_text.strip():
            return 0.0, None  # Empty page

        score = 0.0
        total_chars = len(page_text.strip())

        # ── Factor 1: sparse text (title pages are sparse) ────────────────────
        if total_chars < 80:
            score += 0.28
        elif total_chars < 250:
            score += 0.16
        elif total_chars < 600:
            score += 0.06
        else:
            score -= 0.18  # Dense text → body page, not a title page

        # ── Factor 2: layout of first text block ──────────────────────────────
        text_blocks = sorted(
            [b for b in blocks if b["text"] and len(b["text"]) >= 3],
            key=lambda b: b["y0"],
        )
        if not text_blocks:
            return 0.0, None

        first_block = text_blocks[0]
        title_candidate = first_block["text"].strip()

        # First text block near top of page
        try:
            page_height = doc.load_page(page_idx).rect.height
        except Exception:
            page_height = 800.0
        rel_y = first_block["y0"] / page_height if page_height > 0 else 0
        if rel_y < 0.20:
            score += 0.22
        elif rel_y < 0.35:
            score += 0.12
        elif rel_y > 0.60:
            score -= 0.10  # title very low on page → probably not a title page

        # ── Factor 3: title candidate characteristics ─────────────────────────
        title_len = len(title_candidate)
        if 5 <= title_len <= 80:
            score += 0.14
        elif title_len > 150:
            score -= 0.08  # Too long → probably paragraph text

        # Title case / ALL CAPS suggests a heading
        words = title_candidate.split()
        if words and (title_candidate.isupper() or title_candidate.istitle()):
            score += 0.10

        # Reject if first word is a known section-header keyword
        first_word = words[0].lower() if words else ""
        if first_word in {m.split()[0] for m in _MID_CASE_MARKERS}:
            return 0.0, None  # This IS a section header, not a title

        # ── Factor 4: page has metadata labels ────────────────────────────────
        if _METADATA_RE.search(page_text):
            score += 0.28

        # ── Factor 5: page does NOT contain mid-case content ─────────────────
        page_lower = page_text.lower()
        mid_case_count = sum(1 for m in _MID_CASE_MARKERS if m in page_lower)
        if mid_case_count == 0:
            score += 0.08
        elif mid_case_count >= 2:
            score -= 0.30  # Definitely inside a case

        # ── Factor 6: a section-header page follows within 4 pages ───────────
        for lookahead in range(page_idx + 1, min(total_pages, page_idx + 5)):
            if lookahead in section_pages:
                score += 0.22
                break

        return max(0.0, min(1.0, score)), title_candidate

    def _prune_close_candidates(
        self,
        candidates: List[Tuple[int, str, float]],
        config,
    ) -> List[Tuple[int, str, float]]:
        """
        Remove candidates that are fewer than min_case_pages away from the
        previous confirmed candidate.  When two candidates are too close,
        keep the one with the higher score.
        """
        min_gap = config.processing.min_case_pages
        confirmed: List[Tuple[int, str, float]] = []

        for page_idx, title, score in candidates:
            if not confirmed:
                confirmed.append((page_idx, title, score))
                continue

            last_idx, last_title, last_score = confirmed[-1]
            if page_idx - last_idx < min_gap:
                # Too close — keep the better-scored one
                if score > last_score:
                    confirmed[-1] = (page_idx, title, score)
                    logger.debug(
                        "  replaced p%d (%.2f) with p%d (%.2f)",
                        last_idx + 1, last_score, page_idx + 1, score,
                    )
                # else: keep the existing entry
            else:
                confirmed.append((page_idx, title, score))

        return confirmed

    def _build_boundaries(
        self,
        doc: fitz.Document,
        confirmed: List[Tuple[int, str, float]],
        total_pages: int,
        config,
    ) -> List[CaseBoundary]:
        """Convert confirmed title-page positions into CaseBoundary objects."""
        low_conf = config.confidence.low_confidence_threshold
        boundaries: List[CaseBoundary] = []

        for i, (page_idx, title, score) in enumerate(confirmed):
            page_start = page_idx
            page_end = (
                confirmed[i + 1][0] - 1 if i + 1 < len(confirmed) else total_pages - 1
            )
            page_end = min(page_end, total_pages - 1)

            start_text = extract_page_text(doc, page_start)[:200]

            # Header-pattern confidence is scaled down vs TOC
            confidence = score * 0.75
            notes = [f"layout score {score:.2f}"]
            flags: List[str] = []

            page_count = page_end - page_start + 1
            if page_count < config.processing.min_case_pages:
                flags.append("too_few_pages")
                confidence -= 0.10
            elif page_count > config.processing.max_case_pages:
                flags.append("too_many_pages")
                confidence -= 0.08

            if confidence < low_conf:
                flags.append("low_confidence")

            confidence = max(0.0, min(1.0, confidence))
            needs_review = bool(flags)

            boundaries.append(
                CaseBoundary(
                    title=title or f"Case {i + 1} (untitled)",
                    page_start=page_start,
                    page_end=page_end,
                    confidence=confidence,
                    detection_method="header_pattern",
                    matched_toc_title=None,
                    matched_start_page_text=start_text,
                    matched_patterns=["title_page_layout", "section_header_following"],
                    confidence_notes=notes,
                    needs_manual_review=needs_review,
                    review_flags=flags,
                )
            )

        return boundaries
