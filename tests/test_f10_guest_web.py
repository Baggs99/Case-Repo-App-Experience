"""
F10 Task 1: the guest link-gate (/g/claim/{token}) — GET renders the 8a gate
bound to a real open, instant, candidate-role, case-set proposal; POST claims
it (minting a guest when unauthenticated) and 303-redirects to the console.
Follows the login/cookie + open-link idiom of tests/test_b1_proposals_open.py.
"""

from __future__ import annotations

import unittest
import uuid
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


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestGuestConsole(unittest.TestCase):
    """F10 Task 2 — /g/session/{id}: drives the VERIFIED practice-session
    lifecycle through the real endpoints (no mocking) to reach `finalized`,
    and the IDOR/participant-gating around it."""

    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._alice_ctx = TestClient(app)
        cls.alice = cls._alice_ctx.__enter__()   # a@yale.edu — candidate on the main session
        cls._bob_ctx = TestClient(app)
        cls.bob = cls._bob_ctx.__enter__()       # b@yale.edu — candidate on the unrelated session
        cls._carol_ctx = TestClient(app)
        cls.carol = cls._carol_ctx.__enter__()   # c@yale.edu — real non-participant probe

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES ('F10 Console Case', 'f10 console case',"
                    " 'DevSchool', 2091, 'Technology', 'Profitability', 'Easy', 3.0,"
                    " 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.aid, cls.bid, cls.cid = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]

        # One exhibit on the new case (M2's manifest needs a row to alias);
        # create_reveal only inserts a DB row (no blob read), so a dummy
        # enc_blob_path/key/iv is enough to exercise the release endpoint.
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO case_exhibits (case_id, idx, source_pages, enc_blob_path,"
                    " enc_key, enc_iv, width, height, bytes, created_by)"
                    " VALUES (%s, 1, '1', 'f10-console-dummy.bin', %s, %s, 800, 600, 100, %s)"
                    " RETURNING id;",
                    (cls.case_id, b"\x00" * 32, b"\x00" * 12, cls.aid),
                )
                cls.exhibit_id = cur.fetchone()[0]

        for user_id, ctx in ((cls.aid, cls.alice), (cls.bid, cls.bob), (cls.cid, cls.carol)):
            s = create_session(user_id, user_agent="f10-test", ip_address=None)
            ctx.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM proposals WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM case_exhibits WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._alice_ctx.__exit__(None, None, None)
        cls._bob_ctx.__exit__(None, None, None)
        cls._carol_ctx.__exit__(None, None, None)

    # ── helpers ──────────────────────────────────────────────────────────────

    def _mk_open(self, poster_ctx, case_id=None):
        """poster_ctx posts an open, instant, candidate-role proposal — the
        gate's SQL restriction means whoever claims it becomes interviewer."""
        payload = {"case_id": case_id if case_id is not None else self.case_id,
                   "from_role": "candidate"}
        r = poster_ctx.post("/api/proposals", json=payload)
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["claim_token"]

    def _claim_as_guest(self, token):
        from fastapi.testclient import TestClient
        from webapp.main import app
        anon = TestClient(app, follow_redirects=False)
        r = anon.post(f"/g/claim/{token}", headers={"Origin": "http://testserver"})
        self.assertEqual(r.status_code, 303, r.text)
        session_id = int(r.headers["location"].rsplit("/", 1)[1])
        return anon, session_id

    def _guest_id_for(self, session_id):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT interviewer_id FROM practice_sessions WHERE id = %s;",
                        (session_id,))
            return cur.fetchone()[0]

    def _cleanup_session(self, guest_id, session_id):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # burned has no ON DELETE CASCADE from practice_sessions — drop
                # it first or a finalized session's row blocks the delete.
                # feedback/reveals DO cascade off practice_sessions.
                cur.execute("DELETE FROM burned WHERE session_id = %s;", (session_id,))
                cur.execute("DELETE FROM proposals WHERE session_id = %s;", (session_id,))
                cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (session_id,))
                cur.execute("DELETE FROM sessions WHERE user_id = %s;", (guest_id,))
                cur.execute("DELETE FROM users WHERE id = %s AND is_guest = TRUE;", (guest_id,))

    # ── GET /g/session/{id} — render + gating ───────────────────────────────

    def test_console_200_with_exhibit_markup(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        try:
            r = guest.get(f"/g/session/{sid}")
            self.assertEqual(r.status_code, 200, r.text)
            self.assertIn("GUEST CONSOLE", r.text)
            self.assertIn("READ ALOUD", r.text)
            self.assertIn('id="g-end"', r.text)
            self.assertIn('id="g-release"', r.text)
        finally:
            self._cleanup_session(self._guest_id_for(sid), sid)

    def test_console_renders_without_exhibits(self):
        # Case 1 (seed) carries no case_exhibits row — the exhibit row must
        # be guarded, not a KeyError/500.
        tok = self._mk_open(self.alice, case_id=1)
        guest, sid = self._claim_as_guest(tok)
        try:
            r = guest.get(f"/g/session/{sid}")
            self.assertEqual(r.status_code, 200, r.text)
            self.assertIn("GUEST CONSOLE", r.text)
            self.assertNotIn('id="g-release"', r.text)
        finally:
            self._cleanup_session(self._guest_id_for(sid), sid)

    def test_idor_guest_403_on_unrelated_session(self):
        tok1 = self._mk_open(self.alice)
        guest1, sid1 = self._claim_as_guest(tok1)
        tok2 = self._mk_open(self.bob)
        guest2, sid2 = self._claim_as_guest(tok2)
        try:
            r = guest1.get(f"/g/session/{sid2}")
            self.assertEqual(r.status_code, 403, r.text)
        finally:
            self._cleanup_session(self._guest_id_for(sid1), sid1)
            self._cleanup_session(self._guest_id_for(sid2), sid2)

    def test_real_non_participant_404(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        try:
            r = self.carol.get(f"/g/session/{sid}")
            self.assertEqual(r.status_code, 404, r.text)
        finally:
            self._cleanup_session(self._guest_id_for(sid), sid)

    def test_candidate_seat_redirects_to_authed_call_page(self):
        # Alice is the candidate on the guest-claimed session — the console
        # is interviewer-only; her seat lives at the authed call page.
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        try:
            r = self.alice.get(f"/g/session/{sid}", follow_redirects=False)
            self.assertEqual(r.status_code, 303, r.text)
            self.assertEqual(r.headers["location"], f"/session/{sid}")
        finally:
            self._cleanup_session(self._guest_id_for(sid), sid)

    # ── Full lifecycle: scheduled → … → finalized → /keep redirect ─────────

    def test_lifecycle_to_finalized_then_keep_redirect(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        origin = {"Origin": "http://testserver"}
        try:
            r = guest.post(f"/api/practice/{sid}/consent", json={"consent": True},
                           headers=origin)
            self.assertEqual(r.status_code, 200, r.text)
            r = guest.post(f"/api/practice/{sid}/state", json={"target": "lobby"},
                           headers=origin)
            self.assertEqual(r.status_code, 200, r.text)

            # Candidate (Alice, her own cookie) consents from her side.
            r = self.alice.post(f"/api/practice/{sid}/consent", json={"consent": True},
                                headers=origin)
            self.assertEqual(r.status_code, 200, r.text)

            # INV-10: both consents now true — interviewer may go live.
            r = guest.post(f"/api/practice/{sid}/state", json={"target": "live"},
                           headers=origin)
            self.assertEqual(r.status_code, 200, r.text)
            self.assertIsNotNone(r.json()["started_at"])

            r = guest.post(f"/api/practice/{sid}/reveals",
                           json={"exhibit_id": self.exhibit_id}, headers=origin)
            self.assertEqual(r.status_code, 200, r.text)

            r = guest.post(f"/api/practice/{sid}/state", json={"target": "debrief"},
                           headers=origin)
            self.assertEqual(r.status_code, 200, r.text)

            r = guest.post(f"/api/practice/{sid}/finalize", json={"grade": 4},
                           headers=origin)
            self.assertEqual(r.status_code, 200, r.text)
            # M2 — regression guard for DV-F10-3: a scored finalize must never
            # silently record a computed 0.0 (the console's End action always
            # carries an explicit 1-5 grade).
            self.assertEqual(r.json()["grade"], 4.0)

            r = guest.get(f"/api/practice/{sid}")
            self.assertEqual(r.status_code, 200, r.text)
            self.assertEqual(r.json()["state"], "finalized")

            r = guest.get(f"/g/session/{sid}", follow_redirects=False)
            self.assertEqual(r.status_code, 303, r.text)
            self.assertEqual(r.headers["location"], f"/g/session/{sid}/keep")
        finally:
            self._cleanup_session(self._guest_id_for(sid), sid)


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestGuestKeepUpgrade(unittest.TestCase):
    """F10 Task 3 — /g/session/{id}/keep (gIsPost), the existing
    /api/v1/auth/upgrade consumed by its inline JS, and /g/session/{id}/saved
    (gIsMade / the honest 'not now' close state)."""

    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._alice_ctx = TestClient(app)
        cls.alice = cls._alice_ctx.__enter__()   # a@yale.edu — candidate poster (guest scenarios)
        cls._bob_ctx = TestClient(app)
        cls.bob = cls._bob_ctx.__enter__()       # b@yale.edu — real (non-guest) claimer
        cls._carol_ctx = TestClient(app)
        cls.carol = cls._carol_ctx.__enter__()   # c@yale.edu — candidate poster (non-guest scenario)

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path) VALUES ('F10 Keep Case', 'f10 keep case',"
                    " 'DevSchool', 2091, 'Technology', 'Profitability', 'Easy', 3.0,"
                    " 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.aid, cls.bid, cls.cid = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]

        for user_id, ctx in ((cls.aid, cls.alice), (cls.bid, cls.bob), (cls.cid, cls.carol)):
            s = create_session(user_id, user_agent="f10-test", ip_address=None)
            ctx.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM proposals WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._alice_ctx.__exit__(None, None, None)
        cls._bob_ctx.__exit__(None, None, None)
        cls._carol_ctx.__exit__(None, None, None)

    # ── helpers ──────────────────────────────────────────────────────────────

    def _mk_open(self, poster_ctx):
        """poster_ctx posts an open, instant, candidate-role proposal — the
        gate's SQL restriction means whoever claims it becomes interviewer."""
        payload = {"case_id": self.case_id, "from_role": "candidate"}
        r = poster_ctx.post("/api/proposals", json=payload)
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["claim_token"]

    def _claim_as_guest(self, token):
        from fastapi.testclient import TestClient
        from webapp.main import app
        anon = TestClient(app, follow_redirects=False)
        r = anon.post(f"/g/claim/{token}", headers={"Origin": "http://testserver"})
        self.assertEqual(r.status_code, 303, r.text)
        session_id = int(r.headers["location"].rsplit("/", 1)[1])
        return anon, session_id

    def _guest_id_for(self, session_id):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT interviewer_id FROM practice_sessions WHERE id = %s;",
                        (session_id,))
            return cur.fetchone()[0]

    def _drive_to_finalized(self, interviewer_ctx, candidate_ctx, session_id, grade=4):
        """Drives the VERIFIED lifecycle (see plan's Key data facts) to
        `finalized` via the real endpoints — no mocking, no exhibit release
        (not required to reach finalize)."""
        origin = {"Origin": "http://testserver"}
        r = interviewer_ctx.post(f"/api/practice/{session_id}/consent",
                                 json={"consent": True}, headers=origin)
        self.assertEqual(r.status_code, 200, r.text)
        r = interviewer_ctx.post(f"/api/practice/{session_id}/state",
                                 json={"target": "lobby"}, headers=origin)
        self.assertEqual(r.status_code, 200, r.text)
        r = candidate_ctx.post(f"/api/practice/{session_id}/consent",
                               json={"consent": True}, headers=origin)
        self.assertEqual(r.status_code, 200, r.text)
        r = interviewer_ctx.post(f"/api/practice/{session_id}/state",
                                 json={"target": "live"}, headers=origin)
        self.assertEqual(r.status_code, 200, r.text)
        r = interviewer_ctx.post(f"/api/practice/{session_id}/state",
                                 json={"target": "debrief"}, headers=origin)
        self.assertEqual(r.status_code, 200, r.text)
        r = interviewer_ctx.post(f"/api/practice/{session_id}/finalize",
                                 json={"grade": grade}, headers=origin)
        self.assertEqual(r.status_code, 200, r.text)

    def _cleanup_guest_session(self, guest_id, session_id):
        """Unconditional user delete (not `AND is_guest = TRUE`): a session
        that reached the upgrade happy path has already flipped is_guest to
        FALSE, and this id was only ever minted for this one test."""
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM burned WHERE session_id = %s;", (session_id,))
                cur.execute("DELETE FROM proposals WHERE session_id = %s;", (session_id,))
                cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (session_id,))
                cur.execute("DELETE FROM sessions WHERE user_id = %s;", (guest_id,))
                cur.execute("DELETE FROM users WHERE id = %s;", (guest_id,))

    def _cleanup_real_session(self, session_id):
        """Session driven by the seeded, persistent b/c users — drop only the
        session-scoped rows, never their users/sessions rows (reused by every
        test in this class)."""
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM burned WHERE session_id = %s;", (session_id,))
                cur.execute("DELETE FROM proposals WHERE session_id = %s;", (session_id,))
                cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (session_id,))

    # ── GET /g/session/{id}/keep ─────────────────────────────────────────────

    def test_keep_before_finalize_redirects_to_console(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        try:
            r = guest.get(f"/g/session/{sid}/keep", follow_redirects=False)
            self.assertEqual(r.status_code, 303, r.text)
            self.assertEqual(r.headers["location"], f"/g/session/{sid}")
        finally:
            self._cleanup_guest_session(self._guest_id_for(sid), sid)

    def test_keep_after_finalize_guest_shows_upgrade_ask(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        try:
            self._drive_to_finalized(guest, self.alice, sid)
            r = guest.get(f"/g/session/{sid}/keep")
            self.assertEqual(r.status_code, 200, r.text)
            self.assertIn("Keep this session on a record?", r.text)
            self.assertIn("Create an account", r.text)
            import psycopg
            with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
                cur.execute("SELECT COALESCE(display_name, split_part(email, '@', 1))"
                            " FROM users WHERE id = %s;", (self.aid,))
                peer_name = cur.fetchone()[0]
            self.assertIn(f"FEEDBACK SENT — {peer_name.upper()} HAS IT", r.text)
        finally:
            self._cleanup_guest_session(self._guest_id_for(sid), sid)

    def test_non_guest_claimer_sees_saved_variant(self):
        # Carol posts as candidate; Bob (already logged in, not a guest)
        # claims the link — the "already on the record" branch (no upgrade
        # form, login variant of the gate not designed per canvas note).
        tok = self._mk_open(self.carol)
        r = self.bob.post(f"/g/claim/{tok}", headers={"Origin": "http://testserver"},
                          follow_redirects=False)
        self.assertEqual(r.status_code, 303, r.text)
        sid = int(r.headers["location"].rsplit("/", 1)[1])
        try:
            self._drive_to_finalized(self.bob, self.carol, sid)
            r = self.bob.get(f"/g/session/{sid}/keep")
            self.assertEqual(r.status_code, 200, r.text)
            self.assertIn("Saved to your record.", r.text)
            self.assertNotIn("Create an account", r.text)
        finally:
            self._cleanup_real_session(sid)

    # ── POST /api/v1/auth/upgrade (existing endpoint, consumed by keep's JS) ──

    def test_upgrade_happy_path_flips_is_guest_then_saved_shows_on_record(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        guest_id = self._guest_id_for(sid)
        email = f"guestkeep+{uuid.uuid4().hex[:12]}@yale.edu"
        try:
            self._drive_to_finalized(guest, self.alice, sid)
            r = guest.post("/api/v1/auth/upgrade",
                           json={"email": email, "password": "correct horse battery staple"},
                           headers={"Origin": "http://testserver"})
            self.assertEqual(r.status_code, 200, r.text)
            self.assertTrue(r.json()["upgraded"])
            self.assertEqual(r.json()["user_id"], guest_id)

            import psycopg
            with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
                cur.execute("SELECT is_guest FROM users WHERE id = %s;", (guest_id,))
                self.assertFalse(cur.fetchone()[0])

            r = guest.get(f"/g/session/{sid}/saved")
            self.assertEqual(r.status_code, 200, r.text)
            self.assertIn("On the record.", r.text)
        finally:
            self._cleanup_guest_session(guest_id, sid)

    def test_upgrade_bad_domain_400(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        try:
            r = guest.post("/api/v1/auth/upgrade",
                           json={"email": "foo@gmail.com", "password": "correct horse battery staple"},
                           headers={"Origin": "http://testserver"})
            self.assertEqual(r.status_code, 400, r.text)
            self.assertTrue(r.json()["detail"])  # B2's message surfaces to #up-err
        finally:
            self._cleanup_guest_session(self._guest_id_for(sid), sid)

    # ── GET /g/session/{id}/saved ─────────────────────────────────────────────

    def test_saved_guest1_shows_not_now_copy(self):
        tok = self._mk_open(self.alice)
        guest, sid = self._claim_as_guest(tok)
        try:
            r = guest.get(f"/g/session/{sid}/saved?guest=1")
            self.assertEqual(r.status_code, 200, r.text)
            self.assertIn("Kept for now.", r.text)
            self.assertNotIn("On the record.", r.text)
        finally:
            self._cleanup_guest_session(self._guest_id_for(sid), sid)


if __name__ == "__main__":
    unittest.main()
