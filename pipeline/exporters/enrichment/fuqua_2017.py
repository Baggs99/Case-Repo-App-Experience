"""
Ground-truth metadata for the Duke Fuqua Case Book 2017 (DMCC).

TOC difficulty uses Easy / Medium / Difficult for qual and quant.
Overall ``difficulty`` follows the product rule for this import:
  Difficult on either axis → Hard; else Medium on either → Medium; else Easy.
  N/A uses the other axis.

Keys match normalize_title(case_title) (same algorithm as case_catalog).

PDF_MATCH must distinguish Fuqua 2017 from Fuqua 2026.
"""

from __future__ import annotations

import re
from typing import Any

PDF_MATCH = "Fuqua 2017"


def _nk(title: str) -> str:
    t = title.lower()
    t = re.sub(r"[^\w\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


# --- title, enrichment dict (TOC industry; quant/qual verbatim where known) ---

_RAW: list[tuple[str, dict[str, Any]]] = [
    ("YachtCo", {
        "industry": "Consumer Products",
        "case_type": "Profitability",
        "difficulty": "Easy",
        "difficulty_quant": "Easy",
        "difficulty_qual": "Easy",
    }),
    ("Dam It", {
        "industry": "Public Sector/Infrastructure",
        "case_type": "Public Sector / Nonprofit",
        "difficulty": "Easy",
        "difficulty_quant": "Easy",
        "difficulty_qual": "Easy",
    }),
    ("Sam's Sushi", {
        "industry": "Services",
        "case_type": "Profitability",
        "difficulty": "Easy",
        "difficulty_quant": "Easy",
        "difficulty_qual": "Easy",
    }),
    ("Swipe Right for Canoodle", {
        "industry": "Technology",
        "case_type": "Growth Strategy",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Easy",
    }),
    ("Cackalacky Construction", {
        "industry": "Infrastructure",
        "case_type": "Strategy",
        "difficulty": "Medium",
        "difficulty_quant": "Easy",
        "difficulty_qual": "Medium",
    }),
    ("Polar Bear Pool Float", {
        "industry": "Consumer Products",
        "case_type": "Pricing",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Easy",
    }),
    ("Sardine Airlines", {
        "industry": "Transportation",
        "case_type": "Profitability",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Run of the Mill", {
        "industry": "Industrial Goods",
        "case_type": "Operations",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Critical Transportation", {
        "industry": "Transportation",
        "case_type": "Operations",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Dealer Jack's", {
        "industry": "Retail",
        "case_type": "Growth Strategy",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Duck Island Beer Company", {
        "industry": "Consumer Products",
        "case_type": "Growth Strategy",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("FoodXperts", {
        "industry": "Healthcare (Human Capital)",
        "case_type": "Organization / Human Capital",
        "difficulty": "Medium",
        "difficulty_quant": "N/A",
        "difficulty_qual": "Medium",
    }),
    ("NileKart", {
        "industry": "Technology (Human Capital)",
        "case_type": "Organization / Human Capital",
        "difficulty": "Medium",
        "difficulty_quant": "N/A",
        "difficulty_qual": "Medium",
    }),
    ("Fresher Breath", {
        "industry": "Consumer Products",
        "case_type": "Competitive Response",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Off-Broadway Blues", {
        "industry": "Media & Entertainment",
        "case_type": "Strategy",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Galatica's Epic Struggle", {
        "industry": "Technology",
        "case_type": "Competitive Response",
        "difficulty": "Hard",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Difficult",
    }),
    ("Thrill Park", {
        "industry": "Media & Entertainment",
        "case_type": "Investment Decision",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Medium",
    }),
    ("Specialty Steel", {
        "industry": "Industrial Goods",
        "case_type": "Profitability",
        "difficulty": "Hard",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Difficult",
    }),
    ("Goodbye Horses", {
        "industry": "Healthcare",
        "case_type": "Growth Strategy",
        "difficulty": "Hard",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Difficult",
    }),
    ("Game of Ligers", {
        "industry": "Media & Entertainment",
        "case_type": "Strategy",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Medium",
    }),
    ("From Breakdowns to Make-Ups", {
        "industry": "Industrial Goods",
        "case_type": "Operations",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Difficult",
    }),
    ("Peaceful Energy", {
        "industry": "Energy",
        "case_type": "Strategy",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Difficult",
    }),
    ("Make Airlines Great Again", {
        "industry": "Transportation / Leisure",
        "case_type": "Growth Strategy",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Difficult",
    }),
    ("Deloitte Case: DevCo", {
        "industry": "Healthcare",
        "case_type": "Growth Strategy",
        "firm": "Deloitte",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("BCG Case: Pharma rare disease business growth", {
        "industry": "Healthcare",
        "case_type": "Growth Strategy",
        "firm": "BCG",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("BCG Case: Consumer Products Strategy", {
        "industry": "Consumer Products",
        "case_type": "Strategy",
        "firm": "BCG",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Accenture Case: Surfboard Wax", {
        "industry": "Retail",
        "case_type": "Market Entry",
        "firm": "Accenture",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Accenture Case: Mobilizing your world", {
        "industry": "Technology",
        "case_type": "Strategy",
        "firm": "Accenture",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
    }),
    ("Mission Eternity ('15-16)", {
        "industry": "Other",
        "case_type": "Strategy",
        "difficulty": "Hard",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Difficult",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("Refinery in the Country of Georgia ('15-16)", {
        "industry": "Oil & Gas",
        "case_type": "Investment Decision",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("Walter Black Industries ('15-16)", {
        "industry": "Chemicals",
        "case_type": "Profitability",
        "difficulty": "Hard",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Difficult",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("Activist Action ('15-16)", {
        "industry": "CPG",
        "case_type": "Competitive Response",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Difficult",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("Buy Low, Sell High ('14-15)", {
        "industry": "Financial Services",
        "case_type": "Investment Decision",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Easy",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("Orange Yoga Studio ('14-15)", {
        "industry": "Other",
        "case_type": "Profitability",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Difficult",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("Coyotes ('14-15)", {
        "industry": "Non-Profit",
        "case_type": "Public Sector / Nonprofit",
        "difficulty": "Hard",
        "difficulty_quant": "Difficult",
        "difficulty_qual": "Difficult",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("The Everything Retailer ('14-15)", {
        "industry": "Retail",
        "case_type": "Strategy",
        "difficulty": "Hard",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Difficult",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
    ("Purple Pill Company ('14-15)", {
        "industry": "Pharma",
        "case_type": "Pricing",
        "difficulty": "Medium",
        "difficulty_quant": "Medium",
        "difficulty_qual": "Medium",
        "is_duplicate_case": True,
        "unique_case_count_eligible": False,
    }),
]

ENRICHMENT: dict[str, dict] = {_nk(title): meta for title, meta in _RAW}
