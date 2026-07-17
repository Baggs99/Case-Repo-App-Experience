"""B7 Task 2: per-user firm tracking repo. Needs seeded dev Postgres."""

from __future__ import annotations

import datetime
import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestUserFirmsRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Enter the app lifespan so the shared connection pool is initialized
        # (repo functions go through webapp.db.get_pool()). Must precede any
        # pool-backed call (firms_repo.list_firms below). Matches test_b7_firms.
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()

        import psycopg
        from webapp.repositories import firms as firms_repo
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.uid = cur.fetchone()[0]
        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (self.uid,))

    def test_track_is_idempotent_and_listable(self):
        from webapp.repositories import user_firms as uf
        row = uf.track(self.uid, self.mck)
        self.assertEqual(row["status"], "tracking")
        uf.track(self.uid, self.mck)  # second track = no-op
        tracked = uf.list_tracked(self.uid)
        self.assertEqual(len(tracked), 1)
        self.assertEqual(tracked[0]["slug"], "mckinsey")
        self.assertTrue(uf.is_tracked(self.uid, self.mck))

    def test_untrack_removes(self):
        from webapp.repositories import user_firms as uf
        uf.track(self.uid, self.mck)
        self.assertEqual(uf.untrack(self.uid, self.mck), 1)
        self.assertFalse(uf.is_tracked(self.uid, self.mck))
        self.assertEqual(uf.untrack(self.uid, self.mck), 0)

    def test_record_result_offer_and_rejected(self):
        from webapp.repositories import user_firms as uf
        uf.track(self.uid, self.mck)
        row = uf.record_result(self.uid, self.mck, "offer")
        self.assertEqual(row["status"], "offer")
        self.assertIsNotNone(row["result_recorded_at"])
        self.assertIsNone(row["snooze_until"])
        row2 = uf.record_result(self.uid, self.mck, "rejected")
        self.assertEqual(row2["status"], "rejected")

    def test_record_result_untracked_returns_none(self):
        from webapp.repositories import user_firms as uf
        self.assertIsNone(uf.record_result(self.uid, self.mck, "offer"))

    def test_mark_waiting_sets_snooze(self):
        from webapp.repositories import user_firms as uf
        uf.track(self.uid, self.mck)
        row = uf.mark_waiting(self.uid, self.mck, days=7)
        self.assertEqual(row["status"], "interviewed")
        self.assertIsNotNone(row["snooze_until"])

    def test_firms_needing_prompt_finds_passed_untouched(self):
        from webapp.repositories import user_firms as uf
        uf.track(self.uid, self.rb)          # Roland Berger deadline = 2026-07-02
        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
        mine = [r for r in rows if r["user_id"] == self.uid and r["firm_id"] == self.rb]
        self.assertEqual(len(mine), 1)
        self.assertIn("Roland", mine[0]["firm_name"])

    def test_snoozed_firm_not_prompted(self):
        from webapp.repositories import user_firms as uf
        uf.track(self.uid, self.rb)
        uf.mark_prompted(self.uid, self.rb,
                         snooze_until=datetime.datetime.now(datetime.timezone.utc)
                         + datetime.timedelta(days=7))
        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
        self.assertFalse([r for r in rows if r["firm_id"] == self.rb])

    def test_non_tracking_status_not_prompted(self):
        from webapp.repositories import user_firms as uf
        uf.track(self.uid, self.rb)
        uf.record_result(self.uid, self.rb, "offer")  # status='offer' → done
        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
        self.assertFalse([r for r in rows if r["firm_id"] == self.rb])


if __name__ == "__main__":
    unittest.main()
