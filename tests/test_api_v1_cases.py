"""
Task 7: JSON case browse endpoints under /api/v1 (list + detail).

Needs the seeded dev Postgres — skips cleanly otherwise. Uses the same
login/cookie fixture idiom as tests/test_api_v1_devices.py.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestApiV1Cases(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.client = cls._ctx.__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = %s;", ("a@yale.edu",))
                cls.uid = cur.fetchone()[0]
                cur.execute("SELECT id FROM cases WHERE case_title = 'Dev Dummy Case';")
                cls.dummy_case_id = cur.fetchone()[0]
                cur.execute("SELECT COALESCE(MAX(id), 0) FROM cases;")
                cls.max_case_id = cur.fetchone()[0]

        session = create_session(cls.uid, user_agent="p7-test", ip_address=None)
        cls.client.cookies.set(SESSION_COOKIE_NAME, session.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def test_list_returns_seeded_cases_with_real_keys(self):
        r = self.client.get("/api/v1/cases")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("cases", body)
        self.assertIn("total", body)
        self.assertIsInstance(body["total"], int)
        self.assertGreaterEqual(len(body["cases"]), 1)

        item = body["cases"][0]
        self.assertIn("case_title", item)
        self.assertIn("id", item)
        self.assertIn("source_school", item)
        self.assertIn("industry", item)
        self.assertIn("case_type", item)
        self.assertIn("difficulty", item)
        self.assertNotIn("pdf_path", item)
        self.assertNotIn("title", item)

    def test_q_filter_narrows_results(self):
        unfiltered = self.client.get("/api/v1/cases")
        self.assertEqual(unfiltered.status_code, 200, unfiltered.text)
        total_all = unfiltered.json()["total"]

        # 'Dev Dummy Case' is guaranteed present by scripts/seed_caseroom_dev.py
        # and its exact title is not a substring of any other seeded case.
        r = self.client.get("/api/v1/cases", params={"q": "Dev Dummy"})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["total"], 1)
        self.assertEqual(len(body["cases"]), 1)
        self.assertEqual(body["cases"][0]["id"], self.dummy_case_id)
        self.assertEqual(body["cases"][0]["case_title"], "Dev Dummy Case")

        if total_all > 1:
            self.assertLess(body["total"], total_all)

    def test_detail_has_preview_urls_and_pdf_url(self):
        r = self.client.get(f"/api/v1/cases/{self.dummy_case_id}")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["id"], self.dummy_case_id)
        self.assertEqual(body["case_title"], "Dev Dummy Case")
        self.assertIsInstance(body["preview_urls"], list)
        self.assertIsInstance(body["pdf_url"], str)
        self.assertTrue(body["pdf_url"])
        self.assertNotIn("pdf_path", body)
        # Internal/admin-only columns from get_case_by_id must not leak into
        # the locked iOS API contract.
        for internal_field in (
            "normalized_title", "interviewer_led", "preview_public_slug",
            "is_duplicate_case", "unique_case_count_eligible",
            "created_at", "updated_at",
        ):
            self.assertNotIn(internal_field, body)

    def test_detail_nonexistent_id_returns_404(self):
        r = self.client.get(f"/api/v1/cases/{self.max_case_id + 999999}")
        self.assertEqual(r.status_code, 404, r.text)

    def test_unauthenticated_list_returns_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app

        r = TestClient(app).get("/api/v1/cases")
        self.assertEqual(r.status_code, 401)

    def test_unauthenticated_detail_returns_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app

        r = TestClient(app).get(f"/api/v1/cases/{self.dummy_case_id}")
        self.assertEqual(r.status_code, 401)


if __name__ == "__main__":
    unittest.main()
