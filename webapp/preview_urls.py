"""Build preview image URLs — same-origin (`/files/...`) vs public CDN URLs."""

from __future__ import annotations

from typing import Any

from pipeline.public_preview_keys import public_preview_object_key

from webapp.settings import Settings


def preview_r2_storage_key(slug: str, page_num: int) -> str:
    """R2 object key for a page JPEG under an opaque slug."""
    return public_preview_object_key(slug, page_num)


def preview_page_urls(
    *,
    case_id: int,
    case_row: dict[str, Any],
    page_count: int,
    settings: Settings,
) -> list[str]:
    """Return ordered URLs for pages 1..page_count inclusive."""
    if page_count < 1:
        return []

    slug = case_row.get("preview_public_slug")
    base = settings.case_preview_public_base_url
    if base and slug:
        root = base.rstrip("/")
        return [f"{root}/pv/{slug}/page-{i:03d}.jpg" for i in range(1, page_count + 1)]

    return [f"/files/cases/{case_id}/preview/{i}" for i in range(1, page_count + 1)]
