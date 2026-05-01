"""
Ground-truth metadata enrichment for the MIT Sloan Case Book 2011.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

firm and round are parsed deterministically from the hardcoded parenthetical
suffixes in each title. No inference is performed.

source_school and source_year are set here to correct any classifier mismatch
caused by the file's folder location.
"""

# Trigger: source_pdf contains "MIT 2011"
PDF_MATCH = "MIT 2011"

_BASE = {
    "source_school": "MIT",
    "source_year":   2011,
}

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Antidepressant Pricing (BCG, Round 1)") → "antidepressant pricing bcg round 1"
    "antidepressant pricing bcg round 1": {
        **_BASE,
        "firm":  "BCG",
        "round": "Round 1",
    },
    # normalize_title("Media and Operations (BCG, Round 1)") → "media and operations bcg round 1"
    "media and operations bcg round 1": {
        **_BASE,
        "firm":  "BCG",
        "round": "Round 1",
        "difficulty": "Easy",
    },
    # normalize_title("Zippy Snowmobiles (McKinsey, Round 1)") → "zippy snowmobiles mckinsey round 1"
    "zippy snowmobiles mckinsey round 1": {
        **_BASE,
        "firm":  "McKinsey",
        "round": "Round 1",
        "difficulty": "Medium",
    },
    # normalize_title("Bicycle Part Manufacturer (Bain, Round 1)") → "bicycle part manufacturer bain round 1"
    "bicycle part manufacturer bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Medium",
    },
    # normalize_title("Pharmacy in Supermarket (Bain, Round 1)") → "pharmacy in supermarket bain round 1"
    "pharmacy in supermarket bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Easy",
    },
    # normalize_title("Megabank Under-penetration (McKinsey, Round 1)") → "megabank under penetration mckinsey round 1"
    "megabank under penetration mckinsey round 1": {
        **_BASE,
        "firm":  "McKinsey",
        "round": "Round 1",
        "difficulty": "Medium",
    },
    # normalize_title("Moldovian Coffins (McKinsey, Round 1)") → "moldovian coffins mckinsey round 1"
    "moldovian coffins mckinsey round 1": {
        **_BASE,
        "firm":  "McKinsey",
        "round": "Round 1",
        "difficulty": "Hard",
    },
    # normalize_title("Fast Food Probability (McKinsey, Mock Case)") → "fast food probability mckinsey mock case"
    "fast food probability mckinsey mock case": {
        **_BASE,
        "firm":  "McKinsey",
        "round": "Mock Case",
        "difficulty": "Hard",
    },
    # normalize_title("Always Fresh (BCG, Mock Case)") → "always fresh bcg mock case"
    "always fresh bcg mock case": {
        **_BASE,
        "firm":  "BCG",
        "round": "Mock Case",
    },
    # normalize_title("Learjet (Bain, Mock Case)") → "learjet bain mock case"
    "learjet bain mock case": {
        **_BASE,
        "firm":  "Bain",
        "round": "Mock Case",
        "difficulty": "Medium",
    },
    # normalize_title("Luxury Cruise (Booz, Round 1)") → "luxury cruise booz round 1"
    "luxury cruise booz round 1": {
        **_BASE,
        "firm":  "Booz",
        "round": "Round 1",
        "difficulty": "Easy",
    },
    # normalize_title("Rental Cars & Frequent Flyer Miles (BCG, Round 1)") → "rental cars frequent flyer miles bcg round 1"
    "rental cars frequent flyer miles bcg round 1": {
        **_BASE,
        "firm":  "BCG",
        "round": "Round 1",
        "difficulty": "Hard",
    },
    # normalize_title("Spanish Trains (McKinsey, Round 1)") → "spanish trains mckinsey round 1"
    "spanish trains mckinsey round 1": {
        **_BASE,
        "firm":  "McKinsey",
        "round": "Round 1",
        "difficulty": "Medium",
    },
    # normalize_title("Store Tissue Label Manufacturer (BCG, Round 1)") → "store tissue label manufacturer bcg round 1"
    "store tissue label manufacturer bcg round 1": {
        **_BASE,
        "firm":  "BCG",
        "round": "Round 1",
        "difficulty": "Medium",
    },
    # normalize_title("Fruit Juice (Bain, Round 1)") → "fruit juice bain round 1"
    "fruit juice bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Hard",
    },
    # normalize_title("Art Museum (McKinsey, Round 1)") → "art museum mckinsey round 1"
    "art museum mckinsey round 1": {
        **_BASE,
        "firm":  "McKinsey",
        "round": "Round 1",
    },
    # normalize_title("Broadband Internet Service Provider (Bain, Round 1)") → "broadband internet service provider bain round 1"
    "broadband internet service provider bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
    },
    # normalize_title("Industrial Tools Manufacturer (Bain, Round 1)") → "industrial tools manufacturer bain round 1"
    "industrial tools manufacturer bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Hard",
    },
    # normalize_title("Toothpaste Company (Bain, Round 1)") → "toothpaste company bain round 1"
    "toothpaste company bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Medium",
    },
    # normalize_title("Recreational Aircraft (Bain, Round 1)") → "recreational aircraft bain round 1"
    "recreational aircraft bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Hard",
    },
    # normalize_title("Consumer Packaged Goods (Bain, Round 1)") → "consumer packaged goods bain round 1"
    "consumer packaged goods bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
    },
    # normalize_title("Domino's Pizza (Bain, Round 1)") → "domino s pizza bain round 1"
    "domino s pizza bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Medium",
    },
    # normalize_title("Credit Card Company (Bain, Round 1)") → "credit card company bain round 1"
    "credit card company bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
    },
    # normalize_title("Utility Company (Bain, Round 1)") → "utility company bain round 1"
    "utility company bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
        "difficulty": "Hard",
    },
    # normalize_title("Dairy Farm (Bain, Round 1)") → "dairy farm bain round 1"
    "dairy farm bain round 1": {
        **_BASE,
        "firm":  "Bain",
        "round": "Round 1",
    },
}
