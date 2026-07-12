"""
Recordings repository — per-participant mic recordings, chunk-appended in
strict seq order (spec §4.6, Phase 10).

Files live under RECORDINGS_DIR (default output/recordings/, gitignored and
never web-served — the FastAPI app only mounts /static, which is this
deploy's deny-all equivalent of the spec's .htaccess rule, T10.4). Serving
happens only through the authed passthrough route.

Ordering: the row is locked FOR UPDATE, the incoming seq must equal the
stored chunk count, bytes are appended, then counters advance — a client
retry of an already-applied seq gets a 409 that names the expected seq, so
the uploader can tell "already applied" from "gap".
"""

from __future__ import annotations

import os
import secrets
from pathlib import Path

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.practice_states import TransitionError

REPO_ROOT = Path(__file__).resolve().parents[2]

_EXT = {"audio/webm": "webm", "audio/mp4": "mp4"}


def _recordings_dir() -> Path:
    d = Path(os.environ.get("RECORDINGS_DIR", REPO_ROOT / "output" / "recordings"))
    d.mkdir(parents=True, exist_ok=True)
    return d


def append_chunk(*, session_id: int, user_id: int, role: str,
                 seq: int, mime: str, data: bytes) -> dict:
    """Create the row on seq 0, then append chunks in strict order.
    Raises TransitionError(409) on any seq mismatch or after complete."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT * FROM recordings WHERE session_id = %s AND user_id = %s"
                " FOR UPDATE;",
                (session_id, user_id),
            )
            row = cur.fetchone()

            if row is None:
                if seq != 0:
                    raise TransitionError(409, "expected seq 0")
                ext = _EXT.get(mime, "bin")
                name = f"rec_{session_id}_{user_id}_{secrets.token_hex(8)}.{ext}"
                cur.execute(
                    "INSERT INTO recordings (session_id, user_id, role, path,"
                    " mime) VALUES (%s, %s, %s, %s, %s) RETURNING *;",
                    (session_id, user_id, role, name, mime),
                )
                row = cur.fetchone()

            if row["completed"]:
                raise TransitionError(409, "Recording is already completed")
            if seq != row["chunks"]:
                raise TransitionError(409, f"expected seq {row['chunks']}")

            with open(_recordings_dir() / row["path"], "ab") as fh:
                fh.write(data)
            cur.execute(
                "UPDATE recordings SET chunks = chunks + 1, bytes = bytes + %s"
                " WHERE id = %s RETURNING *;",
                (len(data), row["id"]),
            )
            return cur.fetchone()


def complete(session_id: int, user_id: int) -> dict:
    """Finalize after the last chunk flushed. Idempotent."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "UPDATE recordings SET completed = TRUE"
                " WHERE session_id = %s AND user_id = %s RETURNING *;",
                (session_id, user_id),
            )
            row = cur.fetchone()
            if row is None:
                raise TransitionError(404, "No recording to complete")
            return row


def get_recording(session_id: int, user_id: int) -> dict | None:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT * FROM recordings WHERE session_id = %s AND user_id = %s;",
                (session_id, user_id),
            )
            return cur.fetchone()


def list_for_session(session_id: int) -> list[dict]:
    """Both sides' rows for the debrief/feedback views — metadata only,
    never the path (it's server-local)."""
    sql = """
        SELECT r.user_id, r.role, r.mime, r.bytes, r.chunks, r.completed,
               COALESCE(u.display_name, split_part(u.email::text, '@', 1)) AS name
        FROM recordings r JOIN users u ON u.id = r.user_id
        WHERE r.session_id = %s ORDER BY r.role;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (session_id,))
            return cur.fetchall()


def read_file(path_name: str) -> Path:
    """Absolute path for the download passthrough. path_name comes from the
    DB row (never user input), but stay paranoid about separators anyway."""
    if "/" in path_name or "\\" in path_name or ".." in path_name:
        raise ValueError(f"suspicious recording path {path_name!r}")
    return _recordings_dir() / path_name
