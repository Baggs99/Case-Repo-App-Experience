"""B6 Task 3: groups repository — create/join/leave/transfer + membership
queries. Needs seeded dev Postgres."""

from __future__ import annotations

import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient (bootstraps the db pool)")
class TestGroupsRepo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Repo functions call webapp.db.get_pool(); enter a TestClient to init it.
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
        cls._gids = []

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def tearDown(self):
        import psycopg
        if self._gids:
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("DELETE FROM groups WHERE id = ANY(%s);", (self._gids,))
            self._gids.clear()

    def _make(self, name, creator):
        from webapp.repositories import groups as repo
        g = repo.create_group(name, creator)
        self._gids.append(g["id"])
        return g

    def test_create_makes_admin_and_code(self):
        from webapp.repositories import groups as repo
        g = self._make("Cohort C-14", self.a)
        self.assertEqual(g["role"], "admin")
        self.assertEqual(len(g["invite_code"]), 6)
        self.assertTrue(repo.is_admin(g["id"], self.a))
        self.assertEqual(repo.member_role(g["id"], self.a), "admin")

    def test_join_by_code(self):
        from webapp.repositories import groups as repo
        g = self._make("Cohort C-14", self.a)
        joined = repo.join_by_code(g["invite_code"], self.b)
        self.assertEqual(joined["id"], g["id"])
        self.assertEqual(joined["role"], "member")
        self.assertFalse(joined["already_member"])
        self.assertTrue(repo.is_member(g["id"], self.b))
        # idempotent
        self.assertTrue(repo.join_by_code(g["invite_code"], self.b)["already_member"])

    def test_join_unknown_code(self):
        from webapp.repositories import groups as repo
        self.assertIsNone(repo.join_by_code("ZZZZZZ", self.b))

    def test_transfer_admin(self):
        from webapp.repositories import groups as repo
        g = self._make("Cohort C-14", self.a)
        repo.join_by_code(g["invite_code"], self.b)
        # transfer to self is a safe no-op — never orphans the group
        self.assertTrue(repo.transfer_admin(g["id"], self.a, self.a))
        self.assertTrue(repo.is_admin(g["id"], self.a))
        self.assertTrue(repo.transfer_admin(g["id"], self.a, self.b))
        self.assertTrue(repo.is_admin(g["id"], self.b))
        self.assertEqual(repo.member_role(g["id"], self.a), "member")
        # target not a member
        self.assertFalse(repo.transfer_admin(g["id"], self.b, self.c))

    def test_leave_rules(self):
        from webapp.repositories import groups as repo
        g = self._make("Cohort C-14", self.a)
        repo.join_by_code(g["invite_code"], self.b)
        # sole admin with a remaining member must transfer first
        with self.assertRaises(PermissionError):
            repo.leave_group(g["id"], self.a)
        self.assertEqual(repo.leave_group(g["id"], self.b), "left")
        # now a is the last member -> leaving deletes the group
        self.assertEqual(repo.leave_group(g["id"], self.a), "deleted")
        self.assertIsNone(repo.get_group(g["id"]))

    def test_list_my_groups_and_members(self):
        from webapp.repositories import groups as repo
        g = self._make("Cohort C-14", self.a)
        repo.join_by_code(g["invite_code"], self.b)
        mine = repo.list_my_groups(self.a)
        self.assertIn(g["id"], [x["id"] for x in mine])
        members = repo.list_members(g["id"])
        self.assertEqual({m["user_id"] for m in members}, {self.a, self.b})
        self.assertEqual(sorted(repo.admin_ids(g["id"])), [self.a])

    def test_school_leader_flag(self):
        from webapp.repositories import groups as repo
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT school_id FROM users WHERE id = %s;", (self.a,))
                sid = cur.fetchone()[0]
        self.assertIsNotNone(sid, "seeded yale user must have a school_id")
        self.assertFalse(repo.is_school_leader(self.a, sid))
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO school_leaders (school_id, user_id) VALUES (%s,%s)"
                            " ON CONFLICT DO NOTHING;", (sid, self.a))
        try:
            self.assertTrue(repo.is_school_leader(self.a, sid))
        finally:
            with psycopg.connect(_DB_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("DELETE FROM school_leaders WHERE school_id=%s AND user_id=%s;",
                                (sid, self.a))
