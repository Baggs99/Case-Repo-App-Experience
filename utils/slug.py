"""
URL-safe slug generation for case titles and filenames.
"""

import re
from slugify import slugify as _slugify


def make_case_slug(title: str, max_length: int = 60) -> str:
    """
    Convert a case title to a URL-safe filename slug.

    Examples:
        "Big Tech Bivalves (Healthcare)"  →  "big-tech-bivalves-healthcare"
        "Case 3: M&A in Pharma"           →  "case-3-ma-in-pharma"
        ""                                →  "untitled-case"
    """
    slug = _slugify(title, max_length=max_length, word_boundary=True, separator="-")
    return slug if slug else "untitled-case"


def make_safe_dirname(name: str, max_length: int = 80) -> str:
    """
    Convert any string into a safe directory name (Windows + POSIX compatible).

    Strips characters that are illegal on Windows filesystems.
    """
    # Replace illegal chars with a dash
    safe = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "-", name)
    safe = re.sub(r"-{2,}", "-", safe).strip("-").strip()
    return safe[:max_length] if safe else "unnamed"
