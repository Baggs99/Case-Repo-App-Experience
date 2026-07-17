"""
Purpose: OAuth browser routes — 503 when unconfigured; authorize redirect with
         state cookie when configured; callback upserts on sub and sets a
         session; and the school gate rejects an unregistered OAuth email. All
         token exchange + JWKS are mocked (no live creds, no network).
Inputs:  seeded dev Postgres via tests.test_ws_integration.
Outputs: may create/lookup users by google_sub; cleans up.
Run:     .venv/bin/python -m pytest tests/test_oauth_routes.py -q
"""

from __future__ import annotations

import unittest
from unittest.mock import patch

import psycopg

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

_NEW_YALE = "oauth-new@yale.edu"
_UNREG = "oauth-person@gmail.com"


def _cleanup():
    with psycopg.connect(_DB_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE users SET google_sub = NULL WHERE email = 'a@yale.edu';")
            cur.execute("DELETE FROM sessions WHERE user_id IN "
                        "(SELECT id FROM users WHERE email = %s);", (_NEW_YALE,))
            cur.execute("DELETE FROM users WHERE email = ANY(%s);", ([_NEW_YALE, _UNREG],))


@unittest.skipUnless(_READY and _HTTPX, "requires seeded dev Postgres + httpx")
class TestOAuthRoutes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls.app = app
        cls._ctx = TestClient(app)
        cls.client = cls._ctx.__enter__()

    @classmethod
    def tearDownClass(cls):
        _cleanup()
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        _cleanup()

    def test_start_503_when_unconfigured(self):
        with patch.dict("os.environ", {}, clear=False):
            import os
            os.environ.pop("GOOGLE_CLIENT_ID", None)
            os.environ.pop("GOOGLE_CLIENT_SECRET", None)
            r = self.client.get("/auth/google", follow_redirects=False)
        self.assertEqual(r.status_code, 503)

    def test_start_redirects_with_state_cookie_when_configured(self):
        import os
        with patch.dict(os.environ, {"GOOGLE_CLIENT_ID": "test-client-id",
                                     "GOOGLE_CLIENT_SECRET": "test-secret",
                                     "WEBAPP_SESSION_SECRET": "test-state-secret"}):
            r = self.client.get("/auth/google", follow_redirects=False)
        self.assertIn(r.status_code, (302, 307))
        self.assertIn("accounts.google.com", r.headers["location"])
        self.assertIn("oauth_state_google", "".join(r.headers.get_list("set-cookie")))

    def test_start_503_when_creds_present_but_secret_missing(self):
        import os
        env = {"GOOGLE_CLIENT_ID": "test-client-id", "GOOGLE_CLIENT_SECRET": "test-secret"}
        with patch.dict(os.environ, env):
            os.environ.pop("WEBAPP_SESSION_SECRET", None)
            r = self.client.get("/auth/google", follow_redirects=False)
        self.assertEqual(r.status_code, 503)

    def _drive_callback(self, *, email, sub, seed_client, verified=True, picture=None):
        """Run start (to set the state cookie) then callback with mocked
        exchange + jwks + verify. No live creds, no network."""
        import os
        from webapp.auth import oauth

        async def _fake_exchange(provider, **kw):
            return {"id_token": "fake.jwt.token"}

        async def _fake_jwks(provider):
            return {"keys": []}

        def _fake_verify(provider, id_token, jwks, *, client_id, nonce=None):
            return {"sub": sub, "email": email, "email_verified": verified,
                    "name": "OAuth User", "picture": picture, "nonce": nonce}

        env = {"GOOGLE_CLIENT_ID": "test-client-id",
               "GOOGLE_CLIENT_SECRET": "test-secret",
               "WEBAPP_SESSION_SECRET": "test-state-secret"}
        with patch.dict(os.environ, env):
            start = seed_client.get("/auth/google", follow_redirects=False)
            # extract state from the redirect Location
            from urllib.parse import urlparse, parse_qs
            state = parse_qs(urlparse(start.headers["location"]).query)["state"][0]
            with patch.object(oauth, "exchange_code", _fake_exchange), \
                 patch.object(oauth, "fetch_jwks", _fake_jwks), \
                 patch.object(oauth, "verify_id_token", _fake_verify):
                return seed_client.get(
                    f"/auth/google/callback?code=abc&state={state}",
                    follow_redirects=False)

    def test_callback_links_existing_user_by_email_and_sets_session(self):
        from fastapi.testclient import TestClient
        c = TestClient(self.app)
        r = self._drive_callback(email="a@yale.edu", sub="G-existing", seed_client=c)
        self.assertIn(r.status_code, (302, 307))
        self.assertIn("case_repo_session",
                      "".join(r.headers.get_list("set-cookie")))
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT google_sub FROM users WHERE email = 'a@yale.edu';")
                self.assertEqual(cur.fetchone()[0], "G-existing")

    def test_callback_creates_new_registered_school_user(self):
        from fastapi.testclient import TestClient
        c = TestClient(self.app)
        r = self._drive_callback(email=_NEW_YALE, sub="G-new", seed_client=c)
        self.assertIn(r.status_code, (302, 307))
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT s.domain FROM users u JOIN schools s "
                            "ON s.id = u.school_id WHERE u.email = %s;", (_NEW_YALE,))
                self.assertEqual(cur.fetchone()[0], "yale.edu")

    def test_callback_school_gate_rejects_unregistered_email(self):
        from fastapi.testclient import TestClient
        c = TestClient(self.app)
        r = self._drive_callback(email=_UNREG, sub="G-unreg", seed_client=c)
        self.assertIn(r.status_code, (302, 307))
        self.assertIn("needs_signup", r.headers["location"])
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM users WHERE email = %s;", (_UNREG,))
                self.assertEqual(cur.fetchone()[0], 0)  # no account created

    def test_callback_rejects_unverified_email(self):
        # SECURITY: an unverified provider email must NOT link to an existing
        # account or create one — otherwise account takeover.
        from fastapi.testclient import TestClient
        c = TestClient(self.app)
        r = self._drive_callback(email="a@yale.edu", sub="G-unverified",
                                 seed_client=c, verified=False)
        self.assertIn(r.status_code, (302, 307))
        self.assertIn("needs_signup", r.headers["location"])
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT google_sub FROM users WHERE email = 'a@yale.edu';")
                self.assertIsNone(cur.fetchone()[0])  # existing account NOT linked

    def test_callback_imports_avatar_on_first_link(self):
        import webapp.routes.auth_oauth as ao
        from fastapi.testclient import TestClient

        class _FakeStorage:
            def write(self, key, data, *, content_type):
                pass
            def url(self, key):
                return "/files/" + key

        c = TestClient(self.app)
        png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 40
        with patch.object(ao, "_download_avatar", return_value=(png, "image/png")), \
             patch.object(ao, "get_storage", lambda: _FakeStorage()):
            r = self._drive_callback(email=_NEW_YALE, sub="G-pic", seed_client=c,
                                     picture="https://cdn.example/pic.png")
        self.assertIn(r.status_code, (302, 307))
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT photo_key FROM users WHERE email = %s;", (_NEW_YALE,))
                key = cur.fetchone()[0]
        self.assertIsNotNone(key)             # avatar imported on first link
        self.assertTrue(key.endswith(".png"))


if __name__ == "__main__":
    unittest.main()
