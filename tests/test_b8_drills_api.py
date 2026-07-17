# tests/test_b8_drills_api.py
"""B8 Task 6: gauntlet/boards/trends endpoints — auth, 409 repeat, no counts,
percentile between two users who complete the same daily set."""
from __future__ import annotations

import unittest
import uuid

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
from tests.test_b6_connections_api import _assert_no_counts


def _answers_for(client):
    # GET the (redacted) set, then answer every slot correctly by regenerating
    # the same date-seeded set server-side (test-only shortcut; the wire set is global).
    from datetime import datetime, timezone
    from webapp import drills
    today = datetime.now(timezone.utc).date()
    ans = []
    for w in drills.daily_set(today):
        a = w["answer"]
        if a["kind"] == "numeric":
            ans.append({"slot": w["slot"], "value": a["value"]})
        else:
            ans.append({"slot": w["slot"], "choice_index": a["correct_index"]})
    return ans


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDrillsGauntletApi(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        from fastapi.testclient import TestClient
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from webapp.main import app
        cls._ctx = TestClient(app)
        cls.c1 = cls._ctx.__enter__()
        cls.c2 = TestClient(app)
        cls.e1 = f"b8-api1-{uuid.uuid4().hex}@yale.edu"
        cls.e2 = f"b8-api2-{uuid.uuid4().hex}@yale.edu"
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("INSERT INTO users (email, password_hash, email_verified_at)"
                        " VALUES (%s,'x',NOW()) RETURNING id;", (cls.e1,))
            cls.u1 = cur.fetchone()[0]
            cur.execute("INSERT INTO users (email, password_hash, email_verified_at)"
                        " VALUES (%s,'x',NOW()) RETURNING id;", (cls.e2,))
            cls.u2 = cur.fetchone()[0]
        cls.c1.cookies.set(SESSION_COOKIE_NAME, create_session(cls.u1, user_agent="t", ip_address=None).id)
        cls.c2.cookies.set(SESSION_COOKIE_NAME, create_session(cls.u2, user_agent="t", ip_address=None).id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM drill_attempts WHERE user_id = ANY(%s);", ([cls.u1, cls.u2],))
            cur.execute("DELETE FROM users WHERE id = ANY(%s);", ([cls.u1, cls.u2],))
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM drill_attempts WHERE user_id = ANY(%s);", ([self.u1, self.u2],))

    def test_get_gauntlet_redacted_and_provisional(self):
        r = self.c1.get("/api/v1/drills/gauntlet")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertTrue(body["provisional"])
        self.assertEqual(len(body["slots"]), 6)
        self.assertFalse(body["submitted"])
        self.assertIsNone(body["result"])
        for slot in body["slots"]:
            self.assertNotIn("answer", slot)
            self.assertNotIn("explanation", slot)
        _assert_no_counts(self, body)

    def test_gauntlet_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        self.assertEqual(TestClient(app).get("/api/v1/drills/gauntlet").status_code, 401)

    def test_submit_then_repeat_is_409(self):
        r1 = self.c1.post("/api/v1/drills/gauntlet/attempts", json={"answers": _answers_for(self.c1)})
        self.assertEqual(r1.status_code, 200, r1.text)
        res = r1.json()
        self.assertEqual(res["score"], 6.0)
        self.assertTrue(res["provisional"])
        _assert_no_counts(self, res)
        r2 = self.c1.post("/api/v1/drills/gauntlet/attempts", json={"answers": _answers_for(self.c1)})
        self.assertEqual(r2.status_code, 409, r2.text)
        # After submit, GET carries the result.
        g = self.c1.get("/api/v1/drills/gauntlet").json()
        self.assertTrue(g["submitted"])
        self.assertIsNotNone(g["result"])

    def test_submit_bad_length_422(self):
        r = self.c1.post("/api/v1/drills/gauntlet/attempts", json={"answers": [{"slot": 0, "value": 1}]})
        self.assertEqual(r.status_code, 422, r.text)

    def test_two_users_same_set_get_percentile(self):
        # u1 all correct (score 6), u2 all provably wrong (score 0). Build the wrong
        # answers by regenerating the same date-seeded set and pushing every answer
        # far outside its tolerance (value*1000+987; choice_index+99) so the score is
        # deterministically 0 regardless of which templates the day drew.
        from datetime import datetime, timezone
        from webapp import drills
        self.c1.post("/api/v1/drills/gauntlet/attempts", json={"answers": _answers_for(self.c1)})
        wrong = []
        for w in drills.daily_set(datetime.now(timezone.utc).date()):
            a = w["answer"]
            if a["kind"] == "numeric":
                wrong.append({"slot": w["slot"], "value": float(a["value"]) * 1000.0 + 987.0})
            else:
                wrong.append({"slot": w["slot"], "choice_index": int(a["correct_index"]) + 99})
        r2 = self.c2.post("/api/v1/drills/gauntlet/attempts", json={"answers": wrong})
        self.assertEqual(r2.status_code, 200, r2.text)
        p1 = self.c1.get("/api/v1/drills/gauntlet").json()["result"]["daily_percentile"]
        p2 = r2.json()["daily_percentile"]
        self.assertEqual(p1, 100.0)
        self.assertEqual(p2, 0.0)

    def test_boards_scopes_no_counts(self):
        for scope in ("school", "global", "schools", "group"):
            r = self.c1.get(f"/api/v1/drills/boards?scope={scope}")
            self.assertEqual(r.status_code, 200, (scope, r.text))
            _assert_no_counts(self, r.json())

    def test_boards_bad_scope_422(self):
        self.assertEqual(self.c1.get("/api/v1/drills/boards?scope=bogus").status_code, 422)

    def test_group_board_requires_membership(self):
        # A group the user is not a member of → 403.
        from webapp.repositories import groups as groups_repo
        g = groups_repo.create_group("B8 Board Test", self.u2)   # u1 not a member
        r = self.c1.get(f"/api/v1/drills/boards?scope=group&group_id={g['id']}")
        self.assertEqual(r.status_code, 403, r.text)
        import psycopg
        with psycopg.connect(_DB_URL) as conn, conn.cursor() as cur:
            cur.execute("DELETE FROM groups WHERE id = %s;", (g["id"],))

    def test_trends_shape(self):
        self.c1.post("/api/v1/drills/gauntlet/attempts", json={"answers": _answers_for(self.c1)})
        r = self.c1.get("/api/v1/drills/trends")
        self.assertEqual(r.status_code, 200, r.text)
        t = r.json()
        for k in ("daily", "by_type", "weakest"):
            self.assertIn(k, t)
        _assert_no_counts(self, t)


if __name__ == "__main__":
    unittest.main()
