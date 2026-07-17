"""
B1 Task 2: env-tunable expiry settings (webapp/settings.py). Pure unit test,
no DB — manipulates os.environ around load_settings().
"""

from __future__ import annotations

import os
import unittest


class TestExpirySettings(unittest.TestCase):
    def setUp(self):
        os.environ.setdefault("DATABASE_URL", "postgresql://localhost/caserepo_bgap_b1")
        self._saved = {k: os.environ.get(k)
                       for k in ("PROPOSAL_NOW_EXPIRY_MIN", "SESSION_MISSED_AFTER_MIN")}
        for k in self._saved:
            os.environ.pop(k, None)

    def tearDown(self):
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def test_defaults(self):
        from webapp.settings import load_settings
        s = load_settings()
        self.assertEqual(s.proposal_now_expiry_min, 120)
        self.assertEqual(s.session_missed_after_min, 60)

    def test_env_override(self):
        from webapp.settings import load_settings
        os.environ["PROPOSAL_NOW_EXPIRY_MIN"] = "45"
        os.environ["SESSION_MISSED_AFTER_MIN"] = "90"
        s = load_settings()
        self.assertEqual(s.proposal_now_expiry_min, 45)
        self.assertEqual(s.session_missed_after_min, 90)


if __name__ == "__main__":
    unittest.main()
