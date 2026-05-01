"""
Summary reporter — prints a human-readable processing summary to stdout.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from typing import List

from models.case import CaseMetadata
from models.document import PDFDocument

logger = logging.getLogger(__name__)


def print_summary(
    documents: List[PDFDocument],
    cases: List[CaseMetadata],
    dry_run: bool = False,
) -> None:
    """Print a concise end-of-run summary."""
    print()
    print("=" * 65)
    if dry_run:
        print("  CASE-SPLITTER - DRY-RUN SUMMARY  (no files written)")
    else:
        print("  CASE-SPLITTER - PROCESSING SUMMARY")
    print("=" * 65)

    processable = [d for d in documents if d.is_processable()]
    skipped     = [d for d in documents if not d.is_processable()]
    multi_case  = [d for d in processable if d.classification == "multi_case"]
    single_case = [d for d in processable if d.classification == "single_case"]
    unknown     = [d for d in processable if d.classification == "unknown"]

    needs_review = [c for c in cases if c.needs_manual_review]

    print(f"\n  PDFs scanned          : {len(documents)}")
    print(f"  Skipped (corrupt/enc) : {len(skipped)}")
    print(f"  Multi-case detected   : {len(multi_case)}")
    print(f"  Already-single-case   : {len(single_case)}")
    print(f"  Unknown classification: {len(unknown)}")
    print(f"\n  Total cases produced  : {len(cases)}")
    print(f"  Needing manual review : {len(needs_review)}")

    # ── Breakdown by source folder ─────────────────────────────────────────
    by_folder: dict[str, list[CaseMetadata]] = defaultdict(list)
    for case in cases:
        by_folder[case.source_folder].append(case)

    if by_folder:
        print("\n  Breakdown by folder:")
        for folder in sorted(by_folder):
            folder_cases = by_folder[folder]
            flagged = sum(1 for c in folder_cases if c.needs_manual_review)
            print(
                f"    {folder:<28} {len(folder_cases):>4} cases "
                f"({flagged} need review)"
            )

    # ── Detection method breakdown ─────────────────────────────────────────
    by_method: dict[str, int] = defaultdict(int)
    for case in cases:
        by_method[case.detection_method] += 1
    if by_method:
        print("\n  Detection methods used:")
        for method, count in sorted(by_method.items(), key=lambda x: -x[1]):
            print(f"    {method:<30} {count:>4} cases")

    # ── Top review flags ───────────────────────────────────────────────────
    flag_counts: dict[str, int] = defaultdict(int)
    for case in needs_review:
        for flag in case.review_flags:
            flag_counts[flag] += 1
    if flag_counts:
        print("\n  Most common review flags:")
        for flag, count in sorted(flag_counts.items(), key=lambda x: -x[1])[:8]:
            print(f"    {flag:<36} {count:>3}×")

    print()
    print("=" * 65)
    print()
