"""
Purpose: profile repository read/update + photo key.
Inputs:  seeded dev Postgres via tests.test_ws_integration (_DB_URL/_READY);
         user a@yale.edu.
Outputs: mutates a@yale.edu's profile fields; restores them in tearDown.
Run:     .venv/bin/python -m pytest tests/test_profile_repo.py -q
"""

from __future__ import annotations

import unittest

import psycopg

from tests.test_ws_integration import _DB_URL, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestProfileRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.uid = cur.fetchone()[0]

    @classmethod
    def tearDownClass(cls):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE users SET bio = NULL, linkedin_url = NULL, "
                    "photo_key = NULL WHERE id = %s;", (cls.uid,))
        cls._ctx.__exit__(None, None, None)

    def test_get_profile_includes_school(self):
        from webapp.repositories.profile import get_profile
        p = get_profile(self.uid)
        self.assertEqual(p["email"], "a@yale.edu")
        self.assertIsNotNone(p["school"])
        self.assertEqual(p["school"]["domain"], "yale.edu")

    def test_update_only_sets_provided_fields(self):
        from webapp.repositories.profile import update_profile, get_profile
        before = get_profile(self.uid)["display_name"]
        p = update_profile(self.uid, display_name=None, bio="Second-year MBA",
                           linkedin_url="https://linkedin.com/in/alice")
        self.assertEqual(p["bio"], "Second-year MBA")
        self.assertEqual(p["linkedin_url"], "https://linkedin.com/in/alice")
        self.assertEqual(p["display_name"], before)  # None left it unchanged

    def test_set_photo_key(self):
        from webapp.repositories.profile import set_photo_key, get_profile
        set_photo_key(self.uid, f"avatars/{self.uid}.png")
        self.assertEqual(get_profile(self.uid)["photo_key"], f"avatars/{self.uid}.png")

    def test_get_profile_unknown_user_none(self):
        from webapp.repositories.profile import get_profile
        self.assertIsNone(get_profile(99999999))


if __name__ == "__main__":
    unittest.main()
