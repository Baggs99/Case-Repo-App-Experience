"""
Assign an Easy / Medium / Hard rating to every case in the catalog.

Expert-rated anchor cases calibrate the 1–10 composite score and the
cutoffs of the 3-bucket rating. The user's labels cluster as follows:

    Maize & Blue Cement         Easy         4.0
    Art Museum                  Medium       5.5
    Big Ten Bivalves            Medium       6.0
    Donatella Co.               Medium       6.5
    Melt That Snow              Medium       6.5
    WolverineHomes              Medium       6.5
    Always Fresh                Medium-Hard  7.0
    Malaria Remedy              Medium-Hard  7.0
    TW Tech                     Medium-Hard  7.0
    Let's Vroom                 Medium-Hard  7.5
    Antidepressant Pricing      Hard         8.5

The user distinguishes "Medium-Hard" (7.0–7.5) from "Hard" (8.5) in
their labels, so in the 3-bucket collapse Medium-Hard folds down into
Medium. Resulting boundaries:

    composite <  5.0      → Easy
    5.0 ≤ composite < 8.0 → Medium
    composite ≥  8.0      → Hard

Signal priority, from most to least specific:

    1. anchor override (user-calibrated cases)
    2. numeric `difficulty_quant` + `difficulty_structure` (averaged)
       - scale auto-detected (1–3 vs 1–10)
    3. categorical quant/qual labels averaged together
    4. 1–3 integer scale stored loosely in `difficulty` / `difficulty_raw`
    5. categorical `difficulty_normalized`
    6. free-text keywords (LIGHT / HEAVY / Very Hard / Medium-Hard)
    7. unrated → leave the new columns blank
"""

from __future__ import annotations

import argparse
import csv
import logging
import re
from collections import Counter
from pathlib import Path
from typing import Optional, Tuple

logger = logging.getLogger(__name__)


# ── Calibration constants ────────────────────────────────────────────────────

EASY_MAX = 5.0          # composite <  EASY_MAX → Easy
HARD_MIN = 8.0          # composite >= HARD_MIN → Hard (Antidepressant = 8.5 is the only pure-Hard anchor)

# Where each categorical label lands on the 1–10 composite axis. Anchored so
# "Medium" = 5.5 (Art Museum), "Medium-Hard" = 7.0 (Always Fresh, Malaria,
# TW Tech), "Hard" = 8.5 (Antidepressant Pricing).
LABEL_SCORE = {
    "easy":          3.5,
    "light":         3.5,
    "medium":        5.5,
    "medium/hard":   7.0,
    "medium to hard":7.0,
    "medium-hard":   7.0,
    "hard":          8.5,
    "heavy":         8.5,
    "difficult":     8.0,
    "very hard":     9.0,
}

# 1–3 integer scale sometimes used in the raw data.
SCALE_1_3_SCORE = {1: 3.5, 2: 5.5, 3: 8.0}

# User-calibrated anchor cases. Keys are `case_title.lower()` substrings;
# the first match wins. These are the three expert ratings that calibrate the
# whole rubric, so we pin them explicitly in case the catalog rows for these
# cases have no extractable difficulty signal.
ANCHOR_OVERRIDES = [
    ("antidepressant pricing", 8.5, "anchor:antidepressant"),
    ("always fresh",           7.0, "anchor:always_fresh"),
    ("art museum",             5.5, "anchor:art_museum"),
    ("big ten bivalves",       6.0, "anchor:big_ten_bivalves"),
    ("donatella",              6.5, "anchor:donatella"),
    ("let's vroom",            7.5, "anchor:lets_vroom"),
    ("lets vroom",             7.5, "anchor:lets_vroom"),
    ("maize & blue",           4.0, "anchor:maize_blue_cement"),
    ("malaria remedy",         7.0, "anchor:malaria_remedy"),
    ("melt that snow",         6.5, "anchor:melt_that_snow"),
    ("tw tech",                7.0, "anchor:tw_tech"),
    ("wolverinehomes",         6.5, "anchor:wolverinehomes"),
]


# ── Public interface ─────────────────────────────────────────────────────────

def score_row(row: dict) -> Tuple[Optional[float], str]:
    """
    Compute a 1–10 composite difficulty score for a catalog row.

    Returns (score, source) where `source` is a short string describing
    which signal produced the score (useful for auditing). If no signal
    could be found, returns (None, "none").
    """
    # 0. Expert-rated anchor overrides (calibration cases).
    title_lower = (row.get("case_title") or "").lower()
    for needle, score, source in ANCHOR_OVERRIDES:
        if needle in title_lower:
            return score, source

    # Decide whether the numeric fields are on a 1–3 scale (early
    # hand-labeled data) or a 1–10 scale (later rubric). When the overall
    # `difficulty` is 1/2/3 and all sub-scores are ≤3, treat as 1–3.
    scale_1_3 = _looks_like_1_3_scale(row)

    # 1. On the 1–3 scale the overall `difficulty` is authoritative; fall
    # through to sub-scores only when no overall is given.
    if scale_1_3:
        overall = (row.get("difficulty") or "").strip()
        if overall in {"1", "2", "3"}:
            return SCALE_1_3_SCORE[int(overall)], "overall_1_3"

        quant_num  = _to_float(row.get("difficulty_quant"),  allow_1_3=True)
        qual_num   = _to_float(row.get("difficulty_qual"),   allow_1_3=True)
        struct_num = _to_float(row.get("difficulty_structure"), allow_1_3=True)
        parts = [p for p in (quant_num, qual_num, struct_num) if p is not None]
        if len(parts) >= 2:
            return _score_from_1_3(sum(parts) / len(parts)), "subscore_avg_1_3"
        if parts:
            return _score_from_1_3(parts[0]), "subscore_single_1_3"
    else:
        # 1–10 scale: prefer averaged quant + structure.
        quant_num  = _to_float(row.get("difficulty_quant"))
        struct_num = _to_float(row.get("difficulty_structure"))
        if quant_num is not None and struct_num is not None:
            return _clamp((quant_num + struct_num) / 2.0), "quant+structure"
        if quant_num is not None:
            return _clamp(quant_num), "quant_only"
        if struct_num is not None:
            return _clamp(struct_num), "structure_only"

    # 2. Categorical quant / qual labels.
    quant_lbl = _label_score(row.get("difficulty_quant"))
    qual_lbl  = _label_score(row.get("difficulty_qual"))
    if quant_lbl is not None and qual_lbl is not None:
        return _clamp((quant_lbl + qual_lbl) / 2.0), "quant+qual_labels"
    if quant_lbl is not None:
        return _clamp(quant_lbl), "quant_label"
    if qual_lbl is not None:
        return _clamp(qual_lbl), "qual_label"

    # 3. 1–3 integer scale stored loosely in text columns (fallback).
    for col in ("difficulty", "difficulty_raw"):
        val = (row.get(col) or "").strip()
        if val.isdigit() and int(val) in SCALE_1_3_SCORE:
            return SCALE_1_3_SCORE[int(val)], f"{col}_scale_1_3"

    # 4. Already-normalized Easy / Medium / Hard label.
    norm_lbl = _label_score(row.get("difficulty_normalized"))
    if norm_lbl is not None:
        return _clamp(norm_lbl), "difficulty_normalized"

    # 5. Parse free text for embedded keywords.
    for col in ("difficulty", "difficulty_raw"):
        text = (row.get(col) or "").lower()
        if not text:
            continue
        # Longest phrases first so "medium to hard" wins over "medium".
        for phrase in sorted(LABEL_SCORE, key=len, reverse=True):
            if re.search(rf"\b{re.escape(phrase)}\b", text):
                return LABEL_SCORE[phrase], f"{col}_text:{phrase}"

    return None, "none"


def bucket(score: Optional[float]) -> str:
    """Map a composite score to Easy / Medium / Hard (or ``''`` if unknown)."""
    if score is None:
        return ""
    if score < EASY_MAX:
        return "Easy"
    if score < HARD_MIN:
        return "Medium"
    return "Hard"


def rate_catalog(
    input_csv: Path,
    output_csv: Path,
    score_col: str = "difficulty_score",
    rating_col: str = "difficulty_rating",
    source_col: str = "difficulty_rating_source",
) -> Counter:
    """
    Read `input_csv`, add the three new columns, and write to `output_csv`.

    Returns a Counter of the resulting rating distribution.
    """
    with open(input_csv, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        fieldnames = list(reader.fieldnames or [])

    for col in (score_col, rating_col, source_col):
        if col not in fieldnames:
            fieldnames.append(col)

    dist: Counter = Counter()
    for row in rows:
        score, source = score_row(row)
        rating = bucket(score)
        row[score_col]  = "" if score is None else f"{score:.1f}"
        row[rating_col] = rating
        row[source_col] = source
        dist[rating or "(unrated)"] += 1

    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(output_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    return dist


# ── Internal helpers ─────────────────────────────────────────────────────────

def _to_float(value: object, allow_1_3: bool = False) -> Optional[float]:
    """
    Return ``value`` as a numeric score, or None if not numeric.

    When ``allow_1_3`` is False the value must lie in [1, 10]; when True
    we also accept values in [1, 3] (they'll be mapped to 1–10 elsewhere).
    """
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        f = float(s)
    except ValueError:
        return None
    if allow_1_3 and 1.0 <= f <= 3.0:
        return f
    if 1.0 <= f <= 10.0:
        return f
    return None


def _looks_like_1_3_scale(row: dict) -> bool:
    """Heuristic: True if this row's numeric difficulty fields look like a 1–3 scale."""
    overall = (row.get("difficulty") or "").strip()
    if overall not in {"1", "2", "3"}:
        return False
    nums: list[float] = []
    for col in ("difficulty_quant", "difficulty_qual",
                "difficulty_structure", "difficulty_math",
                "difficulty_creativity"):
        s = (row.get(col) or "").strip()
        try:
            nums.append(float(s))
        except ValueError:
            continue
    return bool(nums) and all(1.0 <= n <= 3.0 for n in nums)


def _score_from_1_3(value: float) -> float:
    """Linearly interpolate a 1–3 scale value onto the 1–10 composite axis."""
    # Anchor: 1 → 3.5 (Easy), 2 → 5.5 (Medium), 3 → 8.0 (Hard).
    if value <= 2.0:
        return 3.5 + (value - 1.0) * (5.5 - 3.5)
    return 5.5 + (value - 2.0) * (8.0 - 5.5)


def _label_score(value: object) -> Optional[float]:
    """Map a categorical label (Easy / Medium / Hard / Difficult / ...) to a score."""
    if value is None:
        return None
    s = str(value).strip().lower()
    if not s:
        return None
    if s in LABEL_SCORE:
        return LABEL_SCORE[s]
    # Only accept short labels to avoid matching narrative sentences stored in
    # these columns by earlier extraction bugs.
    if len(s) > 24:
        return None
    for phrase, score in sorted(LABEL_SCORE.items(), key=lambda p: -len(p[0])):
        if re.search(rf"\b{re.escape(phrase)}\b", s):
            return score
    return None


def _clamp(score: float) -> float:
    return max(1.0, min(10.0, score))


# ── CLI ──────────────────────────────────────────────────────────────────────

def _main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input", type=Path, default=Path("output/case_catalog.csv"),
        help="Input catalog CSV.",
    )
    parser.add_argument(
        "--output", type=Path, default=None,
        help="Output CSV. Defaults to overwriting the input file.",
    )
    args = parser.parse_args()

    out = args.output or args.input
    dist = rate_catalog(args.input, out)

    total = sum(dist.values())
    print(f"Rated {total} cases -> {out}")
    for label in ("Easy", "Medium", "Hard", "(unrated)"):
        n = dist.get(label, 0)
        pct = (100.0 * n / total) if total else 0.0
        print(f"  {label:<10} {n:>4}  ({pct:5.1f}%)")


if __name__ == "__main__":
    _main()
