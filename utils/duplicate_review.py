"""
Conservative duplicate-title keys for human review (not auto-hiding).

Used by ``scripts/find-likely-duplicate-cases.py`` and tests. The web app
reads approved flags from Postgres (``is_duplicate_case`` /
``unique_case_count_eligible``) after you run the apply script.
"""

from __future__ import annotations

import re
from difflib import SequenceMatcher
from typing import Any, Iterable

# Pipeline title normaliser — same tokenisation as the catalog.
from pipeline.exporters.case_catalog import normalize_title

# Trailing legal / shorthand tokens stripped from the loose key (word-boundary).
_SUFFIX_TOKENS = frozenset(
    {
        "co",
        "company",
        "inc",
        "llc",
        "corp",
        "corporation",
    }
)

_FUZZY_MIN_RATIO = 0.88


def duplicate_loose_key(title: str) -> str:
    """
    Normalised key for *likely* same-title matching across punctuation / Co /
    and-vs-ampersand variants.

    Steps:
      1. Lowercase and replace ``&`` with `` and `` *before* ``normalize_title``
         so ``Wine & Co`` and ``Wine and Co`` align.
      2. ``normalize_title`` (non-alnum → space, collapse spaces)
      3. Strip trailing suffix tokens: co, company, inc, llc, corp, corporation
    """
    t = (title or "").strip().lower().replace("&", " and ")
    t = normalize_title(t)
    t = re.sub(r"\s+", " ", t).strip()
    parts = t.split()
    while parts and parts[-1].lower() in _SUFFIX_TOKENS:
        parts.pop()
    return " ".join(parts).strip().lower()


def title_similarity(a: str, b: str) -> float:
    """Token-ish string similarity in ``[0, 1]`` — difflib on normalised titles."""
    na = normalize_title(a or "")
    nb = normalize_title(b or "")
    if not na and not nb:
        return 1.0
    if not na or not nb:
        return 0.0
    return SequenceMatcher(None, na, nb).ratio()


def _year_sort_key(year: Any) -> tuple[int, int]:
    """(prefer_non_null, year_value) — lower is better canonical year."""
    if year is None:
        return (1, 0)
    try:
        y = int(year)
    except (TypeError, ValueError):
        return (1, 0)
    return (0, y)


def pick_canonical_row(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    """
    Choose canonical among a duplicate group.

    Rules:
      1. Prefer ``unique_case_count_eligible is True`` when years tie.
      2. Otherwise lowest non-NULL ``source_year`` wins; NULL year ranks last.
      3. Then lowest ``id``.
    """
    best: dict[str, Any] | None = None
    for r in rows:
        if best is None:
            best = r
            continue
        if _is_better_canonical(r, best):
            best = r
    assert best is not None
    return best


def _is_better_canonical(candidate: dict[str, Any], current: dict[str, Any]) -> bool:
    cy = candidate.get("source_year")
    cu = current.get("source_year")
    cy_key = _year_sort_key(cy)
    cu_key = _year_sort_key(cu)
    if cy_key != cu_key:
        return cy_key < cu_key

    # Same year (including both NULL): prefer already-eligible for stats.
    ce = bool(candidate.get("unique_case_count_eligible", True))
    ue = bool(current.get("unique_case_count_eligible", True))
    if ce != ue:
        return ce and not ue

    return int(candidate["id"]) < int(current["id"])


def recommendation_reason(
    *,
    row: dict[str, Any],
    canonical: dict[str, Any],
    match_kind: str,
) -> str:
    """Short human-readable reason for the CSV."""
    nt = (row.get("normalized_title") or "").strip()
    c_nt = (canonical.get("normalized_title") or "").strip()
    loose_r = duplicate_loose_key(row.get("case_title") or "")
    loose_c = duplicate_loose_key(canonical.get("case_title") or "")

    bits: list[str] = [match_kind]
    if nt != c_nt and loose_r == loose_c:
        bits.append("title differs only after suffix / & / punctuation normalisation")
    elif nt == c_nt:
        bits.append("exact normalized_title match")
    if match_kind == "fuzzy_title":
        bits.append(f"similarity ≥ {_FUZZY_MIN_RATIO:.2f} with same school or industry+case_type")
    return "; ".join(bits)


__all__ = [
    "duplicate_loose_key",
    "title_similarity",
    "pick_canonical_row",
    "recommendation_reason",
    "_FUZZY_MIN_RATIO",
]
