"""
Ground-truth metadata enrichment for the Tuck Case Book 2024.

Keys are normalized case titles (lowercase, punctuation → space, collapsed whitespace).

No difficulty metadata is available for this casebook.
"""

# Trigger: source_pdf contains "Tuck 2024"
PDF_MATCH = "Tuck 2024"

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Aftermarket Auto Parts (LEK)") → "aftermarket auto parts lek"
    "aftermarket auto parts lek": {
        "industry":  "Automotive",
        "case_type": "Growth Strategy",
    },
    # normalize_title("Craft Co (EY-Parthenon)") → "craft co ey parthenon"
    "craft co ey parthenon": {
        "industry":  "Retail & CPG",
        "case_type": "Growth Strategy",
    },
    # normalize_title("Hanover Health") → "hanover health"
    "hanover health": {
        "industry":  "Healthcare",
        "case_type": "Mergers & Acquisitions",
    },
    # normalize_title("Kitchen Co (Innosight)") → "kitchen co innosight"
    "kitchen co innosight": {
        "industry":  "Retail & CPG",
        "case_type": "Growth Strategy",
    },
    # normalize_title("Luxury Landscaping (IGS)") → "luxury landscaping igs"
    "luxury landscaping igs": {
        "industry":  "Engineering & Construction",
        "case_type": "Mergers & Acquisitions",
    },
    # normalize_title("Nutters of Savile Row") → "nutters of savile row"
    "nutters of savile row": {
        "industry":  "Retail & CPG",
        "case_type": "Operations",
    },
    # normalize_title("OldSchool") → "oldschool"
    "oldschool": {
        "industry":  "Government & Public Sector",
        "case_type": "Profitability",
    },
    # normalize_title("Pediatric Hearing Aids") → "pediatric hearing aids"
    "pediatric hearing aids": {
        "industry":  "Healthcare",
        "case_type": "Profitability",
    },
    # normalize_title("PowerStride Sportswear") → "powerstride sportswear"
    "powerstride sportswear": {
        "industry":  "Retail & CPG",
        "case_type": "Growth Strategy",
    },
    # normalize_title("Snow Big Deal") → "snow big deal"
    "snow big deal": {
        "industry":  "Transportation & Logistics",
        "case_type": "Opportunity Assessment",
    },
    # normalize_title("SwitchDeck Motors") → "switchdeck motors"
    "switchdeck motors": {
        "industry":  "Automotive",
        "case_type": "Market Entry",
    },
    # normalize_title("Tuck Air II") → "tuck air ii"
    "tuck air ii": {
        "industry":  "Airline",
        "case_type": "Opportunity Assessment",
    },
}
