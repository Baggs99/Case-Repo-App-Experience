"""
OpenAI-powered difficulty classifier.

Fills in ``difficulty_normalized`` / ``difficulty_score`` for catalog rows
that have not been human-rated yet.  The model is anchored to the labels
already present in the catalog so that its ratings land on the same scale
the project has been using (see ``pipeline/difficulty_rater.py`` for the
hand-calibrated anchors).

Design notes
------------
* Uses the OpenAI **Responses API** with a **JSON schema** structured
  output so every response is directly parseable.
* Defaults to ``gpt-5.4`` (override via ``OPENAI_MODEL`` or
  ``--model``).  The model name is read from env / CLI — no hard-coded
  ``models.yaml`` dependency — to keep the step independent of the rest
  of the pipeline.
* Only rows missing a ``difficulty_normalized`` value are touched
  unless ``force=True`` is passed explicitly.  Human-reviewed rows are
  never overwritten.
* Every request / response is written to an audit CSV so the run is
  reproducible and reviewable.

Public API
----------
    build_difficulty_packet(row, case_text=None) -> dict
    load_calibration_examples(catalog_df)        -> list[dict]
    classify_case_difficulty(packet, calibration, *, client, model)
        -> dict | None
    classify_missing_difficulties(
        catalog_df, *, model=None, limit=None,
        force=False, dry_run=False, audit_dir=None,
        cases_root=None, client=None,
    ) -> pandas.DataFrame
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import random
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

import pandas as pd

logger = logging.getLogger(__name__)


# ── Constants ────────────────────────────────────────────────────────────────

DEFAULT_MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.4")

#: Fields we write back into the catalog.
WRITE_BACK_COLUMNS = [
    "difficulty_normalized",
    "difficulty_score",
    "difficulty_notes",
    "difficulty_source",
    "difficulty_confidence",
    "difficulty_model",
]

#: Allowed normalized labels.
BUCKETS = ("Easy", "Medium", "Hard")

#: Score midpoints + boundaries for review flagging.
_BOUNDARY_SCORES = (4.9, 5.0, 6.9, 7.0)
_BOUNDARY_WINDOW = 0.3
_LOW_CONFIDENCE_CUTOFF = 0.65

#: How many calibration examples to include per bucket (Easy/Medium/Hard).
_EXAMPLES_PER_BUCKET = 4

#: Hard cap on calibration examples regardless of bucket-level size.
_MAX_CALIBRATION_EXAMPLES = 15

#: Char caps on text passed to the model — keeps tokens bounded.
_PROMPT_EXCERPT_CAP = 1200
_CASE_TEXT_CAP = 4000
_EXAMPLE_SUMMARY_CAP = 400

#: Retry behaviour for the API call.
_MAX_ATTEMPTS = 3
_BACKOFF_BASE_SECONDS = 2.0


# ── Structured output schema ─────────────────────────────────────────────────

DIFFICULTY_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "difficulty_normalized": {
            "type": "string",
            "enum": list(BUCKETS),
            "description": "Overall bucket: Easy, Medium, or Hard.",
        },
        "difficulty_score": {
            "type": "number",
            "description": "Composite 1.0-10.0 score. Easy<5.0, Medium 5.0-6.9, Hard>=7.0.",
            "minimum": 1.0,
            "maximum": 10.0,
        },
        "difficulty_quant": {
            "type": "number",
            "description": "Quantitative burden on a 1-10 scale.",
            "minimum": 1.0,
            "maximum": 10.0,
        },
        "difficulty_qual": {
            "type": "number",
            "description": "Qualitative / structural difficulty on a 1-10 scale.",
            "minimum": 1.0,
            "maximum": 10.0,
        },
        "difficulty_notes": {
            "type": "string",
            "description": "One or two sentences explaining the rating.",
        },
        "confidence": {
            "type": "number",
            "description": "Rater self-confidence in [0,1].",
            "minimum": 0.0,
            "maximum": 1.0,
        },
    },
    "required": [
        "difficulty_normalized",
        "difficulty_score",
        "difficulty_quant",
        "difficulty_qual",
        "difficulty_notes",
        "confidence",
    ],
}


SYSTEM_PROMPT = """\
You are an experienced MBB consulting case-interview coach who rates
practice cases for difficulty. Your job is to rate each NEW case on the
exact same scale as the CALIBRATION EXAMPLES you will be shown.

Use this rubric:
- Easy   (1.0-4.9): beginner-friendly, light math, low ambiguity,
                    straightforward structure, limited synthesis.
- Medium (5.0-6.9): standard consulting interview prep, balanced quant
                    + qualitative, some ambiguity, some multi-step
                    reasoning, realistic but manageable.
- Hard   (7.0-10.0): high ambiguity and/or high math burden,
                     data-dense or synthesis-heavy, multi-step, closest
                     to a tough MBB final-round interview.

Explicitly weigh:
  - ambiguity of the prompt
  - amount and complexity of required math / market sizing
  - number of reasoning steps required
  - chart / exhibit complexity
  - synthesis burden (how many threads must be tied together)
  - how close the case feels to a real MBB interview

Avoid over-weighting:
  - interesting topics or famous brands
  - case type label alone (do NOT assume Market Entry or M&A is Hard
    and Profitability is Medium; judge each case on its merits)
  - length of the PDF

Anchor your rating to the calibration examples. If a new case looks
comparable to an Easy anchor, rate it Easy; similarly for Medium / Hard.
If you are unsure between two buckets, still return your best guess and
explain the ambiguity in difficulty_notes, lowering the confidence value.
Respond with the JSON object matching the provided schema, nothing else.
"""


# ── Calibration example selection ────────────────────────────────────────────

@dataclass
class CalibrationExample:
    case_title: str
    source_school: str
    case_type_normalized: str
    industry: str
    summary: str
    difficulty_normalized: str
    difficulty_score: Optional[float]
    difficulty_notes: str = ""

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "case_title": self.case_title,
            "difficulty_normalized": self.difficulty_normalized,
        }
        if self.source_school and self.source_school.lower() != "nan":
            d["source_school"] = self.source_school
        if self.case_type_normalized and self.case_type_normalized.lower() != "nan":
            d["case_type"] = self.case_type_normalized
        if self.industry and self.industry.lower() != "nan":
            d["industry"] = self.industry
        if self.summary:
            d["summary"] = _truncate(self.summary, _EXAMPLE_SUMMARY_CAP)
        if self.difficulty_score is not None:
            d["difficulty_score"] = round(self.difficulty_score, 1)
        if self.difficulty_notes:
            d["note"] = _truncate(self.difficulty_notes, 160)
        return d


def load_calibration_examples(
    catalog_df: pd.DataFrame,
    *,
    per_bucket: int = _EXAMPLES_PER_BUCKET,
    exclude_titles: Optional[Iterable[str]] = None,
) -> list[dict]:
    """
    Select a small, balanced set of already-labeled cases as calibration
    anchors.

    Prefers:
      1. Anchor cases explicitly pinned in ``pipeline/difficulty_rater``.
      2. Cases with a populated ``prompt_excerpt`` / ``case_title_raw``.
      3. Spread across distinct ``source_school`` + ``case_type_normalized``.

    ``exclude_titles`` is an optional iterable of case titles that must
    NOT appear in the calibration set (used by the calibration-eval
    mode to prevent label leakage when evaluating the classifier against
    held-out labeled cases).
    """
    if "difficulty_normalized" not in catalog_df.columns:
        return []

    rng = random.Random(42)  # deterministic

    exclusions = {str(t).strip().lower() for t in (exclude_titles or []) if t}

    examples: list[CalibrationExample] = []
    labeled = catalog_df[catalog_df["difficulty_normalized"].isin(BUCKETS)].copy()
    if exclusions:
        labeled = labeled[
            ~labeled["case_title"].fillna("").str.strip().str.lower().isin(exclusions)
        ]
    if labeled.empty:
        return []

    # Anchor titles from pipeline/difficulty_rater.ANCHOR_OVERRIDES.
    anchor_needles = (
        "antidepressant pricing", "always fresh", "art museum",
        "big ten bivalves", "donatella", "let's vroom", "lets vroom",
        "maize & blue", "malaria remedy", "melt that snow",
        "tw tech", "wolverinehomes",
    )

    titles_lower = labeled["case_title"].fillna("").str.lower()
    anchor_mask = titles_lower.apply(
        lambda t: any(needle in t for needle in anchor_needles)
    )
    anchors = labeled[anchor_mask]
    rest = labeled[~anchor_mask]

    for bucket in BUCKETS:
        bucket_rows: list[pd.Series] = []

        # First pass: anchor cases in this bucket.
        anchor_bucket = anchors[anchors["difficulty_normalized"] == bucket]
        for _, row in anchor_bucket.iterrows():
            if len(bucket_rows) >= per_bucket:
                break
            bucket_rows.append(row)

        # Second pass: fill with diverse cases from other schools / case types.
        remaining = rest[rest["difficulty_normalized"] == bucket]
        remaining = remaining.sample(frac=1.0, random_state=42) if not remaining.empty else remaining
        seen_keys: set[tuple[str, str]] = set(
            (str(r.get("source_school", "")), str(r.get("case_type_normalized", "")))
            for r in bucket_rows
        )
        # Prefer diverse (school, case_type) keys.
        for _, row in remaining.iterrows():
            if len(bucket_rows) >= per_bucket:
                break
            key = (str(row.get("source_school", "")), str(row.get("case_type_normalized", "")))
            if key in seen_keys:
                continue
            bucket_rows.append(row)
            seen_keys.add(key)

        # Third pass: if still short, fill with whatever's left.
        if len(bucket_rows) < per_bucket:
            for _, row in remaining.iterrows():
                if len(bucket_rows) >= per_bucket:
                    break
                bucket_rows.append(row)

        for row in bucket_rows:
            examples.append(_row_to_example(row))

    # Shuffle to avoid bucket-order bias inside the prompt, but keep the
    # list small and deterministic.
    rng.shuffle(examples)
    trimmed = examples[:_MAX_CALIBRATION_EXAMPLES]
    return [e.to_dict() for e in trimmed]


def _row_to_example(row: pd.Series) -> CalibrationExample:
    summary_parts: list[str] = []
    for field_name in ("prompt_excerpt",):
        val = row.get(field_name)
        if isinstance(val, str) and val.strip() and val.strip().lower() != "nan":
            summary_parts.append(val.strip())
    for field_name in ("concepts_tested", "difficulty_quant_category"):
        val = row.get(field_name)
        if isinstance(val, str) and val.strip() and val.strip().lower() != "nan":
            summary_parts.append(f"{field_name}: {val.strip()}")

    score_raw = row.get("difficulty_score")
    try:
        score = float(score_raw) if score_raw not in (None, "", "nan") and pd.notna(score_raw) else None
    except (TypeError, ValueError):
        score = None

    return CalibrationExample(
        case_title=str(row.get("case_title") or "").strip(),
        source_school=str(row.get("source_school") or "").strip(),
        case_type_normalized=str(
            row.get("case_type_normalized") or row.get("case_type") or ""
        ).strip(),
        industry=str(row.get("industry") or "").strip(),
        summary=" | ".join(summary_parts),
        difficulty_normalized=str(row.get("difficulty_normalized") or "").strip(),
        difficulty_score=score,
    )


# ── Packet building ──────────────────────────────────────────────────────────

def build_difficulty_packet(
    row: dict | pd.Series,
    case_text: Optional[str] = None,
) -> dict[str, Any]:
    """
    Build a compact, token-bounded dict describing a single case for
    the model. Only non-empty fields are included.
    """
    if isinstance(row, pd.Series):
        row = row.to_dict()

    def _get(k: str) -> Any:
        v = row.get(k)
        if v is None:
            return None
        if isinstance(v, float) and pd.isna(v):
            return None
        s = str(v).strip()
        return s or None

    packet: dict[str, Any] = {}

    # Core identifying metadata. ``case_title`` is occasionally blank for
    # rows that came in via an enrichment step that only populated the
    # raw / canonical title — fall back so the model always sees a name.
    title = _resolve_title(row, _get)
    if title:
        packet["case_title"] = title

    for k in (
        "source_school", "source_year",
        "industry", "case_type_raw", "case_type_normalized",
    ):
        val = _get(k)
        if val is not None:
            # source_year often survives as "2011.0" after round-tripping
            # through pandas — strip the trailing ".0" so prompts are clean.
            if k == "source_year" and val.endswith(".0"):
                val = val[:-2]
            packet[k] = val

    # Raw difficulty signals that aren't yet normalized (useful context).
    raw_difficulty: dict[str, Any] = {}
    for k in (
        "difficulty", "difficulty_raw",
        "difficulty_quant", "difficulty_qual",
        "difficulty_math", "difficulty_structure",
        "difficulty_creativity", "difficulty_quant_category",
        "difficulty_visual_present",
    ):
        val = _get(k)
        if val is not None:
            raw_difficulty[k] = val
    if raw_difficulty:
        packet["raw_difficulty_hints"] = raw_difficulty

    # Concepts / tags
    concepts = _get("concepts_tested")
    if concepts:
        packet["concepts_tested"] = _truncate(concepts, 400)

    # Structure hints
    try:
        page_count = int(row.get("page_count") or 0)
        if page_count > 0:
            packet["page_count"] = page_count
    except (TypeError, ValueError):
        pass

    interviewer_led = _get("interviewer_led")
    if interviewer_led is not None:
        packet["interviewer_led"] = interviewer_led

    firm = _get("firm")
    if firm:
        packet["firm"] = firm

    # Prompt excerpt straight from the manifest / catalog if available.
    prompt_excerpt = _get("prompt_excerpt")
    if prompt_excerpt:
        packet["prompt_excerpt"] = _truncate(prompt_excerpt, _PROMPT_EXCERPT_CAP)

    # Optional full-case text summary extracted by the caller.
    if case_text:
        packet["case_text_excerpt"] = _truncate(case_text.strip(), _CASE_TEXT_CAP)

    # Traceability
    for k in ("source_pdf", "output_pdf_path"):
        val = _get(k)
        if val is not None:
            packet[k] = val

    return packet


def _resolve_title(row: dict, getter) -> str:
    """Pick the best available title field for a catalog row.

    Some catalog exports leave ``case_title`` blank but populate
    ``case_title_raw`` / ``canonical_case_title`` / ``normalized_title``
    instead.  Falling back keeps audit logs and prompts readable.
    """
    for field_name in (
        "case_title", "case_title_raw",
        "canonical_case_title", "normalized_title",
    ):
        val = getter(field_name)
        if val:
            return val
    return ""


# ── API call ─────────────────────────────────────────────────────────────────

@dataclass
class ClassifyResult:
    ok: bool
    data: Optional[dict[str, Any]] = None
    raw_output: str = ""
    error_type: str = ""
    error_message: str = ""
    attempts: int = 0
    prompt_hash: str = ""
    model: str = ""


#: Model-name prefixes whose Responses-API endpoint does not accept the
#: `temperature` parameter. Matched case-insensitively as ``startswith``.
_REASONING_MODEL_PREFIXES = ("o1", "o3", "o4")


def _supports_temperature(model: str) -> bool:
    low = (model or "").lower()
    return not any(low.startswith(p) for p in _REASONING_MODEL_PREFIXES)


def classify_case_difficulty(
    packet: dict[str, Any],
    calibration_examples: list[dict],
    *,
    client: Any,
    model: str = DEFAULT_MODEL,
    temperature: float = 0.1,
) -> ClassifyResult:
    """Call the OpenAI Responses API for a single case, with retries."""
    if client is None:
        return ClassifyResult(
            ok=False, error_type="client_missing",
            error_message="OpenAI client was not provided.",
            model=model,
        )

    user_payload = {
        "calibration_examples": calibration_examples,
        "new_case": packet,
        "instructions": (
            "Rate the NEW CASE on the same scale used by the calibration "
            "examples above. Respond with the JSON object matching the "
            "provided schema."
        ),
    }
    user_text = json.dumps(user_payload, ensure_ascii=False, indent=2)
    prompt_hash = hashlib.sha256(
        (SYSTEM_PROMPT + "\n" + user_text).encode("utf-8")
    ).hexdigest()[:16]

    last_error: tuple[str, str] = ("", "")
    raw_output = ""

    request_kwargs: dict[str, Any] = {
        "model": model,
        "input": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_text},
        ],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "case_difficulty_rating",
                "strict": True,
                "schema": DIFFICULTY_SCHEMA,
            }
        },
    }
    # Reasoning-family models (o1 / o3 / o4 / …) reject `temperature`.
    if _supports_temperature(model):
        request_kwargs["temperature"] = temperature

    for attempt in range(1, _MAX_ATTEMPTS + 1):
        try:
            try:
                response = client.responses.create(**request_kwargs)
            except Exception as inner:
                # Some endpoints (reasoning-family models, new previews) reject
                # `temperature`. Strip it once and retry within the same attempt
                # so we don't burn the full retry budget on a deterministic
                # schema-level mismatch.
                msg = str(inner).lower()
                if "temperature" in request_kwargs and (
                    "'temperature' is not supported" in msg
                    or "unsupported parameter: 'temperature'" in msg
                ):
                    logger.info(
                        "Model '%s' rejected temperature; retrying without it.",
                        model,
                    )
                    request_kwargs.pop("temperature", None)
                    response = client.responses.create(**request_kwargs)
                else:
                    raise
            raw_output = getattr(response, "output_text", "") or ""
            if not raw_output:
                raw_output = _coerce_output_text(response)

            parsed = _parse_and_validate(raw_output)
            if parsed is not None:
                return ClassifyResult(
                    ok=True, data=parsed, raw_output=raw_output,
                    attempts=attempt, prompt_hash=prompt_hash, model=model,
                )

            last_error = ("invalid_json", f"Could not parse response: {raw_output[:300]}")

        except Exception as exc:  # noqa: BLE001  (we log + retry on any API error)
            last_error = (type(exc).__name__, str(exc))
            logger.warning("OpenAI call failed on attempt %d: %s", attempt, exc)

        # Basic exponential backoff; final failure exits the loop.
        if attempt < _MAX_ATTEMPTS:
            time.sleep(_BACKOFF_BASE_SECONDS ** attempt)

    return ClassifyResult(
        ok=False, raw_output=raw_output, attempts=_MAX_ATTEMPTS,
        error_type=last_error[0] or "unknown",
        error_message=last_error[1] or "Unknown error",
        prompt_hash=prompt_hash, model=model,
    )


def _coerce_output_text(response: Any) -> str:
    """Fallback text extraction when response.output_text is empty."""
    try:
        output = getattr(response, "output", None) or []
        parts: list[str] = []
        for item in output:
            content = getattr(item, "content", None) or []
            for chunk in content:
                text = getattr(chunk, "text", None)
                if isinstance(text, str):
                    parts.append(text)
        return "".join(parts)
    except Exception:
        return ""


def _parse_and_validate(raw: str) -> Optional[dict[str, Any]]:
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        # Some models wrap in ```json ... ```; strip that.
        stripped = raw.strip().strip("`")
        if stripped.lower().startswith("json"):
            stripped = stripped[4:].lstrip()
        try:
            data = json.loads(stripped)
        except json.JSONDecodeError:
            return None

    if not isinstance(data, dict):
        return None
    required = {
        "difficulty_normalized", "difficulty_score",
        "difficulty_notes", "confidence",
    }
    if not required.issubset(data):
        return None
    if data["difficulty_normalized"] not in BUCKETS:
        return None
    try:
        score = float(data["difficulty_score"])
        conf = float(data["confidence"])
    except (TypeError, ValueError):
        return None
    if not 1.0 <= score <= 10.0:
        return None
    if not 0.0 <= conf <= 1.0:
        return None

    data["difficulty_score"] = round(score, 2)
    data["confidence"] = round(conf, 3)
    for sub in ("difficulty_quant", "difficulty_qual"):
        if sub in data:
            try:
                data[sub] = round(float(data[sub]), 2)
            except (TypeError, ValueError):
                data[sub] = None
    return data


# ── Orchestration ────────────────────────────────────────────────────────────

@dataclass
class AuditRecord:
    case_title: str = ""
    source_school: str = ""
    source_year: str = ""
    source_pdf: str = ""
    difficulty_normalized_existing: str = ""
    difficulty_normalized_predicted: str = ""
    difficulty_score_predicted: str = ""
    difficulty_quant_predicted: str = ""
    difficulty_qual_predicted: str = ""
    difficulty_notes: str = ""
    confidence: str = ""
    model_name: str = ""
    prediction_timestamp: str = ""
    prompt_hash: str = ""
    needs_review: bool = False
    review_reasons: list[str] = field(default_factory=list)


@dataclass
class FailureRecord:
    case_title: str = ""
    source_pdf: str = ""
    error_type: str = ""
    error_message: str = ""
    prompt_hash: str = ""
    attempts: int = 0


def classify_missing_difficulties(
    catalog_df: pd.DataFrame,
    *,
    model: Optional[str] = None,
    limit: Optional[int] = None,
    force: bool = False,
    dry_run: bool = False,
    audit_dir: Optional[Path] = None,
    cases_root: Optional[Path] = None,
    client: Any = None,
) -> pd.DataFrame:
    """
    Fill in missing ``difficulty_normalized`` / ``difficulty_score`` using
    the OpenAI Responses API. Returns the updated catalog DataFrame.

    Parameters
    ----------
    catalog_df:
        Full case catalog (from ``output/case_catalog.csv|.xlsx``).
    model:
        OpenAI model name. Falls back to the ``OPENAI_MODEL`` env var or
        ``"gpt-5.4"``.
    limit:
        Classify at most this many rows. ``None`` processes every row
        missing a label.
    force:
        If True, re-classify rows even if they already have a label.
        Existing labels are still kept in the audit log under
        ``difficulty_normalized_existing``.
    dry_run:
        Build packets and log, but do not call the API or modify the
        catalog.
    audit_dir:
        Where to write ``llm_difficulty_predictions.csv`` and friends.
        Defaults to ``output/audit`` relative to cwd.
    cases_root:
        If provided, attempt to read the first couple of pages of the
        split case PDF at ``catalog.output_pdf_path`` to include a
        text excerpt in the packet.  Silently skipped if PyMuPDF / the
        PDF isn't available.
    client:
        Pre-built OpenAI client. If None, one is constructed from the
        ``OPENAI_API_KEY`` env var (unless dry_run).
    """
    model = model or DEFAULT_MODEL
    audit_dir = Path(audit_dir) if audit_dir else Path("output/audit")

    df = catalog_df.copy()
    _ensure_writeback_columns(df)

    rows_to_classify = _select_rows_to_classify(df, force=force, limit=limit)
    if rows_to_classify.empty:
        logger.info(
            "No rows to classify (all %d rows already have "
            "difficulty_normalized and force=False).",
            len(df),
        )
        if not dry_run:
            _write_audit_outputs(df, [], [], audit_dir, model=model)
        return df

    calibration_examples = load_calibration_examples(df)
    logger.info(
        "Selected %d calibration examples across Easy/Medium/Hard.",
        len(calibration_examples),
    )

    if not dry_run and client is None:
        client = _build_openai_client()

    predictions: list[AuditRecord] = []
    failures: list[FailureRecord] = []
    needs_review: list[AuditRecord] = []

    for i, (idx, row) in enumerate(rows_to_classify.iterrows(), start=1):
        title = _row_title(row) or f"row_{idx}"
        case_text = _maybe_read_case_text(row, cases_root) if cases_root else None
        packet = build_difficulty_packet(row, case_text=case_text)

        logger.info("[%d/%d] Classifying: %s", i, len(rows_to_classify), title)

        if dry_run:
            logger.debug("Packet for %s:\n%s", title,
                         json.dumps(packet, indent=2, ensure_ascii=False))
            continue

        result = classify_case_difficulty(
            packet, calibration_examples,
            client=client, model=model,
        )
        timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")

        if not result.ok:
            failures.append(FailureRecord(
                case_title=title,
                source_pdf=str(row.get("source_pdf") or ""),
                error_type=result.error_type,
                error_message=result.error_message,
                prompt_hash=result.prompt_hash,
                attempts=result.attempts,
            ))
            continue

        data = result.data or {}
        df.at[idx, "difficulty_normalized"] = data["difficulty_normalized"]
        df.at[idx, "difficulty_score"] = data["difficulty_score"]
        df.at[idx, "difficulty_notes"] = data.get("difficulty_notes", "")
        df.at[idx, "difficulty_source"] = "openai_calibrated"
        df.at[idx, "difficulty_confidence"] = data.get("confidence", "")
        df.at[idx, "difficulty_model"] = result.model

        record = AuditRecord(
            case_title=title,
            source_school=str(row.get("source_school") or ""),
            source_year=str(row.get("source_year") or ""),
            source_pdf=str(row.get("source_pdf") or ""),
            difficulty_normalized_existing=str(
                row.get("difficulty_normalized") or ""
            ),
            difficulty_normalized_predicted=data["difficulty_normalized"],
            difficulty_score_predicted=f"{data['difficulty_score']:.2f}",
            difficulty_quant_predicted=_fmt_optional(data.get("difficulty_quant")),
            difficulty_qual_predicted=_fmt_optional(data.get("difficulty_qual")),
            difficulty_notes=data.get("difficulty_notes", ""),
            confidence=f"{data.get('confidence', 0):.3f}",
            model_name=result.model,
            prediction_timestamp=timestamp,
            prompt_hash=result.prompt_hash,
        )
        reasons = _review_reasons(data)
        if reasons:
            record.needs_review = True
            record.review_reasons = reasons
            needs_review.append(record)

        predictions.append(record)

    if not dry_run:
        _write_audit_outputs(
            df, predictions, failures, audit_dir,
            model=model, needs_review=needs_review,
            calibration_examples=calibration_examples,
        )
        _log_calibration_report(df, predictions)

    return df


# ── Helpers ──────────────────────────────────────────────────────────────────

def _ensure_writeback_columns(df: pd.DataFrame) -> None:
    for col in WRITE_BACK_COLUMNS:
        if col not in df.columns:
            df[col] = ""


def _select_rows_to_classify(
    df: pd.DataFrame,
    *,
    force: bool,
    limit: Optional[int],
) -> pd.DataFrame:
    if force:
        sub = df
    else:
        mask = df["difficulty_normalized"].apply(_is_blank)
        sub = df[mask]
    if limit is not None and limit >= 0:
        sub = sub.head(limit)
    return sub


def _row_title(row: pd.Series | dict) -> str:
    """Resolve a printable title for a row, with the same fallback chain
    used by ``build_difficulty_packet`` (case_title → case_title_raw →
    canonical_case_title → normalized_title)."""
    for field_name in (
        "case_title", "case_title_raw",
        "canonical_case_title", "normalized_title",
    ):
        val = row.get(field_name) if isinstance(row, dict) else row.get(field_name)
        if val is None:
            continue
        if isinstance(val, float) and pd.isna(val):
            continue
        s = str(val).strip()
        if s and s.lower() != "nan":
            return s
    return ""


def _is_blank(v: Any) -> bool:
    if v is None:
        return True
    if isinstance(v, float) and pd.isna(v):
        return True
    s = str(v).strip()
    return not s or s.lower() == "nan"


def _fmt_optional(v: Any) -> str:
    if v is None:
        return ""
    try:
        return f"{float(v):.2f}"
    except (TypeError, ValueError):
        return str(v)


def _truncate(s: str, max_chars: int) -> str:
    s = s or ""
    if len(s) <= max_chars:
        return s
    return s[: max_chars - 1].rstrip() + "…"


def _review_reasons(data: dict[str, Any]) -> list[str]:
    reasons: list[str] = []
    try:
        conf = float(data.get("confidence", 0.0))
    except (TypeError, ValueError):
        conf = 0.0
    if conf < _LOW_CONFIDENCE_CUTOFF:
        reasons.append(f"low_confidence<{_LOW_CONFIDENCE_CUTOFF}")

    try:
        score = float(data.get("difficulty_score", 0.0))
    except (TypeError, ValueError):
        score = 0.0
    for boundary in _BOUNDARY_SCORES:
        if abs(score - boundary) <= _BOUNDARY_WINDOW:
            reasons.append(f"near_boundary_{boundary}")
            break
    return reasons


def _build_openai_client() -> Any:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError(
            "OPENAI_API_KEY is not set. Export it or pass --dry-run."
        )
    try:
        from openai import OpenAI  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "The `openai` package is not installed. "
            "Run `pip install -r requirements.txt`."
        ) from exc
    return OpenAI(api_key=api_key)


def _maybe_read_case_text(
    row: pd.Series | dict,
    cases_root: Optional[Path],
    max_pages: int = 3,
) -> Optional[str]:
    """Best-effort read of the first few pages of the split case PDF."""
    if cases_root is None:
        return None
    rel = row.get("output_pdf_path") if isinstance(row, dict) else row.get("output_pdf_path")
    if not rel or (isinstance(rel, float) and pd.isna(rel)):
        return None

    rel_str = str(rel)
    candidate = Path(rel_str)
    if not candidate.is_absolute():
        candidate = (cases_root / rel_str).resolve()

    if not candidate.exists():
        # Try interpreting rel as already rooted at cwd.
        alt = Path(rel_str)
        if alt.exists():
            candidate = alt
        else:
            return None

    try:
        import fitz  # type: ignore
    except ImportError:
        return None

    try:
        doc = fitz.open(str(candidate))
    except Exception as exc:
        logger.debug("Could not open %s for text extract: %s", candidate, exc)
        return None

    try:
        parts: list[str] = []
        for idx in range(min(max_pages, doc.page_count)):
            try:
                parts.append(doc.load_page(idx).get_text("text"))
            except Exception:
                continue
        return "\n".join(p for p in parts if p).strip() or None
    finally:
        doc.close()


# ── Audit output ─────────────────────────────────────────────────────────────

def _write_audit_outputs(
    df: pd.DataFrame,
    predictions: Iterable[AuditRecord],
    failures: Iterable[FailureRecord],
    audit_dir: Path,
    *,
    model: str,
    needs_review: Iterable[AuditRecord] = (),
    calibration_examples: Optional[list[dict]] = None,
) -> None:
    audit_dir.mkdir(parents=True, exist_ok=True)

    pred_rows = [
        {
            "case_title": r.case_title,
            "source_school": r.source_school,
            "source_year": r.source_year,
            "source_pdf": r.source_pdf,
            "difficulty_normalized_existing": r.difficulty_normalized_existing,
            "difficulty_normalized_predicted": r.difficulty_normalized_predicted,
            "difficulty_score_predicted": r.difficulty_score_predicted,
            "difficulty_quant_predicted": r.difficulty_quant_predicted,
            "difficulty_qual_predicted": r.difficulty_qual_predicted,
            "difficulty_notes": r.difficulty_notes,
            "confidence": r.confidence,
            "needs_review": "yes" if r.needs_review else "",
            "review_reasons": "; ".join(r.review_reasons),
            "model_name": r.model_name,
            "prediction_timestamp": r.prediction_timestamp,
            "prompt_hash": r.prompt_hash,
        }
        for r in predictions
    ]
    _write_csv(audit_dir / "llm_difficulty_predictions.csv", pred_rows)

    fail_rows = [
        {
            "case_title": r.case_title,
            "source_pdf": r.source_pdf,
            "error_type": r.error_type,
            "error_message": r.error_message,
            "attempts": r.attempts,
            "prompt_hash": r.prompt_hash,
        }
        for r in failures
    ]
    _write_csv(audit_dir / "llm_difficulty_failures.csv", fail_rows)

    review_rows = [
        {
            "case_title": r.case_title,
            "source_school": r.source_school,
            "source_year": r.source_year,
            "difficulty_normalized_predicted": r.difficulty_normalized_predicted,
            "difficulty_score_predicted": r.difficulty_score_predicted,
            "confidence": r.confidence,
            "review_reasons": "; ".join(r.review_reasons),
            "difficulty_notes": r.difficulty_notes,
            "model_name": r.model_name,
            "prediction_timestamp": r.prediction_timestamp,
        }
        for r in needs_review
    ]
    _write_csv(audit_dir / "llm_difficulty_needs_review.csv", review_rows)

    if calibration_examples:
        try:
            (audit_dir / "llm_difficulty_calibration_examples.json").write_text(
                json.dumps(
                    {"model": model, "examples": calibration_examples},
                    indent=2, ensure_ascii=False,
                ),
                encoding="utf-8",
            )
        except OSError as exc:
            logger.warning("Could not write calibration-examples audit: %s", exc)


def _write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        # Write header-only file for deterministic downstream consumption.
        pd.DataFrame().to_csv(path, index=False)
        return
    pd.DataFrame(rows).to_csv(path, index=False)


# ── Summary report ───────────────────────────────────────────────────────────

def _log_calibration_report(
    df: pd.DataFrame,
    predictions: list[AuditRecord],
) -> None:
    if not predictions:
        logger.info("No new predictions produced.")
        return

    logger.info("")
    logger.info("── LLM difficulty calibration report ─────────────────────────")
    pred_df = pd.DataFrame([
        {
            "source_school": r.source_school,
            "bucket": r.difficulty_normalized_predicted,
            "score": float(r.difficulty_score_predicted),
            "confidence": float(r.confidence),
            "case_title": r.case_title,
            "review_reasons": "; ".join(r.review_reasons),
        }
        for r in predictions
    ])

    bucket_counts = pred_df["bucket"].value_counts().to_dict()
    logger.info(
        "Predicted bucket counts: Easy=%d  Medium=%d  Hard=%d  (total=%d)",
        bucket_counts.get("Easy", 0),
        bucket_counts.get("Medium", 0),
        bucket_counts.get("Hard", 0),
        len(pred_df),
    )

    if not pred_df.empty:
        avg_by_school = (
            pred_df.groupby("source_school")["score"]
            .mean()
            .sort_values(ascending=False)
        )
        logger.info("Average predicted score by source_school:")
        for school, avg in avg_by_school.items():
            logger.info("  %-20s %.2f", school or "(unknown)", avg)

    low_conf = pred_df[pred_df["confidence"] < _LOW_CONFIDENCE_CUTOFF]
    if not low_conf.empty:
        logger.info("Low-confidence predictions (<%.2f):", _LOW_CONFIDENCE_CUTOFF)
        for _, r in low_conf.iterrows():
            logger.info("  %s  (%s, conf=%.2f)", r["case_title"], r["bucket"], r["confidence"])

    near_boundary = pred_df[pred_df["review_reasons"].str.contains("near_boundary", na=False)]
    if not near_boundary.empty:
        logger.info("Predictions near category boundaries:")
        for _, r in near_boundary.iterrows():
            logger.info("  %s  (%s, score=%.2f)", r["case_title"], r["bucket"], r["score"])
    logger.info("──────────────────────────────────────────────────────────────")


# ── Calibration evaluation ────────────────────────────────────────────────────

#: Success thresholds for the calibration QA pass.
EVAL_MIN_EXACT_MATCH = 0.70
EVAL_MAX_SCORE_GAP = 1.0


def evaluate_calibration(
    catalog_df: pd.DataFrame,
    *,
    sample_size: int = 30,
    model: Optional[str] = None,
    audit_dir: Optional[Path] = None,
    cases_root: Optional[Path] = None,
    client: Any = None,
    dry_run: bool = False,
    random_seed: int = 7,
) -> dict[str, Any]:
    """
    Re-classify a stratified sample of already-labeled cases and compare
    predictions against the existing labels. **Never modifies the catalog.**

    Produces:
      - ``output/audit/difficulty_calibration_eval.csv``
      - ``output/audit/difficulty_calibration_summary.json``

    Returns the summary dict.
    """
    model = model or DEFAULT_MODEL
    audit_dir = Path(audit_dir) if audit_dir else Path("output/audit")

    if "difficulty_normalized" not in catalog_df.columns:
        raise ValueError("Catalog has no difficulty_normalized column — nothing to evaluate.")

    labeled = catalog_df[catalog_df["difficulty_normalized"].isin(BUCKETS)].copy()
    if labeled.empty:
        raise ValueError("No rows with a labeled difficulty_normalized found in the catalog.")

    sample = _stratified_sample(labeled, sample_size, random_seed=random_seed)
    logger.info(
        "Evaluating %d labeled cases (stratified Easy/Medium/Hard) against the classifier.",
        len(sample),
    )

    sample_titles = [str(t).strip() for t in sample["case_title"].fillna("")]

    # Exclude the sampled cases from the calibration pool so we don't leak labels.
    calibration_examples = load_calibration_examples(
        catalog_df, exclude_titles=sample_titles,
    )
    logger.info(
        "Selected %d calibration anchors (excluding %d sampled cases).",
        len(calibration_examples),
        len(sample_titles),
    )

    if not dry_run and client is None:
        client = _build_openai_client()

    eval_rows: list[dict[str, Any]] = []
    failures: list[FailureRecord] = []

    for i, (idx, row) in enumerate(sample.iterrows(), start=1):
        title = _row_title(row) or f"row_{idx}"
        case_text = _maybe_read_case_text(row, cases_root) if cases_root else None
        # Strip the existing label from the packet so the model doesn't
        # just parrot it back.
        row_for_packet = _strip_existing_difficulty(row)
        packet = build_difficulty_packet(row_for_packet, case_text=case_text)

        logger.info("[%d/%d] Evaluating: %s", i, len(sample), title)

        if dry_run:
            logger.debug(
                "Packet for %s:\n%s", title,
                json.dumps(packet, indent=2, ensure_ascii=False),
            )
            continue

        result = classify_case_difficulty(
            packet, calibration_examples,
            client=client, model=model,
        )
        timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")

        if not result.ok:
            failures.append(FailureRecord(
                case_title=title,
                source_pdf=str(row.get("source_pdf") or ""),
                error_type=result.error_type,
                error_message=result.error_message,
                prompt_hash=result.prompt_hash,
                attempts=result.attempts,
            ))
            continue

        data = result.data or {}
        existing_label = str(row.get("difficulty_normalized") or "").strip()
        predicted_label = data["difficulty_normalized"]
        existing_score = _coerce_float(row.get("difficulty_score"))
        predicted_score = float(data["difficulty_score"])
        score_gap = (
            abs(predicted_score - existing_score)
            if existing_score is not None else None
        )

        eval_rows.append({
            "case_title": title,
            "source_school": str(row.get("source_school") or ""),
            "source_year": _format_year(row.get("source_year")),
            "case_type_normalized": str(row.get("case_type_normalized") or ""),
            "existing_difficulty_normalized": existing_label,
            "predicted_difficulty_normalized": predicted_label,
            "existing_difficulty_score": "" if existing_score is None else f"{existing_score:.2f}",
            "predicted_difficulty_score": f"{predicted_score:.2f}",
            "score_gap": "" if score_gap is None else f"{score_gap:.2f}",
            "match_exact": "yes" if existing_label == predicted_label else "no",
            "confidence": f"{float(data.get('confidence', 0)):.3f}",
            "difficulty_notes": data.get("difficulty_notes", ""),
            "model_name": result.model,
            "prediction_timestamp": timestamp,
            "prompt_hash": result.prompt_hash,
        })

    if dry_run:
        logger.info("Dry run complete — no API calls made, no audit files written.")
        return {"dry_run": True, "sampled": len(sample)}

    audit_dir.mkdir(parents=True, exist_ok=True)
    eval_csv = audit_dir / "difficulty_calibration_eval.csv"
    _write_csv(eval_csv, eval_rows)
    _write_csv(
        audit_dir / "difficulty_calibration_failures.csv",
        [
            {
                "case_title": f.case_title,
                "source_pdf": f.source_pdf,
                "error_type": f.error_type,
                "error_message": f.error_message,
                "attempts": f.attempts,
                "prompt_hash": f.prompt_hash,
            }
            for f in failures
        ],
    )

    summary = _compute_calibration_summary(
        eval_rows, model=model, failures=len(failures),
    )
    summary["sample_size_requested"] = sample_size
    summary["sample_size_actual"] = len(sample)
    summary["eval_csv"] = str(eval_csv)

    summary_path = audit_dir / "difficulty_calibration_summary.json"
    summary_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    _log_calibration_eval_summary(summary)
    return summary


# ── Evaluation helpers ────────────────────────────────────────────────────────

def _strip_existing_difficulty(row: pd.Series | dict) -> dict:
    """Return a copy of the row with all difficulty fields blanked out.

    Used when building the evaluation packet so we never leak the
    existing label back to the model via ``raw_difficulty_hints``."""
    if isinstance(row, pd.Series):
        d = row.to_dict()
    else:
        d = dict(row)
    for col in (
        "difficulty", "difficulty_raw", "difficulty_normalized",
        "difficulty_score", "difficulty_rating", "difficulty_rating_source",
        "difficulty_quant", "difficulty_qual", "difficulty_math",
        "difficulty_structure", "difficulty_creativity",
        "difficulty_quant_category", "difficulty_visual_present",
        "difficulty_notes", "difficulty_source", "difficulty_confidence",
        "difficulty_model",
    ):
        if col in d:
            d[col] = ""
    return d


def _stratified_sample(
    labeled: pd.DataFrame,
    sample_size: int,
    *,
    random_seed: int = 7,
) -> pd.DataFrame:
    """Return a sample stratified across Easy/Medium/Hard with bucket-level
    diversification by (source_school, case_type_normalized)."""
    rng = random.Random(random_seed)

    # Target roughly equal counts per bucket, but don't exceed what exists.
    per_bucket_target = max(1, sample_size // 3)
    remainder = sample_size - per_bucket_target * 3

    picked: list[pd.Series] = []

    for i, bucket in enumerate(BUCKETS):
        target = per_bucket_target + (1 if i < remainder else 0)
        bucket_rows = labeled[labeled["difficulty_normalized"] == bucket].copy()
        if bucket_rows.empty:
            logger.warning("No labeled rows for bucket %s — skipping.", bucket)
            continue

        # Shuffle deterministically.
        bucket_rows = bucket_rows.sample(
            frac=1.0, random_state=random_seed + i,
        )

        # Diversify by (school, case_type) first.
        seen: set[tuple[str, str]] = set()
        diversified: list[pd.Series] = []
        leftovers: list[pd.Series] = []
        for _, r in bucket_rows.iterrows():
            key = (
                str(r.get("source_school", "")),
                str(r.get("case_type_normalized", "")),
            )
            if key in seen:
                leftovers.append(r)
            else:
                seen.add(key)
                diversified.append(r)

        combined = diversified + leftovers
        picked.extend(combined[:target])

    # If we ran short because a bucket was smaller than target, backfill.
    if len(picked) < sample_size:
        picked_titles = {str(r.get("case_title", "")).lower() for r in picked}
        extras = labeled[
            ~labeled["case_title"].fillna("").str.lower().isin(picked_titles)
        ]
        if not extras.empty:
            extras_shuf = extras.sample(frac=1.0, random_state=random_seed + 99)
            for _, r in extras_shuf.iterrows():
                if len(picked) >= sample_size:
                    break
                picked.append(r)

    sample_df = pd.DataFrame(picked).reset_index(drop=True)
    return sample_df.head(sample_size)


def _coerce_float(v: Any) -> Optional[float]:
    if v is None:
        return None
    if isinstance(v, float) and pd.isna(v):
        return None
    s = str(v).strip()
    if not s or s.lower() == "nan":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def _format_year(v: Any) -> str:
    f = _coerce_float(v)
    if f is None:
        s = str(v).strip() if v is not None else ""
        return "" if s.lower() == "nan" else s
    if float(int(f)) == f:
        return str(int(f))
    return f"{f:g}"


def _compute_calibration_summary(
    eval_rows: list[dict[str, Any]],
    *,
    model: str,
    failures: int,
) -> dict[str, Any]:
    total = len(eval_rows)
    if total == 0:
        return {
            "model": model,
            "n_predictions": 0,
            "n_failures": failures,
            "exact_match_rate": None,
            "warnings": ["no_predictions_recorded"],
            "status": "FAIL",
        }

    eval_df = pd.DataFrame(eval_rows)
    eval_df["score_gap_num"] = eval_df["score_gap"].apply(
        lambda v: float(v) if v not in (None, "") else None
    )

    n_matches = int((eval_df["match_exact"] == "yes").sum())
    exact_match_rate = n_matches / total

    # Match rate by existing-bucket.
    match_by_bucket: dict[str, dict[str, Any]] = {}
    for bucket in BUCKETS:
        sub = eval_df[eval_df["existing_difficulty_normalized"] == bucket]
        n = len(sub)
        if n == 0:
            match_by_bucket[bucket] = {"n": 0, "match_rate": None}
            continue
        matches = int((sub["match_exact"] == "yes").sum())
        match_by_bucket[bucket] = {
            "n": n,
            "match_rate": round(matches / n, 4),
        }

    # Confusion matrix: rows=existing, cols=predicted.
    confusion: dict[str, dict[str, int]] = {
        b: {c: 0 for c in BUCKETS} for b in BUCKETS
    }
    for _, r in eval_df.iterrows():
        ex = r["existing_difficulty_normalized"]
        pr = r["predicted_difficulty_normalized"]
        if ex in confusion and pr in confusion[ex]:
            confusion[ex][pr] += 1

    # Score gap statistics.
    gaps = [g for g in eval_df["score_gap_num"].tolist() if g is not None]
    avg_abs_gap = round(sum(gaps) / len(gaps), 3) if gaps else None
    max_gap = round(max(gaps), 3) if gaps else None

    # Worst disagreements: two-step bucket mismatches first, then largest score gaps.
    def _bucket_distance(a: str, b: str) -> int:
        rank = {"Easy": 0, "Medium": 1, "Hard": 2}
        if a not in rank or b not in rank:
            return 0
        return abs(rank[a] - rank[b])

    eval_df["bucket_distance"] = eval_df.apply(
        lambda r: _bucket_distance(
            r["existing_difficulty_normalized"],
            r["predicted_difficulty_normalized"],
        ),
        axis=1,
    )
    worst = (
        eval_df.sort_values(
            by=["bucket_distance", "score_gap_num"],
            ascending=[False, False],
            na_position="last",
        )
        .head(10)
    )
    worst_rows: list[dict[str, Any]] = []
    for _, r in worst.iterrows():
        if r["match_exact"] == "yes" and (r["score_gap_num"] or 0) < 1.0:
            continue
        worst_rows.append({
            "case_title": r["case_title"],
            "source_school": r["source_school"],
            "existing": r["existing_difficulty_normalized"],
            "predicted": r["predicted_difficulty_normalized"],
            "existing_score": r["existing_difficulty_score"],
            "predicted_score": r["predicted_difficulty_score"],
            "score_gap": r["score_gap"],
            "confidence": r["confidence"],
            "notes": r["difficulty_notes"],
        })

    # Disagreements by school.
    disagreement_by_school: dict[str, dict[str, Any]] = {}
    for school, sub in eval_df.groupby(eval_df["source_school"].fillna("")):
        n = len(sub)
        disagreements = int((sub["match_exact"] == "no").sum())
        disagreement_by_school[school or "(unknown)"] = {
            "n": n,
            "disagreements": disagreements,
            "disagreement_rate": round(disagreements / n, 4) if n else None,
        }

    warnings: list[str] = []
    if exact_match_rate < EVAL_MIN_EXACT_MATCH:
        warnings.append(
            f"exact_match_rate_below_threshold: {exact_match_rate:.2%} < "
            f"{EVAL_MIN_EXACT_MATCH:.0%}"
        )
    if avg_abs_gap is not None and avg_abs_gap > EVAL_MAX_SCORE_GAP:
        warnings.append(
            f"avg_abs_score_gap_above_threshold: {avg_abs_gap:.2f} > "
            f"{EVAL_MAX_SCORE_GAP:.2f}"
        )

    return {
        "model": model,
        "n_predictions": total,
        "n_failures": failures,
        "exact_match_rate": round(exact_match_rate, 4),
        "avg_abs_score_gap": avg_abs_gap,
        "max_score_gap": max_gap,
        "match_rate_by_bucket": match_by_bucket,
        "confusion_matrix": confusion,
        "disagreement_by_source_school": disagreement_by_school,
        "worst_disagreements": worst_rows,
        "thresholds": {
            "min_exact_match_rate": EVAL_MIN_EXACT_MATCH,
            "max_avg_abs_score_gap": EVAL_MAX_SCORE_GAP,
        },
        "warnings": warnings,
        "status": "FAIL" if warnings else "PASS",
    }


def _log_calibration_eval_summary(summary: dict[str, Any]) -> None:
    logger.info("")
    logger.info("── Calibration evaluation summary ────────────────────────────")
    logger.info(
        "Model: %s  |  n=%d predictions  |  %d failures",
        summary.get("model"),
        summary.get("n_predictions", 0),
        summary.get("n_failures", 0),
    )

    match = summary.get("exact_match_rate")
    if match is not None:
        logger.info("Exact label match rate: %.1f%%", 100 * match)

    gap = summary.get("avg_abs_score_gap")
    if gap is not None:
        logger.info("Avg |score gap|: %.2f   (max: %.2f)",
                    gap, summary.get("max_score_gap", 0.0))

    match_by_bucket = summary.get("match_rate_by_bucket") or {}
    if match_by_bucket:
        logger.info("Match rate by existing bucket:")
        for bucket in BUCKETS:
            info = match_by_bucket.get(bucket, {})
            rate = info.get("match_rate")
            if rate is None:
                logger.info("  %-6s n=%d  (no labeled rows)", bucket, info.get("n", 0))
            else:
                logger.info("  %-6s n=%d  match=%.1f%%",
                            bucket, info.get("n", 0), 100 * rate)

    cm = summary.get("confusion_matrix") or {}
    if cm:
        logger.info("Confusion matrix (rows=existing, cols=predicted):")
        header = "            " + "  ".join(f"{b:>6}" for b in BUCKETS)
        logger.info(header)
        for bucket in BUCKETS:
            row = cm.get(bucket, {})
            cells = "  ".join(f"{row.get(b, 0):>6}" for b in BUCKETS)
            logger.info("  %-8s  %s", bucket, cells)

    worst = summary.get("worst_disagreements") or []
    if worst:
        logger.info("Worst disagreements (top %d):", len(worst))
        for w in worst:
            logger.info(
                "  %-40s  %s -> %s   gap=%s  (conf=%s)",
                w["case_title"][:40],
                w["existing"] or "?",
                w["predicted"] or "?",
                w.get("score_gap", ""),
                w.get("confidence", ""),
            )

    warnings = summary.get("warnings") or []
    status = summary.get("status", "PASS")
    if warnings:
        logger.warning("Calibration status: %s", status)
        for w in warnings:
            logger.warning("  - %s", w)
    else:
        logger.info("Calibration status: %s", status)

    logger.info("──────────────────────────────────────────────────────────────")
