"""
Ground-truth metadata enrichment for the Ross School of Business Case Book 2022.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_visual_present = True for all cases — the TOC shows difficulty using
dot indicators (Overall / Quant / Qual) but exact numeric values were not transcribed.
Numeric scores should be left null until a dot-to-score converter is built.
"""

# Trigger: source_pdf contains "Ross 2022"
PDF_MATCH = "Ross 2022"

# Shared flag: all cases in this source have visual difficulty indicators
_DIFF_VISUAL = True

ENRICHMENT: dict[str, dict] = {
    "gaming challenges": {
        "industry":                "Media & Entertainment",
        "case_type":               "Go-to-Market Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "household cleaners growth": {
        "industry":                "CPG",
        "case_type":               "Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "little bud co": {
        # Normalized from "Little Bud Co." (period stripped)
        "industry":                "CPG",
        "case_type":               "Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "gasco goes the distance": {
        # Normalized from "GasCo Goes the Distance"
        "industry":                "Oil & Gas",
        "case_type":               "Market Entry / Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "rubicon co": {
        # Normalized from "Rubicon Co." (period stripped)
        "industry":                "Airlines",
        "case_type":               "Post-Acquisition Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "spice up your life": {
        "industry":                "PE & Food/Retail",
        "case_type":               "M&A / Valuation",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "apogee bank": {
        "industry":                "Financial Services",
        "case_type":               "Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "attack helicopter": {
        "industry":                "Defense",
        "case_type":               "Market Entry",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "flc sports league": {
        "industry":                "Sports",
        "case_type":               "Profitability & Market",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "marie s café": {
        # normalize_title("Marie's Café") → "marie s café" (accent preserved)
        "industry":                "Food",
        "case_type":               "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "marie s cafe": {
        # Fallback if PDF stores the title with ASCII 'e'
        "industry":                "Food",
        "case_type":               "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "midwest hospital": {
        "industry":                "Healthcare",
        "case_type":               "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "eurorail": {
        "industry":                "Hospitality",
        "case_type":               "Growth",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "dowork": {
        "industry":                "Technology & Real Estate",
        "case_type":               "Growth",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "banana heaven": {
        "industry":                "Public Sector",
        "case_type":               "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "one tree hill": {
        "industry":                "Non-Profits",
        "case_type":               "Micro-economics / Financing",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "alternative milk": {
        "industry":                "Consumer Packaged Goods",
        "case_type":               "M&A",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "jab we profit": {
        "industry":                "Telecom",
        "case_type":               "New Product",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    "new england trucks": {
        "industry":                "Power & Utilities",
        "case_type":               "Operations",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
}
