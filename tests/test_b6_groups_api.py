"""B6 Task 5: groups API — create/join/leave/transfer, detail+leaderboard,
admin-only progress, auth + IDOR + same-origin. Needs seeded Postgres + httpx."""

from __future__ import annotations

import unittest

from tests.test_b6_connections_api import _assert_no_counts
from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestGroupsApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)
        cls.cara = TestClient(app)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.a, cls.b, cls.c = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]
        for client, uid in ((cls.alice, cls.a), (cls.bob, cls.b), (cls.cara, cls.c)):
            s = create_session(uid, user_agent="b6-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM groups WHERE created_by = ANY(%s);",
                            ([self.a, self.b, self.c],))

    def _create(self, client, name="Cohort C-14"):
        r = client.post("/api/v1/groups", json={"name": name})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def test_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        self.assertEqual(TestClient(app).get("/api/v1/groups").status_code, 401)

    def test_cross_origin_rejected(self):
        r = self.alice.post("/api/v1/groups", json={"name": "X"},
                            headers={"Origin": "http://evil.example"})
        self.assertEqual(r.status_code, 403)

    def test_create_blank_name_422(self):
        self.assertEqual(self.alice.post("/api/v1/groups", json={"name": "  "}).status_code, 422)

    def test_create_join_detail(self):
        g = self._create(self.alice)
        self.assertEqual(g["role"], "admin")
        j = self.bob.post("/api/v1/groups/join", json={"invite_code": g["invite_code"]})
        self.assertEqual(j.status_code, 200, j.text)
        self.assertFalse(j.json()["already_member"])
        self.assertEqual(j.json()["role"], "member")  # C2: role visible on first join
        detail = self.alice.get(f"/api/v1/groups/{g['id']}").json()
        self.assertEqual({m["user_id"] for m in detail["members"]}, {self.a, self.b})
        self.assertTrue(any("rank" in row for row in detail["leaderboard"]))
        _assert_no_counts(self, detail)

    def test_join_bad_code_404(self):
        self.assertEqual(self.bob.post("/api/v1/groups/join",
                                       json={"invite_code": "ZZZZZZ"}).status_code, 404)

    def test_detail_non_member_404(self):
        g = self._create(self.alice)
        self.assertEqual(self.cara.get(f"/api/v1/groups/{g['id']}").status_code, 404)

    def test_progress_admin_only(self):
        g = self._create(self.alice)
        self.bob.post("/api/v1/groups/join", json={"invite_code": g["invite_code"]})
        prog = self.alice.get(f"/api/v1/groups/{g['id']}/progress")
        self.assertEqual(prog.status_code, 200)
        _assert_no_counts(self, prog.json())
        # member (bob) forbidden
        self.assertEqual(self.bob.get(f"/api/v1/groups/{g['id']}/progress").status_code, 403)
        # non-member (cara) 404 (doesn't leak existence)
        self.assertEqual(self.cara.get(f"/api/v1/groups/{g['id']}/progress").status_code, 404)

    def test_transfer_admin_only(self):
        g = self._create(self.alice)
        self.bob.post("/api/v1/groups/join", json={"invite_code": g["invite_code"]})
        # member cannot transfer
        self.assertEqual(self.bob.post(f"/api/v1/groups/{g['id']}/transfer",
                                       json={"user_id": self.b}).status_code, 403)
        # admin transferring to self is rejected (would-be adminless group)
        self.assertEqual(self.alice.post(f"/api/v1/groups/{g['id']}/transfer",
                                         json={"user_id": self.a}).status_code, 400)
        # admin transfers to bob
        self.assertEqual(self.alice.post(f"/api/v1/groups/{g['id']}/transfer",
                                         json={"user_id": self.b}).status_code, 200)
        self.assertEqual(self.bob.get(f"/api/v1/groups/{g['id']}/progress").status_code, 200)

    def test_leave_sole_admin_conflict(self):
        g = self._create(self.alice)
        self.bob.post("/api/v1/groups/join", json={"invite_code": g["invite_code"]})
        self.assertEqual(self.alice.post(f"/api/v1/groups/{g['id']}/leave").status_code, 409)
        self.assertEqual(self.bob.post(f"/api/v1/groups/{g['id']}/leave").status_code, 204)
        self.assertEqual(self.alice.post(f"/api/v1/groups/{g['id']}/leave").status_code, 204)
