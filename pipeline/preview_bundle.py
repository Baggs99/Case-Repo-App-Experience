"""
Lay out local ``output/previews/{case_id}/`` JPEGs as ``pv/<slug>/`` for manual R2 upload.

No network calls — only copies files. Slugs come from Postgres ``preview_public_slug``.
"""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from pipeline.preview_generation import preview_jpeg_filename

logger = logging.getLogger(__name__)


def _local_preview_case_dir(repo_root: Path, case_id: int) -> Path:
    """Where ``generate-previews`` writes JPEGs — read-only; do not mkdir here."""
    return repo_root / "output" / "previews" / str(case_id)


def bundle_previews_for_manual_upload(
    *,
    repo_root: Path,
    dest_root: Path,
    id_slug_rows: list[tuple[int, str]],
) -> tuple[int, int, int]:
    """
    Copy ``page-*.jpg`` into ``dest_root/pv/<slug>/``.

    Returns ``(cases_copied, cases_skipped_no_files, cases_skipped_bad_row)``.
    """
    n_ok = n_skip_nf = n_skip_bad = 0
    pv_root = dest_root / "pv"
    pv_root.mkdir(parents=True, exist_ok=True)

    for cid, slug in id_slug_rows:
        if not slug or not str(slug).strip():
            logger.warning("case %s: empty preview_public_slug — skipping", cid)
            n_skip_bad += 1
            continue

        src_dir = _local_preview_case_dir(repo_root, cid)
        first = src_dir / preview_jpeg_filename(1)
        if not first.is_file():
            logger.debug("case %s: no %s — skipping", cid, first.name)
            n_skip_nf += 1
            continue

        out_dir = pv_root / slug
        out_dir.mkdir(parents=True, exist_ok=True)

        for fp in sorted(src_dir.glob("page-*.jpg")):
            dest = out_dir / fp.name
            shutil.copy2(fp, dest)

        n_ok += 1

    return n_ok, n_skip_nf, n_skip_bad
