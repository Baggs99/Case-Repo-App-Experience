"""
Integration tests for the Phase 6 reveal system: session-time exhibit
manifest/blob/keys endpoints, POST /reveals as system of record, and the
reveal-gated fallback key path (spec §4.4, INTEGRATION.md DV-4/DV-11).

Needs a reachable Postgres with the dev seed applied — skips cleanly
otherwise (same gate as test_ws_integration). Creates its own case +
exhibits under a temp EXHIBITS_DIR and removes them, so the seeded dev
case's authored exhibits are never touched.
"""

from __future__ import annotations

import base64
import os
import shutil
import tempfile
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[1]


def _load_database_url() -> str | None:
    if os.environ.get("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    env = _REPO_ROOT / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("DATABASE_URL="):
                url = line.split("=", 1)[1].strip()
                os.environ["DATABASE_URL"] = url
                return url
    return None


def _db_ready(url: str | None) -> bool:
    if not url:
        return False
    try:
        import psycopg
        with psycopg.connect(url, connect_timeout=3) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT COUNT(*) FROM users WHERE email = 'a@yale.edu';")
                return cur.fetchone()[0] == 1
    except Exception:
        return False


_DB_URL = _load_database_url()
_READY = _db_ready(_DB_URL)

try:
    import httpx  # noqa: F401
    _HTTPX = True
except ImportError:
    _HTTPX = False

# Valid-looking WebP plaintexts so magic-byte assertions mean something.
_PLAINTEXTS = [
    b"RIFF\x28\x00\x00\x00WEBPVP8 fake-exhibit-one-payload",
    b"RIFF\x2c\x00\x00\x00WEBPVP8 fake-exhibit-two-payload!",
]


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestRevealSystem(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._exhibits_dir = tempfile.mkdtemp(prefix="reveal-test-exhibits-")
        cls._prev_exhibits_dir = os.environ.get("EXHIBITS_DIR")
        os.environ["EXHIBITS_DIR"] = cls._exhibits_dir

        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._client_ctx = TestClient(app)          # lifespan opens the pool
        cls.alice = cls._client_ctx.__enter__()    # interviewer
        cls.bob = TestClient(app)                  # candidate
        cls.cara = TestClient(app)                 # outsider
        cls.anon = TestClient(app)

        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu", "c@yale.edu"],))
                ids = {email: uid for email, uid in cur.fetchall()}
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('Reveal Test Case', 'reveal test case', 'DevSchool',"
                    " 2099, 'Technology', 'Profitability', 'Easy', 3.0, 2,"
                    " 'output/cases/devschool/nonexistent.pdf')"
                    " RETURNING id;"
                )
                cls.case_id = cur.fetchone()[0]
        cls.alice_id, cls.bob_id = ids["a@yale.edu"], ids["b@yale.edu"]

        for client, email in ((cls.alice, "a@yale.edu"),
                              (cls.bob, "b@yale.edu"),
                              (cls.cara, "c@yale.edu")):
            session = create_session(ids[email], user_agent="reveal-test",
                                     ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, session.id)

        # Author exhibits directly at the repo layer — rendering is Phase 5's
        # problem; this phase starts at "encrypted blobs exist".
        from webapp.repositories import case_exhibits
        cls.exhibits = case_exhibits.replace_for_case(
            cls.case_id, cls.alice_id,
            [{"webp": p, "source_pages": str(i + 1), "width": 800, "height": 600}
             for i, p in enumerate(_PLAINTEXTS)],
        )

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                # reveals cascade with their sessions
                cur.execute("DELETE FROM practice_sessions WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM case_exhibits WHERE case_id = %s;",
                            (cls.case_id,))
                cur.execute("DELETE FROM cases WHERE id = %s;", (cls.case_id,))
        cls._client_ctx.__exit__(None, None, None)
        shutil.rmtree(cls._exhibits_dir, ignore_errors=True)
        if cls._prev_exhibits_dir is None:
            os.environ.pop("EXHIBITS_DIR", None)
        else:
            os.environ["EXHIBITS_DIR"] = cls._prev_exhibits_dir

    # ── helpers ──────────────────────────────────────────────────────────────

    def _new_session(self) -> int:
        r = self.alice.post("/api/practice", json={
            "interviewer_id": self.alice_id, "candidate_id": self.bob_id,
            "case_id": self.case_id,
        })
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["id"]

    def _go_live(self, sid: int) -> None:
        r = self.alice.post(f"/api/practice/{sid}/state", json={"target": "lobby"})
        self.assertEqual(r.status_code, 200, r.text)
        for client in (self.alice, self.bob):
            r = client.post(f"/api/practice/{sid}/consent", json={"consent": True})
            self.assertEqual(r.status_code, 200, r.text)
        r = self.alice.post(f"/api/practice/{sid}/state", json={"target": "live"})
        self.assertEqual(r.status_code, 200, r.text)

    # ── manifest / blob / keys ───────────────────────────────────────────────

    def test_manifest_no_keys(self):
        sid = self._new_session()
        r = self.bob.get(f"/api/practice/{sid}/exhibits")
        self.assertEqual(r.status_code, 200, r.text)
        exhibits = r.json()["exhibits"]
        self.assertEqual(len(exhibits), 2)
        self.assertEqual([e["idx"] for e in exhibits], [1, 2])
        for e in exhibits:
            self.assertEqual(len(base64.b64decode(e["iv_b64"])), 12)
            self.assertGreater(e["bytes"], len(_PLAINTEXTS[0]))  # ciphertext + tag
        self.assertNotIn("key", r.text)      # neither key_b64 nor enc_key
        self.assertNotIn("blob_path", r.text)

        self.assertEqual(self.cara.get(f"/api/practice/{sid}/exhibits").status_code, 404)
        self.assertEqual(self.anon.get(f"/api/practice/{sid}/exhibits").status_code, 401)

    def test_blob_is_ciphertext_only(self):
        sid = self._new_session()
        eid = self.exhibits[0]["id"]
        r = self.bob.get(f"/api/practice/{sid}/exhibit-blob/{eid}")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.headers["content-type"], "application/octet-stream")
        self.assertFalse(r.content.startswith(b"RIFF"), "blob served as plaintext")
        self.assertNotIn(b"WEBP", r.content[:16])
        self.assertEqual(len(r.content), len(_PLAINTEXTS[0]) + 16)  # +GCM tag

        self.assertEqual(
            self.cara.get(f"/api/practice/{sid}/exhibit-blob/{eid}").status_code, 404)
        self.assertEqual(
            self.bob.get(f"/api/practice/{sid}/exhibit-blob/999999").status_code, 404)

    def test_keys_interviewer_only(self):
        sid = self._new_session()
        r = self.alice.get(f"/api/practice/{sid}/exhibit-keys")
        self.assertEqual(r.status_code, 200, r.text)
        keys = r.json()["keys"]
        self.assertEqual(len(keys), 2)
        for k in keys:
            self.assertEqual(len(base64.b64decode(k["key_b64"])), 32)
            self.assertEqual(len(base64.b64decode(k["iv_b64"])), 12)

        self.assertEqual(self.bob.get(f"/api/practice/{sid}/exhibit-keys").status_code, 403)
        self.assertEqual(self.cara.get(f"/api/practice/{sid}/exhibit-keys").status_code, 404)

    # ── reveal flow ──────────────────────────────────────────────────────────

    def test_reveal_flow_and_fallback_key(self):
        sid = self._new_session()
        eid = self.exhibits[0]["id"]

        # Pre-live: no reveals allowed, no fallback key either.
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid})
        self.assertEqual(r.status_code, 409)
        self.assertEqual(
            self.bob.get(f"/api/practice/{sid}/exhibit-key/{eid}").status_code, 404)

        self._go_live(sid)

        # Wrong actor / bogus exhibit.
        r = self.bob.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid})
        self.assertEqual(r.status_code, 403)
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": 999999})
        self.assertEqual(r.status_code, 404)

        # Cross-origin POST blocked (DV-8).
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid},
                            headers={"Origin": "https://evil.example"})
        self.assertEqual(r.status_code, 403)

        # The real reveal.
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid})
        self.assertEqual(r.status_code, 200, r.text)
        reveal = r.json()
        self.assertFalse(reveal["already_revealed"])
        self.assertGreaterEqual(reveal["t_offset_ms"], 0)
        self.assertLess(reveal["t_offset_ms"], 60_000)

        # Idempotent: same row back, no duplicate.
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["already_revealed"])
        self.assertEqual(r.json()["t_offset_ms"], reveal["t_offset_ms"])

        # Reveal list visible to both participants, with display idx.
        for client in (self.alice, self.bob):
            r = client.get(f"/api/practice/{sid}/reveals")
            self.assertEqual(r.status_code, 200)
            rows = r.json()["reveals"]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["exhibit_id"], eid)
            self.assertEqual(rows[0]["idx"], 1)

        # Fallback key: candidate gets it now — and it actually decrypts.
        r = self.bob.get(f"/api/practice/{sid}/exhibit-key/{eid}")
        self.assertEqual(r.status_code, 200, r.text)
        key = base64.b64decode(r.json()["key_b64"])
        iv = base64.b64decode(r.json()["iv_b64"])
        blob = self.bob.get(f"/api/practice/{sid}/exhibit-blob/{eid}").content

        from webapp.exhibit_crypto import decrypt_exhibit
        plaintext = decrypt_exhibit(blob, key, iv)
        self.assertEqual(plaintext, _PLAINTEXTS[0])
        self.assertTrue(plaintext.startswith(b"RIFF"))

        # Wrong roles on the fallback endpoint.
        self.assertEqual(
            self.alice.get(f"/api/practice/{sid}/exhibit-key/{eid}").status_code, 403)
        self.assertEqual(
            self.cara.get(f"/api/practice/{sid}/exhibit-key/{eid}").status_code, 404)

        # Unrevealed exhibit still locked.
        other = self.exhibits[1]["id"]
        self.assertEqual(
            self.bob.get(f"/api/practice/{sid}/exhibit-key/{other}").status_code, 404)

    def test_debrief_semantics(self):
        sid = self._new_session()
        eid1, eid2 = self.exhibits[0]["id"], self.exhibits[1]["id"]
        self._go_live(sid)
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid1})
        self.assertEqual(r.status_code, 200)

        r = self.alice.post(f"/api/practice/{sid}/state", json={"target": "debrief"})
        self.assertEqual(r.status_code, 200, r.text)

        # Timeline survives into debrief (T6.4); revealed key stays available
        # (the candidate has seen it — spec's accepted tradeoff); NEW reveals
        # are rejected, but re-posting an old one stays idempotent-OK.
        self.assertEqual(self.bob.get(f"/api/practice/{sid}/reveals").status_code, 200)
        self.assertEqual(
            self.bob.get(f"/api/practice/{sid}/exhibit-key/{eid1}").status_code, 200)
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid2})
        self.assertEqual(r.status_code, 409)
        r = self.alice.post(f"/api/practice/{sid}/reveals", json={"exhibit_id": eid1})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["already_revealed"])


if __name__ == "__main__":
    unittest.main()
