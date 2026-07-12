"""
Case-exhibits repository — SQL for case_exhibits plus the encrypt-and-store
step. Blobs are AES-256-GCM ciphertext on local disk under EXHIBITS_DIR
(default output/exhibits/, never web-served); keys/IVs live only in the DB.
The read-only Storage abstraction has no write path, so exhibits use plain
file I/O like the rest of the pipeline's outputs (INTEGRATION.md DV-12).
"""

from __future__ import annotations

import os
import secrets
from pathlib import Path

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.exhibit_crypto import encrypt_exhibit

REPO_ROOT = Path(__file__).resolve().parents[2]


def _exhibits_dir() -> Path:
    d = Path(os.environ.get("EXHIBITS_DIR", REPO_ROOT / "output" / "exhibits"))
    d.mkdir(parents=True, exist_ok=True)
    return d


def list_for_case(case_id: int) -> list[dict]:
    sql = """
        SELECT id, case_id, idx, source_pages, width, height, bytes, created_by
        FROM case_exhibits WHERE case_id = %s ORDER BY idx;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (case_id,))
            return cur.fetchall()


def replace_for_case(case_id: int, created_by: int,
                     rendered: list[dict]) -> list[dict]:
    """Replace a case's exhibit set atomically. `rendered` items:
    {webp: bytes, source_pages: str, width: int, height: int}, in display
    order. Encrypts and writes each blob, then swaps the DB rows in one
    transaction; old blob files are removed after commit."""
    new_rows, new_paths = [], []
    for i, item in enumerate(rendered, start=1):
        ciphertext, key, iv = encrypt_exhibit(item["webp"])
        name = f"ex_{case_id}_{i}_{secrets.token_hex(8)}.bin"
        path = _exhibits_dir() / name
        path.write_bytes(ciphertext)
        new_paths.append(path)
        new_rows.append((case_id, i, item["source_pages"], name, key, iv,
                         item["width"], item["height"], len(ciphertext), created_by))

    try:
        with get_pool().connection() as conn:
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute("SELECT enc_blob_path FROM case_exhibits"
                            " WHERE case_id = %s;", (case_id,))
                old_files = [r["enc_blob_path"] for r in cur.fetchall()]
                cur.execute("DELETE FROM case_exhibits WHERE case_id = %s;", (case_id,))
                for row in new_rows:
                    cur.execute(
                        "INSERT INTO case_exhibits (case_id, idx, source_pages,"
                        " enc_blob_path, enc_key, enc_iv, width, height, bytes,"
                        " created_by) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s);",
                        row,
                    )
    except Exception:
        for p in new_paths:
            p.unlink(missing_ok=True)  # don't strand ciphertext on failure
        raise

    for name in old_files:
        (_exhibits_dir() / name).unlink(missing_ok=True)
    return list_for_case(case_id)


def read_blob(enc_blob_path: str) -> bytes:
    return (_exhibits_dir() / enc_blob_path).read_bytes()
