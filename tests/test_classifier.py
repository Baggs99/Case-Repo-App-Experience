"""
Unit tests for pipeline.classifier.

These tests mock fitz and config so they run without any real PDFs.
"""

from __future__ import annotations

import types
import unittest
from unittest.mock import MagicMock, patch

from pipeline.classifier import (
    classify_pdf,
    _detect_toc,
    _school_filename_score,
)


# ── Config fixture ─────────────────────────────────────────────────────────────

def _make_config(
    min_pages: int = 30,
    max_case_pages: int = 60,
    max_toc_pages: int = 40,
    min_toc_entries: int = 3,
):
    """Return a minimal SimpleNamespace config for testing."""
    cfg = types.SimpleNamespace()
    cfg.processing = types.SimpleNamespace(
        likely_casebook_min_pages=min_pages,
        max_case_pages=max_case_pages,
        max_toc_search_pages=max_toc_pages,
    )
    cfg.section_headers = types.SimpleNamespace(
        primary=["Prompt", "Clarifying Information", "Exhibits", "Conclusion"],
        toc_indicators=["Table of Contents", "Contents"],
    )
    cfg.heuristics = types.SimpleNamespace(min_toc_entries=min_toc_entries)
    return cfg


def _make_doc(page_texts: list[str]) -> MagicMock:
    """Build a mock fitz.Document with preset page text."""
    doc = MagicMock()
    doc.__len__ = MagicMock(return_value=len(page_texts))

    def load_page(idx):
        page = MagicMock()
        page.get_text.return_value = page_texts[idx]
        return page

    doc.load_page.side_effect = load_page
    return doc


# ── Tests ──────────────────────────────────────────────────────────────────────

class TestClassifyPdf(unittest.TestCase):

    def setUp(self):
        self.config = _make_config()

    def test_large_page_count_classifies_multi(self):
        """A 60-page PDF with no other signals → multi_case."""
        texts = ["some page text\n"] * 60
        doc = _make_doc(texts)
        classification, conf, notes = classify_pdf(doc, self.config, "casebook.pdf")
        self.assertEqual(classification, "multi_case")
        self.assertGreater(conf, 0.0)

    def test_small_page_count_classifies_single(self):
        """A 12-page PDF with no section headers → single_case."""
        texts = ["just some text\n"] * 12
        doc = _make_doc(texts)
        classification, conf, notes = classify_pdf(doc, self.config, "case.pdf")
        self.assertEqual(classification, "single_case")

    def test_toc_presence_strongly_predicts_multi(self):
        """A 10-page PDF with a TOC should still classify as multi_case."""
        texts = ["Table of Contents\nBig Bivalves.....5\nMarket Entry....8\n"]
        texts += ["some page\n"] * 9
        doc = _make_doc(texts)
        classification, conf, notes = classify_pdf(doc, self.config, "cases.pdf")
        self.assertEqual(classification, "multi_case")
        self.assertGreater(conf, 0.5)

    def test_repeated_headers_signal_multi(self):
        """Many pages with 'Prompt' → multi_case."""
        # 5 pages each with Prompt, Clarifying Information, etc.
        body = "Prompt\nBig company profits fell.\n\nClarifying Information\nFoo bar.\n"
        texts = [body] * 10
        doc = _make_doc(texts)
        classification, conf, notes = classify_pdf(doc, self.config, "casebook.pdf")
        self.assertEqual(classification, "multi_case")

    def test_rocketblocks_school_forces_single(self):
        """RocketBlocks PDFs should always classify as single_case."""
        texts = ["Some case text\n"] * 40  # even large page count
        doc = _make_doc(texts)
        classification, conf, notes = classify_pdf(
            doc, self.config, "rb-profitability.pdf", source_school="rocketblocks"
        )
        self.assertEqual(classification, "single_case")

    def test_casebook_filename_keyword(self):
        """Filename containing 'casebook' contributes to multi_case signal."""
        texts = ["page\n"] * 35
        doc = _make_doc(texts)
        _, _, notes = classify_pdf(doc, self.config, "Booth_casebook_2025.pdf")
        self.assertTrue(any("multi-case" in n.lower() or "casebook" in n.lower() for n in notes))


class TestDetectToc(unittest.TestCase):

    def setUp(self):
        self.config = _make_config()

    def test_finds_explicit_toc_heading(self):
        texts = ["Table of Contents\nCase 1.....5\nCase 2.....12\n"] + ["body"] * 5
        doc = _make_doc(texts)
        found, page = _detect_toc(doc, self.config, ["table of contents", "contents"])
        self.assertTrue(found)
        self.assertEqual(page, 0)

    def test_finds_numeric_toc_without_heading(self):
        """Page with 3+ lines ending in numbers should be detected as TOC."""
        toc_text = (
            "Big Tech Bivalves..........5\n"
            "Market Entry Case.........12\n"
            "Pharma M&A................20\n"
        )
        texts = [toc_text] + ["body\n"] * 10
        doc = _make_doc(texts)
        found, page = _detect_toc(doc, self.config, ["table of contents"])
        self.assertTrue(found)

    def test_no_toc_returns_false(self):
        texts = ["Just a normal paragraph.\nNo page numbers here.\n"] * 5
        doc = _make_doc(texts)
        found, page = _detect_toc(doc, self.config, ["table of contents", "contents"])
        self.assertFalse(found)


class TestSchoolFilenameScore(unittest.TestCase):

    def test_rocketblocks_score_is_negative(self):
        notes: list = []
        score = _school_filename_score("rocketblocks", "case.pdf", notes)
        self.assertLess(score, 0)

    def test_casebook_keyword_is_positive(self):
        notes: list = []
        score = _school_filename_score("booth", "Booth_casebook_2025.pdf", notes)
        self.assertGreater(score, 0)

    def test_profitability_filename_is_negative(self):
        notes: list = []
        score = _school_filename_score("yale", "profitability-case.pdf", notes)
        self.assertLess(score, 0)


if __name__ == "__main__":
    unittest.main()
