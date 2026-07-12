"""
Exhibit authoring tests: rendering (pure, in-memory PDF) and the full
authoring flow (POST → encrypted blobs on disk → decrypt roundtrip).
DB-backed parts skip without the seeded dev database, like the WS tests.
"""

from __future__ import annotations

import unittest

import fitz

from webapp.exhibits_render import page_count, render_exhibit_webp, render_page_thumb

from tests.test_ws_integration import _DB_URL, _HTTPX, _READY

WEBP_MAGIC_OFFSET = 8  # bytes 8..12 of a WebP file are b"WEBP"


def _pdf(pages: int = 3) -> bytes:
    doc = fitz.open()
    for i in range(pages):
        page = doc.new_page()
        page.insert_text((72, 100), f"render test page {i + 1}", fontsize=24)
    data = doc.tobytes()
    doc.close()
    return data


class TestRender(unittest.TestCase):
    def test_renders_webp_within_bounds(self):
        webp, w, h = render_exhibit_webp(_pdf(), 2)
        self.assertEqual(webp[WEBP_MAGIC_OFFSET:WEBP_MAGIC_OFFSET + 4], b"WEBP")
        self.assertLessEqual(max(w, h), 1800)

    def test_thumb_is_jpeg_and_small(self):
        jpeg = render_page_thumb(_pdf(), 1)
        self.assertEqual(jpeg[:3], b"\xff\xd8\xff")
        self.assertLess(len(jpeg), 100_000)

    def test_page_bounds(self):
        self.assertEqual(page_count(_pdf(3)), 3)
        with self.assertRaises(ValueError):
            render_exhibit_webp(_pdf(3), 4)
        with self.assertRaises(ValueError):
            render_exhibit_webp(_pdf(3), 0)


@unittest.skipUnless(_READY, "requires seeded dev Postgres")
@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
class TestAuthoringFlow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from fastapi.testclient import TestClient
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls.client = cls._ctx.__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                uid = cur.fetchone()[0]
                cur.execute("SELECT id FROM cases WHERE case_title = 'Dev Dummy Case';")
                cls.case_id = cur.fetchone()[0]
        session = create_session(uid, user_agent="exhibit-test", ip_address=None)
        cls.client.cookies.set(SESSION_COOKIE_NAME, session.id)

    @classmethod
    def tearDownClass(cls):
        cls._ctx.__exit__(None, None, None)

    def test_author_encrypt_store_decrypt(self):
        r = self.client.post(f"/api/cases/{self.case_id}/exhibits",
                             json={"pages": [{"page": 2}, {"page": 3}]})
        self.assertEqual(r.status_code, 200, r.text)
        exhibits = r.json()["exhibits"]
        self.assertEqual([e["idx"] for e in exhibits], [1, 2])

        from webapp.repositories.case_exhibits import read_blob
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT enc_blob_path, enc_key, enc_iv FROM case_exhibits"
                    " WHERE case_id = %s AND idx = 1;", (self.case_id,))
                path, key, iv = cur.fetchone()

        blob = read_blob(path)
        # At rest it must NOT look like an image (INV-6: ciphertext only).
        self.assertNotEqual(blob[WEBP_MAGIC_OFFSET:WEBP_MAGIC_OFFSET + 4], b"WEBP")

        from webapp.exhibit_crypto import decrypt_exhibit
        plain = decrypt_exhibit(blob, bytes(key), bytes(iv))
        self.assertEqual(plain[WEBP_MAGIC_OFFSET:WEBP_MAGIC_OFFSET + 4], b"WEBP")

    def test_page_beyond_range_rejected(self):
        r = self.client.post(f"/api/cases/{self.case_id}/exhibits",
                             json={"pages": [{"page": 40}]})
        self.assertEqual(r.status_code, 400)

    def test_thumb_endpoint(self):
        r = self.client.get(f"/api/cases/{self.case_id}/page-thumb/1")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.headers["content-type"], "image/jpeg")

    def test_authoring_page_renders(self):
        r = self.client.get(f"/cases/{self.case_id}/exhibits")
        self.assertEqual(r.status_code, 200)
        self.assertIn("Mark exhibits", r.text)


if __name__ == "__main__":
    unittest.main()
