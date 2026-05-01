"""
Case catalog exporter.

Reads manifest.json, applies ground-truth enrichment for known casebooks,
validates the rows, then writes:

    output/case_catalog.csv   — flat CSV for programmatic use
    output/case_catalog.xlsx  — formatted Excel workbook for human review

Enrichment priority (highest → lowest):
  1. Hardcoded ground-truth data in pipeline/exporters/enrichment/
  2. Heuristic metadata already in the manifest (industry, case_type, etc.)

Usage
-----
    from pipeline.exporters.case_catalog import build_catalog, write_catalog

    rows = build_catalog(manifest_path)
    write_catalog(rows, output_dir)
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

import pandas as pd

from pipeline.exporters.enrichment import booth_2021, booth_2026, columbia_2017, columbia_2021, darden_2017, darden_2018_2019, darden_2021, darden_2024, fuqua_2026, harvard_2002, kellogg_2016, kellogg_2023, kellogg_2024, mit_2011, ross_2019, ross_2022, ross_2024, stern_2021, stern_2025, tuck_2024, wharton_2017, yale_2024, yale_2025
from pipeline.exporters.enrichment.source_school_resolver import resolve_source_school, infer_from_filename
from pipeline.exporters.enrichment.source_year_resolver import resolve_source_year, is_valid_year
from pipeline.exporters.enrichment.case_type_normalizer import normalize_case_type, ALLOWED_CASE_TYPES
from pipeline.exporters.enrichment.difficulty_normalizer import normalize_difficulty, BUCKETS as DIFFICULTY_BUCKETS

logger = logging.getLogger(__name__)


# ── Column specification ───────────────────────────────────────────────────────

CATALOG_COLUMNS = [
    "case_title",
    "case_title_raw",      # plain-text backup; case_title becomes a HYPERLINK in XLSX
    "open_case",           # "Open" hyperlink in XLSX; omitted from CSV
    "normalized_title",
    "source_pdf",
    "source_school",
    "source_year",
    "page_start",
    "page_end",
    "page_count",
    "industry",
    "case_type",
    "case_type_raw",
    "case_type_normalized",
    "difficulty",
    "difficulty_raw",
    "difficulty_normalized",
    "difficulty_quant",
    "difficulty_qual",
    "difficulty_math",
    "difficulty_structure",
    "difficulty_creativity",
    "concepts_tested",
    "difficulty_visual_present",
    "difficulty_quant_category",
    "firm",
    "round",
    "interviewer_led",
    "is_new_case",
    "is_duplicate_case",
    "unique_case_count_eligible",
    "canonical_case_title",
    "duplicate_of_source_school",
    "duplicate_of_source_year",
    "duplicate_of_case_title",
    "detection_method",
    "extraction_confidence",
    "needs_manual_review",
    "output_pdf_path",
]

# XLSX column widths (characters)
_COL_WIDTHS: dict[str, int] = {
    "case_title":            38,
    "case_title_raw":        38,
    "open_case":              9,
    "normalized_title":      30,
    "source_pdf":            42,
    "source_school":         16,
    "source_year":           11,
    "page_start":            11,
    "page_end":              10,
    "page_count":            11,
    "industry":              28,
    "case_type":             28,
    "case_type_raw":         28,
    "case_type_normalized":  22,
    "difficulty":            13,
    "difficulty_raw":        28,
    "difficulty_normalized": 16,
    "difficulty_quant":      17,
    "difficulty_qual":       15,
    "difficulty_math":       17,
    "difficulty_structure":  21,
    "difficulty_creativity": 21,
    "concepts_tested":            45,
    "difficulty_visual_present":   22,
    "difficulty_quant_category":   22,
    "firm":                        18,
    "round":                 10,
    "interviewer_led":       15,
    "is_new_case":           12,
    "is_duplicate_case":           18,
    "unique_case_count_eligible":  24,
    "canonical_case_title":        35,
    "duplicate_of_source_school":  24,
    "duplicate_of_source_year":    22,
    "duplicate_of_case_title":     35,
    "detection_method":            36,
    "extraction_confidence":       22,
    "needs_manual_review":         20,
    "output_pdf_path":             52,
}


# ── Enrichment registry ────────────────────────────────────────────────────────

def _matches(source_pdf: str, patterns) -> bool:
    """Return True if source_pdf contains any of the given pattern strings."""
    if isinstance(patterns, str):
        patterns = (patterns,)
    return any(p in source_pdf for p in patterns)


# List of (match_predicate, enrichment_dict) pairs checked in order.
_ENRICHMENT_REGISTRY: list[tuple] = [
    (lambda pdf: _matches(pdf, columbia_2021.PDF_MATCH), columbia_2021.ENRICHMENT),
    (lambda pdf: _matches(pdf, columbia_2017.PDF_MATCH), columbia_2017.ENRICHMENT),
    (lambda pdf: _matches(pdf, darden_2017.PDF_MATCH),        darden_2017.ENRICHMENT),
    (lambda pdf: _matches(pdf, darden_2018_2019.PDF_MATCH),  darden_2018_2019.ENRICHMENT),
    (lambda pdf: _matches(pdf, darden_2021.PDF_MATCH),       darden_2021.ENRICHMENT),
    (lambda pdf: _matches(pdf, darden_2024.PDF_MATCH),       darden_2024.ENRICHMENT),
    (lambda pdf: _matches(pdf, fuqua_2026.PDF_MATCH),        fuqua_2026.ENRICHMENT),
    (lambda pdf: _matches(pdf, harvard_2002.PDF_MATCH),      harvard_2002.ENRICHMENT),
    (lambda pdf: _matches(pdf, mit_2011.PDF_MATCH),          mit_2011.ENRICHMENT),
    (lambda pdf: _matches(pdf, kellogg_2016.PDF_MATCH),      kellogg_2016.ENRICHMENT),
    (lambda pdf: _matches(pdf, kellogg_2023.PDF_MATCH),      kellogg_2023.ENRICHMENT),
    (lambda pdf: _matches(pdf, kellogg_2024.PDF_MATCH),      kellogg_2024.ENRICHMENT),
    (lambda pdf: _matches(pdf, ross_2019.PDF_MATCH),         ross_2019.ENRICHMENT),
    (lambda pdf: _matches(pdf, ross_2022.PDF_MATCH),         ross_2022.ENRICHMENT),
    (lambda pdf: _matches(pdf, ross_2024.PDF_MATCH),         ross_2024.ENRICHMENT),
    (lambda pdf: _matches(pdf, stern_2021.PDF_MATCH),        stern_2021.ENRICHMENT),
    (lambda pdf: _matches(pdf, stern_2025.PDF_MATCH),        stern_2025.ENRICHMENT),
    (lambda pdf: _matches(pdf, tuck_2024.PDF_MATCH),         tuck_2024.ENRICHMENT),
    (lambda pdf: _matches(pdf, wharton_2017.PDF_MATCH),      wharton_2017.ENRICHMENT),
    (lambda pdf: _matches(pdf, yale_2024.PDF_MATCH),         yale_2024.ENRICHMENT),
    (lambda pdf: _matches(pdf, yale_2025.PDF_MATCH),         yale_2025.ENRICHMENT),
    (lambda pdf: _matches(pdf, booth_2021.PDF_MATCH),        booth_2021.ENRICHMENT),
    (lambda pdf: _matches(pdf, booth_2026.PDF_MATCH),        booth_2026.ENRICHMENT),
]


# ── Title normalisation ────────────────────────────────────────────────────────

def normalize_title(title: str) -> str:
    """
    Produce a search-friendly key from a case title.

    Steps:
      1. Lowercase
      2. Replace every non-alphanumeric character with a space
         (handles hyphens, parentheses, periods, commas, apostrophes, etc.)
      3. Collapse runs of whitespace to a single space and strip edges

    Examples:
      "Ban the Box"          → "ban the box"
      "Co-V(id)accinated"    → "co v id accinated"
      "Sparkle Co."          → "sparkle co"
      "Fast Food Co."        → "fast food co"
      "Pay Me My Money, In Cash" → "pay me my money  in cash" → "pay me my money in cash"
    """
    t = title.lower()
    t = re.sub(r"[^\w\s]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


# ── Core builder ──────────────────────────────────────────────────────────────

def build_catalog(manifest_path: Path) -> list[dict[str, Any]]:
    """
    Load manifest.json, enrich each row with ground-truth metadata where
    available, validate, and return a list of catalog row dicts.

    Parameters
    ----------
    manifest_path:
        Path to the manifest.json produced by the split pipeline.

    Returns
    -------
    List of row dicts keyed by CATALOG_COLUMNS.  Rows that fail hard
    validation (blank title, page_start > page_end) are skipped with a warning.
    """
    if not manifest_path.exists():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")

    with open(manifest_path, encoding="utf-8") as f:
        manifest: list[dict] = json.load(f)

    logger.info("Building catalog from %d manifest entries", len(manifest))

    rows: list[dict[str, Any]] = []
    seen: set[tuple] = set()          # dedup key: (source_pdf, case_title, page_start)
    skipped = 0

    for entry in manifest:
        row = _build_row(entry)

        # ── Hard validation ────────────────────────────────────────────────────
        if not row["case_title"]:
            logger.warning("Skipping entry with blank case_title (source: %s)", entry.get("source_pdf"))
            skipped += 1
            continue

        if row["page_start"] is not None and row["page_end"] is not None:
            if row["page_start"] > row["page_end"]:
                logger.warning(
                    "Skipping '%s' — page_start (%d) > page_end (%d)",
                    row["case_title"], row["page_start"], row["page_end"],
                )
                skipped += 1
                continue

        dedup_key = (row["source_pdf"], row["case_title"], row["page_start"])
        if dedup_key in seen:
            logger.warning("Skipping duplicate row: %s / %s / p%s", *dedup_key)
            skipped += 1
            continue
        seen.add(dedup_key)

        rows.append(row)

    logger.info(
        "Catalog built: %d rows (%d skipped during validation)",
        len(rows), skipped,
    )

    # ── Collect source_school resolution stats ────────────────────────────────
    corrected = sum(
        1 for r in rows
        if r.get("source_school") != r.get("_source_school_raw")
        and r.get("_source_school_raw") is not None
    )
    if corrected:
        logger.info("source_school corrected by resolver: %d rows", corrected)

    # ── Collect source_year resolution stats ──────────────────────────────────
    def _as_int(v):
        try:
            return int(v) if v not in (None, "") else None
        except (TypeError, ValueError):
            return None

    year_corrected = sum(
        1 for r in rows
        if _as_int(r.get("source_year")) != _as_int(r.get("_source_year_raw"))
    )
    year_missing = sum(1 for r in rows if r.get("source_year") is None)
    if year_corrected:
        logger.info("source_year corrected by resolver: %d rows", year_corrected)
    logger.info("source_year missing/null: %d rows", year_missing)

    # ── Deterministic backfill for blank case_type / industry ─────────────────
    from pipeline.exporters.case_type_backfill import backfill_rocketblocks, canonicalise_case_types
    rows, _bf_stats = backfill_rocketblocks(rows)
    canonicalise_case_types(rows)

    # ── Re-normalize case_type_raw/_normalized after backfill ─────────────────
    # Backfill can fill blank values for RocketBlocks and canonicalise others,
    # so normalization must run against the post-backfill raw value.
    for r in rows:
        raw = r.get("case_type") or ""
        r["case_type_raw"]        = raw
        r["case_type_normalized"] = normalize_case_type(
            raw,
            source_school=r.get("source_school"),
            industry=r.get("industry"),
        )

    # ── Summary logging for normalization coverage ────────────────────────────
    diff_filled = sum(1 for r in rows if r.get("difficulty_normalized") in DIFFICULTY_BUCKETS)
    diff_missing = len(rows) - diff_filled
    ct_filled   = sum(1 for r in rows if r.get("case_type_normalized") in ALLOWED_CASE_TYPES
                                          and r["case_type_normalized"] != "Other")
    ct_other    = sum(1 for r in rows if r.get("case_type_normalized") == "Other")
    logger.info(
        "difficulty_normalized: %d filled, %d missing (out of %d)",
        diff_filled, diff_missing, len(rows),
    )
    logger.info(
        "case_type_normalized: %d mapped, %d Other (out of %d)",
        ct_filled, ct_other, len(rows),
    )

    return rows


def _build_row(entry: dict) -> dict[str, Any]:
    """Convert a single manifest entry into a catalog row dict."""
    source_pdf = entry.get("source_pdf", "")

    # Look up enrichment for this source file (if any).
    enrichment: dict = {}
    for pred, table in _ENRICHMENT_REGISTRY:
        if pred(source_pdf):
            key = normalize_title(entry.get("case_title", ""))
            enrichment = table.get(key, {})
            break

    def _pick(manifest_field: str, enrich_key: str | None = None) -> Any:
        """Return enrichment value if present, else manifest value."""
        ek = enrich_key or manifest_field
        if ek in enrichment and enrichment[ek] is not None:
            return enrichment[ek]
        return entry.get(manifest_field)

    title = entry.get("case_title", "")

    raw_source_school     = enrichment.get("source_school") or entry.get("source_school")
    resolved_source_school = resolve_source_school(source_pdf, enrichment.get("source_school") or entry.get("source_school"))

    raw_source_year       = enrichment.get("source_year") or entry.get("source_year")
    resolved_source_year  = resolve_source_year(source_pdf)

    # ── case_type + difficulty normalization ──────────────────────────────────
    # Build a temporary "pre-row" so the difficulty normalizer sees the same
    # values that will land in the catalog.
    _case_type   = _pick("case_type")
    _industry    = _pick("industry")
    _pre_row_for_difficulty = {
        "difficulty":                 _pick("difficulty_overall", "difficulty"),
        "difficulty_quant":           _pick("difficulty_quant"),
        "difficulty_qual":            _pick("difficulty_qual"),
        "difficulty_structure":       enrichment.get("difficulty_structure"),
        "difficulty_visual_present":  enrichment.get("difficulty_visual_present"),
    }
    diff_norm, diff_raw = normalize_difficulty(_pre_row_for_difficulty)
    case_type_norm = normalize_case_type(
        _case_type, source_school=resolved_source_school, industry=_industry
    )

    return {
        "case_title":            title,   # becomes HYPERLINK in XLSX; plain text in CSV
        "case_title_raw":        title,   # always plain text
        "open_case":             "",      # populated with HYPERLINK formula in XLSX only
        "normalized_title":      normalize_title(title),
        "source_pdf":            source_pdf,
        "source_school":         resolved_source_school,
        "_source_school_raw":    raw_source_school,     # internal audit field, stripped before output
        "source_year":           resolved_source_year,
        "_source_year_raw":      raw_source_year,       # internal audit field, stripped before output
        "page_start":            entry.get("page_start"),
        "page_end":              entry.get("page_end"),
        "page_count":            entry.get("page_count"),
        "industry":              _industry,
        "case_type":             _case_type,
        "case_type_raw":         _case_type,
        "case_type_normalized":  case_type_norm,
        "difficulty":            _pre_row_for_difficulty["difficulty"],
        "difficulty_raw":        diff_raw,
        "difficulty_normalized": diff_norm,
        "difficulty_quant":      _pick("difficulty_quant"),
        "difficulty_qual":       _pick("difficulty_qual"),
        "difficulty_math":       _pick("difficulty_quant",  "difficulty_math"),
        "difficulty_structure":  enrichment.get("difficulty_structure"),
        "difficulty_creativity": enrichment.get("difficulty_creativity"),
        "concepts_tested":            enrichment.get("concepts_tested"),
        "difficulty_visual_present":   enrichment.get("difficulty_visual_present"),
        "difficulty_quant_category":   enrichment.get("difficulty_quant_category"),
        "firm":                        enrichment.get("firm"),
        "round":                 enrichment.get("round"),
        "interviewer_led":            enrichment.get("interviewer_led"),
        "is_new_case":                enrichment.get("is_new_case", False),
        # ── Deduplication fields ──────────────────────────────────────────────────
        # Populated by enrichment for casebooks that re-use cases from earlier years.
        # All other rows default to is_duplicate_case=False, eligible=True.
        "is_duplicate_case":          enrichment.get("is_duplicate_case", False),
        "unique_case_count_eligible": not enrichment.get("is_duplicate_case", False),
        "canonical_case_title":       enrichment.get("canonical_case_title", normalize_title(title)),
        "duplicate_of_source_school": enrichment.get("duplicate_of_source_school"),
        "duplicate_of_source_year":   enrichment.get("duplicate_of_source_year"),
        "duplicate_of_case_title":    enrichment.get("duplicate_of_case_title"),
        # ─────────────────────────────────────────────────────────────────────────
        "detection_method":      entry.get("detection_method"),
        "extraction_confidence": entry.get("extraction_confidence"),
        "needs_manual_review":   entry.get("needs_manual_review"),
        "output_pdf_path":       entry.get("output_pdf_path"),
    }


# ── Path helpers ──────────────────────────────────────────────────────────────

def _abs_win_path(rel_or_abs: str, base: Path) -> str:
    """
    Return an absolute Windows path string for a catalog output_pdf_path value.

    The catalog stores paths relative to the output directory's parent
    (e.g. ``cases/Booth/Booth 2026/army-hotel.pdf``).  We join them with
    *base* (the output directory, e.g. ``C:\\…\\output``) to get a full path.
    """
    p = Path(rel_or_abs)
    if not p.is_absolute():
        p = (base / p).resolve()
    return str(p)


def _make_hyperlink(abs_path: str, friendly: str) -> str:
    """Return an Excel HYPERLINK formula for a local file path."""
    # Escape double-quotes inside the path (rare but safe)
    escaped = abs_path.replace('"', '""')
    return f'=HYPERLINK("{escaped}", "{friendly}")'


# ── Writers ───────────────────────────────────────────────────────────────────

def write_catalog(
    rows: list[dict[str, Any]],
    output_dir: Path,
    base_dir: Path | None = None,
) -> tuple[Path, Path]:
    """
    Write CSV and XLSX catalog files.

    Parameters
    ----------
    rows:       Output of build_catalog().
    output_dir: Directory to write into (must already exist).
    base_dir:   Base directory used to resolve relative output_pdf_path values.
                Defaults to *output_dir* (paths like ``cases/…`` sit inside it).

    Returns
    -------
    (csv_path, xlsx_path) — paths to the written files.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    if base_dir is None:
        base_dir = output_dir.resolve()

    # Strip any internal audit fields that may still be present
    clean_rows = [{k: v for k, v in r.items() if not k.startswith("_")} for r in rows]
    df = pd.DataFrame(clean_rows, columns=CATALOG_COLUMNS)

    # source_year is an integer year or null; use pandas nullable Int dtype
    # so it renders as "2024" instead of "2024.0" in CSV and XLSX output.
    if "source_year" in df.columns:
        df["source_year"] = pd.to_numeric(df["source_year"], errors="coerce").astype("Int64")

    # ── Resolve absolute paths (used for hyperlinks) ──────────────────────────
    def _resolve_path(raw: Any) -> str:
        if not raw or (isinstance(raw, float)):
            return ""
        try:
            return _abs_win_path(str(raw), base_dir)
        except Exception:
            return str(raw)

    abs_paths: list[str] = [_resolve_path(r) for r in df["output_pdf_path"]]

    # Warn on missing paths
    for i, (row, ap) in enumerate(zip(rows, abs_paths)):
        if not ap:
            logger.warning(
                "Row %d (%s): output_pdf_path is empty — hyperlink will be blank.",
                i + 1, row.get("case_title", "?"),
            )

    # Store resolved absolute paths back into the df for CSV too
    df["output_pdf_path"] = abs_paths

    csv_path  = output_dir / "case_catalog.csv"
    xlsx_path = output_dir / "case_catalog.xlsx"

    # ── CSV — plain text, no formulas, drop open_case placeholder ────────────
    csv_cols = [c for c in CATALOG_COLUMNS if c != "open_case"]
    df[csv_cols].to_csv(csv_path, index=False, encoding="utf-8-sig")
    logger.info("Wrote CSV catalog: %s (%d rows)", csv_path, len(df))

    # ── XLSX — includes clickable hyperlink formulas ──────────────────────────
    _write_xlsx(df, xlsx_path, abs_paths)
    logger.info("Wrote XLSX catalog: %s", xlsx_path)

    return csv_path, xlsx_path


def _write_xlsx(df: pd.DataFrame, path: Path, abs_paths: list[str]) -> None:
    """
    Write df to an XLSX file with:
      - Bold navy header, freeze row, autofilter, zebra stripes
      - case_title cells → =HYPERLINK(path, title)
      - open_case cells  → =HYPERLINK(path, "Open")
      - Hyperlink styling on those two columns
    """
    from openpyxl.styles import Font, PatternFill, Alignment
    from openpyxl.utils import get_column_letter

    col_names  = list(df.columns)
    title_col  = col_names.index("case_title")  + 1   # 1-based
    open_col   = col_names.index("open_case")   + 1
    path_col   = col_names.index("output_pdf_path") + 1

    # Write plain data first (pandas handles the bulk write)
    with pd.ExcelWriter(str(path), engine="openpyxl") as writer:
        df.to_excel(writer, index=False, sheet_name="Cases")
        ws = writer.sheets["Cases"]

        # ── Header formatting ─────────────────────────────────────────────────
        header_font  = Font(bold=True, color="FFFFFF", size=11)
        header_fill  = PatternFill(fill_type="solid", fgColor="1F4E79")
        header_align = Alignment(horizontal="center", vertical="center", wrap_text=True)

        for col_idx in range(1, len(col_names) + 1):
            cell            = ws.cell(row=1, column=col_idx)
            cell.font       = header_font
            cell.fill       = header_fill
            cell.alignment  = header_align

        ws.row_dimensions[1].height = 28

        # ── Column widths ─────────────────────────────────────────────────────
        for col_idx, col_name in enumerate(col_names, start=1):
            ws.column_dimensions[get_column_letter(col_idx)].width = _COL_WIDTHS.get(col_name, 20)

        # ── Freeze + filter ───────────────────────────────────────────────────
        ws.freeze_panes        = "A2"
        ws.auto_filter.ref     = ws.dimensions

        # ── Styles for hyperlink cells ────────────────────────────────────────
        link_font        = Font(color="0563C1", underline="single", size=11)
        link_font_stripe = Font(color="0563C1", underline="single", size=11)
        stripe_fill      = PatternFill(fill_type="solid", fgColor="EBF3FB")
        center_align     = Alignment(horizontal="center", vertical="center")
        wrap_cols        = {"output_pdf_path", "source_pdf", "concepts_tested"}

        # ── Data rows ─────────────────────────────────────────────────────────
        for row_idx in range(2, len(df) + 2):
            data_idx  = row_idx - 2          # 0-based index into abs_paths
            ap        = abs_paths[data_idx]
            is_stripe = (row_idx % 2 == 0)

            for col_idx in range(1, len(col_names) + 1):
                cell      = ws.cell(row=row_idx, column=col_idx)
                col_name  = col_names[col_idx - 1]

                # Zebra stripe background
                if is_stripe:
                    cell.fill = stripe_fill

                # Wrap long columns
                if col_name in wrap_cols:
                    cell.alignment = Alignment(wrap_text=True)

                # ── Hyperlink: case_title ─────────────────────────────────────
                if col_idx == title_col:
                    raw_title = df.iloc[data_idx]["case_title_raw"]
                    if ap:
                        safe_title = str(raw_title).replace('"', '""')
                        cell.value = _make_hyperlink(ap, safe_title)
                        cell.font  = link_font
                    # else: leave as-is (pandas wrote the plain title already)

                # ── Hyperlink: open_case ──────────────────────────────────────
                elif col_idx == open_col:
                    if ap:
                        cell.value     = _make_hyperlink(ap, "Open")
                        cell.font      = link_font
                        cell.alignment = center_align
                    else:
                        cell.value = ""

                # ── Plain path column — no extra processing ───────────────────
                # (already written correctly by pandas)


# ── Convenience entry point ───────────────────────────────────────────────────

def export_catalog(
    manifest_path: Path,
    output_dir: Path,
    base_dir: Path | None = None,
) -> tuple[Path, Path]:
    """
    Full export: load manifest → build catalog → backfill → write CSV + XLSX.

    Parameters
    ----------
    manifest_path : Path to manifest.json.
    output_dir    : Directory to write catalog files into.
    base_dir      : Base directory for resolving relative output_pdf_path values.
                    Defaults to output_dir (paths like ``cases/…`` live inside it).

    Returns (csv_path, xlsx_path).
    """
    rows = build_catalog(manifest_path)

    # ── Audit: source_school mismatches ───────────────────────────────────────
    _write_source_school_mismatch_audit(rows, output_dir)

    # ── Audit: source_year issues ─────────────────────────────────────────────
    _write_source_year_issues_audit(rows, output_dir)

    # ── Audit: blank case_type rows ───────────────────────────────────────────
    _write_missing_case_type_audit(rows, output_dir)

    # ── Audit: difficulty + case_type normalization ───────────────────────────
    _write_difficulty_normalization_audit(rows, output_dir)
    _write_case_type_normalization_audit(rows, output_dir)

    # Strip internal audit fields before writing output files
    for r in rows:
        r.pop("_source_school_raw", None)
        r.pop("_source_year_raw", None)

    return write_catalog(rows, output_dir, base_dir=base_dir)


def _write_source_school_mismatch_audit(rows: list[dict], output_dir: Path) -> None:
    """
    Write output/audit/source_school_mismatches.csv.

    Reports rows where the resolver changed source_school (corrected) and
    rows where the filename implies a different school than what is stored
    (potential mismatch requiring attention).
    """
    audit_dir = output_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)

    mismatch_rows = []
    corrected = 0
    unresolved = 0

    for r in rows:
        raw      = r.get("_source_school_raw") or ""
        resolved = r.get("source_school") or ""
        pdf      = r.get("source_pdf", "")
        inferred = infer_from_filename(pdf) or ""

        changed = resolved.lower() != raw.lower()
        if changed:
            corrected += 1

        # Flag if filename implies a school that differs from what's stored
        if inferred and inferred.lower() != resolved.lower():
            issue = (
                f"filename implies '{inferred}' but source_school is '{resolved}'"
            )
            mismatch_rows.append({
                "source_pdf":              pdf,
                "case_title":             r.get("case_title", ""),
                "current_source_school":  raw,
                "resolved_source_school": resolved,
                "filename_implied_school": inferred,
                "issue":                  issue,
            })

        if not resolved:
            unresolved += 1

    audit_path = audit_dir / "source_school_mismatches.csv"
    pd.DataFrame(mismatch_rows).to_csv(audit_path, index=False, encoding="utf-8-sig")

    logger.info(
        "source_school audit: %d corrected, %d residual mismatches, %d unresolved → %s",
        corrected, len(mismatch_rows), unresolved, audit_path,
    )
    if mismatch_rows:
        logger.warning(
            "source_school residual mismatches: %d rows still have filename/school conflicts "
            "(see %s)", len(mismatch_rows), audit_path,
        )


def _write_source_year_issues_audit(rows: list[dict], output_dir: Path) -> None:
    """
    Write output/audit/source_year_issues.csv.

    Flags three categories of rows:
      * ``missing``       – resolver returned None (no year in filename)
      * ``out_of_range``  – stored year is outside VALID_YEAR_RANGE
      * ``mismatch``      – filename year differs from originally stored value
                            (informational: resolver will have overwritten it)
    """
    audit_dir = output_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)

    def _as_int(v):
        try:
            return int(v) if v not in (None, "") else None
        except (TypeError, ValueError):
            return None

    issues: list[dict] = []
    missing = 0
    mismatch = 0
    out_of_range = 0

    for r in rows:
        pdf       = r.get("source_pdf", "")
        resolved  = _as_int(r.get("source_year"))
        raw       = _as_int(r.get("_source_year_raw"))
        extracted = resolve_source_year(pdf)   # re-run for audit clarity

        if resolved is None:
            missing += 1
            issues.append({
                "source_pdf":     pdf,
                "case_title":     r.get("case_title", ""),
                "extracted_year": "",
                "current_year":   "" if raw is None else raw,
                "issue":          "missing",
            })
            continue

        if not is_valid_year(resolved):
            out_of_range += 1
            issues.append({
                "source_pdf":     pdf,
                "case_title":     r.get("case_title", ""),
                "extracted_year": extracted if extracted is not None else "",
                "current_year":   resolved,
                "issue":          "out_of_range",
            })
            continue

        if raw is not None and raw != resolved:
            mismatch += 1
            issues.append({
                "source_pdf":     pdf,
                "case_title":     r.get("case_title", ""),
                "extracted_year": extracted if extracted is not None else "",
                "current_year":   raw,
                "issue":          f"mismatch (manifest {raw} -> resolver {resolved})",
            })

    audit_path = audit_dir / "source_year_issues.csv"
    pd.DataFrame(issues).to_csv(audit_path, index=False, encoding="utf-8-sig")

    logger.info(
        "source_year audit: %d missing, %d out-of-range, %d mismatch corrections -> %s",
        missing, out_of_range, mismatch, audit_path,
    )


def _write_difficulty_normalization_audit(rows: list[dict], output_dir: Path) -> None:
    """
    Write output/audit/difficulty_normalization_audit.csv.

    One row per case, capturing the raw inputs and the normalized bucket.
    Useful for spot-checking rule behaviour.
    """
    audit_dir = output_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)

    records = [
        {
            "case_title":            r.get("case_title", ""),
            "source_school":         r.get("source_school", ""),
            "source_year":           r.get("source_year", ""),
            "difficulty_raw":        r.get("difficulty_raw", ""),
            "difficulty_normalized": r.get("difficulty_normalized") or "",
        }
        for r in rows
    ]

    audit_path = audit_dir / "difficulty_normalization_audit.csv"
    pd.DataFrame(records).to_csv(audit_path, index=False, encoding="utf-8-sig")

    filled  = sum(1 for r in rows if r.get("difficulty_normalized") in DIFFICULTY_BUCKETS)
    missing = len(rows) - filled
    logger.info(
        "difficulty audit: %d normalized, %d unresolved -> %s",
        filled, missing, audit_path,
    )


def _write_case_type_normalization_audit(rows: list[dict], output_dir: Path) -> None:
    """
    Write output/audit/case_type_normalization_audit.csv.

    Records the raw value, the normalized bucket, and (for debugging) the
    source_school + industry that influenced any Public Sector / Nonprofit
    reroute.
    """
    audit_dir = output_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)

    records = [
        {
            "case_title":            r.get("case_title", ""),
            "source_school":         r.get("source_school", ""),
            "source_year":           r.get("source_year", ""),
            "industry":              r.get("industry", ""),
            "case_type_raw":         r.get("case_type_raw", ""),
            "case_type_normalized":  r.get("case_type_normalized", ""),
        }
        for r in rows
    ]

    audit_path = audit_dir / "case_type_normalization_audit.csv"
    pd.DataFrame(records).to_csv(audit_path, index=False, encoding="utf-8-sig")

    mapped_count = sum(
        1 for r in rows
        if r.get("case_type_normalized") in ALLOWED_CASE_TYPES
        and r["case_type_normalized"] != "Other"
    )
    other_count = sum(1 for r in rows if r.get("case_type_normalized") == "Other")
    logger.info(
        "case_type audit: %d mapped, %d -> Other -> %s",
        mapped_count, other_count, audit_path,
    )


def _write_missing_case_type_audit(rows: list[dict], output_dir: Path) -> None:
    """Write output/audit/missing_case_type_after_backfill.csv."""
    from collections import Counter
    audit_dir = output_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)

    missing = [
        {
            "source_school":    r.get("source_school", ""),
            "source_pdf":       r.get("source_pdf", ""),
            "case_title":       r.get("case_title", ""),
            "case_type":        r.get("case_type", ""),
            "output_pdf_path":  r.get("output_pdf_path", ""),
        }
        for r in rows
        if not (r.get("case_type") or "").strip()
    ]

    # Write CSV
    audit_path = audit_dir / "missing_case_type_after_backfill.csv"
    pd.DataFrame(missing).to_csv(audit_path, index=False, encoding="utf-8-sig")

    # Log summary by school
    by_school = Counter(r["source_school"] for r in missing)
    if missing:
        logger.info(
            "Blank case_type after backfill: %d rows — %s",
            len(missing),
            ", ".join(f"{s}: {n}" for s, n in by_school.most_common()),
        )
    else:
        logger.info("Blank case_type after backfill: 0 rows — all filled.")
