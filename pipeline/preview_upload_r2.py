"""Upload JPEGs from ``output/previews/{case_id}/`` to R2 for public CDN delivery."""

from __future__ import annotations

import logging
import os
from pathlib import Path

from pipeline.preview_generation import preview_dir, preview_jpeg_filename
from pipeline.public_preview_keys import public_preview_object_key
from pipeline.storage.cloud import R2Storage

logger = logging.getLogger(__name__)

_IMMUTABLE_YEAR = "public, max-age=31536000, immutable"


def maybe_upload_preview_jpegs(
    *,
    dest_root: Path,
    case_id: int,
    slug: str,
    pages_written: int,
) -> None:
    """If ``CASE_PREVIEW_PUBLIC_BASE_URL`` is set, push each JPEG to R2."""

    _pub = os.environ.get("CASE_PREVIEW_PUBLIC_BASE_URL", "").strip() or os.environ.get(
        "R2_PUBLIC_BASE_URL", ""
    ).strip()
    if not _pub:
        return
    if pages_written < 1:
        return

    try:
        storage = R2Storage.from_env()
    except RuntimeError as exc:
        logger.warning("Preview upload skipped — R2 not configured: %s", exc)
        return

    out_dir = preview_dir(dest_root, case_id)
    n_ok = 0
    for page_num in range(1, pages_written + 1):
        fp = out_dir / preview_jpeg_filename(page_num)
        if not fp.is_file():
            logger.warning("[case %s] missing preview file %s", case_id, fp.name)
            continue
        key = public_preview_object_key(slug, page_num)
        storage.put_file(
            key,
            fp,
            content_type="image/jpeg",
            cache_control=_IMMUTABLE_YEAR,
        )
        n_ok += 1

    logger.info(
        "[case %s] uploaded %d preview JPEG(s) to R2 under previews/%s/",
        case_id,
        n_ok,
        slug,
    )
