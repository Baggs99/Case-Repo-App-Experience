"""
Data model for a source PDF document discovered during scanning.

PDFDocument holds everything the pipeline knows about a source file
before any case splitting happens.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass
class PDFDocument:
    """
    Represents a single PDF file found on disk during the scan phase.

    Attributes set at scan time:
        path, relative_path, source_folder, source_school,
        source_year, page_count, is_encrypted, is_corrupted

    Attributes set at classification time:
        classification, classification_confidence, classification_notes

    Attributes set at processing time:
        was_processed, processing_error
    """

    # ── Identity ──────────────────────────────────────────────────────────────
    path: Path                    # Absolute path on disk
    relative_path: str            # Relative to the input root (for display / output keys)
    source_folder: str            # First-level subfolder name, e.g. "Booth"
    source_school: str            # Normalised slug, e.g. "booth"
    source_year: Optional[int]    # Parsed from filename, e.g. 2024

    # ── Basic PDF properties ──────────────────────────────────────────────────
    page_count: int = 0
    is_encrypted: bool = False
    is_corrupted: bool = False

    # ── Classification results ────────────────────────────────────────────────
    # "multi_case" | "single_case" | "unknown"
    classification: str = "unknown"
    classification_confidence: float = 0.0
    classification_notes: List[str] = field(default_factory=list)

    # ── Processing state ──────────────────────────────────────────────────────
    was_processed: bool = False
    processing_error: Optional[str] = None

    # ── Helpers ───────────────────────────────────────────────────────────────

    @property
    def stem(self) -> str:
        """Filename without extension, e.g. 'Ross 2024'."""
        return self.path.stem

    @property
    def filename(self) -> str:
        """Filename with extension, e.g. 'Ross 2024.pdf'."""
        return self.path.name

    def is_processable(self) -> bool:
        """Return True if the PDF can actually be opened and split."""
        return not self.is_encrypted and not self.is_corrupted and self.page_count > 0

    def summary(self) -> str:
        """One-line human-readable summary for logging."""
        status = []
        if self.is_encrypted:
            status.append("encrypted")
        if self.is_corrupted:
            status.append("corrupted")
        if not status:
            status.append(self.classification)
        return (
            f"{self.relative_path} "
            f"[{self.page_count}p | {' | '.join(status)} "
            f"| conf={self.classification_confidence:.2f}]"
        )
