"""
Purpose: seed a local dev database with verified test users and a dummy case
         so CaseRoom flows can be exercised without real signups or PDFs.
Inputs:  DATABASE_URL env (or .env at repo root); no arguments.
Outputs: three users a/b/c@yale.edu (password: caseroom-dev-1, verified) and
         one published dummy case, inserted if absent; prints their ids.
Run:     .venv/bin/python scripts/seed_caseroom_dev.py

Dev-only. Idempotent — safe to re-run; never touches existing rows.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from webapp.auth.passwords import hash_password  # noqa: E402

DEV_PASSWORD = "caseroom-dev-1"
DEV_USERS = [
    ("a@yale.edu", "Alice Dev"),
    ("b@yale.edu", "Bob Dev"),
    ("c@yale.edu", "Cara Dev"),
]


def main() -> None:
    if not os.environ.get("DATABASE_URL"):
        env = Path(__file__).resolve().parents[1] / ".env"
        for line in env.read_text().splitlines() if env.exists() else []:
            if line.startswith("DATABASE_URL="):
                os.environ["DATABASE_URL"] = line.split("=", 1)[1].strip()

    import psycopg

    with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
        with conn.cursor() as cur:
            pw_hash = hash_password(DEV_PASSWORD)
            for email, name in DEV_USERS:
                cur.execute(
                    "INSERT INTO users (email, password_hash, email_verified_at, display_name)"
                    " VALUES (%s, %s, NOW(), %s) ON CONFLICT (email) DO NOTHING;",
                    (email, pw_hash, name),
                )
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path)"
                " VALUES ('Dev Dummy Case', 'dev dummy case', 'DevSchool', 2026,"
                " 'Technology', 'Profitability', 'Medium', 5.0, 3,"
                " 'output/cases/devschool/dev-dummy-case.pdf')"
                " ON CONFLICT ON CONSTRAINT cases_unique_per_school_year DO NOTHING;"
            )
            cur.execute("SELECT id, email FROM users WHERE email = ANY(%s) ORDER BY id;",
                        ([e for e, _ in DEV_USERS],))
            for uid, email in cur.fetchall():
                print(f"user {uid}: {email}")
            cur.execute("SELECT id FROM cases WHERE case_title = 'Dev Dummy Case';")
            print(f"case {cur.fetchone()[0]}: Dev Dummy Case")


if __name__ == "__main__":
    main()
