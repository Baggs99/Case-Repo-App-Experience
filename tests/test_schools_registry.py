"""
Purpose: schools registry lookups + registry-backed validate_email.
Inputs:  seeded dev Postgres via tests.test_ws_integration (_DB_URL/_READY);
         schools seeded by migration 023.
Outputs: no writes; read-only.
Run:     .venv/bin/python -m pytest tests/test_schools_registry.py -q
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestSchoolsRegistry(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()  # opens the pool via app lifespan

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def test_get_school_by_domain(self):
        from webapp.repositories.schools import get_school_by_domain
        s = get_school_by_domain("yale.edu")
        self.assertIsNotNone(s)
        self.assertEqual(s["domain"], "yale.edu")
        self.assertIn("Yale", s["name"])

    def test_domain_is_registered(self):
        from webapp.repositories.schools import domain_is_registered
        self.assertTrue(domain_is_registered("umich.edu"))
        self.assertFalse(domain_is_registered("gmail.com"))

    def test_validate_email_registry_backed(self):
        from webapp.auth.users import validate_email, InvalidEmailDomain
        self.assertEqual(validate_email("Someone@Yale.edu"), "someone@yale.edu")
        with self.assertRaises(InvalidEmailDomain):
            validate_email("user@gmail.com")

    def test_school_id_for_email(self):
        from webapp.auth.users import school_id_for_email
        from webapp.repositories.schools import get_school_by_domain
        self.assertEqual(school_id_for_email("x@umich.edu"),
                         get_school_by_domain("umich.edu")["id"])
        self.assertIsNone(school_id_for_email("x@gmail.com"))


if __name__ == "__main__":
    unittest.main()
