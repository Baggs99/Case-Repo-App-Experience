"""
Phase 9 tests: session history, per-dimension trends (hand-computed
comparison), the three §4.8 recommendation rules firing on a seeded
fixture, and the T9.3 privacy audit (no grade reaches any other user).

Needs the seeded dev Postgres — skips cleanly otherwise. All fixture rows
(cases, sessions, feedback, votes, templates) are created and removed here.

Hand computation for the trend fixture (3 finalized-as-candidate sessions,
generic template, every item max 5; A11 scale = AVG(points/max) × 5):
  structure     (4+3+5)/3 /5 ×5 = 4.00
  quant         (2+0+1)/3 /5 ×5 = 1.00   ← strictly weakest
  insight       (3+4+4)/3 /5 ×5 = 3.67
  communication (5+4+4)/3 /5 ×5 = 4.33
  synthesis     (1+2+3)/3 /5 ×5 = 2.00
Grades 4.5 / 4.0 / 4.2 → mean 4.23 ≥ 4.0 → the difficulty ladder fires.
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
_EXPECTED_TRENDS = {"structure": 4.0, "quant": 1.0, "insight": 3.67,
                    "communication": 4.33, "synthesis": 2.0}


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDashboard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.bob = cls._ctx.__enter__()      # privacy prober
        cls.cara = TestClient(app)          # the dashboard subject

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid, cls.cid = (ids["a@yale.edu"], ids["b@yale.edu"],
                                     ids["c@yale.edu"])
        for client, email in ((cls.bob, "b@yale.edu"), (cls.cara, "c@yale.edu")):
            s = create_session(ids[email], user_agent="p9-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

        def new_case(cur, title, ctype, difficulty, score):
            cur.execute(
                "INSERT INTO cases (case_title, normalized_title, source_school,"
                " source_year, industry, case_type, difficulty, difficulty_score,"
                " page_count, pdf_path)"
                " VALUES (%s, %s, 'DevSchool', 2095, 'Technology', %s, %s, %s,"
                " 2, 'output/none.pdf') RETURNING id;",
                (title, title.lower(), ctype, difficulty, score))
            return cur.fetchone()[0]

        from webapp.repositories.practice_sessions import (
            get_default_rubric_template_id)
        from webapp.repositories.rooms import get_or_create_room
        room_id = get_or_create_room(cls.aid)["id"]

        cls.case_ids = []
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # Practiced type (3 × Easy for the ladder mode) + its Medium rung.
                cls.a1 = new_case(cur, "P9 Trend Case 1", "P9-TypeA", "Easy", 2)
                cls.a2 = new_case(cur, "P9 Trend Case 2", "P9-TypeA", "Easy", 3)
                cls.a3 = new_case(cur, "P9 Trend Case 3", "P9-TypeA", "Easy", 4)
                cls.a4 = new_case(cur, "P9 Ladder Target", "P9-TypeA", "Medium", 5)
                # Coverage-gap type: '00-…' wins the zero-count alphabetical tie
                # against any other type in the dev DB. B1 outrates B2 (DV-6).
                cls.b1 = new_case(cur, "P9 Gap Rated", "00-P9-GapType", "Easy", 3)
                cls.b2 = new_case(cur, "P9 Gap Unrated", "00-P9-GapType", "Easy", 3)
                # Weak-dimension case: template weights quant 8 of 10 (share .8).
                cls.w1 = new_case(cur, "P9 Quant Heavy", "P9-TypeA", "Easy", 3)
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
                            (cls.session_ids,))          # cascades feedback
                cur.execute("DELETE FROM case_votes WHERE case_id = ANY(%s);",
                            (cls.case_ids,))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);",
                            (cls.case_ids,))             # cascades templates
        cls._ctx.__exit__(None, None, None)

    # ── trends: hand-computed comparison (done-when) ─────────────────────────

    def test_dimension_averages_match_hand_computation(self):
        r = self.cara.get("/api/dashboard")
        self.assertEqual(r.status_code, 200, r.text)
        got = {t["dimension"]: t["avg_score"]
               for t in r.json()["dimension_averages"]}
        self.assertEqual(got, _EXPECTED_TRENDS)
        # weakest first, for the weak-dimension rule
        self.assertEqual(r.json()["dimension_averages"][0]["dimension"], "quant")

    def test_history_rows(self):
        r = self.cara.get("/api/dashboard")
        hist = [h for h in r.json()["history"]
                if h["id"] in set(self.session_ids)]
        self.assertEqual(len(hist), 3)
        self.assertEqual(hist[0]["grade"], 4.5)   # newest first = S1 (1 day ago)
        self.assertEqual(hist[0]["your_role"], "candidate")
        self.assertEqual(hist[0]["counterpart"], "Alice Dev")

    # ── the three rules fire (done-when) ─────────────────────────────────────

    def test_recommendation_rules_fire(self):
        r = self.cara.get("/api/dashboard")
        recs = {rec["rule"]: rec for rec in r.json()["recommendations"]}
        self.assertEqual(recs["coverage-gap"]["case_id"], self.b1,
                         "gap type should win the tie and B1 outrate B2 (DV-6)")
        self.assertEqual(recs["difficulty-ladder"]["case_id"], self.a4,
                         "mean 4.23 ≥ 4.0 and mode is TypeA/Easy → its Medium rung")
        self.assertEqual(recs["weak-dimension"]["case_id"], self.w1,
                         "quant is weakest (1.0) and W1's template weights it .8")
        self.assertLessEqual(len(r.json()["recommendations"]), 5)

    # ── T9.3 privacy audit ───────────────────────────────────────────────────

    def test_grades_never_reach_other_users(self):
        # Bob's dashboard contains none of Cara's sessions or grades.
        r = self.bob.get("/api/dashboard")
        self.assertEqual(r.status_code, 200)
        bob_ids = {h["id"] for h in r.json()["history"]}
        self.assertFalse(bob_ids & set(self.session_ids))

        # Bob cannot pull a session's feedback he wasn't part of (404,
        # existence undisclosed — DV-11).
        for sid in self.session_ids:
            self.assertEqual(
                self.bob.get(f"/api/practice/{sid}/feedback").status_code, 404)
            self.assertEqual(
                self.bob.get(f"/api/practice/{sid}/rubric").status_code, 404)

        # Cara's public room, as seen by Bob: stats only — no grades, no
        # history, no recommendations.
        from webapp.repositories.rooms import get_or_create_room
        slug = get_or_create_room(self.cid)["slug"]
        page = self.bob.get(f"/room/{slug}")
        self.assertEqual(page.status_code, 200)
        self.assertIn("3 finalized sessions", page.text)
        for marker in ("4.5", "4.2", "Recommended", "History", "grade"):
            self.assertNotIn(marker, page.text,
                             f"{marker!r} leaked into another user's room view")

        # Anonymous: nothing at all.
        from fastapi.testclient import TestClient
        from webapp.main import app
        self.assertEqual(TestClient(app).get("/api/dashboard").status_code, 401)


if __name__ == "__main__":
    unittest.main()
