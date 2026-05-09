"""
Orchestrator — wires every pipeline stage together.

Processing order for each source PDF:
  1. Open the PDF (already probed during scan).
  2. Classify: multi_case / single_case / unknown.
  3. Select parser based on classification + school profile.
  4. Run parser → List[CaseBoundary].
  5. For each boundary: split PDF pages + extract metadata → CaseMetadata.
  6. Collect all CaseMetadata records.

After all PDFs are processed:
  7. Run QA checks across the full manifest.
  8. Write manifest.json, manifest.csv, review_queue.csv.
  9. Print summary report.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import List, Optional

import fitz

from models.case import CaseBoundary, CaseMetadata
from models.document import PDFDocument
from pipeline.classifier import classify_document
from pipeline.metadata_extractor import build_case_metadata
from pipeline.manifest import merge_manifest_replace_sources, write_manifest, write_review_queue
from pipeline.parsers.header_pattern import HeaderPatternParser
from pipeline.parsers.profiles import get_profile, apply_config_overrides
from pipeline.parsers.profiles.columbia_2017 import Columbia2017Parser
from pipeline.parsers.profiles.columbia_2021 import Columbia2021Parser
from pipeline.parsers.profiles.darden_2017 import Darden2017Parser
from pipeline.parsers.profiles.darden_2018_2019 import Darden2018_2019Parser
from pipeline.parsers.profiles.darden_2021 import Darden2021Parser
from pipeline.parsers.profiles.wharton_2017 import Wharton2017Parser
from pipeline.parsers.profiles.kellogg_2016 import Kellogg2016Parser
from pipeline.parsers.profiles.kellogg_2023 import Kellogg2023Parser
from pipeline.parsers.profiles.kellogg_2024 import Kellogg2024Parser
from pipeline.parsers.profiles.ross_2019 import Ross2019Parser
from pipeline.parsers.profiles.ross_2022 import Ross2022Parser
from pipeline.parsers.profiles.stern_2021 import Stern2021Parser
from pipeline.parsers.profiles.stern_2025 import Stern2025Parser
from pipeline.parsers.profiles.tuck_2024 import Tuck2024Parser
from pipeline.parsers.profiles.yale_2024 import Yale2024Parser
from pipeline.parsers.profiles.yale_2025 import Yale2025Parser
from pipeline.parsers.profiles.booth_2021 import Booth2021Parser
from pipeline.parsers.profiles.booth_2026 import Booth2026Parser
from pipeline.parsers.profiles.darden_2024 import Darden2024Parser
from pipeline.parsers.profiles.fuqua_2017 import Fuqua2017Parser
from pipeline.parsers.profiles.fuqua_2026 import Fuqua2026Parser
from pipeline.parsers.profiles.harvard_2002 import Harvard2002Parser
from pipeline.parsers.profiles.mit_2011 import MIT2011Parser
from pipeline.parsers.profiles.ross_2024 import Ross2024Parser
from pipeline.parsers.single_case import SingleCaseParser
from pipeline.parsers.toc_driven import TocDrivenParser
from pipeline.reporter import print_summary
from pipeline.reviewer import run_qa
from pipeline.splitter import split_document, determine_output_path

logger = logging.getLogger(__name__)


# ── Public API ─────────────────────────────────────────────────────────────────

def run_pipeline(
    documents: List[PDFDocument],
    output_root: Path,
    config,
    dry_run: bool = False,
    merge_manifest_path: Optional[Path] = None,
) -> List[CaseMetadata]:
    """
    Process every document and return the complete list of CaseMetadata.

    When dry_run=True no files are written (PDFs, manifests, or review queue).

    When *merge_manifest_path* points to an existing manifest, the written
    manifest is the merge of that file with the cases produced in this run
    (old rows for any processed ``source_pdf`` are replaced by the new rows).
    """
    all_cases: List[CaseMetadata] = []

    for i, doc_record in enumerate(documents, start=1):
        logger.info(
            "[%d/%d] Processing: %s",
            i, len(documents), doc_record.relative_path,
        )

        if not doc_record.is_processable():
            logger.warning("  Skipping unprocessable PDF: %s", doc_record.processing_error)
            continue

        cases = _process_document(doc_record, output_root, config, dry_run)
        all_cases.extend(cases)
        doc_record.was_processed = True
        logger.info("  → %d case(s) produced", len(cases))

    # ── QA pass ───────────────────────────────────────────────────────────────
    logger.info("Running QA checks on %d cases…", len(all_cases))
    all_cases = run_qa(all_cases, documents, config)

    manifest_cases = all_cases
    if merge_manifest_path and merge_manifest_path.is_file() and documents:
        processed_sources = {d.relative_path.replace("\\", "/") for d in documents}
        manifest_cases = merge_manifest_replace_sources(
            baseline_path=merge_manifest_path,
            processed_source_pdfs=processed_sources,
            new_cases=all_cases,
        )
        logger.info(
            "Merged manifest: %d cases this run → %d total rows (baseline %s)",
            len(all_cases),
            len(manifest_cases),
            merge_manifest_path,
        )

    # ── Write outputs ─────────────────────────────────────────────────────────
    if not dry_run:
        write_manifest(manifest_cases, output_root)
        write_review_queue(manifest_cases, output_root)
    else:
        n_review = sum(1 for c in manifest_cases if c.needs_manual_review)
        logger.info(
            "[DRY-RUN] would write %d manifest entries, %d review items",
            len(manifest_cases), n_review,
        )

    # ── Summary ───────────────────────────────────────────────────────────────
    print_summary(documents, all_cases, dry_run=dry_run)

    return all_cases


# ── Per-document processing ────────────────────────────────────────────────────

def _process_document(
    doc_record: PDFDocument,
    output_root: Path,
    config,
    dry_run: bool,
) -> List[CaseMetadata]:
    """
    Full pipeline for a single source PDF.
    Returns a list of CaseMetadata (one per detected case).
    """
    try:
        doc = fitz.open(str(doc_record.path))
    except Exception as exc:
        logger.error("Cannot open %s: %s", doc_record.path, exc)
        doc_record.processing_error = str(exc)
        return []

    try:
        # Step 1: classify
        classify_document(doc_record, doc, config)
        logger.info(
            "  Classification: %s (conf=%.2f)",
            doc_record.classification, doc_record.classification_confidence,
        )
        for note in doc_record.classification_notes:
            logger.debug("    %s", note)

        # Step 2: select parser + detect boundaries
        profile = get_profile(doc_record.source_school)
        profile = apply_config_overrides(profile, config)
        boundaries = _detect_boundaries(doc, doc_record, profile, config)

        if not boundaries:
            logger.warning(
                "  No boundaries detected for %s — skipping",
                doc_record.filename,
            )
            return []

        logger.info("  Detected %d boundary/ies", len(boundaries))

    finally:
        doc.close()

    # Step 3: split + build metadata
    split_results = split_document(doc_record, boundaries, output_root, dry_run)

    cases: List[CaseMetadata] = []
    doc2 = fitz.open(str(doc_record.path))
    try:
        for boundary, out_path, success in split_results:
            if not success and not dry_run:
                logger.warning("  Skipping metadata for failed split: %s", boundary.title)
                continue
            metadata = build_case_metadata(
                doc_record, boundary, out_path, output_root, config
            )
            cases.append(metadata)
    finally:
        doc2.close()

    return cases


def _is_columbia_2017(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Columbia MCA Case Book 2017."""
    name = doc_record.filename
    return "Columbia 2017" in name or "MCA Case Book 2017" in name


def _is_columbia_2021(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Columbia Business School Case Book 2021."""
    return "Columbia 2021" in doc_record.filename


def _is_darden_2017(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Darden School of Business Case Book 2017."""
    return "Darden 2017" in doc_record.filename


def _is_darden_2018_2019(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Darden School of Business Case Book 2018–2019."""
    name = doc_record.filename
    return "Darden 2019" in name or "Darden 2018-2019" in name or "Darden 2018_2019" in name


def _is_darden_2021(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Darden School of Business Case Book 2021."""
    return "Darden 2021" in doc_record.filename


def _is_wharton_2017(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Wharton Casebook 2017."""
    name = doc_record.filename
    return "Wharton 2017" in name or "Wharton Casebook 2017" in name


def _is_kellogg_2016(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Kellogg School of Management Case Book 2016."""
    return "Kellogg 2016" in doc_record.filename


def _is_kellogg_2023(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Kellogg School of Management Case Book 2023."""
    return "Kellogg 2023" in doc_record.filename


def _is_kellogg_2024(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Kellogg School of Management Case Book 2024."""
    return "Kellogg 2024" in doc_record.filename


def _is_ross_2019(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Ross School of Business Case Book 2019."""
    return "Ross 2019" in doc_record.filename


def _is_ross_2022(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Ross School of Business Case Book 2022."""
    return "Ross 2022" in doc_record.filename


def _is_stern_2021(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the NYU Stern Case Book 2021."""
    return "Stern 2021" in doc_record.filename


def _is_stern_2025(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the NYU Stern Case Book 2025."""
    return "Stern 2025" in doc_record.filename


def _is_tuck_2024(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Tuck Case Book 2024."""
    return "Tuck 2024" in doc_record.filename


def _is_yale_2024(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Yale SOM Case Book 2024."""
    return "Yale 2024" in doc_record.filename


def _is_yale_2025(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Yale SOM Case Book 2025."""
    return "Yale 2025" in doc_record.filename


def _is_booth_2021(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Booth School of Business Case Book 2021."""
    return "Booth 2021" in doc_record.filename


def _is_booth_2026(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Booth School of Business Case Book 2026."""
    return "Booth 2026" in doc_record.filename


def _is_darden_2024(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Darden Case Book 2024."""
    return "Darden 2024" in doc_record.filename or "Darden 2023-24 Casebook" in doc_record.filename


def _is_fuqua_2017(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Duke Fuqua Case Book 2017."""
    name = doc_record.filename
    return "Fuqua 2017" in name and "Fuqua 2026" not in name


def _is_fuqua_2026(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Duke Fuqua Case Book 2026."""
    return "Fuqua 2026" in doc_record.filename


def _is_harvard_2002(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Harvard Business School Case Book 2002."""
    return "Harvard 2002" in doc_record.filename


def _is_mit_2011(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the MIT Sloan Case Book 2011."""
    return "MIT 2011" in doc_record.filename


def _is_ross_2024(doc_record: PDFDocument) -> bool:
    """True when the source PDF is the Ross School of Business Case Book 2024."""
    return "Ross 2024" in doc_record.filename


def _detect_boundaries(
    doc: fitz.Document,
    doc_record: PDFDocument,
    profile,
    config,
) -> List[CaseBoundary]:
    """
    Choose and run the appropriate parser based on classification and profile.

    Parser priority:
      0. Manual-override parsers for known gold-standard documents.
      1. Profile.preferred_parser (when not "auto")
      2. SingleCaseParser — when classification is "single_case" or profile says always_single_case
      3. TocDrivenParser — when can_handle() returns True
      4. HeaderPatternParser — always available as final fallback
    """
    # ── Manual overrides — bypass all heuristics for known gold-standard files ─
    if _is_columbia_2017(doc_record):
        return Columbia2017Parser().parse(doc, config)
    if _is_columbia_2021(doc_record):
        return Columbia2021Parser().parse(doc, config)
    if _is_darden_2017(doc_record):
        return Darden2017Parser().parse(doc, config)
    if _is_darden_2018_2019(doc_record):
        return Darden2018_2019Parser().parse(doc, config)
    if _is_darden_2021(doc_record):
        return Darden2021Parser().parse(doc, config)
    if _is_wharton_2017(doc_record):
        return Wharton2017Parser().parse(doc, config)
    if _is_kellogg_2016(doc_record):
        return Kellogg2016Parser().parse(doc, config)
    if _is_kellogg_2023(doc_record):
        return Kellogg2023Parser().parse(doc, config)
    if _is_kellogg_2024(doc_record):
        return Kellogg2024Parser().parse(doc, config)
    if _is_ross_2019(doc_record):
        return Ross2019Parser().parse(doc, config)
    if _is_ross_2022(doc_record):
        return Ross2022Parser().parse(doc, config)
    if _is_stern_2021(doc_record):
        return Stern2021Parser().parse(doc, config)
    if _is_stern_2025(doc_record):
        return Stern2025Parser().parse(doc, config)
    if _is_tuck_2024(doc_record):
        return Tuck2024Parser().parse(doc, config)
    if _is_yale_2024(doc_record):
        return Yale2024Parser().parse(doc, config)
    if _is_yale_2025(doc_record):
        return Yale2025Parser().parse(doc, config)
    if _is_booth_2021(doc_record):
        return Booth2021Parser().parse(doc, config)
    if _is_booth_2026(doc_record):
        return Booth2026Parser().parse(doc, config)
    if _is_darden_2024(doc_record):
        return Darden2024Parser().parse(doc, config)
    if _is_fuqua_2017(doc_record):
        return Fuqua2017Parser().parse(doc, config)
    if _is_fuqua_2026(doc_record):
        return Fuqua2026Parser().parse(doc, config)
    if _is_harvard_2002(doc_record):
        return Harvard2002Parser().parse(doc, config)
    if _is_mit_2011(doc_record):
        return MIT2011Parser().parse(doc, config)
    if _is_ross_2024(doc_record):
        return Ross2024Parser().parse(doc, config)

    classification = doc_record.classification
    preferred = profile.preferred_parser

    # ── Forced single-case ────────────────────────────────────────────────────
    if profile.always_single_case or (
        classification == "single_case" and preferred != "toc_driven"
    ):
        logger.debug("  Using SingleCaseParser (forced)")
        return SingleCaseParser().parse(doc, config)

    # ── Explicit preferred parser ─────────────────────────────────────────────
    if preferred == "single_case":
        return SingleCaseParser().parse(doc, config)
    if preferred == "toc_driven":
        parser = TocDrivenParser()
        if parser.can_handle(doc, config):
            results = parser.parse(doc, config)
            if results:
                return results
            logger.info("  TocDrivenParser returned no results; trying HeaderPatternParser")
        else:
            logger.info("  TocDrivenParser cannot handle this doc; trying HeaderPatternParser")
        return HeaderPatternParser().parse(doc, config)
    if preferred == "header_pattern":
        return HeaderPatternParser().parse(doc, config)

    # ── Auto mode ─────────────────────────────────────────────────────────────
    # Try TOC first; fall back to header pattern; fall back to single case
    toc_parser = TocDrivenParser()
    if toc_parser.can_handle(doc, config):
        results = toc_parser.parse(doc, config)
        if results:
            logger.debug("  Auto: TocDrivenParser succeeded (%d boundaries)", len(results))
            return results
        logger.info("  Auto: TocDrivenParser found no entries; falling back")

    hp_results = HeaderPatternParser().parse(doc, config)
    if hp_results:
        logger.debug("  Auto: HeaderPatternParser found %d boundaries", len(hp_results))
        return hp_results

    # Last resort: treat as single case
    logger.info("  Auto: no boundaries found — treating as single case")
    return SingleCaseParser().parse(doc, config)
