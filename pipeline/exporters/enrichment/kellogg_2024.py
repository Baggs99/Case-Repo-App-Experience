"""
Ground-truth metadata enrichment for the Kellogg School of Management Case Book 2024.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).
interviewer_led defaults to False; set explicitly only where True.
is_new_case is True only for Andrew's Simple Delights and Pandora (new to 2024).
No difficulty scores are provided for this source.
"""

# Trigger: source_pdf contains "Kellogg 2024"
PDF_MATCH = "Kellogg 2024"

ENRICHMENT: dict[str, dict] = {
    "avalon": {
        "case_type":      "Opportunity Assessment",
        "industry":       "Energy, Utilities & Mining",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "busch s barber shop": {
        "case_type":      "Market entry",
        "industry":       "Hospitality & Leisure",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "bubbly llc": {
        "case_type":      "Market entry",
        "industry":       "Retail & CPG",
        "interviewer_led": True,
        "is_new_case":    False,
    },
    "chic cosmetology": {
        "case_type":      "Market entry",
        "industry":       "Hospitality & Leisure",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "chicouver cycle": {
        "case_type":      "Market entry",
        "industry":       "Transportation & Logistics",
        "interviewer_led": False,
        "is_new_case":    False,
        "difficulty":     "Hard",
    },
    "dark sky": {
        "case_type":      "New product",
        "industry":       "Aerospace & Defense",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "digibooks": {
        "case_type":      "Market entry",
        "industry":       "Retail & CPG",
        "interviewer_led": True,
        "is_new_case":    False,
    },
    "evanston eagles": {
        "case_type":      "Operations",
        "industry":       "Media & Entertainment",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "events com": {
        "case_type":      "Profitability",
        "industry":       "Technology",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "garthwaite healthcare": {
        "case_type":      "Profitability",
        "industry":       "Healthcare",
        "interviewer_led": True,
        "is_new_case":    False,
    },
    "health coaches": {
        "case_type":      "Operations",
        "industry":       "Healthcare",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "healthy foods": {
        "case_type":      "Growth Strategy",
        "industry":       "Retail & CPG",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "high q plastics": {
        "case_type":      "Profitability",
        "industry":       "Engineering & Construction",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "kellogg capital": {
        "case_type":      "Growth Strategy",
        "industry":       "Financial Services",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "kellogg in india": {
        "case_type":      "Market entry",
        "industry":       "Government & Public Sector",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "kellogg klogs": {
        "case_type":      "New product",
        "industry":       "Retail & CPG",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "lobster woman": {
        "case_type":      "Financial Decisioning",
        "industry":       "Fisheries",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "maine apples": {
        "case_type":      "New product",
        "industry":       "Agriculture & Food",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "money bank call center": {
        "case_type":      "Cost reduction",
        "industry":       "Legal & Professional Services",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "montoya soup": {
        "case_type":      "Cost reduction",
        "industry":       "Retail & CPG",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "mustard clinic": {
        "case_type":      "Operations",
        "industry":       "Healthcare",
        "interviewer_led": True,
        "is_new_case":    False,
    },
    "orrington office supplies": {
        "case_type":      "Operations",
        "industry":       "Engineering & Construction",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "plastic world": {
        "case_type":      "Mergers & Acquisitions",
        "industry":       "Private Equity",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "rotisserie ranch": {
        "case_type":      "New product",
        "industry":       "Retail & CPG",
        "interviewer_led": True,
        "is_new_case":    False,
    },
    "salty sole shoe": {
        "case_type":      "Profitability",
        "industry":       "Retail & CPG",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "sosland sports": {
        "case_type":      "Market entry",
        "industry":       "Hospitality & Leisure",
        "interviewer_led": True,
        "is_new_case":    False,
        "difficulty":     "Medium",
    },
    "swagger llamas": {
        "case_type":      "Growth Strategy",
        "industry":       "Technology",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "tacotle": {
        "case_type":      "Profitability",
        "industry":       "Agriculture & Food",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "vitality insurance": {
        "case_type":      "Profitability",
        "industry":       "Financial Services",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "wildcat wings": {
        "case_type":      "Operations",
        "industry":       "Transportation & Logistics",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "wine co": {
        # Normalized from "Wine & Co" (& → space → collapsed)
        "case_type":      "Opportunity Assessment",
        "industry":       "Agriculture & Food",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "winter olympics bidding": {
        "case_type":      "Opportunity Assessment",
        "industry":       "Entertainment & Media",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "zephyr beverages": {
        "case_type":      "Mergers & Acquisitions",
        "industry":       "Retail & CPG",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "zoo co": {
        "case_type":      "Mergers & Acquisitions",
        "industry":       "Financial Services",
        "interviewer_led": False,
        "is_new_case":    False,
    },
    "andrew s simple delights": {
        # Normalized from "Andrew's Simple Delights"
        "case_type":      "Profitability",
        "industry":       "Retail & CPG",
        "interviewer_led": False,
        "is_new_case":    True,
        "difficulty":     "Medium",
    },
    "pandora": {
        # User-supplied label: "Pandora Coaching" (catalog title: "Pandora")
        "case_type":      "Opportunity Assessment",
        "industry":       "Education Services",
        "interviewer_led": False,
        "is_new_case":    True,
        "difficulty":     "Hard",
    },
}
