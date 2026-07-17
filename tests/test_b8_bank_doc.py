"""B8 Task 7: the required bank-integration note exists and covers each mandated
section, and the symbols it pins actually resolve in code."""
from __future__ import annotations

import pathlib
import unittest

from webapp.settings import REPO_ROOT

DOC = REPO_ROOT / "docs" / "superpowers" / "notes" / "2026-07-17-drills-bank-integration.md"


class TestBankDoc(unittest.TestCase):
    def test_doc_present_and_covers_required_sections(self):
        self.assertTrue(DOC.exists(), DOC)
        text = DOC.read_text()
        for needle in ("daily_set(", "provider interface", "template selection",
                       "scoring interface", "migration 019", "when the bank lands"):
            self.assertIn(needle, text, f"missing section: {needle}")

    def test_pinned_symbols_resolve(self):
        # The doc pins these as the swap seams; they must exist in code.
        from webapp import drills, gauntlet  # noqa: F401
        from webapp.repositories import gauntlet as grepo  # noqa: F401
        self.assertTrue(hasattr(drills, "daily_set"))
        self.assertTrue(hasattr(drills, "score_slot"))
        self.assertTrue(hasattr(grepo, "record_submission"))


if __name__ == "__main__":
    unittest.main()
