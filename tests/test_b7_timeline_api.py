"""B7 Task 5: timeline router — track/untrack, timeline-detail payload, the
post-deadline result flow, auth + IDOR. Needs seeded dev Postgres + httpx."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestTimelineApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from webapp.repositories import firms as firms_repo

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]
        for client, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
            s = create_session(uid, user_agent="b7-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)
        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM user_firms WHERE user_id = ANY(%s);",
                            ([cls.aid, cls.bid],))
        cls._ctx.__exit__(None, None, None)

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM user_firms WHERE user_id = ANY(%s);",
                            ([self.aid, self.bid],))

    # ── auth ────────────────────────────────────────────────────────────────
    def test_timeline_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        self.assertEqual(TestClient(app).get("/api/v1/timeline").status_code, 401)

    def test_track_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        r = TestClient(app).post("/api/v1/timeline/firms", json={"firm_id": self.mck})
        self.assertEqual(r.status_code, 401)

    # ── track / list / untrack ───────────────────────────────────────────────
    def test_track_untrack_and_catalog(self):
        r = self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.mck})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["status"], "tracking")

        cat = self.alice.get("/api/v1/timeline/firms").json()["firms"]
        mck = next(f for f in cat if f["firm_id"] == self.mck)
        self.assertTrue(mck["tracked"])
        self.assertIsNotNone(mck["next_deadline"])

        tl = self.alice.get("/api/v1/timeline").json()
        self.assertEqual(len(tl["firms"]), 1)
        self.assertIn(tl["firms"][0]["readiness_tag"], {"on_track", "focus", "early"})
        self.assertEqual(tl["readiness"]["label"], "needs_work")  # Alice: no data

        self.assertEqual(
            self.alice.delete(f"/api/v1/timeline/firms/{self.mck}").status_code, 204)
        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 0)

    def test_track_unknown_firm_404(self):
        r = self.alice.post("/api/v1/timeline/firms", json={"firm_id": -1})
        self.assertEqual(r.status_code, 404)

    # ── post-deadline result flow ─────────────────────────────────────────────
    def test_passed_deadline_prompt_then_offer(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
        tl = self.alice.get("/api/v1/timeline").json()
        rb = next(f for f in tl["firms"] if f["firm_id"] == self.rb)
        self.assertTrue(rb["deadline"]["passed"])
        self.assertTrue(rb["prompt"]["show"])

        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
                            json={"outcome": "offer"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["status"], "offer")
        # Prompt gone once resolved.
        tl2 = self.alice.get("/api/v1/timeline").json()
        rb2 = next(f for f in tl2["firms"] if f["firm_id"] == self.rb)
        self.assertFalse(rb2["prompt"]["show"])
        self.assertEqual(rb2["status"], "offer")

    def test_no_offer_returns_reweight(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
                            json={"outcome": "no_offer"})
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["status"], "rejected")
        self.assertEqual(set(body["reweight"]),
                         {"focus_dimension", "suggested_drill_type", "extra_cases"})

    def test_waiting_snoozes(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
                            json={"outcome": "waiting"})
        self.assertEqual(r.json()["status"], "interviewed")
        self.assertIsNotNone(r.json()["snooze_until"])

    def test_didnt_interview_drops_off(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
                            json={"outcome": "didnt_interview"})
        self.assertTrue(r.json()["dropped"])
        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 0)

    def test_bad_outcome_400(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
                            json={"outcome": "nope"})
        self.assertEqual(r.status_code, 400)

    # ── IDOR: Bob cannot resolve or untrack a firm only Alice tracks ──────────
    def test_result_on_untracked_firm_404(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
        r = self.bob.post(f"/api/v1/timeline/firms/{self.rb}/result",
                          json={"outcome": "offer"})
        self.assertEqual(r.status_code, 404)
        # Alice's row is untouched.
        tl = self.alice.get("/api/v1/timeline").json()
        self.assertEqual(tl["firms"][0]["status"], "tracking")

    def test_untrack_is_per_user(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
        # Bob deleting the same firm_id only touches his own (absent) row.
        self.assertEqual(
            self.bob.delete(f"/api/v1/timeline/firms/{self.rb}").status_code, 204)
        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 1)


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDashboardTimelineKeys(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from webapp.repositories import firms as firms_repo
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.aid = cur.fetchone()[0]
        s = create_session(cls.aid, user_agent="b7-dash", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, s.id)
        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (cls.aid,))
        cls._ctx.__exit__(None, None, None)

    def test_dashboard_has_diagnostic_and_timeline(self):
        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.mck})
        d = self.alice.get("/api/v1/dashboard").json()
        # Additive — existing B4 keys still present.
        self.assertIn("recommendations", d)
        self.assertIn("dimension_averages", d)
        # New B7 keys.
        self.assertIn("diagnostic", d)
        self.assertEqual(set(d["diagnostic"]) >= {
            "cases_done_60d", "dimensions", "strengths", "weaknesses",
            "focus_dimension", "trend"}, True)
        self.assertIn("timeline", d)
        self.assertEqual(d["timeline"]["tracked_count"], 1)
        # tracked_count already proves the timeline block is wired. next_deadline
        # rides the real wall clock against is_estimate seed dates, so guard the
        # subscript: it is McKinsey while that deadline is upcoming, None once it
        # passes — never a hard TypeError (final-review I-1).
        nd = d["timeline"]["next_deadline"]
        self.assertTrue(nd is None or nd["slug"] == "mckinsey")


if __name__ == "__main__":
    unittest.main()
