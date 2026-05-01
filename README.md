# case-splitter

A local-first pipeline that takes a repository of consulting casebook PDFs and
splits them into individual case PDFs with structured metadata.

## Features

- **Recursive scan** of a root folder across any number of school sub-folders
- **Automatic classification** of each PDF (multi-case casebook vs already-split)
- **TOC-driven parsing** (primary) — finds the Table of Contents and uses it as the ground truth for case boundaries
- **Header-pattern parsing** (fallback) — detects case-title pages via layout scoring when no TOC is found
- **Structured metadata** per case: school, year, industry, case type, difficulty, interviewer style, prompt excerpt
- **Dry-run mode** — preview everything without writing a single file
- **Review queue CSV** — every uncertain case is flagged for manual QA
- **Full manifest** — `manifest.json` + `manifest.csv` with one row per case
- **Diagnostic traceability** — every boundary decision is saved in metadata so mis-splits can be debugged

---

## Project Structure

```
Case Repo/               ← your input folder (contains Booth/, Yale/, etc.)
├── main.py              ← CLI entry point
├── config.yaml          ← all heuristic thresholds (tune without touching code)
├── requirements.txt
├── README.md
│
├── models/
│   ├── case.py          ← CaseBoundary, CaseMetadata dataclasses
│   └── document.py      ← PDFDocument dataclass
│
├── utils/
│   ├── logging_setup.py
│   ├── pdf_utils.py     ← fitz wrappers (open, extract text, split pages)
│   └── slug.py          ← filesystem-safe slug generation
│
├── pipeline/
│   ├── scanner.py       ← recursive PDF discovery
│   ├── classifier.py    ← multi-case vs single-case heuristics
│   ├── splitter.py      ← writes split PDFs to disk
│   ├── metadata_extractor.py  ← enriches boundaries with content metadata
│   ├── manifest.py      ← writes manifest.json/.csv and review_queue.csv
│   ├── reviewer.py      ← QA checks (overlaps, short/long cases, duplicates)
│   ├── reporter.py      ← prints the end-of-run summary
│   ├── orchestrator.py  ← ties all stages together
│   └── parsers/
│       ├── base.py              ← BaseCasebookParser (abstract)
│       ├── toc_driven.py        ← TocDrivenParser (primary)
│       ├── header_pattern.py    ← HeaderPatternParser (fallback)
│       ├── single_case.py       ← SingleCaseParser (last resort / already-split)
│       └── profiles/
│           ├── __init__.py      ← profile registry + get_profile()
│           └── default.py       ← CasebookProfile dataclass + school factories
│
└── tests/
    ├── test_classifier.py
    ├── test_boundary_detection.py
    └── test_metadata_extraction.py
```

---

## Quick Start

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

Requirements: Python 3.10+, PyMuPDF, pdfplumber, click, PyYAML, python-slugify.

### 2. Preview without writing files (dry run)

```bash
python main.py split --input "Case Repo" --output output --dry-run
```

### 3. Run the full pipeline

```bash
python main.py split --input "Case Repo" --output output
```

### 4. Scan only (classify, no splitting)

```bash
python main.py scan --input "Case Repo"
```

### 5. Inspect the review queue

```bash
python main.py review --manifest output/manifest.json --only-flagged
```

---

## CLI Reference

```
python main.py scan  --input DIR [--config FILE] [--verbose]
python main.py split --input DIR [--output DIR] [--config FILE] [--dry-run] [--verbose] [--log-file FILE]
python main.py review --manifest FILE [--only-flagged]
python main.py classify-difficulty [--catalog FILE] [--cases-root DIR] [--model NAME] [--limit N] [--dry-run] [--force]
python main.py evaluate-difficulty-calibration [--catalog FILE] [--cases-root DIR] [--sample-size N] [--model NAME] [--dry-run]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--input` | (required) | Root folder containing school sub-folders |
| `--output` | `output` | Destination for split PDFs and manifests |
| `--config` | `config.yaml` | Path to configuration file |
| `--dry-run` | off | Log everything; write nothing |
| `--verbose` | off | Show DEBUG-level logs in terminal |
| `--log-file` | `output/pipeline.log` | Write full DEBUG log to file |

---

## Output Layout

```
output/
├── manifest.json          ← all cases, full detail
├── manifest.csv           ← same, flat CSV
├── review_queue.csv       ← only flagged cases
├── pipeline.log           ← full debug log
└── cases/
    ├── Booth/
    │   └── Booth 2026/
    │       ├── big-tech-bivalves.pdf
    │       └── healthcare-market-entry.pdf
    └── Yale/
        └── Ross 2024/
            ├── retail-growth-strategy.pdf
            └── pharma-acquisition.pdf
```

---

## Manifest Fields

| Field | Description |
|-------|-------------|
| `id` | UUID4 |
| `case_title` | Detected title |
| `source_pdf` | Relative path of source PDF |
| `source_folder` | Top-level subfolder (`Booth`, `Yale`, …) |
| `source_school` | Normalised slug (`booth`, `yale`, …) |
| `source_year` | Year parsed from filename (null if not found) |
| `page_start` | 1-indexed start page in source PDF |
| `page_end` | 1-indexed end page in source PDF |
| `page_count` | Number of pages in the split case |
| `output_pdf_path` | Relative path of the output PDF |
| `extraction_confidence` | 0.0 – 1.0 |
| `detection_method` | `toc` / `header_pattern` / `already_single_case` |
| `needs_manual_review` | `true` / `false` |
| `industry` | Inferred or extracted industry |
| `case_type` | `Profitability`, `Market Entry`, `M&A`, … |
| `difficulty_overall` | From labeled field or null |
| `difficulty_quant` | From labeled field or null |
| `difficulty_qual` | From labeled field or null |
| `interviewer_style` | `Interviewee-led` / `Interviewer-led` / null |
| `prompt_excerpt` | First 300 chars of the Prompt section |
| `matched_toc_title` | Exact title string from TOC |
| `matched_start_page_text` | First 200 chars of detected start page |
| `matched_patterns` | Heuristics that fired |
| `confidence_notes` | Human-readable scoring explanation |
| `review_flags` | Short tokens: `too_few_pages`, `title_mismatch_on_start_page`, … |

---

## Review Flags

| Flag | Meaning |
|------|---------|
| `too_few_pages` | Case is shorter than `min_case_pages` in config |
| `too_many_pages` | Case is longer than `max_case_pages` in config |
| `title_mismatch_on_start_page` | TOC title not found in start-page text |
| `overlapping_page_range` | Page ranges overlap with adjacent case |
| `low_confidence` | Overall confidence below threshold |
| `duplicate_title` | Same title appears multiple times in source PDF |
| `unassigned_pages_warning` | Many pages in source PDF not covered by any case |
| `invalid_page_order` | `page_start` ≥ `page_end` |
| `title_too_short` | Title has fewer than 3 characters |
| `title_is_number` | Title is purely numeric |

---

## Configuration (`config.yaml`)

All heuristic thresholds live in `config.yaml` so you can tune the pipeline
without touching Python source code.

Key settings:

```yaml
processing:
  max_toc_search_pages: 40      # How deep to search for a TOC
  likely_casebook_min_pages: 30 # PDFs larger than this are assumed multi-case
  min_case_pages: 3             # Shorter cases get a review flag
  max_case_pages: 60            # Longer cases get a review flag

confidence:
  low_confidence_threshold: 0.50  # Below this → needs_manual_review = true
  toc_match_threshold: 0.65
  header_pattern_threshold: 0.45

school_overrides:
  rocketblocks:
    always_single_case: true     # Skip boundary detection for this school
  booth:
    preferred_parser: toc_driven # Force TOC parser for Booth
```

### Adding a new school

1. Add a folder-name → slug entry in `config.yaml :: known_schools`.
2. Optionally add overrides in `config.yaml :: school_overrides`.
3. If you need custom section headers, edit `pipeline/parsers/profiles/default.py`.

---

## Adding a New Parser

1. Create `pipeline/parsers/my_parser.py`.
2. Subclass `BaseCasebookParser` and implement `parse()` (and optionally `can_handle()`).
3. Register it in `pipeline/orchestrator.py :: _detect_boundaries()`.

The base class provides `_clamp_boundaries()` and `_sort_boundaries()` utilities.

---

## Running Tests

```bash
python -m pytest tests/ -v
```

Tests use mocked `fitz.Document` objects — no real PDFs are required.

---

## How the Parsers Work

### TocDrivenParser (primary)

1. Searches the first `max_toc_search_pages` pages for TOC indicators.
2. Extracts `(title, printed_page_number)` pairs using five regex patterns that
   cover dotted leaders, space-separated, tab-separated, and "page X" formats.
3. Detects the **page offset** — many PDFs have unnumbered front matter so
   "printed page 1" is actually fitz page index 3.  The parser probes the first
   few TOC entries against actual page text to measure this offset.
4. Builds one `CaseBoundary` per TOC entry.
5. Validates: checks that each start page actually contains the expected title
   fragment; flags mismatches for review.

**Confidence starts at 0.90 for TOC-derived boundaries** and is reduced by:
- Applying a page-number offset (−0.04)
- Title not found on start page (−0.20)
- Overlapping ranges (−0.25)
- Case shorter/longer than expected (−0.10 to −0.15)

### HeaderPatternParser (fallback)

Scores every page on a 0–1 scale using these signals:

| Signal | Points |
|--------|--------|
| Very little text on page (< 80 chars) | +0.28 |
| First text block in top 20% of page | +0.22 |
| Page contains metadata labels (Industry:, Type:, …) | +0.28 |
| A section-header page follows within 4 pages | +0.22 |
| Page does NOT contain mid-case content | +0.08 |
| Title is Title Case or ALL CAPS | +0.10 |
| Page has lots of text (> 1500 chars) | −0.18 |
| Page contains 2+ mid-case markers | −0.30 |

Pages scoring ≥ 0.42 become case-start candidates.  Candidates too close
together (< `min_case_pages`) are pruned by keeping the higher-scored one.

**Confidence is capped at 0.75 × raw score** (vs 0.90+ for TOC).

---

## Limitations & Known Issues

- **Image-only PDFs**: Text extraction will return empty strings.  The pipeline
  will classify these as `single_case` and flag them for manual review.
  OCR is intentionally not included; add it as a pre-processing step if needed.
- **Unusual TOC formats**: Very creative formatting (e.g., inline tables, fancy
  fonts rendered as images) may defeat the regex extractor.  In those cases
  the pipeline falls back to header-pattern detection.
- **Page-number offset**: Some PDFs use section-based page numbering (1, 2, 3
  within each chapter) which can confuse the offset detector.  Check the
  `confidence_notes` field for evidence.

---

## OpenAI Difficulty Classifier

Cases that were never hand-rated can be filled in automatically by the
`classify-difficulty` command. It calls the OpenAI **Responses API**
(default model: `gpt-5.4`) with a **JSON schema** structured output so
every response parses cleanly.

### How it works

1. The case catalog is loaded from `output/case_catalog.csv|.xlsx`.
2. Rows with a blank `difficulty_normalized` are selected (existing
   human-reviewed labels are never overwritten unless `--force` is
   passed).
3. A small, diverse set of already-labeled cases is picked as
   **calibration anchors** — a few Easy, a few Medium, a few Hard —
   preferring the hand-pinned anchors from
   `pipeline/difficulty_rater.py` and then spreading across distinct
   schools and case types.
4. For each unlabeled case we build a compact JSON **difficulty packet**
   (title, school, year, case type, concepts, prompt excerpt, raw
   difficulty hints, optional first-pages text from the split PDF).
5. The model receives the anchors + the new case and returns:

   ```json
   {
     "difficulty_normalized": "Easy" | "Medium" | "Hard",
     "difficulty_score":       1.0-10.0,
     "difficulty_quant":       1-10,
     "difficulty_qual":        1-10,
     "difficulty_notes":       "short rationale",
     "confidence":             0.0-1.0
   }
   ```

6. Results are written back into the catalog (`difficulty_normalized`,
   `difficulty_score`, `difficulty_notes`, plus provenance fields
   `difficulty_source="openai_calibrated"`, `difficulty_confidence`,
   `difficulty_model`).
7. Every prediction is also logged to `output/audit/`:
   - `llm_difficulty_predictions.csv` — one row per successful call
   - `llm_difficulty_failures.csv` — parse / API failures
   - `llm_difficulty_needs_review.csv` — low-confidence or
     near-boundary predictions (confidence < 0.65 or score within 0.3
     of the 4.9/5.0 or 6.9/7.0 boundary)
   - `llm_difficulty_calibration_examples.json` — the exact anchor set
     sent with the run

### Running it

```bash
export OPENAI_API_KEY=sk-...
python main.py classify-difficulty \
    --catalog output/case_catalog.xlsx \
    --cases-root output/cases
```

Useful flags:

| Flag | Purpose |
|------|---------|
| `--model gpt-5.4` | Override the model (also reads `OPENAI_MODEL`) |
| `--limit 20` | Only classify the first N unlabeled rows |
| `--dry-run` | Build packets and log; don't call the API |
| `--force` | Re-rate every row, not just the blank ones |
| `--cases-root output/cases` | Include a PDF text excerpt in each packet |
| `--audit-dir output/audit` | Where to write the audit CSVs |

### Calibration QA pass (recommended before a full run)

Before you unleash the classifier on all 217 unlabeled rows, sanity-check
that it agrees with the existing labels. The `evaluate-difficulty-calibration`
command stratified-samples already-labeled cases, re-runs the classifier
on them (with the sampled titles *excluded* from the calibration anchor
pool so no labels leak in-context), and compares predicted vs. existing:

```bash
python main.py evaluate-difficulty-calibration \
    --catalog output/case_catalog.xlsx \
    --cases-root output/cases \
    --sample-size 30
```

Outputs (catalog is **never** modified):

- `output/audit/difficulty_calibration_eval.csv` — one row per evaluated
  case with existing vs. predicted label, score gap, confidence, and
  the model's difficulty notes.
- `output/audit/difficulty_calibration_summary.json` — aggregate
  metrics: exact-match rate, match rate per bucket, confusion matrix
  (rows = existing, cols = predicted), avg `|score gap|`, worst
  disagreements, and disagreement rate by school.

Warning thresholds (logged + written into the summary's `warnings`
list, non-fatal):

| Metric | Threshold |
|--------|-----------|
| Exact label match rate | ≥ 70% |
| Average absolute score gap | ≤ 1.0 |

If either threshold trips, investigate the `worst_disagreements`
section before running `classify-difficulty` in anger.

### Rerunning safely

- The command is **idempotent by default**: it only fills blanks.
- Manually reviewed labels are never overwritten unless you pass
  `--force` explicitly.
- If you interrupt a run and re-invoke it, only the still-blank rows
  are re-classified.
- Every prompt has a short SHA-256 hash logged, so you can tell
  whether inputs changed between runs.

---

## License

MIT — use freely, attribution appreciated.
