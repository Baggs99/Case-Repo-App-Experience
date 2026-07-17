"""
B2 Task 5: POST /api/v1/auth/upgrade converts a guest to a real account in
place — history FKs intact, cookie now authenticates a real user, previously
403'd endpoints open. Needs seeded dev Postgres + migration 025 — skips
otherwise.
"""

from __future__ import annotations

import unittest
import uuid

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
class TestGuestUpgrade(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        cls.app = app
        cls.SESSION_COOKIE_NAME = SESSION_COOKIE_NAME
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email='b@yale.edu';")
                cls.bid = cur.fetchone()[0]
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('B2 Guest Upgrade Case', 'b2 guest upgrade case', 'DevSchool',"
                    " 2100, 'Technology', 'Profitability', 'Easy', 2.0, 2,"
                    " 'output/cases/devschool/dev-dummy-case.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.bob = TestClient(app)
        cls.bob.cookies.set(SESSION_COOKIE_NAME,
                            create_session(cls.bid, user_agent="b2-test").id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        _cleanup_case(cls.case_id)  # removes case sessions first (frees FKs)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email LIKE %s;",
                            ("grad-%@yale.edu",))
                ids = [r[0] for r in cur.fetchall()]
                if ids:
                    cur.execute("DELETE FROM sessions WHERE user_id = ANY(%s);", (ids,))
                    cur.execute("DELETE FROM users WHERE id = ANY(%s);", (ids,))
        cls._ctx.__exit__(None, None, None)

    def _fresh_email(self):
        return f"grad-{uuid.uuid4().hex[:10]}@yale.edu"

    def _new_guest_with_session(self):
        from fastapi.testclient import TestClient
        tok = self.bob.post("/api/proposals", json={
            "from_role": "candidate", "case_id": self.case_id}).json()["claim_token"]
        guest = TestClient(self.app)
        sid = guest.post(f"/api/proposals/claim/{tok}").json()["session_id"]
        return guest, sid

    def test_upgrade_happy_path_keeps_history_and_opens_endpoints(self):
        guest, sid = self._new_guest_with_session()
        # Before upgrade: guest is 403 on /me.
        self.assertEqual(guest.get("/api/v1/me").status_code, 403)
        email = self._fresh_email()
        r = guest.post("/api/v1/auth/upgrade", json={"email": email, "password": "correct horse battery staple"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertTrue(r.json()["upgraded"])
        self.assertEqual(r.json()["email"], email)
        # After upgrade: same cookie now authenticates a real user.
        me = guest.get("/api/v1/me")
        self.assertEqual(me.status_code, 200, me.text)
        # History FK intact: the guest's finalized-or-not session still lists them.
        s = guest.get(f"/api/practice/{sid}")
        self.assertEqual(s.status_code, 200, s.text)
        self.assertEqual(s.json()["your_role"], "interviewer")
        self.assertFalse(s.json()["interviewer_is_guest"])

    def test_second_upgrade_rejected_as_real_user(self):
        # After the first upgrade, the SAME cookie now resolves to a real
        # (is_guest=FALSE) user, so require_guest rejects the second call with
        # 403 before the handler runs. (The genuine concurrent-race path — two
        # requests both seeing is_guest=TRUE — returns 409 via GuestUpgradeConflict
        # and is proven at the repo level in test_b2_guest_crud.)
        guest, _ = self._new_guest_with_session()
        self.assertEqual(guest.post("/api/v1/auth/upgrade",
                         json={"email": self._fresh_email(), "password": "correct horse battery staple"}).status_code, 200)
        r = guest.post("/api/v1/auth/upgrade",
                       json={"email": self._fresh_email(), "password": "correct horse battery staple"})
        self.assertEqual(r.status_code, 403, r.text)

    def test_upgrade_bad_domain_rejected(self):
        guest, _ = self._new_guest_with_session()
        r = guest.post("/api/v1/auth/upgrade",
                       json={"email": "someone@gmail.com", "password": "correct horse battery staple"})
        self.assertEqual(r.status_code, 400, r.text)

    def test_upgrade_taken_email_conflicts(self):
        guest, _ = self._new_guest_with_session()
        r = guest.post("/api/v1/auth/upgrade",
                       json={"email": "a@yale.edu", "password": "correct horse battery staple"})
        self.assertEqual(r.status_code, 409, r.text)

    def test_non_guest_cannot_upgrade(self):
        r = self.bob.post("/api/v1/auth/upgrade",
                          json={"email": self._fresh_email(), "password": "correct horse battery staple"})
        self.assertEqual(r.status_code, 403, r.text)

    def test_unauthenticated_upgrade_401(self):
        from fastapi.testclient import TestClient
        r = TestClient(self.app).post("/api/v1/auth/upgrade",
                                      json={"email": self._fresh_email(), "password": "correct horse battery staple"})
        self.assertEqual(r.status_code, 401, r.text)


if __name__ == "__main__":
    unittest.main()
