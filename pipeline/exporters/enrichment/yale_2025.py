"""
Ground-truth metadata enrichment for the Yale SOM Case Book 2025.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_quant and difficulty_qual preserve the exact labels from the index:
    "Easy" | "Medium" | "Hard"

concepts_tested is stored as a semicolon-separated string, exactly as listed in
the index (whitespace trimmed around each semicolon).

Deduplication:
    Eight cases in Yale 2025 are reprints of Yale 2024 cases.
    These rows receive is_duplicate_case = True and cross-reference fields so
    downstream analytics can exclude them from unique-case counts while still
    preserving full source traceability.

    Duplicate cases (also in Yale 2024):
        Right Price Tea, Eye-to-Eye, How Do I Get Ranked?, Foreign Sounds,
        Spruce Up Fir Real, Plant-Powered Gains, Excellence Corporation, Battery Co.

    Net-new cases unique to Yale 2025:
        A Case of the Cases, Outsourcing Odyssey, Shale Co., Breaking Brokers,
        Pinus Strobus Timber Investments, SkyHigh Airlines
"""

# Trigger: source_pdf contains "Yale 2025"
PDF_MATCH = "Yale 2025"

# Shared duplicate reference fields
_DUP_SCHOOL = "Yale"
_DUP_YEAR   = 2024


def _dup(title_2024: str) -> dict:
    """Return the shared deduplication fields for a case that also appeared in Yale 2024."""
    return {
        "is_duplicate_case":          True,
        "unique_case_count_eligible": False,
        "canonical_case_title":       title_2024,
        "duplicate_of_source_school": _DUP_SCHOOL,
        "duplicate_of_source_year":   _DUP_YEAR,
        "duplicate_of_case_title":    title_2024,
    }


ENRICHMENT: dict[str, dict] = {
    # ── Duplicate cases (also in Yale 2024) ───────────────────────────────────────

    # normalize_title("Right Price Tea") → "right price tea"
    "right price tea": {
        "industry":         "CPG",
        "difficulty_quant": "Easy",
        "difficulty_qual":  "Easy",
        "concepts_tested":  "Market sizing; market entry; breakeven analysis",
        "case_type":        "Market Entry",
        **_dup("Right Price Tea"),
    },
    # normalize_title("Eye-to-Eye") → "eye to eye"
    "eye to eye": {
        "industry":         "Non-profit: Public Education",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Opportunity comparison; cost-benefit analysis; non-profit thinking",
        "case_type":        "Opportunity Assessment",
        **_dup("Eye-to-Eye"),
    },
    # normalize_title("How Do I Get Ranked?") → "how do i get ranked"
    "how do i get ranked": {
        "industry":         "Higher Education",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Strategic moves; human capital strategy; graphical interpretation",
        "case_type":        "Strategy",
        **_dup("How Do I Get Ranked?"),
    },
    # normalize_title("Foreign Sounds") → "foreign sounds"
    "foreign sounds": {
        "industry":         "Non-traditional: Record Label",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Market assessment; market entry; revenue growth",
        "case_type":        "Market Entry",
        **_dup("Foreign Sounds"),
    },
    # normalize_title("Spruce Up Fir Real") → "spruce up fir real"
    "spruce up fir real": {
        "industry":         "Retail, CPG",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Profit calculations; brainstorming; interviewer-led",
        "case_type":        "Profitability",
        **_dup("Spruce Up Fir Real"),
    },
    # normalize_title("Plant-Powered Gains") → "plant powered gains"
    "plant powered gains": {
        "industry":         "Private Equity, CPG",
        "difficulty_quant": "Easy",
        "difficulty_qual":  "Hard",
        "concepts_tested":  "Market sizing; growth projections; complex exhibits",
        "case_type":        "Growth Strategy",
        **_dup("Plant-Powered Gains"),
    },
    # normalize_title("Excellence Corporation") → "excellence corporation"
    "excellence corporation": {
        "industry":         "Energy / Utilities, Digital",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Hard",
        "concepts_tested":  "Strategic cost reduction; opportunity comparison; cost-benefit analysis",
        "case_type":        "Cost Reduction",
        **_dup("Excellence Corporation"),
    },
    # normalize_title("Battery Co.") → "battery co"
    "battery co": {
        "industry":         "Private Equity",
        "difficulty_quant": "Hard",
        "difficulty_qual":  "Hard",
        "concepts_tested":  "Valuations; synergies; complex math",
        "case_type":        "M&A",
        **_dup("Battery Co."),
    },

    # ── Net-new cases unique to Yale 2025 ─────────────────────────────────────────

    # normalize_title("A Case of the Cases") → "a case of the cases"
    "a case of the cases": {
        "industry":                   "Fun / Random",
        "difficulty_quant":           "Easy",
        "difficulty_qual":            "Medium",
        "concepts_tested":            "Opportunity comparison; verbal exhibits",
        "case_type":                  "Opportunity Assessment",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "A Case of the Cases",
    },
    # normalize_title("Outsourcing Odyssey") → "outsourcing odyssey"
    "outsourcing odyssey": {
        "industry":                   "Financial Technology",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Medium",
        "concepts_tested":            "Procurement considerations; quality vs cost savings balance",
        "case_type":                  "Operations",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Outsourcing Odyssey",
    },
    # normalize_title("Shale Co.") → "shale co"
    "shale co": {
        "industry":                   "Energy (O&G)",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Hard",
        "concepts_tested":            "Market entry; profitability; opportunity analysis; pressure test",
        "case_type":                  "Market Entry",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Shale Co.",
    },
    # normalize_title("Breaking Brokers") → "breaking brokers"
    "breaking brokers": {
        "industry":                   "Retail / Grocery",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Hard",
        "concepts_tested":            "Profitability analysis; cost-benefit analysis; root cause analysis",
        "case_type":                  "Profitability",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Breaking Brokers",
    },
    # normalize_title("Pinus Strobus Timber Investments") → "pinus strobus timber investments"
    "pinus strobus timber investments": {
        "industry":                   "Investment Management, Natural Resources",
        "difficulty_quant":           "Hard",
        "difficulty_qual":            "Medium",
        "concepts_tested":            "Financial analysis (NPV, CAGR); interviewer-led",
        "case_type":                  "Investment Decision",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Pinus Strobus Timber Investments",
    },
    # normalize_title("SkyHigh Airlines") → "skyhigh airlines"
    "skyhigh airlines": {
        "industry":                   "Airline",
        "difficulty_quant":           "Hard",
        "difficulty_qual":            "Hard",
        "concepts_tested":            "Financial analysis; pressure test; interviewer-led",
        "case_type":                  "Profitability",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "SkyHigh Airlines",
    },
}
