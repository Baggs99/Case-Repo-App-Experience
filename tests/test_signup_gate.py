"""
Purpose: school-email sign-up gate (OD-B5-2) — registered domain issues a link
         via the existing verification infra; unregistered domain is a neutral
         no-op; always 202 (no enumeration).
Inputs:  seeded dev Postgres via tests.test_ws_integration.
Outputs: may create a provisional user + a verification token for a fresh yale
         email; cleans up.
Run:     .venv/bin/python -m pytest tests/test_signup_gate.py -q
"""

from __future__ import annotations

import unittest
from unittest.mock import patch

import psycopg

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

_FRESH = "signup-fresh@umich.edu"
_UNREG = "signup-person@gmail.com"


def _cleanup():
    with psycopg.connect(_DB_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM email_verification_tokens WHERE user_id IN "
                        "(SELECT id FROM users WHERE email = ANY(%s));",
                        ([_FRESH, _UNREG],))
            cur.execute("DELETE FROM users WHERE email = ANY(%s);", ([_FRESH, _UNREG],))


@unittest.skipUnless(_READY and _HTTPX, "requires seeded dev Postgres + httpx")
class TestSignupGate(unittest.TestCase):
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

    def _post(self, email):
        class _Sender:
            sent = []
            def send(self, *, to, subject, text_body, html_body=None, attachments=None):
                _Sender.sent.append(to)
        _Sender.sent = []
        with patch("webapp.routes.onboarding.get_email_sender", return_value=_Sender()):
            r = self.client.post("/api/v1/signup/request", json={"email": email})
        return r, _Sender.sent

    def test_registered_domain_issues_link(self):
        r, sent = self._post(_FRESH)
        self.assertEqual(r.status_code, 202)
        self.assertEqual(r.json(), {"status": "ok"})
        self.assertIn(_FRESH, sent)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id, school_id FROM users WHERE email = %s;", (_FRESH,))
                row = cur.fetchone()
                self.assertIsNotNone(row)
                self.assertIsNotNone(row[1])  # school stamped
                cur.execute("SELECT COUNT(*) FROM email_verification_tokens "
                            "WHERE user_id = %s;", (row[0],))
                self.assertEqual(cur.fetchone()[0], 1)  # token issued via existing infra

    def test_unregistered_domain_noop_but_202(self):
        r, sent = self._post(_UNREG)
        self.assertEqual(r.status_code, 202)
        self.assertEqual(r.json(), {"status": "ok"})
        self.assertEqual(sent, [])  # nothing sent
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM users WHERE email = %s;", (_UNREG,))
                self.assertEqual(cur.fetchone()[0], 0)  # no account


if __name__ == "__main__":
    unittest.main()
