"""
Abstract base class for all casebook parsers.

Each parser implementation must override:
  can_handle(doc, config) → bool
  parse(doc, config)      → List[CaseBoundary]

The pipeline tries parsers in priority order and uses the first one
that can_handle() returns True for and that returns at least one boundary.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import List

import fitz

from models.case import CaseBoundary


class BaseCasebookParser(ABC):
    """
    Abstract base for case-boundary detectors.

    Subclass this to add a new parsing strategy.  Keep each strategy in its
    own module so the logic stays readable and independently testable.
    """

    #: Short name used in detection_method metadata field
    name: str = "base"

    @abstractmethod
    def parse(self, doc: fitz.Document, config) -> List[CaseBoundary]:
        """
        Detect case boundaries in *doc* and return them.

        Implementations must:
        - Return an empty list (not raise) when no boundaries are found.
        - Populate the diagnostic fields of every CaseBoundary they create
          (matched_toc_title, matched_start_page_text, matched_patterns,
           confidence_notes) so every splitting decision is traceable.
        - Use 0-indexed page numbers (fitz convention).
        - Not write any files; the splitter handles that.

        Args:
            doc:    Open fitz.Document.  Do not close it inside parse().
            config: Loaded config namespace (from config.yaml).

        Returns:
            List of CaseBoundary in ascending page order.
        """

    def can_handle(self, doc: fitz.Document, config) -> bool:  # noqa: ARG002
        """
        Return True when this parser is applicable to *doc*.

        The default implementation always returns True so subclasses only
        need to override when they have a specific pre-condition check.
        """
        return True

    # ── Shared utilities available to all subclasses ──────────────────────────

    @staticmethod
    def _clamp_boundaries(
        boundaries: List[CaseBoundary],
        total_pages: int,
    ) -> List[CaseBoundary]:
        """
        Ensure all page indices are within [0, total_pages-1] and that
        page_start ≤ page_end.  Invalid entries are removed.
        """
        valid = []
        for b in boundaries:
            clamped = b.clamp(total_pages)
            if clamped.page_start <= clamped.page_end:
                valid.append(clamped)
        return valid

    @staticmethod
    def _sort_boundaries(boundaries: List[CaseBoundary]) -> List[CaseBoundary]:
        """Return boundaries sorted by page_start ascending."""
        return sorted(boundaries, key=lambda b: b.page_start)
