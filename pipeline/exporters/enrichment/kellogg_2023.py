"""
Ground-truth metadata enrichment for the Kellogg School of Management Case Book 2023.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).
interviewer_led is True only where explicitly marked in the TOC.
No difficulty scores were provided in this source — leave difficulty blank.
"""

# Trigger: source_pdf contains "Kellogg 2023"
PDF_MATCH = "Kellogg 2023"

ENRICHMENT: dict[str, dict] = {
    "avalon": {
        "case_type": "Opportunity Assessment",
        "industry":  "Energy, Utilities & Mining",
    },
    "busch s barber shop": {
        "case_type": "Market entry",
        "industry":  "Hospitality & Leisure",
    },
    "bubbly llc": {
        "case_type":      "Market entry",
        "industry":       "Retail & CPG",
        "interviewer_led": True,
    },
    "chic cosmetology": {
        "case_type": "Market entry",
        "industry":  "Hospitality & Leisure",
    },
    "chicoure cycle": {
        "case_type": "Market entry",
        "industry":  "Transportation & Logistics",
    },
    "dark sky": {
        "case_type": "New product",
        "industry":  "Aerospace & Defense",
    },
    "digibooks": {
        "case_type":      "Market entry",
        "industry":       "Retail & CPG",
        "interviewer_led": True,
    },
    "events com": {
        "case_type": "Profitability",
        "industry":  "Technology",
    },
    "garthwaite healthcare": {
        "case_type":      "Profitability",
        "industry":       "Healthcare",
        "interviewer_led": True,
    },
    "health coaches": {
        "case_type": "Operations",
        "industry":  "Healthcare",
    },
    "healthy foods": {
        "case_type": "Growth Strategy",
        "industry":  "Retail & CPG",
    },
    "high q plastics": {
        "case_type": "Profitability",
        "industry":  "Engineering & Construction",
    },
    "kellogg capital": {
        "case_type": "Growth Strategy",
        "industry":  "Financial Services",
    },
    "kellogg in india": {
        "case_type": "Market entry",
        "industry":  "Government & Public Sector",
    },
    "kellogg klogs": {
        "case_type": "New Product",
        "industry":  "Retail & CPG",
    },
    "maine apples": {
        "case_type": "New product",
        "industry":  "Agriculture & Food",
    },
    "money bank call center": {
        "case_type": "Cost reduction",
        "industry":  "Legal & Professional Services",
    },
    "montoya soup": {
        "case_type": "Cost reduction",
        "industry":  "Retail & CPG",
    },
    "mustard clinic": {
        "case_type":      "Operations",
        "industry":       "Healthcare",
        "interviewer_led": True,
    },
    "orrington office supplies": {
        "case_type": "Operations",
        "industry":  "Engineering & Construction",
    },
    "plastic world": {
        "case_type": "Mergers & Acquisitions",
        "industry":  "Private Equity",
    },
    "rotisserie ranch": {
        "case_type":      "New product",
        "industry":       "Retail & CPG",
        "interviewer_led": True,
    },
    "salty sole shoe": {
        "case_type": "Profitability",
        "industry":  "Retail & CPG",
    },
    "solsand sports": {
        "case_type":      "Market entry",
        "industry":       "Hospitality & Leisure",
        "interviewer_led": True,
    },
    "swagger llamas": {
        "case_type": "Growth Strategy",
        "industry":  "Technology",
    },
    "tacotle": {
        "case_type": "Profitability",
        "industry":  "Agriculture & Food",
    },
    "vitality insurance": {
        "case_type": "Profitability",
        "industry":  "Financial Services",
    },
    "wildcat wings": {
        "case_type": "Operations",
        "industry":  "Transportation & Logistics",
    },
    "wine co": {
        # Normalized from "Wine & Co" (& → space → collapsed)
        "case_type": "Opportunity Assessment",
        "industry":  "Agriculture & Food",
    },
    "winter olympics bidding": {
        "case_type": "Opportunity Assessment",
        "industry":  "Entertainment & Media",
    },
    "zephyr beverages": {
        "case_type": "Mergers & Acquisitions",
        "industry":  "Retail & CPG",
    },
    "zoo co": {
        "case_type": "Mergers & Acquisitions",
        "industry":  "Financial Services",
    },
    "evanston eagles": {
        "case_type": "Operations",
        "industry":  "Media & Entertainment",
    },
    "lobster woman": {
        "case_type": "Financial Decisioning",
        "industry":  "Fisheries",
    },
}
