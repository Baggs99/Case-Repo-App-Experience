"""Apply db/migrations/005_case_access_kind_constraint_fix.sql

Environment (first match wins):
  MIGRATION_DATABASE_URL  — use this for production / one-off (overrides .env)
  DATABASE_URL            — from .env or your shell (after load_dotenv)

For local Postgres when your URL has sslmode=require but the server has no SSL,
set PGSSLMODE=prefer in the shell or use a URL with sslmode=prefer.
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
    """If connecting to localhost with sslmode=require, prefer() avoids local SSL errors."""
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
        print(
            "ERROR: Set MIGRATION_DATABASE_URL or DATABASE_URL (e.g. in .env).",
            file=sys.stderr,
        )
        return 2

    url = _coerce_url_for_localhost(url)

    sql_path = REPO / "db" / "migrations" / "005_case_access_kind_constraint_fix.sql"
    if not sql_path.is_file():
        print(f"ERROR: missing {sql_path}", file=sys.stderr)
        return 1

    sql = sql_path.read_text(encoding="utf-8")

    import psycopg

    try:
        with psycopg.connect(url, autocommit=True) as conn:
            with conn.cursor() as cur:
                cur.execute(sql)
    except Exception as e:
        err = str(e).lower()
        if "case_access_events" in err and "does not exist" in err:
            print(
                "ERROR: The connected database has no case_access_events table.\n"
                "This is usually the wrong database (e.g. empty local Postgres).\n"
                "Use your *production* Postgres URL:\n"
                "  PowerShell:\n"
                "    $env:MIGRATION_DATABASE_URL='<paste from Render Postgres>'\n"
                "    python scripts/apply_migration_005.py\n"
                "  Or on Render: open Render Shell, then:\n"
                "    psql $DATABASE_URL -f db/migrations/005_case_access_kind_constraint_fix.sql",
                file=sys.stderr,
            )
        else:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    print("Migration 005 applied successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
