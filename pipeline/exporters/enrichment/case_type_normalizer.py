"""
Case-type normalization.

Maps raw source-specific ``case_type`` values onto a small controlled
vocabulary suitable for app-side filtering.

Allowed normalized values
-------------------------

    Profitability
    Market Entry
    Growth Strategy
    Market Sizing
    M&A
    Pricing
    Cost Reduction
    Operations
    Opportunity Assessment
    Investment Decision
    Strategy
    Competitive Response
    New Product
    Organization / Human Capital
    Public Sector / Nonprofit
    Other

Resolution order
----------------
1. Exact match against a curated lowercase→canonical dictionary.
2. Substring fallback in priority order (e.g. any string containing
   ``"profitab"`` maps to Profitability, any string containing
   ``"m&a"``/``"acquisition"``/``"merger"`` maps to M&A, etc.).
3. If the raw value is blank/"Other" and *industry* clearly signals a
   public-sector or nonprofit case, return ``"Public Sector / Nonprofit"``.
4. Otherwise return ``"Other"``.

The design is intentionally deterministic — no LLM calls, no heuristics
on the case title.
"""

from __future__ import annotations

import re
from typing import Optional


# ── Allowed output values ─────────────────────────────────────────────────────
ALLOWED_CASE_TYPES = frozenset({
    "Profitability",
    "Market Entry",
    "Growth Strategy",
    "Market Sizing",
    "M&A",
    "Pricing",
    "Cost Reduction",
    "Operations",
    "Opportunity Assessment",
    "Investment Decision",
    "Strategy",
    "Competitive Response",
    "New Product",
    "Organization / Human Capital",
    "Public Sector / Nonprofit",
    "Other",
})


# ── 1. Exact-match dictionary (lowercase keys) ────────────────────────────────
# Compound values are routed according to the spec (e.g. the spec lists
# "Profitability / Market Entry" under Profitability, so direct match wins).

_DIRECT: dict[str, str] = {
    # Profitability
    "profitability":                              "Profitability",
    "profitability improvement":                  "Profitability",
    "improving profitability":                    "Profitability",
    "diagnosis / profitability":                  "Profitability",
    "revenue growth":                             "Profitability",
    "revenue":                                    "Profitability",
    "post-acquisition profitability":             "Profitability",
    "profitability / market entry":               "Profitability",
    "market entry / profitability":               "Market Entry",   # leading segment
    "profitability / operations":                 "Profitability",
    "profitability/operations":                   "Profitability",
    "profitability, pricing":                     "Profitability",
    "profitability/growth strategy":              "Profitability",
    "profitability & market":                     "Profitability",
    "turnaround":                                 "Profitability",

    # Market Entry
    "market entry":                               "Market Entry",
    "market assessment":                          "Market Entry",
    "go-to-market strategy":                      "Market Entry",
    "market entry / product mix":                 "Market Entry",
    "market entry / market sizing":               "Market Entry",
    "new product/market entry":                   "Market Entry",

    # Growth Strategy
    "growth":                                     "Growth Strategy",
    "growth strategy":                            "Growth Strategy",
    "growth /":                                   "Growth Strategy",

    # New Product
    "new product":                                "New Product",
    "product launch":                             "New Product",

    # Market Sizing
    "market sizing":                              "Market Sizing",

    # M&A
    "m&a":                                        "M&A",
    "mergers & acquisitions":                     "M&A",
    "private equity":                             "M&A",
    "private equity & profitability improvement": "M&A",
    "m&a / valuation":                            "M&A",
    "m&a, valuation financial":                   "M&A",

    # Pricing
    "pricing":                                    "Pricing",
    "product pricing":                            "Pricing",

    # Cost Reduction
    "cost reduction":                             "Cost Reduction",
    "cost improvement":                           "Cost Reduction",
    "strategic cost reduction":                   "Cost Reduction",
    "sourcing / outsourcing":                     "Cost Reduction",
    "cost/benefit analysis":                      "Cost Reduction",
    "cost analysis":                              "Cost Reduction",
    "cost / change management":                   "Cost Reduction",
    "cost reduction and m&a":                     "Cost Reduction",

    # Operations
    "operations":                                 "Operations",
    "operating model":                            "Operations",
    "implementation":                             "Operations",
    "optimization":                               "Operations",
    "market sizing / optimization":               "Operations",
    "asset optimization":                         "Operations",

    # Opportunity / Investment
    "opportunity assessment":                     "Opportunity Assessment",
    "investment decision":                        "Investment Decision",
    "investment":                                 "Investment Decision",
    "decision analysis":                          "Investment Decision",
    "financial decisioning":                      "Investment Decision",
    "new investment analysis":                    "Investment Decision",

    # Strategy
    "strategy":                                   "Strategy",
    "strategy formulation":                       "Strategy",
    "sustainability":                             "Strategy",

    # Competitive Response
    "competitive response":                       "Competitive Response",
    "business-response":                          "Competitive Response",
    "business response":                          "Competitive Response",
    "non-traditional problem":                    "Competitive Response",
    "competitor analysis":                        "Competitive Response",

    # Organization / Human Capital
    "organizational change":                      "Organization / Human Capital",
    "human resources":                            "Organization / Human Capital",
    "human capital strategy":                     "Organization / Human Capital",

    # Other / catch-alls that are too vague to bucket
    "other":                                      "Other",
    "impact analysis":                            "Other",
    "legal analysis":                             "Other",
    "micro-economics / financing":                "Other",
    "market":                                     "Other",
}


# ── 2. Substring fallback (first match wins) ──────────────────────────────────
# Order matters: more specific substrings before generic ones so that e.g.
# "Cost Reduction and M&A" matches "cost" before "m&a".

_SUBSTRING_RULES: list[tuple[str, str]] = [
    # M&A signals
    ("merger",                  "M&A"),
    ("acquisition",             "M&A"),
    ("m&a",                     "M&A"),
    ("private equity",          "M&A"),

    # Market Entry signals
    ("market entry",            "Market Entry"),
    ("go-to-market",            "Market Entry"),
    ("go to market",            "Market Entry"),
    ("market assessment",       "Market Entry"),

    # Market Sizing (check before the broader "market" rule)
    ("market sizing",           "Market Sizing"),

    # Profitability signals
    ("profitab",                "Profitability"),
    ("turnaround",              "Profitability"),
    ("revenue",                 "Profitability"),

    # Growth signals
    ("growth",                  "Growth Strategy"),

    # New Product signals
    ("new product",             "New Product"),
    ("product launch",          "New Product"),

    # Pricing signals
    ("pricing",                 "Pricing"),

    # Cost signals
    ("cost",                    "Cost Reduction"),
    ("sourcing",                "Cost Reduction"),

    # Investment / opportunity signals
    ("opportunity",             "Opportunity Assessment"),
    ("investment",              "Investment Decision"),
    ("decision",                "Investment Decision"),

    # Competitive Response signals
    ("competitive response",    "Competitive Response"),
    ("competitor",              "Competitive Response"),
    ("business response",       "Competitive Response"),
    ("business-response",       "Competitive Response"),

    # Org / Human Capital signals
    ("organizational",          "Organization / Human Capital"),
    ("human resource",          "Organization / Human Capital"),
    ("human capital",           "Organization / Human Capital"),

    # Operations signals
    ("operation",               "Operations"),
    ("optimization",            "Operations"),
    ("implementation",          "Operations"),
    ("operating model",         "Operations"),

    # Strategy signals (broadest — last)
    ("sustainability",          "Strategy"),
    ("strategy",                "Strategy"),
]


# ── 3. Public-sector / nonprofit detection from industry field ────────────────
_PUBLIC_INDUSTRY_RE = re.compile(
    r"\b(public\s+sector|public-sector|government|nonprofits?|non-profits?|"
    r"not[- ]for[- ]profits?|ngos?|civic)\b",
    re.IGNORECASE,
)


# ── Public API ────────────────────────────────────────────────────────────────

def normalize_case_type(
    raw_case_type: Optional[str],
    *,
    source_school: Optional[str] = None,
    industry: Optional[str] = None,
) -> str:
    """
    Map *raw_case_type* onto the controlled vocabulary (see ALLOWED_CASE_TYPES).

    Parameters
    ----------
    raw_case_type:
        The exact value from the catalog's ``case_type`` column.  May be
        ``None`` or empty.
    source_school:
        Reserved for future school-specific overrides; currently unused
        except for the public-sector heuristic.
    industry:
        Optional industry/sector string.  Used to reroute blank / "Other"
        values to ``Public Sector / Nonprofit`` when the industry clearly
        signals it (e.g. ``"Government"``, ``"Nonprofit"``).

    Returns
    -------
    One of ``ALLOWED_CASE_TYPES``.  Always a non-empty string; unmapped
    inputs default to ``"Other"`` (or ``"Public Sector / Nonprofit"`` when
    the industry indicates it).
    """
    raw = (raw_case_type or "").strip()
    key = raw.lower()

    # 1. Direct lookup
    if key in _DIRECT:
        mapped = _DIRECT[key]
    else:
        mapped = None

        # 2. Substring fallback
        if key:
            for needle, canonical in _SUBSTRING_RULES:
                if needle in key:
                    mapped = canonical
                    break

        # 3. Nothing matched → Other (will be refined by industry rule below)
        if mapped is None:
            mapped = "Other"

    # 4. Public-sector override for Other / blank
    if mapped == "Other" and industry and _PUBLIC_INDUSTRY_RE.search(industry):
        return "Public Sector / Nonprofit"

    return mapped
