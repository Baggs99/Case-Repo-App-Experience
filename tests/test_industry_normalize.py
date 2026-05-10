"""Tests for canonical industry label mapping."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from webapp.industry_normalize import (
    attach_industry_display,
    industry_raws_matching_canonical,
    normalize_industry_label,
)


def test_normalize_none_and_noise():
    assert normalize_industry_label(None) is None
    assert normalize_industry_label("") is None
    assert normalize_industry_label("  ") is None
    assert normalize_industry_label("n/a") is None


def test_user_examples():
    assert normalize_industry_label("Aerospace & Defense") == "Aerospace, Airlines & Transportation"
    assert normalize_industry_label("Airlines / Transportation") == "Aerospace, Airlines & Transportation"
    assert normalize_industry_label("Retail / CPG") == "Consumer & Retail"
    assert normalize_industry_label("Consumer Goods") == "Consumer & Retail"
    assert normalize_industry_label("Banking") == "Financial Services"
    assert normalize_industry_label("Financial Services") == "Financial Services"
    assert normalize_industry_label("Pharma") == "Healthcare & Life Sciences"
    assert normalize_industry_label("Oil & Gas") == "Energy & Utilities"
    assert normalize_industry_label("Software") == "Technology"
    assert normalize_industry_label("Media") == "Media & Entertainment"
    assert normalize_industry_label("Manufacturing") == "Industrials & Manufacturing"
    assert normalize_industry_label("Logistics") == "Transportation & Logistics"


def test_unknown_maps_to_other():
    assert normalize_industry_label("Fun / Random") == "Other"


def test_matching_raws_for_canonical():
    raws = ["Retail / CPG", "Consumer", "Pharma", "n/a"]
    m = industry_raws_matching_canonical("Consumer & Retail", raws)
    assert m == ["Consumer", "Retail / CPG"]


def test_attach_industry_display():
    row = {"industry": "Retail / CPG"}
    attach_industry_display(row)
    assert row["industry_raw"] == "Retail / CPG"
    assert row["industry_display"] == "Consumer & Retail"
