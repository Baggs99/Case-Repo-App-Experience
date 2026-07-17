"""
Purpose: The B7 readiness signal — ONE swap-point (OD-B7-1 stand-in) that every
  caller goes through — plus the reweight payload derived from the diagnostic +
  recommendation engine. See docs/superpowers/notes/2026-07-17-readiness-signal-seams.md.
Inputs:  user_id; dashboard repo (dimension averages, recommendations);
  practice_sessions (recent candidate-finalized count).
Outputs: readiness_signal() / reweight_payload() dicts. No side effects.
Run:     from webapp import readiness; readiness.readiness_signal(user_id)
"""

from __future__ import annotations

from webapp.db import get_pool
from webapp.repositories import dashboard as dashboard_repo

# Stand-in thresholds (OD-B7-1, DV-B7-3). dimension_averages is a /5 scale.
READINESS_THRESHOLD = 3.0
READINESS_MIN_CASES = 3
DIAGNOSTIC_WINDOW_DAYS = 60


def _recent_case_count(user_id: int, window_days: int = DIAGNOSTIC_WINDOW_DAYS) -> int:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM practice_sessions"
                " WHERE candidate_id = %(u)s AND state = 'finalized'"
                "   AND ended_at >= NOW() - make_interval(days => %(w)s);",
                {"u": user_id, "w": window_days})
            return int(cur.fetchone()[0])


def readiness_signal(user_id: int) -> dict:
    """Stand-in readiness (OD-B7-1): needs_work if the user has fewer than
    READINESS_MIN_CASES recent candidate sessions OR their weakest dimension
    averages below READINESS_THRESHOLD; else on_track. Firm-independent — the
    per-firm display tag is derived in timeline_service (DV-B7-5)."""
    dims = dashboard_repo.dimension_averages(user_id)   # ascending, /5
    recent = _recent_case_count(user_id)
    focus = dims[0]["dimension"] if dims else None
    weakest_avg = float(dims[0]["avg_score"]) if dims else None
    on_track = (recent >= READINESS_MIN_CASES
                and weakest_avg is not None
                and weakest_avg >= READINESS_THRESHOLD)
    return {
        "label": "on_track" if on_track else "needs_work",
        "ready": on_track,
        "focus_dimension": focus,
        "recent_case_count": recent,
        "threshold": READINESS_THRESHOLD,
        "min_cases": READINESS_MIN_CASES,
    }


def suggested_drill_type(dimension: str | None) -> str:
    """Map a rubric dimension name to one of the 3 existing drill generators
    (webapp/drills.py _TYPES). Substring match keeps it robust to naming."""
    if not dimension:
        return "mental_math"
    d = dimension.lower()
    if "siz" in d:
        return "market_sizing"
    if "quant" in d or "math" in d or "numer" in d:
        return "mental_math"
    return "framework_recall"


def reweight_payload(user_id: int) -> dict:
    """The 'No offer → reweight' response (DESIGN DELTA). focus_dimension +
    drill from the diagnostic; extra_cases from the B4 rec engine (limit 2 —
    'two extra cases before BCG'). Derivation is a documented seam."""
    sig = readiness_signal(user_id)
    focus = sig["focus_dimension"]
    recs = dashboard_repo.recommendations(user_id, [], limit=2)
    return {
        "focus_dimension": focus,
        "suggested_drill_type": suggested_drill_type(focus),
        "extra_cases": [r["case_id"] for r in recs],
    }
