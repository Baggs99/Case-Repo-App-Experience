"""
Difficulty normalization.

Reduces every source-specific difficulty system to a single controlled
vocabulary: ``"Easy"``, ``"Medium"``, ``"Hard"``, or ``None``.

Sources handled
---------------
* **Booth**      – ``difficulty`` in {``Light``/``Medium``/``Heavy``}
                   (also already-normalized ``Easy``/``Medium``/``Hard``)
* **Columbia**   – ``difficulty`` in {``Easy``/``Medium``/``Hard``/``Very Hard``}
* **Darden**     – ``difficulty`` overall on a 1–3 integer scale; per-dimension
                   ``difficulty_quant``/``difficulty_qual`` also 1–3
* **Fuqua**      – ``difficulty_quant``/``difficulty_qual`` in
                   {``Easy``/``Medium``/``Difficult``}
* **Kellogg**    – ``difficulty_quant``/``difficulty_structure`` on a 1–10 scale
* **Ross**       – visual dots only (``difficulty_visual_present``); no
                   categorical value is emitted.  Also 1 row with
                   ``"Easy, Round 1 Case"``.
* **Stern 2021** – numeric 1–10 on ``difficulty_quant``/``difficulty_structure``
* **Stern 2025** – numeric ``difficulty_quant`` + categorical
                   ``difficulty_structure``
* **Wharton**    – compound ``difficulty`` strings like ``"Medium to Hard"``
                   or ``"Hard if you aren't familiar with operations strategy"``
* **Yale**       – categorical ``difficulty_quant``/``difficulty_qual``
                   (``Easy``/``Medium``/``Hard``)
* **Harvard / MIT / Tuck / RocketBlocks** – no difficulty data; returns None.

Rules
-----
Priority, in order:

1. If the ``difficulty`` overall field is a recognised single value
   (categorical or numeric), return that bucket directly.
2. If both per-dimension fields are numeric in the 1–10 range, average
   them and threshold at 4.5 / 7.5.
3. If both per-dimension fields are numeric in the 1–3 range, average
   them and threshold at 1.5 / 2.5.
4. If quant + qual (or quant + structure) resolve individually to
   categorical buckets, combine with the Yale matrix (pick the higher
   of the two when they disagree by one step).
5. If only one dimension resolves, return that bucket.
6. If only visual dots are present, return None (preserve the dots flag
   separately in the catalog).
7. Otherwise return None.

OCR noise handling
------------------
Some Darden/Stern cells contain sentence fragments ("A great candidate
will ask…", "headed and use their logic…").  These get parsed to None
silently — no warning — and the normalizer falls through to the next
priority level.
"""

from __future__ import annotations

import re
from typing import Any, Optional


# ── Allowed output values ─────────────────────────────────────────────────────
BUCKETS = ("Easy", "Medium", "Hard")
_RANK = {"Easy": 1, "Medium": 2, "Hard": 3}


# ── Vocabulary for categorical parsing ────────────────────────────────────────
# Keyed by the lowercase token found inside a value.  "very hard" / "very
# difficult" are checked first so they short-circuit before "hard".
_CATEGORICAL_MAP = {
    "very hard":      "Hard",
    "very difficult": "Hard",
    "easy":           "Easy",
    "light":          "Easy",
    "medium":         "Medium",
    "moderate":       "Medium",
    "hard":           "Hard",
    "heavy":          "Hard",
    "difficult":      "Hard",
}

# Regex to pull every categorical token from a compound string like
# "Medium to Hard" or "Hard if you aren't familiar with operations strategy".
_TOKEN_RE = re.compile(
    r"\bvery\s+hard\b|\bvery\s+difficult\b|"
    r"\beasy\b|\blight\b|\bmedium\b|\bmoderate\b|"
    r"\bhard\b|\bheavy\b|\bdifficult\b",
    re.IGNORECASE,
)


# ── Private helpers ───────────────────────────────────────────────────────────

def _clean(v: Any) -> str:
    """Return a stripped string, or empty string if *v* is None/blank."""
    if v is None:
        return ""
    return str(v).strip()


def _as_number(v: Any) -> Optional[float]:
    """Return *v* parsed as float, or None if it isn't a simple numeric value."""
    s = _clean(v)
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _numeric_small_to_bucket(n: float) -> Optional[str]:
    """Map a 1–3 numeric score to Easy/Medium/Hard."""
    if n < 1.5:
        return "Easy"
    if n < 2.5:
        return "Medium"
    if n <= 3.0:
        return "Hard"
    return None


def _numeric_tenpoint_to_bucket(n: float) -> Optional[str]:
    """Map a 4–10 numeric score to Easy/Medium/Hard."""
    if n < 4.5:
        return "Easy"
    if n < 7.5:
        return "Medium"
    if n <= 10.0:
        return "Hard"
    return None


def _parse_single(v: Any) -> Optional[str]:
    """
    Resolve *v* to one of the buckets, or return None.

    Accepts numeric (1–3 or 4–10 scale), plain categorical ("Easy"),
    and compound strings ("Medium to Hard", "Easy, Round 1 Case") by
    extracting all recognisable tokens and picking the highest bucket.
    """
    s = _clean(v)
    if not s:
        return None

    n = _as_number(s)
    if n is not None:
        if 1 <= n <= 3:
            return _numeric_small_to_bucket(n)
        if 3 < n <= 10:
            return _numeric_tenpoint_to_bucket(n)
        return None   # out of range → treat as noise

    # Categorical / compound string: collect every recognised token.
    tokens = _TOKEN_RE.findall(s)
    if not tokens:
        return None

    buckets: list[str] = []
    for t in tokens:
        key = re.sub(r"\s+", " ", t.lower())
        bucket = _CATEGORICAL_MAP.get(key)
        if bucket:
            buckets.append(bucket)

    if not buckets:
        return None

    # When a value contains a range or multiple tokens, pick the higher one.
    return max(buckets, key=lambda b: _RANK[b])


def _combine_yale(a: str, b: str) -> str:
    """
    Combine two categorical buckets per the Yale quant+qual matrix.

    Logic: take the higher of the two, but soften a Hard+Easy pair to Medium
    (matching the user-supplied table):

        Easy   + Easy   -> Easy
        Easy   + Medium -> Easy
        Easy   + Hard   -> Medium
        Medium + Medium -> Medium
        Medium + Hard   -> Hard
        Hard   + Hard   -> Hard
    """
    ra, rb = _RANK[a], _RANK[b]
    hi, lo = max(ra, rb), min(ra, rb)

    if hi == 1:
        return "Easy"             # Easy + Easy
    if hi == 2:
        return "Easy" if lo == 1 else "Medium"
    # hi == 3
    if lo == 1:
        return "Medium"           # Hard + Easy
    return "Hard"                 # Hard + Medium / Hard + Hard


def _is_truthy_flag(v: Any) -> bool:
    """Return True if *v* is a truthy boolean flag (True, 'True', 'true', etc.)."""
    if v is True:
        return True
    if isinstance(v, str):
        return v.strip().lower() in {"true", "yes", "1"}
    return False


# ── Public API ────────────────────────────────────────────────────────────────

def normalize_difficulty(row: dict) -> tuple[Optional[str], str]:
    """
    Resolve a catalog row's difficulty to (bucket, raw_summary).

    Parameters
    ----------
    row:
        Dict containing (any subset of) ``difficulty``, ``difficulty_quant``,
        ``difficulty_qual``, ``difficulty_structure``, ``difficulty_visual_present``.

    Returns
    -------
    bucket:
        ``"Easy"``, ``"Medium"``, ``"Hard"``, or ``None`` when nothing
        usable is present.
    raw_summary:
        Short human-readable string describing what was used to derive
        the bucket (``""`` when nothing was found).  Suitable for the
        ``difficulty_raw`` column.
    """
    overall = _clean(row.get("difficulty"))

    # 1. Overall categorical / numeric → direct mapping
    if overall:
        bucket = _parse_single(overall)
        if bucket:
            return bucket, overall
        # overall was unparseable noise; fall through to per-dimension.

    q_raw = _clean(row.get("difficulty_quant"))
    u_raw = _clean(row.get("difficulty_qual"))
    s_raw = _clean(row.get("difficulty_structure"))

    q_num = _as_number(q_raw)
    u_num = _as_number(u_raw)
    s_num = _as_number(s_raw)

    # 2. Pair of numerics on the 1–10 scale → average + threshold
    if q_num is not None and s_num is not None and (q_num > 3 or s_num > 3):
        avg = (q_num + s_num) / 2
        bucket = _numeric_tenpoint_to_bucket(avg)
        if bucket:
            return bucket, f"quant={q_raw}; structure={s_raw} (avg={avg:.1f}/10)"

    if q_num is not None and u_num is not None and (q_num > 3 or u_num > 3):
        avg = (q_num + u_num) / 2
        bucket = _numeric_tenpoint_to_bucket(avg)
        if bucket:
            return bucket, f"quant={q_raw}; qual={u_raw} (avg={avg:.1f}/10)"

    # 3. Pair of numerics on the 1–3 scale (Darden per-dimension) → avg + threshold
    if q_num is not None and u_num is not None and q_num <= 3 and u_num <= 3:
        avg = (q_num + u_num) / 2
        bucket = _numeric_small_to_bucket(avg)
        if bucket:
            return bucket, f"quant={q_raw}; qual={u_raw} (avg={avg:.1f}/3)"

    # 4. Categorical / mixed pairs → Yale matrix
    q_b = _parse_single(q_raw)
    u_b = _parse_single(u_raw)
    s_b = _parse_single(s_raw)

    if q_b and u_b:
        return _combine_yale(q_b, u_b), f"quant={q_raw}; qual={u_raw}"

    if q_b and s_b:
        return _combine_yale(q_b, s_b), f"quant={q_raw}; structure={s_raw}"

    # 5. Only one dimension resolved
    if s_b:
        return s_b, f"structure={s_raw}"
    if q_b:
        return q_b, f"quant={q_raw}"
    if u_b:
        return u_b, f"qual={u_raw}"

    # 6. Visual dots only — flag-only sources (Ross 2022/2024)
    if _is_truthy_flag(row.get("difficulty_visual_present")):
        return None, "visual dots only"

    # 7. Nothing usable
    return None, ""
