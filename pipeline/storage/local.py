"""
LocalStorage — serves case PDFs from a directory on the local filesystem.

Used for development and single-machine deployments. The web app should
mount a static-file route at `route_prefix` that maps requests to files
inside `base_dir`.
"""

from __future__ import annotations

from pathlib import Path
from typing import BinaryIO, Optional
from urllib.parse import quote

from .base import Storage, validate_key


class LocalStorage(Storage):
    def __init__(self, base_dir: Path | str, route_prefix: str = "/files"):
        self.base_dir = Path(base_dir).resolve()
        self.route_prefix = "/" + route_prefix.strip("/")

        if not self.base_dir.exists():
            raise FileNotFoundError(
                f"LocalStorage base_dir does not exist: {self.base_dir}"
            )

    def _full_path(self, key: str) -> Path:
        validate_key(key)
        return self.base_dir / key

    def exists(self, key: str) -> bool:
        return self._full_path(key).is_file()

    def open(self, key: str) -> BinaryIO:
        return self._full_path(key).open("rb")

    def size(self, key: str) -> int:
        return self._full_path(key).stat().st_size

    def write(self, key: str, data: bytes, *, content_type: str) -> None:
        _ = content_type  # local disk stores no MIME metadata; route sets it
        path = self._full_path(key)  # validates key (rejects '..', absolute, backslash)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def url(
        self,
        key: str,
        expires_in: Optional[int] = None,
        *,
        attachment_filename: Optional[str] = None,
    ) -> str:
        _ = attachment_filename  # routing layer sets Content-Disposition for local files
        validate_key(key)
        # Quote each path segment individually — joining first would
        # double-encode the slashes.
        encoded = "/".join(quote(seg) for seg in key.split("/"))
        return f"{self.route_prefix}/{encoded}"

    def local_path(self, key: str) -> Path | None:
        path = self._full_path(key)
        return path if path.is_file() else None

    def __repr__(self) -> str:
        return f"LocalStorage(base_dir={self.base_dir!r}, route_prefix={self.route_prefix!r})"
