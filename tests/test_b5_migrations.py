"""
Purpose: assert migrations 022-024 produced the expected schema and seed, and
         that existing users' school_id backfilled from their email domain.
Inputs:  seeded dev Postgres via tests.test_ws_integration (_DB_URL/_READY).
Outputs: no writes; read-only schema/seed assertions.
Run:     .venv/bin/python -m pytest tests/test_b5_migrations.py -q
"""

from __future__ import annotations

import unittest

import psycopg

from tests.test_ws_integration import _DB_URL, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestB5Migrations(unittest.TestCase):
    def _cols(self, table: str) -> set[str]:
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT column_name FROM information_schema.columns "
                    "WHERE table_name = %s;",
                    (table,),
                )
                return {r[0] for r in cur.fetchall()}

    def test_user_identity_columns_exist(self):
        cols = self._cols("users")
        for c in ("bio", "photo_key", "linkedin_url", "google_sub",
                  "linkedin_sub", "school_id"):
            self.assertIn(c, cols)

    def test_hardcoded_email_check_dropped(self):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT 1 FROM pg_constraint WHERE conname = 'users_email_allowed';")
                self.assertIsNone(cur.fetchone())

    def test_schools_seeded(self):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT domain FROM schools ORDER BY domain;")
                domains = {r[0] for r in cur.fetchall()}
        self.assertTrue({"yale.edu", "umich.edu", "chicagobooth.edu"} <= domains)

    def test_seeded_user_school_backfilled(self):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT s.domain FROM users u JOIN schools s ON s.id = u.school_id "
                    "WHERE u.email = 'a@yale.edu';")
                row = cur.fetchone()
        self.assertIsNotNone(row)
        self.assertEqual(row[0], "yale.edu")

    def test_notification_settings_and_otp_tables_exist(self):
        self.assertIn("proposals", self._cols("notification_settings"))
        self.assertIn("code_hash", self._cols("login_otp_codes"))


if __name__ == "__main__":
    unittest.main()
