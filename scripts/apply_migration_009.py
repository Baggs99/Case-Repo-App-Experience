"""Apply db/migrations/009_case_duplicate_review_flags.sql

Same pattern as scripts/apply_migration_005.py — see that file for
notes on MIGRATION_DATABASE_URL vs DATABASE_URL and the localhost
sslmode coercion.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

REPO = Path(__file__).resolve().parents[1]


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def _coerce_url_for_localhost(url: str) -> str:
    p = urlparse(url)
    if p.hostname not in ("localhost", "127.0.0.1", "::1"):
        return url
    q = parse_qs(p.query, keep_blank_values=True)
    if q.get("sslmode") == ["require"]:
        q["sslmode"] = ["prefer"]
    else:
        return url
    new_query = urlencode(q, doseq=True)
    return urlunparse(p._replace(query=new_query))


def main() -> int:
    load_dotenv(REPO / ".env")
    url = os.environ.get("MIGRATION_DATABASE_URL") or os.environ.get("DATABASE_URL")
    if not url:
        print("ERROR: Set MIGRATION_DATABASE_URL or DATABASE_URL.", file=sys.stderr)
        return 2

    url = _coerce_url_for_localhost(url)

    sql_path = REPO / "db" / "migrations" / "009_case_duplicate_review_flags.sql"
    if not sql_path.is_file():
        print(f"ERROR: missing {sql_path}", file=sys.stderr)
        return 1

    sql = sql_path.read_text(encoding="utf-8")

    import psycopg

    with psycopg.connect(url, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            cur.execute(
                "SELECT column_name, data_type, column_default "
                "FROM information_schema.columns "
                "WHERE table_schema = 'public' AND table_name = 'cases' "
                "AND column_name IN ('is_duplicate_case', 'unique_case_count_eligible') "
                "ORDER BY column_name;"
            )
            cols = cur.fetchall()
            for r in cols:
                print(f"  {r[0]:<32} {r[1]:<10} default={r[2]}")
            cur.execute("SELECT COUNT(*) FROM cases WHERE is_duplicate_case = true;")
            n = cur.fetchone()[0]
            print(f"  rows currently flagged is_duplicate_case=true: {n}")

    print("Migration 009 applied successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
