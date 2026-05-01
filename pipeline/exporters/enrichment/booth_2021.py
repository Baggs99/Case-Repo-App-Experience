"""
Ground-truth metadata enrichment for the Booth School of Business Case Book 2021.

Only entries where case_type has been manually classified are included.
Most Booth 2021 cases were parsed heuristically and do not have enrichment data.
"""

# Trigger: source_pdf contains "Booth 2021"
PDF_MATCH = "Booth 2021"

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Quahog Public Schools") → "quahog public schools"
    "quahog public schools": {
        "case_type": "Operations",
    },
}
