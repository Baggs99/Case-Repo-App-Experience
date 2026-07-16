"""
Purpose: Verify the P4 drill template bank + deterministic generator — bank
         integrity, per-op answer correctness, recall-shuffle tracking, market
         sizing, and the two GET /api/v1/drills endpoints.
Inputs:  webapp/drill_templates.json + webapp/drills.py (pure); seeded dev
         Postgres via tests.test_ws_integration (_DB_URL/_READY/_HTTPX) and
         a@yale.edu for the two DB-gated endpoint tests.
Outputs: no files, no DB writes (endpoint tests only read).
Run:     .venv/bin/python -m pytest tests/test_drills_bank.py -q
"""

from __future__ import annotations

import random
import re
import unittest
from datetime import date
from pathlib import Path

from webapp import drills
from webapp.drills import _BANK, _draw_params, daily_drill, generate_drill

_NUM_RE = re.compile(r"\d+(?:\.\d+)?")
_REPO_ROOT = Path(__file__).resolve().parents[1]

_REQUIRED_OPS = {
    "pct_change", "growth_compound", "breakeven_units", "margin_pct",
    "markup_price", "market_share_revenue", "per_capita", "weighted_avg_2",
    "cagr_2yr_approx", "payback_months",
}


def _templates_of(drill_type):
    return [t for t in _BANK["templates"] if t["drill_type"] == drill_type]


def _expected_answer(op, p):
    """Independent recomputation of each mental_math answer — deliberately does
    NOT call drills._OPS. Own arithmetic, per the correctness contract."""
    if op == "pct_change":
        return (p["b"] - p["a"]) / p["a"] * 100
    if op == "growth_compound":
        return p["a"] * (1 + p["g"] / 100) * (1 + p["g"] / 100)
    if op == "breakeven_units":
        return p["fixed"] / (p["price"] - p["vc"])
    if op == "margin_pct":
        return (p["rev"] - p["cost"]) / p["rev"] * 100
    if op == "markup_price":
        return p["cost"] * (1 + p["markup"] / 100)
    if op == "market_share_revenue":
        return p["market"] * p["share"] / 100
    if op == "per_capita":
        return p["total"] / p["pop"]
    if op == "weighted_avg_2":
        return (p["v1"] * p["w1"] + p["v2"] * p["w2"]) / (p["w1"] + p["w2"])
    if op == "cagr_2yr_approx":
        return (p["end"] - p["start"]) / p["start"] / 2 * 100
    if op == "payback_months":
        return p["invest"] / p["monthly"]
    raise AssertionError(f"unhandled op {op!r}")


class TestFixtureParity(unittest.TestCase):
    """The iOS bundled fixture must stay byte-identical to the backend bank so
    the on-device engine and the server draw the same drills. Nothing else
    guards the copy — a regenerate that skips it would drift silently."""

    def test_ios_fixture_matches_backend_bank(self):
        backend = _REPO_ROOT / "webapp" / "drill_templates.json"
        ios = _REPO_ROOT / "ios" / "CaseRoomTests" / "Fixtures" / "drill_templates.json"
        self.assertEqual(
            backend.read_bytes(),
            ios.read_bytes(),
            "iOS ios/CaseRoomTests/Fixtures/drill_templates.json drifted from"
            " webapp/drill_templates.json — regenerate the iOS fixture copy.",
        )


class TestDrillBankIntegrity(unittest.TestCase):
    def test_version_and_min_templates(self):
        self.assertEqual(_BANK["version"], 1)
        self.assertGreaterEqual(len(_BANK["templates"]), 30)

    def test_per_type_minimums(self):
        self.assertGreaterEqual(len(_templates_of("mental_math")), 10)
        self.assertGreaterEqual(len(_templates_of("market_sizing")), 8)
        self.assertGreaterEqual(len(_templates_of("framework_recall")), 12)

    def test_all_required_ops_present(self):
        ops = {t["op"] for t in _templates_of("mental_math")}
        self.assertTrue(_REQUIRED_OPS.issubset(ops),
                        f"missing ops: {_REQUIRED_OPS - ops}")

    def test_keys_unique(self):
        keys = [t["key"] for t in _BANK["templates"]]
        self.assertEqual(len(keys), len(set(keys)))

    def test_mental_math_fields_valid(self):
        for t in _templates_of("mental_math"):
            self.assertIn(t["op"], drills._OPS, t["key"])
            self.assertIsInstance(t["question"], str)
            self.assertIsInstance(t["answer_format"], str)
            self.assertIsInstance(t["tolerance_pct"], (int, float))
            self.assertIsInstance(t["params"], dict)
            self.assertTrue(t["params"], t["key"])
            for name, spec in t["params"].items():
                lo, hi, step = spec
                self.assertLessEqual(lo, hi, f"{t['key']}:{name}")
                self.assertGreaterEqual(step, 1, f"{t['key']}:{name}")

    def test_market_sizing_fields_valid(self):
        for t in _templates_of("market_sizing"):
            self.assertIsInstance(t["question"], str)
            self.assertGreater(t["reference_per_unit"], 0, t["key"])
            self.assertIn(t["unit_param"], t["params"], t["key"])
            self.assertGreater(t["tolerance_factor"], 0, t["key"])
            self.assertIn("explanation", t, t["key"])

    def test_framework_recall_fields_valid(self):
        for t in _templates_of("framework_recall"):
            self.assertIsInstance(t["question"], str)
            self.assertIsInstance(t["choices"], list)
            self.assertGreaterEqual(len(t["choices"]), 4, t["key"])
            self.assertEqual(len(t["choices"]), len(set(t["choices"])), t["key"])
            self.assertTrue(0 <= t["correct_index"] < len(t["choices"]), t["key"])
            self.assertIn("explanation", t, t["key"])


class TestGeneratorDeterminism(unittest.TestCase):
    def test_same_seed_identical(self):
        for t in _BANK["templates"]:
            self.assertEqual(generate_drill(t, 42), generate_drill(t, 42), t["key"])

    def test_different_seed_varies_params(self):
        t = next(x for x in _templates_of("mental_math") if x["op"] == "pct_change")
        seen = {tuple(generate_drill(t, s)["numbers"]) for s in range(25)}
        self.assertGreaterEqual(len(seen), 2)

    def test_wire_shape(self):
        for dtype in ("mental_math", "market_sizing", "framework_recall"):
            d = generate_drill(_templates_of(dtype)[0], 7)
            for key in ("key", "drill_type", "prompt", "answer", "explanation", "numbers"):
                self.assertIn(key, d, dtype)
            self.assertIsInstance(d["numbers"], list)
            if dtype == "framework_recall":
                self.assertEqual(d["answer"]["kind"], "choice")
                self.assertIn("choices", d)
                self.assertIn("correct_index", d["answer"])
            elif dtype == "market_sizing":
                self.assertEqual(d["answer"]["kind"], "numeric")
                self.assertIn("tolerance_factor", d["answer"])
            else:
                self.assertEqual(d["answer"]["kind"], "numeric")
                self.assertIn("tolerance_pct", d["answer"])


class TestAnswerCorrectness(unittest.TestCase):
    def test_mental_math_answers_recomputed_independently(self):
        for t in _templates_of("mental_math"):
            op = t["op"]
            for seed in range(25):
                p = _draw_params(t["params"], random.Random(seed))
                expected = _expected_answer(op, p)
                got = generate_drill(t, seed)["answer"]["value"]
                self.assertAlmostEqual(got, expected, places=6,
                                       msg=f"{t['key']} seed={seed} params={p}")

    def test_market_sizing_answer_is_reference_times_param(self):
        for t in _templates_of("market_sizing"):
            for seed in range(25):
                p = _draw_params(t["params"], random.Random(seed))
                expected = t["reference_per_unit"] * p[t["unit_param"]]
                d = generate_drill(t, seed)
                self.assertAlmostEqual(d["answer"]["value"], float(expected), places=6,
                                       msg=f"{t['key']} seed={seed}")
                # numbers = every literal rendered into the prompt.
                self.assertEqual(d["numbers"], _NUM_RE.findall(d["prompt"]))
                self.assertIn(str(p[t["unit_param"]]), d["numbers"])

    def test_recall_shuffle_keeps_correct_answer(self):
        for t in _templates_of("framework_recall"):
            original_correct = t["choices"][t["correct_index"]]
            for seed in range(25):
                d = generate_drill(t, seed)
                idx = d["answer"]["correct_index"]
                self.assertEqual(d["choices"][idx], original_correct,
                                 f"{t['key']} seed={seed}")
                self.assertEqual(set(d["choices"]), set(t["choices"]), t["key"])

    def test_numbers_equal_prompt_literals_all_types(self):
        for t in _BANK["templates"]:
            for seed in range(5):
                d = generate_drill(t, seed)
                self.assertEqual(d["numbers"], _NUM_RE.findall(d["prompt"]), t["key"])


class TestDailyDrill(unittest.TestCase):
    def test_same_user_and_date_identical(self):
        on = date(2026, 7, 15)
        self.assertEqual(daily_drill(101, on), daily_drill(101, on))

    def test_varies_by_date(self):
        pairs = {(daily_drill(101, date(2026, 7, d))["key"],
                  daily_drill(101, date(2026, 7, d))["prompt"]) for d in range(1, 11)}
        self.assertGreaterEqual(len(pairs), 2)

    def test_varies_by_user(self):
        on = date(2026, 7, 15)
        keys = {daily_drill(uid, on)["key"] for uid in range(1, 11)}
        self.assertGreaterEqual(len(keys), 2)

    def test_type_selection_covers_all_three(self):
        on = date(2026, 7, 15)
        types = {daily_drill(uid, on)["drill_type"] for uid in range(1, 60)}
        self.assertEqual(types, {"mental_math", "market_sizing", "framework_recall"})


# ── DB-gated endpoint tests ──────────────────────────────────────────────────
try:
    from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
except Exception:  # pragma: no cover
    _DB_URL, _HTTPX, _READY = None, False, False


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDrillsEndpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        from fastapi.testclient import TestClient

        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.aid = cur.fetchone()[0]

        session = create_session(cls.aid, user_agent="p4-drills-bank-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, session.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def test_daily_returns_wire_drill_and_is_stable(self):
        r = self.alice.get("/api/v1/drills/daily")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("drill", body)
        self.assertIn("date", body)
        drill = body["drill"]
        for key in ("key", "drill_type", "prompt", "answer", "explanation", "numbers"):
            self.assertIn(key, drill)
        # Same user, same UTC day -> identical drill.
        r2 = self.alice.get("/api/v1/drills/daily")
        self.assertEqual(r2.json()["drill"], drill)

    def test_daily_unauthenticated_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).get("/api/v1/drills/daily")
        self.assertEqual(r.status_code, 401)

    def test_templates_returns_bank(self):
        r = self.alice.get("/api/v1/drills/templates")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["version"], 1)
        self.assertGreaterEqual(len(body["templates"]), 30)

    def test_templates_unauthenticated_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).get("/api/v1/drills/templates")
        self.assertEqual(r.status_code, 401)


if __name__ == "__main__":
    unittest.main()
