"""B6 Task 4: leaderboards repository — activity points, group board + progress,
school standings. Percentiles only; NO population counts. Needs seeded Postgres."""

from __future__ import annotations

import json
import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
class TestLeaderboardsRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Repo functions call webapp.db.get_pool(); enter a TestClient to init it.
        from fastapi.testclient import TestClient
        from webapp.main import app
        import psycopg
        from webapp.repositories.rooms import get_or_create_room
        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute("SELECT id FROM cases WHERE case_title = 'Dev Dummy Case'"
                            " ORDER BY id LIMIT 1;")
                cls.case_id = cur.fetchone()[0]  # seeded dummy case (do not assume id=1)
        cls.a, cls.b, cls.c = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]
        cls.room = get_or_create_room(cls.a)["id"]
        cls.tmpl = get_default_rubric_template_id(cls.case_id, cls.a)
        cls.sids = []
        # Give b two finalized sessions (as candidate) with grades; c one.
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                for cand, grade in ((cls.b, 4.0), (cls.b, 4.5), (cls.c, 3.0)):
                    cur.execute(
                        "INSERT INTO practice_sessions (room_id, interviewer_id,"
                        " candidate_id, case_id, rubric_template_id, state,"
                        " consent_interviewer, consent_candidate, started_at,"
                        " ended_at, state_changed_at) VALUES (%s,%s,%s,%s,%s,'finalized',"
                        " TRUE,TRUE, NOW()-INTERVAL '1 day', NOW()-INTERVAL '1 day', NOW())"
                        " RETURNING id;", (cls.room, cls.a, cand, cls.case_id, cls.tmpl))
                    sid = cur.fetchone()[0]
                    cls.sids.append(sid)
                    cur.execute("INSERT INTO feedback (session_id, rubric_json, notes_md,"
                                " grade, finalized_at) VALUES (%s,%s,'fx',%s,NOW());",
                                (sid, json.dumps({"items": {}}), grade))

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM practice_sessions WHERE id = ANY(%s);", (cls.sids,))
                cur.execute("DELETE FROM drill_attempts WHERE user_id = ANY(%s);",
                            ([cls.a, cls.b, cls.c],))
                cur.execute("DELETE FROM groups WHERE created_by = ANY(%s);",
                            ([cls.a, cls.b, cls.c],))
        cls._ctx.__exit__(None, None, None)

    def test_group_leaderboard_ranks_and_points(self):
        from webapp.repositories import groups as grepo
        from webapp.repositories import leaderboards as repo
        g = grepo.create_group("Board Test", self.a)
        grepo.join_by_code(g["invite_code"], self.b)
        grepo.join_by_code(g["invite_code"], self.c)
        board = repo.group_leaderboard(g["id"])
        # b (2 finalized) outranks c (1) outranks a (0)
        self.assertEqual([r["user_id"] for r in board], [self.b, self.c, self.a])
        self.assertEqual([r["rank"] for r in board], [1, 2, 3])
        self.assertGreater(board[0]["points"], board[1]["points"])
        self.assertIn("streak", board[0])
        grepo.leave_group(g["id"], self.b); grepo.leave_group(g["id"], self.c)
        grepo.leave_group(g["id"], self.a)

    def test_group_progress_metrics(self):
        from webapp.repositories import groups as grepo
        from webapp.repositories import leaderboards as repo
        from webapp.repositories.drill_attempts import record_attempt
        record_attempt(self.b, drill_type="mental_math", source="server",
                       drill_key=None, correct=True)
        g = grepo.create_group("Progress Test", self.a)
        grepo.join_by_code(g["invite_code"], self.b)
        prog = {r["user_id"]: r for r in repo.group_progress(g["id"])}
        self.assertEqual(prog[self.b]["cases_done"], 2)
        self.assertAlmostEqual(float(prog[self.b]["mean_grade"]), 4.25, places=1)
        self.assertEqual(prog[self.b]["drill_attempts_30d"], 1)
        self.assertEqual(prog[self.a]["cases_done"], 0)
        grepo.leave_group(g["id"], self.b); grepo.leave_group(g["id"], self.a)

    def test_school_standings_no_counts(self):
        from webapp.repositories import leaderboards as repo
        standings = repo.school_standings()
        self.assertTrue(standings)
        for s in standings:
            self.assertIn("avg_member_percentile", s)
            self.assertIn("campus_city", s)
            self.assertIn("rank", s)
            # NO population-count leakage
            for k in s:
                self.assertNotIn("count", k.lower())
                self.assertNotIn("total", k.lower())

    def test_my_school_standing(self):
        from webapp.repositories import leaderboards as repo
        me = repo.my_school_standing(self.b)
        self.assertIsNotNone(me["school"])
        self.assertIn("campus_city", me["school"])
        self.assertIsInstance(me["your_percentile"], float)

    def test_scope_user_ids(self):
        from webapp.repositories import groups as grepo
        from webapp.repositories import leaderboards as repo
        g = grepo.create_group("Scope Test", self.a)
        grepo.join_by_code(g["invite_code"], self.b)
        self.assertEqual(set(repo.scope_user_ids("group", user_id=self.a, group_id=g["id"])),
                         {self.a, self.b})
        self.assertIn(self.a, repo.scope_user_ids("school", user_id=self.a))
        self.assertIn(self.a, repo.scope_user_ids("global", user_id=self.a))
        grepo.leave_group(g["id"], self.b); grepo.leave_group(g["id"], self.a)
