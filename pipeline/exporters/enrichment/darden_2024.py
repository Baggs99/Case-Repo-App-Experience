"""
Ground-truth metadata enrichment for the Darden School of Business Case Book 2024.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_quant, difficulty_qual, and difficulty_overall are exact numeric scores
on a 1–3 scale from the casebook index. Do NOT convert to Easy/Medium/Hard.
"""

# Trigger: source_pdf contains "Darden 2024" OR "Darden 2023-24 Casebook"
PDF_MATCH = ("Darden 2024", "Darden 2023-24 Casebook")

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Sticky Surfactants") → "sticky surfactants"
    "sticky surfactants": {
        "industry":          "Chemicals",
        "case_type":         "Profitability",
        "difficulty_quant":  1,
        "difficulty_qual":   1,
        "difficulty":        1,
    },
    # normalize_title("Pedal Pals") → "pedal pals"
    "pedal pals": {
        "industry":          "Technology",
        "case_type":         "Cost Improvement",
        "difficulty_quant":  1,
        "difficulty_qual":   1,
        "difficulty":        1,
    },
    # normalize_title("Seven Flags") → "seven flags"
    "seven flags": {
        "industry":          "Entertainment",
        "case_type":         "Pricing",
        "difficulty_quant":  2,
        "difficulty_qual":   1,
        "difficulty":        1,
    },
    # normalize_title("Weasley's Wizarding Warehouse") → "weasley s wizarding warehouse"
    "weasley s wizarding warehouse": {
        "industry":          "Consumer/Retail",
        "case_type":         "Market Entry",
        "difficulty_quant":  1,
        "difficulty_qual":   2,
        "difficulty":        2,
    },
    # normalize_title("Jane Darden's Ranch") → "jane darden s ranch"
    "jane darden s ranch": {
        "industry":          "Hospitality",
        "case_type":         "Market Entry",
        "difficulty_quant":  2,
        "difficulty_qual":   2,
        "difficulty":        2,
    },
    # normalize_title("PharmaCo") → "pharmaco"
    "pharmaco": {
        "industry":          "Pharmaceuticals",
        "case_type":         "M&A",
        "difficulty_quant":  3,
        "difficulty_qual":   2,
        "difficulty":        2,
    },
    # normalize_title("Circle Bubble") → "circle bubble"
    "circle bubble": {
        "industry":          "Industrials",
        "case_type":         "Growth",
        "difficulty_quant":  3,
        "difficulty_qual":   2,
        "difficulty":        2,
    },
    # normalize_title("Shisha: Just Blowing Smoke?") → "shisha just blowing smoke"
    "shisha just blowing smoke": {
        "industry":          "Public Sector",
        "case_type":         "Market Entry",
        "difficulty_quant":  2,
        "difficulty_qual":   2,
        "difficulty":        2,
    },
    # normalize_title("Entertainment Co.") → "entertainment co"
    "entertainment co": {
        "industry":          "Entertainment",
        "case_type":         "M&A",
        "difficulty_quant":  2,
        "difficulty_qual":   2,
        "difficulty":        2,
    },
    # normalize_title("Robots Inc.") → "robots inc"
    "robots inc": {
        "industry":          "Tech/AI",
        "case_type":         "Growth",
        "difficulty_quant":  3,
        "difficulty_qual":   2,
        "difficulty":        2,
    },
    # normalize_title("Opus Two") → "opus two"
    "opus two": {
        "industry":          "Consumer",
        "case_type":         "Market Sizing / Optimization",
        "difficulty_quant":  2,
        "difficulty_qual":   3,
        "difficulty":        3,
    },
    # normalize_title("News Co.") → "news co"
    "news co": {
        "industry":          "Media",
        "case_type":         "Diagnosis / Profitability",
        "difficulty_quant":  3,
        "difficulty_qual":   3,
        "difficulty":        3,
    },
}
