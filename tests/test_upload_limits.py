"""
Unit tests for webapp.upload_limits (recording-chunk validation, spec INV-5).
"""

from __future__ import annotations

import unittest

from fastapi import HTTPException

from webapp.upload_limits import (
    MB,
    check_chunk_size,
    check_first_chunk_container,
    check_total_size,
)


class TestChunkSize(unittest.TestCase):
    def test_within_limit_passes(self):
        check_chunk_size(4 * MB, max_mb=8)

    def test_at_limit_passes(self):
        check_chunk_size(8 * MB, max_mb=8)

    def test_over_limit_413(self):
        with self.assertRaises(HTTPException) as ctx:
            check_chunk_size(8 * MB + 1, max_mb=8)
        self.assertEqual(ctx.exception.status_code, 413)

    def test_empty_chunk_400(self):
        with self.assertRaises(HTTPException) as ctx:
            check_chunk_size(0)
        self.assertEqual(ctx.exception.status_code, 400)


class TestTotalSize(unittest.TestCase):
    def test_under_cap_passes(self):
        check_total_size(100 * MB, 10 * MB, max_mb=150)

    def test_over_cap_413(self):
        with self.assertRaises(HTTPException) as ctx:
            check_total_size(145 * MB, 6 * MB, max_mb=150)
        self.assertEqual(ctx.exception.status_code, 413)


class TestFirstChunkContainer(unittest.TestCase):
    WEBM_HEAD = b"\x1a\x45\xdf\xa3" + b"\x00" * 16
    MP4_HEAD = b"\x00\x00\x00\x20ftypisom" + b"\x00" * 16

    def test_webm_accepted(self):
        check_first_chunk_container(self.WEBM_HEAD, "audio/webm;codecs=opus")

    def test_mp4_accepted(self):
        check_first_chunk_container(self.MP4_HEAD, "audio/mp4")

    def test_webm_bytes_with_mp4_mime_415(self):
        with self.assertRaises(HTTPException) as ctx:
            check_first_chunk_container(self.WEBM_HEAD, "audio/mp4")
        self.assertEqual(ctx.exception.status_code, 415)

    def test_unknown_mime_415(self):
        with self.assertRaises(HTTPException):
            check_first_chunk_container(self.WEBM_HEAD, "audio/ogg")

    def test_garbage_bytes_415(self):
        with self.assertRaises(HTTPException):
            check_first_chunk_container(b"not-a-container", "audio/webm")


if __name__ == "__main__":
    unittest.main()
