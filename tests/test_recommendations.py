"""
B4 Task 1-3 tests: the recommendation engine's human-readable `why`, the
exclude/limit affordances and canonical item shape (Task 1), the native
`GET /api/v1/recommendations` mouth (Task 2), and the `/api/v1/dashboard`
Home card (Task 3).

Reuses the proven §4.8 fixture idiom from tests/test_dashboard.py: three
finalized sessions with a hand-tuned rubric make all three rules fire for
one candidate (Cara). Skips cleanly without the seeded dev Postgres.
"""

from __future__ import annotations

import json
import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

# points per dimension per session: (structure, quant, insight, comm, synth)
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
class TestRecommendationSurfaces(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.cara = cls._ctx.__enter__()          # enters app lifespan → pool live

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.cid = ids["a@yale.edu"], ids["c@yale.edu"]
        s = create_session(cls.cid, user_agent="b4-test", ip_address=None)
        cls.cara.cookies.set(SESSION_COOKIE_NAME, s.id)

        def new_case(cur, title, ctype, difficulty, score):
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path)"
                " VALUES (%s, %s, 'DevSchool', 2095, 'Technology', %s, %s, %s,"
                " 2, 'output/none.pdf') RETURNING id;",
                (title, title.lower(), ctype, difficulty, score))
            return cur.fetchone()[0]

        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        from webapp.repositories.rooms import get_or_create_room
        room_id = get_or_create_room(cls.aid)["id"]

        cls.case_ids = []
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cls.a1 = new_case(cur, "B4 Trend Case 1", "B4-TypeA", "Easy", 2)
                cls.a2 = new_case(cur, "B4 Trend Case 2", "B4-TypeA", "Easy", 3)
                cls.a3 = new_case(cur, "B4 Trend Case 3", "B4-TypeA", "Easy", 4)
                cls.a4 = new_case(cur, "B4 Ladder Target", "B4-TypeA", "Medium", 5)
                # Coverage-gap type: '00-…' wins the zero-count alphabetical tie.
                # B1 outrates B2 (DV-6); with B1 excluded, B2 is the runner-up.
                cls.b1 = new_case(cur, "B4 Gap Rated", "00-B4-GapType", "Easy", 3)
                cls.b2 = new_case(cur, "B4 Gap Unrated", "00-B4-GapType", "Easy", 3)
                cls.w1 = new_case(cur, "B4 Quant Heavy", "B4-TypeA", "Easy", 3)
                cls.case_ids = [cls.a1, cls.a2, cls.a3, cls.a4, cls.b1, cls.b2, cls.w1]

                cur.execute(
                    "INSERT INTO case_votes (case_id, user_id, vote_type)"
                    " VALUES (%s, %s, 'useful');", (cls.b1, cls.aid))
                cur.execute(
                    "INSERT INTO rubric_templates (case_id, name, items_json,"
                    " created_by) VALUES (%s, 'Quant heavy', %s, %s);",
                    (cls.w1, json.dumps([
                        {"id": "quant", "label": "Quant", "dimension": "quant",
                         "max_points": 8},
                        {"id": "structure", "label": "Structure",
                         "dimension": "structure", "max_points": 2},
                    ]), cls.aid))

                template_id = get_default_rubric_template_id(cls.a1, cls.aid)
                cls.session_ids = []
                for i, (case_id, spec) in enumerate(
                        zip((cls.a1, cls.a2, cls.a3), _SESSIONS)):
                    cur.execute(
                        "INSERT INTO practice_sessions (room_id, interviewer_id,"
                        " candidate_id, case_id, rubric_template_id, state,"
                        " consent_interviewer, consent_candidate, started_at,"
                        " ended_at, state_changed_at)"
                        " VALUES (%s, %s, %s, %s, %s, 'finalized', TRUE, TRUE,"
                        " NOW() - (%s + 1) * INTERVAL '1 day',"
                        " NOW() - (%s + 1) * INTERVAL '1 day' + INTERVAL '45 min',"
                        " NOW()) RETURNING id;",
                        (room_id, cls.aid, cls.cid, case_id, template_id, i, i))
                    sid = cur.fetchone()[0]
                    cls.session_ids.append(sid)
                    items = {dim: {"points": pts, "note": ""}
                             for dim, pts in spec["pts"].items()}
                    cur.execute(
                        "INSERT INTO feedback (session_id, rubric_json, notes_md,"
                        " grade, finalized_at)"
                        " VALUES (%s, %s, 'fixture', %s, NOW());",
                        (sid, json.dumps({"items": items}), spec["grade"]))

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);",
                            (cls.session_ids,))
                cur.execute("DELETE FROM case_votes WHERE case_id = ANY(%s);",
                            (cls.case_ids,))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    # ── Task 1: engine (repo-direct) ────────────────────────────────────────

    def test_item_shape_is_canonical(self):
        from webapp.repositories import dashboard as repo
        recs = repo.recommendations(self.cid)
        self.assertTrue(recs)
        for rec in recs:
            self.assertEqual(set(rec), {"case_id", "title", "case_type",
                                        "difficulty", "why", "rule"})
            self.assertIsInstance(rec["title"], str)
            self.assertIsInstance(rec["why"], str)
            self.assertTrue(rec["why"])

    def test_why_strings_per_rule(self):
        from webapp.repositories import dashboard as repo
        by_rule = {r["rule"]: r for r in repo.recommendations(self.cid)}
        self.assertIn("least-practiced", by_rule["coverage-gap"]["why"])
        self.assertIn(by_rule["coverage-gap"]["case_type"],
                      by_rule["coverage-gap"]["why"])
        self.assertIn("step up", by_rule["difficulty-ladder"]["why"])
        self.assertIn("Medium", by_rule["difficulty-ladder"]["why"])
        self.assertIn("weakest dimension is quant",
                      by_rule["weak-dimension"]["why"])

    def test_exclude_drops_case_and_backfills(self):
        from webapp.repositories import dashboard as repo
        base = {r["rule"]: r["case_id"] for r in repo.recommendations(self.cid)}
        self.assertEqual(base["coverage-gap"], self.b1)
        excluded = repo.recommendations(self.cid, exclude_case_ids=[self.b1])
        ids = {r["case_id"] for r in excluded}
        self.assertNotIn(self.b1, ids)
        # B2 is the same-type runner-up once B1 is excluded (DV-6 tie-break).
        self.assertEqual({r["rule"]: r["case_id"]
                          for r in excluded}["coverage-gap"], self.b2)

    def test_limit_caps_results(self):
        from webapp.repositories import dashboard as repo
        self.assertLessEqual(len(repo.recommendations(self.cid, limit=1)), 1)
        self.assertLessEqual(len(repo.recommendations(self.cid, limit=2)), 2)

    def test_web_engine_selection_unchanged(self):
        # Byte-compat guard: the three rules still select b1/a4/w1 (as
        # test_dashboard.py asserts) — only the item key label changed.
        from webapp.repositories import dashboard as repo
        by_rule = {r["rule"]: r["case_id"] for r in repo.recommendations(self.cid)}
        self.assertEqual(by_rule["coverage-gap"], self.b1)
        self.assertEqual(by_rule["difficulty-ladder"], self.a4)
        self.assertEqual(by_rule["weak-dimension"], self.w1)

    # ── Task 2: native list mouth ───────────────────────────────────────────

    def test_api_recommendations_shape(self):
        r = self.cara.get("/api/v1/recommendations")
        self.assertEqual(r.status_code, 200, r.text)
        recs = r.json()["recommendations"]
        self.assertTrue(recs)
        for rec in recs:
            self.assertEqual(set(rec), {"case_id", "title", "case_type",
                                        "difficulty", "why", "rule"})
        by_rule = {rec["rule"]: rec["case_id"] for rec in recs}
        self.assertEqual(by_rule["coverage-gap"], self.b1)

    def test_api_recommendations_exclude(self):
        r = self.cara.get(f"/api/v1/recommendations?exclude={self.b1}")
        self.assertEqual(r.status_code, 200, r.text)
        ids = {rec["case_id"] for rec in r.json()["recommendations"]}
        self.assertNotIn(self.b1, ids)
        self.assertIn(self.b2, ids)

    def test_api_recommendations_invalid_exclude_is_400(self):
        r = self.cara.get("/api/v1/recommendations?exclude=1,abc")
        self.assertEqual(r.status_code, 400, r.text)

    def test_api_recommendations_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).get("/api/v1/recommendations")
        self.assertEqual(r.status_code, 401)

    # ── Task 3: Home-card mouth ─────────────────────────────────────────────

    def test_api_v1_dashboard_gains_dims_and_recs(self):
        r = self.cara.get("/api/v1/dashboard")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        # dimension_averages: existing web-dashboard shape, weakest first.
        dims = body["dimension_averages"]
        self.assertTrue(dims)
        self.assertEqual(set(dims[0]), {"dimension", "avg_score", "samples"})
        self.assertEqual(dims[0]["dimension"], "quant")
        # recommendations: canonical item shape, rules fire.
        recs = body["recommendations"]
        by_rule = {rec["rule"]: rec["case_id"] for rec in recs}
        self.assertEqual(by_rule["coverage-gap"], self.b1)
        for rec in recs:
            self.assertEqual(set(rec), {"case_id", "title", "case_type",
                                        "difficulty", "why", "rule"})

    def test_api_v1_dashboard_keeps_existing_keys(self):
        body = self.cara.get("/api/v1/dashboard").json()
        for key in ("sessions_finalized", "streak_weeks", "next_session",
                    "streak_days", "drill_done_today"):
            self.assertIn(key, body)


if __name__ == "__main__":
    unittest.main()
