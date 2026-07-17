"""
Tests for registry-backed school-email validation (OD-B5-2). The schools
registry (migration 023) is the allowlist; validate_email now hits the DB.
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestEmailDomains(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def test_yale_edu_allowed(self):
        from webapp.auth.users import validate_email
        self.assertEqual(validate_email("student@yale.edu"), "student@yale.edu")

    def test_umich_edu_allowed(self):
        from webapp.auth.users import validate_email
        self.assertEqual(validate_email("rossmba@umich.edu"), "rossmba@umich.edu")

    def test_booth_domain_now_registered(self):
        # Registry model: chicagobooth.edu is a full school domain now.
        from webapp.auth.users import validate_email
        self.assertEqual(validate_email("anyone@chicagobooth.edu"),
                         "anyone@chicagobooth.edu")

    def test_unregistered_domain_rejected(self):
        from webapp.auth.users import InvalidEmailDomain, validate_email
        with self.assertRaises(InvalidEmailDomain):
            validate_email("user@gmail.com")

    def test_malformed_rejected(self):
        from webapp.auth.users import InvalidEmailDomain, validate_email
        with self.assertRaises(InvalidEmailDomain):
            validate_email("not-an-email")


if __name__ == "__main__":
    unittest.main()
