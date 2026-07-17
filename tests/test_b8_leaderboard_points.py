# tests/test_b8_leaderboard_points.py
"""B8 Task 4: gauntlet score feeds activity points; non-gauntlet unchanged."""
from __future__ import annotations

import unittest
import uuid

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx (bootstraps db pool)")
class TestGauntletPoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        cls.email = f"b8-pts-{uuid.uuid4().hex}@yale.edu"
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("INSERT INTO users (email, password_hash, email_verified_at)"
                        " VALUES (%s,'x',NOW()) RETURNING id;", (cls.email,))
            cls.uid = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM users WHERE id = %s;", (cls.uid,))
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM drill_attempts WHERE user_id = %s;", (self.uid,))

    def _points(self):
        # activity_points for this user via the shared CTE.
        import psycopg
        from webapp.repositories.leaderboards import ACTIVITY_POINTS_SQL
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(f"WITH {ACTIVITY_POINTS_SQL}"
                        " SELECT points FROM activity_points WHERE user_id = %s;", (self.uid,))
            row = cur.fetchone()
        return row[0] if row else None

    def test_practice_drill_counts_one_point_each(self):
        import psycopg
        from webapp.repositories.leaderboards import POINTS_PER_DRILL
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            for _ in range(3):
                cur.execute("INSERT INTO drill_attempts (user_id, drill_type, source, correct)"
                            " VALUES (%s,'mental_math','on_device',TRUE);", (self.uid,))
        self.assertEqual(self._points(), 3 * POINTS_PER_DRILL)

    def test_gauntlet_score_adds_weighted_points_not_raw_count(self):
        import psycopg
        from webapp.repositories.leaderboards import POINTS_PER_GAUNTLET_POINT
        # 4 gauntlet rows, 3 correct → run score 3.0; these must NOT count as 4 raw drills.
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            for correct, score in [(True, 1.0), (True, 1.0), (True, 1.0), (False, 0.0)]:
                cur.execute(
                    "INSERT INTO drill_attempts (user_id, drill_type, source, correct, score, set_key)"
                    " VALUES (%s,'mental_math','server',%s,%s,'2026-07-17');",
                    (self.uid, correct, score))
        self.assertEqual(self._points(), int(3.0 * POINTS_PER_GAUNTLET_POINT))

    def test_gauntlet_only_user_is_in_population(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO drill_attempts (user_id, drill_type, source, correct, score, set_key)"
                " VALUES (%s,'mental_math','server',TRUE,1.0,'2026-07-17');", (self.uid,))
        # A user with only gauntlet activity must appear in activity_points.
        self.assertIsNotNone(self._points())


if __name__ == "__main__":
    unittest.main()
