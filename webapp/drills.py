"""
Purpose: Server-side drill template bank + deterministic drill generator for
         the P4 habit layer — the single source the iOS FM engine mirrors.
Inputs:  webapp/drill_templates.json (read once at import); generate_drill()
         takes a template dict + int seed; daily_drill() takes user_id + date.
Outputs: pure in-memory wire-drill dicts; no DB, no files, no clock reads
         inside generation (the endpoint passes UTC today as `on`).
Run:     python -c "from webapp.drills import daily_drill; print(daily_drill(1))"
"""

from __future__ import annotations

import hashlib
import json
import random
import re
from datetime import date, datetime, timezone

from webapp.settings import REPO_ROOT

_NUM_RE = re.compile(r"\d+(?:\.\d+)?")

#: Drill types indexed by ``seed % 3`` for even daily rotation.
_TYPES = ("mental_math", "market_sizing", "framework_recall")

#: Mental-math answer functions — small pure ops over the drawn params dict.
#: The correctness contract: every answer is recomputable from op + params.
_OPS = {
    "pct_change":            lambda p: (p["b"] - p["a"]) / p["a"] * 100,
    "growth_compound":       lambda p: p["a"] * (1 + p["g"] / 100) ** 2,
    "breakeven_units":       lambda p: p["fixed"] / (p["price"] - p["vc"]),
    "margin_pct":            lambda p: (p["rev"] - p["cost"]) / p["rev"] * 100,
    "markup_price":          lambda p: p["cost"] * (1 + p["markup"] / 100),
    "market_share_revenue":  lambda p: p["market"] * p["share"] / 100,
    "per_capita":            lambda p: p["total"] / p["pop"],
    "weighted_avg_2":        lambda p: (p["v1"] * p["w1"] + p["v2"] * p["w2"]) / (p["w1"] + p["w2"]),
    "cagr_2yr_approx":       lambda p: (p["end"] - p["start"]) / p["start"] / 2 * 100,
    "payback_months":        lambda p: p["invest"] / p["monthly"],
}

_BANK = json.loads((REPO_ROOT / "webapp" / "drill_templates.json").read_text())


def _draw_params(spec: dict, rng: random.Random) -> dict:
    """Draw each `[lo, hi, step]` inclusive range with the given RNG. Insertion
    order (from the JSON) fixes the draw sequence, so it's seed-deterministic."""
    return {name: rng.randrange(lo, hi + 1, step) for name, (lo, hi, step) in spec.items()}


def _fmt_num(value: float) -> str:
    """Human-readable answer for the explanation string (2 dp, trailing .0 dropped)."""
    rounded = round(float(value), 2)
    return str(int(rounded)) if rounded == int(rounded) else str(rounded)


def generate_drill(template: dict, seed: int) -> dict:
    """Deterministically render a template into a wire drill for `seed`.

    Wire shape: {key, drill_type, prompt, choices?, answer, explanation, numbers}
    where `numbers` is every numeric literal appearing in the prompt, as strings,
    exactly as rendered (the iOS FM validator consumes it)."""
    rng = random.Random(seed)
    dtype = template["drill_type"]

    if dtype == "mental_math":
        params = _draw_params(template["params"], rng)
        value = _OPS[template["op"]](params)
        framing = template.get("framing", "").format(**params)
        question = template["question"].format(**params)
        prompt = f"{framing} {question}".strip() if framing else question
        explanation = template.get("explanation", "").format(answer=_fmt_num(value), **params)
        return {
            "key": template["key"],
            "drill_type": dtype,
            "prompt": prompt,
            "answer": {"kind": "numeric", "value": value,
                       "tolerance_pct": float(template["tolerance_pct"])},
            "explanation": explanation,
            "numbers": _NUM_RE.findall(prompt),
        }

    if dtype == "market_sizing":
        params = _draw_params(template["params"], rng)
        value = template["reference_per_unit"] * params[template["unit_param"]]
        prompt = template["question"].format(**params)
        explanation = template.get("explanation", "").format(answer=f"{value:,}", **params)
        return {
            "key": template["key"],
            "drill_type": dtype,
            "prompt": prompt,
            "answer": {"kind": "numeric", "value": float(value),
                       "tolerance_factor": float(template["tolerance_factor"])},
            "explanation": explanation,
            "numbers": _NUM_RE.findall(prompt),
        }

    if dtype == "framework_recall":
        choices = list(template["choices"])
        correct_answer = choices[template["correct_index"]]
        rng.shuffle(choices)
        prompt = template["question"]
        return {
            "key": template["key"],
            "drill_type": dtype,
            "prompt": prompt,
            "choices": choices,
            "answer": {"kind": "choice", "correct_index": choices.index(correct_answer)},
            "explanation": template.get("explanation", ""),
            "numbers": _NUM_RE.findall(prompt),
        }

    raise ValueError(f"unknown drill_type {dtype!r}")


def daily_drill(user_id: int, on: date | None = None) -> dict:
    """The drill for `user_id` on day `on` (UTC today if None). Deterministic all
    day, varies by day and by user. Type is chosen evenly via `seed % 3`, then a
    seeded template of that type."""
    day = on or datetime.now(timezone.utc).date()
    seed = int(hashlib.sha256(f"{user_id}:{day.isoformat()}".encode()).hexdigest()[:8], 16)
    dtype = _TYPES[seed % 3]
    candidates = [t for t in _BANK["templates"] if t["drill_type"] == dtype]
    template = random.Random(seed).choice(candidates)
    return generate_drill(template, seed)


def bank_document() -> dict:
    """The raw bank JSON ({version, templates}) — the device offline cache."""
    return _BANK


# ── B8: global daily gauntlet (date-seeded, same set for everyone) ──────────
# SEAMS ONLY (OD-B8-1): 6 slots served by the 3 existing generator types (2 each),
# every payload flagged provisional. daily_set() is the swap-point the future
# question-bank provider replaces — see docs/superpowers/notes/2026-07-17-drills-bank-integration.md.

#: The gauntlet fills this many slots. "Six types" is the future (bank) vision;
#: today it is 6 slots drawn from the 3 generator types, 2 of each.
GAUNTLET_SLOTS: int = 6


def _slot_seed(day: date, i: int) -> int:
    """Per-slot deterministic seed from the DATE ONLY (never the user) so the set
    is identical for everyone and stable all day, but each slot draws distinctly."""
    return int(hashlib.sha256(f"gauntlet:{day.isoformat()}:{i}".encode()).hexdigest()[:8], 16)


def daily_set(on: date | None = None) -> list[dict]:
    """Today's global gauntlet: `GAUNTLET_SLOTS` full wire drills (with answers,
    for server-side scoring), each carrying its `slot` index. Date-only seeded —
    the SAME set for every user, deterministic across a day. Types are spread
    evenly (2 of each of the 3 generator types)."""
    day = on or datetime.now(timezone.utc).date()
    day_seed = int(hashlib.sha256(f"gauntlet:{day.isoformat()}".encode()).hexdigest()[:8], 16)
    out: list[dict] = []
    for i in range(GAUNTLET_SLOTS):
        dtype = _TYPES[(day_seed + i) % len(_TYPES)]  # 6 slots / 3 types → 2 each
        sub = _slot_seed(day, i)
        candidates = [t for t in _BANK["templates"] if t["drill_type"] == dtype]
        template = random.Random(sub).choice(candidates)
        drill = generate_drill(template, sub)
        drill["slot"] = i
        out.append(drill)
    return out


def public_drill(wire: dict) -> dict:
    """Wire-safe view of a gauntlet slot for the client: prompt + choices + the
    numeric literals, but NEVER the answer/explanation (the server re-scores on
    submit, so the leaderboard can't be gamed by reading the payload)."""
    pub = {
        "slot": wire["slot"],
        "drill_type": wire["drill_type"],
        "key": wire["key"],
        "prompt": wire["prompt"],
        "numbers": wire["numbers"],
    }
    if "choices" in wire:
        pub["choices"] = wire["choices"]
    return pub


def score_slot(wire: dict, *, value: float | None = None,
               choice_index: int | None = None) -> bool:
    """Score one submitted slot answer against its generated wire drill. Numeric
    drills accept a percentage band (`tolerance_pct`) or an order-of-magnitude
    band (`tolerance_factor`); choice drills compare the selected index. A missing
    answer is always wrong."""
    ans = wire["answer"]
    if ans["kind"] == "numeric":
        if value is None:
            return False
        target = float(ans["value"])
        if "tolerance_pct" in ans:
            tol = abs(target) * float(ans["tolerance_pct"]) / 100.0
            return abs(float(value) - target) <= tol
        if "tolerance_factor" in ans:
            f = float(ans["tolerance_factor"])
            lo, hi = sorted((target / f, target * f))  # sorted() so a negative target still bands correctly
            return lo <= float(value) <= hi
        return float(value) == target
    if ans["kind"] == "choice":
        return choice_index is not None and int(choice_index) == int(ans["correct_index"])
    return False
