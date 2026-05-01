"""
Ground-truth metadata enrichment for the NYU Stern Case Book 2025.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_structure preserves the exact label from the Casing Contents table:
    "Easy" | "Medium" | "Hard"

difficulty_quant is not available for this casebook and is left absent (null in catalog).
"""

# Trigger: source_pdf contains "Stern 2025"
PDF_MATCH = "Stern 2025"

ENRICHMENT: dict[str, dict] = {
    # normalize_title("One Man's Trash") → "one man s trash"
    "one man s trash": {
        "case_type":            "Opportunity Assessment",
        "industry":             "Waste Management",
        "difficulty_structure": "Easy",
    },
    # normalize_title("The Pricing Games") → "the pricing games"
    "the pricing games": {
        "case_type":            "Product Pricing",
        "industry":             "Technology",
        "difficulty_structure": "Easy",
    },
    # normalize_title("Stance at a Distance") → "stance at a distance"
    "stance at a distance": {
        "case_type":            "Cost Reduction",
        "industry":             "Education (Public Sector)",
        "difficulty_structure": "Easy",
    },
    # normalize_title("Drinks Gone Flat") → "drinks gone flat"
    "drinks gone flat": {
        "case_type":            "Revenue Growth",
        "industry":             "Retail",
        "difficulty_structure": "Easy",
    },
    # normalize_title("Apple of My Eye") → "apple of my eye"
    "apple of my eye": {
        "case_type":            "Market Entry",
        "industry":             "Food and Beverage",
        "difficulty_structure": "Easy",
    },
    # normalize_title("Tres Burritos") → "tres burritos"
    "tres burritos": {
        "case_type":            "Profitability",
        "industry":             "Restaurant",
        "difficulty_structure": "Easy",
    },
    # normalize_title("Men's Extra Comfortable Essentials") → "men s extra comfortable essentials"
    "men s extra comfortable essentials": {
        "case_type":            "Growth Strategy",
        "industry":             "Consumer Goods",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Adventure Capital") → "adventure capital"
    "adventure capital": {
        "case_type":            "Investment Decision",
        "industry":             "Archaeology",
        "difficulty_structure": "Medium",
    },
    # normalize_title("All Night Long") → "all night long"
    "all night long": {
        "case_type":            "Cost/Benefit Analysis",
        "industry":             "Entertainment",
        "difficulty_structure": "Easy",
    },
    # normalize_title("GGC Health") → "ggc health"
    "ggc health": {
        "case_type":            "Revenue Growth",
        "industry":             "Healthcare",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Gassy Convenience") → "gassy convenience"
    "gassy convenience": {
        "case_type":            "Opportunity Assessment",
        "industry":             "Retail & Tech",
        "difficulty_structure": "Easy",
    },
    # normalize_title("The Rats Don't Run This City") → "the rats don t run this city"
    "the rats don t run this city": {
        "case_type":            "Opportunity Assessment",
        "industry":             "Government",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Nook Co.") → "nook co"
    "nook co": {
        "case_type":            "Private Equity",
        "industry":             "Hospitality",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Apartment Co.") → "apartment co"
    "apartment co": {
        "case_type":            "Profitability",
        "industry":             "Real Estate",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Sternofil") → "sternofil"
    "sternofil": {
        "case_type":            "M&A",
        "industry":             "Pharmaceutical",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Cups") → "cups"
    "cups": {
        "case_type":            "Opportunity Assessment",
        "industry":             "Consumer Goods",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Fungicide") → "fungicide"
    "fungicide": {
        "case_type":            "Profitability / Operations",
        "industry":             "Industrial Products",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Hybrid Work Model") → "hybrid work model"
    "hybrid work model": {
        "case_type":            "Cost / Change Management",
        "industry":             "Entertainment",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Toto Foundation") → "toto foundation"
    "toto foundation": {
        "case_type":            "Opportunity Assessment",
        "industry":             "Non-Profit",
        "difficulty_structure": "Medium",
    },
    # normalize_title("WiFi in the Sky") → "wifi in the sky"
    "wifi in the sky": {
        "case_type":            "Market Entry",
        "industry":             "Airline",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Take Your Pills") → "take your pills"
    "take your pills": {
        "case_type":            "Revenue Growth",
        "industry":             "Pharmaceutical",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Great Burger") → "great burger"
    "great burger": {
        "case_type":            "M&A",
        "industry":             "Food and Beverage",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Uranus Co.") → "uranus co"
    "uranus co": {
        "case_type":            "Market Entry",
        "industry":             "Travel/Hospitality",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Green Dreamz") → "green dreamz"
    "green dreamz": {
        "case_type":            "Growth Strategy",
        "industry":             "Retail",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Dr. Stern's Botanicals") → "dr stern s botanicals"
    "dr stern s botanicals": {
        "case_type":            "Profitability",
        "industry":             "Consumer Goods",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Mord Motor Co") → "mord motor co"
    "mord motor co": {
        "case_type":            "Market Entry / Product Mix",
        "industry":             "Automotive",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Curling and Careers") → "curling and careers"
    "curling and careers": {
        "case_type":            "Operations",
        "industry":             "Non-Profit",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Center Stage") → "center stage"
    "center stage": {
        "case_type":            "Market Entry",
        "industry":             "Theatre/Producing",
        "difficulty_structure": "Medium",
    },
    # normalize_title("Pharmageddon") → "pharmageddon"
    "pharmageddon": {
        "case_type":            "M&A",
        "industry":             "Pharmaceutical",
        "difficulty_structure": "Hard",
    },
    # normalize_title("Game On") → "game on"
    "game on": {
        "case_type":            "M&A",
        "industry":             "Streaming",
        "difficulty_structure": "Hard",
    },
}
