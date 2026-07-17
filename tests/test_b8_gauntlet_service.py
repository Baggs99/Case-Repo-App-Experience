"""B8 Task 5: gauntlet service — scoring/persist round-trip + results payload."""
from __future__ import annotations

import unittest
import uuid
from datetime import date

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx (bootstraps db pool)")
class TestGauntletService(unittest.TestCase):
    ON = date(2026, 7, 17)
    KEY = "2026-07-17"

    @classmethod
    def setUpClass(cls):
        import psycopg
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        cls.email = f"b8-svc-{uuid.uuid4().hex}@yale.edu"
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("INSERT INTO users (email, password_hash, email_verified_at)"
                        " VALUES (%s,'x',NOW()) RETURNING id;", (cls.email,))
            cls.uid = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM drill_attempts WHERE user_id = %s;", (cls.uid,))
            cur.execute("DELETE FROM users WHERE id = %s;", (cls.uid,))
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM drill_attempts WHERE user_id = %s;", (self.uid,))

    def _all_correct_answers(self):
        from webapp import drills
        out = []
        for w in drills.daily_set(self.ON):
            a = w["answer"]
            if a["kind"] == "numeric":
                out.append({"slot": w["slot"], "value": a["value"], "duration_ms": 500})
            else:
                out.append({"slot": w["slot"], "choice_index": a["correct_index"], "duration_ms": 500})
        return out

    def test_submit_all_correct_scores_full(self):
        from webapp import gauntlet
        res = gauntlet.submit(self.uid, self._all_correct_answers(), on=self.ON)
        self.assertEqual(res["score"], 6.0)
        self.assertEqual(res["slots_correct"], 6)
        self.assertEqual(res["slots"], 6)
        self.assertTrue(res["provisional"])
        self.assertEqual(res["set_key"], self.KEY)
        self.assertEqual(res["daily_percentile"], 0.0)   # sole submitter
        self.assertIsNone(res["group"])                  # ephemeral user has no group
        self.assertIn("streak", res)
        self.assertIn("weak_section", res)

    def test_submit_twice_raises_already(self):
        from webapp import gauntlet
        from webapp.repositories import gauntlet as repo
        gauntlet.submit(self.uid, self._all_correct_answers(), on=self.ON)
        with self.assertRaises(repo.AlreadySubmitted):
            gauntlet.submit(self.uid, self._all_correct_answers(), on=self.ON)

    def test_submit_wrong_length_raises_invalid(self):
        from webapp import gauntlet
        with self.assertRaises(gauntlet.InvalidSubmission):
            gauntlet.submit(self.uid, [{"slot": 0, "value": 1}], on=self.ON)

    def test_submit_answer_without_slot_raises_invalid(self):
        from webapp import gauntlet
        bad = [{"value": 1} for _ in range(6)]  # every answer omits `slot`
        with self.assertRaises(gauntlet.InvalidSubmission):
            gauntlet.submit(self.uid, bad, on=self.ON)

    def test_results_for_none_before_submit(self):
        from webapp import gauntlet
        self.assertIsNone(gauntlet.results_for(self.uid, self.KEY))

    def test_trends_shape(self):
        from webapp import gauntlet
        gauntlet.submit(self.uid, self._all_correct_answers(), on=self.ON)
        t = gauntlet.trends(self.uid)
        self.assertIn("daily", t)
        self.assertIn("by_type", t)
        self.assertIn("weakest", t)
        self.assertEqual(t["daily"][-1]["date"], self.KEY)


if __name__ == "__main__":
    unittest.main()
