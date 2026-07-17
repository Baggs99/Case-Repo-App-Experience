"""
B2 Task 4: guest cookie scoping — a guest drives its own session's endpoints
(incl. finalize, name renders 'Guest') and is 403'd on every other session
and every non-session /api endpoint (IDOR surface). Needs seeded dev Postgres
+ migration 025 — skips otherwise.
"""

from __future__ import annotations

import unittest

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
class TestGuestScoping(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg

        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        cls.SESSION_COOKIE_NAME = SESSION_COOKIE_NAME
        cls.app = app

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                for e in ("a@yale.edu", "b@yale.edu", "c@yale.edu"):
                    cur.execute("SELECT id FROM users WHERE email=%s;", (e,))
                    setattr(cls, {"a@yale.edu": "aid", "b@yale.edu": "bid",
                                  "c@yale.edu": "cid"}[e], cur.fetchone()[0])
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('B2 Guest Scoping Case', 'b2 guest scoping case', 'DevSchool',"
                    " 2099, 'Technology', 'Profitability', 'Easy', 2.0, 2,"
                    " 'output/cases/devschool/dev-dummy-case.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]

        cls.bob = TestClient(app)  # candidate who opens links
        cls.bob.cookies.set(SESSION_COOKIE_NAME,
                            create_session(cls.bid, user_agent="b2-test").id)

        # Guest interviewer session, via a case-set 'now' open link.
        tok = cls.bob.post("/api/proposals", json={
            "from_role": "candidate", "case_id": cls.case_id}).json()["claim_token"]
        cls.guest = TestClient(app)
        claim = cls.guest.post(f"/api/proposals/claim/{tok}")
        cls.guest_session_id = claim.json()["session_id"]

        # A foreign session between two real users (guest is NOT a participant).
        cls.foreign_session_id = cls._create_real_session(cls.aid, cls.cid)

    @classmethod
    def tearDownClass(cls):
        _cleanup_case(cls.case_id)
        cls._ctx.__exit__(None, None, None)

    @classmethod
    def _create_real_session(cls, interviewer_id, candidate_id):
        from webapp.repositories.practice_sessions import create_practice_session
        s = create_practice_session(interviewer_id=interviewer_id,
                                     candidate_id=candidate_id, case_id=cls.case_id)
        return s["id"]

    def _fresh_guest_session(self):
        """A brand-new guest-interviewer session (Bob = candidate), isolated so
        state mutation doesn't leak into the shared read-only fixtures."""
        from fastapi.testclient import TestClient
        tok = self.bob.post("/api/proposals", json={
            "from_role": "candidate", "case_id": self.case_id}).json()["claim_token"]
        guest = TestClient(self.app)
        sid = guest.post(f"/api/proposals/claim/{tok}").json()["session_id"]
        return guest, sid

    # ---- guest drives its OWN session ---------------------------------------

    def test_guest_reads_own_session_and_sees_is_guest_flag(self):
        r = self.guest.get(f"/api/practice/{self.guest_session_id}")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["your_role"], "interviewer")
        self.assertTrue(body["interviewer_is_guest"])
        self.assertFalse(body["candidate_is_guest"])
        self.assertEqual(body["interviewer_name"], "Guest")

    def test_guest_can_run_session_through_finalize(self):
        # Fresh isolated session (Bob = candidate). join-config, draft rubric,
        # both consents (INV-10: no going live without both), drive states,
        # finalize as the guest interviewer.
        guest, sid = self._fresh_guest_session()
        self.assertEqual(guest.get(f"/api/practice/{sid}/join-config").status_code, 200)
        # Interviewer-only rubric read is reachable by the guest interviewer.
        self.assertEqual(guest.get(f"/api/practice/{sid}/rubric").status_code, 200)
        self.assertEqual(guest.post(f"/api/practice/{sid}/state",
                                    json={"target": "lobby"}).status_code, 200)
        # Interviewer (guest) + candidate (Bob) both consent while in lobby.
        self.assertEqual(guest.post(f"/api/practice/{sid}/consent",
                                    json={"consent": True}).status_code, 200)
        self.assertEqual(self.bob.post(f"/api/practice/{sid}/consent",
                                       json={"consent": True}).status_code, 200)
        for target in ("live", "debrief"):
            r = guest.post(f"/api/practice/{sid}/state", json={"target": target})
            self.assertEqual(r.status_code, 200, r.text)
        fin = guest.post(f"/api/practice/{sid}/finalize", json={})
        self.assertEqual(fin.status_code, 200, fin.text)
        self.assertTrue(fin.json()["finalized"])

    # ---- guest is 403'd on OTHER sessions (IDOR) ----------------------------

    def test_guest_403_on_foreign_session_endpoints(self):
        fid = self.foreign_session_id
        for method, path in [
            ("get", f"/api/practice/{fid}"),
            ("get", f"/api/practice/{fid}/join-config"),
            ("get", f"/api/practice/{fid}/reveals"),
            ("get", f"/api/practice/{fid}/recordings"),
            ("get", f"/api/practice/{fid}/feedback"),
        ]:
            r = getattr(self.guest, method)(path)
            self.assertEqual(r.status_code, 403, f"{method} {path} -> {r.status_code}")

    # ---- guest is 403'd on NON-session endpoints ----------------------------

    def test_guest_403_on_non_session_endpoints(self):
        for path in ["/api/v1/me", "/api/v1/dashboard", "/api/v1/cases",
                     "/api/v1/proposals", "/api/v1/availability", "/api/v1/drills/daily"]:
            r = self.guest.get(path)
            self.assertEqual(r.status_code, 403, f"{path} -> {r.status_code}")

    # ---- real users unaffected ---------------------------------------------

    def test_real_nonparticipant_still_404_not_403(self):
        # Regression: require_session_participant must not change real-user 404.
        from fastapi.testclient import TestClient
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        cara = TestClient(self.app)
        cara.cookies.set(SESSION_COOKIE_NAME, create_session(self.cid, user_agent="b2-test").id)
        # Cara is not in the guest's session.
        r = cara.get(f"/api/practice/{self.guest_session_id}")
        self.assertEqual(r.status_code, 404, r.text)

    def test_guest_ws_scoping(self):
        from starlette.websockets import WebSocketDisconnect
        # Own session: handshake accepted.
        with self.guest.websocket_connect(f"/ws/practice/{self.guest_session_id}") as ws:
            ws.close()
        # Foreign session: rejected.
        with self.assertRaises(WebSocketDisconnect):
            with self.guest.websocket_connect(f"/ws/practice/{self.foreign_session_id}"):
                pass


if __name__ == "__main__":
    unittest.main()
