# tests/test_b8_gauntlet_gen.py
"""B8 Task 2: pure gauntlet generation + scoring (no DB)."""
from __future__ import annotations

import unittest
from datetime import date

from webapp import drills


class TestDailySet(unittest.TestCase):
    def test_six_slots_indexed(self):
        s = drills.daily_set(date(2026, 7, 17))
        self.assertEqual(len(s), drills.GAUNTLET_SLOTS)
        self.assertEqual(drills.GAUNTLET_SLOTS, 6)
        self.assertEqual([d["slot"] for d in s], [0, 1, 2, 3, 4, 5])

    def test_two_of_each_type(self):
        s = drills.daily_set(date(2026, 7, 17))
        counts = {}
        for d in s:
            counts[d["drill_type"]] = counts.get(d["drill_type"], 0) + 1
        self.assertEqual(sorted(counts), sorted(drills._TYPES))
        self.assertTrue(all(v == 2 for v in counts.values()), counts)

    def test_date_seeded_same_for_everyone_and_stable(self):
        a = drills.daily_set(date(2026, 7, 17))
        b = drills.daily_set(date(2026, 7, 17))
        self.assertEqual([d["prompt"] for d in a], [d["prompt"] for d in b])
        c = drills.daily_set(date(2026, 7, 18))
        self.assertNotEqual([d["prompt"] for d in a], [d["prompt"] for d in c])

    def test_public_drill_redacts_answer(self):
        wire = drills.daily_set(date(2026, 7, 17))[0]
        pub = drills.public_drill(wire)
        self.assertNotIn("answer", pub)
        self.assertNotIn("explanation", pub)
        for k in ("slot", "drill_type", "key", "prompt", "numbers"):
            self.assertIn(k, pub)


class TestScoreSlot(unittest.TestCase):
    def test_numeric_pct_tolerance(self):
        wire = {"answer": {"kind": "numeric", "value": 100.0, "tolerance_pct": 5.0}}
        self.assertTrue(drills.score_slot(wire, value=103.0))
        self.assertFalse(drills.score_slot(wire, value=120.0))
        self.assertFalse(drills.score_slot(wire, value=None))

    def test_numeric_factor_tolerance(self):
        wire = {"answer": {"kind": "numeric", "value": 1000.0, "tolerance_factor": 2.0}}
        self.assertTrue(drills.score_slot(wire, value=1500.0))   # within /2..*2
        self.assertTrue(drills.score_slot(wire, value=600.0))
        self.assertFalse(drills.score_slot(wire, value=2500.0))

    def test_choice(self):
        wire = {"answer": {"kind": "choice", "correct_index": 2}}
        self.assertTrue(drills.score_slot(wire, choice_index=2))
        self.assertFalse(drills.score_slot(wire, choice_index=0))
        self.assertFalse(drills.score_slot(wire, choice_index=None))

    def test_real_generated_slot_scores_its_own_answer(self):
        for wire in drills.daily_set(date(2026, 7, 17)):
            ans = wire["answer"]
            if ans["kind"] == "numeric":
                self.assertTrue(drills.score_slot(wire, value=ans["value"]))
            else:
                self.assertTrue(drills.score_slot(wire, choice_index=ans["correct_index"]))


if __name__ == "__main__":
    unittest.main()
