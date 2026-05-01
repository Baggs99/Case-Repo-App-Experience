"""
Manifest writer — produces manifest.json, manifest.csv, and review_queue.csv.
"""

from __future__ import annotations

import csv
import json
import logging
from pathlib import Path
from typing import List

from models.case import CaseMetadata

logger = logging.getLogger(__name__)


def write_manifest(cases: List[CaseMetadata], output_root: Path) -> None:
    """Write manifest.json and manifest.csv into output_root."""
    output_root.mkdir(parents=True, exist_ok=True)

    _write_json(cases, output_root / "manifest.json")
    _write_csv(cases, output_root / "manifest.csv", CaseMetadata.CSV_FIELDS)

    logger.info(
        "Manifest written: %d cases → %s",
        len(cases), output_root,
    )


def write_review_queue(cases: List[CaseMetadata], output_root: Path) -> None:
    """Write review_queue.csv containing only cases that need manual review."""
    flagged = [c for c in cases if c.needs_manual_review]

    if not flagged:
        logger.info("No cases flagged for manual review")
        return

    review_path = output_root / "review_queue.csv"
    _write_csv(flagged, review_path, CaseMetadata.CSV_FIELDS)
    logger.info(
        "Review queue: %d/%d cases → %s",
        len(flagged), len(cases), review_path,
    )


# ── Internal ───────────────────────────────────────────────────────────────────

def _write_json(cases: List[CaseMetadata], path: Path) -> None:
    data = [c.to_dict() for c in cases]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    logger.debug("Wrote %s", path)


def _write_csv(cases: List[CaseMetadata], path: Path, fields: List[str]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        for case in cases:
            writer.writerow(case.to_csv_row())
    logger.debug("Wrote %s", path)
