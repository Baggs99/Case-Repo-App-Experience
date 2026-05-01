"""
Random tokens for verification links and session IDs.

Two-part pattern (used for email verification):
  - Generate a random token (URL-safe, ~43 chars).
  - Send the RAW token to the user (in the email).
  - Store the SHA-256 HASH in the database — never the raw token.
  - On verification: hash the incoming token and look up by hash.

Why hash even though we control the database? Defense in depth: a SQL
injection or backup leak doesn't hand attackers usable verification links.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets


# 32 random bytes → ~43 URL-safe characters. >256 bits of entropy, far
# beyond brute-force reach.
TOKEN_BYTES = 32


def generate_token() -> tuple[str, str]:
    """Return (raw_token, token_hash). Send raw to user, store hash in DB."""
    raw = secrets.token_urlsafe(TOKEN_BYTES)
    return raw, hash_token(raw)


def hash_token(raw: str) -> str:
    """SHA-256 of the raw token, hex-encoded (64 chars)."""
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def constant_time_equals(a: str, b: str) -> bool:
    """Wrapper for `hmac.compare_digest` — used for hash comparisons to
    avoid leaking timing information about which characters match."""
    return hmac.compare_digest(a, b)
