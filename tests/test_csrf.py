"""
Unit tests for webapp.csrf (Origin-check CSRF guard).

Uses a duck-typed request stub — require_same_origin only touches
request.headers, so a full Starlette Request scope isn't needed.
"""

from __future__ import annotations

import unittest
from types import SimpleNamespace

from fastapi import HTTPException

from webapp.csrf import require_same_origin


def _request(headers: dict[str, str]) -> SimpleNamespace:
    return SimpleNamespace(headers=headers)


class TestRequireSameOrigin(unittest.TestCase):
    def test_same_origin_passes(self):
        require_same_origin(_request({
            "origin": "https://example.edu",
            "host": "example.edu",
        }))

    def test_same_origin_with_port_passes(self):
        require_same_origin(_request({
            "origin": "http://localhost:8000",
            "host": "localhost:8000",
        }))

    def test_host_case_insensitive(self):
        require_same_origin(_request({
            "origin": "https://Example.EDU",
            "host": "example.edu",
        }))

    def test_missing_origin_passes(self):
        # curl and same-origin GETs carry no Origin; non-browser clients have
        # no ambient cookie authority to abuse.
        require_same_origin(_request({"host": "example.edu"}))

    def test_cross_origin_rejected(self):
        with self.assertRaises(HTTPException) as ctx:
            require_same_origin(_request({
                "origin": "https://evil.example.com",
                "host": "example.edu",
            }))
        self.assertEqual(ctx.exception.status_code, 403)

    def test_null_origin_rejected(self):
        with self.assertRaises(HTTPException) as ctx:
            require_same_origin(_request({
                "origin": "null",
                "host": "example.edu",
            }))
        self.assertEqual(ctx.exception.status_code, 403)

    def test_port_mismatch_rejected(self):
        with self.assertRaises(HTTPException):
            require_same_origin(_request({
                "origin": "http://localhost:9999",
                "host": "localhost:8000",
            }))

    def test_garbage_origin_rejected(self):
        with self.assertRaises(HTTPException):
            require_same_origin(_request({
                "origin": "not a url",
                "host": "example.edu",
            }))


if __name__ == "__main__":
    unittest.main()
