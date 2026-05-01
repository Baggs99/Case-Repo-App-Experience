"""
Storage backends for case PDFs.

Public API
----------
- `Storage`              the abstract interface
- `LocalStorage`         filesystem-backed implementation
- `get_storage()`        factory that reads env vars and returns the configured backend
- `to_storage_key(...)`  utility for turning legacy absolute pdf paths into keys

Cloud backends (R2 / S3 / Supabase Storage) are not yet implemented — see the
TODO in `pipeline/storage/cloud.py` when you're ready to deploy.
"""

from __future__ import annotations

import os
from pathlib import Path

from .base import Storage, validate_key
from .local import LocalStorage


__all__ = [
    "Storage",
    "LocalStorage",
    "validate_key",
    "get_storage",
    "to_storage_key",
]


# Default base dir = <repo>/output/cases. Computed once at import time so
# tests can override via STORAGE_LOCAL_DIR without monkey-patching.
_DEFAULT_BASE = Path(__file__).resolve().parents[2] / "output" / "cases"


def get_storage() -> Storage:
    """Return the configured storage backend.

    Reads two environment variables:
      - STORAGE_BACKEND     'local' (default) | 's3' | 'r2' | 'supabase'
      - STORAGE_LOCAL_DIR   override base dir for LocalStorage
    """
    backend = os.environ.get("STORAGE_BACKEND", "local").lower()

    if backend == "local":
        base = os.environ.get("STORAGE_LOCAL_DIR", str(_DEFAULT_BASE))
        return LocalStorage(base)

    if backend in ("s3", "r2", "supabase"):
        raise NotImplementedError(
            f"Storage backend {backend!r} is not yet implemented. "
            "Add an S3-compatible backend in pipeline/storage/cloud.py "
            "when you're ready to deploy."
        )

    raise ValueError(
        f"Unknown STORAGE_BACKEND {backend!r}. "
        "Valid values: 'local', 's3', 'r2', 'supabase'."
    )


def to_storage_key(raw_path: str) -> str | None:
    """Convert a legacy absolute pdf path into a portable storage key.

    Looks for the `output/cases/` (or `output\\cases\\`) marker in the path
    and returns everything after it, normalized to forward slashes.

    Examples
    --------
    >>> to_storage_key(r"C:\\Users\\Dan\\Desktop\\Case Repo\\output\\cases\\Booth\\Booth 2026\\foo.pdf")
    'Booth/Booth 2026/foo.pdf'
    >>> to_storage_key("output/cases/Yale/Yale 2025/bar.pdf")
    'Yale/Yale 2025/bar.pdf'
    >>> to_storage_key("Booth/Booth 2026/already-a-key.pdf")
    'Booth/Booth 2026/already-a-key.pdf'
    """
    if not raw_path:
        return None

    p = raw_path.replace("\\", "/").strip()

    marker = "/output/cases/"
    idx = p.lower().find(marker)
    if idx >= 0:
        return p[idx + len(marker):]

    marker = "output/cases/"
    if p.lower().startswith(marker):
        return p[len(marker):]

    if p.lower().endswith(".pdf") and "/" in p and ".." not in p.split("/"):
        return p.lstrip("/")

    return None
