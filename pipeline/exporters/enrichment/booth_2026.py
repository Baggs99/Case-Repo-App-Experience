"""
Ground-truth metadata enrichment for the Booth School of Business Case Book 2026.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

All values are hardcoded verbatim from the Index of Practice Cases.
Nothing is inferred, extracted, or computed dynamically.

Difficulty mapping applied (quant level → difficulty label):
    Light  → Easy
    Medium → Medium
    Heavy  → Hard
"""

# Trigger: source_pdf contains "Booth 2026"
PDF_MATCH = "Booth 2026"

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Army Hotel") → "army hotel"
    "army hotel": {
        "firm":       "McKinsey & Company",
        "case_type":  "Market Entry",
        "industry":   "Hospitality",
        "difficulty": "Medium",
    },
    # normalize_title("Breast Cancer Surgery") → "breast cancer surgery"
    "breast cancer surgery": {
        "firm":       "L.E.K. Consulting",
        "case_type":  "Profitability",
        "industry":   "Healthcare",
        "difficulty": "Easy",
    },
    # normalize_title("Burger Palace") → "burger palace"
    "burger palace": {
        "firm":       "Undisclosed",
        "case_type":  "Market Entry",
        "industry":   "Restaurants, Food & Beverage",
        "difficulty": "Medium",
    },
    # normalize_title("Chicken Pox Vaccine") → "chicken pox vaccine"
    "chicken pox vaccine": {
        "firm":       "Undisclosed",
        "case_type":  "Market Sizing",
        "industry":   "Pharmaceutical/Healthcare",
        "difficulty": "Hard",
    },
    # normalize_title("Cleaning Products") → "cleaning products"
    "cleaning products": {
        "firm":       "McKinsey & Company",
        "case_type":  "Growth Strategy",
        "industry":   "Consumer Products",
        "difficulty": "Medium",
    },
    # normalize_title("Coffee and Tea Apparel") → "coffee and tea apparel"
    "coffee and tea apparel": {
        "firm":       "Deloitte",
        "case_type":  "Mergers & Acquisitions",
        "industry":   "Retail & Apparel",
        "difficulty": "Hard",
    },
    # normalize_title("Commercial Vehicle OEM in China") → "commercial vehicle oem in china"
    "commercial vehicle oem in china": {
        "firm":       "Strategy&",
        "case_type":  "Growth Strategy",
        "industry":   "Transportation & Automotive",
        "difficulty": "Medium",
    },
    # normalize_title("Consumer Products Strategy") → "consumer products strategy"
    "consumer products strategy": {
        "firm":       "BCG",
        "case_type":  "Market Entry",
        "industry":   "Consumer Products",
        "difficulty": "Medium",
    },
    # normalize_title("Contact Lenses") → "contact lenses"
    "contact lenses": {
        "firm":       "McKinsey & Company",
        "case_type":  "Profitability",
        "industry":   "Consumer Products",
        "difficulty": "Medium",
    },
    # normalize_title("Deepwater Inc.") → "deepwater inc"
    "deepwater inc": {
        "firm":       "Undisclosed",
        "case_type":  "Investment Decision",
        "industry":   "Energy",
        "difficulty": "Easy",
    },
    # normalize_title("Electric Utility") → "electric utility"
    "electric utility": {
        "firm":       "McKinsey & Company",
        "case_type":  "Profitability",
        "industry":   "Energy",
        "difficulty": "Easy",
    },
    # normalize_title("Elena's Electronics") → "elena s electronics"
    "elena s electronics": {
        "firm":       "Undisclosed",
        "case_type":  "Profitability",
        "industry":   "Consumer Electronics",
        "difficulty": "Hard",
    },
    # normalize_title("Finance Co") → "finance co"
    "finance co": {
        "firm":       "Bain & Company",
        "case_type":  "Growth Strategy",
        "industry":   "Financial Services",
        "difficulty": "Hard",
    },
    # normalize_title("French Beauty Co") → "french beauty co"
    "french beauty co": {
        "firm":       "Accenture",
        "case_type":  "Operating Model",
        "industry":   "Retail & Apparel",
        "difficulty": "Easy",
    },
    # normalize_title("German Telecom") → "german telecom"
    "german telecom": {
        "firm":       "BCG",
        "case_type":  "Profitability",
        "industry":   "Telecommunications",
        "difficulty": "Medium",
    },
    # normalize_title("Green Co") → "green co"
    "green co": {
        "firm":       "Deloitte",
        "case_type":  "Investment Decision",
        "industry":   "Retail & Leisure",
        "difficulty": "Hard",
    },
    # normalize_title("GreenShield Health Insurance") → "greenshield health insurance"
    "greenshield health insurance": {
        "firm":       "Strategy&",
        "case_type":  "Market Entry / Market Sizing",
        "industry":   "Financial Services & Insurance",
        "difficulty": "Medium",
    },
    # normalize_title("Hawaiian Smoothies") → "hawaiian smoothies"
    "hawaiian smoothies": {
        "firm":       "BCG",
        "case_type":  "Market Entry",
        "industry":   "Restaurants, Food & Beverage",
        "difficulty": "Medium",
    },
    # normalize_title("Heavy Attrition") → "heavy attrition"
    "heavy attrition": {
        "firm":       "Z.S. Associates",
        "case_type":  "Organizational Change",
        "industry":   "Healthcare",
        "difficulty": "Easy",
    },
    # normalize_title("International Airlines") → "international airlines"
    "international airlines": {
        "firm":       "Bain & Company",
        "case_type":  "Profitability",
        "industry":   "Transportation",
        "difficulty": "Easy",
    },
    # normalize_title("Katrina") → "katrina"
    "katrina": {
        "firm":       "BCG",
        "case_type":  "Non-traditional Problem",
        "industry":   "Non-profit/Education",
        "difficulty": "Medium",
    },
    # normalize_title("Linda's Great Burgers") → "linda s great burgers"
    "linda s great burgers": {
        "firm":       "McKinsey & Company",
        "case_type":  "Mergers & Acquisitions",
        "industry":   "Restaurants, Food & Beverage",
        "difficulty": "Easy",
    },
    # normalize_title("Lola Lo's Zoo") → "lola lo s zoo"
    "lola lo s zoo": {
        "firm":       "Undisclosed",
        "case_type":  "Investment Decision",
        "industry":   "Entertainment",
        "difficulty": "Hard",
    },
    # normalize_title("Lost Patent") → "lost patent"
    "lost patent": {
        "firm":       "A.T. Kearney",
        "case_type":  "Revenue",
        "industry":   "Pharmaceutical/Healthcare",
        "difficulty": "Easy",
    },
    # normalize_title("Midwest Machinery Co.") → "midwest machinery co"
    "midwest machinery co": {
        "firm":       "Bain & Company",
        "case_type":  "Sourcing / Outsourcing",
        "industry":   "Industrial Goods",
        "difficulty": "Hard",
    },
    # normalize_title("New Vaccine") → "new vaccine"
    "new vaccine": {
        "firm":       "L.E.K. Consulting",
        "case_type":  "Market Entry",
        "industry":   "Pharmaceutical/Healthcare",
        "difficulty": "Medium",
    },
    # normalize_title("Payments Company") → "payments company"
    "payments company": {
        "firm":       "Deloitte",
        "case_type":  "Profitability",
        "industry":   "Financial Services",
        "difficulty": "Medium",
    },
    # normalize_title("Pharmaceutical Rare Disease") → "pharmaceutical rare disease"
    "pharmaceutical rare disease": {
        "firm":       "BCG",
        "case_type":  "Growth Strategy",
        "industry":   "Pharmaceutical/Healthcare",
        "difficulty": "Medium",
    },
    # normalize_title("Project Gargoyle") → "project gargoyle"
    "project gargoyle": {
        "firm":       "Bain & Company",
        "case_type":  "Investment Decision",
        "industry":   "Car Products",
        "difficulty": "Easy",
    },
    # normalize_title("PyeongChang Winter Olympics") → "pyeongchang winter olympics"
    "pyeongchang winter olympics": {
        "firm":       "McKinsey & Company",
        "case_type":  "Investment Decision",
        "industry":   "Tech, Media, & Telecom",
        "difficulty": "Hard",
    },
    # normalize_title("Quahog Public Schools") → "quahog public schools"
    "quahog public schools": {
        "firm":       "McKinsey & Company",
        "case_type":  "Non-traditional Problem",
        "industry":   "Non-profit/Education",
        "difficulty": "Medium",
    },
    # normalize_title("Retirement Apartment Complex") → "retirement apartment complex"
    "retirement apartment complex": {
        "firm":       "Undisclosed",
        "case_type":  "Profitability / Market Entry",
        "industry":   "Real Estate",
        "difficulty": "Medium",
    },
    # normalize_title("Skylight Goods") → "skylight goods"
    "skylight goods": {
        "firm":       "BCG",
        "case_type":  "Operations",
        "industry":   "Industrial Goods",
        "difficulty": "Hard",
    },
    # normalize_title("Smart Cards") → "smart cards"
    "smart cards": {
        "firm":       "McKinsey & Company",
        "case_type":  "Growth Strategy",
        "industry":   "Tech, Media, & Telecom",
        "difficulty": "Easy",
    },
    # normalize_title("Student Health Insurance") → "student health insurance"
    "student health insurance": {
        "firm":       "Deloitte",
        "case_type":  "Growth Strategy",
        "industry":   "Financial Services & Insurance",
        "difficulty": "Medium",
    },
    # normalize_title("Super Jr. Baby Formula") → "super jr baby formula"
    "super jr baby formula": {
        "firm":       "Bain & Company",
        "case_type":  "Investment Decision",
        "industry":   "Consumer Products",
        "difficulty": "Medium",
    },
    # normalize_title("Apache Helicopter") → "apache helicopter"
    "apache helicopter": {
        "firm":       "Undisclosed",
        "case_type":  "Market Sizing / Cost-Benefit Analysis",
        "industry":   "Industrial Goods",
        "difficulty": "Hard",
    },
    # normalize_title("White Boards") → "white boards"
    "white boards": {
        "firm":       "Bain & Company",
        "case_type":  "Sourcing / Outsourcing",
        "industry":   "Durable Goods",
        "difficulty": "Medium",
    },
    # normalize_title("Telco Talks") → "telco talks"
    "telco talks": {
        "firm":       "Accenture",
        "case_type":  "Mergers & Acquisitions",
        "industry":   "Telecommunications",
        "difficulty": "Medium",
    },
    # normalize_title("Warmouth Yachts") → "warmouth yachts"
    "warmouth yachts": {
        "firm":       "Cornerstone Research",
        "case_type":  "Legal Analysis",
        "industry":   "Luxury Retail",
        "difficulty": "Easy",
    },
    # normalize_title("Sueno Mattress") → "sueno mattress"
    "sueno mattress": {
        "firm":       "KPMG Strategy",
        "case_type":  "Profitability",
        "industry":   "Consumer Products",
        "difficulty": "Medium",
    },
    # normalize_title("Cruise Line Acquisition") → "cruise line acquisition"
    "cruise line acquisition": {
        "firm":       "BCG",
        "case_type":  "Profitability",
        "industry":   "Travel & Tourism",
        "difficulty": "Medium",
    },
    # normalize_title("Shoe Co.") → "shoe co"
    "shoe co": {
        "firm":       "Bain",
        "case_type":  "Market Entry",
        "industry":   "Consumer Products",
        "difficulty": "Easy",
    },
    # normalize_title("Craft Co.") → "craft co"
    "craft co": {
        "firm":       "EY-Parthenon",
        "case_type":  "Profitability",
        "industry":   "Consumer Products",
        "difficulty": "Medium",
    },
    # normalize_title("Telecom Co.") → "telecom co"
    "telecom co": {
        "firm":       "Bain",
        "case_type":  "Market Entry",
        "industry":   "Telecom",
        "difficulty": "Hard",
    },
}
