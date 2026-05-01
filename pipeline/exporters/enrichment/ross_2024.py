"""
Ground-truth metadata enrichment for the Ross School of Business Case Book 2024.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_visual_present = True for all cases — the TOC shows difficulty using
dot indicators (Overall / Quant / Qual) but exact numeric values were not transcribed.
Numeric scores should be left null until a dot-to-score converter is built.
"""

# Trigger: source_pdf contains "Ross 2024"
PDF_MATCH = "Ross 2024"

_DIFF_VISUAL = True

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Big Ten Bivalves") → "big ten bivalves"
    "big ten bivalves": {
        "industry":                  "Food/aquaculture",
        "case_type":                 "Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Maize & Blue Cement") → "maize blue cement"
    "maize blue cement": {
        "industry":                  "Construction",
        "case_type":                 "Profitability/Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Household Cleaners Growth") → "household cleaners growth"
    "household cleaners growth": {
        "industry":                  "CPG",
        "case_type":                 "Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Melt That Snow") → "melt that snow"
    "melt that snow": {
        "industry":                  "Public Sector",
        "case_type":                 "Go-to-Market Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Malaria Remedy") → "malaria remedy"
    "malaria remedy": {
        "industry":                  "Healthcare",
        "case_type":                 "Go-to-Market Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Donatella Co.") → "donatella co"
    "donatella co": {
        "industry":                  "CPG",
        "case_type":                 "Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("GasCo Goes the Distance") → "gasco goes the distance"
    "gasco goes the distance": {
        "industry":                  "Oil & Gas",
        "case_type":                 "Market Entry/Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Rubicon Co.") → "rubicon co"
    "rubicon co": {
        "industry":                  "Airlines",
        "case_type":                 "Post-Acquisition Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Banana Heaven") → "banana heaven"
    "banana heaven": {
        "industry":                  "Public Sector",
        "case_type":                 "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("One Tree Hill") → "one tree hill"
    "one tree hill": {
        "industry":                  "Non Profits",
        "case_type":                 "Micro-Economics, Financing",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Let's Vroom") → "let s vroom"
    "let s vroom": {
        "industry":                  "Sports",
        "case_type":                 "Profitability, Pricing",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("DoWork") → "dowork"
    "dowork": {
        "industry":                  "Technology & Real Estate",
        "case_type":                 "Growth",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Spice Up Your Life") → "spice up your life"
    "spice up your life": {
        "industry":                  "Private Equity, Food/Retail",
        "case_type":                 "M&A, Valuation Financial",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Apogee Bank") → "apogee bank"
    "apogee bank": {
        "industry":                  "Services",
        "case_type":                 "Growth Strategy",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Marie's Café") → "marie s café"  (accent preserved by normalize_title)
    "marie s café": {
        "industry":                  "Food",
        "case_type":                 "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # Fallback if PDF stores the title with ASCII 'e'
    "marie s cafe": {
        "industry":                  "Food",
        "case_type":                 "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Midwest Hospital") → "midwest hospital"
    "midwest hospital": {
        "industry":                  "Healthcare",
        "case_type":                 "Profitability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("Jab We Profit") → "jab we profit"
    "jab we profit": {
        "industry":                  "Telecom",
        "case_type":                 "New Product",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("WolverineHomes") → "wolverinehomes"
    "wolverinehomes": {
        "industry":                  "Real Estate & Energy",
        "case_type":                 "Sustainability",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
    # normalize_title("TW Tech") → "tw tech"
    "tw tech": {
        "industry":                  "Technology",
        "case_type":                 "Market Entry",
        "difficulty_visual_present": _DIFF_VISUAL,
    },
}
