"""R2/object-storage key layout for externally hosted preview JPEGs."""

from __future__ import annotations


def public_preview_object_key(slug: str, page_num: int) -> str:
    """Object key under bucket root: ``previews/<slug>/page-NNN.jpg``."""
    return f"previews/{slug}/page-{page_num:03d}.jpg"


def public_preview_knit_object_key(slug: str) -> str:
    """Vertically stitched preview for optional long-scroll UI."""
    return f"previews/{slug}/preview-knit.jpg"
