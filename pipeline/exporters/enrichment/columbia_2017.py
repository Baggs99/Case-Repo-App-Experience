"""
Ground-truth metadata enrichment for Columbia MCA Case Book 2017.

Columbia 2017 uses per-dimension difficulty ratings (Math / Structure /
Creativity) rather than a single overall score.  Leave `difficulty` blank
and populate the three sub-columns instead.

Keys are normalized case titles (lowercase, punctuation → space, collapsed
whitespace).

To add values: fill in the dicts below.  Any key left out of a dict will
appear as blank in the catalog — never invent values.
"""

# Trigger: source_pdf contains "Columbia 2017" OR "MCA Case Book 2017"
PDF_MATCH = ("Columbia 2017", "MCA Case Book 2017")

ENRICHMENT: dict[str, dict] = {
    # Each entry may include:
    #   industry, case_type,
    #   difficulty_math, difficulty_structure, difficulty_creativity,
    #   concepts_tested
    # Example (Fast Food Co. — values visible in the case index image):
    "fast food co": {
        "industry": "Food",
        "case_type": "Market Entry",
        "difficulty_math": "Easy",
        "difficulty_structure": "Medium",
        "difficulty_creativity": "Easy",
        "concepts_tested": "Market sizing; Mental math; Market entry",
    },
    # ── Add remaining cases here as values are verified ───────────────────────
}
