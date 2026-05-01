"""
Recursively scan an input directory for PDF files and produce
PDFDocument records ready for classification.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import List, Optional

from models.document import PDFDocument
from utils.pdf_utils import open_pdf_safely

logger = logging.getLogger(__name__)

_YEAR_RE = re.compile(r"(20\d{2})")


# ── Helpers ───────────────────────────────────────────────────────────────────

def infer_school_from_folder(folder_name: str, known_schools: dict) -> str:
    """
    Map a folder name to a normalised school slug.

    known_schools maps display names ("Booth") → slugs ("booth").
    Matching is case-insensitive and substring-based so that a folder
    named "Booth Cases" still maps to "booth".
    Returns the lower-cased folder name when no match is found.
    """
    folder_lower = folder_name.lower()
    for display_name, slug in known_schools.items():
        if display_name.lower() in folder_lower:
            return slug
    return folder_lower.replace(" ", "_")


def infer_year_from_filename(filename: str) -> Optional[int]:
    """
    Try to extract a four-digit year (20xx) from a filename stem.

    Returns None when no year is found.
    """
    match = _YEAR_RE.search(filename)
    return int(match.group(1)) if match else None


# ── Main scanner ──────────────────────────────────────────────────────────────

def scan_directory(
    root_path: Path,
    config,
    exclude_dirs: list[Path] | None = None,
) -> List[PDFDocument]:
    """
    Recursively walk *root_path* and return a PDFDocument for every PDF.

    Args:
        root_path:    Directory to scan.
        config:       Loaded pipeline config.
        exclude_dirs: Absolute paths of directories to skip (e.g. the output
                      directory when it lives inside the input directory).

    Ordering: sorted alphabetically by path for reproducibility.
    """
    known_schools: dict = vars(config.known_schools) if hasattr(config, "known_schools") else {}
    exclude_set: set[Path] = set(exclude_dirs or [])

    if not root_path.exists():
        raise FileNotFoundError(f"Input directory not found: {root_path}")

    all_pdfs = sorted(root_path.rglob("*.pdf"))

    # Filter out any path that lives inside an excluded directory.
    # Resolve both sides to absolute paths for a reliable comparison.
    def _is_excluded(p: Path) -> bool:
        resolved = p.resolve()
        return any(
            resolved == exc or exc in resolved.parents
            for exc in exclude_set
        )

    pdf_paths = [p for p in all_pdfs if not _is_excluded(p)]

    if len(pdf_paths) < len(all_pdfs):
        logger.info(
            "Excluded %d PDF(s) inside excluded directories",
            len(all_pdfs) - len(pdf_paths),
        )
    logger.info("Found %d PDF file(s) under %s", len(pdf_paths), root_path)

    documents: List[PDFDocument] = []

    for pdf_path in pdf_paths:
        rel = _relative_path(pdf_path, root_path)
        parts = Path(rel).parts
        source_folder = parts[0] if len(parts) > 1 else root_path.name
        source_school = infer_school_from_folder(source_folder, known_schools)
        source_year = infer_year_from_filename(pdf_path.stem)

        doc_fitz, error = open_pdf_safely(pdf_path)

        if error:
            logger.warning("Cannot open %s — %s", rel, error)
            record = PDFDocument(
                path=pdf_path,
                relative_path=rel,
                source_folder=source_folder,
                source_school=source_school,
                source_year=source_year,
                page_count=0,
                is_encrypted="password" in error.lower(),
                is_corrupted=True,
                processing_error=error,
            )
        else:
            page_count = len(doc_fitz)
            doc_fitz.close()
            record = PDFDocument(
                path=pdf_path,
                relative_path=rel,
                source_folder=source_folder,
                source_school=source_school,
                source_year=source_year,
                page_count=page_count,
            )

        documents.append(record)
        logger.debug("Scanned: %s", record.summary())

    logger.info(
        "Scan complete: %d processable, %d skipped (encrypted/corrupted)",
        sum(1 for d in documents if d.is_processable()),
        sum(1 for d in documents if not d.is_processable()),
    )
    return documents


# ── Internal ──────────────────────────────────────────────────────────────────

def _relative_path(full_path: Path, root: Path) -> str:
    """Return a forward-slash relative path string."""
    try:
        return full_path.relative_to(root).as_posix()
    except ValueError:
        return full_path.as_posix()
