"""
Vertically stitch ``page-NNN.jpg`` previews into one JPEG per case folder.

Pure Pillow — used after ``generate-previews-local``.
"""

from __future__ import annotations

import re
from pathlib import Path

_PAGE_RE = re.compile(r"^page-(\d+)\.jpg$", re.IGNORECASE)


def _norm_only_source_prefix(s: str) -> str:
    return s.replace("\\", "/").strip().strip("/")


def preview_folder_matches_only_source(
    folder: Path, previews_root: Path, only_source: str | None
) -> bool:
    """True if *folder* is under ``previews_root/<only_source>/``."""
    if not only_source:
        return True
    p = _norm_only_source_prefix(only_source)
    try:
        rel = folder.resolve().relative_to(previews_root.resolve())
    except ValueError:
        return False
    key = rel.as_posix()
    return key == p or key.startswith(f"{p}/")


def _sorted_page_jpegs(folder: Path) -> list[Path]:
    pairs: list[tuple[int, Path]] = []
    for p in folder.iterdir():
        if not p.is_file():
            continue
        m = _PAGE_RE.match(p.name)
        if m:
            pairs.append((int(m.group(1)), p))
    pairs.sort(key=lambda x: x[0])
    return [p for _, p in pairs]


def knit_preview_folder_to_jpeg(
    folder: Path,
    dest: Path,
    *,
    gap_px: int = 6,
    bg_rgb: tuple[int, int, int] = (250, 250, 250),
    jpeg_quality: int = 88,
    jpeg_max_dimension: int = 65500,
) -> bool:
    """
    Concatenate ``page-*.jpg`` in ``folder`` top-to-bottom into ``dest``.

    Returns True if a file was written. Width-normalizes pages when widths differ.
    Shrinks strip uniformly if width or height would exceed ``jpeg_max_dimension``.
    """
    try:
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError(
            "Pillow is required. Install with: pip install Pillow"
        ) from exc

    paths = _sorted_page_jpegs(folder)
    if not paths:
        return False

    ims: list = []
    try:
        for fp in paths:
            ims.append(Image.open(fp).convert("RGB"))

        max_w = max(im.width for im in ims)
        normalized: list = []
        for im in ims:
            if im.width != max_w:
                nh = max(1, round(im.height * max_w / im.width))
                normalized.append(im.resize((max_w, nh), Image.Resampling.LANCZOS))
                im.close()
            else:
                normalized.append(im)
        ims = normalized

        gap = max(0, gap_px)
        total_h = sum(im.height for im in ims) + gap * max(0, len(ims) - 1)

        scale_down = 1.0
        if total_h > jpeg_max_dimension or max_w > jpeg_max_dimension:
            scale_down = min(
                jpeg_max_dimension / total_h,
                jpeg_max_dimension / max_w,
                1.0,
            )

        if scale_down < 1.0:
            nw = max(1, int(round(max_w * scale_down)))
            shrunk: list = []
            for im in ims:
                nh = max(1, int(round(im.height * scale_down)))
                shrunk.append(im.resize((nw, nh), Image.Resampling.LANCZOS))
                im.close()
            ims = shrunk
            max_w = nw
            total_h = sum(im.height for im in ims) + gap * max(0, len(ims) - 1)

        canvas = Image.new("RGB", (max_w, total_h), bg_rgb)
        y = 0
        for i, im in enumerate(ims):
            x_off = (max_w - im.width) // 2
            canvas.paste(im, (x_off, y))
            y += im.height
            if i < len(ims) - 1:
                y += gap
            im.close()
        ims = []

        dest.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(dest, format="JPEG", quality=jpeg_quality, optimize=True)
        canvas.close()

    finally:
        for im in ims:
            try:
                im.close()
            except Exception:
                pass

    return True


def find_case_preview_directories(previews_root: Path) -> list[Path]:
    """Folders that contain ``page-001.jpg`` (one level = one case)."""
    if not previews_root.is_dir():
        return []
    return sorted({p.parent for p in previews_root.rglob("page-001.jpg")})
