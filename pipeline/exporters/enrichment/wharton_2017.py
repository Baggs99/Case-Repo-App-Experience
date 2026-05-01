"""
Ground-truth metadata enrichment for the Wharton School Case Book 2017.

Only entries where case_type has been manually classified are included.
Salt Lake City Airport has not been classified yet.
"""

# Trigger: source_pdf contains "Wharton 2017"
PDF_MATCH = "Wharton 2017"

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Penn & Teller") → "penn teller"
    "penn teller": {
        "case_type": "Profitability",
    },
}
