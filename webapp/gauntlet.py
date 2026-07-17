"""
Purpose: Gauntlet service — score a submission against today's global set,
         persist it, and compose the percentile-first results + trends payloads.
Inputs:  user_id + submitted per-slot answers; reads drills + gauntlet/leaderboard
         /groups repos.
Outputs: results/trends dicts for the drills router; persists via the gauntlet repo.
Run:     from webapp import gauntlet; gauntlet.results_for(1, "2026-07-17")
"""

from __future__ import annotations

from datetime import date, datetime, timezone

from webapp import drills
from webapp.repositories import drill_attempts as drills_repo
from webapp.repositories import gauntlet as repo
from webapp.repositories import groups as groups_repo
from webapp.repositories import leaderboards

#: Human labels for the weak-section CTA ("Practice market sizing").
GAUNTLET_TYPE_LABELS: dict[str, str] = {
    "market_sizing": "market sizing",
    "mental_math": "mental math",
    "framework_recall": "framework recall",
}


class InvalidSubmission(Exception):
    """Malformed submission (wrong slot count / duplicate or out-of-range slots)."""


def _today_key(on: date | None) -> tuple[date, str]:
    day = on or datetime.now(timezone.utc).date()
    return day, day.isoformat()


def submit(user_id: int, answers: list[dict], on: date | None = None) -> dict:
    """Score `answers` against the global daily set, persist one row per slot,
    and return the results payload. Raises InvalidSubmission on a malformed set;
    the repo raises AlreadySubmitted on a repeat same-day submission."""
    day, set_key = _today_key(on)
    full = drills.daily_set(day)
    if not all(isinstance(a.get("slot"), int) for a in answers):
        raise InvalidSubmission("each answer needs an integer slot")
    slots_seen = sorted(a.get("slot") for a in answers)
    if slots_seen != list(range(drills.GAUNTLET_SLOTS)):
        raise InvalidSubmission(f"expected slots 0..{drills.GAUNTLET_SLOTS - 1}, got {slots_seen}")

    rows: list[dict] = []
    for ans in answers:
        wire = full[ans["slot"]]
        correct = drills.score_slot(wire, value=ans.get("value"),
                                    choice_index=ans.get("choice_index"))
        rows.append({"drill_type": wire["drill_type"], "drill_key": wire["key"],
                     "correct": correct, "score": 1.0 if correct else 0.0,
                     "duration_ms": ans.get("duration_ms")})
    repo.record_submission(user_id, set_key, rows)   # may raise AlreadySubmitted
    return results_for(user_id, set_key)


def _group_block(user_id: int) -> dict | None:
    """The user's primary joined group (most recently created group you belong to
    (list_my_groups orders by group created_at DESC)) as a rank+points block — the ONLY scope where literal
    rank/points are exposed. None if unaffiliated."""
    my = groups_repo.list_my_groups(user_id)
    if not my:
        return None
    gid = my[0]["id"]
    name = my[0].get("name")
    board = leaderboards.group_leaderboard(gid)
    mine = next((e for e in board if e["user_id"] == user_id), None)
    if mine is None:
        return None
    rank = mine["rank"]
    behind = (board[rank - 2]["points"] - mine["points"]) if rank > 1 else None
    return {"group_id": gid, "name": name, "rank": rank,
            "points": mine["points"], "points_behind_next": behind}


def results_for(user_id: int, set_key: str) -> dict | None:
    """The percentile-first results payload for a submitted day, or None if the
    user hasn't submitted. Literal rank/points only inside the joined group."""
    summary = repo.submission_summary(user_id, set_key)
    if summary is None:
        return None
    group = _group_block(user_id)
    weak = repo.weakest_type(user_id)
    weak_section = ({"drill_type": weak, "label": GAUNTLET_TYPE_LABELS[weak]}
                    if weak is not None else None)
    return {
        "score": summary["score"],
        "slots_correct": summary["slots_correct"],
        "slots": summary["slots"],
        "points_awarded": int(summary["score"] * leaderboards.POINTS_PER_GAUNTLET_POINT),
        "daily_percentile": repo.daily_percentile(user_id, set_key),
        "group": group,
        # reuses the B6 global percentile (== my_school_standing.your_percentile, the
        # school-card standing); a within-school population is a future refinement
        "school_percentile": leaderboards.user_global_percentile(user_id),
        "vs_peers_delta": group["points_behind_next"] if group else None,
        "weak_section": weak_section,
        "streak": drills_repo.streak_days(user_id),
        "set_key": set_key,
        "provisional": True,
    }


def trends(user_id: int) -> dict:
    """{daily: [{date,score}], by_type: [{drill_type,attempts,correct,accuracy}],
    weakest: drill_type|None} over the last 60 days of gauntlet activity."""
    return {"daily": repo.daily_scores(user_id),
            "by_type": repo.per_type_accuracy(user_id),
            "weakest": repo.weakest_type(user_id)}
