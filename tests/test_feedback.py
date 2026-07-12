"""
Integration tests for Phase 7: rubric drafts, grade computation, the
finalize transaction (grade + burned + queue_want removal + state flip),
released-feedback gating, and A6 burned-case session rejection.

Needs the seeded dev Postgres — skips cleanly otherwise. Creates its own
case row and cleans up everything it writes (sessions cascade feedback and
reveals; burned/queue rows removed explicitly).
"""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestFeedbackAndFinalize(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()   # interviewer
        cls.bob = TestClient(app)          # candidate
        cls.cara = TestClient(app)         # outsider

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('Feedback Test Case', 'feedback test case', 'DevSchool',"
                    " 2097, 'Technology', 'Profitability', 'Easy', 3.0, 2,"
                    " 'output/cases/devschool/nonexistent.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.alice_id, cls.bob_id = ids["a@yale.edu"], ids["b@yale.edu"]

        for client, email in ((cls.alice, "a@yale.edu"), (cls.bob, "b@yale.edu"),
                              (cls.cara, "c@yale.edu")):
            s = create_session(ids[email], user_agent="feedback-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM burned WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM queue_want WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    # ── helpers ──────────────────────────────────────────────────────────────

    def _new_session(self, to_state: str = "scheduled") -> int:
        r = self.alice.post("/api/practice", json={
            "interviewer_id": self.alice_id, "candidate_id": self.bob_id,
            "case_id": self.case_id,
        })
        self.assertEqual(r.status_code, 200, r.text)
        sid = r.json()["id"]
        if to_state in ("lobby", "live", "debrief"):
            self.assertEqual(self.alice.post(
                f"/api/practice/{sid}/state", json={"target": "lobby"}).status_code, 200)
        if to_state in ("live", "debrief"):
            for c in (self.alice, self.bob):
                self.assertEqual(c.post(
                    f"/api/practice/{sid}/consent", json={"consent": True}).status_code, 200)
            self.assertEqual(self.alice.post(
                f"/api/practice/{sid}/state", json={"target": "live"}).status_code, 200)
        if to_state == "debrief":
            self.assertEqual(self.alice.post(
                f"/api/practice/{sid}/state", json={"target": "debrief"}).status_code, 200)
        return sid

    DRAFT = {
        "items": {
            "structure": {"points": 4, "note": "good tree"},
            "quant": {"points": 3, "note": ""},
            "insight": {"points": 5, "note": "sharp"},
            "communication": {"points": 4, "note": ""},
            "synthesis": {"points": 2, "note": "rushed"},
        },
        "notes_md": "Overall solid. Practice synthesis under time pressure.",
    }
    # 18/25 → 5×0.72 = 3.6

    # ── rubric draft ─────────────────────────────────────────────────────────

    def test_rubric_roles_and_persistence(self):
        sid = self._new_session("live")

        r = self.alice.get(f"/api/practice/{sid}/rubric")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(len(r.json()["template_items"]), 5)
        self.assertEqual(r.json()["grade_preview"], 0.0)

        self.assertEqual(self.bob.get(f"/api/practice/{sid}/rubric").status_code, 403)
        self.assertEqual(self.cara.get(f"/api/practice/{sid}/rubric").status_code, 404)
        self.assertEqual(
            self.bob.put(f"/api/practice/{sid}/rubric", json=self.DRAFT).status_code, 403)

        r = self.alice.put(f"/api/practice/{sid}/rubric", json=self.DRAFT)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["grade_preview"], 3.6)

        # Draft survives (the reload case): fresh GET returns what was saved.
        r = self.alice.get(f"/api/practice/{sid}/rubric")
        self.assertEqual(r.json()["items"]["structure"]["points"], 4)
        self.assertEqual(r.json()["notes_md"], self.DRAFT["notes_md"])
        self.assertEqual(r.json()["grade_preview"], 3.6)

    def test_rubric_validation(self):
        sid = self._new_session("live")
        bad_id = {"items": {"nonsense": {"points": 1}}, "notes_md": ""}
        r = self.alice.put(f"/api/practice/{sid}/rubric", json=bad_id)
        self.assertEqual(r.status_code, 400)
        over = {"items": {"quant": {"points": 9}}, "notes_md": ""}
        r = self.alice.put(f"/api/practice/{sid}/rubric", json=over)
        self.assertEqual(r.status_code, 400)

    # ── finalize ─────────────────────────────────────────────────────────────

    def test_finalize_full_transaction(self):
        sid = self._new_session("debrief")
        self.assertEqual(self.alice.put(
            f"/api/practice/{sid}/rubric", json=self.DRAFT).status_code, 200)

        # Seed a want-queue row so its removal is observable.
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO queue_want (user_id, case_id) VALUES (%s, %s)"
                            " ON CONFLICT DO NOTHING;", (self.bob_id, self.case_id))

        # Wrong actor, then pre-finalize feedback gating.
        self.assertEqual(self.bob.post(
            f"/api/practice/{sid}/finalize", json={}).status_code, 403)
        self.assertEqual(self.bob.get(
            f"/api/practice/{sid}/feedback").status_code, 409)

        r = self.alice.post(f"/api/practice/{sid}/finalize", json={})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["grade"], 3.6)

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT state FROM practice_sessions WHERE id = %s;", (sid,))
                self.assertEqual(cur.fetchone()[0], "finalized")
                cur.execute("SELECT session_id FROM burned WHERE user_id = %s"
                            " AND case_id = %s;", (self.bob_id, self.case_id))
                self.assertEqual(cur.fetchone()[0], sid)
                cur.execute("SELECT 1 FROM queue_want WHERE user_id = %s"
                            " AND case_id = %s;", (self.bob_id, self.case_id))
                self.assertIsNone(cur.fetchone())

        # Released feedback: both participants, full breakdown.
        for client in (self.bob, self.alice):
            r = client.get(f"/api/practice/{sid}/feedback")
            self.assertEqual(r.status_code, 200, r.text)
            body = r.json()
            self.assertEqual(body["grade"], 3.6)
            self.assertEqual(len(body["items"]), 5)
            by_id = {i["id"]: i for i in body["items"]}
            self.assertEqual(by_id["synthesis"]["points"], 2)
            self.assertEqual(by_id["synthesis"]["note"], "rushed")
            self.assertIn("synthesis under time pressure", body["notes_md"])
        self.assertEqual(self.cara.get(f"/api/practice/{sid}/feedback").status_code, 404)

        # Post-finalize: draft is read-only, double finalize 409.
        self.assertEqual(self.alice.put(
            f"/api/practice/{sid}/rubric", json=self.DRAFT).status_code, 409)
        self.assertEqual(self.alice.post(
            f"/api/practice/{sid}/finalize", json={}).status_code, 409)

        # A6: the case is now burned for Bob — new session rejected.
        r = self.alice.post("/api/practice", json={
            "interviewer_id": self.alice_id, "candidate_id": self.bob_id,
            "case_id": self.case_id,
        })
        self.assertEqual(r.status_code, 409)
        self.assertIn("burned", r.json()["detail"])
        # …but Bob can still interview OTHERS on it (burn is per-candidate).
        r = self.bob.post("/api/practice", json={
            "interviewer_id": self.bob_id,
            "candidate_id": ids_of(self, "c@yale.edu"),
            "case_id": self.case_id,
        })
        self.assertEqual(r.status_code, 200, r.text)

        # Clean the burn so other tests (and re-runs) start fresh.
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM burned WHERE user_id = %s AND case_id = %s;",
                            (self.bob_id, self.case_id))

    def test_finalize_requires_debrief_and_range(self):
        sid = self._new_session("live")
        r = self.alice.post(f"/api/practice/{sid}/finalize", json={})
        self.assertEqual(r.status_code, 409)

        self.assertEqual(self.alice.post(
            f"/api/practice/{sid}/state", json={"target": "debrief"}).status_code, 200)
        r = self.alice.post(f"/api/practice/{sid}/finalize", json={"grade": 7})
        self.assertEqual(r.status_code, 422)  # pydantic ge/le bound

        r = self.alice.post(f"/api/practice/{sid}/finalize", json={"grade": 4.5})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["grade"], 4.5)
        with __import__("psycopg").connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM burned WHERE user_id = %s AND case_id = %s;",
                            (self.bob_id, self.case_id))


def ids_of(test: TestFeedbackAndFinalize, email: str) -> int:
    import psycopg
    with psycopg.connect(_DB_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = %s;", (email,))
            return cur.fetchone()[0]


if __name__ == "__main__":
    unittest.main()
