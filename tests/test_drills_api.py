"""
Purpose: Test the P4 drill_attempts substrate — record_attempt/streak_days/
         attempted_today repo logic, POST /api/v1/drills/attempts, and the
         daily streak fields added to GET /api/v1/dashboard.
Inputs:  seeded dev Postgres via tests.test_ws_integration (_DB_URL/_READY/
         _HTTPX); a@yale.edu for endpoint auth; one ephemeral @yale.edu user
         for the exact-count repo tests.
Outputs: no files; inserts/deletes only its own drill_attempts, practice_sessions,
         case and ephemeral-user rows, cleaned up in setUp/tearDown.
Run:     .venv/bin/python -m pytest tests/test_drills_api.py -q
"""

from __future__ import annotations

import unittest
import uuid

from psycopg.rows import dict_row

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient (bootstraps the db pool)")
class TestDrillsRepo(unittest.TestCase):
    """Repo-level streak logic against a dedicated ephemeral user. The shared
    dev DB gives a@/b@yale.edu persistent finalized sessions, so exact streak
    counts (0, 2, 1, …) are only hermetic on a user whose entire qualifying-day
    set this test controls."""

    @classmethod
    def setUpClass(cls):
        import psycopg
        from fastapi.testclient import TestClient

        from webapp.main import app
        from webapp.repositories.practice_sessions import get_default_rubric_template_id
        from webapp.repositories.rooms import get_or_create_room

        # Enter the app context so the db pool is initialised (same idiom as the
        # HTTP test classes); these repo calls go through get_pool().
        cls._ctx = TestClient(app)
        cls._ctx.__enter__()

        cls.email = f"p4-drill-{uuid.uuid4().hex}@yale.edu"
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # Self-heal: a prior crashed run (setUpClass raising skips
                # tearDownClass) can strand this fixture's case. Clear it before
                # re-inserting, since (school, year) is uniquely ours here.
                cur.execute(
                    "DELETE FROM practice_sessions WHERE case_id IN"
                    " (SELECT id FROM cases WHERE source_school = 'DevSchool'"
                    "  AND source_year = 2097);"
                )
                cur.execute(
                    "DELETE FROM cases WHERE source_school = 'DevSchool'"
                    " AND source_year = 2097;"
                )
                cur.execute(
                    "INSERT INTO users (email, password_hash, email_verified_at)"
                    " VALUES (%s, 'x', NOW()) RETURNING id;",
                    (cls.email,),
                )
                cls.uid = cur.fetchone()[0]
                # A distinct counterpart is required to satisfy the
                # interviewer_id <> candidate_id check on the finalized-session
                # fixture; a@yale.edu is always seeded.
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.counterpart = cur.fetchone()[0]
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES (%s, %s, 'DevSchool', 2097, 'Technology', 'P4-Drill',"
                    " 'Easy', 2, 2, 'output/none.pdf') RETURNING id;",
                    ("P4 Drill Case", "p4 drill case"),
                )
                cls.case_id = cur.fetchone()[0]

        cls.template_id = get_default_rubric_template_id(cls.case_id, cls.counterpart)
        cls.room_id = get_or_create_room(cls.counterpart)["id"]

    @classmethod
    def tearDownClass(cls):
        import psycopg

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # practice_sessions.case_id has no ON DELETE, so drop sessions
                # before the case; users cascade drops drill_attempts.
                cur.execute(
                    "DELETE FROM practice_sessions"
                    " WHERE interviewer_id = %(u)s OR candidate_id = %(u)s;",
                    {"u": cls.uid},
                )
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
                cur.execute("DELETE FROM users WHERE id = %s;", (cls.uid,))
        cls._ctx.__exit__(None, None, None)

    def setUp(self):
        self._sweep_stale_ephemeral()
        self._clean()

    def tearDown(self):
        self._clean()

    def _sweep_stale_ephemeral(self):
        """A prior crashed run (setUpClass raising skips tearDownClass) can
        strand this fixture's ephemeral p4-drill-* user plus its drill_attempts
        and finalized sessions. Sweep every such user except this run's own so
        the exact streak counts here stay hermetic. Parameterized throughout;
        the % in the LIKE pattern is a bound value, not SQL, so needs no escape."""
        import psycopg

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT id FROM users WHERE email LIKE %(pat)s AND id <> %(keep)s;",
                    {"pat": "p4-drill-%@yale.edu", "keep": self.uid},
                )
                stale = [row[0] for row in cur.fetchall()]
                if stale:
                    # practice_sessions has no ON DELETE on interviewer/candidate,
                    # so clear it before the users; drill_attempts cascade on the
                    # user delete, but drop them explicitly too.
                    cur.execute(
                        "DELETE FROM practice_sessions"
                        " WHERE interviewer_id = ANY(%(ids)s) OR candidate_id = ANY(%(ids)s);",
                        {"ids": stale},
                    )
                    cur.execute("DELETE FROM drill_attempts WHERE user_id = ANY(%(ids)s);",
                                {"ids": stale})
                    cur.execute("DELETE FROM users WHERE id = ANY(%(ids)s);",
                                {"ids": stale})

    def _clean(self):
        import psycopg

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM drill_attempts WHERE user_id = %s;", (self.uid,))
                cur.execute(
                    "DELETE FROM practice_sessions"
                    " WHERE interviewer_id = %(u)s OR candidate_id = %(u)s;",
                    {"u": self.uid},
                )

    def _attempt_days_ago(self, n, *, drill_type="mental_math", source="on_device",
                          drill_key=None, correct=True):
        """Insert a drill attempt whose UTC day is n days before today. Uses the
        DB clock throughout so day arithmetic matches what streak_days reads."""
        import psycopg

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO drill_attempts (user_id, drill_type, source,"
                    " drill_key, correct, completed_at)"
                    " VALUES (%(u)s, %(t)s, %(s)s, %(k)s, %(c)s,"
                    " now() - make_interval(days => %(n)s));",
                    {"u": self.uid, "t": drill_type, "s": source, "k": drill_key,
                     "c": correct, "n": n},
                )

    def _finalized_session_days_ago(self, n):
        import psycopg

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO practice_sessions (room_id, interviewer_id,"
                    " candidate_id, case_id, rubric_template_id, state, ended_at)"
                    " VALUES (%(room)s, %(iv)s, %(cand)s, %(case)s, %(tmpl)s,"
                    " 'finalized', now() - make_interval(days => %(n)s));",
                    {"room": self.room_id, "iv": self.counterpart, "cand": self.uid,
                     "case": self.case_id, "tmpl": self.template_id, "n": n},
                )

    # ── record_attempt ────────────────────────────────────────────────────
    def test_record_attempt_inserts_and_returns_row(self):
        from webapp.repositories import drill_attempts as repo

        row = repo.record_attempt(
            self.uid, drill_type="market_sizing", source="server",
            drill_key="ms-42", correct=True,
        )
        self.assertIsNotNone(row.get("id"))
        self.assertEqual(row["user_id"], self.uid)
        self.assertEqual(row["drill_type"], "market_sizing")
        self.assertEqual(row["source"], "server")
        self.assertEqual(row["drill_key"], "ms-42")
        self.assertTrue(row["correct"])
        self.assertIsNotNone(row.get("completed_at"))

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM drill_attempts WHERE user_id = %s;",
                            (self.uid,))
                self.assertEqual(cur.fetchone()[0], 1)

    def test_record_attempt_allows_null_drill_key(self):
        from webapp.repositories import drill_attempts as repo

        row = repo.record_attempt(
            self.uid, drill_type="mental_math", source="on_device",
            drill_key=None, correct=False,
        )
        self.assertIsNone(row["drill_key"])
        self.assertFalse(row["correct"])

    # ── streak_days ───────────────────────────────────────────────────────
    def test_streak_days_zero_with_no_data(self):
        from webapp.repositories import drill_attempts as repo

        self.assertEqual(repo.streak_days(self.uid), 0)

    def test_streak_days_today_and_yesterday_is_two(self):
        from webapp.repositories import drill_attempts as repo

        self._attempt_days_ago(0)
        self._attempt_days_ago(1)
        self.assertEqual(repo.streak_days(self.uid), 2)

    def test_streak_days_gap_does_not_extend(self):
        from webapp.repositories import drill_attempts as repo

        self._attempt_days_ago(0)
        self._attempt_days_ago(1)
        self._attempt_days_ago(3)  # today-2 missing -> the run stops at 2
        self.assertEqual(repo.streak_days(self.uid), 2)

    def test_streak_days_yesterday_only_is_one(self):
        from webapp.repositories import drill_attempts as repo

        self._attempt_days_ago(1)  # nothing today -> yesterday-anchored
        self.assertEqual(repo.streak_days(self.uid), 1)

    def test_streak_days_two_days_ago_only_is_zero(self):
        from webapp.repositories import drill_attempts as repo

        self._attempt_days_ago(2)  # neither today nor yesterday -> broken
        self.assertEqual(repo.streak_days(self.uid), 0)

    def test_streak_days_counts_finalized_session_day(self):
        from webapp.repositories import drill_attempts as repo

        self._finalized_session_days_ago(0)  # finalized session today, no drills
        self.assertEqual(repo.streak_days(self.uid), 1)

    def test_streak_days_mixes_sessions_and_drills(self):
        from webapp.repositories import drill_attempts as repo

        self._finalized_session_days_ago(0)  # today via session
        self._attempt_days_ago(1)            # yesterday via drill
        self.assertEqual(repo.streak_days(self.uid), 2)

    # ── attempted_today ───────────────────────────────────────────────────
    def test_attempted_today_false_then_true(self):
        from webapp.repositories import drill_attempts as repo

        self.assertFalse(repo.attempted_today(self.uid))
        self._attempt_days_ago(0)
        self.assertTrue(repo.attempted_today(self.uid))

    def test_attempted_today_ignores_yesterday(self):
        from webapp.repositories import drill_attempts as repo

        self._attempt_days_ago(1)
        self.assertFalse(repo.attempted_today(self.uid))


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestDrillsApi(unittest.TestCase):
    """POST /api/v1/drills/attempts and the dashboard's new streak fields,
    authenticated as the seeded a@yale.edu via a minted session cookie."""

    @classmethod
    def setUpClass(cls):
        import psycopg
        from fastapi.testclient import TestClient

        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.aid = cur.fetchone()[0]

        session = create_session(cls.aid, user_agent="p4-drills-test", ip_address=None)
        cls.alice.cookies.set(SESSION_COOKIE_NAME, session.id)

    @classmethod
    def tearDownClass(cls):
        cls._clean(cls.aid)
        cls._ctx.__exit__(None, None, None)

    @staticmethod
    def _clean(uid):
        import psycopg

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM drill_attempts WHERE user_id = %s;", (uid,))

    def setUp(self):
        self._clean(self.aid)

    def tearDown(self):
        self._clean(self.aid)

    def _attempts_for_alice(self):
        import psycopg

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute(
                    "SELECT drill_type, source, drill_key, correct"
                    " FROM drill_attempts WHERE user_id = %s;",
                    (self.aid,),
                )
                return cur.fetchall()

    def test_post_attempt_returns_204_and_persists(self):
        r = self.alice.post(
            "/api/v1/drills/attempts",
            json={"drill_type": "mental_math", "source": "on_device", "correct": True},
        )
        self.assertEqual(r.status_code, 204, r.text)
        self.assertEqual(r.content, b"")

        rows = self._attempts_for_alice()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["drill_type"], "mental_math")
        self.assertEqual(rows[0]["source"], "on_device")
        self.assertIsNone(rows[0]["drill_key"])
        self.assertTrue(rows[0]["correct"])

    def test_post_attempt_with_drill_key_persists(self):
        r = self.alice.post(
            "/api/v1/drills/attempts",
            json={"drill_type": "framework_recall", "source": "server",
                  "drill_key": "fr-7", "correct": False},
        )
        self.assertEqual(r.status_code, 204, r.text)
        rows = self._attempts_for_alice()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["drill_key"], "fr-7")
        self.assertFalse(rows[0]["correct"])

    def test_post_attempt_invalid_drill_type_422(self):
        r = self.alice.post(
            "/api/v1/drills/attempts",
            json={"drill_type": "bogus", "source": "on_device", "correct": True},
        )
        self.assertEqual(r.status_code, 422, r.text)
        self.assertEqual(self._attempts_for_alice(), [])

    def test_post_attempt_invalid_source_422(self):
        r = self.alice.post(
            "/api/v1/drills/attempts",
            json={"drill_type": "mental_math", "source": "telepathy", "correct": True},
        )
        self.assertEqual(r.status_code, 422, r.text)

    def test_post_attempt_unauthenticated_401(self):
        from fastapi.testclient import TestClient
        from webapp.main import app

        r = TestClient(app).post(
            "/api/v1/drills/attempts",
            json={"drill_type": "mental_math", "source": "on_device", "correct": True},
        )
        self.assertEqual(r.status_code, 401)

    def test_dashboard_preserves_existing_keys_and_adds_streak_fields(self):
        r = self.alice.get("/api/v1/dashboard")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        for key in ("sessions_finalized", "streak_weeks", "next_session",
                    "streak_days", "drill_done_today"):
            self.assertIn(key, body)
        self.assertIsInstance(body["streak_days"], int)
        self.assertIsInstance(body["drill_done_today"], bool)
        # setUp cleared Alice's drill_attempts: no drill today yet.
        self.assertFalse(body["drill_done_today"])
        before = body["streak_days"]

        r2 = self.alice.post(
            "/api/v1/drills/attempts",
            json={"drill_type": "mental_math", "source": "on_device", "correct": True},
        )
        self.assertEqual(r2.status_code, 204, r2.text)

        body2 = self.alice.get("/api/v1/dashboard").json()
        self.assertTrue(body2["drill_done_today"])
        # Today now qualifies via the drill, so the streak is >= 1 and can only
        # hold or grow relative to before (never shrink).
        self.assertGreaterEqual(body2["streak_days"], 1)
        self.assertGreaterEqual(body2["streak_days"], before)


if __name__ == "__main__":
    unittest.main()
