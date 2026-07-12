"""
AES-256-GCM encryption for exhibit images at rest.

Exhibit blobs are preloaded to the candidate's browser *encrypted* before the
interviewer reveals them; the per-exhibit key crosses the wire only at reveal
time (DataChannel fast path, or the reveal-gated key endpoint). See
docs/caseroom-spec.md §4.4 and INTEGRATION.md DV-3/DV-4.

Interop constraint: the candidate decrypts with WebCrypto
(crypto.subtle.decrypt AES-GCM), which expects the 16-byte auth tag APPENDED
to the ciphertext. AESGCM.encrypt() produces exactly that layout — do not
split the tag off.
"""

from __future__ import annotations

import secrets

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

KEY_BYTES = 32   # AES-256
IV_BYTES = 12    # GCM-recommended nonce length; WebCrypto default


def encrypt_exhibit(plaintext: bytes) -> tuple[bytes, bytes, bytes]:
    """Encrypt one rendered exhibit image.

    Returns (ciphertext_with_tag, key, iv). Key and IV are freshly random per
    exhibit — a key is never reused across exhibits, so revealing one exhibit
    never unlocks another (spec's accepted per-exhibit-key tradeoff).
    """
    key = secrets.token_bytes(KEY_BYTES)
    iv = secrets.token_bytes(IV_BYTES)
    ciphertext = AESGCM(key).encrypt(iv, plaintext, None)
    return ciphertext, key, iv


def decrypt_exhibit(ciphertext: bytes, key: bytes, iv: bytes) -> bytes:
    """Decrypt an exhibit blob (server-side use: integrity checks, admin ops).

    Raises cryptography.exceptions.InvalidTag if the blob or key/IV is wrong
    or the ciphertext was tampered with.
    """
    return AESGCM(key).decrypt(iv, ciphertext, None)
