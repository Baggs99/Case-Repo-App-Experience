"""
Storage abstraction for case PDFs.

All implementations speak the same vocabulary so callers (the publisher, the
web app, the verifier) never know whether the PDF lives on local disk, in
S3, in Cloudflare R2, or anywhere else.

Key conventions
---------------
- Every PDF is identified by a `key` string.
- Keys use forward slashes regardless of OS.
- Keys are relative to the storage root (no leading slash, no drive letter).
- Keys may NOT contain `..` segments.

Example key:  "Booth/Booth 2026/retirement-apartment-complex.pdf"
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path
from typing import BinaryIO, Optional


class Storage(ABC):
    """Abstract base class — every storage backend implements these methods."""

    @abstractmethod
    def exists(self, key: str) -> bool:
        """Return True iff a PDF is stored under `key`."""

    @abstractmethod
    def open(self, key: str) -> BinaryIO:
        """Open the PDF at `key` for binary reading. Caller closes."""

    @abstractmethod
    def size(self, key: str) -> int:
        """Return the size of the PDF at `key` in bytes."""

    @abstractmethod
    def url(
        self,
        key: str,
        expires_in: Optional[int] = None,
        *,
        attachment_filename: Optional[str] = None,
    ) -> str:
        """Return a URL the browser can fetch.

        For local storage this is a relative path served by the web app.
        For cloud storage this is a signed URL that expires in `expires_in`
        seconds (defaults to 1 hour). Never returns a permanent public URL —
        we always want fine-grained access control.

        When ``attachment_filename`` is set, cloud backends should hint
        ``Content-Disposition: attachment`` so browsers save the file.
        """

    @abstractmethod
    def write(self, key: str, data: bytes, *, content_type: str) -> None:
        """Store `data` under `key`, replacing any existing object.

        `content_type` is the MIME type (e.g. 'image/png') — cloud backends
        persist it so served URLs carry the right Content-Type. Callers
        validate size/type before calling; this method just persists bytes.
        """

    def local_path(self, key: str) -> Optional[Path]:
        """If the storage backend has a real filesystem path for this key,
        return it. Otherwise return None.

        Used by the web app's PDF route: filesystem paths can be served
        with FastAPI's FileResponse (which uses the OS sendfile syscall),
        which is dramatically faster than streaming through Python.
        Cloud backends return None and the route falls back to redirecting
        to a signed URL.
        """
        return None


def validate_key(key: str) -> None:
    """Raise ValueError if `key` violates our conventions.

    Centralized so every backend rejects unsafe keys identically — defense
    against path traversal attempts (`../../../etc/passwd`) and absolute
    paths sneaking in.
    """
    if not key:
        raise ValueError("storage key may not be empty")
    if key.startswith("/"):
        raise ValueError(f"storage key must be relative, got {key!r}")
    if "\\" in key:
        raise ValueError(f"storage key must use forward slashes, got {key!r}")
    if ".." in key.split("/"):
        raise ValueError(f"storage key may not contain '..', got {key!r}")
