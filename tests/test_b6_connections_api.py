"""B6 Task 2: connections API — request/accept/decline/remove, auth + IDOR +
same-origin. Needs seeded dev Postgres + httpx."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

# Shared no-population-count auditor (imported by the groups + leaderboards API
# tests). Walks nested JSON and fails on any count-like/headcount key — the
# B6 delta: percentiles only, never "of N".
_FORBIDDEN = ("count", "total", "num_", "of_n", "n_members", "n_players", "population")


def _assert_no_counts(case, obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            for bad in _FORBIDDEN:
                case.assertNotIn(bad, k.lower(), f"count-like key leaked: {k}")
            _assert_no_counts(case, v)
    elif isinstance(obj, list):
        for v in obj:
            _assert_no_counts(case, v)


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestConnectionsApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        import psycopg
        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.a, cls.b, cls.c = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]
        for client, uid in ((cls.alice, cls.a), (cls.bob, cls.b)):
            s = create_session(uid, user_agent="b6-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM connections WHERE user_id = ANY(%s) OR friend_id = ANY(%s);",
                            ([self.a, self.b, self.c], [self.a, self.b, self.c]))

    def test_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        self.assertEqual(TestClient(app).get("/api/v1/connections").status_code, 401)

    def test_cross_origin_rejected(self):
        r = self.alice.post("/api/v1/connections/requests", json={"to_user_id": self.b},
                            headers={"Origin": "http://evil.example"})
        self.assertEqual(r.status_code, 403)

    def test_request_self_400(self):
        r = self.alice.post("/api/v1/connections/requests", json={"to_user_id": self.a})
        self.assertEqual(r.status_code, 400)

    def test_request_unknown_404(self):
        r = self.alice.post("/api/v1/connections/requests", json={"to_user_id": -1})
        self.assertEqual(r.status_code, 404)

    def test_full_flow(self):
        r = self.alice.post("/api/v1/connections/requests", json={"to_user_id": self.b})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["state"], "pending")
        # bob sees it incoming
        inc = self.bob.get("/api/v1/connections/requests").json()["incoming"]
        self.assertEqual([c["user_id"] for c in inc], [self.a])
        # bob accepts
        self.assertEqual(self.bob.post(f"/api/v1/connections/{self.a}/accept").status_code, 200)
        full = self.alice.get("/api/v1/connections").json()
        cards = full["connections"]
        self.assertEqual([c["user_id"] for c in cards], [self.b])
        self.assertIn("photo_url", cards[0])
        self.assertFalse(cards[0]["swap_invite_pending"])
        _assert_no_counts(self, full)
        # alice removes
        self.assertEqual(self.alice.delete(f"/api/v1/connections/{self.b}").status_code, 204)
        self.assertEqual(self.alice.get("/api/v1/connections").json()["connections"], [])

    def test_accept_idor(self):
        # alice -> bob pending; c (via a third client) must not be able to accept.
        self.alice.post("/api/v1/connections/requests", json={"to_user_id": self.b})
        # alice cannot accept her own request (she is requester, not target)
        self.assertEqual(self.alice.post(f"/api/v1/connections/{self.b}/accept").status_code, 404)

    def test_decline_404_when_none(self):
        self.assertEqual(self.bob.post(f"/api/v1/connections/{self.a}/decline").status_code, 404)
