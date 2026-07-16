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
