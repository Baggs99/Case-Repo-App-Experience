"""B6 Task 1: connections repository — request/accept/decline/remove + listing
with free-now decoration. Needs seeded dev Postgres."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient (bootstraps the db pool)")
class TestConnectionsRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Repo functions call webapp.db.get_pool(); the pool is initialized only
        # inside the app lifespan, so enter a TestClient to bootstrap it.
        from fastapi.testclient import TestClient
        from webapp.main import app
        import psycopg
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.a, cls.b, cls.c = ids["a@yale.edu"], ids["b@yale.edu"], ids["c@yale.edu"]

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def tearDown(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM connections WHERE user_id = ANY(%s) OR friend_id = ANY(%s);",
                            ([self.a, self.b, self.c], [self.a, self.b, self.c]))
                cur.execute("DELETE FROM availability WHERE user_id = ANY(%s);",
                            ([self.a, self.b, self.c],))

    def test_request_creates_pending(self):
        from webapp.repositories import connections as repo
        self.assertEqual(repo.request(self.a, self.b), {"state": "pending"})
        self.assertFalse(repo.are_connected(self.a, self.b))
        self.assertEqual([r["user_id"] for r in repo.list_incoming(self.b)], [self.a])
        self.assertEqual([r["user_id"] for r in repo.list_outgoing(self.a)], [self.b])

    def test_self_request_rejected(self):
        from webapp.repositories import connections as repo
        with self.assertRaises(ValueError):
            repo.request(self.a, self.a)

    def test_accept_makes_connection(self):
        from webapp.repositories import connections as repo
        repo.request(self.a, self.b)
        self.assertTrue(repo.accept(self.a, self.b))
        self.assertTrue(repo.are_connected(self.a, self.b))
        self.assertTrue(repo.are_connected(self.b, self.a))
        self.assertEqual([r["user_id"] for r in repo.list_accepted(self.a)], [self.b])
        self.assertEqual([r["user_id"] for r in repo.list_accepted(self.b)], [self.a])

    def test_accept_only_by_target(self):
        from webapp.repositories import connections as repo
        repo.request(self.a, self.b)
        # c cannot accept a's request to b; a cannot self-accept
        self.assertFalse(repo.accept(self.a, self.c))
        self.assertFalse(repo.are_connected(self.a, self.b))

    def test_reciprocal_request_auto_accepts(self):
        from webapp.repositories import connections as repo
        repo.request(self.a, self.b)
        self.assertEqual(repo.request(self.b, self.a), {"state": "accepted"})
        self.assertTrue(repo.are_connected(self.a, self.b))

    def test_decline_and_remove(self):
        from webapp.repositories import connections as repo
        repo.request(self.a, self.b)
        self.assertTrue(repo.decline(self.a, self.b))
        self.assertFalse(repo.are_connected(self.a, self.b))
        repo.request(self.a, self.b)
        repo.accept(self.a, self.b)
        repo.remove(self.b, self.a)  # either party removes
        self.assertFalse(repo.are_connected(self.a, self.b))

    def test_free_now_decoration(self):
        from webapp.repositories import connections as repo
        from webapp.repositories import availability as av
        repo.request(self.a, self.b)
        repo.accept(self.a, self.b)
        av.set_free(self.b, 60)
        row = repo.list_accepted(self.a)[0]
        self.assertTrue(row["free_now"])
        # a is not free -> b sees a not-free
        self.assertFalse(repo.list_accepted(self.b)[0]["free_now"])
