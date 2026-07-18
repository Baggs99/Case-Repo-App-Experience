"""
F10 Task 1: the guest link-gate (/g/claim/{token}) — GET renders the 8a gate
bound to a real open, instant, candidate-role, case-set proposal; POST claims
it (minting a guest when unauthenticated) and 303-redirects to the console.
Follows the login/cookie + open-link idiom of tests/test_b1_proposals_open.py.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestGuestLinkGate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES ('F10 Gate Case', 'f10 gate case',"
                    " 'DevSchool', 2091, 'Technology', 'Profitability', 'Easy', 3.0,"
                    " 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.aid, cls.bid, cls.cid = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]
        s = create_session(cls.aid, user_agent="f10-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # proposals.session_id FKs practice_sessions -> delete proposals first.
                cur.execute("DELETE FROM proposals WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)

    def _mk_open(self, **overrides):
        """Alice (candidate role) sends an open link — from_role=candidate so
        the claimer becomes the interviewer, per the gate's SQL restriction."""
        payload = {"case_id": self.case_id, "from_role": "candidate"}
        payload.update(overrides)
        r = self.alice.post("/api/proposals", json=payload)
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["claim_token"]

    def _user_count(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM users;")
                return cur.fetchone()[0]

    def _cleanup_guest(self, user_id, session_id):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # FK order: proposals.session_id -> practice_sessions.id (no
                # cascade), practice_sessions.interviewer_id -> users.id (no
                # cascade) -> delete proposal, then session, then user.
                cur.execute("DELETE FROM proposals WHERE session_id = %s;", (session_id,))
                cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (session_id,))
                cur.execute("DELETE FROM sessions WHERE user_id = %s;", (user_id,))
                cur.execute("DELETE FROM users WHERE id = %s AND is_guest = TRUE;", (user_id,))

    # ── GET /g/claim/{token} ────────────────────────────────────────────────

    def test_get_gate_renders_open_proposal(self):
        tok = self._mk_open()
        r = self.alice.get(f"/g/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("ASKED TO INTERVIEW", r.text.upper())
        self.assertIn("F10 Gate Case", r.text)
        # from_name = a@yale.edu's display_name (COALESCE/split_part fallback);
        # anchor on the h1's own closing style attr so this isn't a
        # trivially-true substring check against arbitrary HTML.
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT COALESCE(display_name, split_part(email, '@', 1))"
                        " FROM users WHERE id = %s;", (self.aid,))
            expected_from_name = cur.fetchone()[0]
        self.assertIn(f'color:#0D1C31">{expected_from_name}</h1>', r.text)

    def test_get_gate_unknown_token_404(self):
        r = self.alice.get("/g/claim/bogustoken")
        self.assertEqual(r.status_code, 404)
        self.assertIn("no longer active", r.text.lower())

    # ── POST /g/claim/{token} ───────────────────────────────────────────────

    def test_post_claim_unauth_mints_guest_and_redirects(self):
        tok = self._mk_open()
        before = self._user_count()
        from fastapi.testclient import TestClient
        from webapp.main import app
        anon = TestClient(app, follow_redirects=False)
        r = anon.post(f"/g/claim/{tok}", headers={"Origin": "http://testserver"})
        self.assertEqual(r.status_code, 303, r.text)
        self.assertTrue(r.headers["location"].startswith("/g/session/"))
        after = self._user_count()
        self.assertEqual(after, before + 1)
        # Locate + clean up the minted guest.
        session_id = int(r.headers["location"].rsplit("/", 1)[1])
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT interviewer_id FROM practice_sessions WHERE id = %s;",
                            (session_id,))
                guest_id = cur.fetchone()[0]
        self._cleanup_guest(guest_id, session_id)

    def test_post_claim_scheduled_token_404_no_orphan_guest(self):
        when = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        tok = self._mk_open(proposed_times=[when])
        before = self._user_count()
        from fastapi.testclient import TestClient
        from webapp.main import app
        anon = TestClient(app, follow_redirects=False)
        r = anon.post(f"/g/claim/{tok}", headers={"Origin": "http://testserver"})
        self.assertEqual(r.status_code, 404, r.text)
        after = self._user_count()
        self.assertEqual(after, before)  # no orphan guest row left behind


if __name__ == "__main__":
    unittest.main()
