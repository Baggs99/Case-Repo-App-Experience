"""
B2 Task 3: unauthenticated claim endpoints mint a scoped guest + session
cookie. Needs the seeded dev Postgres with migration 025 — skips otherwise.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


def _cleanup_case(case_id: int) -> None:
    """Remove everything a B2 test attached to its dedicated case, in FK order,
    so the suite is re-runnable (finalize writes a `burned` row that would else
    409 later claims of the same case)."""
    import psycopg
    with psycopg.connect(_DB_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM users WHERE is_guest AND (id IN"
                " (SELECT interviewer_id FROM practice_sessions WHERE case_id=%s)"
                " OR id IN (SELECT candidate_id FROM practice_sessions WHERE case_id=%s));",
                (case_id, case_id))
            guest_ids = [r[0] for r in cur.fetchall()]
            cur.execute("DELETE FROM burned WHERE case_id=%s;", (case_id,))
            cur.execute("DELETE FROM queue_want WHERE case_id=%s;", (case_id,))
            cur.execute("DELETE FROM proposals WHERE case_id=%s;", (case_id,))
            cur.execute("DELETE FROM pairing_tokens WHERE case_id=%s;", (case_id,))
            cur.execute("DELETE FROM practice_sessions WHERE case_id=%s;", (case_id,))
            if guest_ids:
                cur.execute("DELETE FROM sessions WHERE user_id = ANY(%s);", (guest_ids,))
                cur.execute("DELETE FROM users WHERE id = ANY(%s);", (guest_ids,))
            cur.execute("DELETE FROM cases WHERE id=%s;", (case_id,))


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestGuestClaim(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        cls.SESSION_COOKIE_NAME = SESSION_COOKIE_NAME

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email='b@yale.edu';")
                cls.bid = cur.fetchone()[0]
                # Dedicated case so guest sessions here never collide with the
                # seeded dummy or other B2 files (re-runnable teardown below).
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('B2 Guest Claim Case', 'b2 guest claim case', 'DevSchool',"
                    " 2098, 'Technology', 'Profitability', 'Easy', 2.0, 2,"
                    " 'output/cases/devschool/dev-dummy-case.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]

        # Bob (candidate) logs in to create open-link proposals.
        cls.bob = TestClient(app)
        cls.bob.cookies.set(SESSION_COOKIE_NAME,
                            create_session(cls.bid, user_agent="b2-test").id)

    @classmethod
    def tearDownClass(cls):
        _cleanup_case(cls.case_id)
        cls._ctx.__exit__(None, None, None)

    def _mk_open_now_case(self) -> str:
        """Bob (candidate) opens a case-set 'now' link — the claimer becomes
        the interviewer and the session is auto-created (B1 DD-1)."""
        r = self.bob.post("/api/proposals", json={
            "from_role": "candidate", "case_id": self.case_id})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["claim_token"]

    def test_unauth_proposal_claim_mints_guest_interviewer(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        tok = self._mk_open_now_case()

        anon = TestClient(app)
        r = anon.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertTrue(body["accepted"])
        sid = body["session_id"]
        self.assertIsNotNone(sid)
        # A guest session cookie was minted.
        self.assertIn(self.SESSION_COOKIE_NAME, anon.cookies)

        # The guest is the interviewer and can read its own session.
        gr = anon.get(f"/api/practice/{sid}")
        self.assertEqual(gr.status_code, 200, gr.text)
        self.assertEqual(gr.json()["your_role"], "interviewer")

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT interviewer_id FROM practice_sessions WHERE id=%s;", (sid,))
                iv_id = cur.fetchone()[0]
                cur.execute("SELECT is_guest, email FROM users WHERE id=%s;", (iv_id,))
                is_guest, email = cur.fetchone()
        self.assertTrue(is_guest)
        self.assertIsNone(email)

    def test_authenticated_claim_still_works_for_real_user(self):
        # Regression: a real logged-in user claiming is unchanged.
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email='c@yale.edu';")
                cid = cur.fetchone()[0]
        cara = TestClient(app)
        cara.cookies.set(SESSION_COOKIE_NAME, create_session(cid, user_agent="b2-test").id)
        tok = self._mk_open_now_case()
        r = cara.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)

    def test_guest_cannot_reclaim_a_second_link(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        tok1 = self._mk_open_now_case()
        anon = TestClient(app)
        self.assertEqual(anon.post(f"/api/proposals/claim/{tok1}").status_code, 200)
        # Same guest cookie, a different open link → 403 (scoped to one session).
        tok2 = self._mk_open_now_case()
        r = anon.post(f"/api/proposals/claim/{tok2}")
        self.assertEqual(r.status_code, 403, r.text)

    def test_unauth_pair_claim_mints_guest(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        mint = self.bob.post("/api/practice/pair/create", json={"case_id": self.case_id})
        self.assertEqual(mint.status_code, 200, mint.text)
        token = mint.json()["token"]
        anon = TestClient(app)
        r = anon.post("/api/practice/pair/claim", json={"token": token})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn(self.SESSION_COOKIE_NAME, anon.cookies)

    def test_guest_interviewer_claim_sends_no_invite_to_null_email(self):
        # NULL-email guard: the guest-interviewer claim must not blow up on
        # the invite path, and the guest can still fetch its own .ics.
        from fastapi.testclient import TestClient
        from webapp.main import app
        tok = self._mk_open_now_case()
        anon = TestClient(app)
        r = anon.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(r.status_code, 200, r.text)
        sid = r.json()["session_id"]
        ics = anon.get(f"/ics/session-{sid}.ics")
        self.assertEqual(ics.status_code, 200, ics.text)

    def test_claim_nulls_dead_claim_token(self):
        # B1 report N-1 (lands in B2 scope): claiming nulls the now-dead
        # claim_token so it never surfaces on the claimed row / in the inbox.
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from datetime import datetime, timedelta, timezone
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email='c@yale.edu';")
                cid = cur.fetchone()[0]
        cara = TestClient(app)
        cara.cookies.set(SESSION_COOKIE_NAME, create_session(cid, user_agent="b2-test").id)
        future = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        tok = self.bob.post("/api/proposals", json={
            "from_role": "candidate", "case_id": self.case_id,
            "proposed_times": [future]}).json()["claim_token"]
        res = cara.post(f"/api/proposals/claim/{tok}")
        self.assertEqual(res.status_code, 200, res.text)
        pid = res.json()["proposal_id"]
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT claim_token FROM proposals WHERE id=%s;", (pid,))
                self.assertIsNone(cur.fetchone()[0])

    def test_failed_proposal_claim_leaves_no_orphan_guest(self):
        # Unauthenticated bad-token claim must not persist a guest user/session.
        from fastapi.testclient import TestClient
        from webapp.main import app
        import psycopg
        def _counts():
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT count(*) FROM users WHERE is_guest;")
                    g = cur.fetchone()[0]
                    cur.execute("SELECT count(*) FROM sessions;")
                    s = cur.fetchone()[0]
            return g, s
        before = _counts()
        r = TestClient(app).post("/api/proposals/claim/nope-nope-nope")
        self.assertEqual(r.status_code, 404, r.text)
        self.assertEqual(_counts(), before)

    def test_failed_pair_claim_leaves_no_orphan_guest(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        import psycopg
        def _gcount():
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT count(*) FROM users WHERE is_guest;")
                    return cur.fetchone()[0]
        before = _gcount()
        r = TestClient(app).post("/api/practice/pair/claim", json={})
        self.assertEqual(r.status_code, 422, r.text)
        self.assertEqual(_gcount(), before)


if __name__ == "__main__":
    unittest.main()
