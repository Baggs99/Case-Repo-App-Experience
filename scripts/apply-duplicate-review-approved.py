#!/usr/bin/env python3
"""
Apply operator-approved duplicate flags from a CSV (updates Postgres only).

Input file (default): output/duplicate_review_approved.csv

Required columns (from the candidate export, plus approval):
    case_id, recommended_action, approved

``approved`` must be truthy (1, yes, true, y, on) for a row to be applied.

Actions:
    mark_duplicate  → is_duplicate_case=true,  unique_case_count_eligible=false
    keep_canonical  → is_duplicate_case=false, unique_case_count_eligible=true

Usage:
    python scripts/apply-duplicate-review-approved.py
    python scripts/apply-duplicate-review-approved.py --dry-run
    python scripts/apply-duplicate-review-approved.py --file path/to/approved.csv
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

try:
    from dotenv import load_dotenv

    load_dotenv(REPO_ROOT / ".env")
except ImportError:
    pass

import psycopg

_TRUTHY = {"1", "true", "yes", "y", "on"}


def _approved_val(raw: str) -> bool:
    return str(raw or "").strip().lower() in _TRUTHY


def _find_approve_column(fieldnames: list[str]) -> str | None:
    for name in fieldnames:
        low = name.lower().strip()
        if low in ("approved", "approve", "apply"):
            return name
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--file",
        type=Path,
        default=REPO_ROOT / "output" / "duplicate_review_approved.csv",
        help="CSV path (copy of candidates with an approved column)",
    )
    ap.add_argument("--dry-run", action="store_true", help="Print SQL but do not commit")
    args = ap.parse_args()

    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url:
        print("DATABASE_URL is not set.", file=sys.stderr)
        sys.exit(1)

    if not args.file.exists():
        print(f"Input file not found: {args.file}", file=sys.stderr)
        sys.exit(1)

    with open(args.file, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            print("CSV has no header row.", file=sys.stderr)
            sys.exit(1)
        approve_col = _find_approve_column(list(reader.fieldnames))
        if not approve_col:
            print(
                "CSV must include an ``approved`` (or ``approve`` / ``apply``) column.",
                file=sys.stderr,
            )
            sys.exit(1)
        rows = list(reader)

    to_apply: list[tuple[str, int]] = []
    for row in rows:
        if not _approved_val(row.get(approve_col, "")):
            continue
        try:
            cid = int(row["case_id"])
        except (KeyError, TypeError, ValueError):
            print(f"Skipping row with bad case_id: {row}", file=sys.stderr)
            continue
        action = (row.get("recommended_action") or "").strip().lower()
        if action not in ("mark_duplicate", "keep_canonical"):
            print(f"Skipping approved row {cid}: unknown action {action!r}", file=sys.stderr)
            continue
        to_apply.append((action, cid))

    if not to_apply:
        print("No approved rows to apply.")
        return

    dup_sql = """
        UPDATE cases
        SET is_duplicate_case = %s,
            unique_case_count_eligible = %s,
            updated_at = NOW()
        WHERE id = %s;
    """

    with psycopg.connect(database_url) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT column_name FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'cases'
                  AND column_name IN ('is_duplicate_case', 'unique_case_count_eligible');
                """
            )
            found = {r[0] for r in cur.fetchall()}
            if found != {"is_duplicate_case", "unique_case_count_eligible"}:
                print(
                    "ERROR: apply db/migrations/009_case_duplicate_review_flags.sql first.",
                    file=sys.stderr,
                )
                sys.exit(2)

        n = 0
        with conn.cursor() as cur:
            for action, cid in to_apply:
                if action == "mark_duplicate":
                    params = (True, False, cid)
                else:
                    params = (False, True, cid)
                if args.dry_run:
                    print(f"DRY-RUN {action} case_id={cid} -> {params[:2]}")
                else:
                    cur.execute(dup_sql, params)
                    n += cur.rowcount
        if args.dry_run:
            print(f"Dry-run complete - {len(to_apply)} rows would be updated.")
        else:
            conn.commit()
            print(f"Updated {n} case row(s).")


if __name__ == "__main__":
    main()
