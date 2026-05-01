"""
Ground-truth metadata enrichment for Darden School of Business Case Book 2021.

Keys are normalized case titles (lowercase, punctuation → space, collapsed
whitespace).
"""

# Trigger: source_pdf contains "Darden 2021"
PDF_MATCH = "Darden 2021"

ENRICHMENT: dict[str, dict] = {
    "alpha aviation": {
        "firm":     "McKinsey",
        "industry": "Aviation",
        "round":    2,
    },
    "back it on up": {
        "firm":     "EYP",
        "industry": "Tech",
        "round":    2,
    },
    "the big shot": {
        "firm":     "Bain",
        "industry": "Entertainment",
        "round":    1,
    },
    "contagion containment": {
        "firm":      "BCG",
        "industry":  "Non-Profit",
        "round":     2,
        "case_type": "Decision Analysis",
    },
    "food frenzy": {
        "firm":     "IDEO",
        "industry": "Retail",
        "round":    2,
    },
    "a hairy ordeal": {
        "firm":     "Bain",
        "industry": "Retail",
        "round":    1,
    },
    "lizard insurance": {
        "firm":     "Bain",
        "industry": "Insurance",
        "round":    1,
    },
    "met with problems": {
        "firm":     "BCG",
        "industry": "Non-Profit",
        "round":    1,
    },
    "a messi decision": {
        "firm":     "BCG",
        "industry": "Sports",
        "round":    1,
    },
    "new rubber plant investment": {
        "firm":     "AT Kearney",
        "industry": "Industrial",
        "round":    2,
    },
    "pubu": {
        "firm":     "McKinsey",
        "industry": "Energy",
        "round":    1,
    },
    "whale hotel": {
        "firm":      "McKinsey",
        "industry":  "Real Estate",
        "round":     2,
        "case_type": "Investment Decision",
    },
}
