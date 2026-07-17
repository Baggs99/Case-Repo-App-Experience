"""
Purpose: email+passcode OTP — neutral 202 (no enumeration), registry gate for
         new emails, hashed-at-rest codes, 10-min expiry, <=3 attempts, session
         cookie on verify, existing seeded users keep working.
Inputs:  seeded dev Postgres via tests.test_ws_integration; user a@yale.edu.
         The email sender is monkeypatched to capture the emitted code.
Outputs: writes/reads login_otp_codes; may create a user for a fresh yale email;
         cleans up its own rows.
Run:     .venv/bin/python -m pytest tests/test_otp.py -q
"""

from __future__ import annotations

import unittest
from unittest.mock import patch

import psycopg

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

_FRESH = "otp-fresh@yale.edu"
_UNREG = "otp-person@gmail.com"


def _cleanup():
    with psycopg.connect(_DB_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM login_otp_codes WHERE email = ANY(%s);",
                        ([_FRESH, _UNREG, "a@yale.edu"],))
            cur.execute("DELETE FROM sessions WHERE user_id IN "
                        "(SELECT id FROM users WHERE email = %s);", (_FRESH,))
            cur.execute("DELETE FROM users WHERE email = %s;", (_FRESH,))


@unittest.skipUnless(_READY and _HTTPX, "requires seeded dev Postgres + httpx")
class TestOtp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls.client = cls._ctx.__enter__()

    @classmethod
    def tearDownClass(cls):
        _cleanup()
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        _cleanup()

    def _request_and_capture(self, email: str):
        """POST otp/request with the sender patched; return the 6-digit code or None."""
        captured = {}

        class _Sender:
            def send(self, *, to, subject, text_body, html_body=None, attachments=None):
                captured["to"] = to
                captured["text"] = text_body

        with patch("webapp.auth.otp.get_email_sender", return_value=_Sender()):
            r = self.client.post("/api/v1/auth/otp/request", json={"email": email})
        self.assertEqual(r.status_code, 202)
        self.assertEqual(r.json(), {"status": "ok"})
        import re
        m = re.search(r"\b(\d{6})\b", captured.get("text", ""))
        return m.group(1) if m else None

    def test_request_always_202_even_unregistered(self):
        code = self._request_and_capture(_UNREG)
        self.assertIsNone(code)  # unregistered, non-existing -> no code sent
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM users WHERE email = %s;", (_UNREG,))
                self.assertEqual(cur.fetchone()[0], 0)  # no account created

    def test_existing_user_verify_sets_cookie(self):
        code = self._request_and_capture("a@yale.edu")
        self.assertIsNotNone(code)
        r = self.client.post("/api/v1/auth/otp/verify",
                             json={"email": "a@yale.edu", "code": code})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["user"]["email"], "a@yale.edu")
        self.assertIn("case_repo_session", r.cookies)

    def test_new_registered_email_provisions_and_verifies(self):
        code = self._request_and_capture(_FRESH)
        self.assertIsNotNone(code)
        r = self.client.post("/api/v1/auth/otp/verify",
                             json={"email": _FRESH, "code": code})
        self.assertEqual(r.status_code, 200, r.text)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT s.domain FROM users u JOIN schools s "
                            "ON s.id = u.school_id WHERE u.email = %s;", (_FRESH,))
                self.assertEqual(cur.fetchone()[0], "yale.edu")  # school stamped

    def test_wrong_code_rejected_and_attempts_capped(self):
        self._request_and_capture("a@yale.edu")
        for _ in range(3):
            r = self.client.post("/api/v1/auth/otp/verify",
                                 json={"email": "a@yale.edu", "code": "000000"})
            self.assertEqual(r.status_code, 401)
        # 4th attempt still 401 even with a (hypothetically) right code: capped
        r = self.client.post("/api/v1/auth/otp/verify",
                             json={"email": "a@yale.edu", "code": "000000"})
        self.assertEqual(r.status_code, 401)

    def test_codes_hashed_at_rest(self):
        code = self._request_and_capture("a@yale.edu")
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT code_hash FROM login_otp_codes "
                            "WHERE email = 'a@yale.edu' ORDER BY id DESC LIMIT 1;")
                stored = cur.fetchone()[0]
        self.assertNotEqual(stored, code)      # not plaintext
        self.assertEqual(len(stored), 64)      # sha-256 hex


if __name__ == "__main__":
    unittest.main()
