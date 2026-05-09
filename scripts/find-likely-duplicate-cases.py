#!/usr/bin/env python3
"""
Find likely duplicate cases for human review (no database writes).

Reads all rows from ``cases``, builds conservative duplicate groups, and
writes ``output/duplicate_review_candidates.csv``.

Requires ``DATABASE_URL`` (or ``.env`` loaded by python-dotenv if installed).

Usage:
    python scripts/find-likely-duplicate-cases.py

Then review the CSV, copy it to ``output/duplicate_review_approved.csv``,
set ``approved`` to yes for rows you want applied, and run:
    python scripts/apply-duplicate-review-approved.py
"""

from __future__ import annotations

import csv
import os
import sys
from collections import defaultdict
from pathlib import Path

# Repo root on sys.path
REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

try:
    from dotenv import load_dotenv

    load_dotenv(REPO_ROOT / ".env")
except ImportError:
    pass

import psycopg
from psycopg.rows import dict_row

from utils.duplicate_review import (
    _FUZZY_MIN_RATIO,
    duplicate_loose_key,
    pick_canonical_row,
    recommendation_reason,
    title_similarity,
)


def _load_cases(conn) -> list[dict]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'cases'
              AND column_name IN ('is_duplicate_case', 'unique_case_count_eligible');
            """
        )
        cols = {r["column_name"] for r in cur.fetchall()}
        has_dup = "is_duplicate_case" in cols
        has_elig = "unique_case_count_eligible" in cols

        if not has_dup or not has_elig:
            print(
                "ERROR: cases table is missing is_duplicate_case or "
                "unique_case_count_eligible.\n"
                "Apply db/migrations/009_case_duplicate_review_flags.sql first.",
                file=sys.stderr,
            )
            sys.exit(2)

        cur.execute(
            """
            SELECT
                id,
                case_title,
                normalized_title,
                source_school,
                source_year,
                industry,
                case_type,
                difficulty,
                pdf_path,
                is_duplicate_case,
                unique_case_count_eligible
            FROM cases
            ORDER BY id;
            """
        )
        return list(cur.fetchall())


class _UF:
    def __init__(self) -> None:
        self._p: dict[int, int] = {}

    def find(self, x: int) -> int:
        self._p.setdefault(x, x)
        if self._p[x] != x:
            self._p[x] = self.find(self._p[x])
        return self._p[x]

    def union(self, a: int, b: int) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self._p[rb] = ra

    def components(self) -> dict[int, list[int]]:
        groups: dict[int, list[int]] = defaultdict(list)
        for x in list(self._p.keys()):
            groups[self.find(x)].append(x)
        return dict(groups)


def _build_groups(cases: list[dict]) -> list[list[dict]]:
    """Return list of case groups (each len >= 2) using union-find."""
    by_id = {int(c["id"]): c for c in cases}
    uf = _UF()

    # 1) Exact normalized_title (non-empty)
    by_nt: dict[str, list[dict]] = defaultdict(list)
    for c in cases:
        nt = (c.get("normalized_title") or "").strip()
        if nt:
            by_nt[nt].append(c)
    for rows in by_nt.values():
        if len(rows) < 2:
            continue
        ids = [int(r["id"]) for r in rows]
        for i in range(1, len(ids)):
            uf.union(ids[0], ids[i])

    # 2) Loose key + same school
    by_loose: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for c in cases:
        lk = duplicate_loose_key(c.get("case_title") or "")
        sch = (c.get("source_school") or "").strip()
        if lk and sch:
            by_loose[(lk, sch)].append(c)
    for rows in by_loose.values():
        if len(rows) < 2:
            continue
        ids = [int(r["id"]) for r in rows]
        for i in range(1, len(ids)):
            uf.union(ids[0], ids[i])

    # 3) Fuzzy pairs (conservative gate)
    n = len(cases)
    for i in range(n):
        for j in range(i + 1, n):
            a, b = cases[i], cases[j]
            if int(a["id"]) == int(b["id"]):
                continue
            if title_similarity(a.get("case_title") or "", b.get("case_title") or "") < _FUZZY_MIN_RATIO:
                continue
            same_school = (a.get("source_school") or "").strip() == (b.get("source_school") or "").strip()
            ind_a, ind_b = a.get("industry"), b.get("industry")
            ct_a, ct_b = a.get("case_type"), b.get("case_type")
            same_ind_ct = (
                ind_a and ind_b and ct_a and ct_b
                and str(ind_a).strip() == str(ind_b).strip()
                and str(ct_a).strip() == str(ct_b).strip()
            )
            if not (same_school or same_ind_ct):
                continue
            uf.union(int(a["id"]), int(b["id"]))

    out: list[list[dict]] = []
    for _root, id_list in uf.components().items():
        if len(id_list) < 2:
            continue
        members = [by_id[i] for i in sorted(id_list)]
        out.append(members)
    return out


def _group_key(members: list[dict]) -> str:
    ids = sorted(int(m["id"]) for m in members)
    return f"merged|{'-'.join(str(i) for i in ids)}"


def _match_kind_for_row(row: dict, canonical: dict, members: list[dict]) -> str:
    nt = (row.get("normalized_title") or "").strip()
    c_nt = (canonical.get("normalized_title") or "").strip()
    if nt and nt == c_nt:
        return "exact_normalized_title"
    lk_r = duplicate_loose_key(row.get("case_title") or "")
    lk_c = duplicate_loose_key(canonical.get("case_title") or "")
    if lk_r == lk_c and (row.get("source_school") or "") == (canonical.get("source_school") or ""):
        return "loose_title_same_school"
    return "fuzzy_title"


def main() -> None:
    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url:
        print("DATABASE_URL is not set.", file=sys.stderr)
        sys.exit(1)

    out_path = REPO_ROOT / "output" / "duplicate_review_candidates.csv"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with psycopg.connect(database_url) as conn:
        cases = _load_cases(conn)

    groups = _build_groups(cases)
    rows_out: list[dict] = []

    for members in groups:
        canonical = pick_canonical_row(members)
        cid = int(canonical["id"])
        gkey = _group_key(members)
        for m in members:
            mid = int(m["id"])
            is_canon = mid == cid
            action = "keep_canonical" if is_canon else "mark_duplicate"
            mk = _match_kind_for_row(m, canonical, members)
            reason = recommendation_reason(row=m, canonical=canonical, match_kind=mk)
            rows_out.append(
                {
                    "group_key": gkey,
                    "case_id": mid,
                    "title": m.get("case_title") or "",
                    "source_school": m.get("source_school") or "",
                    "source_year": m.get("source_year") if m.get("source_year") is not None else "",
                    "industry": m.get("industry") or "",
                    "case_type": m.get("case_type") or "",
                    "difficulty": m.get("difficulty") or "",
                    "pdf_path": m.get("pdf_path") or "",
                    "current_is_duplicate_case": str(bool(m.get("is_duplicate_case"))).lower(),
                    "current_unique_case_count_eligible": str(
                        bool(m.get("unique_case_count_eligible", True))
                    ).lower(),
                    "recommended_canonical": cid,
                    "recommended_action": action,
                    "reason": reason,
                }
            )

    fieldnames = [
        "group_key",
        "case_id",
        "title",
        "source_school",
        "source_year",
        "industry",
        "case_type",
        "difficulty",
        "pdf_path",
        "current_is_duplicate_case",
        "current_unique_case_count_eligible",
        "recommended_canonical",
        "recommended_action",
        "reason",
    ]
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in sorted(rows_out, key=lambda x: (x["group_key"], int(x["case_id"]))):
            w.writerow(r)

    print(f"Wrote {len(rows_out)} rows across {len(groups)} candidate groups -> {out_path}")
    print()
    print("--- Candidate groups (summary) ---")
    for members in sorted(groups, key=lambda g: min(int(x["id"]) for x in g))[:80]:
        gkey = _group_key(members)
        titles = " | ".join(f'{m["id"]}:{m.get("case_title")} ({m.get("source_school")} {m.get("source_year")})' for m in sorted(members, key=lambda x: int(x["id"])))
        print(f"[{gkey}]")
        print(f"  {titles}")
    if len(groups) > 80:
        print(f"... and {len(groups) - 80} more groups (see CSV).")
    print()
    print("Next steps:")
    print("  1. Review duplicate_review_candidates.csv")
    print("  2. Copy to output/duplicate_review_approved.csv")
    print("  3. Add column approved = yes for each row you want applied")
    print("  4. Run: python scripts/apply-duplicate-review-approved.py")


if __name__ == "__main__":
    main()
