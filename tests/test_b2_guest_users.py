"""
B2 Task 1: migration 025 (is_guest, nullable email/password, guest-aware
domain CHECK) + User.is_guest plumbing. Needs the seeded dev Postgres with
migration 025 applied — skips cleanly otherwise.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestGuestUsersSchema(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Enter the app context so the DB pool is initialized (get_user_by_id
        # uses the pool). Raw psycopg inserts open their own connections.
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        self._created: list[int] = []

    def tearDown(self):
        import psycopg
        if self._created:
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("DELETE FROM users WHERE id = ANY(%s);", (self._created,))

    def test_guest_row_with_null_email_and_password_is_allowed(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO users (email, password_hash, is_guest, display_name)"
                    " VALUES (NULL, NULL, TRUE, 'Guest') RETURNING id, is_guest;")
                row = cur.fetchone()
        self._created.append(row[0])
        self.assertTrue(row[1])

    def test_non_guest_with_null_email_is_rejected(self):
        import psycopg
        with self.assertRaises(psycopg.errors.CheckViolation):
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO users (email, password_hash, is_guest)"
                        " VALUES (NULL, 'x', FALSE) RETURNING id;")

    def test_non_guest_with_bad_domain_still_rejected(self):
        import psycopg
        with self.assertRaises(psycopg.errors.CheckViolation):
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO users (email, password_hash, is_guest)"
                        " VALUES ('nope@gmail.com', 'x', FALSE) RETURNING id;")

    def test_user_dataclass_exposes_is_guest(self):
        import psycopg
        from webapp.auth.users import get_user_by_id
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO users (email, password_hash, is_guest, display_name)"
                    " VALUES (NULL, NULL, TRUE, 'Guest') RETURNING id;")
                gid = cur.fetchone()[0]
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                aid = cur.fetchone()[0]
        self._created.append(gid)
        self.assertTrue(get_user_by_id(gid).is_guest)
        self.assertFalse(get_user_by_id(aid).is_guest)


if __name__ == "__main__":
    unittest.main()
