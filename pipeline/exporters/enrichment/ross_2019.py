"""
Ground-truth metadata enrichment for the Ross School of Business Case Book 2019.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).
No difficulty scores were provided in this source.
"""

# Trigger: source_pdf contains "Ross 2019"
PDF_MATCH = "Ross 2019"

ENRICHMENT: dict[str, dict] = {
    "american bank atm dilemma": {
        "industry":  "Financial Services",
        "case_type": "Profitability Improvement",
    },
    "harrison energy ev goals": {
        "industry":  "Power & Utilities",
        "case_type": "Market Entry",
    },
    "bailey brothers bancorp": {
        "industry":  "Financial Services",
        "case_type": "Profitability Improvement",
    },
    "orange bank co": {
        "industry":  "Financial Services",
        "case_type": "M&A",
    },
    "shopop": {
        "industry":  "Retail",
        "case_type": "Profitability Improvement",
    },
    "ferris wheel": {
        "industry":  "Entertainment",
        "case_type": "New Investment Analysis",
    },
    "6paq p e firm": {
        # Normalized from "6PAQ P.E. Firm" (. → space, collapsed)
        "industry":  "Entertainment",
        "case_type": "Private Equity & Profitability Improvement",
    },
    "hamm s university": {
        # Normalized from "Hamm's University" (' → space)
        "industry":  "Higher Ed / Non-Profit",
        "case_type": "Profitability Improvement",
    },
    "allsafe": {
        "industry":  "Insurance",
        "case_type": "M&A",
    },
    "mega pharma": {
        "industry":  "Retail",
        "case_type": "M&A",
    },
    "mike apparel": {
        "industry":  "Consumer Goods",
        "case_type": "Market Entry",
    },
    "pharmadeliver": {
        "industry":  "Pharma",
        "case_type": "Growth Strategy",
    },
    "single cup of coffee": {
        "industry":  "Consumer Products",
        "case_type": "Market Sizing",
    },
    "cheesy situation": {
        "industry":  "Food and Beverage",
        "case_type": "Growth Strategy",
    },
}
