"""
Task 6: JSON auth endpoints under /api/v1 (login, logout, me).

Needs the seeded dev Postgres — skips cleanly otherwise. Uses the same
login/cookie fixture idiom as tests/test_api_v1_devices.py.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

_DEV_PASSWORD = "caseroom-dev-1"


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestApiV1Auth(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls.client = cls._ctx.__enter__()

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def test_login_success_sets_cookie_and_returns_user(self):
        r = self.client.post("/api/v1/auth/login",
                              json={"email": "a@yale.edu", "password": _DEV_PASSWORD})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("user", body)
        self.assertIn("id", body["user"])
        self.assertEqual(body["user"]["email"], "a@yale.edu")
        self.assertEqual(body["user"]["name"], "Alice Dev")
        self.assertIn("case_repo_session", r.cookies)

    def test_me_returns_same_user(self):
        login = self.client.post("/api/v1/auth/login",
                                  json={"email": "a@yale.edu", "password": _DEV_PASSWORD})
        self.assertEqual(login.status_code, 200, login.text)
        user = login.json()["user"]

        r = self.client.get("/api/v1/me")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["id"], user["id"])
        self.assertEqual(body["email"], "a@yale.edu")
        self.assertEqual(body["name"], "Alice Dev")

    def test_login_wrong_password_rejected(self):
        r = self.client.post("/api/v1/auth/login",
                              json={"email": "a@yale.edu", "password": "wrong-password"})
        self.assertEqual(r.status_code, 401)
        self.assertEqual(r.json(), {"detail": "invalid_credentials"})

    def test_logout_destroys_session(self):
        login = self.client.post("/api/v1/auth/login",
                                  json={"email": "a@yale.edu", "password": _DEV_PASSWORD})
        self.assertEqual(login.status_code, 200, login.text)

        r = self.client.post("/api/v1/auth/logout")
        self.assertEqual(r.status_code, 204, r.text)

        r = self.client.get("/api/v1/me")
        self.assertEqual(r.status_code, 401)


if __name__ == "__main__":
    unittest.main()
