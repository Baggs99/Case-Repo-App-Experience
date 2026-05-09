"""
One-shot helper: read output/duplicate_review_candidates.csv and produce
output/duplicate_review_approved.csv with ``approved=yes`` only on rows
whose match kind is high-confidence:

  * ``exact_normalized_title`` — same normalized_title as canonical
  * ``loose_title_same_school`` — same school + same loose key
    (covers Salty Sole / Wine / Healthy Foods kind of suffix-or-&-only diffs)

Fuzzy_title rows are left ``no`` so the operator can review by hand.
"""

from __future__ import annotations

import csv
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CAND = REPO / "output" / "duplicate_review_candidates.csv"
OUT = REPO / "output" / "duplicate_review_approved.csv"

SAFE_KINDS = ("exact_normalized_title", "loose_title_same_school")


def is_safe(reason: str) -> bool:
    head = (reason or "").strip().split(";", 1)[0].strip().lower()
    return head in SAFE_KINDS


def main() -> int:
    if not CAND.exists():
        print(f"Missing {CAND} — run scripts/find-likely-duplicate-cases.py first.")
        return 1

    with open(CAND, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = (reader.fieldnames or []) + ["approved"]
        rows = list(reader)

    n_approved_dup = 0
    n_approved_canon = 0
    n_skipped_rows = 0
    n_skipped_groups = 0

    # A group is approvable only when EVERY mark_duplicate row in it is high
    # confidence (exact normalized title or loose-key + same school). If any
    # duplicate is a fuzzy match, the whole group stays unapproved so the
    # operator can review.
    by_group: dict[str, list[dict]] = {}
    for r in rows:
        by_group.setdefault(r["group_key"], []).append(r)

    safe_groups: set[str] = set()
    for gk, members in by_group.items():
        dup_reasons = [
            (m.get("reason") or "")
            for m in members
            if (m.get("recommended_action") or "").strip().lower() == "mark_duplicate"
        ]
        if dup_reasons and all(is_safe(rs) for rs in dup_reasons):
            safe_groups.add(gk)
        else:
            n_skipped_groups += 1

    for r in rows:
        gk = r["group_key"]
        action = (r.get("recommended_action") or "").strip().lower()
        if gk in safe_groups:
            r["approved"] = "yes"
            if action == "mark_duplicate":
                n_approved_dup += 1
            else:
                n_approved_canon += 1
        else:
            r["approved"] = "no"
            n_skipped_rows += 1

    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)

    print(f"Wrote {OUT}")
    print(f"  approved groups:           {len(safe_groups)}")
    print(f"  approved mark_duplicate:   {n_approved_dup}")
    print(f"  approved keep_canonical:   {n_approved_canon}")
    print(f"  unapproved groups (fuzzy): {n_skipped_groups}")
    print(f"  unapproved rows (fuzzy):   {n_skipped_rows}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
