"""
Exhibit authoring tests: rendering (pure, in-memory PDF) and the full
authoring flow (POST → encrypted blobs on disk → decrypt roundtrip).
DB-backed parts skip without the seeded dev database, like the WS tests.
"""

from __future__ import annotations

import os
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
    """Authors on its OWN case row (sharing the seeded dummy PDF bytes) so
    the dev case's authored exhibits are never replaced by a test run — and
    because replace-after-reveal is now a 409 (DV-13), a shared case would
    break the suite the moment a dev session revealed from it."""

    @classmethod
    def setUpClass(cls):
        import shutil
        import tempfile
        cls._exhibits_dir = tempfile.mkdtemp(prefix="authoring-test-exhibits-")
        cls._rm = shutil.rmtree
        cls._prev_exhibits_dir = os.environ.get("EXHIBITS_DIR")
        os.environ["EXHIBITS_DIR"] = cls._exhibits_dir

        from fastapi.testclient import TestClient
        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
        from webapp.main import app

        cls._ctx = TestClient(app)
        cls.client = cls._ctx.__enter__()

        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
                cls.uid = cur.fetchone()[0]
                cur.execute("SELECT id FROM users WHERE email = 'b@yale.edu';")
                cls.uid_b = cur.fetchone()[0]
                cur.execute(
                    "INSERT INTO cases (case_title, normalized_title, source_school,"
                    " source_year, industry, case_type, difficulty, difficulty_score,"
                    " page_count, pdf_path)"
                    " SELECT 'Authoring Test Case', 'authoring test case',"
                    " 'DevSchool', 2098, industry, case_type, difficulty,"
                    " difficulty_score, page_count, pdf_path"
                    " FROM cases WHERE case_title = 'Dev Dummy Case'"
                    " RETURNING id;")
                cls.case_id = cur.fetchone()[0]
        session = create_session(cls.uid, user_agent="exhibit-test", ip_address=None)
        cls.client.cookies.set(SESSION_COOKIE_NAME, session.id)

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
        cls._ctx.__exit__(None, None, None)
        cls._rm(cls._exhibits_dir, ignore_errors=True)
        if cls._prev_exhibits_dir is None:
            os.environ.pop("EXHIBITS_DIR", None)
        else:
            os.environ["EXHIBITS_DIR"] = cls._prev_exhibits_dir

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

    def test_reauthor_blocked_after_reveal(self):
        """DV-13: once an exhibit is in a session's reveal record, the
        case's exhibit set can no longer be replaced."""
        r = self.client.post(f"/api/cases/{self.case_id}/exhibits",
                             json={"pages": [{"page": 1}]})
        self.assertEqual(r.status_code, 200, r.text)
        exhibit_id = r.json()["exhibits"][0]["id"]

        r = self.client.post("/api/practice", json={
            "interviewer_id": self.uid, "candidate_id": self.uid_b,
            "case_id": self.case_id,
        })
        self.assertEqual(r.status_code, 200, r.text)
        sid = r.json()["id"]
        import psycopg
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO reveals (session_id, exhibit_id, t_offset_ms)"
                    " VALUES (%s, %s, 1000);", (sid, exhibit_id))

        r = self.client.post(f"/api/cases/{self.case_id}/exhibits",
                             json={"pages": [{"page": 1}, {"page": 2}]})
        self.assertEqual(r.status_code, 409, r.text)
        self.assertIn("reveal record", r.json()["detail"])

        # Remove the reveal (via its session) so other tests in this class
        # can author again regardless of method execution order.
        with psycopg.connect(_DB_URL) as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM practice_sessions WHERE id = %s;", (sid,))


if __name__ == "__main__":
    unittest.main()
