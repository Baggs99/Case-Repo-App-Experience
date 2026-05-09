"""
Rasterise case PDFs listed in ``case_catalog.csv`` — no Postgres.

JPEGs mirror catalog paths under ``output/previews_local/<…>/page-NNN.jpg``.
"""

from __future__ import annotations

import logging
import math
from pathlib import Path
from typing import Any

import pandas as pd

from pipeline.preview_generation import rasterize_pdf_bytes_to_dir

logger = logging.getLogger(__name__)


def _is_blank(val: Any) -> bool:
    if val is None:
        return True
    if isinstance(val, float) and math.isnan(val):
        return True
    if isinstance(val, str) and val.strip() == "":
        return True
    return False


def resolve_catalog_pdf_path(raw: str, repo_root: Path) -> Path | None:
    """Resolve ``output_pdf_path`` cell to an existing file under this repo."""
    raw = raw.strip().replace("\\", "/")
    if not raw:
        return None

    marker = "output/cases/"
    low = raw.lower()
    idx = low.find(marker)
    if idx >= 0:
        suffix = raw[idx + len(marker) :].lstrip("/")
        cand = (repo_root / "output" / "cases" / suffix).resolve()
        return cand if cand.is_file() else None

    p = Path(raw)
    if p.is_absolute():
        return p.resolve() if p.is_file() else None

    cand = (repo_root / raw).resolve()
    return cand if cand.is_file() else None


def previews_local_out_dir(pdf_path: Path, repo_root: Path) -> Path:
    """``output/previews_local/<mirror-of-output/cases/…>`` without ``.pdf``."""
    cases_root = (repo_root / "output" / "cases").resolve()
    pdf_resolved = pdf_path.resolve()
    try:
        rel = pdf_resolved.relative_to(cases_root)
    except ValueError:
        stem_safe = pdf_resolved.stem.replace("/", "_").replace("\\", "_")
        return repo_root / "output" / "previews_local" / "_outside_cases" / stem_safe

    key = rel.with_suffix("")
    return repo_root / "output" / "previews_local" / key


def generate_previews_from_catalog_csv(
    *,
    catalog_path: Path,
    repo_root: Path,
    match_substr: str | None,
    limit: int | None,
    skip_existing: bool,
    verbose: bool,
) -> dict[str, int]:
    """
    Read catalog rows; rasterise each ``output_pdf_path`` PDF.

    Returns counts: ok, skip_existing, skip_missing_pdf, skip_bad_row, fail.
    """
    if catalog_path.suffix.lower() in {".xlsx", ".xlsm"}:
        df = pd.read_excel(catalog_path)
    else:
        df = pd.read_csv(catalog_path)

    if "output_pdf_path" not in df.columns or "page_count" not in df.columns:
        raise ValueError(
            "catalog must include columns output_pdf_path and page_count "
            f"(got {list(df.columns)})"
        )

    rows = df[["case_title", "output_pdf_path", "page_count"]].copy()
    if match_substr:
        m = match_substr.strip().lower()
        rows = rows[rows["case_title"].astype(str).str.lower().str.contains(m, na=False)]

    if limit is not None:
        rows = rows.head(max(0, int(limit)))

    ok = skip_ex = skip_pdf = skip_bad = fail = 0

    for _, raw in rows.iterrows():
        title = raw.get("case_title")
        pdf_cell = raw.get("output_pdf_path")
        pc_cell = raw.get("page_count")

        if _is_blank(pdf_cell):
            skip_bad += 1
            continue
        try:
            pc = int(float(pc_cell)) if not _is_blank(pc_cell) else 0
        except (TypeError, ValueError):
            pc = 0

        pdf_path = resolve_catalog_pdf_path(str(pdf_cell), repo_root)
        if pdf_path is None:
            logger.warning("PDF not found for %r — catalog path %r", title, pdf_cell)
            skip_pdf += 1
            continue

        out_dir = previews_local_out_dir(pdf_path, repo_root)
        first_jpg = out_dir / "page-001.jpg"
        if skip_existing and first_jpg.is_file():
            skip_ex += 1
            continue

        try:
            pdf_bytes = pdf_path.read_bytes()
        except OSError as exc:
            logger.warning("read failed %s: %s", pdf_path, exc)
            fail += 1
            continue

        try:
            written = rasterize_pdf_bytes_to_dir(
                out_dir=out_dir,
                pdf_bytes=pdf_bytes,
                catalog_page_count=pc,
            )
        except Exception as exc:
            logger.warning("raster failed %s: %s", pdf_path, exc)
            fail += 1
            continue

        if verbose:
            logger.info("%s → %d page(s) → %s", title, written, out_dir.relative_to(repo_root))
        ok += 1

    return {
        "ok": ok,
        "skip_existing": skip_ex,
        "skip_missing_pdf": skip_pdf,
        "skip_bad_row": skip_bad,
        "fail": fail,
    }
