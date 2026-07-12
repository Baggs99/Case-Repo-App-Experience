"""
Phase 10 tests: chunk ordering, INV-5 limits, role/state gating, the authed
download passthrough, and the deny-all guarantee (recording files are never
web-served). Uses a temp RECORDINGS_DIR and its own case; removes all rows.
"""

from __future__ import annotations

import os
import shutil
import tempfile
import unittest

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

WEBM_MAGIC = b"\x1a\x45\xdf\xa3"          # EBML — what MediaRecorder emits
CHUNK0 = WEBM_MAGIC + b"fake-opus-chunk-zero" * 10
CHUNK1 = b"continuation-bytes-one" * 10
CHUNK2 = b"continuation-bytes-two" * 10


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestRecordings(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._dir = tempfile.mkdtemp(prefix="rec-test-")
        cls._prev = os.environ.get("RECORDINGS_DIR")
        os.environ["RECORDINGS_DIR"] = cls._dir

        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()   # interviewer
        cls.bob = TestClient(app)          # candidate
        cls.cara = TestClient(app)         # outsider
        cls.anon = TestClient(app)

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = dict(cur.fetchall())
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('Recording Test Case', 'recording test case',"
                    " 'DevSchool', 2094, 'Technology', 'Profitability', 'Easy',"
                    " 3.0, 2, 'output/none.pdf') RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]

        for client, email in ((cls.alice, "a@yale.edu"), (cls.bob, "b@yale.edu"),
                              (cls.cara, "c@yale.edu")):
            s = create_session(ids[email], user_agent="rec-test", ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, s.id)

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;",
                            (cls.case_id,))              # cascades recordings
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._ctx.__exit__(None, None, None)
        shutil.rmtree(cls._dir, ignore_errors=True)
        if cls._prev is None:
            os.environ.pop("RECORDINGS_DIR", None)
        else:
            os.environ["RECORDINGS_DIR"] = cls._prev

    def _live_session(self) -> int:
        r = self.alice.post("/api/practice", json={
            "interviewer_id": self.aid, "candidate_id": self.bid,
            "case_id": self.case_id})
        sid = r.json()["id"]
        self.alice.post(f"/api/practice/{sid}/state", json={"target": "lobby"})
        for c in (self.alice, self.bob):
            c.post(f"/api/practice/{sid}/consent", json={"consent": True})
        self.alice.post(f"/api/practice/{sid}/state", json={"target": "live"})
        return sid

    def _chunk(self, client, sid, seq, data, mime="audio/webm", **kw):
        return client.post(
            f"/api/practice/{sid}/recordings/chunk",
            data={"seq": str(seq), "mime": mime},
            files={"blob": ("chunk.webm", data, mime)}, **kw)

    # ── ordering + append ────────────────────────────────────────────────────

    def test_chunks_append_in_order(self):
        sid = self._live_session()
        for seq, data in enumerate((CHUNK0, CHUNK1, CHUNK2)):
            r = self._chunk(self.bob, sid, seq, data)
            self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["chunks"], 3)
        self.assertEqual(r.json()["bytes"], len(CHUNK0 + CHUNK1 + CHUNK2))

        # Gap and duplicate both 409, naming the expected seq.
        r = self._chunk(self.bob, sid, 5, CHUNK1)
        self.assertEqual(r.status_code, 409)
        self.assertIn("expected seq 3", r.json()["detail"])
        r = self._chunk(self.bob, sid, 2, CHUNK1)
        self.assertEqual(r.status_code, 409)

        # Non-zero first chunk for a fresh participant: 409 expected seq 0.
        r = self._chunk(self.alice, sid, 1, CHUNK1)
        self.assertEqual(r.status_code, 409)
        self.assertIn("expected seq 0", r.json()["detail"])

        # Download passthrough: exact bytes, either participant; outsiders no.
        for client in (self.bob, self.alice):
            r = client.get(f"/api/practice/{sid}/recordings/{self.bid}")
            self.assertEqual(r.status_code, 200)
            self.assertEqual(r.content, CHUNK0 + CHUNK1 + CHUNK2)
            self.assertEqual(r.headers["content-type"].split(";")[0], "audio/webm")
        self.assertEqual(
            self.cara.get(f"/api/practice/{sid}/recordings/{self.bid}").status_code, 404)
        self.assertEqual(
            self.anon.get(f"/api/practice/{sid}/recordings/{self.bid}").status_code, 401)

        # complete → listed as completed; further chunks rejected.
        r = self.bob.post(f"/api/practice/{sid}/recordings/complete")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self._chunk(self.bob, sid, 3, CHUNK1).status_code, 409)
        rows = self.bob.get(f"/api/practice/{sid}/recordings").json()["recordings"]
        mine = [x for x in rows if x["user_id"] == self.bid][0]
        self.assertTrue(mine["completed"])
        self.assertEqual(mine["chunks"], 3)
        self.assertNotIn("path", mine)   # server-local detail never leaves

    # ── limits + validation (INV-5) ──────────────────────────────────────────

    def test_limits_and_validation(self):
        sid = self._live_session()
        r = self._chunk(self.bob, sid, 0, b"\x00" * (9 * 1024 * 1024))
        self.assertEqual(r.status_code, 413)                 # chunk cap 8 MB
        r = self._chunk(self.bob, sid, 0, b"not-a-webm-stream")
        self.assertEqual(r.status_code, 415)                 # container sniff
        r = self._chunk(self.bob, sid, 0, CHUNK0, mime="audio/ogg")
        self.assertEqual(r.status_code, 415)                 # mime whitelist
        r = self._chunk(self.bob, sid, 0, CHUNK0,
                        headers={"Origin": "https://evil.example"})
        self.assertEqual(r.status_code, 403)                 # CSRF

        # Session total cap: shrink the env cap to 1 MB for this check.
        os.environ["MAX_REC_TOTAL_MB"] = "1"
        try:
            self.assertEqual(self._chunk(self.bob, sid, 0, CHUNK0).status_code, 200)
            r = self._chunk(self.bob, sid, 1, b"\x00" * (1024 * 1024 + 1))
            self.assertEqual(r.status_code, 413)
        finally:
            os.environ.pop("MAX_REC_TOTAL_MB", None)

    def test_state_and_role_gates(self):
        r = self.alice.post("/api/practice", json={
            "interviewer_id": self.aid, "candidate_id": self.bid,
            "case_id": self.case_id})
        sid = r.json()["id"]
        self.assertEqual(self._chunk(self.bob, sid, 0, CHUNK0).status_code, 409,
                         "no chunks while scheduled")
        self.assertEqual(self._chunk(self.cara, sid, 0, CHUNK0).status_code, 404)
        self.assertEqual(
            self.bob.post(f"/api/practice/{sid}/recordings/complete").status_code, 404,
            "complete with no recording row")

    # ── deny-all (T10.4 equivalent) ──────────────────────────────────────────

    def test_recording_files_never_web_served(self):
        sid = self._live_session()
        self.assertEqual(self._chunk(self.bob, sid, 0, CHUNK0).status_code, 200)
        from webapp.repositories.recordings import get_recording
        name = get_recording(sid, self.bid)["path"]
        for url in (f"/output/recordings/{name}", f"/recordings/{name}",
                    f"/static/../output/recordings/{name}"):
            self.assertIn(self.cara.get(url).status_code, (401, 403, 404),
                          f"{url} must not serve recording bytes")


if __name__ == "__main__":
    unittest.main()
