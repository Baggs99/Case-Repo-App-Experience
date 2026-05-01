"""
Source-year resolver.

Derives the casebook publication year deterministically from the source PDF
*filename*, independent of folder structure, manifest content, or enrichment
overrides.

Rules
-----
1. Extract every 4-digit number from the filename stem.
2. Keep only values inside the plausible range ``VALID_YEAR_RANGE``.
3. If multiple candidates remain (e.g. ``"Darden 2018-2019.pdf"``), pick the
   **latest** year.
4. If no valid year is found, return ``None``.

Scope
-----
Casebooks use a ``"<School> <Year>.pdf"`` naming convention, so this resolver
covers every source PDF of interest.  Individual-case PDFs (RocketBlocks) have
no year in their filenames and will legitimately return ``None``.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional


# Plausible publication-year window for casebooks in this repo.
VALID_YEAR_RANGE = range(1990, 2036)   # 1990 .. 2035 inclusive

_YEAR_RE = re.compile(r"\b(19\d{2}|20\d{2})\b")


def resolve_source_year(source_pdf: str) -> Optional[int]:
    """
    Return the casebook publication year inferred from *source_pdf*.

    Parameters
    ----------
    source_pdf:
        Path string as stored in the manifest, e.g. ``"Booth/Darden 2024.pdf"``.
        Any path form is accepted — only the filename stem is inspected.

    Returns
    -------
    * The latest valid year in the filename if one exists.
    * ``None`` if the filename contains no 4-digit number inside
      ``VALID_YEAR_RANGE``.

    Examples
    --------
    >>> resolve_source_year("Booth/Darden 2024.pdf")
    2024
    >>> resolve_source_year("Yale/Darden 2018-2019.pdf")
    2019
    >>> resolve_source_year("RocketBlocks/RocketBlocks-Case-1-profitability.pdf")  # no year
    >>> resolve_source_year("Booth/Harvard 2002.pdf")
    2002
    """
    if not source_pdf:
        return None

    stem = Path(source_pdf).stem
    candidates = [int(m) for m in _YEAR_RE.findall(stem)]
    valid = [y for y in candidates if y in VALID_YEAR_RANGE]

    if not valid:
        return None

    return max(valid)


def is_valid_year(year: object) -> bool:
    """Return True when *year* is an int-like value inside ``VALID_YEAR_RANGE``."""
    if year is None:
        return False
    try:
        return int(year) in VALID_YEAR_RANGE
    except (TypeError, ValueError):
        return False
