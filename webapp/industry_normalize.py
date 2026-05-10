"""
Canonical industry labels for browse / search UX.

The database keeps the original ``industry`` string from enrichment;
this module maps noisy variants onto a small set of broad categories
used for filter dropdowns, SQL filtering, and card display.
"""

from __future__ import annotations

import re
from typing import Any, Optional, Sequence

# Ordered rules: first matching pattern wins. Patterns are checked as
# lowercase substrings on a punctuation-collapsed ``match key``.
_CANONICAL_RULES: tuple[tuple[str, tuple[str, ...]], ...] = (
    # Healthcare before Technology so ``medtech`` / ``health tech`` map correctly.
    (
        "Aerospace, Airlines & Transportation",
        (
            "aerospace",
            "airline",
            "airlines",
            "aviation",
            "aircraft",
            "defense",
            "aerospace and defense",
            "aerospace and defence",
            "military",
            "space ",
            "rocket",
        ),
    ),
    (
        "Healthcare & Life Sciences",
        (
            "healthcare",
            "health care",
            "pharma",
            "pharmaceutical",
            "biotech",
            "biopharma",
            "bio pharma",
            "medical",
            "medtech",
            "med device",
            "hospital",
            "clinical",
            "life science",
            "health insurance",
            "dental",
            "veterinary",
        ),
    ),
    (
        "Hospitality & Leisure",
        (
            "hospitality",
            "hotel",
            "cruise",
            "resort",
            "tourism",
            "travel",
            "leisure",
            "casino",
            "theme park",
            "restaurant",
            "restaurants",
        ),
    ),
    (
        "Consumer & Retail",
        (
            "consumer",
            "retail",
            "cpg",
            "food and beverage",
            "food & beverage",
            "grocery",
            "apparel",
            "fashion",
            "luxury",
            "ecommerce",
            "e commerce",
            "car product",
            "automotive retail",
        ),
    ),
    (
        "Financial Services",
        (
            "banking",
            "bank ",
            " banks",
            "financial service",
            "financial services",
            "finance",
            "fintech",
            "asset management",
            "wealth management",
            "private wealth",
            "insurance",
            "credit union",
            "investment bank",
            "capital market",
            "hedge fund",
            "reit",
        ),
    ),
    (
        "Media & Entertainment",
        (
            "media",
            "entertainment",
            "broadcast",
            "publishing",
            "streaming",
            "film",
            "music",
            "gaming",
            "sports media",
        ),
    ),
    (
        "Energy & Utilities",
        (
            "oil and gas",
            "oil & gas",
            "oil",
            "natural gas",
            "utility",
            "utilities",
            "power ",
            "electric",
            "renewable",
            "solar",
            "wind energy",
            "energy",
            "mining",
            "upstream",
            "downstream",
        ),
    ),
    (
        "Industrials & Manufacturing",
        (
            "manufacturing",
            "industrial",
            "chemical",
            "chemicals",
            "machinery",
            "oem",
            "automotive",
            "aerospace manufacturing",
            "steel",
            "construction equipment",
            "heavy industry",
            "industrials",
        ),
    ),
    (
        "Agriculture & Food",
        (
            "agriculture",
            "agri",
            "farming",
            "crop",
            "fisheries",
            "aquaculture",
            "ranch",
        ),
    ),
    (
        "Real Estate",
        (
            "real estate",
            "property",
            "housing",
            "commercial real",
            "residential real",
        ),
    ),
    (
        "Education",
        (
            "education",
            "university",
            "k-12",
            "k12",
            "pre-k",
            "higher education",
            "school district",
        ),
    ),
    (
        "Government & Public Sector",
        (
            "government",
            "public sector",
            "federal",
            "municipal",
            "public education",
            "defense contract",
        ),
    ),
    (
        "Private Equity",
        (
            "private equity",
            "venture capital",
            " buyout",
            "lbo",
        ),
    ),
    (
        "Legal & Professional Services",
        (
            "legal",
            "law firm",
            "professional service",
            "accounting",
            "consulting",
        ),
    ),
    (
        "Non-profit & Social Impact",
        (
            "non-profit",
            "nonprofit",
            "foundation",
            "charity",
            "ngo",
            "social impact",
        ),
    ),
    (
        "Construction & Engineering",
        (
            "construction",
            "engineering and construction",
            "engineering & construction",
            "infrastructure",
        ),
    ),
    (
        "Technology",
        (
            "software",
            "internet",
            "saas",
            "cloud",
            "semiconductor",
            "cyber",
            "technology",
            "digital",
            "data center",
            "e commerce",
            "e-commerce",
            "platform",
            "it services",
            "information technology",
        ),
    ),
    (
        "Telecommunications",
        (
            "telecom",
            "telecommunication",
            "wireless",
            "mobile network",
            "telco",
            "5g",
            "4g",
        ),
    ),
    (
        "Transportation & Logistics",
        (
            "logistics",
            "freight",
            "trucking",
            "railroad",
            "rail transport",
            "shipping",
            "supply chain",
            "warehouse",
            "warehousing",
            "courier",
            "parcel",
            "fleet",
            "transportation and logistics",
            "transportation and automotive",
            "transportation",
        ),
    ),
)

_NOISE_PLACEHOLDERS = frozenset(
    {
        "",
        "-",
        "—",
        "n/a",
        "na",
        "none",
        "unknown",
        "tbd",
        "misc",
        "mixed",
        "various",
        "...",
        ".",
        "??",
    }
)


def _prepare_match_key(raw: str) -> str:
    t = raw.lower().strip()
    t = t.replace("&", " and ")
    t = t.replace("/", " ")
    t = t.replace("+", " ")
    t = re.sub(r"[_]+", " ", t)
    t = re.sub(r"[^\w\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def normalize_industry_label(raw: Optional[str]) -> Optional[str]:
    """Map a raw DB industry string to a canonical label, or ``None`` if empty/noise.

    Unrecognized non-empty strings become ``"Other"`` so the UI stays
    clean while the original remains in ``industry`` / ``industry_raw``.
    """
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    if s.lower() in _NOISE_PLACEHOLDERS:
        return None

    key = _prepare_match_key(s)
    if not key:
        return None

    for canonical, patterns in _CANONICAL_RULES:
        for p in patterns:
            if p in key:
                return canonical
    return "Other"


def attach_industry_display(row: Optional[dict[str, Any]]) -> None:
    """Mutate a case row dict with ``industry_display`` / ``industry_raw`` for templates."""
    if row is None:
        return
    raw = row.get("industry")
    row["industry_raw"] = raw
    disp = normalize_industry_label(raw) if raw is not None else None
    row["industry_display"] = disp


def industry_raws_matching_canonical(
    canonical: str, raw_distinct: Sequence[str]
) -> list[str]:
    """Return every distinct raw value that normalizes to ``canonical``."""
    out: set[str] = set()
    for r in raw_distinct:
        if r is None:
            continue
        rs = str(r).strip()
        if not rs:
            continue
        if normalize_industry_label(rs) == canonical:
            out.add(rs)
    return sorted(out)
