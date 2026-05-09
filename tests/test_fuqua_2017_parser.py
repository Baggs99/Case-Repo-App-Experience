"""
Sanity checks for Fuqua 2017 manual TOC boundaries (split ranges).
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from pipeline.parsers.profiles.fuqua_2017 import Fuqua2017Parser


def _fake_doc(n_pages: int = 400) -> MagicMock:
    doc = MagicMock()
    doc.__len__.return_value = n_pages
    page = MagicMock()
    page.get_text.return_value = "YachtCo overview"
    doc.load_page.return_value = page
    return doc


def test_fuqua_2017_exactly_37_cases():
    boundaries = Fuqua2017Parser().parse(_fake_doc(), MagicMock())
    assert len(boundaries) == 37


@pytest.mark.parametrize(
    ("title", "want_start", "want_end"),
    [
        ("Off-Broadway Blues", 161, 168),
        ("Coyotes ('14-15)", 360, 370),
        ("Purple Pill Company ('14-15)", 379, 384),
    ],
)
def test_fuqua_2017_anchor_ranges(title: str, want_start: int, want_end: int):
    boundaries = Fuqua2017Parser().parse(_fake_doc(), MagicMock())
    b = next(x for x in boundaries if x.title == title)
    assert b.page_start + 1 == want_start
    assert b.page_end + 1 == want_end


def test_fuqua_2017_human_page_292_skipped_between_mobilizing_and_mission():
    boundaries = Fuqua2017Parser().parse(_fake_doc(), MagicMock())
    mob = next(x for x in boundaries if x.title == "Accenture Case: Mobilizing your world")
    miss = next(x for x in boundaries if x.title == "Mission Eternity ('15-16)")
    assert mob.page_end + 1 == 291
    assert miss.page_start + 1 == 293


def test_fuqua_2017_parser_returns_empty_when_pdf_too_short_for_first_case():
    """First case starts human p20 — shorter PDFs are rejected before boundaries."""
    assert Fuqua2017Parser().parse(_fake_doc(15), MagicMock()) == []

