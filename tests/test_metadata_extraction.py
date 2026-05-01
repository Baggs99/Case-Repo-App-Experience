"""
Unit tests for pipeline.metadata_extractor.

Tests cover labeled-field extraction, industry inference, case-type inference,
and interviewer-style detection — all without opening real PDFs.
"""

from __future__ import annotations

import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from pipeline.metadata_extractor import (
    _extract_labeled_fields,
    _infer_industry,
    _infer_case_type,
    _infer_interviewer_style,
    _extract_prompt_excerpt,
    build_case_metadata,
)
from models.case import CaseBoundary


# ── Labeled-field extraction ───────────────────────────────────────────────────

class TestExtractLabeledFields(unittest.TestCase):

    def test_colon_separated(self):
        text = "Industry: Healthcare\nType: Profitability\n"
        fields = _extract_labeled_fields(text)
        self.assertEqual(fields.get("industry"), "Healthcare")
        self.assertEqual(fields.get("type"), "Profitability")

    def test_dash_separated(self):
        text = "Difficulty - 3/5\nStyle - Interviewee-led\n"
        fields = _extract_labeled_fields(text)
        self.assertEqual(fields.get("difficulty"), "3/5")

    def test_multiple_fields(self):
        text = (
            "Industry: Technology\n"
            "Case Type: Market Entry\n"
            "Overall Difficulty: Hard\n"
            "Quant Difficulty: Medium\n"
        )
        fields = _extract_labeled_fields(text)
        self.assertEqual(fields.get("industry"), "Technology")
        self.assertEqual(fields.get("case type"), "Market Entry")
        self.assertEqual(fields.get("overall difficulty"), "Hard")
        self.assertEqual(fields.get("quant difficulty"), "Medium")

    def test_no_fields(self):
        text = "Some random paragraph with no labeled fields.\n"
        fields = _extract_labeled_fields(text)
        self.assertEqual(fields, {})

    def test_strips_trailing_punctuation(self):
        text = "Industry: Healthcare,\n"
        fields = _extract_labeled_fields(text)
        self.assertEqual(fields.get("industry"), "Healthcare")


# ── Industry inference ────────────────────────────────────────────────────────

class TestInferIndustry(unittest.TestCase):

    def test_healthcare_detected(self):
        text = "The hospital has seen a decline in patient volumes. pharma revenues also fell."
        result = _infer_industry(text)
        self.assertEqual(result, "Healthcare")

    def test_technology_detected(self):
        text = "The SaaS platform has grown its cloud software subscriber base by 30%."
        result = _infer_industry(text)
        self.assertEqual(result, "Technology")

    def test_retail_detected(self):
        text = "The consumer brand lost market share in its core retail stores and e-commerce."
        result = _infer_industry(text)
        self.assertEqual(result, "Retail / CPG")

    def test_ambiguous_returns_none(self):
        text = "A company has a problem. What is your recommendation?"
        result = _infer_industry(text)
        self.assertIsNone(result)

    def test_requires_two_hits(self):
        """A single keyword hit should NOT be enough to infer industry."""
        text = "The company hired a doctor."
        # Only one healthcare keyword ("doctor") — below threshold
        result = _infer_industry(text)
        self.assertIsNone(result)


# ── Case type inference ───────────────────────────────────────────────────────

class TestInferCaseType(unittest.TestCase):

    def test_profitability_detected(self):
        text = "Our client's profit margin has declined. Revenue fell and costs rose."
        result = _infer_case_type(text)
        self.assertEqual(result, "Profitability")

    def test_market_entry_detected(self):
        text = "The client wants to enter the market in Southeast Asia. Should they expand?"
        result = _infer_case_type(text)
        self.assertEqual(result, "Market Entry")

    def test_ma_detected(self):
        text = "Our client is considering an acquisition of a smaller competitor. Valuation?"
        result = _infer_case_type(text)
        self.assertEqual(result, "M&A")

    def test_pricing_detected(self):
        text = "The client wants to raise prices for its premium product line."
        result = _infer_case_type(text)
        self.assertEqual(result, "Pricing")

    def test_no_match_returns_none(self):
        text = "Just some generic text with no case-type signals."
        result = _infer_case_type(text)
        self.assertIsNone(result)


# ── Interviewer style ─────────────────────────────────────────────────────────

class TestInferInterviewerStyle(unittest.TestCase):

    def test_interviewee_led(self):
        text = "This is an interviewee-led case. The candidate drives the structure."
        self.assertEqual(_infer_interviewer_style(text), "Interviewee-led")

    def test_interviewer_led(self):
        text = "Interviewer-led. The interviewer will provide data when asked."
        self.assertEqual(_infer_interviewer_style(text), "Interviewer-led")

    def test_none_when_ambiguous(self):
        self.assertIsNone(_infer_interviewer_style("No style information here."))


# ── Prompt excerpt ────────────────────────────────────────────────────────────

class TestExtractPromptExcerpt(unittest.TestCase):

    def test_extracts_after_prompt_header(self):
        text = "Some preamble.\n\nPrompt:\nYour client is a healthcare company that...\n"
        excerpt = _extract_prompt_excerpt(text, max_chars=50)
        self.assertIsNotNone(excerpt)
        self.assertIn("healthcare", excerpt.lower())

    def test_extracts_after_question_header(self):
        text = "Question:\nShould the client enter the European market?"
        excerpt = _extract_prompt_excerpt(text)
        self.assertIsNotNone(excerpt)

    def test_returns_none_when_no_marker(self):
        text = "There is no prompt marker in this text."
        self.assertIsNone(_extract_prompt_excerpt(text))

    def test_respects_max_chars(self):
        text = "Prompt:\n" + "A" * 500
        excerpt = _extract_prompt_excerpt(text, max_chars=100)
        self.assertIsNotNone(excerpt)
        self.assertLessEqual(len(excerpt), 100)


# ── Integration: build_case_metadata ─────────────────────────────────────────

class TestBuildCaseMetadata(unittest.TestCase):

    def _make_config(self):
        cfg = types.SimpleNamespace()
        cfg.processing = types.SimpleNamespace(max_metadata_extract_pages=3)
        return cfg

    def _make_boundary(self) -> CaseBoundary:
        return CaseBoundary(
            title="Big Tech Bivalves",
            page_start=4,
            page_end=9,
            confidence=0.88,
            detection_method="toc",
            matched_toc_title="Big Tech Bivalves",
            matched_start_page_text="Big Tech Bivalves\nIndustry: Technology\n",
            matched_patterns=["toc_entry"],
            confidence_notes=[],
        )

    def _make_doc_record(self):
        rec = MagicMock()
        rec.relative_path = "Yale/yale2024.pdf"
        rec.source_folder = "Yale"
        rec.source_school = "yale"
        rec.source_year = 2024
        rec.path = Path("Yale/yale2024.pdf")
        return rec

    @patch("pipeline.metadata_extractor._read_case_pages")
    def test_metadata_fields_populated(self, mock_read):
        mock_read.return_value = [
            "Big Tech Bivalves\nIndustry: Technology\nType: Market Entry\n"
            "Interviewee-led\nPrompt:\nShould the client launch a new product?\n"
        ]
        config = self._make_config()
        boundary = self._make_boundary()
        doc_record = self._make_doc_record()
        output_path = Path("output/cases/Yale/yale2024/big-tech-bivalves.pdf")
        output_root = Path("output")

        metadata = build_case_metadata(doc_record, boundary, output_path, output_root, config)

        self.assertEqual(metadata.case_title, "Big Tech Bivalves")
        self.assertEqual(metadata.source_school, "yale")
        self.assertEqual(metadata.source_year, 2024)
        self.assertEqual(metadata.page_start, 5)   # 1-indexed
        self.assertEqual(metadata.page_end, 10)    # 1-indexed
        self.assertEqual(metadata.page_count, 6)
        self.assertEqual(metadata.industry, "Technology")
        self.assertEqual(metadata.case_type, "Market Entry")
        self.assertEqual(metadata.interviewer_style, "Interviewee-led")
        self.assertIsNotNone(metadata.prompt_excerpt)

    @patch("pipeline.metadata_extractor._read_case_pages")
    def test_missing_fields_are_none(self, mock_read):
        mock_read.return_value = ["Big Tech Bivalves\nSome generic text.\n"]
        config = self._make_config()
        boundary = self._make_boundary()
        doc_record = self._make_doc_record()
        output_path = Path("output/cases/Yale/yale2024/big-tech-bivalves.pdf")
        output_root = Path("output")

        metadata = build_case_metadata(doc_record, boundary, output_path, output_root, config)

        # No labeled fields in page text; inference should fail for uncommon topics
        # (industry inferred from "Technology" in title area is expected to pass here,
        # but prompt_excerpt should be None as there's no Prompt marker)
        self.assertIsNone(metadata.prompt_excerpt)


if __name__ == "__main__":
    unittest.main()
