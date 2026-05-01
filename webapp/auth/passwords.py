"""
Password hashing using argon2id — the OWASP-recommended algorithm as of 2024+.

Why argon2id (vs bcrypt or scrypt):
  - Memory-hard: GPU cracking is expensive
  - Side-channel resistant
  - Tunable cost parameters (we use the argon2-cffi defaults, which are
    calibrated to take ~50ms per hash on modern hardware)

Why never roll your own: timing attacks, salt mismanagement, and a hundred
other footguns. Use the library, don't reinvent.
"""

from __future__ import annotations

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, InvalidHashError, VerificationError


# Single shared hasher — argon2-cffi PasswordHasher is thread-safe.
_hasher = PasswordHasher()


# OWASP minimums; deliberately permissive (length matters far more than
# complexity rules per NIST SP 800-63B-4). We trust users to pick sensible
# passwords and rely on the slow hash + per-account salt to make brute force
# infeasible.
MIN_PASSWORD_LENGTH = 8
MAX_PASSWORD_LENGTH = 128


class WeakPasswordError(ValueError):
    """Raised when a password fails our minimal strength rules."""


def validate_password(plain: str) -> None:
    """Raise WeakPasswordError if `plain` is unacceptable.

    Note: we explicitly do NOT enforce mixed-case / digit / symbol rules.
    Modern guidance says these reduce real-world security by encouraging
    predictable transformations like 'Password!1'.
    """
    if len(plain) < MIN_PASSWORD_LENGTH:
        raise WeakPasswordError(
            f"Password must be at least {MIN_PASSWORD_LENGTH} characters."
        )
    if len(plain) > MAX_PASSWORD_LENGTH:
        raise WeakPasswordError(
            f"Password must be at most {MAX_PASSWORD_LENGTH} characters."
        )


def hash_password(plain: str) -> str:
    """Return an argon2id hash with embedded salt + parameters."""
    validate_password(plain)
    return _hasher.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    """Constant-time verify. Returns False for mismatches and malformed hashes;
    never raises (so callers can use it in simple boolean checks)."""
    try:
        return _hasher.verify(hashed, plain)
    except (VerifyMismatchError, InvalidHashError, VerificationError):
        return False


def needs_rehash(hashed: str) -> bool:
    """True if the hash was produced with weaker parameters than current
    defaults (e.g., after we tune up the work factor). Re-hash on next login."""
    try:
        return _hasher.check_needs_rehash(hashed)
    except (InvalidHashError, VerificationError):
        return False
