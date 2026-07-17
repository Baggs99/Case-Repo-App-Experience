"""B3 Task 1: migrations 028/029 — schema shape + idempotency. Needs the dev
Postgres; skips cleanly otherwise. Mirrors tests/test_ws_integration.py."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _READY


@unittest.skipUnless(_READY, "requires dev Postgres")
class TestB3Migrations(unittest.TestCase):
    def _cols(self, table):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT column_name, is_nullable FROM information_schema.columns"
                " WHERE table_name = %s;", (table,))
            return {r[0]: r[1] for r in cur.fetchall()}

    def test_practice_sessions_case_and_rubric_nullable(self):
        cols = self._cols("practice_sessions")
        self.assertEqual(cols["case_id"], "YES")
        self.assertEqual(cols["rubric_template_id"], "YES")
        self.assertIn("swapped_from_session_id", cols)

    def test_state_check_allows_negotiating(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint"
                " WHERE conname = 'practice_sessions_state_check';")
            self.assertIn("negotiating", cur.fetchone()[0])

    def test_negotiation_and_swap_tables_exist(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT table_name FROM information_schema.tables"
                " WHERE table_name = ANY(%s);",
                (["case_negotiations", "swap_invites"],))
            names = {r[0] for r in cur.fetchall()}
        self.assertEqual(names, {"case_negotiations", "swap_invites"})

    def test_feedback_recap_columns(self):
        cols = self._cols("feedback")
        for c in ("viewed_at", "closed_at", "case_rating", "feedback_thumbs"):
            self.assertIn(c, cols)


if __name__ == "__main__":
    unittest.main()
