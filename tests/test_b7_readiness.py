"""B7 Task 3: the readiness swap-point (OD-B7-1 stand-in) + reweight payload.

Uses the same finalized-session fixture shape as tests/test_dashboard.py:
Cara (c@yale.edu) is the subject; 3 finalized-as-candidate sessions with a
generic template make quant strictly weakest (avg 1.0/5) so the stand-in
returns needs_work and focus_dimension='quant'.
"""

from __future__ import annotations

import json
import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

# All FIVE generic-template dimensions must be seeded: dimension_averages
# iterates the template's items and COALESCEs a missing dimension to 0, so an
# unseeded dim (insight/synthesis) would score 0.0 and steal "weakest" from
# quant. These values (mirroring tests/test_dashboard.py) make quant strictly
# weakest (1.0/5) and communication strongest (4.33/5).
_SESSIONS = [
    {"grade": 4.5, "pts": {"structure": 4, "quant": 2, "insight": 3,
                           "communication": 5, "synthesis": 1}},
    {"grade": 4.0, "pts": {"structure": 3, "quant": 0, "insight": 4,
                           "communication": 4, "synthesis": 2}},
    {"grade": 4.2, "pts": {"structure": 5, "quant": 1, "insight": 4,
                           "communication": 4, "synthesis": 3}},
]


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestReadiness(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Enter the app lifespan so the shared connection pool is initialized
        # (get_or_create_room / get_default_rubric_template_id and the readiness
        # functions all go through webapp.db.get_pool()). Must precede any
        # pool-backed call below. Matches test_b7_firms / test_b7_user_firms.
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()

        import psycopg
        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        from webapp.repositories.rooms import get_or_create_room

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.cid = ids["a@yale.edu"], ids["c@yale.edu"]
        room_id = get_or_create_room(cls.aid)["id"]

        cls.case_ids, cls.session_ids = [], []
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                for i in range(3):
                    cur.execute(
                        "INSERT INTO cases (case_title, normalized_title,"
                        " source_school, source_year, industry, case_type,"
                        " difficulty, difficulty_score, page_count, pdf_path)"
                        " VALUES (%s, %s, 'DevSchool', 2096, 'Technology',"
                        " 'B7-Rd', 'Easy', 3, 2, 'output/none.pdf') RETURNING id;",
                        (f"B7 Rd Case {i}", f"b7 rd case {i}"))
                    cls.case_ids.append(cur.fetchone()[0])
                template_id = get_default_rubric_template_id(cls.case_ids[0], cls.aid)
                for i, spec in enumerate(_SESSIONS):
                    cur.execute(
                        "INSERT INTO practice_sessions (room_id, interviewer_id,"
                        " candidate_id, case_id, rubric_template_id, state,"
                        " consent_interviewer, consent_candidate, started_at,"
                        " ended_at, state_changed_at)"
                        " VALUES (%s, %s, %s, %s, %s, 'finalized', TRUE, TRUE,"
                        " NOW() - (%s + 1) * INTERVAL '1 day',"
                        " NOW() - (%s + 1) * INTERVAL '1 day' + INTERVAL '45 min',"
                        " NOW()) RETURNING id;",
                        (room_id, cls.aid, cls.cid, cls.case_ids[i], template_id, i, i))
                    sid = cur.fetchone()[0]
                    cls.session_ids.append(sid)
                    items = {d: {"points": p, "note": ""} for d, p in spec["pts"].items()}
                    cur.execute(
                        "INSERT INTO feedback (session_id, rubric_json, notes_md,"
                        " grade, finalized_at) VALUES (%s, %s, 'fx', %s, NOW());",
                        (sid, json.dumps({"items": items}), spec["grade"]))

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
                            (cls.session_ids,))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    def test_signal_needs_work_focus_quant(self):
        from webapp import readiness
        sig = readiness.readiness_signal(self.cid)
        self.assertEqual(sig["label"], "needs_work")   # weakest quant 1.0 < 3.0
        self.assertFalse(sig["ready"])
        self.assertEqual(sig["focus_dimension"], "quant")
        self.assertEqual(sig["recent_case_count"], 3)

    def test_signal_no_data_is_needs_work(self):
        from webapp import readiness
        # Alice (a@yale.edu) has no finalized-as-candidate sessions here.
        sig = readiness.readiness_signal(self.aid)
        self.assertEqual(sig["label"], "needs_work")
        self.assertIsNone(sig["focus_dimension"])
        self.assertEqual(sig["recent_case_count"], 0)

    def test_suggested_drill_type_mapping(self):
        from webapp import readiness
        self.assertEqual(readiness.suggested_drill_type("market_sizing"), "market_sizing")
        self.assertEqual(readiness.suggested_drill_type("quant"), "mental_math")
        self.assertEqual(readiness.suggested_drill_type("structure"), "framework_recall")
        self.assertEqual(readiness.suggested_drill_type(None), "mental_math")

    def test_reweight_payload_shape(self):
        from webapp import readiness
        rw = readiness.reweight_payload(self.cid)
        self.assertEqual(set(rw), {"focus_dimension", "suggested_drill_type", "extra_cases"})
        self.assertEqual(rw["focus_dimension"], "quant")
        self.assertEqual(rw["suggested_drill_type"], "mental_math")
        self.assertIsInstance(rw["extra_cases"], list)
        self.assertLessEqual(len(rw["extra_cases"]), 2)
        for cid in rw["extra_cases"]:
            self.assertIsInstance(cid, int)


if __name__ == "__main__":
    unittest.main()
