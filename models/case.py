"""
Data models for case boundaries and per-case metadata.

CaseBoundary  — a detected boundary inside a source PDF (internal, 0-indexed pages).
CaseMetadata  — the full metadata record written to manifest / CSV (1-indexed pages).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from typing import List, Optional


# ── CaseBoundary ──────────────────────────────────────────────────────────────

@dataclass
class CaseBoundary:
    """
    A detected case boundary inside a source PDF.

    Page numbers are 0-indexed (PyMuPDF / fitz convention) for all internal
    processing.  Human-readable (1-indexed) versions are produced on demand
    via `to_human_pages()`.

    Diagnostic fields (matched_toc_title, matched_start_page_text, …) are
    populated by the parser so that every splitting decision is fully
    traceable back to the evidence that produced it.
    """

    title: str
    page_start: int          # 0-indexed, inclusive
    page_end: int            # 0-indexed, inclusive
    confidence: float        # 0.0 – 1.0

    # How was this boundary found?
    # "toc" | "header_pattern" | "already_single_case" | "filename"
    detection_method: str

    # ── Diagnostic / traceability fields ─────────────────────────────────────
    matched_toc_title: Optional[str] = None
    # First ~200 chars of the start page text, for human review
    matched_start_page_text: Optional[str] = None
    # Human-readable list of heuristics that fired
    matched_patterns: List[str] = field(default_factory=list)
    # Explanation of confidence score adjustments
    confidence_notes: List[str] = field(default_factory=list)

    # ── QA flags ─────────────────────────────────────────────────────────────
    needs_manual_review: bool = False
    # Short tokens like "too_few_pages", "title_mismatch_on_start_page", …
    review_flags: List[str] = field(default_factory=list)

    # Optional filesystem slug for output PDF (when slugify(title) is not desired).
    file_slug: Optional[str] = None

    # ── Derived ──────────────────────────────────────────────────────────────
    @property
    def page_count(self) -> int:
        return self.page_end - self.page_start + 1

    def to_human_pages(self) -> tuple[int, int]:
        """Return (start, end) as 1-indexed page numbers."""
        return (self.page_start + 1, self.page_end + 1)

    def clamp(self, total_pages: int) -> "CaseBoundary":
        """Return a copy with page_start / page_end clamped to [0, total_pages-1]."""
        return CaseBoundary(
            title=self.title,
            page_start=max(0, min(self.page_start, total_pages - 1)),
            page_end=max(0, min(self.page_end, total_pages - 1)),
            confidence=self.confidence,
            detection_method=self.detection_method,
            matched_toc_title=self.matched_toc_title,
            matched_start_page_text=self.matched_start_page_text,
            matched_patterns=list(self.matched_patterns),
            confidence_notes=list(self.confidence_notes),
            needs_manual_review=self.needs_manual_review,
            review_flags=list(self.review_flags),
            file_slug=self.file_slug,
        )


# ── CaseMetadata ──────────────────────────────────────────────────────────────

@dataclass
class CaseMetadata:
    """
    Complete metadata record for a single extracted case.

    Page numbers here are 1-indexed (human-readable) for all output
    files (manifest.json, manifest.csv, review_queue.csv).
    """

    # ── Core identification ───────────────────────────────────────────────────
    id: str                     # UUID4
    case_title: str
    source_pdf: str             # Path relative to the input root
    source_folder: str          # E.g. "Booth", "Yale"
    source_school: str          # Normalised slug, e.g. "booth"
    source_year: Optional[int]  # Extracted from filename when possible

    # ── Page provenance (1-indexed) ───────────────────────────────────────────
    page_start: int
    page_end: int
    page_count: int

    # ── Output ───────────────────────────────────────────────────────────────
    output_pdf_path: str        # Path relative to the output root

    # ── Quality indicators ────────────────────────────────────────────────────
    extraction_confidence: float
    detection_method: str
    needs_manual_review: bool

    # ── Optional content fields (null when not extractable with confidence) ───
    industry: Optional[str] = None
    case_type: Optional[str] = None
    difficulty_overall: Optional[str] = None
    difficulty_quant: Optional[str] = None
    difficulty_qual: Optional[str] = None
    interviewer_style: Optional[str] = None
    prompt_excerpt: Optional[str] = None

    # ── Diagnostic / traceability fields ─────────────────────────────────────
    matched_toc_title: Optional[str] = None
    matched_start_page_text: Optional[str] = None
    matched_patterns: List[str] = field(default_factory=list)
    confidence_notes: List[str] = field(default_factory=list)
    review_flags: List[str] = field(default_factory=list)

    # ── Factories ─────────────────────────────────────────────────────────────

    @classmethod
    def new_id(cls) -> str:
        return str(uuid.uuid4())

    @classmethod
    def from_manifest_dict(cls, d: dict) -> CaseMetadata:
        """Rehydrate from a manifest.json entry (lists, not semicolon-joined)."""
        return cls(
            id=d["id"],
            case_title=d["case_title"],
            source_pdf=d["source_pdf"],
            source_folder=d["source_folder"],
            source_school=d["source_school"],
            source_year=d.get("source_year"),
            page_start=int(d["page_start"]),
            page_end=int(d["page_end"]),
            page_count=int(d["page_count"]),
            output_pdf_path=d["output_pdf_path"],
            extraction_confidence=float(d["extraction_confidence"]),
            detection_method=d["detection_method"],
            needs_manual_review=bool(d["needs_manual_review"]),
            industry=d.get("industry"),
            case_type=d.get("case_type"),
            difficulty_overall=d.get("difficulty_overall"),
            difficulty_quant=d.get("difficulty_quant"),
            difficulty_qual=d.get("difficulty_qual"),
            interviewer_style=d.get("interviewer_style"),
            prompt_excerpt=d.get("prompt_excerpt"),
            matched_toc_title=d.get("matched_toc_title"),
            matched_start_page_text=d.get("matched_start_page_text"),
            matched_patterns=list(d.get("matched_patterns") or []),
            confidence_notes=list(d.get("confidence_notes") or []),
            review_flags=list(d.get("review_flags") or []),
        )

    # ── Serialisation ─────────────────────────────────────────────────────────

    def to_dict(self) -> dict:
        """Full dict for JSON manifest."""
        return {
            "id": self.id,
            "case_title": self.case_title,
            "source_pdf": self.source_pdf,
            "source_folder": self.source_folder,
            "source_school": self.source_school,
            "source_year": self.source_year,
            "page_start": self.page_start,
            "page_end": self.page_end,
            "page_count": self.page_count,
            "output_pdf_path": self.output_pdf_path,
            "extraction_confidence": round(self.extraction_confidence, 4),
            "detection_method": self.detection_method,
            "needs_manual_review": self.needs_manual_review,
            "industry": self.industry,
            "case_type": self.case_type,
            "difficulty_overall": self.difficulty_overall,
            "difficulty_quant": self.difficulty_quant,
            "difficulty_qual": self.difficulty_qual,
            "interviewer_style": self.interviewer_style,
            "prompt_excerpt": self.prompt_excerpt,
            "matched_toc_title": self.matched_toc_title,
            "matched_start_page_text": self.matched_start_page_text,
            "matched_patterns": self.matched_patterns,
            "confidence_notes": self.confidence_notes,
            "review_flags": self.review_flags,
        }

    def to_csv_row(self) -> dict:
        """Flat dict for CSV manifest (lists are joined as semicolon strings)."""
        d = self.to_dict()
        d["matched_patterns"] = "; ".join(self.matched_patterns)
        d["confidence_notes"] = "; ".join(self.confidence_notes)
        d["review_flags"] = "; ".join(self.review_flags)
        return d

    # CSV column order (used by manifest writer)
    CSV_FIELDS = [
        "id", "case_title", "source_pdf", "source_folder", "source_school",
        "source_year", "page_start", "page_end", "page_count",
        "output_pdf_path", "extraction_confidence", "detection_method",
        "needs_manual_review", "industry", "case_type",
        "difficulty_overall", "difficulty_quant", "difficulty_qual",
        "interviewer_style", "prompt_excerpt",
        "matched_toc_title", "matched_start_page_text",
        "matched_patterns", "confidence_notes", "review_flags",
    ]
