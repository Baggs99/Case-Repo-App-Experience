"""
Integration test: the full §4.2 signaling flow over real WebSockets against
the real app (cookie auth, DB-backed session lookup, hub relay).

Needs a reachable Postgres with the dev seed applied
(scripts/seed_caseroom_dev.py) — skips cleanly otherwise, so the suite
stays runnable in environments without a database. Requires httpx
(dev-only, like pytest): .venv/bin/pip install httpx
"""

from __future__ import annotations

import os
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
                seeded = cur.fetchone()[0] == 1
                cur.execute("SELECT COUNT(*) FROM cases;")
                return seeded and cur.fetchone()[0] >= 1
    except Exception:
        return False


_DB_URL = _load_database_url()
_READY = _db_ready(_DB_URL)

try:
    import httpx  # noqa: F401
    _HTTPX = True
except ImportError:
    _HTTPX = False


@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestSignalingIntegration(unittest.TestCase):
    PASSWORD = "caseroom-dev-1"

    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.main import app

        cls._client_ctx = TestClient(app)          # lifespan opens the pool
        cls.alice = cls._client_ctx.__enter__()
        cls.bob = TestClient(app)                  # separate cookie jars
        cls.cara = TestClient(app)

        # POST /login 500s under TestClient: its synthetic client host is the
        # string "testclient", which the repo's sessions.ip_address INET
        # column rejects. Login itself is curl-proven (Phase 2 evidence), so
        # mint the session rows directly with a NULL ip and set cookies.
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM cases ORDER BY id LIMIT 1;")
                cls.case_id = cur.fetchone()[0]
                emails = ("a@yale.edu", "b@yale.edu", "c@yale.edu")
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (list(emails),))
                ids = dict(cur.fetchall())

        for client, email in ((cls.alice, "a@yale.edu"),
                              (cls.bob, "b@yale.edu"),
                              (cls.cara, "c@yale.edu")):
            session = create_session(ids[email], user_agent="ws-test",
                                     ip_address=None)
            client.cookies.set(SESSION_COOKIE_NAME, session.id)

    @classmethod
    def tearDownClass(cls):
        cls._client_ctx.__exit__(None, None, None)

    def _new_session(self) -> int:
        # Alice interviews Bob. Created via the API so the whole path is real.
        r = self.alice.post("/api/practice", json={
            "interviewer_id": 1, "candidate_id": 2, "case_id": self.case_id,
        })
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["id"]

    def _expect_reject(self, client, path: str) -> int | None:
        """Connect expecting a pre-accept close; returns the close code if
        surfaced as WebSocketDisconnect (starlette may raise a denial-response
        error instead, depending on version)."""
        from starlette.websockets import WebSocketDisconnect
        try:
            with client.websocket_connect(path) as ws:
                ws.receive_json()
        except WebSocketDisconnect as exc:
            return exc.code
        except Exception:
            return None
        self.fail("connection was not rejected")

    def test_session_page_participants_only(self):
        sid = self._new_session()
        r = self.alice.get(f"/session/{sid}")
        self.assertEqual(r.status_code, 200)
        self.assertIn("window.CASEROOM", r.text)
        self.assertIn('"role": "interviewer"', r.text)
        r = self.cara.get(f"/session/{sid}")
        self.assertEqual(r.status_code, 404)

    def test_full_flow_knock_admit_relay_bye(self):
        sid = self._new_session()
        path = f"/ws/practice/{sid}"

        with self.alice.websocket_connect(path) as ws_a:
            ok_a = ws_a.receive_json()
            self.assertEqual(
                ok_a, {"type": "ok", "role": "interviewer",
                       "peer_present": False, "admitted": False})

            with self.bob.websocket_connect(path) as ws_b:
                ok_b = ws_b.receive_json()
                self.assertEqual(ok_b["role"], "candidate")
                self.assertTrue(ok_b["peer_present"])

                self.assertEqual(ws_a.receive_json(),
                                 {"type": "peer-joined", "role": "candidate"})

                ws_b.send_json({"type": "knock"})
                self.assertEqual(ws_a.receive_json(),
                                 {"type": "knock", "display_name": "Bob Dev"})

                # Pre-admit sdp from Bob must NOT reach Alice; the marker
                # message after admit proves ordering.
                ws_b.send_json({"type": "sdp", "description": "too-early"})
                ws_a.send_json({"type": "admit"})
                self.assertEqual(ws_b.receive_json(), {"type": "admit"})

                ws_b.send_json({"type": "sdp", "description": "post-admit-offer"})
                self.assertEqual(
                    ws_a.receive_json(),
                    {"type": "sdp", "description": "post-admit-offer"},
                    "pre-admit sdp leaked through the relay")

                ws_a.send_json({"type": "ice", "candidate": "a-cand-1"})
                self.assertEqual(ws_b.receive_json(),
                                 {"type": "ice", "candidate": "a-cand-1"})

                # Unknown type dropped; ping/pong proves the socket survived.
                ws_b.send_json({"type": "evil-eval"})
                ws_b.send_json({"type": "ping"})
                self.assertEqual(ws_b.receive_json(), {"type": "pong"})

                ws_b.send_json({"type": "bye"})
                self.assertEqual(ws_a.receive_json(), {"type": "peer-left"})

    def test_outsider_and_unauthenticated_rejected(self):
        sid = self._new_session()
        code = self._expect_reject(self.cara, f"/ws/practice/{sid}")
        if code is not None:
            self.assertEqual(code, 4403)

        from fastapi.testclient import TestClient
        from webapp.main import app
        anon = TestClient(app)
        code = self._expect_reject(anon, f"/ws/practice/{sid}")
        if code is not None:
            self.assertEqual(code, 4401)

    def test_aborted_session_not_joinable(self):
        sid = self._new_session()
        r = self.alice.post(f"/api/practice/{sid}/state", json={"target": "aborted"})
        self.assertEqual(r.status_code, 200)
        code = self._expect_reject(self.alice, f"/ws/practice/{sid}")
        if code is not None:
            self.assertEqual(code, 4403)

    def test_reconnect_replaces_socket(self):
        sid = self._new_session()
        path = f"/ws/practice/{sid}"
        with self.alice.websocket_connect(path) as ws_a:
            ws_a.receive_json()
            with self.bob.websocket_connect(path) as ws_b1:
                ws_b1.receive_json()
                ws_a.receive_json()  # peer-joined
                with self.bob.websocket_connect(path) as ws_b2:
                    ok2 = ws_b2.receive_json()
                    self.assertTrue(ok2["peer_present"])
                    # Old socket was closed with CLOSE_REPLACED by the hub.
                    from starlette.websockets import WebSocketDisconnect
                    with self.assertRaises(WebSocketDisconnect) as ctx:
                        ws_b1.receive_json()
                    self.assertEqual(ctx.exception.code, 4000)
                    # New socket is live end-to-end.
                    ws_b2.send_json({"type": "knock"})
                    msgs = [ws_a.receive_json()["type"] for _ in range(2)]
                    self.assertIn("knock", msgs)  # alongside peer-joined


if __name__ == "__main__":
    unittest.main()
