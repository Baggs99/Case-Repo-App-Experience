"""
Ground-truth metadata enrichment for the NYU Stern Case Book 2021.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_quant and difficulty_structure are exact numeric scores (1–10) from the
"List of Cases" section of the casebook.

interviewer_led:
    True  → Interviewer-led
    False → Interviewee-led
"""

# Trigger: source_pdf contains "Stern 2021"
PDF_MATCH = "Stern 2021"

ENRICHMENT: dict[str, dict] = {
    # normalize_title("The Pricing Games") → "the pricing games"
    "the pricing games": {
        "case_type":            "Product Pricing",
        "industry":             "Technology",
        "difficulty_quant":     5,
        "difficulty_structure": 7,
        "interviewer_led":      True,
    },
    # normalize_title("Kungide") → "kungide"
    "kungide": {
        "case_type":            "Profitability/Operations",
        "industry":             "Industrial Products",
        "difficulty_quant":     7,
        "difficulty_structure": 9,
        "interviewer_led":      True,
    },
    # normalize_title("Men's Extra Comfortable Essentials") → "men s extra comfortable essentials"
    "men s extra comfortable essentials": {
        "case_type":            "Growth Strategy",
        "industry":             "Consumer Goods",
        "difficulty_quant":     8,
        "difficulty_structure": 6,
        "interviewer_led":      False,
    },
    # normalize_title("Dirty (Hot) Dogs") → "dirty hot dogs"
    "dirty hot dogs": {
        "case_type":            "Growth Strategy",
        "industry":             "Food and Beverage",
        "difficulty_quant":     7,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("WiFi in the Sky") → "wifi in the sky"
    "wifi in the sky": {
        "case_type":            "Market Entry",
        "industry":             "Airline",
        "difficulty_quant":     9,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("Tres Burritos") → "tres burritos"
    "tres burritos": {
        "case_type":            "Profitability",
        "industry":             "Restaurant",
        "difficulty_quant":     5,
        "difficulty_structure": 8,
        "interviewer_led":      True,
    },
    # normalize_title("FlashPro") → "flashpro"
    "flashpro": {
        "case_type":            "Growth Strategy",
        "industry":             "Technology",
        "difficulty_quant":     9,
        "difficulty_structure": 7,
        "interviewer_led":      True,
    },
    # normalize_title("Uranus Co.") → "uranus co"
    "uranus co": {
        "case_type":            "Market Entry",
        "industry":             "Travel/Hospitality",
        "difficulty_quant":     9,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("Stance at a Distance") → "stance at a distance"
    "stance at a distance": {
        "case_type":            "Cost Reduction",
        "industry":             "Education (Public Sector)",
        "difficulty_quant":     4,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("Grad-U-Date") → "grad u date"
    "grad u date": {
        "case_type":            "Pricing",
        "industry":             "Online Dating",
        "difficulty_quant":     6,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("Get-Health") → "get health"
    "get health": {
        "case_type":            "Revenue Growth",
        "industry":             "Healthcare",
        "difficulty_quant":     6,
        "difficulty_structure": 8,
        "interviewer_led":      False,
    },
    # normalize_title("Hook Co.") → "hook co"
    "hook co": {
        "case_type":            "Private Equity",
        "industry":             "Hospitality",
        "difficulty_quant":     8,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("Chocolate") → "chocolate"
    "chocolate": {
        "case_type":            "Market Entry",
        "industry":             "Consumer Goods",
        "difficulty_quant":     4,
        "difficulty_structure": 6,
        "interviewer_led":      False,
    },
    # normalize_title("Royal Cinema") → "royal cinema"
    "royal cinema": {
        "case_type":            "Market Entry",
        "industry":             "Entertainment",
        "difficulty_quant":     7,
        "difficulty_structure": 6,
        "interviewer_led":      True,
    },
    # normalize_title("Adventure Capital") → "adventure capital"
    "adventure capital": {
        "case_type":            "Investment Decision",
        "industry":             "Archaeology",
        "difficulty_quant":     8,
        "difficulty_structure": 5,
        "interviewer_led":      False,
    },
    # normalize_title("Steel Co.") → "steel co"
    "steel co": {
        "case_type":            "Cost Reduction",
        "industry":             "Industrial Goods",
        "difficulty_quant":     7,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("All Night Long") → "all night long"
    "all night long": {
        "case_type":            "Cost/Benefit Analysis",
        "industry":             "Entertainment",
        "difficulty_quant":     7,
        "difficulty_structure": 4,
        "interviewer_led":      False,
    },
    # normalize_title("Is Teleconferencing a Good Call?") → "is teleconferencing a good call"
    "is teleconferencing a good call": {
        "case_type":            "Cost Analysis",
        "industry":             "Financial Services",
        "difficulty_quant":     8,
        "difficulty_structure": 7,
        "interviewer_led":      False,
    },
    # normalize_title("Apple of My Eye") → "apple of my eye"
    "apple of my eye": {
        "case_type":            "Market Entry",
        "industry":             "Food and Beverage",
        "difficulty_quant":     7,
        "difficulty_structure": 6,
        "interviewer_led":      False,
    },
    # normalize_title("Jimmy's Dilemma") → "jimmy s dilemma"
    "jimmy s dilemma": {
        "case_type":            "Investment Decision",
        "industry":             "Recruiting",
        "difficulty_quant":     9,
        "difficulty_structure": 9,
        "interviewer_led":      False,
    },
    # normalize_title("Apartment Co.") → "apartment co"
    "apartment co": {
        "case_type":            "Profitability",
        "industry":             "Real Estate",
        "difficulty_quant":     7,
        "difficulty_structure": 8,
        "interviewer_led":      False,
    },
    # normalize_title("Great Burger") → "great burger"
    "great burger": {
        "case_type":            "M&A",
        "industry":             "Food and Beverage",
        "difficulty_quant":     8,
        "difficulty_structure": 9,
        "interviewer_led":      True,
    },
    # normalize_title("Drinks Gone Flat") → "drinks gone flat"
    "drinks gone flat": {
        "case_type":            "Revenue Growth",
        "industry":             "Retail",
        "difficulty_quant":     7,
        "difficulty_structure": 6,
        "interviewer_led":      True,
    },
    # normalize_title("Tofu Foundation") → "tofu foundation"
    "tofu foundation": {
        "case_type":            "Opportunity Assessment",
        "industry":             "Non-Profit",
        "difficulty_quant":     7,
        "difficulty_structure": 8,
        "interviewer_led":      True,
    },
    # normalize_title("Cups") → "cups"
    "cups": {
        "case_type":            "Opportunity Assessment",
        "industry":             "Consumer Goods",
        "difficulty_quant":     8,
        "difficulty_structure": 7,
        "interviewer_led":      True,
    },
}
