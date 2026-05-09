"""Unit tests for utils/duplicate_review.py (no database)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from utils.duplicate_review import duplicate_loose_key, pick_canonical_row, title_similarity


def test_salty_sole_shoe_loose_key_matches():
    a = duplicate_loose_key("Salty Sole Shoe")
    b = duplicate_loose_key("Salty Sole Shoe Co.")
    assert a == b
    assert a == "salty sole shoe"


def test_wine_and_co_loose_key_matches():
    a = duplicate_loose_key("Wine and Co")
    b = duplicate_loose_key("Wine & Co")
    assert a == b
    assert a == "wine and"


def test_pick_canonical_prefers_older_year():
    rows = [
        {"id": 1, "source_year": 2023, "unique_case_count_eligible": True},
        {"id": 2, "source_year": 2016, "unique_case_count_eligible": True},
    ]
    assert pick_canonical_row(rows)["id"] == 2


def test_pick_canonical_same_year_prefers_eligible():
    rows = [
        {"id": 10, "source_year": 2020, "unique_case_count_eligible": False},
        {"id": 11, "source_year": 2020, "unique_case_count_eligible": True},
    ]
    assert pick_canonical_row(rows)["id"] == 11


def test_title_similarity_wine_pair_moderate():
    # Fuzzy pairing still requires ≥0.88 in the finder script; these two
    # strings are usually matched via loose_key + same school instead.
    r = title_similarity("Wine and Co", "Wine & Co")
    assert r >= 0.75
