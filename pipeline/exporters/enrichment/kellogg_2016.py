"""
Ground-truth metadata enrichment for the Kellogg School of Management Case Book 2016.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

IMPORTANT: difficulty_quant and difficulty_structure are raw numeric scores out of 10
as printed in the TOC. Do NOT convert them to Easy / Medium / Hard labels.
The difficulty field is intentionally left blank — no overall label was provided
in the source.

Interviewer-led cases (marked * in the TOC):
    Rotisserie Ranch, Thompson Healthcare, After School Programming
"""

# Trigger: source_pdf contains "Kellogg 2016"
PDF_MATCH = "Kellogg 2016"

ENRICHMENT: dict[str, dict] = {
    "maine apples": {
        "case_type":           "New product/market entry",
        "industry":            "Consumer Products",
        "difficulty_quant":    "8",
        "difficulty_structure": "6",
    },
    "kellogg in india": {
        "case_type":           "Market entry",
        "industry":            "Education",
        "difficulty_quant":    "8",
        "difficulty_structure": "5",
    },
    "rotisserie ranch": {
        "case_type":           "New product/market entry",
        "industry":            "Consumer Products",
        "difficulty_quant":    "6",
        "difficulty_structure": "5",
        "interviewer_led":     True,
    },
    "tarrant fixtures": {
        "case_type":           "Profitability",
        "industry":            "Industrial Goods",
        "difficulty_quant":    "8",
        "difficulty_structure": "7",
    },
    "portkey inc": {
        "case_type":           "New product/market entry",
        "industry":            "Transportation",
        "difficulty_quant":    "5",
        "difficulty_structure": "4",
    },
    "salty sole shoe co": {
        "case_type":           "Profitability",
        "industry":            "Retail",
        "difficulty_quant":    "7",
        "difficulty_structure": "6",
    },
    "money bank call center": {
        "case_type":           "Cost Reduction and M&A",
        "industry":            "Call Center",
        "difficulty_quant":    "8",
        "difficulty_structure": "9",
    },
    "zephyr beverages": {
        "case_type":           "Opportunity Assessment",
        "industry":            "Consumer Products",
        "difficulty_quant":    "1",
        "difficulty_structure": "5",
    },
    "shermer pharma": {
        "case_type":           "New product/market entry",
        "industry":            "Healthcare",
        "difficulty_quant":    "5",
        "difficulty_structure": "5",
    },
    "orange retailer": {
        "case_type":           "Market Entry",
        "industry":            "Retail",
        "difficulty_quant":    "5",
        "difficulty_structure": "5",
    },
    "vitality insurance": {
        "case_type":           "Profitability",
        "industry":            "Insurance",
        "difficulty_quant":    "3",
        "difficulty_structure": "7",
    },
    "realty seattle": {
        "case_type":           "Profitability",
        "industry":            "Real Estate",
        "difficulty_quant":    "7",
        "difficulty_structure": "4",
    },
    "dark sky": {
        "case_type":           "Growth Strategy",
        "industry":            "Aerospace and Defense",
        "difficulty_quant":    "5",
        "difficulty_structure": "5",
    },
    "healthy foods co": {
        "case_type":           "Growth Strategy",
        "industry":            "Consumer Products",
        "difficulty_quant":    "5",
        "difficulty_structure": "6",
    },
    "plastic world": {
        "case_type":           "M&A",
        "industry":            "Private Equity",
        "difficulty_quant":    "3",
        "difficulty_structure": "4",
    },
    "gonet": {
        "case_type":           "Market Entry",
        "industry":            "Telecom",
        "difficulty_quant":    "8",
        "difficulty_structure": "4",
    },
    "orrington office supplies": {
        "case_type":           "Profitability",
        "industry":            "Consumer Products",
        "difficulty_quant":    "6",
        "difficulty_structure": "7",
    },
    "winter olympics bidding": {
        "case_type":           "Opportunity Assessment",
        "industry":            "Media",
        "difficulty_quant":    "8",
        "difficulty_structure": "4",
    },
    "vindaloo corporation": {
        "case_type":           "New product/market entry",
        "industry":            "Consumer Products",
        "difficulty_quant":    "8",
        "difficulty_structure": "4",
    },
    "digibooks": {
        "case_type":           "New product/market entry",
        "industry":            "Tech",
        "difficulty_quant":    "4",
        "difficulty_structure": "7",
    },
    "health coaches": {
        "case_type":           "New product/market entry",
        "industry":            "Healthcare",
        "difficulty_quant":    "8",
        "difficulty_structure": "6",
    },
    "high q plastics": {
        "case_type":           "Improving Profitability",
        "industry":            "Industrial Goods",
        "difficulty_quant":    "8",
        "difficulty_structure": "5",
    },
    "zoo co": {
        "case_type":           "M&A",
        "industry":            "Financial Services",
        "difficulty_quant":    "7",
        "difficulty_structure": "5",
    },
    "syzygy supercomputers": {
        "case_type":           "Profitability",
        "industry":            "Tech",
        "difficulty_quant":    "3",
        "difficulty_structure": "7",
    },
    "thompson healthcare": {
        "case_type":           "Cost Reduction",
        "industry":            "Healthcare",
        "difficulty_quant":    "8",
        "difficulty_structure": "9",
        "interviewer_led":     True,
    },
    "rock energy": {
        "case_type":           "Opportunity Assessment",
        "industry":            "Energy",
        "difficulty_quant":    "7",
        "difficulty_structure": "5",
    },
    "chic cosmetology": {
        "case_type":           "Opportunity Assessment",
        "industry":            "Education",
        "difficulty_quant":    "7",
        "difficulty_structure": "8",
    },
    "tacotle": {
        "case_type":           "Profitability",
        "industry":            "Restaurant",
        "difficulty_quant":    "6",
        "difficulty_structure": "5",
    },
    "wine and co": {
        "case_type":           "Opportunity Assessment",
        "industry":            "Consumer Products",
        "difficulty_quant":    "7",
        "difficulty_structure": "5",
    },
    "a airline co": {
        # Normalized from "A+ Airline Co" (+ → space → collapsed to "a airline co")
        "case_type":           "Opportunity Assessment",
        "industry":            "Airline",
        "difficulty_quant":    "8",
        "difficulty_structure": "8",
    },
    "bell computer": {
        "case_type":           "Improving Profitability",
        "industry":            "Tech",
        "difficulty_quant":    "8",
        "difficulty_structure": "10",
    },
    "montoya soup": {
        "case_type":           "Improving Profitability",
        "industry":            "Consumer Products",
        "difficulty_quant":    "8",
        "difficulty_structure": "5",
    },
    "after school programming": {
        "case_type":           "Growth Strategy",
        "industry":            "Non-Profit",
        "difficulty_quant":    "10",
        "difficulty_structure": "10",
        "interviewer_led":     True,
    },
}
