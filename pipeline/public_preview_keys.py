"""R2/object-storage key layout for externally hosted preview JPEGs."""


def public_preview_object_key(slug: str, page_num: int) -> str:
    """Stable key prefix ``pv/<slug>/`` keeps previews separate from case PDF paths."""
    return f"pv/{slug}/page-{page_num:03d}.jpg"
