"""
Postgres publisher — sync `output/case_catalog.csv` into the `cases` table.

The catalog has 50+ debug / provenance columns; we publish only the ~12 that
the website actually queries on. The mapping below is the single source of
truth for "what shows up in the database".

Idempotent by design: re-running the publisher updates existing rows in
place rather than duplicating them, thanks to the
`UNIQUE (source_school, source_year, normalized_title)` constraint and an
ON CONFLICT DO UPDATE upsert.
"""

from __future__ import annotations

import logging
import math
from pathlib import Path
from typing import Any

import pandas as pd
import psycopg

from pipeline.storage import to_storage_key, get_storage

logger = logging.getLogger(__name__)


# CSV column → DB column. Only these columns get published.
COLUMN_MAP: dict[str, str] = {
    "case_title":            "case_title",
    "normalized_title":      "normalized_title",
    "source_school":         "source_school",
    "source_year":           "source_year",
    "industry":              "industry",
    "case_type_normalized":  "case_type",
    "difficulty_normalized": "difficulty",
    "difficulty_score":      "difficulty_score",
    "firm":                  "firm",
    "interviewer_led":       "interviewer_led",
    "page_count":            "page_count",
    "output_pdf_path":       "pdf_path",
}

VALID_DIFFICULTY = {"Easy", "Medium", "Hard"}

REQUIRED_NOT_NULL = {"case_title", "normalized_title", "source_school", "pdf_path"}


# ── Cell-level cleaning ────────────────────────────────────────────────────────

def _is_blank(val: Any) -> bool:
    """True for None, NaN, or empty/whitespace strings."""
    if val is None:
        return True
    if isinstance(val, float) and math.isnan(val):
        return True
    if isinstance(val, str) and val.strip() == "":
        return True
    return False


def _clean_value(val: Any, col_name: str) -> Any:
    """Coerce a raw CSV value to the right Python type for `col_name`,
    or return None if it's blank / invalid for the column's check
    constraint."""
    if _is_blank(val):
        return None

    if col_name in ("source_year", "page_count"):
        try:
            return int(float(val))
        except (TypeError, ValueError):
            return None

    if col_name == "difficulty_score":
        try:
            score = float(val)
        except (TypeError, ValueError):
            return None
        if not (0 <= score <= 10):
            return None
        return round(score, 1)

    if col_name == "difficulty":
        s = str(val).strip()
        return s if s in VALID_DIFFICULTY else None

    if col_name == "interviewer_led":
        s = str(val).strip().lower()
        if s in ("true", "1", "yes", "y"):
            return True
        if s in ("false", "0", "no", "n"):
            return False
        return None

    return str(val).strip()


# ── Main entry point ───────────────────────────────────────────────────────────

UPSERT_SQL = """
INSERT INTO cases (
    case_title, normalized_title, source_school, source_year,
    industry, case_type, difficulty, difficulty_score,
    firm, interviewer_led, page_count, pdf_path
) VALUES (
    %(case_title)s, %(normalized_title)s, %(source_school)s, %(source_year)s,
    %(industry)s, %(case_type)s, %(difficulty)s, %(difficulty_score)s,
    %(firm)s, %(interviewer_led)s, %(page_count)s, %(pdf_path)s
)
ON CONFLICT (source_school, source_year, normalized_title) DO UPDATE SET
    case_title       = EXCLUDED.case_title,
    industry         = EXCLUDED.industry,
    case_type        = EXCLUDED.case_type,
    difficulty       = EXCLUDED.difficulty,
    difficulty_score = EXCLUDED.difficulty_score,
    firm             = EXCLUDED.firm,
    interviewer_led  = EXCLUDED.interviewer_led,
    page_count       = EXCLUDED.page_count,
    pdf_path         = EXCLUDED.pdf_path,
    updated_at       = NOW()
RETURNING (xmax = 0) AS inserted;
"""


def publish_catalog(
    catalog_path: Path,
    database_url: str,
    *,
    dry_run: bool = False,
) -> dict[str, int]:
    """Read a case_catalog.csv (or .xlsx) and upsert each row into `cases`.

    Returns a dict with keys: total_rows, prepared, skipped, inserted, updated.
    """
    if catalog_path.suffix.lower() in (".xlsx", ".xls"):
        df = pd.read_excel(catalog_path)
    else:
        df = pd.read_csv(catalog_path)

    logger.info("Loaded %d rows from %s", len(df), catalog_path)

    missing_cols = [c for c in COLUMN_MAP if c not in df.columns]
    if missing_cols:
        raise ValueError(
            f"Catalog is missing required columns: {missing_cols}. "
            f"Re-run `python main.py export-catalog` and try again."
        )

    df_subset = df[list(COLUMN_MAP.keys())].copy()
    df_subset.columns = [COLUMN_MAP[c] for c in df_subset.columns]

    # Storage backend used to (a) convert legacy absolute paths to portable
    # keys and (b) verify each file is actually reachable. If a file is
    # missing on disk we still publish the row — the verifier surfaces it
    # later — but we log a warning so the operator notices.
    storage = get_storage()

    rows: list[dict[str, Any]] = []
    skipped = 0
    missing_files = 0
    for _, raw in df_subset.iterrows():
        clean = {col: _clean_value(raw[col], col) for col in df_subset.columns}

        # Convert legacy absolute pdf path → portable storage key.
        raw_pdf = clean.get("pdf_path")
        if raw_pdf:
            key = to_storage_key(raw_pdf)
            if key is None:
                logger.warning(
                    "Could not derive storage key from pdf_path %r — skipping",
                    raw_pdf,
                )
                clean["pdf_path"] = None
            else:
                clean["pdf_path"] = key
                if not storage.exists(key):
                    missing_files += 1
                    logger.warning(
                        "PDF not found in storage for key %r (case: %r)",
                        key, clean.get("case_title"),
                    )

        missing_required = [c for c in REQUIRED_NOT_NULL if clean.get(c) is None]
        if missing_required:
            logger.warning(
                "Skipping row %r — missing required: %s",
                clean.get("case_title") or "<no title>",
                missing_required,
            )
            skipped += 1
            continue

        rows.append(clean)

    logger.info(
        "Prepared %d rows for upsert (%d skipped, %d with missing PDF on disk)",
        len(rows), skipped, missing_files,
    )

    if dry_run:
        logger.info("DRY RUN — no database connection opened")
        return {
            "total_rows":    len(df),
            "prepared":      len(rows),
            "skipped":       skipped,
            "missing_files": missing_files,
            "inserted":      0,
            "updated":       0,
        }

    inserted = 0
    updated = 0
    with psycopg.connect(database_url) as conn:
        with conn.cursor() as cur:
            for row in rows:
                cur.execute(UPSERT_SQL, row)
                result = cur.fetchone()
                # `xmax = 0` is true for freshly-inserted rows; an UPDATE
                # leaves a non-zero xmax. This is how Postgres lets us
                # distinguish INSERT vs UPDATE in a single ON CONFLICT.
                if result and result[0]:
                    inserted += 1
                else:
                    updated += 1
        conn.commit()

    logger.info("Upsert complete: %d inserted, %d updated", inserted, updated)
    return {
        "total_rows":    len(df),
        "prepared":      len(rows),
        "skipped":       skipped,
        "missing_files": missing_files,
        "inserted":      inserted,
        "updated":       updated,
    }
