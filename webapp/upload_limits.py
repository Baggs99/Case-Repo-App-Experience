"""
Server-side upload validation for CaseRoom (spec INV-5).

v1's only client-upload surface is recording chunks (exhibits are rendered
server-side from library PDFs — INTEGRATION.md DV-2), so this module covers:
per-chunk size, per-session total, and first-chunk container sniffing.
Later chunks of a MediaRecorder stream are continuation bytes with no magic,
so only chunk 0 can be type-checked.

Limits come from env (MAX_REC_CHUNK_MB, MAX_REC_TOTAL_MB) with spec defaults;
callers pass them in so this module stays settings-free and testable.
"""

from __future__ import annotations

from fastapi import HTTPException

MB = 1024 * 1024

# Spec §9 defaults; override via env, threaded through by the caller.
DEFAULT_REC_CHUNK_MB = 8
DEFAULT_REC_TOTAL_MB = 150


def check_chunk_size(n_bytes: int, max_mb: int = DEFAULT_REC_CHUNK_MB) -> None:
    """413 when a single uploaded chunk exceeds the per-chunk ceiling."""
    if n_bytes > max_mb * MB:
        raise HTTPException(
            status_code=413,
            detail=f"Chunk exceeds {max_mb} MB limit",
        )
    if n_bytes == 0:
        raise HTTPException(status_code=400, detail="Empty chunk")


def check_total_size(existing_bytes: int, incoming_bytes: int,
                     max_mb: int = DEFAULT_REC_TOTAL_MB) -> None:
    """413 when appending a chunk would blow the per-session recording cap."""
    if existing_bytes + incoming_bytes > max_mb * MB:
        raise HTTPException(
            status_code=413,
            detail=f"Recording exceeds {max_mb} MB session limit",
        )


def check_first_chunk_container(data: bytes, mime: str) -> None:
    """415 unless chunk 0 looks like the container the client claims.

    MediaRecorder produces WebM (Chrome/Firefox: EBML magic) or fragmented
    MP4 (Safari: 'ftyp' box at offset 4).
    """
    if mime.startswith("audio/webm"):
        ok = data[:4] == b"\x1a\x45\xdf\xa3"
    elif mime.startswith("audio/mp4"):
        ok = len(data) >= 8 and data[4:8] == b"ftyp"
    else:
        ok = False
    if not ok:
        raise HTTPException(
            status_code=415,
            detail=f"First chunk does not match declared type {mime!r}",
        )
