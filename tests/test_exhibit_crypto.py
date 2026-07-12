"""
Unit tests for webapp.exhibit_crypto (AES-256-GCM exhibit encryption).
"""

from __future__ import annotations

import unittest

from cryptography.exceptions import InvalidTag

from webapp.exhibit_crypto import (
    IV_BYTES,
    KEY_BYTES,
    decrypt_exhibit,
    encrypt_exhibit,
)


class TestExhibitCrypto(unittest.TestCase):
    def test_roundtrip(self):
        plaintext = b"RIFF....WEBPfake-exhibit-bytes" * 100
        ciphertext, key, iv = encrypt_exhibit(plaintext)
        self.assertEqual(decrypt_exhibit(ciphertext, key, iv), plaintext)

    def test_key_and_iv_lengths(self):
        _, key, iv = encrypt_exhibit(b"x")
        self.assertEqual(len(key), KEY_BYTES)
        self.assertEqual(len(iv), IV_BYTES)

    def test_tag_appended_to_ciphertext(self):
        # WebCrypto interop: ciphertext must be plaintext-length + 16-byte tag.
        plaintext = b"p" * 1000
        ciphertext, _, _ = encrypt_exhibit(plaintext)
        self.assertEqual(len(ciphertext), len(plaintext) + 16)

    def test_fresh_key_per_exhibit(self):
        _, key1, iv1 = encrypt_exhibit(b"a")
        _, key2, iv2 = encrypt_exhibit(b"a")
        self.assertNotEqual(key1, key2)
        self.assertNotEqual(iv1, iv2)

    def test_wrong_key_rejected(self):
        ciphertext, _, iv = encrypt_exhibit(b"secret exhibit")
        _, other_key, _ = encrypt_exhibit(b"other")
        with self.assertRaises(InvalidTag):
            decrypt_exhibit(ciphertext, other_key, iv)

    def test_tampered_ciphertext_rejected(self):
        ciphertext, key, iv = encrypt_exhibit(b"secret exhibit")
        tampered = bytes([ciphertext[0] ^ 0xFF]) + ciphertext[1:]
        with self.assertRaises(InvalidTag):
            decrypt_exhibit(tampered, key, iv)


if __name__ == "__main__":
    unittest.main()
