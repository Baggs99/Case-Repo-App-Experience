"""
PDF splitter — writes individual case PDFs to the output directory.

Each split case is saved to:
  {output_root}/cases/{source_folder}/{source_pdf_stem}/{case_slug}.pdf

The splitter is a pure I/O layer: it takes already-detected CaseBoundary
objects and writes pages; it does not do any analysis.

Dry-run mode logs every action without writing any files.
"""

from __future__ import annotations

import logging
from pathlib import Path

import fitz

from models.case import CaseBoundary
from models.document import PDFDocument
from utils.pdf_utils import save_pdf_pages
from utils.slug import make_case_slug, make_safe_dirname

logger = logging.getLogger(__name__)


def determine_output_path(
    doc_record: PDFDocument,
    boundary: CaseBoundary,
    output_root: Path,
) -> Path:
    """
    Compute the output PDF path for a single case boundary.

    Layout:
      {output_root}/cases/{source_folder}/{pdf_stem}/{case_slug}.pdf

    All path components are sanitised to be filesystem-safe.
    """
    folder = make_safe_dirname(doc_record.source_folder)
    stem   = make_safe_dirname(doc_record.stem)
    slug   = make_case_slug(boundary.title)
    return output_root / "cases" / folder / stem / f"{slug}.pdf"


def split_case(
    source_doc: fitz.Document,
    boundary: CaseBoundary,
    output_path: Path,
    dry_run: bool = False,
) -> bool:
    """
    Write the pages described by *boundary* to *output_path*.

    Returns True on success, False on error.
    Skips writing when dry_run=True.
    """
    page_start = boundary.page_start
    page_end   = boundary.page_end
    h_start, h_end = boundary.to_human_pages()

    if dry_run:
        logger.info(
            "[DRY-RUN] would write pages %d–%d → %s",
            h_start, h_end, output_path,
        )
        return True

    try:
        save_pdf_pages(source_doc, page_start, page_end, output_path)
        logger.info("Saved pages %d–%d → %s", h_start, h_end, output_path.name)
        return True
    except Exception as exc:
        logger.error("Failed to write %s: %s", output_path, exc)
        return False


def split_document(
    doc_record: PDFDocument,
    boundaries: list[CaseBoundary],
    output_root: Path,
    dry_run: bool = False,
) -> list[tuple[CaseBoundary, Path, bool]]:
    """
    Split all cases from a single source PDF.

    Opens the source PDF once and writes all case PDFs in one pass.

    Returns a list of (boundary, output_path, success) tuples.
    """
    results: list[tuple[CaseBoundary, Path, bool]] = []

    if not boundaries:
        logger.debug("No boundaries for %s; nothing to split", doc_record.filename)
        return results

    doc = fitz.open(str(doc_record.path))
    try:
        for boundary in boundaries:
            out_path = determine_output_path(doc_record, boundary, output_root)
            success = split_case(doc, boundary, out_path, dry_run=dry_run)
            results.append((boundary, out_path, success))
    finally:
        doc.close()

    return results
