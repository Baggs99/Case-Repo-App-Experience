"""
B2 Task 2: guest CRUD (mint_guest_user, upgrade_guest) + require_guest dep.
Needs the seeded dev Postgres with migration 025 — skips otherwise.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestGuestCrud(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Enter the app context so the DB pool is initialized (init_pool runs in
        # the lifespan). These tests call repo functions directly, not via HTTP.
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
                    cur.execute("DELETE FROM sessions WHERE user_id = ANY(%s);", (self._created,))
                    cur.execute("DELETE FROM users WHERE id = ANY(%s);", (self._created,))

    def _fresh_email(self) -> str:
        import uuid
        return f"upgrade-{uuid.uuid4().hex[:10]}@yale.edu"

    def test_mint_guest_user_creates_flagged_row(self):
        from webapp.auth.guest import mint_guest_user
        g = mint_guest_user()
        self._created.append(g.id)
        self.assertTrue(g.is_guest)
        self.assertIsNone(g.email)
        self.assertFalse(g.is_verified)

    def test_upgrade_guest_converts_in_place(self):
        from webapp.auth.guest import mint_guest_user, upgrade_guest
        g = mint_guest_user()
        self._created.append(g.id)
        email = self._fresh_email()
        upgraded = upgrade_guest(g.id, email, "correct horse battery staple")
        self.assertEqual(upgraded.id, g.id)          # same row → FKs intact
        self.assertFalse(upgraded.is_guest)
        self.assertEqual(upgraded.email, email)

    def test_upgrade_rejects_bad_domain(self):
        from webapp.auth.guest import mint_guest_user, upgrade_guest
        from webapp.auth.users import InvalidEmailDomain
        g = mint_guest_user()
        self._created.append(g.id)
        with self.assertRaises(InvalidEmailDomain):
            upgrade_guest(g.id, "someone@gmail.com", "correct horse battery staple")

    def test_double_upgrade_second_call_conflicts(self):
        from webapp.auth.guest import mint_guest_user, upgrade_guest, GuestUpgradeConflict
        g = mint_guest_user()
        self._created.append(g.id)
        upgrade_guest(g.id, self._fresh_email(), "correct horse battery staple")
        with self.assertRaises(GuestUpgradeConflict):
            upgrade_guest(g.id, self._fresh_email(), "correct horse battery staple")

    def test_upgrade_rejects_taken_email(self):
        from webapp.auth.guest import mint_guest_user, upgrade_guest
        from webapp.auth.users import EmailAlreadyRegistered
        g = mint_guest_user()
        self._created.append(g.id)
        with self.assertRaises(EmailAlreadyRegistered):
            upgrade_guest(g.id, "a@yale.edu", "correct horse battery staple")

    def test_require_guest_dependency(self):
        from fastapi import HTTPException, Request
        from webapp.auth.guest import require_guest
        from webapp.auth.users import User
        from datetime import datetime, timezone

        def _req(user):
            scope = {"type": "http", "headers": [], "method": "GET", "path": "/"}
            r = Request(scope)
            r.state.user = user
            return r

        guest = User(id=1, email=None, email_verified_at=None,
                     created_at=datetime.now(timezone.utc), last_login_at=None, is_guest=True)
        real = User(id=2, email="a@yale.edu", email_verified_at=datetime.now(timezone.utc),
                    created_at=datetime.now(timezone.utc), last_login_at=None, is_guest=False)

        self.assertIs(require_guest(_req(guest)), guest)
        with self.assertRaises(HTTPException) as ctx_real:
            require_guest(_req(real))
        self.assertEqual(ctx_real.exception.status_code, 403)
        with self.assertRaises(HTTPException) as ctx_none:
            require_guest(_req(None))
        self.assertEqual(ctx_none.exception.status_code, 401)


if __name__ == "__main__":
    unittest.main()
