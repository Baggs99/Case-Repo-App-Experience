"""
Ground-truth metadata enrichment for Darden School of Business Case Book 2018–2019.

Keys are normalized case titles (lowercase, punctuation → space, collapsed
whitespace).

Each entry includes: firm, industry, round, difficulty (overall),
difficulty_quant, difficulty_qual (numeric 1–3 from the index).
"""

# Trigger: source_pdf contains "Darden 2019" OR "Darden 2018-2019"
PDF_MATCH = ("Darden 2019", "Darden 2018-2019", "Darden 2018_2019")

ENRICHMENT: dict[str, dict] = {
    # ── New 2019 Darden Cases ────────────────────────────────────────────────
    "national express trucking": {
        "firm":             "Bain & Co.",
        "industry":         "Transportation",
        "round":            1,
        "difficulty":       "1",
        "difficulty_quant": "1",
        "difficulty_qual":  "2",
    },
    "styrofoam situation": {
        "firm":             "BCG",
        "industry":         "Financial / PE",
        "round":            2,
        "difficulty":       "1",
        "difficulty_quant": "1",
        "difficulty_qual":  "2",
    },
    "north south pharma": {
        "firm":             "AT Kearney",
        "industry":         "Healthcare",
        "round":            1,
        "difficulty":       "2",
        "difficulty_quant": "2",
        "difficulty_qual":  "2",
        "case_type":        "Profitability",
    },
    "fire proof inc": {
        "firm":             "Parthenon EY",
        "industry":         "Manufacturing",
        "round":            1,
        "difficulty":       "2",
        "difficulty_quant": "2",
        "difficulty_qual":  "2",
    },
    "quality bottling co": {
        "firm":             "Parthenon EY",
        "industry":         "Manufacturing",
        "round":            1,
        "difficulty":       "2",
        "difficulty_quant": "2",
        "difficulty_qual":  "3",
    },
    "canyon capital": {
        "firm":             "Bain & Co.",
        "industry":         "Financial / PE",
        "round":            2,
        "difficulty":       "3",
        "difficulty_quant": "3",
        "difficulty_qual":  "2",
    },
    # ── Updated Darden Cases ─────────────────────────────────────────────────
    "transportation tech co": {
        "firm":             "Parthenon EY",
        "industry":         "Transportation",
        "round":            1,
        "difficulty":       "2",
        "difficulty_quant": "2",
        "difficulty_qual":  "2",
        "case_type":        "Market Entry",
    },
    "lonely gas station": {
        "firm":             "BCG",
        "industry":         "Financial",
        "round":            2,
        "difficulty":       "2",
        "difficulty_quant": "3",
        "difficulty_qual":  "1",
    },
    "copier co": {
        "firm":             "BCG",
        "industry":         "Consumer",
        "round":            1,
        "difficulty":       "2",
        "difficulty_quant": "3",
        "difficulty_qual":  "1",
    },
    "maxicure": {
        "firm":             "McKinsey",
        "industry":         "Healthcare",
        "round":            1,
        "difficulty":       "2",
        "difficulty_quant": "3",
        "difficulty_qual":  "2",
    },
    "to automate or not": {
        "firm":             "BCG",
        "industry":         "Retail",
        "round":            2,
        "difficulty":       "3",
        "difficulty_quant": "2",
        "difficulty_qual":  "3",
    },
    "rubber bumper laboratories": {
        "firm":             "McKinsey",
        "industry":         "Manufacturing",
        "round":            1,
        "difficulty":       "3",
        "difficulty_quant": "3",
        "difficulty_qual":  "3",
    },
}
