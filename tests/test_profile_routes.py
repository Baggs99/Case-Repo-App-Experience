"""
Purpose: /api/v1 profile, photo, and notification-settings endpoints — auth
         guard, validation, upload whitelist/size cap, IDOR (photo key derives
         from the authed user, never client input).
Inputs:  seeded dev Postgres via tests.test_ws_integration; users a/b@yale.edu.
         STORAGE_BACKEND defaults to local (writes under a temp dir).
Outputs: writes profile fields + an avatar file + notification_settings; cleans up.
Run:     .venv/bin/python -m pytest tests/test_profile_routes.py -q
"""

from __future__ import annotations

import os
import struct
import tempfile
import unittest
import zlib

import psycopg

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY


def _png_bytes() -> bytes:
    # Minimal valid 1x1 PNG (signature + IHDR + IDAT + IEND).
    sig = b"\x89PNG\r\n\x1a\n"
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    idat = zlib.compress(b"\x00\xff\x00\x00")
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


@unittest.skipUnless(_READY and _HTTPX, "requires seeded dev Postgres + httpx")
class TestProfileRoutes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._storage_tmp = tempfile.TemporaryDirectory()
        os.environ["STORAGE_BACKEND"] = "local"
        os.environ["STORAGE_LOCAL_DIR"] = cls._storage_tmp.name

        from fastapi.testclient import TestClient
        from webapp.main import app
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session

        cls._ctx = TestClient(app)
        cls.alice = cls._ctx.__enter__()
        cls.bob = TestClient(app)

        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
                            (["a@yale.edu", "b@yale.edu"],))
                ids = dict(cur.fetchall())
        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]
        cls.alice.cookies.set(SESSION_COOKIE_NAME,
                              create_session(cls.aid, ip_address=None).id)
        cls.bob.cookies.set(SESSION_COOKIE_NAME,
                            create_session(cls.bid, ip_address=None).id)

    @classmethod
    def tearDownClass(cls):
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("UPDATE users SET bio=NULL, linkedin_url=NULL, "
                            "photo_key=NULL WHERE id = ANY(%s);", ([cls.aid, cls.bid],))
                cur.execute("DELETE FROM notification_settings WHERE user_id = ANY(%s);",
                            ([cls.aid, cls.bid],))
        cls._ctx.__exit__(None, None, None)
        cls._storage_tmp.cleanup()
        os.environ.pop("STORAGE_LOCAL_DIR", None)

    def test_profile_requires_auth(self):
        from fastapi.testclient import TestClient
        from webapp.main import app
        anon = TestClient(app)
        self.assertEqual(anon.get("/api/v1/profile").status_code, 401)

    def test_get_profile_shape(self):
        r = self.alice.get("/api/v1/profile")
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body["email"], "a@yale.edu")
        self.assertEqual(body["school"]["domain"], "yale.edu")
        self.assertIn("photo_url", body)

    def test_put_profile_updates_and_validates(self):
        r = self.alice.put("/api/v1/profile",
                           json={"bio": "MBA '26", "linkedin_url": "https://li/in/a"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.json()["bio"], "MBA '26")
        # too-long bio rejected
        r = self.alice.put("/api/v1/profile", json={"bio": "x" * 2001})
        self.assertEqual(r.status_code, 422)

    def test_put_profile_rejects_non_http_linkedin(self):
        # A non-http(s) scheme (e.g. javascript:) must be rejected.
        r = self.alice.put("/api/v1/profile",
                           json={"linkedin_url": "javascript:alert(1)"})
        self.assertEqual(r.status_code, 422)
        # A valid https:// URL is still accepted.
        r = self.alice.put("/api/v1/profile",
                           json={"linkedin_url": "https://li/in/alice"})
        self.assertEqual(r.status_code, 200, r.text)

    def test_photo_upload_happy_path_and_key(self):
        r = self.alice.post("/api/v1/profile/photo",
                            files={"file": ("a.png", _png_bytes(), "image/png")})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertIn("photo_url", r.json())
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT photo_key FROM users WHERE id = %s;", (self.aid,))
                key = cur.fetchone()[0]
        # IDOR: key is bound to the authenticated user's id, not client input.
        self.assertEqual(key, f"avatars/{self.aid}.png")

    def test_photo_rejects_bad_content_type(self):
        r = self.alice.post("/api/v1/profile/photo",
                            files={"file": ("a.gif", b"GIF89a", "image/gif")})
        self.assertEqual(r.status_code, 415)

    def test_photo_rejects_oversize(self):
        big = _png_bytes() + b"\x00" * (5 * 1024 * 1024 + 1)
        r = self.alice.post("/api/v1/profile/photo",
                            files={"file": ("a.png", big, "image/png")})
        self.assertEqual(r.status_code, 413)

    def test_photo_oversize_still_413_bounded(self):
        # A body far larger than the cap is still rejected — the handler now
        # bounds its read to cap+1 instead of buffering the whole upload.
        big = _png_bytes() + b"\x00" * (6 * 1024 * 1024)
        r = self.alice.post("/api/v1/profile/photo",
                            files={"file": ("a.png", big, "image/png")})
        self.assertEqual(r.status_code, 413)

    def test_photo_rejects_spoofed_magic_bytes(self):
        r = self.alice.post("/api/v1/profile/photo",
                            files={"file": ("a.png", b"not-a-real-png", "image/png")})
        self.assertEqual(r.status_code, 415)

    def test_notification_settings_get_put(self):
        r = self.alice.get("/api/v1/settings/notifications")
        self.assertEqual(r.status_code, 200, r.text)
        self.assertTrue(r.json()["community"])
        r = self.alice.put("/api/v1/settings/notifications", json={"community": False})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertFalse(r.json()["community"])
        self.assertFalse(self.alice.get("/api/v1/settings/notifications").json()["community"])


if __name__ == "__main__":
    unittest.main()
