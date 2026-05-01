"""
Ground-truth metadata enrichment for the Duke Fuqua Case Book 2026.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

difficulty_quant and difficulty_qual preserve exact labels: "Easy" | "Medium" | "Difficult"
Do NOT convert to numeric values.

Section 1 (new cases):     is_duplicate_case = False, unique_case_count_eligible = True
Section 2 (classic cases): is_duplicate_case = True,  unique_case_count_eligible = False

Classic cases are reused from prior Fuqua casebooks; specific source year is not
documented, so duplicate_of_source_year / duplicate_of_case_title are left null.
"""

# Trigger: source_pdf contains "Fuqua 2026"
PDF_MATCH = "Fuqua 2026"

# ── Section 1: New / original cases ───────────────────────────────────────────

ENRICHMENT: dict[str, dict] = {
    # normalize_title("MedTech Co.") → "medtech co"
    "medtech co": {
        "industry":                   "Healthcare",
        "case_type":                  "Profitability",
        "firm":                       "BCG",
        "difficulty_quant":           "Easy",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "MedTech Co.",
    },
    # normalize_title("The Grass is Greener") → "the grass is greener"
    "the grass is greener": {
        "industry":                   "Agriculture",
        "case_type":                  "Growth Strategy",
        "firm":                       "Bain",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "The Grass is Greener",
    },
    # normalize_title("BioPharma LOE") → "biopharma loe"
    "biopharma loe": {
        "industry":                   "Bio-Pharma",
        "case_type":                  "Cost Reduction",
        "firm":                       "BCG",
        "difficulty_quant":           "Difficult",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "BioPharma LOE",
    },
    # normalize_title("Breaking out of Boston") → "breaking out of boston"
    "breaking out of boston": {
        "industry":                   "Real Estate",
        "case_type":                  "Market Entry",
        "firm":                       "McKinsey",
        "difficulty_quant":           "Easy",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Breaking out of Boston",
    },
    # normalize_title("Big Fat Greek Problem") → "big fat greek problem"
    "big fat greek problem": {
        "industry":                   "Hospitality",
        "case_type":                  "Growth Strategy",
        "firm":                       "D/L/Bain",
        "difficulty_quant":           "Difficult",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Big Fat Greek Problem",
    },
    # normalize_title("Fasten your Seatbelts") → "fasten your seatbelts"
    "fasten your seatbelts": {
        "industry":                   "Travel",
        "case_type":                  "Operations",
        "firm":                       "BCG",
        "difficulty_quant":           "Difficult",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Fasten your Seatbelts",
    },
    # normalize_title("Tiny Ripples Coffee Co.") → "tiny ripples coffee co"
    "tiny ripples coffee co": {
        "industry":                   "Food & Beverage",
        "case_type":                  "Profitability",
        "firm":                       "Bain",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Tiny Ripples Coffee Co.",
    },
    # normalize_title("Pet Paws") → "pet paws"
    "pet paws": {
        "industry":                   "Retail",
        "case_type":                  "M&A",
        "firm":                       "Bain",
        "difficulty_quant":           "Difficult",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Pet Paws",
    },
    # normalize_title("AI in the Clouds") → "ai in the clouds"
    "ai in the clouds": {
        "industry":                   "Tech",
        "case_type":                  "Implementation",
        "firm":                       "McKinsey",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "AI in the Clouds",
    },

    # ── Section 2: Classic cases ──────────────────────────────────────────────
    # Originally marked as duplicates of prior Fuqua casebooks, but those
    # casebooks are not in this library, so these are unique within the repo.

    # normalize_title("Lactose King") → "lactose king"
    "lactose king": {
        "industry":                   "Services",
        "case_type":                  "Growth",
        "difficulty_quant":           "Easy",
        "difficulty_qual":            "Easy",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Lactose King",
    },
    # normalize_title("Born for Beauty") → "born for beauty"
    "born for beauty": {
        "industry":                   "Consumer",
        "case_type":                  "Growth",
        "difficulty_quant":           "Easy",
        "difficulty_qual":            "Easy",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Born for Beauty",
    },
    # normalize_title("MotherTech") → "mothertech"
    "mothertech": {
        "industry":                   "Healthcare",
        "case_type":                  "M&A",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "MotherTech",
    },
    # normalize_title("Bumpers R Us") → "bumpers r us"
    "bumpers r us": {
        "industry":                   "Manufacturing",
        "case_type":                  "Operations",
        "difficulty_quant":           "Easy",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Bumpers R Us",
    },
    # normalize_title("A-Plus School District") → "a plus school district"
    "a plus school district": {
        "industry":                   "Education",
        "case_type":                  "Other",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "A-Plus School District",
    },
    # normalize_title("Sardine Airlines") → "sardine airlines"
    "sardine airlines": {
        "industry":                   "Transportation",
        "case_type":                  "Profitability",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Medium",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Sardine Airlines",
    },
    # normalize_title("Goodbye Horses") → "goodbye horses"
    "goodbye horses": {
        "industry":                   "Healthcare",
        "case_type":                  "Decision Analysis",
        "difficulty_quant":           "Medium",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Goodbye Horses",
    },
    # normalize_title("Scrub Strategy") → "scrub strategy"
    "scrub strategy": {
        "industry":                   "Consumer",
        "case_type":                  "Product Launch",
        "difficulty_quant":           "Difficult",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Scrub Strategy",
    },
    # normalize_title("Swift Business") → "swift business"
    "swift business": {
        "industry":                   "Entertainment",
        "case_type":                  "Market Entry",
        "difficulty_quant":           "Difficult",
        "difficulty_qual":            "Difficult",
        "is_duplicate_case":          False,
        "unique_case_count_eligible": True,
        "canonical_case_title":       "Swift Business",
    },
}
