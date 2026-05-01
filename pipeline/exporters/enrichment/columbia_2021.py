"""
Ground-truth metadata enrichment for Columbia Business School Case Book 2021.

Keys are normalized case titles (lowercase, punctuation → space, collapsed
whitespace) so they survive minor formatting differences in the manifest.

Each entry may contain any subset of:
    industry, case_type, difficulty,
    difficulty_math, difficulty_structure, difficulty_creativity,
    concepts_tested
"""

# Trigger: source_pdf contains "Columbia 2021"
PDF_MATCH = "Columbia 2021"

ENRICHMENT: dict[str, dict] = {
    "ban the box": {
        "industry": "Government",
        "case_type": "Impact Analysis",
        "difficulty": "Medium",
    },
    "cheers": {
        "industry": "CPG",
        "case_type": "Profitability",
        "difficulty": "Medium",
    },
    "combating climate change": {
        "industry": "Government",
        "case_type": "Strategy Formulation",
        "difficulty": "Medium",
    },
    "co v id accinated": {
        "industry": "Public Sector",
        "case_type": "Optimization",
        "difficulty": "Very Hard",
    },
    "dam dam dam": {
        "industry": "Energy",
        "case_type": "Impact Analysis",
        "difficulty": "Hard",
    },
    "dizzy fruits": {
        "industry": "Retail",
        "case_type": "Market Entry",
        "difficulty": "Medium",
    },
    "dust cloud": {
        "industry": "Agriculture",
        "case_type": "Profitability",
        "difficulty": "Medium",
    },
    "echo yankee game": {
        "industry": "Technology",
        "case_type": "Profitability",
        "difficulty": "Easy",
    },
    "educo": {
        "industry": "Education Technology",
        "case_type": "Growth Strategy",
        "difficulty": "Medium",
    },
    "explorer bank": {
        "industry": "Financial Services",
        "case_type": "Profitability",
        "difficulty": "Medium",
    },
    "fintech startup": {
        "industry": "Financial Services",
        "case_type": "Opportunity Assessment",
        "difficulty": "Hard",
    },
    "funeral homes": {
        "industry": "Death Care",
        "case_type": "Profitability",
        "difficulty": "Hard",
    },
    "grocer prepared foods": {
        "industry": "Grocery",
        "case_type": "Profitability",
        "difficulty": "Easy",
    },
    "housing authority goes green": {
        "industry": "Government",
        "case_type": "Investment",
        "difficulty": "Medium",
    },
    "insta famous": {
        "industry": "Social Media",
        "case_type": "New Product",
        "difficulty": "Medium",
    },
    "mta subway": {
        "industry": "Transportation",
        "case_type": "Profitability",
        "difficulty": "Medium",
    },
    "neuronow": {
        "industry": "Pharma",
        "case_type": "Market Entry",
        "difficulty": "Hard",
    },
    "optic eye": {
        "industry": "Technology",
        "case_type": "Market Entry",
        "difficulty": "Medium",
    },
    "packaging cost reduction": {
        "industry": "Manufacturing",
        "case_type": "Cost Reduction",
        "difficulty": "Easy",
    },
    "pandan diplomacy": {
        "industry": "Lobbyist",
        "case_type": "Strategy Formulation",
        "difficulty": "Medium",
    },
    "pay me my money in cash": {
        "industry": "Education",
        "case_type": "Strategy Formulation",
        "difficulty": "Very Hard",
    },
    "race to 270": {
        "industry": "Political Election",
        "case_type": "Asset Optimization",
        "difficulty": "Hard",
    },
    "seabag marina": {
        "industry": "Nautical",
        "case_type": "Profitability",
        "difficulty": "Medium",
    },
    "sparkle co": {
        "industry": "Retail",
        "case_type": "Profitability",
        "difficulty": "Medium",
    },
    "st boat sale": {
        "industry": "Transportation",
        "case_type": "Opportunity Assessment",
        "difficulty": "Easy",
    },
    "the greatest show on earth": {
        "industry": "Non-Profit",
        "case_type": "Other",
        "difficulty": "Medium",
    },
    "the home of gnome": {
        "industry": "Media & Entertainment",
        "case_type": "Competitor Analysis",
        "difficulty": "Medium",
    },
    "timeless watches": {
        "industry": "Fashion Retail / Tech",
        "case_type": "Market Entry",
        "difficulty": "Hard",
    },
    "tribeca branding": {
        "industry": "Professional Services",
        "case_type": "Market Entry",
        "difficulty": "Medium",
    },
    "alkaline ash": {
        "industry": "Chemicals",
        "case_type": "Growth",
        "difficulty": "Medium",
    },
    "car wash chain": {
        "industry": "Private Equity",
        "case_type": "Opportunity Assessment",
        "difficulty": "Medium",
    },
    "lion king bank": {
        "industry": "Banking",
        "case_type": "Market Sizing",
        "difficulty": "Easy",
    },
    "madecasse": {
        "industry": "Non-Profit",
        "case_type": "Market Entry",
        "difficulty": "Hard",
    },
    "pre k education": {
        "industry": "Education",
        "case_type": "Asset Optimization",
        "difficulty": "Hard",
    },
    "swedish death metal": {
        "industry": "Entertainment",
        "case_type": "Market Entry",
        "difficulty": "Hard",
    },
    "timber crisis": {
        "industry": "Manufacturing",
        "case_type": "Turnaround",
        "difficulty": "Very Hard",
    },
    "traditional toy maker": {
        "industry": "Private Equity",
        "case_type": "Opportunity Assessment",
        "difficulty": "Medium",
    },
    "tristar home appliances": {
        "industry": "Manufacturing",
        "case_type": "Market Expansion",
        "difficulty": "Medium",
    },
}
