"""
Unit tests for boundary detection parsers.

Tests use mock fitz.Document objects so no real PDFs are required.
"""

from __future__ import annotations

import types
import unittest
from unittest.mock import MagicMock

from pipeline.parsers.toc_driven import TocDrivenParser, _filter_toc_page_runs
from pipeline.parsers.header_pattern import HeaderPatternParser
from pipeline.parsers.single_case import SingleCaseParser


# ── Helpers ────────────────────────────────────────────────────────────────────

def _make_config(
    min_case_pages: int = 3,
    max_case_pages: int = 60,
    max_toc_pages: int = 40,
    min_toc_entries: int = 3,
    low_conf_threshold: float = 0.50,
    header_pattern_threshold: float = 0.45,
):
    cfg = types.SimpleNamespace()
    cfg.processing = types.SimpleNamespace(
        min_case_pages=min_case_pages,
        max_case_pages=max_case_pages,
        max_toc_search_pages=max_toc_pages,
    )
    cfg.heuristics = types.SimpleNamespace(
        min_toc_entries=min_toc_entries,
        title_min_length=3,
        title_max_length=150,
        very_short_case_pages=3,
        very_long_case_pages=55,
        unassigned_pages_warn_threshold=10,
    )
    cfg.confidence = types.SimpleNamespace(
        low_confidence_threshold=low_conf_threshold,
        header_pattern_threshold=header_pattern_threshold,
    )
    return cfg


def _make_doc(page_texts: list[str], page_height: float = 800.0) -> MagicMock:
    """
    Build a mock fitz.Document with predictable page text and block extraction.

    Each page's text is returned as-is from get_text("text").
    Blocks are constructed from the text as a single block at y=50 (near top).
    """
    doc = MagicMock()
    doc.__len__ = MagicMock(return_value=len(page_texts))
    doc.metadata = {}

    def load_page(idx):
        page = MagicMock()
        text = page_texts[idx]
        page.get_text.return_value = text
        page.rect = MagicMock(height=page_height)

        # Simulate blocks: one block per non-empty line
        raw_blocks = []
        y = 50.0
        for i, line in enumerate(text.strip().splitlines()):
            if line.strip():
                # (x0, y0, x1, y1, text, block_no, block_type=0)
                raw_blocks.append((10.0, y, 400.0, y + 20, line.strip() + "\n", i, 0))
                y += 25.0
        page.get_text.side_effect = lambda fmt: (
            text if fmt == "text" else raw_blocks
        )
        return page

    doc.load_page.side_effect = load_page
    return doc


# ── TocDrivenParser tests ──────────────────────────────────────────────────────

class TestTocDrivenParser(unittest.TestCase):

    def setUp(self):
        self.config = _make_config()
        self.parser = TocDrivenParser()

    def _doc_with_toc(self, entries: list[tuple[str, int]], total_pages: int) -> MagicMock:
        """
        Build a mock document with:
          - page 0: TOC listing the given entries
          - pages 1..total_pages-1: body text including each case title
        """
        toc_lines = ["Table of Contents\n"]
        for title, pnum in entries:
            toc_lines.append(f"{title}{'.' * 10}{pnum}\n")
        toc_text = "".join(toc_lines)

        body_pages = ["body text\n"] * (total_pages - 1)
        # Put each case title on its declared page (1-indexed → 0-indexed = pnum-1)
        for title, pnum in entries:
            idx = pnum - 1  # 0-indexed
            if 0 <= idx < len(body_pages):
                body_pages[idx] = f"{title}\nPrompt\nSome case content.\n"

        return _make_doc([toc_text] + body_pages)

    def test_can_handle_with_toc(self):
        doc = self._doc_with_toc([("Big Tech", 2), ("Market Entry", 8)], total_pages=20)
        self.assertTrue(self.parser.can_handle(doc, self.config))

    def test_cannot_handle_without_toc(self):
        doc = _make_doc(["Just body text\n"] * 5)
        self.assertFalse(self.parser.can_handle(doc, self.config))

    def test_extracts_two_boundaries(self):
        entries = [("Big Tech Bivalves", 2), ("Market Entry Case", 8)]
        doc = self._doc_with_toc(entries, total_pages=15)
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(len(boundaries), 2)

    def test_boundary_titles_match_toc(self):
        entries = [("Healthcare Profitability", 2), ("Retail Growth", 9)]
        doc = self._doc_with_toc(entries, total_pages=18)
        boundaries = self.parser.parse(doc, self.config)
        titles = [b.title for b in boundaries]
        self.assertIn("Healthcare Profitability", titles)
        self.assertIn("Retail Growth", titles)

    def test_page_ranges_are_contiguous(self):
        """Each case should end just before the next one starts."""
        entries = [("Case Alpha", 2), ("Case Beta", 7), ("Case Gamma", 12)]
        doc = self._doc_with_toc(entries, total_pages=20)
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(len(boundaries), 3)
        # Case Alpha ends at page 5 (0-indexed), Case Beta starts at 6
        self.assertEqual(boundaries[0].page_end + 1, boundaries[1].page_start)
        self.assertEqual(boundaries[1].page_end + 1, boundaries[2].page_start)

    def test_last_case_ends_at_final_page(self):
        entries = [("Case A", 2), ("Case B", 8)]
        doc = self._doc_with_toc(entries, total_pages=15)
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(boundaries[-1].page_end, 14)  # 0-indexed last page

    def test_detection_method_is_toc(self):
        entries = [("Case X", 2), ("Case Y", 7)]
        doc = self._doc_with_toc(entries, total_pages=12)
        boundaries = self.parser.parse(doc, self.config)
        self.assertTrue(all(b.detection_method == "toc" for b in boundaries))

    def test_short_case_gets_review_flag(self):
        """A case shorter than min_case_pages should be flagged."""
        # Case A: pages 2-3 (2 pages, below min of 3)
        entries = [("Case A", 2), ("Case B", 4)]
        doc = self._doc_with_toc(entries, total_pages=20)
        boundaries = self.parser.parse(doc, self.config)
        case_a = next(b for b in boundaries if "A" in b.title)
        self.assertIn("too_few_pages", case_a.review_flags)
        self.assertTrue(case_a.needs_manual_review)


class TestFilterTocPageRuns(unittest.TestCase):

    def test_empty_input(self):
        self.assertEqual(_filter_toc_page_runs([]), [])

    def test_short_run_kept(self):
        pages = [0, 1, 2]
        self.assertEqual(_filter_toc_page_runs(pages, max_run=5), [0, 1, 2])

    def test_long_run_dropped(self):
        pages = list(range(10))  # 10 consecutive pages
        result = _filter_toc_page_runs(pages, max_run=5)
        self.assertEqual(result, [])

    def test_two_separate_runs(self):
        pages = [0, 1, 10, 11]  # Two short runs far apart
        result = _filter_toc_page_runs(pages, max_run=5)
        self.assertIn(0, result)
        self.assertIn(10, result)


# ── SingleCaseParser tests ─────────────────────────────────────────────────────

class TestSingleCaseParser(unittest.TestCase):

    def setUp(self):
        self.config = _make_config()
        self.parser = SingleCaseParser()

    def test_returns_one_boundary(self):
        doc = _make_doc(["Big Tech Bivalves\nSome content\n"] * 10)
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(len(boundaries), 1)

    def test_boundary_spans_full_document(self):
        doc = _make_doc(["page content\n"] * 15)
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(boundaries[0].page_start, 0)
        self.assertEqual(boundaries[0].page_end, 14)

    def test_detection_method(self):
        doc = _make_doc(["page\n"] * 5)
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(boundaries[0].detection_method, "already_single_case")

    def test_empty_document_returns_empty(self):
        doc = MagicMock()
        doc.__len__ = MagicMock(return_value=0)
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(boundaries, [])

    def test_uses_metadata_title_when_available(self):
        doc = _make_doc(["content\n"] * 5)
        doc.metadata = {"title": "My Consulting Case"}
        boundaries = self.parser.parse(doc, self.config)
        self.assertEqual(boundaries[0].title, "My Consulting Case")


if __name__ == "__main__":
    unittest.main()
