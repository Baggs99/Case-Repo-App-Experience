"""
Ground-truth metadata enrichment for Darden School of Business Case Book 2017.

Keys are normalized case titles (lowercase, punctuation → space, collapsed
whitespace).

Each entry includes: firm, round, difficulty (numeric 1–3 from the index).
"""

# Trigger: source_pdf contains "Darden 2017"
PDF_MATCH = "Darden 2017"

ENRICHMENT: dict[str, dict] = {
    "bank savings for savings bank cio": {
        "firm":      "McKinsey",
        "round":     2,
        "difficulty": "2",
        "case_type": "Cost Reduction",
    },
    "to automate or not": {
        "firm": "BCG",
        "round": 2,
        "difficulty": "3",
    },
    "broche laboratories": {
        "firm": "Bain",
        "round": 2,
        "difficulty": "3",
    },
    "ceo of your favorite company": {
        "firm": "McKinsey",
        "round": 2,
        "difficulty": "1",
    },
    "copier co": {
        "firm": "BCG",
        "round": 1,
        "difficulty": "2",
    },
    "henry s furniture": {
        "firm": "BCG",
        "round": 1,
        "difficulty": "1",
    },
    "cdc pharmaceuticals": {
        "firm": "McKinsey",
        "round": 1,
        "difficulty": "2",
    },
    "world vision": {
        "firm": "Deloitte",
        "round": 2,
        "difficulty": "2",
    },
    "maxicure": {
        "firm": "McKinsey",
        "round": 1,
        "difficulty": "2",
    },
    "railroad budget blowout": {
        "firm": "BCG",
        "round": 2,
        "difficulty": "2",
    },
    "saving the payphone company": {
        "firm": "McKinsey",
        "round": 2,
        "difficulty": "2",
    },
    "selling laylays in bahrain": {
        "firm": "A.T. Kearney",
        "round": 1,
        "difficulty": "2",
    },
    "starbucks ice cream dream": {
        "firm": "Bain",
        "round": 1,
        "difficulty": "1",
    },
    "transportation techco": {
        "firm":      "Parthenon",
        "round":     1,
        "difficulty": "2",
        "case_type": "Market Entry",
    },
}
