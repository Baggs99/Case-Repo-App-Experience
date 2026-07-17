# tests/test_b8_migration.py
"""B8 Task 1: assert migration 034/035 shape on the live dev DB (columns + indexes)."""
from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _READY


@unittest.skipUnless(_READY, "requires dev Postgres")
class TestB8Migration(unittest.TestCase):
    def _cols(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT column_name, data_type, is_nullable FROM information_schema.columns"
                " WHERE table_name = 'drill_attempts';")
            return {r[0]: (r[1], r[2]) for r in cur.fetchall()}

    def _indexes(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT indexname FROM pg_indexes WHERE tablename = 'drill_attempts';")
            return {r[0] for r in cur.fetchall()}

    def test_new_columns_present_and_nullable(self):
        cols = self._cols()
        self.assertIn("score", cols)
        self.assertEqual(cols["score"], ("real", "YES"))
        self.assertIn("duration_ms", cols)
        self.assertEqual(cols["duration_ms"], ("integer", "YES"))
        self.assertIn("set_key", cols)
        self.assertEqual(cols["set_key"], ("text", "YES"))

    def test_rank_indexes_present(self):
        idx = self._indexes()
        self.assertIn("idx_drill_attempts_setkey", idx)
        self.assertIn("idx_drill_attempts_user_setkey", idx)


if __name__ == "__main__":
    unittest.main()
