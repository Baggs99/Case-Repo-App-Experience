"""
End-to-end test for Task 5 (web exhibit reveal migrated off the WebRTC
DataChannel onto the signaling WebSocket, decision 5 — one protocol, two
clients): POST /api/practice/{sid}/reveals must broadcast the exhibit key to
the CANDIDATE's signaling WS connection.

Needs a reachable Postgres with the dev seed applied — same skip gate as
test_ws_integration.py / test_reveals.py. Creates its own case + exhibit
under a temp EXHIBITS_DIR and removes them.
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

# Valid-looking WebP plaintext so the round-trip decrypt assertion means
# something (not just "some bytes came back").
_PLAINTEXT = b"RIFF\x2c\x00\x00\x00WEBPVP8 fake-exhibit-ws-e2e-payload!"


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestRevealOverSignalingWs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._exhibits_dir = tempfile.mkdtemp(prefix="reveal-ws-e2e-exhibits-")
        cls._prev_exhibits_dir = os.environ.get("EXHIBITS_DIR")
        os.environ["EXHIBITS_DIR"] = cls._exhibits_dir

        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._client_ctx = TestClient(app)          # lifespan opens the pool
        cls.alice = cls._client_ctx.__enter__()    # interviewer
        cls.bob = TestClient(app)                  # candidate

        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = {email: uid for email, uid in cur.fetchall()}
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " VALUES ('Reveal WS E2E Case', 'reveal ws e2e case', 'DevSchool',"
                    " 2099, 'Technology', 'Profitability', 'Easy', 3.0, 1,"
                    " 'output/cases/devschool/nonexistent.pdf')"
                    " RETURNING id;"
                )
                cls.case_id = cur.fetchone()[0]
        cls.alice_id, cls.bob_id = ids["a@yale.edu"], ids["b@yale.edu"]

        for client, email in ((cls.alice, "a@yale.edu"), (cls.bob, "b@yale.edu")):
            session = create_session(ids[email], user_agent="reveal-ws-e2e-test",
                                     ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, session.id)

        # Author one exhibit directly at the repo layer (rendering is out of
        # scope here — this test starts at "an encrypted blob exists").
        from webapp.repositories import case_exhibits
        cls.exhibits = case_exhibits.replace_for_case(
            cls.case_id, cls.alice_id,
            [{"webp": _PLAINTEXT, "source_pages": "1", "width": 800, "height": 600}],
        )
        cls.exhibit_id = cls.exhibits[0]["id"]

    @classmethod
    def tearDownClass(cls):
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
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

    def test_reveal_post_broadcasts_key_to_candidate_ws(self):
        sid = self._new_session()
        self._go_live(sid)
        path = f"/ws/practice/{sid}"

        with self.alice.websocket_connect(path) as ws_a:
            ok_a = ws_a.receive_json()
            self.assertEqual(ok_a["role"], "interviewer")

            with self.bob.websocket_connect(path) as ws_b:
                ok_b = ws_b.receive_json()
                self.assertEqual(ok_b["role"], "candidate")
                self.assertEqual(ws_a.receive_json(), {"type": "peer-joined", "role": "candidate"})

                # The interviewer's reveal action, end to end: HTTP POST only
                # (no DataChannel relay) — the server broadcast must deliver
                # the key over THIS WebSocket.
                r = self.alice.post(f"/api/practice/{sid}/reveals",
                                    json={"exhibit_id": self.exhibit_id})
                self.assertEqual(r.status_code, 200, r.text)

                msg = ws_b.receive_json()
                self.assertEqual(msg["type"], "reveal")
                self.assertEqual(msg["exhibit_id"], self.exhibit_id)
                self.assertTrue(msg["key_b64"])
                key = base64.b64decode(msg["key_b64"])
                self.assertEqual(len(key), 32)

                # Prove it's really the exhibit's key: decrypt the blob with it.
                manifest = self.bob.get(f"/api/practice/{sid}/exhibits").json()["exhibits"]
                iv_b64 = next(e["iv_b64"] for e in manifest if e["exhibit_id"] == self.exhibit_id)
                blob = self.bob.get(
                    f"/api/practice/{sid}/exhibit-blob/{self.exhibit_id}").content

                from webapp.exhibit_crypto import decrypt_exhibit
                plaintext = decrypt_exhibit(blob, key, base64.b64decode(iv_b64))
                self.assertEqual(plaintext, _PLAINTEXT)

                # Reveal logging (system of record) still happened.
                rows = self.bob.get(f"/api/practice/{sid}/reveals").json()["reveals"]
                self.assertEqual(len(rows), 1)
                self.assertEqual(rows[0]["exhibit_id"], self.exhibit_id)


if __name__ == "__main__":
    unittest.main()
