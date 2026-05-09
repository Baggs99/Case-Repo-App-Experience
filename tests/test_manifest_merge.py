"""Tests for manifest merge (partial re-split)."""

import json
import sys
import uuid
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from models.case import CaseMetadata
from pipeline.manifest import merge_manifest_replace_sources, write_manifest


def _row(source: str, title: str, page: int) -> dict:
    cid = str(uuid.uuid4())
    return {
        "id": cid,
        "case_title": title,
        "source_pdf": source,
        "source_folder": "Yale",
        "source_school": "yale",
        "source_year": 2017,
        "page_start": page,
        "page_end": page,
        "page_count": 1,
        "output_pdf_path": f"cases/{Path(source).stem}/x.pdf",
        "extraction_confidence": 1.0,
        "detection_method": "manual",
        "needs_manual_review": False,
        "industry": None,
        "case_type": None,
        "difficulty_overall": None,
        "difficulty_quant": None,
        "difficulty_qual": None,
        "interviewer_style": None,
        "prompt_excerpt": None,
        "matched_toc_title": title,
        "matched_start_page_text": None,
        "matched_patterns": [],
        "confidence_notes": [],
        "review_flags": [],
    }


def test_merge_manifest_replace_sources_order(tmp_path):
    baseline = tmp_path / "manifest.json"
    old = [
        _row("Other/Book.pdf", "Keep A", 1),
        _row("Yale/Fuqua 2017.pdf", "Old Fuqua", 5),
        _row("Yale/Fuqua 2017.pdf", "Old Fuqua 2", 6),
        _row("Other/Book2.pdf", "Keep B", 1),
    ]
    baseline.write_text(json.dumps(old), encoding="utf-8")

    new_cases = [
        CaseMetadata.from_manifest_dict(_row("Yale/Fuqua 2017.pdf", "New Fuqua", 99)),
    ]
    merged = merge_manifest_replace_sources(
        baseline_path=baseline,
        processed_source_pdfs={"Yale/Fuqua 2017.pdf"},
        new_cases=new_cases,
    )
    assert len(merged) == 3
    assert merged[0].case_title == "Keep A"
    assert merged[1].case_title == "New Fuqua"
    assert merged[2].case_title == "Keep B"


def test_round_trip_via_write_manifest(tmp_path):
    old = [_row("S.pdf", "One", 1)]
    p = tmp_path / "m.json"
    p.write_text(json.dumps(old), encoding="utf-8")
    new_cases = [CaseMetadata.from_manifest_dict(_row("S.pdf", "Repl", 2))]
    merged = merge_manifest_replace_sources(
        baseline_path=p,
        processed_source_pdfs={"S.pdf"},
        new_cases=new_cases,
    )
    write_manifest(merged, tmp_path)
    loaded = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))
    assert len(loaded) == 1
    assert loaded[0]["case_title"] == "Repl"
