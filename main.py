#!/usr/bin/env python3
"""
case-splitter — command-line interface.

Commands
--------
  scan           Recursively scan a directory and classify PDFs (no splitting).
  split          Full pipeline: scan → classify → parse → split → manifest.
  review         Pretty-print the review queue from an existing manifest.
  export-catalog Build case_catalog.csv + case_catalog.xlsx from a manifest.
  classify-difficulty  Fill missing difficulty labels via the OpenAI API.
  evaluate-difficulty-calibration  QA the classifier against existing labels.
  classify-industry    Fill missing industry labels via the OpenAI API.

Examples
--------
  python main.py scan  --input "Case Repo"
  python main.py split --input "Case Repo" --output output
  python main.py split --input "Case Repo" --output output --dry-run
  python main.py split --input "Case Repo" --output output --verbose
  python main.py review --manifest output/manifest.json
  python main.py export-catalog --manifest output/manifest.json --output output
"""

import json
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import click
import yaml

# Add project root to path so absolute imports work when calling as a script
sys.path.insert(0, str(Path(__file__).parent))


# ── Zero-dependency .env loader ────────────────────────────────────────────────
# Loads KEY=VALUE pairs from a `.env` file in the project root into the
# environment on import. Only sets vars that are not already present, so
# explicit shell exports always win. Quoted values and blank / comment
# lines are handled. No external packages required.

def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
    except OSError:
        return


_load_dotenv(Path(__file__).parent / ".env")

from pipeline.orchestrator import run_pipeline
from pipeline.scanner import scan_directory
from pipeline.classifier import classify_document
from utils.logging_setup import setup_logging

import fitz  # noqa: F401  (validate install early)


# ── Config loading ─────────────────────────────────────────────────────────────

def _load_config(config_path: Path) -> SimpleNamespace:
    """Load config.yaml into a nested SimpleNamespace for attribute access."""
    with open(config_path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return _to_namespace(data)


def _to_namespace(obj):
    """Recursively convert dicts to SimpleNamespace; leave other types as-is."""
    if isinstance(obj, dict):
        ns = SimpleNamespace()
        for key, value in obj.items():
            setattr(ns, key, _to_namespace(value))
        return ns
    if isinstance(obj, list):
        return [_to_namespace(item) for item in obj]
    return obj


def _resolve_config(config_path_str: str) -> SimpleNamespace:
    """Resolve config path and load it, with helpful error on failure."""
    cfg_path = Path(config_path_str)
    if not cfg_path.exists():
        click.echo(f"ERROR: config file not found: {cfg_path}", err=True)
        raise SystemExit(1)
    return _load_config(cfg_path)


def _safe_write_catalog(df, out_path: Path) -> None:
    """Write catalog DataFrame, falling back gracefully when the target
    file is locked (e.g. open in Excel).

    For an XLSX target we always write the CSV companion first so the
    work is never lost even if Excel has the .xlsx open. For a CSV
    target we only attempt the CSV write.
    """
    is_xlsx = out_path.suffix.lower() in {".xlsx", ".xlsm"}

    if is_xlsx:
        # Always update the CSV companion first; it's rarely locked.
        csv_companion = out_path.with_suffix(".csv")
        try:
            df.to_csv(csv_companion, index=False)
            click.echo(f"\nCatalog CSV written : {csv_companion.resolve()}")
        except OSError as exc:
            click.echo(
                f"\nERROR: could not write {csv_companion}: {exc}",
                err=True,
            )

        try:
            df.to_excel(out_path, index=False)
            click.echo(f"Catalog XLSX written: {out_path.resolve()}")
        except PermissionError:
            click.echo(
                f"\nWARNING: {out_path} is locked (open in Excel?). "
                f"The CSV companion at {csv_companion} was updated. "
                f"Close Excel and re-run to refresh the .xlsx.",
                err=True,
            )
        except Exception as exc:  # noqa: BLE001
            click.echo(
                f"\nWARNING: failed to write {out_path}: {exc}. "
                f"CSV companion at {csv_companion} is current.",
                err=True,
            )
        return

    try:
        df.to_csv(out_path, index=False)
        click.echo(f"\nCatalog written: {out_path.resolve()}")
    except OSError as exc:
        click.echo(f"\nERROR: could not write {out_path}: {exc}", err=True)
        raise SystemExit(1)


# ── CLI group ──────────────────────────────────────────────────────────────────

@click.group()
def cli():
    """case-splitter: split consulting casebook PDFs into individual cases."""


# ── scan command ───────────────────────────────────────────────────────────────

@cli.command()
@click.option("--input", "input_dir", required=True,
              help="Root directory containing casebook PDFs.")
@click.option("--config", "config_path", default="config.yaml", show_default=True,
              help="Path to config.yaml.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
def scan(input_dir: str, config_path: str, verbose: bool):
    """
    Scan a directory and classify every PDF (no files written).

    Use this to preview what the pipeline will do before committing
    to a full split run.
    """
    setup_logging(verbose=verbose)
    config = _resolve_config(config_path)
    root = Path(input_dir)

    click.echo(f"\nScanning: {root.resolve()}\n")
    # Exclude common output directory names to avoid re-scanning previous runs
    default_excl = [root / "output"]
    exclude = [p.resolve() for p in default_excl if p.exists()]
    documents = scan_directory(root, config, exclude_dirs=exclude)

    # Classify each document
    import fitz as _fitz
    for doc_record in documents:
        if not doc_record.is_processable():
            click.echo(
                f"  [SKIP]  {doc_record.relative_path}  "
                f"({doc_record.processing_error})"
            )
            continue
        try:
            doc = _fitz.open(str(doc_record.path))
            classify_document(doc_record, doc, config)
            doc.close()
        except Exception as exc:
            click.echo(f"  [ERR]  {doc_record.relative_path}: {exc}")
            continue

        status_icon = {
            "multi_case":  "[MULTI]",
            "single_case": "[SINGLE]",
            "unknown":     "[UNKNWN]",
        }.get(doc_record.classification, "[?]")

        click.echo(
            f"  {status_icon}  {doc_record.relative_path}  "
            f"({doc_record.page_count}p, conf={doc_record.classification_confidence:.2f})"
        )
        if verbose:
            for note in doc_record.classification_notes:
                click.echo(f"           {note}")

    # Summary counts
    total = len(documents)
    multi  = sum(1 for d in documents if d.classification == "multi_case")
    single = sum(1 for d in documents if d.classification == "single_case")
    unk    = sum(1 for d in documents if d.classification == "unknown")
    skip   = sum(1 for d in documents if not d.is_processable())

    click.echo(
        f"\nTotal: {total} PDFs | "
        f"multi={multi} single={single} unknown={unk} skipped={skip}\n"
    )


# ── split command ──────────────────────────────────────────────────────────────

@cli.command()
@click.option("--input", "input_dir", required=True,
              help="Root directory containing casebook PDFs.")
@click.option("--output", "output_dir", default="output", show_default=True,
              help="Directory to write split PDFs and manifests.")
@click.option("--config", "config_path", default="config.yaml", show_default=True,
              help="Path to config.yaml.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Log what would happen without writing any files.")
@click.option("--clean", is_flag=True, default=False,
              help="Delete and recreate the output/cases directory before splitting "
                   "so stale files from previous runs are removed.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
@click.option("--log-file", "log_file", default=None,
              help="Optional file path for full DEBUG log.")
def split(
    input_dir: str,
    output_dir: str,
    config_path: str,
    dry_run: bool,
    clean: bool,
    verbose: bool,
    log_file: str | None,
):
    """
    Full pipeline: scan → classify → parse boundaries → split PDFs → manifest.

    Output layout:
      {output}/cases/{folder}/{pdf_stem}/{case_slug}.pdf
      {output}/manifest.json
      {output}/manifest.csv
      {output}/review_queue.csv

    Use --clean to wipe stale files from previous runs before writing.
    """
    import shutil

    log_path = Path(log_file) if log_file else Path(output_dir) / "pipeline.log"
    setup_logging(verbose=verbose, log_file=log_path if log_file or not dry_run else None)

    config = _resolve_config(config_path)
    root   = Path(input_dir)
    out    = Path(output_dir)

    if dry_run:
        click.echo("\n[DRY-RUN MODE] No files will be written.\n")
    else:
        cases_dir = out / "cases"
        if clean and cases_dir.exists():
            click.echo(f"\n[--clean] Removing {cases_dir.resolve()} ...")
            shutil.rmtree(cases_dir)
        out.mkdir(parents=True, exist_ok=True)
        click.echo(f"\nOutput directory: {out.resolve()}\n")

    # Exclude the output directory in case it lives inside the input tree
    exclude = [out.resolve()] if out.resolve().is_relative_to(root.resolve()) else []
    documents = scan_directory(root, config, exclude_dirs=exclude)
    if not documents:
        click.echo("No PDFs found. Check your --input path.")
        raise SystemExit(0)

    run_pipeline(documents, out, config, dry_run=dry_run)

    if not dry_run:
        click.echo(f"\nManifest: {out / 'manifest.json'}")
        click.echo(f"Review:   {out / 'review_queue.csv'}")

        # Auto-export case catalog after every successful split run
        manifest_path = out / "manifest.json"
        if manifest_path.exists():
            try:
                from pipeline.exporters.case_catalog import export_catalog
                csv_p, xlsx_p = export_catalog(manifest_path, out, base_dir=out)
                click.echo(f"Catalog:  {csv_p}")
                click.echo(f"          {xlsx_p}")
            except Exception as exc:
                click.echo(f"\n[WARN] Catalog export failed: {exc}", err=True)
        click.echo()


# ── export-catalog command ─────────────────────────────────────────────────────

@cli.command("export-catalog")
@click.option("--manifest", "manifest_path", required=True,
              help="Path to an existing manifest.json.")
@click.option("--output", "output_dir", default="output", show_default=True,
              help="Directory to write case_catalog.csv and case_catalog.xlsx.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
def export_catalog_cmd(manifest_path: str, output_dir: str, verbose: bool):
    """
    Build case_catalog.csv and case_catalog.xlsx from an existing manifest.

    Applies ground-truth enrichment (industry, case type, difficulty) for
    known casebooks (Columbia 2021, Columbia 2017) and writes a clean
    spreadsheet ready for web-app or filtering use.

    Example:
      python main.py export-catalog --manifest output/manifest.json
    """
    setup_logging(verbose=verbose)
    from pipeline.exporters.case_catalog import export_catalog

    m_path = Path(manifest_path)
    o_dir  = Path(output_dir)

    if not m_path.exists():
        click.echo(f"ERROR: manifest not found: {m_path}", err=True)
        raise SystemExit(1)

    click.echo(f"\nBuilding catalog from: {m_path.resolve()}")
    try:
        csv_p, xlsx_p = export_catalog(m_path, o_dir, base_dir=o_dir.resolve())
        click.echo(f"  CSV:  {csv_p.resolve()}")
        click.echo(f"  XLSX: {xlsx_p.resolve()}")
        click.echo()
    except Exception as exc:
        click.echo(f"ERROR: {exc}", err=True)
        raise SystemExit(1)


# ── publish-cases command ──────────────────────────────────────────────────────

@cli.command("publish-cases")
@click.option("--catalog", "catalog_path", default="output/case_catalog.csv",
              show_default=True,
              help="Path to case_catalog.csv or .xlsx.")
@click.option("--database-url", "database_url", default=None,
              help="Postgres connection string. Defaults to $DATABASE_URL from .env.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Read + clean the catalog but don't connect to the database.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
def publish_cases_cmd(catalog_path: str, database_url: str, dry_run: bool, verbose: bool):
    """
    Sync output/case_catalog.csv into the Postgres `cases` table.

    Idempotent: re-running updates existing rows in place rather than
    duplicating them. Safe to run after every pipeline execution.

    Example:
      python main.py publish-cases
      python main.py publish-cases --catalog output/case_catalog.xlsx --dry-run
    """
    setup_logging(verbose=verbose)
    from pipeline.publishers.postgres import publish_catalog

    db_url = database_url or os.environ.get("DATABASE_URL")
    if not db_url and not dry_run:
        click.echo(
            "ERROR: no database URL provided.\n"
            "  Set DATABASE_URL in .env, or pass --database-url.\n"
            "  Example: postgresql://postgres:postgres@localhost:5432/caserepo",
            err=True,
        )
        raise SystemExit(1)

    cat_path = Path(catalog_path)
    if not cat_path.exists():
        click.echo(f"ERROR: catalog not found: {cat_path}", err=True)
        raise SystemExit(1)

    click.echo(f"\nReading catalog: {cat_path.resolve()}")
    if dry_run:
        click.echo("(dry run — no database writes)")

    try:
        stats = publish_catalog(cat_path, db_url or "", dry_run=dry_run)
    except Exception as exc:
        click.echo(f"ERROR: {exc}", err=True)
        raise SystemExit(1)

    click.echo("\nResult:")
    click.echo(f"  Total rows in catalog: {stats['total_rows']}")
    click.echo(f"  Prepared for upsert:   {stats['prepared']}")
    click.echo(f"  Skipped (bad rows):    {stats['skipped']}")
    click.echo(f"  Missing PDF on disk:   {stats.get('missing_files', 0)}")
    if not dry_run:
        click.echo(f"  Inserted:              {stats['inserted']}")
        click.echo(f"  Updated:               {stats['updated']}")
    click.echo()


# ── serve command ──────────────────────────────────────────────────────────────

@cli.command("serve")
@click.option("--host", default="127.0.0.1", show_default=True,
              help="Bind address. Use 0.0.0.0 to expose on the LAN.")
@click.option("--port", default=8000, show_default=True, type=int,
              help="Port to listen on.")
@click.option("--reload", is_flag=True, default=False,
              help="Auto-reload on code changes (dev only).")
def serve_cmd(host: str, port: int, reload: bool):
    """
    Launch the Case Repo web application.

    Equivalent to:
      uvicorn webapp.main:app --host HOST --port PORT [--reload]

    Example:
      python main.py serve --reload
    """
    import uvicorn
    click.echo(f"\nStarting Case Repo on http://{host}:{port}")
    click.echo(f"  Press Ctrl+C to stop.\n")
    uvicorn.run(
        "webapp.main:app",
        host=host,
        port=port,
        reload=reload,
        log_level="info",
    )


# ── verify-storage command ─────────────────────────────────────────────────────

@cli.command("verify-storage")
@click.option("--database-url", "database_url", default=None,
              help="Postgres connection string. Defaults to $DATABASE_URL.")
@click.option("--show", "show_n", default=10, show_default=True,
              help="Number of missing rows to print before truncating.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
def verify_storage_cmd(database_url: str, show_n: int, verbose: bool):
    """
    Walk every row in the cases table and check the PDF actually exists
    in the configured storage backend.

    Useful right after a `publish-cases` run, or on prod to detect
    bucket-vs-database drift. Read-only: never modifies the database.

    Example:
      python main.py verify-storage
    """
    setup_logging(verbose=verbose)
    import psycopg
    from pipeline.storage import get_storage

    db_url = database_url or os.environ.get("DATABASE_URL")
    if not db_url:
        click.echo("ERROR: DATABASE_URL not set in environment or --database-url.", err=True)
        raise SystemExit(1)

    storage = get_storage()
    click.echo(f"\nUsing storage backend: {storage}")

    found = 0
    missing: list[tuple[int, str, str]] = []
    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, case_title, pdf_path FROM cases ORDER BY id;")
            for row_id, title, key in cur:
                if key and storage.exists(key):
                    found += 1
                else:
                    missing.append((row_id, title or "<no title>", key or "<no key>"))

    total = found + len(missing)
    click.echo(f"\nVerified {total} rows:")
    click.echo(f"  Reachable: {found}")
    click.echo(f"  Missing:   {len(missing)}")

    if missing:
        click.echo(f"\nFirst {min(show_n, len(missing))} missing:")
        for row_id, title, key in missing[:show_n]:
            click.echo(f"  id={row_id:<4}  {title}")
            click.echo(f"    key: {key}")
        if len(missing) > show_n:
            click.echo(f"  ... and {len(missing) - show_n} more (use --show N to see more)")
        raise SystemExit(2)
    click.echo()


# ── review command ─────────────────────────────────────────────────────────────

@cli.command()
@click.option("--manifest", "manifest_path", required=True,
              help="Path to an existing manifest.json.")
@click.option("--only-flagged", is_flag=True, default=False,
              help="Show only cases that need manual review.")
def review(manifest_path: str, only_flagged: bool):
    """
    Pretty-print cases from an existing manifest for inspection.

    Useful for quickly checking what the pipeline produced without
    opening the CSV files.
    """
    path = Path(manifest_path)
    if not path.exists():
        click.echo(f"ERROR: manifest not found: {path}", err=True)
        raise SystemExit(1)

    with open(path, encoding="utf-8") as f:
        cases = json.load(f)

    if only_flagged:
        cases = [c for c in cases if c.get("needs_manual_review")]

    if not cases:
        click.echo("No cases to show.")
        return

    sep = "-" * 65
    click.echo(f"\n{sep}")
    click.echo(f"  {'TITLE':<36} {'PG':>4}  {'CONF':>5}  {'FLAGS'}")
    click.echo(sep)

    for case in cases:
        flags = "; ".join(case.get("review_flags", []))
        title = case.get("case_title", "")[:35]
        pages = f"{case.get('page_start')}-{case.get('page_end')}"
        conf  = f"{case.get('extraction_confidence', 0):.2f}"
        marker = "* " if case.get("needs_manual_review") else "  "
        click.echo(f"{marker} {title:<36} {pages:>6}  {conf:>5}  {flags}")

    flagged = sum(1 for c in cases if c.get("needs_manual_review"))
    click.echo(sep)
    click.echo(f"  Total: {len(cases)} cases | {flagged} need review\n")


# ── audit-catalog command ──────────────────────────────────────────────────────

@cli.command("audit-catalog")
@click.option("--catalog", "catalog_path",
              default="output/case_catalog.csv", show_default=True,
              help="Path to the case_catalog.csv (or .xlsx) file.")
@click.option("--cases-root", "cases_root",
              default="output/cases", show_default=True,
              help="Root directory containing split case PDFs.")
@click.option("--output", "output_dir",
              default="output/audit", show_default=True,
              help="Directory to write audit reports into.")
@click.option("--base-dir", "base_dir",
              default=None,
              help="Base directory for resolving relative paths in the catalog "
                   "(defaults to current working directory).")
@click.option("--verbose", is_flag=True, default=False)
def audit_catalog_cmd(
    catalog_path: str,
    cases_root: str,
    output_dir: str,
    base_dir: str | None,
    verbose: bool,
) -> None:
    """
    QA audit: compare split case files on disk against the case catalog.

    Produces a set of CSV, JSON, and Markdown reports in the --output directory
    that answer:

    \b
      - What files are missing from the catalog?
      - What catalog rows have no file on disk?
      - Are there duplicate rows?
      - Are there metadata gaps?
      - Which source PDFs pass / fail coverage checks?

    Example:

    \b
      python main.py audit-catalog \\
          --catalog output/case_catalog.csv \\
          --cases-root output/cases \\
          --output output/audit
    """
    import logging
    log_level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=log_level,
                        format="%(asctime)s  %(levelname)-8s  %(name)s: %(message)s",
                        datefmt="%H:%M:%S")

    from pipeline.audit.catalog_auditor import run_audit

    cat  = Path(catalog_path)
    root = Path(cases_root)
    out  = Path(output_dir)

    if not cat.exists():
        click.echo(f"ERROR: catalog not found: {cat}", err=True)
        raise SystemExit(1)
    if not root.exists():
        click.echo(f"ERROR: cases-root not found: {root}", err=True)
        raise SystemExit(1)

    click.echo(f"\nRunning catalog audit …")
    click.echo(f"  Catalog:    {cat}")
    click.echo(f"  Cases root: {root}")
    click.echo(f"  Output:     {out}\n")

    summary = run_audit(
        catalog_path=cat,
        cases_root=root,
        output_dir=out,
        base_dir=Path(base_dir) if base_dir else None,
    )

    status = summary["overall_status"]
    color  = "green" if status == "PASS" else ("yellow" if "WARNING" in status else "red")

    click.echo("")
    click.echo(f"  Overall status : " + click.style(status, fg=color, bold=True))
    click.echo(f"  Catalog rows   : {summary['total_catalog_rows']}")
    click.echo(f"  Files on disk  : {summary['total_files_on_disk']}")
    click.echo(f"  Missing from catalog : {summary['missing_from_catalog']}")
    click.echo(f"  Missing file on disk : {summary['missing_file_on_disk']}")
    click.echo(f"  Duplicate records    : {summary['duplicate_records']}")
    click.echo(f"  Suspicious rows      : {summary['suspicious_metadata_rows']}")
    click.echo(f"  Sources PASS         : {summary['source_pdfs_pass']}")
    click.echo(f"  Sources WARN         : {summary['source_pdfs_warn']}")
    click.echo(f"  Sources FAIL         : {summary['source_pdfs_fail']}")

    if summary["failing_sources"]:
        click.echo("\n  Failing sources:")
        for src in summary["failing_sources"]:
            click.echo(f"    - {src}")

    click.echo(f"\n  Reports written to: {out.resolve()}")
    click.echo(f"  Summary MD : {out / 'case_catalog_audit_summary.md'}")
    click.echo("")


# ── classify-difficulty command ────────────────────────────────────────────────

@cli.command("classify-difficulty")
@click.option("--catalog", "catalog_path",
              default="output/case_catalog.xlsx", show_default=True,
              help="Path to case_catalog.csv or case_catalog.xlsx.")
@click.option("--output", "output_path", default=None,
              help="Where to write the updated catalog. Defaults to "
                   "overwriting --catalog.")
@click.option("--audit-dir", "audit_dir",
              default="output/audit", show_default=True,
              help="Directory for the LLM prediction / failure / review audit files.")
@click.option("--cases-root", "cases_root", default=None,
              help="Root directory containing split case PDFs. If provided, "
                   "the classifier will read the first few pages of each case "
                   "and include an excerpt in the model prompt.")
@click.option("--model", "model", default=None,
              help="OpenAI model to use. Defaults to the OPENAI_MODEL env var "
                   "or 'gpt-5.4'.")
@click.option("--limit", type=int, default=None,
              help="Classify at most N rows (useful for smoke tests).")
@click.option("--fill-missing-only/--force", "fill_missing_only",
              default=True, show_default=True,
              help="By default only fills rows with blank difficulty_normalized. "
                   "--force re-rates every row, overwriting existing labels.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Build packets and log what would happen, but don't call "
                   "the API or modify the catalog.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
def classify_difficulty_cmd(
    catalog_path: str,
    output_path: str | None,
    audit_dir: str,
    cases_root: str | None,
    model: str | None,
    limit: int | None,
    fill_missing_only: bool,
    dry_run: bool,
    verbose: bool,
):
    """
    Classify unlabeled case difficulties with an OpenAI model.

    For every catalog row missing a `difficulty_normalized` value, builds
    a compact prompt packet, calls the OpenAI Responses API with a
    strict JSON schema, and writes the result back into the catalog.

    A small set of already-labeled cases from the catalog is passed to
    the model as calibration anchors so predictions stay on the scale
    the project has been using.

    Requires the OPENAI_API_KEY environment variable (unless --dry-run).

    Example:

    \b
      export OPENAI_API_KEY=sk-...
      python main.py classify-difficulty \\
          --catalog output/case_catalog.xlsx \\
          --cases-root output/cases \\
          --limit 20
    """
    setup_logging(verbose=verbose)
    from pipeline.enrichment.openai_difficulty_classifier import (
        classify_missing_difficulties,
    )

    cat_path = Path(catalog_path)
    if not cat_path.exists():
        click.echo(f"ERROR: catalog not found: {cat_path}", err=True)
        raise SystemExit(1)

    out_path = Path(output_path) if output_path else cat_path
    audit = Path(audit_dir)
    cases_root_p = Path(cases_root) if cases_root else None

    # Read catalog (supports both CSV and XLSX).
    import pandas as pd
    if cat_path.suffix.lower() in {".xlsx", ".xlsm"}:
        df = pd.read_excel(cat_path)
    else:
        df = pd.read_csv(cat_path)

    click.echo(f"\nLoaded {len(df)} catalog rows from {cat_path}.")
    if dry_run:
        click.echo("[DRY-RUN] No API calls or file writes will happen.\n")

    updated = classify_missing_difficulties(
        df,
        model=model,
        limit=limit,
        force=not fill_missing_only,
        dry_run=dry_run,
        audit_dir=audit,
        cases_root=cases_root_p,
    )

    if dry_run:
        click.echo("\nDry run complete — catalog not modified.\n")
        return

    _safe_write_catalog(updated, out_path)

    click.echo(f"\nAudit outputs:  {audit.resolve()}")
    click.echo("  - llm_difficulty_predictions.csv")
    click.echo("  - llm_difficulty_failures.csv")
    click.echo("  - llm_difficulty_needs_review.csv")
    click.echo()


# ── evaluate-difficulty-calibration command ───────────────────────────────────

@cli.command("evaluate-difficulty-calibration")
@click.option("--catalog", "catalog_path",
              default="output/case_catalog.xlsx", show_default=True,
              help="Path to case_catalog.csv or case_catalog.xlsx.")
@click.option("--cases-root", "cases_root", default=None,
              help="Root directory containing split case PDFs. If provided, "
                   "each packet includes an excerpt from the case PDF.")
@click.option("--output", "audit_dir",
              default="output/audit", show_default=True,
              help="Directory for the evaluation CSV and summary JSON.")
@click.option("--model", "model", default=None,
              help="OpenAI model to use. Defaults to OPENAI_MODEL or 'gpt-5.4'.")
@click.option("--sample-size", type=int, default=30, show_default=True,
              help="Number of already-labeled cases to evaluate, stratified "
                   "across Easy / Medium / Hard.")
@click.option("--seed", type=int, default=7, show_default=True,
              help="Random seed for deterministic sampling.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Build packets and log what would happen, but don't call "
                   "the API or write any files.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
def evaluate_difficulty_calibration_cmd(
    catalog_path: str,
    cases_root: str | None,
    audit_dir: str,
    model: str | None,
    sample_size: int,
    seed: int,
    dry_run: bool,
    verbose: bool,
):
    """
    QA the OpenAI difficulty classifier against already-labeled cases.

    Stratified-samples rows that already have a difficulty_normalized
    value, re-runs the classifier on them (with label leakage
    prevented — the sampled rows are excluded from the calibration
    anchor pool), and compares predicted vs. existing labels.

    \b
    Never modifies the catalog. Writes:
      output/audit/difficulty_calibration_eval.csv
      output/audit/difficulty_calibration_summary.json

    Prints a warning if the exact-match rate drops below 70% or the
    average |score gap| exceeds 1.0. Warnings are non-fatal — the
    command always exits 0 unless an unrecoverable error occurs.

    Example:

    \b
      export OPENAI_API_KEY=sk-...
      python main.py evaluate-difficulty-calibration \\
          --catalog output/case_catalog.xlsx \\
          --cases-root output/cases \\
          --sample-size 30
    """
    setup_logging(verbose=verbose)
    from pipeline.enrichment.openai_difficulty_classifier import (
        evaluate_calibration,
    )

    cat_path = Path(catalog_path)
    if not cat_path.exists():
        click.echo(f"ERROR: catalog not found: {cat_path}", err=True)
        raise SystemExit(1)

    audit = Path(audit_dir)
    cases_root_p = Path(cases_root) if cases_root else None

    import pandas as pd
    if cat_path.suffix.lower() in {".xlsx", ".xlsm"}:
        df = pd.read_excel(cat_path)
    else:
        df = pd.read_csv(cat_path)

    click.echo(f"\nLoaded {len(df)} catalog rows from {cat_path}.")
    if dry_run:
        click.echo("[DRY-RUN] No API calls or file writes will happen.\n")

    summary = evaluate_calibration(
        df,
        sample_size=sample_size,
        model=model,
        audit_dir=audit,
        cases_root=cases_root_p,
        dry_run=dry_run,
        random_seed=seed,
    )

    if dry_run:
        click.echo("\nDry run complete — no evaluation performed.\n")
        return

    status = summary.get("status", "PASS")
    match = summary.get("exact_match_rate")
    gap = summary.get("avg_abs_score_gap")

    click.echo("")
    color = "green" if status == "PASS" else "yellow"
    click.echo("  Status: " + click.style(status, fg=color, bold=True))
    if match is not None:
        click.echo(f"  Exact label match : {match:.1%}  (threshold {0.70:.0%})")
    if gap is not None:
        click.echo(f"  Avg |score gap|   : {gap:.2f}  (threshold 1.00)")
    click.echo(f"  Predictions       : {summary.get('n_predictions', 0)}")
    click.echo(f"  Failures          : {summary.get('n_failures', 0)}")

    click.echo(f"\n  Eval CSV : {(audit / 'difficulty_calibration_eval.csv').resolve()}")
    click.echo(f"  Summary  : {(audit / 'difficulty_calibration_summary.json').resolve()}")

    for w in summary.get("warnings", []) or []:
        click.echo(click.style(f"  WARNING: {w}", fg="yellow"), err=True)
    click.echo()


# ── classify-industry command ─────────────────────────────────────────────────

@cli.command("classify-industry")
@click.option("--catalog", "catalog_path",
              default="output/case_catalog.xlsx", show_default=True,
              help="Path to case_catalog.csv or case_catalog.xlsx.")
@click.option("--output", "output_path", default=None,
              help="Where to write the updated catalog. Defaults to "
                   "overwriting --catalog.")
@click.option("--audit-dir", "audit_dir",
              default="output/audit", show_default=True,
              help="Directory for the LLM industry prediction / failure / review "
                   "audit files.")
@click.option("--cases-root", "cases_root", default=None,
              help="Root directory containing split case PDFs. If provided, "
                   "the classifier will read the first few pages of each case "
                   "and include an excerpt in the model prompt.")
@click.option("--model", "model", default=None,
              help="OpenAI model to use. Defaults to the OPENAI_MODEL env var "
                   "or 'gpt-5.4'.")
@click.option("--limit", type=int, default=None,
              help="Classify at most N rows (useful for smoke tests).")
@click.option("--fill-missing-only/--force", "fill_missing_only",
              default=True, show_default=True,
              help="By default only fills rows with blank industry. "
                   "--force re-rates every row, overwriting existing labels.")
@click.option("--dry-run", is_flag=True, default=False,
              help="Build packets and log what would happen, but don't call "
                   "the API or modify the catalog.")
@click.option("--verbose", is_flag=True, default=False,
              help="Enable DEBUG-level logging.")
def classify_industry_cmd(
    catalog_path: str,
    output_path: str | None,
    audit_dir: str,
    cases_root: str | None,
    model: str | None,
    limit: int | None,
    fill_missing_only: bool,
    dry_run: bool,
    verbose: bool,
):
    """
    Classify unlabeled case industries with an OpenAI model.

    For every catalog row missing an `industry` value, builds a compact
    prompt packet, calls the OpenAI Responses API with a strict JSON
    schema (output restricted to a canonical industry taxonomy), and
    writes the result back into the catalog.

    A small set of already-labeled cases — one per canonical bucket —
    is passed to the model as calibration anchors so predictions stay
    consistent with the labels already in the catalog.

    Requires the OPENAI_API_KEY environment variable (unless --dry-run).

    Example:

    \b
      export OPENAI_API_KEY=sk-...
      python main.py classify-industry \\
          --catalog output/case_catalog.xlsx \\
          --cases-root output/cases
    """
    setup_logging(verbose=verbose)
    from pipeline.enrichment.openai_industry_classifier import (
        classify_missing_industries,
    )

    cat_path = Path(catalog_path)
    if not cat_path.exists():
        click.echo(f"ERROR: catalog not found: {cat_path}", err=True)
        raise SystemExit(1)

    out_path = Path(output_path) if output_path else cat_path
    audit = Path(audit_dir)
    cases_root_p = Path(cases_root) if cases_root else None

    import pandas as pd
    if cat_path.suffix.lower() in {".xlsx", ".xlsm"}:
        df = pd.read_excel(cat_path)
    else:
        df = pd.read_csv(cat_path)

    click.echo(f"\nLoaded {len(df)} catalog rows from {cat_path}.")
    if dry_run:
        click.echo("[DRY-RUN] No API calls or file writes will happen.\n")

    updated = classify_missing_industries(
        df,
        model=model,
        limit=limit,
        force=not fill_missing_only,
        dry_run=dry_run,
        audit_dir=audit,
        cases_root=cases_root_p,
    )

    if dry_run:
        click.echo("\nDry run complete — catalog not modified.\n")
        return

    _safe_write_catalog(updated, out_path)

    click.echo(f"\nAudit outputs:  {audit.resolve()}")
    click.echo("  - llm_industry_predictions.csv")
    click.echo("  - llm_industry_failures.csv")
    click.echo("  - llm_industry_needs_review.csv")
    click.echo()


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    cli()
