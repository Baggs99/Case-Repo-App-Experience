"""B3 Task 7: role swap. Needs seeded dev Postgres."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
from tests.test_b3_recap_gate import _seed_finalized_session, _purge_session


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestSwap(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()   # interviewer of the finished session
        cls.bob = TestClient(app)          # candidate
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE email = ANY(%s) ORDER BY email;",
                        (["a@yale.edu", "b@yale.edu"],))
            cls.aid, cls.bid = (r[0] for r in cur.fetchall())
        for c, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
            s = create_session(uid, user_agent="b3", ip_address=None)
            c.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def _finished(self):
        sid, cid = _seed_finalized_session(self.aid, self.bid, "B3 Swap Src")
        # ensure Bob's recap is closed so a later swap can be gated cleanly
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("UPDATE feedback SET closed_at = NOW(), case_rating = 5"
                        " WHERE session_id = %s;", (sid,))
        self.addCleanup(self._drop, sid, cid)
        return sid

    def test_interviewer_swaps_roles_reversed(self):
        sid = self._finished()
        r = self.alice.post(f"/api/practice/{sid}/swap")
        self.assertEqual(r.status_code, 200, r.text)
        r = self.bob.post(f"/api/practice/{sid}/swap/accept")
        self.assertEqual(r.status_code, 200, r.text)
        new_sid = r.json()["session_id"]
        self.addCleanup(self._drop, new_sid, None)
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT interviewer_id, candidate_id, state, mode,"
                        " swapped_from_session_id FROM practice_sessions WHERE id = %s;",
                        (new_sid,))
            ivr, cand, state, mode, frm = cur.fetchone()
        self.assertEqual((ivr, cand), (self.bid, self.aid))   # reversed
        self.assertEqual(state, "negotiating")
        self.assertEqual(frm, sid)

    def test_candidate_cannot_initiate(self):
        sid = self._finished()
        r = self.bob.post(f"/api/practice/{sid}/swap")
        self.assertEqual(r.status_code, 403, r.text)

    def test_swap_gate_blocks_new_candidate(self):
        # Alice (who will become the NEW candidate) has her own open recap.
        blk_sid, blk_cid = _seed_finalized_session(self.bid, self.aid, "B3 Swap Gate")
        self.addCleanup(self._drop, blk_sid, blk_cid)   # Alice is candidate here → open recap
        sid = self._finished()
        self.alice.post(f"/api/practice/{sid}/swap")
        r = self.bob.post(f"/api/practice/{sid}/swap/accept")
        self.assertEqual(r.status_code, 409, r.text)
        self.assertEqual(r.json()["detail"]["blocked_by_recap"], blk_sid)

    def test_claim_invite_single_winner(self):
        from webapp.repositories import swaps as swap_repo
        sid = self._finished()
        self.alice.post(f"/api/practice/{sid}/swap")   # creates a pending invite
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id, invitee_id FROM swap_invites"
                        " WHERE from_session_id = %s AND state='pending';", (sid,))
            invite_id, invitee_id = cur.fetchone()
        self.assertTrue(swap_repo.claim_invite(invite_id, invitee_id))    # first wins
        self.assertFalse(swap_repo.claim_invite(invite_id, invitee_id))   # second loses

    def _drop(self, sid, cid):
        import psycopg
        # Purge any session swapped FROM this one first (new_session_id/swapped_from
        # are ON DELETE SET NULL, so order is not FK-critical, but keep it tidy).
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("SELECT id FROM practice_sessions WHERE swapped_from_session_id = %s;", (sid,))
            children = [r[0] for r in cur.fetchall()]
        for child in children:
            _purge_session(child)
        _purge_session(sid)
        if cid:
            with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
                cur.execute("DELETE FROM cases WHERE id = %s;", (cid,))
