"""
Source-school resolver.

Derives the true originating school from the PDF *filename*, not the
repository storage folder.

Problem
-------
PDFs are stored in top-level "bucket" folders such as ``Booth/`` and
``Yale/`` that reflect where the file was collected, not which school
published the casebook.  The scanner naively uses the bucket folder as
``source_school``, so ``Booth/Darden 2024.pdf`` ends up with
``source_school = booth`` instead of ``Darden``.

Solution
--------
``resolve_source_school`` inspects the PDF *filename stem* (e.g.
``"Darden 2024"``), matches it against an ordered list of school names,
and returns the canonical display name.  Enrichment-supplied values
always take priority.

Repo buckets
------------
``Booth`` and ``Yale`` are storage buckets, not necessarily the source
school.  They are valid source schools only when the filename itself
confirms it (e.g. ``Booth 2026.pdf``, ``Yale 2024.pdf``).
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional


# ── School name registry ──────────────────────────────────────────────────────
# Order matters: more specific / longer names first so they match before
# shorter substrings (e.g. "HBS" before "H", though none clash here).
# Each entry is (search_token_lowercase, canonical_display_name).

SCHOOL_TOKENS: list[tuple[str, str]] = [
    ("rocketblocks", "RocketBlocks"),
    ("columbia",     "Columbia"),
    ("darden",       "Darden"),
    ("fuqua",        "Fuqua"),
    ("harvard",      "Harvard"),
    ("haas",         "Haas"),
    ("hbs",          "Harvard"),
    ("johnson",      "Johnson"),
    ("kellogg",      "Kellogg"),
    ("carlson",      "Carlson"),
    ("mccombs",      "McCombs"),
    ("anderson",     "Anderson"),
    ("tepper",       "Tepper"),
    ("mit",          "MIT"),
    ("ross",         "Ross"),
    ("stern",        "Stern"),
    ("tuck",         "Tuck"),
    ("wharton",      "Wharton"),
    ("booth",        "Booth"),
    ("yale",         "Yale"),
]

# Folder names that are merely storage buckets in this repo and must NOT
# be accepted as source_school unless the PDF filename confirms the match.
REPO_BUCKETS: frozenset[str] = frozenset({"booth", "yale"})


# ── Public API ────────────────────────────────────────────────────────────────

def resolve_source_school(
    source_pdf: str,
    enrichment_source_school: Optional[str] = None,
) -> str:
    """
    Return the canonical source-school display name for a catalog row.

    Priority
    --------
    1. *enrichment_source_school* — if a per-casebook enrichment module
       already provides a trusted value, use it as-is.
    2. PDF filename stem — parse the basename of *source_pdf* and match
       against ``SCHOOL_TOKENS``.
    3. *enrichment_source_school* again — if the filename gave no match,
       fall back to whatever was passed in (could be the manifest slug).

    Parameters
    ----------
    source_pdf:
        Path string as stored in the manifest, e.g. ``"Booth/Darden 2024.pdf"``.
    enrichment_source_school:
        Value from the per-casebook enrichment dict (may be None).

    Returns
    -------
    Canonical display name, e.g. ``"Darden"``, ``"Harvard"``, ``"RocketBlocks"``.
    Falls back to *enrichment_source_school* (or ``""`` if nothing resolves).
    """
    # Priority 1 — trust the enrichment dict if it explicitly set a value
    # that is NOT itself just a repo-bucket slug.
    if enrichment_source_school and enrichment_source_school.lower() not in REPO_BUCKETS:
        return enrichment_source_school

    # Priority 2 — infer from filename stem
    stem = Path(source_pdf).stem.lower()   # e.g. "darden 2024"
    for token, canonical in SCHOOL_TOKENS:
        if token in stem:
            return canonical

    # Priority 3 — fall back to whatever was passed in
    return enrichment_source_school or ""


def infer_from_filename(source_pdf: str) -> Optional[str]:
    """
    Return the canonical school name inferred from *source_pdf* filename,
    or ``None`` if no match is found.

    Useful for audit / validation independent of any existing value.
    """
    stem = Path(source_pdf).stem.lower()
    for token, canonical in SCHOOL_TOKENS:
        if token in stem:
            return canonical
    return None
