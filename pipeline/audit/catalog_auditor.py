"""
Case Catalog QA Auditor
=======================

Compares split case PDFs on disk against the case catalog CSV and produces
a structured set of audit reports.

Outputs (written to --output directory):
    case_catalog_audit_summary.json     — machine-readable summary
    case_catalog_audit_summary.md       — human-readable markdown report
    missing_from_catalog.csv            — files on disk not in catalog
    missing_file_on_disk.csv            — catalog rows whose file doesn't exist
    duplicate_catalog_rows.csv          — duplicate rows (3 duplicate types)
    suspicious_metadata.csv             — rows with metadata problems
    source_pdf_coverage_report.csv      — per-source-PDF pass/fail summary
"""

from __future__ import annotations

import json
import logging
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

logger = logging.getLogger(__name__)

# ── Expected case counts for gold-standard manual-override sources ─────────────

EXPECTED_CASE_COUNTS: dict[str, int] = {
    "Columbia 2017":    24,
    "Columbia 2021":    38,
    "Darden 2017":      14,
    "Darden 2018":      12,   # matches "Darden 2018-2019" filenames
    "Darden 2019":      12,   # secondary match for same file
    "Darden 2021":      12,
    "Darden 2024":      12,
    "Wharton 2017":     18,
    "Harvard 2002":     24,
    "Kellogg 2016":     33,
    "Kellogg 2023":     34,
    "Kellogg 2024":     36,
    "Ross 2019":        14,
    "Ross 2022":        18,
    "Ross 2024":        19,
    "Stern 2021":       25,
    "Stern 2025":       30,
    "Tuck 2024":        12,
    "Yale 2024":         8,
    "Yale 2025":         6,   # 8 duplicates of Yale 2024 removed; only unique cases kept
    "Booth 2026":       45,
    "Fuqua 2026":       18,
    "MIT 2011":         25,
}

# ── Sources where source_year is legitimately absent ──────────────────────────
# These are individual-case PDFs rather than year-stamped casebooks.
SOURCE_YEAR_OPTIONAL: tuple[str, ...] = (
    "RocketBlocks",
)

# ── Fuqua-style sources where is_duplicate_case=true without duplicate_of_* ───
# Classic / reused cases that don't have a traceable canonical origin.
DUPLICATE_WITHOUT_ORIGIN_OK: tuple[str, ...] = (
    "Fuqua 2026",
)

# ── Per-source required metadata fields ───────────────────────────────────────
# Maps a source-name fragment (checked via `in source_pdf`) to the set of
# catalog columns that must be non-blank for every row from that source.

REQUIRED_FIELDS: list[tuple[str, list[str]]] = [
    ("Booth 2026",        ["firm", "case_type", "industry", "difficulty"]),
    ("Columbia 2017",     ["case_type", "industry"]),
    ("Columbia 2021",     ["case_type", "industry", "difficulty"]),
    ("Darden 2017",       ["firm", "round", "difficulty"]),
    ("Darden 2018",       ["firm", "industry", "round", "difficulty",
                           "difficulty_quant", "difficulty_qual"]),
    ("Darden 2019",       ["firm", "industry", "round", "difficulty",
                           "difficulty_quant", "difficulty_qual"]),
    ("Darden 2021",       ["firm", "round", "industry"]),
    ("Darden 2024",       ["industry", "case_type",
                           "difficulty_quant", "difficulty_qual", "difficulty"]),
    ("Fuqua 2026",        ["industry", "case_type",
                           "difficulty_quant", "difficulty_qual"]),
    ("Kellogg 2016",      ["case_type", "industry"]),
    ("Kellogg 2023",      ["case_type", "industry"]),
    ("MIT 2011",          ["firm", "round"]),
    ("Ross 2019",         ["industry", "case_type"]),
    ("Ross 2022",         ["industry", "case_type"]),
    ("Ross 2024",         ["industry", "case_type"]),
    ("Stern 2021",        ["case_type", "industry",
                           "difficulty_quant", "difficulty_structure"]),
    ("Stern 2025",        ["case_type", "industry", "difficulty_structure"]),
    ("Tuck 2024",         ["industry", "case_type"]),
    ("Yale 2024",         ["industry",
                           "difficulty_quant", "difficulty_qual", "concepts_tested"]),
    ("Yale 2025",         ["industry",
                           "difficulty_quant", "difficulty_qual", "concepts_tested"]),
    # The following have no structured metadata requirements
    ("Harvard 2002",      []),
    ("Wharton 2017",      []),
]

# ── Path helpers ───────────────────────────────────────────────────────────────

def _path_key(p: Path | str) -> str:
    """Case-insensitive, separator-normalised string key for path comparison."""
    return str(p).lower().replace("\\", "/")


def _resolve(path_str: str, base: Path) -> Path:
    """Return an absolute Path, resolving relative paths against *base*."""
    p = Path(str(path_str).strip())
    return p if p.is_absolute() else (base / p)


def _is_blank(val: Any) -> bool:
    if val is None:
        return True
    if isinstance(val, float):
        import math
        return math.isnan(val)
    return str(val).strip() in ("", "None", "nan", "NaN")


def _required_for(source_pdf: str) -> list[str]:
    """Return the list of required metadata fields for a given source_pdf."""
    for fragment, fields in REQUIRED_FIELDS:
        if fragment in str(source_pdf):
            return fields
    return []


def _expected_count(source_pdf: str) -> int | None:
    """Return the expected case count if this source is gold-standard, else None."""
    for fragment, count in EXPECTED_CASE_COUNTS.items():
        if fragment in str(source_pdf):
            return count
    return None


# ── Auditor ────────────────────────────────────────────────────────────────────

class CatalogAuditor:
    """
    Compares the case catalog against split PDFs on disk.

    Parameters
    ----------
    catalog_path : path-like
        Path to case_catalog.csv (or .xlsx).
    cases_root : path-like
        Root directory that was used as the split output (e.g. output/cases).
    output_dir : path-like
        Directory where audit reports will be written.
    base_dir : path-like, optional
        Base directory for resolving relative paths stored in the catalog.
        Defaults to the current working directory.
    """

    def __init__(
        self,
        catalog_path: str | Path,
        cases_root: str | Path,
        output_dir: str | Path,
        base_dir: str | Path | None = None,
    ) -> None:
        self.catalog_path = Path(catalog_path).resolve()
        self.cases_root   = Path(cases_root).resolve()
        self.output_dir   = Path(output_dir)
        # Catalog stores paths relative to the *parent* of cases_root (e.g. "output/").
        # Use cases_root.parent as the resolution base unless the caller overrides it.
        self.base_dir = (
            Path(base_dir).resolve() if base_dir else self.cases_root.parent
        )

        # Internal state
        self.df: pd.DataFrame                    = pd.DataFrame()
        self.disk_files: set[Path]               = set()
        self.disk_file_keys: dict[str, Path]     = {}
        self.catalog_path_keys: dict[str, int]   = {}  # key → row index

        # Result buckets
        self.missing_from_catalog: list[dict]    = []
        self.missing_file_on_disk: list[dict]    = []
        self.duplicate_rows: list[dict]          = []
        self.suspicious_metadata: list[dict]     = []
        self.coverage_rows: list[dict]           = []
        self.summary: dict                       = {}

    # ── Public API ─────────────────────────────────────────────────────────────

    def run(self) -> dict:
        """Execute all audit checks and write reports. Returns the summary dict."""
        self.output_dir.mkdir(parents=True, exist_ok=True)
        logger.info("Audit: loading catalog from %s", self.catalog_path)
        self._load_catalog()
        logger.info("Audit: scanning disk under %s", self.cases_root)
        self._scan_disk()
        logger.info("Audit: checking coverage …")
        self._check_missing_from_catalog()
        self._check_missing_file_on_disk()
        self._check_duplicates()
        self._check_metadata()
        self._build_coverage_report()
        self._build_summary()
        logger.info("Audit: writing reports to %s", self.output_dir)
        self._write_outputs()
        return self.summary

    # ── Internal: loaders ──────────────────────────────────────────────────────

    def _load_catalog(self) -> None:
        p = self.catalog_path
        if p.suffix.lower() in (".xlsx", ".xls"):
            self.df = pd.read_excel(p, dtype=str)
        else:
            self.df = pd.read_csv(p, dtype=str, encoding="utf-8-sig")
        self.df = self.df.fillna("")
        logger.info("  catalog rows: %d", len(self.df))

        # Build path-key → row-index map for O(1) lookup
        for idx, row in self.df.iterrows():
            raw = row.get("output_pdf_path", "")
            if raw:
                resolved = _resolve(raw, self.base_dir)
                key = _path_key(resolved)
                self.catalog_path_keys[key] = idx

    def _scan_disk(self) -> None:
        if not self.cases_root.exists():
            logger.warning("cases_root does not exist: %s", self.cases_root)
            return
        files = list(self.cases_root.rglob("*.pdf"))
        self.disk_files = set(files)
        self.disk_file_keys = {_path_key(f): f for f in files}
        logger.info("  files on disk: %d", len(self.disk_files))

    # ── Check 1: files on disk but not in catalog ──────────────────────────────

    def _check_missing_from_catalog(self) -> None:
        catalog_keys = set(self.catalog_path_keys.keys())
        for key, file_path in self.disk_file_keys.items():
            if key not in catalog_keys:
                parts = file_path.parts
                # Try to infer school from the first directory under cases_root
                try:
                    rel = file_path.relative_to(self.cases_root)
                    school = rel.parts[0] if len(rel.parts) > 1 else ""
                except ValueError:
                    school = ""
                self.missing_from_catalog.append({
                    "output_pdf_path":       str(file_path),
                    "inferred_source_school": school,
                    "inferred_case_title":   file_path.stem.replace("-", " ").title(),
                    "issue":                 "file_exists_but_not_in_catalog",
                })
        logger.info("  missing from catalog: %d", len(self.missing_from_catalog))

    # ── Check 2: catalog rows missing real file ────────────────────────────────

    def _check_missing_file_on_disk(self) -> None:
        for _, row in self.df.iterrows():
            raw = row.get("output_pdf_path", "")
            if not raw:
                self.missing_file_on_disk.append({
                    "case_title":       row.get("case_title", ""),
                    "source_school":    row.get("source_school", ""),
                    "source_year":      row.get("source_year", ""),
                    "source_pdf":       row.get("source_pdf", ""),
                    "output_pdf_path":  "",
                    "issue":            "catalog_row_missing_output_pdf_path",
                })
                continue
            key = _path_key(_resolve(raw, self.base_dir))
            if key not in self.disk_file_keys:
                self.missing_file_on_disk.append({
                    "case_title":       row.get("case_title", ""),
                    "source_school":    row.get("source_school", ""),
                    "source_year":      row.get("source_year", ""),
                    "source_pdf":       row.get("source_pdf", ""),
                    "output_pdf_path":  raw,
                    "issue":            "catalog_row_missing_file",
                })
        logger.info("  catalog rows missing file: %d", len(self.missing_file_on_disk))

    # ── Check 3: duplicate catalog rows ───────────────────────────────────────

    def _check_duplicates(self) -> None:
        seen: dict[str, list[int]] = defaultdict(list)

        # Type A: same output_pdf_path
        a_groups: dict[str, list[int]] = defaultdict(list)
        for idx, row in self.df.iterrows():
            raw = row.get("output_pdf_path", "")
            if raw:
                key = _path_key(_resolve(raw, self.base_dir))
                a_groups[key].append(idx)
        for key, indices in a_groups.items():
            if len(indices) > 1:
                for idx in indices:
                    row = self.df.loc[idx]
                    self.duplicate_rows.append({
                        "duplicate_type":  "same_output_pdf_path",
                        "output_pdf_path": row.get("output_pdf_path", ""),
                        "case_title":      row.get("case_title", ""),
                        "source_pdf":      row.get("source_pdf", ""),
                        "page_start":      row.get("page_start", ""),
                        "page_end":        row.get("page_end", ""),
                        "row_index":       idx,
                    })

        # Type B: same source_pdf + case_title + page_start + page_end
        b_groups: dict[tuple, list[int]] = defaultdict(list)
        for idx, row in self.df.iterrows():
            key = (
                row.get("source_pdf", ""),
                row.get("case_title", ""),
                row.get("page_start", ""),
                row.get("page_end", ""),
            )
            b_groups[key].append(idx)
        for key, indices in b_groups.items():
            if len(indices) > 1:
                for idx in indices:
                    row = self.df.loc[idx]
                    self.duplicate_rows.append({
                        "duplicate_type":  "same_source_title_pages",
                        "output_pdf_path": row.get("output_pdf_path", ""),
                        "case_title":      row.get("case_title", ""),
                        "source_pdf":      row.get("source_pdf", ""),
                        "page_start":      row.get("page_start", ""),
                        "page_end":        row.get("page_end", ""),
                        "row_index":       idx,
                    })

        # Type C: same school + year + normalized_title + page_start
        c_groups: dict[tuple, list[int]] = defaultdict(list)
        for idx, row in self.df.iterrows():
            key = (
                row.get("source_school", ""),
                row.get("source_year", ""),
                row.get("normalized_title", ""),
                row.get("page_start", ""),
            )
            c_groups[key].append(idx)
        for key, indices in c_groups.items():
            if len(indices) > 1:
                for idx in indices:
                    row = self.df.loc[idx]
                    self.duplicate_rows.append({
                        "duplicate_type":  "same_school_year_title_pagestart",
                        "output_pdf_path": row.get("output_pdf_path", ""),
                        "case_title":      row.get("case_title", ""),
                        "source_pdf":      row.get("source_pdf", ""),
                        "page_start":      row.get("page_start", ""),
                        "page_end":        row.get("page_end", ""),
                        "row_index":       idx,
                    })

        logger.info("  duplicate row records: %d", len(self.duplicate_rows))

    # ── Check 4: suspicious metadata ──────────────────────────────────────────

    def _check_metadata(self) -> None:
        for idx, row in self.df.iterrows():
            issues: list[str] = []
            source_pdf = row.get("source_pdf", "")

            # ── Universal checks ──────────────────────────────────────────────
            if _is_blank(row.get("case_title")):
                issues.append("blank_case_title")
            if _is_blank(row.get("normalized_title")):
                issues.append("blank_normalized_title")
            if _is_blank(row.get("source_school")):
                issues.append("blank_source_school")
            year_optional = any(p in source_pdf for p in SOURCE_YEAR_OPTIONAL)
            if not year_optional and _is_blank(row.get("source_year")):
                issues.append("blank_source_year")
            if _is_blank(row.get("page_start")):
                issues.append("blank_page_start")
            if _is_blank(row.get("page_end")):
                issues.append("blank_page_end")
            if _is_blank(row.get("output_pdf_path")):
                issues.append("blank_output_pdf_path")

            # Page range sanity
            try:
                ps = int(float(row.get("page_start", 0)))
                pe = int(float(row.get("page_end", 0)))
                if ps > pe:
                    issues.append(f"page_start({ps})>page_end({pe})")
                if ps <= 0:
                    issues.append(f"page_start_not_positive({ps})")
            except (ValueError, TypeError):
                pass

            # Page count consistency
            try:
                ps = int(float(row.get("page_start", 0)))
                pe = int(float(row.get("page_end", 0)))
                pc_str = row.get("page_count", "")
                if pc_str and not _is_blank(pc_str):
                    pc = int(float(pc_str))
                    expected_pc = pe - ps + 1
                    if pc != expected_pc:
                        issues.append(
                            f"page_count_mismatch(stored={pc},computed={expected_pc})"
                        )
            except (ValueError, TypeError):
                pass

            # Manual-override cases should NOT need review
            dm = row.get("detection_method", "")
            if dm.startswith("manual_override_"):
                if row.get("needs_manual_review", "").strip().lower() == "true":
                    issues.append("manual_override_but_needs_review=true")

            # Duplicate flag integrity
            is_dup = row.get("is_duplicate_case", "").strip().lower()
            if is_dup == "true":
                dup_origin_ok = any(p in source_pdf for p in DUPLICATE_WITHOUT_ORIGIN_OK)
                if not dup_origin_ok and (
                    _is_blank(row.get("duplicate_of_source_school")) and
                    _is_blank(row.get("duplicate_of_case_title"))
                ):
                    issues.append(
                        "is_duplicate_case=true_but_missing_duplicate_of_fields"
                    )

            # ── Source-specific required fields ───────────────────────────────
            required = _required_for(source_pdf)
            for field in required:
                if _is_blank(row.get(field)):
                    issues.append(f"missing_required_field:{field}")

            if issues:
                self.suspicious_metadata.append({
                    "row_index":       idx,
                    "case_title":      row.get("case_title", ""),
                    "source_school":   row.get("source_school", ""),
                    "source_year":     row.get("source_year", ""),
                    "source_pdf":      source_pdf,
                    "detection_method": dm,
                    "output_pdf_path": row.get("output_pdf_path", ""),
                    "issues":          "; ".join(issues),
                })

        logger.info("  suspicious metadata rows: %d", len(self.suspicious_metadata))

    # ── Coverage report ────────────────────────────────────────────────────────

    def _build_coverage_report(self) -> None:
        # Group catalog rows by source_pdf
        groups: dict[str, list[int]] = defaultdict(list)
        for idx, row in self.df.iterrows():
            groups[row.get("source_pdf", "__unknown__")].append(idx)

        # Index quick lookups
        missing_disk_paths = {
            r["output_pdf_path"] for r in self.missing_file_on_disk
        }
        missing_catalog_keys = {
            _path_key(Path(r["output_pdf_path"]))
            for r in self.missing_from_catalog
        }
        dup_indices = {r["row_index"] for r in self.duplicate_rows}
        susp_indices = {r["row_index"] for r in self.suspicious_metadata}

        for source_pdf, indices in sorted(groups.items()):
            rows_for_source = [self.df.loc[i] for i in indices]
            catalog_count = len(indices)

            # Files that exist on disk for this source
            on_disk = 0
            miss_disk = 0
            for row in rows_for_source:
                raw = row.get("output_pdf_path", "")
                if not raw or raw in missing_disk_paths:
                    miss_disk += 1
                else:
                    key = _path_key(_resolve(raw, self.base_dir))
                    if key in self.disk_file_keys:
                        on_disk += 1
                    else:
                        miss_disk += 1

            dup_count  = len([i for i in indices if i in dup_indices])
            susp_count = len([i for i in indices if i in susp_indices])

            expected = _expected_count(source_pdf)

            # Determine status
            status = "PASS"
            warnings: list[str] = []

            if miss_disk > 0:
                status = "FAIL"
                warnings.append(f"{miss_disk}_files_missing_on_disk")
            if expected is not None and catalog_count != expected:
                status = "FAIL"
                warnings.append(
                    f"expected_{expected}_cases_got_{catalog_count}"
                )
            if expected is not None and on_disk != expected:
                status = "FAIL"
                warnings.append(
                    f"expected_{expected}_files_on_disk_got_{on_disk}"
                )
            if dup_count > 0:
                if status == "PASS":
                    status = "PASS_WITH_WARNINGS"
                warnings.append(f"{dup_count}_duplicate_rows")
            if susp_count > 0:
                if status == "PASS":
                    status = "PASS_WITH_WARNINGS"
                warnings.append(f"{susp_count}_suspicious_metadata_rows")

            row_data = self.df.loc[indices[0]]
            self.coverage_rows.append({
                "source_school":              row_data.get("source_school", ""),
                "source_year":                row_data.get("source_year", ""),
                "source_pdf":                 source_pdf,
                "expected_case_count":        expected if expected is not None else "",
                "catalog_case_count":         catalog_count,
                "files_on_disk_count":        on_disk,
                "missing_from_catalog_count": 0,   # calculated below
                "missing_file_on_disk_count": miss_disk,
                "duplicate_row_count":        dup_count,
                "suspicious_row_count":       susp_count,
                "audit_status":               status,
                "warnings":                   "; ".join(warnings) if warnings else "",
            })

        # Fill in missing_from_catalog_count — files on disk not attributed to a source
        # (These are reported in missing_from_catalog.csv but have no source_pdf yet)
        for coverage_row in self.coverage_rows:
            coverage_row["missing_from_catalog_count"] = len(self.missing_from_catalog)

        logger.info(
            "  coverage report: %d source PDFs, %d PASS, %d PASS_WITH_WARNINGS, %d FAIL",
            len(self.coverage_rows),
            sum(1 for r in self.coverage_rows if r["audit_status"] == "PASS"),
            sum(1 for r in self.coverage_rows if r["audit_status"] == "PASS_WITH_WARNINGS"),
            sum(1 for r in self.coverage_rows if r["audit_status"] == "FAIL"),
        )

    # ── Summary ────────────────────────────────────────────────────────────────

    def _build_summary(self) -> None:
        pass_sources  = [r for r in self.coverage_rows if r["audit_status"] == "PASS"]
        warn_sources  = [r for r in self.coverage_rows if r["audit_status"] == "PASS_WITH_WARNINGS"]
        fail_sources  = [r for r in self.coverage_rows if r["audit_status"] == "FAIL"]

        self.summary = {
            "generated_at":             datetime.now(timezone.utc).isoformat(),
            "catalog_path":             str(self.catalog_path),
            "cases_root":               str(self.cases_root),
            "total_catalog_rows":       len(self.df),
            "total_files_on_disk":      len(self.disk_files),
            "missing_from_catalog":     len(self.missing_from_catalog),
            "missing_file_on_disk":     len(self.missing_file_on_disk),
            "duplicate_records":        len(self.duplicate_rows),
            "suspicious_metadata_rows": len(self.suspicious_metadata),
            "source_pdfs_total":        len(self.coverage_rows),
            "source_pdfs_pass":         len(pass_sources),
            "source_pdfs_warn":         len(warn_sources),
            "source_pdfs_fail":         len(fail_sources),
            "failing_sources":          [r["source_pdf"] for r in fail_sources],
            "warning_sources":          [r["source_pdf"] for r in warn_sources],
            "overall_status": (
                "FAIL"             if fail_sources  else
                "PASS_WITH_WARNINGS" if warn_sources else
                "PASS"
            ),
        }

    # ── Writers ────────────────────────────────────────────────────────────────

    def _write_outputs(self) -> None:
        od = self.output_dir

        def _write_csv(rows: list[dict], name: str) -> None:
            path = od / name
            pd.DataFrame(rows).to_csv(path, index=False, encoding="utf-8-sig")
            logger.info("  wrote %s (%d rows)", name, len(rows))

        _write_csv(self.missing_from_catalog,  "missing_from_catalog.csv")
        _write_csv(self.missing_file_on_disk,  "missing_file_on_disk.csv")
        _write_csv(self.duplicate_rows,         "duplicate_catalog_rows.csv")
        _write_csv(self.suspicious_metadata,    "suspicious_metadata.csv")
        _write_csv(self.coverage_rows,          "source_pdf_coverage_report.csv")

        # JSON summary
        json_path = od / "case_catalog_audit_summary.json"
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(self.summary, f, indent=2, ensure_ascii=False)
        logger.info("  wrote case_catalog_audit_summary.json")

        # Markdown summary
        self._write_markdown(od / "case_catalog_audit_summary.md")
        logger.info("  wrote case_catalog_audit_summary.md")

    def _write_markdown(self, path: Path) -> None:
        s = self.summary
        lines: list[str] = []
        a = lines.append

        a("# Case Catalog QA Audit Report")
        a("")
        a(f"Generated: {s['generated_at']}")
        a(f"Catalog:   `{s['catalog_path']}`")
        a(f"Cases dir: `{s['cases_root']}`")
        a("")
        a(f"**Overall status: {s['overall_status']}**")
        a("")

        # ── Headline numbers ──────────────────────────────────────────────────
        a("## Summary")
        a("")
        a("| Metric | Count |")
        a("|---|---|")
        a(f"| Total catalog rows | {s['total_catalog_rows']} |")
        a(f"| Total files on disk | {s['total_files_on_disk']} |")
        a(f"| Files missing from catalog | {s['missing_from_catalog']} |")
        a(f"| Catalog rows missing file | {s['missing_file_on_disk']} |")
        a(f"| Duplicate catalog records | {s['duplicate_records']} |")
        a(f"| Suspicious metadata rows | {s['suspicious_metadata_rows']} |")
        a(f"| Source PDFs: PASS | {s['source_pdfs_pass']} |")
        a(f"| Source PDFs: PASS WITH WARNINGS | {s['source_pdfs_warn']} |")
        a(f"| Source PDFs: FAIL | {s['source_pdfs_fail']} |")
        a("")

        # ── Failing sources ────────────────────────────────────────────────────
        if s["failing_sources"]:
            a("## Failing Sources")
            a("")
            for src in s["failing_sources"]:
                cov = next(r for r in self.coverage_rows if r["source_pdf"] == src)
                a(f"- **{src}** — {cov['warnings']}")
            a("")

        if s["warning_sources"]:
            a("## Sources with Warnings")
            a("")
            for src in s["warning_sources"]:
                cov = next(r for r in self.coverage_rows if r["source_pdf"] == src)
                a(f"- **{src}** — {cov['warnings']}")
            a("")

        # ── Source PDF coverage table ──────────────────────────────────────────
        a("## Source PDF Coverage")
        a("")
        a("| Source PDF | Expected | Catalog | On Disk | Miss Disk | Dups | Susp | Status |")
        a("|---|---|---|---|---|---|---|---|")
        for r in self.coverage_rows:
            exp = r["expected_case_count"] if r["expected_case_count"] != "" else "—"
            a(
                f"| {r['source_pdf']} "
                f"| {exp} "
                f"| {r['catalog_case_count']} "
                f"| {r['files_on_disk_count']} "
                f"| {r['missing_file_on_disk_count']} "
                f"| {r['duplicate_row_count']} "
                f"| {r['suspicious_row_count']} "
                f"| **{r['audit_status']}** |"
            )
        a("")

        # ── Priority fixes ─────────────────────────────────────────────────────
        a("## Highest Priority Fixes")
        a("")
        priority: list[tuple[int, str]] = []

        if s["missing_file_on_disk"] > 0:
            priority.append((1, f"**{s['missing_file_on_disk']} catalog rows have no file on disk** "
                               f"→ see `missing_file_on_disk.csv`"))
        if s["missing_from_catalog"] > 0:
            priority.append((2, f"**{s['missing_from_catalog']} files on disk have no catalog row** "
                               f"→ see `missing_from_catalog.csv`"))
        for src in s["failing_sources"]:
            cov = next(r for r in self.coverage_rows if r["source_pdf"] == src)
            if "expected" in cov["warnings"]:
                priority.append((3, f"**Count mismatch: {src}** — {cov['warnings']}"))
        if s["duplicate_records"] > 0:
            priority.append((4, f"**{s['duplicate_records']} duplicate records** "
                               f"→ see `duplicate_catalog_rows.csv`"))
        if s["suspicious_metadata_rows"] > 0:
            priority.append((5, f"**{s['suspicious_metadata_rows']} suspicious metadata rows** "
                               f"→ see `suspicious_metadata.csv`"))

        if priority:
            for _, msg in sorted(priority):
                a(f"1. {msg}")
        else:
            a("None — all checks passed.")
        a("")

        # ── How to run ─────────────────────────────────────────────────────────
        a("## How to Re-run this Audit")
        a("")
        a("```bash")
        a("python main.py audit-catalog \\")
        a("    --catalog output/case_catalog.csv \\")
        a("    --cases-root output/cases \\")
        a("    --output output/audit")
        a("```")
        a("")

        path.write_text("\n".join(lines), encoding="utf-8")


# ── Convenience function ───────────────────────────────────────────────────────

def run_audit(
    catalog_path: str | Path,
    cases_root: str | Path,
    output_dir: str | Path,
    base_dir: str | Path | None = None,
) -> dict:
    """Run the full audit and return the summary dict."""
    auditor = CatalogAuditor(catalog_path, cases_root, output_dir, base_dir)
    return auditor.run()
