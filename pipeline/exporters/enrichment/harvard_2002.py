"""
Ground-truth metadata enrichment for the Harvard Business School Case Book 2002.

The PDF is stored in a folder that causes the classifier to assign the wrong school.
This enrichment corrects source_school and source_year for every case.

Harvard 2002 does not provide structured metadata for case_type or industry,
but manually curated difficulty ratings (Easy / Medium / Hard) have been
added for all 24 Practice Cases — the normalizer will pick these up as
``difficulty_normalized``.
"""

# Trigger: source_pdf contains "Harvard 2002"
PDF_MATCH = "Harvard 2002"

# Applied to every case in this book.
_BASE = {
    "source_school": "Harvard",
    "source_year":   2002,
}

ENRICHMENT: dict[str, dict] = {
    # normalize_title("Practice Case 1 (Retailer)") → "practice case 1 retailer"
    "practice case 1 retailer":                      {**_BASE, "difficulty": "Easy"},
    # normalize_title("Practice Case 2 (Butcher Shop)") → "practice case 2 butcher shop"
    "practice case 2 butcher shop":                  {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 3 (Juice Producer)") → "practice case 3 juice producer"
    "practice case 3 juice producer":                {**_BASE, "difficulty": "Easy"},
    # normalize_title("Practice Case 4 (Chemical Manufacturer)") → "practice case 4 chemical manufacturer"
    "practice case 4 chemical manufacturer":         {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 5 (Viettel)") → "practice case 5 viettel"
    "practice case 5 viettel":                       {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 6 (World View)") → "practice case 6 world view"
    "practice case 6 world view":                    {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 7 (Le Seine)") → "practice case 7 le seine"
    "practice case 7 le seine":                      {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 8 (Beer Brew)") → "practice case 8 beer brew"
    "practice case 8 beer brew":                     {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 9 (Wheeler Dealer)") → "practice case 9 wheeler dealer"
    "practice case 9 wheeler dealer":                {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 10 (Travel Agency)") → "practice case 10 travel agency"
    "practice case 10 travel agency":                {**_BASE, "difficulty": "Easy"},
    # normalize_title("Practice Case 11 (Hospital)") → "practice case 11 hospital"
    "practice case 11 hospital":                     {**_BASE, "difficulty": "Hard"},
    # normalize_title("Practice Case 12 (E-Grocery)") → "practice case 12 e grocery"
    "practice case 12 e grocery":                    {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 13 (Formula Producer)") → "practice case 13 formula producer"
    "practice case 13 formula producer":             {**_BASE, "difficulty": "Hard"},
    # normalize_title("Practice Case 14 (Pharmaceutical Company)") → "practice case 14 pharmaceutical company"
    "practice case 14 pharmaceutical company":       {**_BASE, "difficulty": "Hard"},
    # normalize_title("Practice Case 15 (Scotch Manufacturer)") → "practice case 15 scotch manufacturer"
    "practice case 15 scotch manufacturer":          {**_BASE, "difficulty": "Hard"},
    # normalize_title("Practice Case 16 (Regional Jet Corporation)") → "practice case 16 regional jet corporation"
    "practice case 16 regional jet corporation":     {**_BASE, "difficulty": "Hard"},
    # normalize_title("Practice Case 17 (British Times)") → "practice case 17 british times"
    "practice case 17 british times":                {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 18 (Children Clothes E-Retailer)") → "practice case 18 children clothes e retailer"
    "practice case 18 children clothes e retailer":  {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 19 (Consumer Products)") → "practice case 19 consumer products"
    "practice case 19 consumer products":            {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 20 (The Video Store)") → "practice case 20 the video store"
    "practice case 20 the video store":              {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 21 (The English Church)") → "practice case 21 the english church"
    "practice case 21 the english church":           {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 22 (HBS as a Business)") → "practice case 22 hbs as a business"
    "practice case 22 hbs as a business":            {**_BASE, "difficulty": "Easy"},
    # normalize_title("Practice Case 23 (Fast Food Restaurant)") → "practice case 23 fast food restaurant"
    "practice case 23 fast food restaurant":         {**_BASE, "difficulty": "Medium"},
    # normalize_title("Practice Case 24 (Automobile Producer)") → "practice case 24 automobile producer"
    "practice case 24 automobile producer":          {**_BASE, "case_type": "Growth Strategy", "difficulty": "Hard"},
}
