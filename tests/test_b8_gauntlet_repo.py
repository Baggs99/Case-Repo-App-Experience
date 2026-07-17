# tests/test_b8_gauntlet_repo.py
"""B8 Task 3: gauntlet repo — one-per-day persistence, percentile, trends.
Uses two ephemeral @yale.edu users so exact counts/percentiles are hermetic."""
from __future__ import annotations

import unittest
import uuid

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx (bootstraps db pool)")
class TestGauntletRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        cls.u1_email = f"b8-g1-{uuid.uuid4().hex}@yale.edu"
        cls.u2_email = f"b8-g2-{uuid.uuid4().hex}@yale.edu"
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("INSERT INTO users (email, password_hash, email_verified_at)"
                        " VALUES (%s,'x',NOW()) RETURNING id;", (cls.u1_email,))
            cls.u1 = cur.fetchone()[0]
            cur.execute("INSERT INTO users (email, password_hash, email_verified_at)"
                        " VALUES (%s,'x',NOW()) RETURNING id;", (cls.u2_email,))
            cls.u2 = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM users WHERE id = ANY(%s);", ([cls.u1, cls.u2],))
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM drill_attempts WHERE user_id = ANY(%s);",
                        ([self.u1, self.u2],))

    def _slots(self, corrects):
        return [{"drill_type": "mental_math", "drill_key": f"k{i}",
                 "correct": c, "score": 1.0 if c else 0.0, "duration_ms": 1000}
                for i, c in enumerate(corrects)]

    def test_record_and_has_submitted(self):
        from webapp.repositories import gauntlet as repo
        self.assertFalse(repo.has_submitted(self.u1, "2026-07-17"))
        repo.record_submission(self.u1, "2026-07-17", self._slots([True, True, False]))
        self.assertTrue(repo.has_submitted(self.u1, "2026-07-17"))

    def test_second_submission_same_day_raises(self):
        from webapp.repositories import gauntlet as repo
        repo.record_submission(self.u1, "2026-07-17", self._slots([True]))
        with self.assertRaises(repo.AlreadySubmitted):
            repo.record_submission(self.u1, "2026-07-17", self._slots([True]))

    def test_submission_summary(self):
        from webapp.repositories import gauntlet as repo
        repo.record_submission(self.u1, "2026-07-17", self._slots([True, True, True, False, False, False]))
        s = repo.submission_summary(self.u1, "2026-07-17")
        self.assertEqual(s["score"], 3.0)
        self.assertEqual(s["slots_correct"], 3)
        self.assertEqual(s["slots"], 6)
        self.assertIsNone(repo.submission_summary(self.u2, "2026-07-17"))

    def test_daily_percentile_two_submitters(self):
        from webapp.repositories import gauntlet as repo
        repo.record_submission(self.u1, "2026-07-17", self._slots([True, True, True]))   # score 3
        repo.record_submission(self.u2, "2026-07-17", self._slots([True, False, False]))  # score 1
        top = repo.daily_percentile(self.u1, "2026-07-17")
        low = repo.daily_percentile(self.u2, "2026-07-17")
        self.assertEqual(top, 100.0)
        self.assertEqual(low, 0.0)

    def test_daily_scores_and_per_type(self):
        from webapp.repositories import gauntlet as repo
        repo.record_submission(self.u1, "2026-07-17",
                               [{"drill_type": "mental_math", "drill_key": "a", "correct": True,
                                 "score": 1.0, "duration_ms": 1},
                                {"drill_type": "market_sizing", "drill_key": "b", "correct": False,
                                 "score": 0.0, "duration_ms": 1}])
        scores = repo.daily_scores(self.u1)
        self.assertEqual(scores[-1]["date"], "2026-07-17")
        self.assertEqual(scores[-1]["score"], 1.0)
        by_type = {r["drill_type"]: r for r in repo.per_type_accuracy(self.u1)}
        self.assertEqual(by_type["mental_math"]["accuracy"], 1.0)
        self.assertEqual(by_type["market_sizing"]["accuracy"], 0.0)
        self.assertEqual(repo.weakest_type(self.u1), "market_sizing")

    def test_guest_excluded_from_percentile(self):
        import psycopg
        from webapp.repositories import gauntlet as repo
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("UPDATE users SET is_guest = TRUE WHERE id = %s;", (self.u2,))
        try:
            repo.record_submission(self.u1, "2026-07-17", self._slots([True, True]))   # score 2
            repo.record_submission(self.u2, "2026-07-17", self._slots([True, True, True]))  # guest, score 3
            # Only u1 counts → sole non-guest submitter → percent_rank 0.0.
            self.assertEqual(repo.daily_percentile(self.u1, "2026-07-17"), 0.0)
        finally:
            with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
                cur.execute("UPDATE users SET is_guest = FALSE WHERE id = %s;", (self.u2,))


if __name__ == "__main__":
    unittest.main()
