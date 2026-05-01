"""
Ground-truth metadata enrichment for the Yale SOM Case Book 2024.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_quant and difficulty_qual preserve the exact labels from the index:
    "Easy" | "Medium" | "Hard"

concepts_tested is stored as a semicolon-separated string, exactly as listed in
the index (whitespace trimmed around each semicolon).
"""

# Trigger: source_pdf contains "Yale 2024"
PDF_MATCH = "Yale 2024"

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Right Price Tea") → "right price tea"
    "right price tea": {
        "industry":         "CPG",
        "difficulty_quant": "Easy",
        "difficulty_qual":  "Easy",
        "concepts_tested":  "Market sizing; market entry; breakeven analysis",
    },
    # normalize_title("Eye-to-Eye") → "eye to eye"
    "eye to eye": {
        "industry":         "Non-profit: Public Education",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Opportunity comparison; cost-benefit analysis; non-profit thinking",
        "case_type":        "Opportunity Assessment",
    },
    # normalize_title("How Do I Get Ranked?") → "how do i get ranked"
    "how do i get ranked": {
        "industry":         "Higher Education",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Strategic moves; human capital strategy; graphical interpretation",
        "case_type":        "Strategy",
    },
    # normalize_title("Foreign Sounds") → "foreign sounds"
    "foreign sounds": {
        "industry":         "Non-traditional: Music Record Label",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Market assessment; market entry; revenue growth",
    },
    # normalize_title("Spruce Up Fir Real") → "spruce up fir real"
    "spruce up fir real": {
        "industry":         "Retail, CPG",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Medium",
        "concepts_tested":  "Profit calculations; brainstorming; interviewer-led",
    },
    # normalize_title("Plant-Powered Gains") → "plant powered gains"
    "plant powered gains": {
        "industry":         "Private Equity, CPG",
        "difficulty_quant": "Easy",
        "difficulty_qual":  "Hard",
        "concepts_tested":  "Market sizing; growth projections; complex exhibits",
    },
    # normalize_title("Excellence Corporation") → "excellence corporation"
    "excellence corporation": {
        "industry":         "Energy/Utilities, Digital",
        "difficulty_quant": "Medium",
        "difficulty_qual":  "Hard",
        "concepts_tested":  "Strategic cost reduction; opportunity comparison; cost-benefit analysis",
    },
    # normalize_title("Battery Co.") → "battery co"
    "battery co": {
        "industry":         "Private Equity",
        "difficulty_quant": "Hard",
        "difficulty_qual":  "Hard",
        "concepts_tested":  "Valuations; synergies; complex math",
    },
}
