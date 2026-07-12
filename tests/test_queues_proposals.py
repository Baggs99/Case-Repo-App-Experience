"""
Integration tests for Phase 8: queues, intersections (with burn exclusion),
the proposal lifecycle (create/decline/expire/accept→session+.ics), and
RFC 5545 validity of the invite (parsed with the icalendar library).

Needs the seeded dev Postgres — skips cleanly otherwise. Builds the
done-when fixture (3 users, 6 cases, 1 burned) and removes every row and
email file it creates.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

_REPO_ROOT = Path(__file__).resolve().parents[1]
EMAILS_DIR = _REPO_ROOT / "output" / "emails"

try:
    import icalendar  # dev-only, like pytest/httpx
    _ICAL = True
except ImportError:
    _ICAL = False


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestQueuesAndProposals(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)
        cls.cara = TestClient(app)

        import psycopg
        cls.case_ids = []
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                for i in range(1, 7):
                    cur.execute(
                        "INSERT INTO cases (case_title, normalized_title,"
                        " source_school, source_year, industry, case_type,"
                        " difficulty, difficulty_score, page_count, pdf_path)"
                        " VALUES (%s, %s, 'DevSchool', 2096, 'Technology',"
                        " 'Profitability', 'Easy', 3.0, 2, 'output/none.pdf')"
                        " RETURNING id;",
                        (f"P8 Fixture Case {i}", f"p8 fixture case {i}"),
                    )
                    cls.case_ids.append(cur.fetchone()[0])
        cls.aid, cls.bid, cls.cid = (ids["a@yale.edu"], ids["b@yale.edu"],
                                     ids["c@yale.edu"])

        for client, email in ((cls.alice, "a@yale.edu"), (cls.bob, "b@yale.edu"),
                              (cls.cara, "c@yale.edu")):
            s = create_session(ids[email], user_agent="p8-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

        # Burn fixture: C2 is burned for Bob (via a throwaway session row).
        from webapp.repositories.practice_sessions import create_practice_session
        burn_session = create_practice_session(
            interviewer_id=cls.aid, candidate_id=cls.bid,
            case_id=cls.case_ids[1])
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO burned (user_id, case_id, session_id)"
                    " VALUES (%s, %s, %s);",
                    (cls.bid, cls.case_ids[1], burn_session["id"]),
                )

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM burned WHERE case_id = ANY(%s);", (cls.case_ids,))
                cur.execute("DELETE FROM proposals WHERE case_id = ANY(%s);", (cls.case_ids,))
                cur.execute("DELETE FROM practice_sessions WHERE case_id = ANY(%s);",
                            (cls.case_ids,))
                for t in ("queue_want", "queue_give"):
                    cur.execute(f"DELETE FROM {t} WHERE case_id = ANY(%s);", (cls.case_ids,))
                cur.execute("DELETE FROM cases WHERE id = ANY(%s);", (cls.case_ids,))
        cls._ctx.__exit__(None, None, None)

    # ── queues (T8.1) ────────────────────────────────────────────────────────

    def test_queue_crud_and_membership(self):
        c = self.case_ids[4]
        r = self.alice.post(f"/api/queues/want/{c}")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertTrue(r.json()["want"])
        self.assertFalse(r.json()["give"])

        r = self.alice.post(f"/api/queues/want/{c}")   # idempotent
        self.assertEqual(r.status_code, 200)

        r = self.alice.get("/api/queues")
        self.assertIn(c, [row["id"] for row in r.json()["want"]])

        r = self.alice.delete(f"/api/queues/want/{c}")
        self.assertEqual(r.status_code, 200)
        self.assertFalse(r.json()["want"])

        self.assertEqual(self.alice.post(f"/api/queues/bogus/{c}").status_code, 400)
        self.assertEqual(self.alice.post("/api/queues/want/999999").status_code, 404)
        r = self.alice.post(f"/api/queues/want/{c}",
                            headers={"Origin": "https://evil.example"})
        self.assertEqual(r.status_code, 403)

    # ── intersections (T8.2, done-when fixture) ─────────────────────────────

    def test_intersections_exclude_burned(self):
        C1, C2, C3, C4, C5, C6 = self.case_ids
        from webapp.repositories import queues as q
        for cid in (C1, C2, C3):
            q.add(self.aid, "give", cid)
        for cid in (C1, C2, C4):
            q.add(self.bid, "want", cid)     # C2 burned for Bob
        for cid in (C4, C5):
            q.add(self.aid, "want", cid)
        for cid in (C4, C6):
            q.add(self.bid, "give", cid)

        inter = q.intersections(self.aid, self.bid)  # Alice visiting Bob
        self.assertEqual([r["id"] for r in inter["give_to_them"]], [C1],
                         "C2 must be excluded — burned for Bob")
        self.assertEqual([r["id"] for r in inter["receive_from_them"]], [C4])

        # Same math through the room page itself.
        from webapp.repositories.rooms import get_or_create_room
        slug = get_or_create_room(self.bid)["slug"]
        page = self.alice.get(f"/room/{slug}").text
        self.assertIn("P8 Fixture Case 1", page)
        self.assertNotIn("P8 Fixture Case 2", page)
        self.assertIn("P8 Fixture Case 4", page)

    # ── proposals (T8.3) ─────────────────────────────────────────────────────

    def _propose(self, client=None, **overrides):
        payload = {
            "to_user_id": self.bid, "case_id": self.case_ids[0],
            "from_role": "interviewer", "message": "up for it?",
            "proposed_times": [(datetime.now(timezone.utc)
                                + timedelta(days=1)).isoformat()],
        }
        payload.update(overrides)
        return (client or self.alice).post("/api/proposals", json=payload)

    def test_create_validation(self):
        r = self._propose(to_user_id=self.aid)                    # self-propose
        self.assertEqual(r.status_code, 400)
        r = self._propose(case_id=self.case_ids[1])               # burned for Bob
        self.assertEqual(r.status_code, 409)
        times = [(datetime.now(timezone.utc) + timedelta(days=d)).isoformat()
                 for d in range(1, 5)]
        r = self._propose(proposed_times=times)                   # 4 > max 3
        self.assertEqual(r.status_code, 422)
        r = self._propose(case_id=999999)
        self.assertEqual(r.status_code, 404)

    def test_decline_and_inbox(self):
        pid = self._propose().json()["id"]

        r = self.bob.get("/api/proposals/inbox")
        self.assertIn(pid, [p["id"] for p in r.json()["proposals"]])
        self.assertNotIn(pid, [p["id"] for p in
                               self.cara.get("/api/proposals/inbox").json()["proposals"]])

        # Only the recipient may respond; existence undisclosed to others.
        self.assertEqual(
            self.alice.post(f"/api/proposals/{pid}/decline").status_code, 404)
        self.assertEqual(
            self.cara.post(f"/api/proposals/{pid}/decline").status_code, 404)

        self.assertEqual(self.bob.post(f"/api/proposals/{pid}/decline").status_code, 200)
        self.assertEqual(self.bob.post(f"/api/proposals/{pid}/decline").status_code, 409)

    def test_expiry_sweep(self):
        pid = self._propose().json()["id"]
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE proposals SET created_at = NOW() - INTERVAL"
                            " '8 days' WHERE id = %s;", (pid,))
        # Accept must expire it first, not accept it.
        r = self.bob.post(f"/api/proposals/{pid}/accept", json={})
        self.assertEqual(r.status_code, 409)
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT state FROM proposals WHERE id = %s;", (pid,))
                self.assertEqual(cur.fetchone()[0], "expired")

    # ── accept → session + .ics (T8.4) ───────────────────────────────────────

    def test_accept_creates_session_and_ics(self):
        when = (datetime.now(timezone.utc) + timedelta(days=2)).replace(microsecond=0)
        pid = self._propose(from_role="candidate",
                            proposed_times=[when.isoformat()]).json()["id"]

        before = set(EMAILS_DIR.glob("*")) if EMAILS_DIR.exists() else set()
        r = self.bob.post(f"/api/proposals/{pid}/accept",
                          json={"scheduled_at": when.isoformat()})
        self.assertEqual(r.status_code, 200, r.text)
        sid = r.json()["session_id"]
        self.assertEqual(r.json()["ics_url"], f"/ics/session-{sid}.ics")

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT interviewer_id, candidate_id, case_id,"
                            " scheduled_at, state FROM practice_sessions"
                            " WHERE id = %s;", (sid,))
                ivr, cand, case_id, sched, state = cur.fetchone()
                cur.execute("SELECT state, session_id FROM proposals WHERE id = %s;",
                            (pid,))
                pstate, linked = cur.fetchone()

        # from_role=candidate → proposer Alice is candidate, Bob interviews.
        self.assertEqual((ivr, cand), (self.bid, self.aid))
        self.assertEqual(case_id, self.case_ids[0])
        self.assertEqual(sched.astimezone(timezone.utc), when)
        self.assertEqual(state, "scheduled")
        self.assertEqual((pstate, linked), ("accepted", sid))

        # Double accept blocked.
        self.assertEqual(self.bob.post(f"/api/proposals/{pid}/accept",
                                       json={}).status_code, 409)

        # Both parties emailed, each with the .ics attached (console backend
        # writes 2 txt + 2 ics files).
        new_files = sorted(set(EMAILS_DIR.glob("*")) - before)
        self.addCleanup(lambda: [f.unlink(missing_ok=True) for f in new_files])
        txts = [f for f in new_files if f.suffix == ".txt"]
        icss = [f for f in new_files if f.name.endswith(".ics")]
        self.assertEqual(len(txts), 2, [f.name for f in new_files])
        self.assertEqual(len(icss), 2)

        # The invite parses as RFC 5545 (validator: icalendar library) and
        # carries the spec'd fields.
        if _ICAL:
            cal = icalendar.Calendar.from_ical(icss[0].read_bytes())
            self.assertEqual(str(cal["METHOD"]), "REQUEST")
            event = [c for c in cal.walk() if c.name == "VEVENT"][0]
            self.assertTrue(str(event["UID"]).startswith(f"caseroom-{sid}@"))
            self.assertEqual(str(event["SUMMARY"]),
                             "Case practice: P8 Fixture Case 1")
            self.assertEqual(event["DTSTART"].dt, when)

        # Download endpoint: participants only, CRLF, folded ≤ 75 octets.
        r = self.alice.get(f"/ics/session-{sid}.ics")
        self.assertEqual(r.status_code, 200)
        self.assertIn("text/calendar", r.headers["content-type"])
        self.assertEqual(self.cara.get(f"/ics/session-{sid}.ics").status_code, 404)
        raw = r.content
        self.assertTrue(raw.endswith(b"\r\n"))
        for line in raw.split(b"\r\n"):
            self.assertLessEqual(len(line), 76)  # 75 + leading fold space

    def test_ics_escaping_and_defaults(self):
        from webapp.ics import build_session_ics
        ics = build_session_ics(
            session_id=1, case_title="Profit; Loss, and\nChaos",
            starts_at=None, organizer_name="A", organizer_email="a@x.co",
            attendee_name="B", attendee_email="b@x.co",
            session_url="https://x.co/session/1", host="x.co")
        self.assertIn("SUMMARY:Case practice: Profit\\; Loss\\, and\\nChaos", ics)
        self.assertIn("DTSTART:", ics)   # 'now' still yields a concrete stamp
        if _ICAL:
            icalendar.Calendar.from_ical(ics)  # must parse


if __name__ == "__main__":
    unittest.main()
