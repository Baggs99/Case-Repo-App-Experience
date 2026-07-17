"""B7 Task 1: firms reference table + read repo. Needs seeded dev Postgres."""

from __future__ import annotations

import datetime
import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestFirmsRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Enter the app lifespan so the shared connection pool is initialized
        # (repo functions go through webapp.db.get_pool()). Matches the harness
        # note in the B7 plan's File Structure section.
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def test_list_firms_has_mbb(self):
        from webapp.repositories import firms as firms_repo
        firms = firms_repo.list_firms()
        slugs = {f["slug"] for f in firms}
        self.assertGreaterEqual(len(firms), 12)
        self.assertTrue({"mckinsey", "bcg", "bain"}.issubset(slugs))
        for f in firms:
            self.assertEqual(set(f), {"id", "name", "slug"})

    def test_get_firm_by_id_and_missing(self):
        from webapp.repositories import firms as firms_repo
        first = firms_repo.list_firms()[0]
        got = firms_repo.get_firm(first["id"])
        self.assertEqual(got["slug"], first["slug"])
        self.assertIsNone(firms_repo.get_firm(-1))

    def test_all_deadlines_are_dates_flagged_estimate(self):
        from webapp.repositories import firms as firms_repo
        deadlines = firms_repo.all_deadlines()
        self.assertGreaterEqual(len(deadlines), 12)
        for d in deadlines:
            self.assertIsInstance(d["deadline_date"], datetime.date)
            self.assertTrue(d["is_estimate"])
            self.assertEqual(d["region"], "US")

    def test_roland_berger_deadline_is_in_the_past_fixture(self):
        # The persona's passed deadline — powers the post-deadline prompt tests.
        from webapp.repositories import firms as firms_repo
        rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")
        rb_dl = [d for d in firms_repo.all_deadlines() if d["firm_id"] == rb["id"]]
        self.assertEqual(rb_dl[0]["deadline_date"], datetime.date(2026, 7, 2))


if __name__ == "__main__":
    unittest.main()
