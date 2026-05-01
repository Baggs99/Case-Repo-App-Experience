"""
Metadata extractor — enriches CaseBoundary data into full CaseMetadata.

After splitting, this module reads the first few pages of each case and
tries to extract:
  - case title (refined from the boundary title if possible)
  - industry, case type, difficulty, interviewer style
  - prompt excerpt

All extraction is conservative: fields are left None rather than guessing.
Low-confidence extractions are noted in confidence_notes.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Optional

import fitz

from models.case import CaseBoundary, CaseMetadata
from models.document import PDFDocument
from utils.pdf_utils import extract_page_text

logger = logging.getLogger(__name__)


# ── Label→value pattern ────────────────────────────────────────────────────────
# Matches lines like "Industry: Healthcare" or "Type - Profitability"
_LABEL_RE = re.compile(
    r"(?P<label>"
    r"industry|sector|case type|type|difficulty|overall difficulty|"
    r"quant difficulty|qual difficulty|quantitative|qualitative|"
    r"interviewer style|style|level|case number|number"
    r")\s*[:\-–]\s*(?P<value>[^\n]{1,80})",
    re.IGNORECASE,
)

# Prompt / question section markers
_PROMPT_MARKERS = re.compile(
    r"(prompt|question|background|case background)\s*[:\n]",
    re.IGNORECASE,
)

# Interviewer style signals
_INTERVIEWEE_LED = re.compile(r"interviewee[\s\-]led", re.IGNORECASE)
_INTERVIEWER_LED = re.compile(r"interviewer[\s\-]led", re.IGNORECASE)

# ── Industry keyword maps ──────────────────────────────────────────────────────
_INDUSTRY_KEYWORDS: dict[str, list[str]] = {
    "Healthcare": [
        "hospital", "pharma", "pharmaceutical", "drug", "medical",
        "biotech", "health", "clinic", "patient", "insurance",
    ],
    "Technology": [
        "software", "saas", "platform", "app", "digital", "cloud",
        "tech", "semiconductor", "data", "ai ", "machine learning",
    ],
    "Retail / CPG": [
        "retail", "consumer", "brand", "store", "cpg", "grocery",
        "e-commerce", "ecommerce", "fashion", "apparel",
    ],
    "Energy": [
        "oil", "gas", "energy", "renewable", "utility", "power",
        "solar", "wind", "nuclear",
    ],
    "Financial Services": [
        "bank", "financial", "insurance", "investment", "hedge fund",
        "private equity", "asset management", "fintech",
    ],
    "Airlines / Transportation": [
        "airline", "aviation", "airport", "rail", "logistics",
        "shipping", "fleet",
    ],
    "Media / Entertainment": [
        "media", "entertainment", "streaming", "content", "studio",
        "gaming", "music", "publishing",
    ],
    "Industrials": [
        "manufacturing", "industrial", "chemical", "mining",
        "construction", "aerospace", "defence", "defense",
    ],
}

# ── Case type keyword maps ────────────────────────────────────────────────────
_CASE_TYPE_KEYWORDS: dict[str, list[str]] = {
    "Profitability": [
        "profitab", "profit declin", "revenue declin", "margin",
        "cost reduction", "operating loss",
    ],
    "Market Entry": [
        "market entry", "enter the market", "new market", "expand into",
        "launch", "geographic expansion",
    ],
    "M&A": [
        "acqui", "merger", "m&a", "due diligence", "valuation", "buyout",
    ],
    "Growth": [
        "growth", "scale", "increase revenue", "expand", "new product",
    ],
    "Pricing": [
        "pricing", "price increase", "willingness to pay", "premium",
        "discount",
    ],
    "Operations": [
        "operations", "efficiency", "supply chain", "process improvement",
        "capacity", "throughput",
    ],
    "Investment": [
        "invest", "capital allocation", "npv", "irr", "return on invest",
    ],
}


# ── Public interface ───────────────────────────────────────────────────────────

def build_case_metadata(
    doc_record: PDFDocument,
    boundary: CaseBoundary,
    output_path: Path,
    output_root: Path,
    config,
) -> CaseMetadata:
    """
    Combine boundary data with extracted content metadata into a CaseMetadata.

    Opens the source PDF to read the first few pages of the case.
    All extracted fields are optional: if extraction fails the field is None.
    """
    max_pages = config.processing.max_metadata_extract_pages
    h_start, h_end = boundary.to_human_pages()

    # Build the relative output path string (forward slashes)
    try:
        rel_out = output_path.relative_to(output_root).as_posix()
    except ValueError:
        rel_out = output_path.as_posix()

    # ── Read pages from the source PDF ───────────────────────────────────────
    pages_text = _read_case_pages(doc_record.path, boundary, max_pages)
    combined_text = "\n".join(pages_text)

    # ── Extract fields ────────────────────────────────────────────────────────
    labels = _extract_labeled_fields(combined_text)

    industry = (
        labels.get("industry") or labels.get("sector")
        or _infer_industry(combined_text)
    )
    case_type = (
        labels.get("case type") or labels.get("type")
        or _infer_case_type(combined_text)
    )
    difficulty_overall = labels.get("difficulty") or labels.get("overall difficulty") or labels.get("level")
    difficulty_quant = labels.get("quant difficulty") or labels.get("quantitative")
    difficulty_qual = labels.get("qual difficulty") or labels.get("qualitative")
    interviewer_style = (
        labels.get("interviewer style") or labels.get("style")
        or _infer_interviewer_style(combined_text)
    )
    prompt_excerpt = _extract_prompt_excerpt(combined_text)

    # ── Confidence and review flags ───────────────────────────────────────────
    review_flags = list(boundary.review_flags)
    confidence_notes = list(boundary.confidence_notes)

    if not industry:
        confidence_notes.append("industry not extracted")
    if not case_type:
        confidence_notes.append("case_type not extracted")

    return CaseMetadata(
        id=CaseMetadata.new_id(),
        case_title=boundary.title,
        source_pdf=doc_record.relative_path,
        source_folder=doc_record.source_folder,
        source_school=doc_record.source_school,
        source_year=doc_record.source_year,
        page_start=h_start,
        page_end=h_end,
        page_count=boundary.page_count,
        output_pdf_path=rel_out,
        extraction_confidence=boundary.confidence,
        detection_method=boundary.detection_method,
        needs_manual_review=boundary.needs_manual_review,
        industry=_clean(industry),
        case_type=_clean(case_type),
        difficulty_overall=_clean(difficulty_overall),
        difficulty_quant=_clean(difficulty_quant),
        difficulty_qual=_clean(difficulty_qual),
        interviewer_style=_clean(interviewer_style),
        prompt_excerpt=prompt_excerpt,
        matched_toc_title=boundary.matched_toc_title,
        matched_start_page_text=boundary.matched_start_page_text,
        matched_patterns=list(boundary.matched_patterns),
        confidence_notes=confidence_notes,
        review_flags=review_flags,
    )


# ── Internal helpers ───────────────────────────────────────────────────────────

def _read_case_pages(pdf_path: Path, boundary: CaseBoundary, max_pages: int) -> list[str]:
    """
    Open the source PDF and return text for the first max_pages of this case.
    Returns empty list on error.
    """
    texts: list[str] = []
    try:
        doc = fitz.open(str(pdf_path))
        try:
            end = min(boundary.page_start + max_pages, boundary.page_end + 1)
            for idx in range(boundary.page_start, end):
                texts.append(extract_page_text(doc, idx))
        finally:
            doc.close()
    except Exception as exc:
        logger.debug("Could not read pages for metadata extraction: %s", exc)
    return texts


def _extract_labeled_fields(text: str) -> dict[str, str]:
    """
    Extract key:value pairs from lines like "Industry: Healthcare".

    Returns a dict with lowercase keys.
    """
    result: dict[str, str] = {}
    for match in _LABEL_RE.finditer(text):
        label = match.group("label").lower().strip()
        value = match.group("value").strip().rstrip(".,;")
        if value and label not in result:
            result[label] = value
    return result


def _infer_industry(text: str) -> Optional[str]:
    """
    Return the best-matching industry based on keyword counts.
    Returns None when no industry has a clear signal.
    """
    text_lower = text.lower()
    scores: dict[str, int] = {}
    for industry, keywords in _INDUSTRY_KEYWORDS.items():
        score = sum(1 for kw in keywords if kw in text_lower)
        if score > 0:
            scores[industry] = score
    if not scores:
        return None
    best = max(scores, key=lambda k: scores[k])
    # Require at least 2 keyword hits to avoid false positives
    return best if scores[best] >= 2 else None


def _infer_case_type(text: str) -> Optional[str]:
    """
    Return the best-matching case type based on keyword counts.
    Returns None when confidence is too low.
    """
    text_lower = text.lower()
    scores: dict[str, int] = {}
    for ctype, keywords in _CASE_TYPE_KEYWORDS.items():
        score = sum(1 for kw in keywords if kw in text_lower)
        if score > 0:
            scores[ctype] = score
    if not scores:
        return None
    best = max(scores, key=lambda k: scores[k])
    return best if scores[best] >= 1 else None


def _infer_interviewer_style(text: str) -> Optional[str]:
    """Return 'Interviewee-led', 'Interviewer-led', or None."""
    if _INTERVIEWEE_LED.search(text):
        return "Interviewee-led"
    if _INTERVIEWER_LED.search(text):
        return "Interviewer-led"
    return None


def _extract_prompt_excerpt(text: str, max_chars: int = 300) -> Optional[str]:
    """
    Find the Prompt / Question / Background section and return the first
    max_chars characters of its content.
    """
    match = _PROMPT_MARKERS.search(text)
    if not match:
        return None
    after = text[match.end():].strip()
    if not after:
        return None
    return after[:max_chars].strip()


def _clean(value: Optional[str]) -> Optional[str]:
    """Strip whitespace and return None for empty strings."""
    if not value:
        return None
    cleaned = value.strip()
    return cleaned if cleaned else None
