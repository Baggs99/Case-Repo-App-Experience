"""
Purpose: Assemble tracked firms + curated deadlines + the readiness signal into
  the B7 timeline payloads (GET /api/v1/timeline, /timeline/firms, and the
  dashboard timeline summary).
Inputs:  user_id, as_of (date, passed explicitly for determinism); firms +
  user_firms repos; readiness swap-point.
Outputs: plain dicts for the routers. No side effects.
Run:     from webapp import timeline_service; timeline_service.timeline_view(uid, date.today())
"""

from __future__ import annotations

import datetime

from webapp import readiness
from webapp.repositories import firms as firms_repo
from webapp.repositories import user_firms as user_firms_repo

# Far-out deadlines read as 'early' regardless of readiness (DV-B7-5).
EARLY_DEADLINE_DAYS = 75


def _deadlines_by_firm() -> dict[int, list[dict]]:
    out: dict[int, list[dict]] = {}
    for d in firms_repo.all_deadlines():
        out.setdefault(d["firm_id"], []).append(d)
    return out


def _relevant_deadline(deadlines: list[dict], as_of: datetime.date) -> dict | None:
    """Soonest upcoming deadline, else the latest passed one (the prompt anchor)."""
    if not deadlines:
        return None
    upcoming = sorted((d for d in deadlines if d["deadline_date"] >= as_of),
                      key=lambda d: d["deadline_date"])
    if upcoming:
        return upcoming[0]
    return sorted(deadlines, key=lambda d: d["deadline_date"])[-1]


def _deadline_block(d: dict | None, as_of: datetime.date) -> dict | None:
    if d is None:
        return None
    days = (d["deadline_date"] - as_of).days
    return {
        "cycle_label": d["cycle_label"],
        "deadline_date": d["deadline_date"].isoformat(),
        "region": d["region"],
        "is_estimate": d["is_estimate"],
        "days_remaining": days,
        "passed": days < 0,
    }


def _firm_tag(signal: dict, block: dict | None) -> str:
    """Per-firm display tag over the firm-independent swap-point (DV-B7-5):
    'early' when the deadline is far out, else on_track/focus from readiness."""
    if block is not None and not block["passed"] and block["days_remaining"] > EARLY_DEADLINE_DAYS:
        return "early"
    return "on_track" if signal["ready"] else "focus"


def timeline_view(user_id: int, as_of: datetime.date) -> dict:
    """The 7b Timeline-detail payload: tracked firms + per-firm deadline +
    readiness tag + post-deadline prompt state, plus the top-level signal."""
    signal = readiness.readiness_signal(user_id)
    by_firm = _deadlines_by_firm()
    rows = []
    for uf in user_firms_repo.list_tracked(user_id):
        block = _deadline_block(_relevant_deadline(by_firm.get(uf["firm_id"], []), as_of), as_of)
        rows.append({
            "firm_id": uf["firm_id"],
            "name": uf["name"],
            "slug": uf["slug"],
            "status": uf["status"],
            "added_at": uf["added_at"].isoformat() if uf["added_at"] else None,
            "deadline": block,
            "readiness_tag": _firm_tag(signal, block),
            # Prompt shows only for a still-tracking firm whose deadline passed.
            "prompt": {"show": bool(block and block["passed"] and uf["status"] == "tracking")},
        })
    return {"as_of": as_of.isoformat(), "readiness": signal, "firms": rows}


def firm_catalog(user_id: int, as_of: datetime.date) -> list[dict]:
    """All firms with a tracked flag + next deadline — the add-a-firm picker."""
    tracked_ids = {uf["firm_id"] for uf in user_firms_repo.list_tracked(user_id)}
    by_firm = _deadlines_by_firm()
    out = []
    for f in firms_repo.list_firms():
        block = _deadline_block(_relevant_deadline(by_firm.get(f["id"], []), as_of), as_of)
        out.append({"firm_id": f["id"], "name": f["name"], "slug": f["slug"],
                    "tracked": f["id"] in tracked_ids, "next_deadline": block})
    return out


def next_deadline_summary(user_id: int, as_of: datetime.date) -> dict:
    """Dashboard timeline block: soonest UPCOMING deadline across tracked firms
    + tracked_count. next_deadline is None when nothing is tracked or all
    deadlines have passed."""
    view = timeline_view(user_id, as_of)
    upcoming = [f for f in view["firms"]
                if f["deadline"] and not f["deadline"]["passed"]]
    upcoming.sort(key=lambda f: f["deadline"]["days_remaining"])
    nxt = None
    if upcoming:
        f = upcoming[0]
        nxt = {"firm_id": f["firm_id"], "name": f["name"], "slug": f["slug"],
               "cycle_label": f["deadline"]["cycle_label"],
               "deadline_date": f["deadline"]["deadline_date"],
               "days_remaining": f["deadline"]["days_remaining"],
               "readiness_tag": f["readiness_tag"]}
    return {"tracked_count": len(view["firms"]), "next_deadline": nxt}
