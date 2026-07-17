"""
Purpose: LocalStorage.write persists bytes under a key and rejects unsafe keys.
Inputs:  a temp dir as the storage base.
Outputs: writes only inside the temp dir (auto-cleaned).
Run:     .venv/bin/python -m pytest tests/test_storage_write.py -q
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from pipeline.storage.local import LocalStorage


class TestLocalStorageWrite(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name)
        self.storage = LocalStorage(self.base)

    def tearDown(self):
        self._tmp.cleanup()

    def test_write_persists_bytes_and_creates_dirs(self):
        self.storage.write("avatars/42.png", b"\x89PNG-bytes", content_type="image/png")
        self.assertTrue(self.storage.exists("avatars/42.png"))
        self.assertEqual((self.base / "avatars" / "42.png").read_bytes(), b"\x89PNG-bytes")

    def test_write_rejects_traversal_key(self):
        with self.assertRaises(ValueError):
            self.storage.write("../escape.png", b"x", content_type="image/png")

    def test_write_overwrites(self):
        self.storage.write("avatars/7.png", b"old", content_type="image/png")
        self.storage.write("avatars/7.png", b"new", content_type="image/png")
        self.assertEqual((self.base / "avatars" / "7.png").read_bytes(), b"new")


if __name__ == "__main__":
    unittest.main()
