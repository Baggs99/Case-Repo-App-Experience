"""
OpenAI-powered industry classifier.

Fills in ``industry`` for catalog rows that don't have one. Uses the
OpenAI **Responses API** with a strict **JSON schema** so every
response is directly parseable.

Mirrors the design of ``openai_difficulty_classifier.py`` and reuses
several of its helpers (client builder, PDF excerpt reader, title
fallback, write-csv) so the two enrichment steps stay symmetric.

Why a controlled taxonomy?
--------------------------
The existing ``industry`` column has ~113 unique strings across ~432
rows ("Tech" vs "Technology", "Pharma" vs "Pharmaceutical" vs
"Pharmaceuticals", a handful of garbage values, etc.). Rather than let
the model invent yet more variants, the schema restricts the output to
a small canonical taxonomy. Legacy strings on already-labeled rows are
left alone — only blank rows get filled.

Public API
----------
    INDUSTRY_TAXONOMY:           tuple[str, ...]
    build_industry_packet(row, case_text=None) -> dict
    load_industry_examples(catalog_df)        -> list[dict]
    classify_case_industry(packet, examples, *, client, model)
        -> ClassifyResult
    classify_missing_industries(
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
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional

import pandas as pd

# Reuse helpers from the difficulty classifier so the two stay symmetric.
from pipeline.enrichment.openai_difficulty_classifier import (
    _build_openai_client,
    _coerce_output_text,
    _is_blank,
    _maybe_read_case_text,
    _row_title,
    _supports_temperature,
    _truncate,
    _write_csv,
)

logger = logging.getLogger(__name__)


# ── Constants ────────────────────────────────────────────────────────────────

DEFAULT_MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.4")

#: Canonical industry taxonomy. Designed to cover every case in the catalog
#: while collapsing the messy legacy variants into stable buckets.
INDUSTRY_TAXONOMY: tuple[str, ...] = (
    "Technology",
    "Healthcare",
    "Pharmaceuticals",
    "Retail / CPG",
    "Food & Beverage",
    "Financial Services",
    "Private Equity",
    "Insurance",
    "Manufacturing",
    "Energy & Utilities",
    "Transportation & Logistics",
    "Automotive",
    "Aerospace & Defense",
    "Hospitality & Travel",
    "Real Estate",
    "Education",
    "Non-Profit",
    "Public Sector",
    "Media & Entertainment",
    "Sports",
    "Telecom",
    "Agriculture",
    "Chemicals & Materials",
    "Professional Services",
    "Other",
)

#: Mapping of canonical labels to the legacy strings that should be
#: treated as the same bucket when sourcing calibration examples. Keys
#: are canonical labels; values are sequences of acceptable variants
#: (matched case-insensitively, exact string match).
LEGACY_INDUSTRY_ALIASES: dict[str, tuple[str, ...]] = {
    "Technology":               ("Tech", "Tech/AI", "Social Media", "Streaming",
                                  "Online Dating", "Education Technology",
                                  "Financial Technology", "Fashion Retail / Tech",
                                  "Technology"),
    "Healthcare":               ("Healthcare",),
    "Pharmaceuticals":          ("Pharma", "Pharmaceutical", "Pharmaceuticals", "Bio-Pharma"),
    "Retail / CPG":             ("Retail", "Retail / CPG", "Retail & CPG", "Retail, CPG",
                                  "CPG", "Consumer Products", "Consumer Goods",
                                  "Consumer Packaged Goods", "Consumer", "Consumer/Retail",
                                  "Luxury Retail", "Personal Care", "Grocery",
                                  "Retail / Grocery", "Retail & Tech"),
    "Food & Beverage":          ("Food", "Food and Beverage", "Food & Beverage",
                                  "Food/aquaculture", "Restaurant"),
    "Financial Services":       ("Financial Services", "Financial", "Banking",
                                  "Investment Management, Natural Resources",
                                  "Financial / PE"),
    "Private Equity":           ("Private Equity", "PE", "PE & Food/Retail",
                                  "Private Equity, CPG"),
    "Insurance":                ("Insurance",),
    "Manufacturing":            ("Manufacturing", "Industrial Goods", "Industrials",
                                  "Industrial Products", "Industrial",
                                  "Engineering & Construction", "Construction"),
    "Energy & Utilities":       ("Energy", "Power & Utilities", "Oil & Gas",
                                  "Oil and Gas", "Energy (O&G)",
                                  "Energy, Utilities & Mining", "Energy/Utilities, Digital"),
    "Transportation & Logistics": ("Transportation", "Transportation & Logistics",
                                    "Airline", "Airlines", "Airlines / Transportation",
                                    "Aviation"),
    "Automotive":               ("Automotive",),
    "Aerospace & Defense":      ("Aerospace and Defense", "Defense"),
    "Hospitality & Travel":     ("Hospitality", "Hospitality & Leisure", "Travel",
                                  "Travel/Hospitality"),
    "Real Estate":              ("Real Estate", "Real Estate & Energy",
                                  "Technology & Real Estate"),
    "Education":                ("Education", "Education Services", "Higher Education",
                                  "Higher Ed / Non-Profit", "Education (Public Sector)",
                                  "Non-profit: Public Education"),
    "Non-Profit":               ("Non-Profit", "Non-Profits"),
    "Public Sector":            ("Public Sector", "Public Services", "Government",
                                  "Government & Public Sector", "Lobbyist",
                                  "Political Election"),
    "Media & Entertainment":    ("Entertainment", "Media", "Media & Entertainment",
                                  "Media / Entertainment", "Theatre/Producing",
                                  "Non-traditional: Music Record Label"),
    "Sports":                   ("Sports",),
    "Telecom":                  ("Telecom",),
    "Agriculture":              ("Agriculture", "Agriculture & Food", "Fisheries"),
    "Chemicals & Materials":    ("Chemicals",),
    "Professional Services":    ("Professional Services", "Services", "Recruiting",
                                  "Call Center"),
    "Other":                    ("Other", "Death Care", "Waste Management",
                                  "Sanitation", "Archaeology", "Nautical",
                                  "Fun / Random"),
}

#: How many calibration examples per bucket and overall. Industry is a
#: simpler classification than difficulty so a smaller anchor set is fine.
_EXAMPLES_PER_BUCKET = 1
_MAX_CALIBRATION_EXAMPLES = 18

#: Char caps on text passed to the model.
_PROMPT_EXCERPT_CAP = 800
_CASE_TEXT_CAP = 2400
_EXAMPLE_SUMMARY_CAP = 220

#: Retry behaviour.
_MAX_ATTEMPTS = 3
_BACKOFF_BASE_SECONDS = 2.0

#: Confidence threshold below which a prediction is flagged for review.
_LOW_CONFIDENCE_CUTOFF = 0.55

#: Catalog columns we may write back.
WRITE_BACK_COLUMNS = (
    "industry",
    "industry_secondary",
    "industry_notes",
    "industry_source",
    "industry_confidence",
    "industry_model",
)


# ── Structured output schema ─────────────────────────────────────────────────

INDUSTRY_SCHEMA: dict[str, Any] = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "industry": {
            "type": "string",
            "enum": list(INDUSTRY_TAXONOMY),
            "description": "Primary industry bucket. Pick the single best match from the enum.",
        },
        "industry_secondary": {
            "type": "string",
            "enum": list(INDUSTRY_TAXONOMY) + [""],
            "description": (
                "Optional secondary bucket if the case clearly straddles two "
                "industries (e.g. a fintech case is Technology + Financial "
                "Services). Empty string if not applicable."
            ),
        },
        "notes": {
            "type": "string",
            "description": "One short sentence explaining the choice.",
        },
        "confidence": {
            "type": "number",
            "minimum": 0.0,
            "maximum": 1.0,
            "description": "Self-rated confidence in [0,1].",
        },
    },
    "required": ["industry", "industry_secondary", "notes", "confidence"],
}


SYSTEM_PROMPT = """\
You are tagging consulting practice cases with their primary INDUSTRY.
Pick the single best industry bucket for each NEW CASE from the
controlled taxonomy in the schema. Use the calibration examples
provided to keep your labels consistent with the rest of the catalog.

Guidelines:
- Choose the industry of the *client* in the case, not the firm doing
  the analysis (e.g., a McKinsey case about a hospital chain is
  "Healthcare", not "Professional Services").
- Pharma / biotech / drug-makers go to "Pharmaceuticals".
  Hospitals, clinics, payers, and medical devices go to "Healthcare".
- Banks, asset managers, brokerages, fintech-style payments go to
  "Financial Services". PE / VC funds buying or evaluating companies
  go to "Private Equity" (regardless of the underlying target).
- Insurance carriers stand alone in "Insurance".
- Restaurants, beverages, packaged food → "Food & Beverage".
- Other retail (apparel, electronics, grocery, CPG) → "Retail / CPG".
- Airlines, rail, trucking, shipping, ports → "Transportation & Logistics".
  Carmakers / OEMs → "Automotive". Defense / aerospace → "Aerospace & Defense".
- Streaming, social media, SaaS, AI, edtech platforms → "Technology".
  Hardware-led telcos / carriers → "Telecom".
- Government, military procurement, election work → "Public Sector".
  Charities and NGOs → "Non-Profit". Universities and K-12 → "Education".
- If a case clearly straddles two industries, fill `industry_secondary`.
  Otherwise leave it as "".
- If the case is whimsical / hypothetical with no clear industry,
  use "Other" with a short explanation in `notes`.

Respond with the JSON object matching the provided schema, nothing else.
"""


# ── Calibration example selection ────────────────────────────────────────────

@dataclass
class IndustryExample:
    case_title: str
    canonical_industry: str
    legacy_industry: str
    case_type: str
    summary: str

    def to_dict(self) -> dict[str, Any]:
        d: dict[str, Any] = {
            "case_title": self.case_title,
            "industry": self.canonical_industry,
        }
        if self.case_type:
            d["case_type"] = self.case_type
        if self.summary:
            d["summary"] = _truncate(self.summary, _EXAMPLE_SUMMARY_CAP)
        if self.legacy_industry and self.legacy_industry != self.canonical_industry:
            d["legacy_label_in_catalog"] = self.legacy_industry
        return d


def _canonicalize(legacy: str) -> Optional[str]:
    """Map a legacy industry string to its canonical bucket.

    Returns the canonical bucket name if the input matches either a canonical
    label directly or any registered legacy variant (case-insensitively).
    Returns None for blanks, NaN, or strings not in the taxonomy.
    """
    if not legacy:
        return None
    s = legacy.strip()
    if not s or s.lower() == "nan":
        return None
    s_low = s.lower()
    for canonical in INDUSTRY_TAXONOMY:
        if canonical.lower() == s_low:
            return canonical
    for canonical, variants in LEGACY_INDUSTRY_ALIASES.items():
        for v in variants:
            if v.lower() == s_low:
                return canonical
    return None


def load_industry_examples(catalog_df: pd.DataFrame) -> list[dict]:
    """Pick a small, diverse calibration set covering as many buckets as
    possible. Prefers rows whose legacy ``industry`` already maps onto a
    canonical bucket; ignores garbage strings."""
    if "industry" not in catalog_df.columns:
        return []

    labeled = catalog_df[~catalog_df["industry"].apply(_is_blank)].copy()
    if labeled.empty:
        return []

    labeled["_canonical"] = labeled["industry"].apply(_canonicalize)
    labeled = labeled[labeled["_canonical"].notna()]
    if labeled.empty:
        return []

    examples: list[IndustryExample] = []
    seen_buckets: set[str] = set()

    for canonical in INDUSTRY_TAXONOMY:
        bucket_rows = labeled[labeled["_canonical"] == canonical]
        if bucket_rows.empty:
            continue

        bucket_rows = bucket_rows.sample(frac=1.0, random_state=42)
        picked_titles: set[str] = set()
        bucket_picks = 0
        for _, row in bucket_rows.iterrows():
            if bucket_picks >= _EXAMPLES_PER_BUCKET:
                break
            title = _row_title(row)
            if not title or title.lower() in picked_titles:
                continue
            picked_titles.add(title.lower())
            examples.append(_row_to_example(row, canonical))
            bucket_picks += 1
            seen_buckets.add(canonical)

    if len(examples) > _MAX_CALIBRATION_EXAMPLES:
        examples = examples[:_MAX_CALIBRATION_EXAMPLES]

    return [e.to_dict() for e in examples]


def _row_to_example(row: pd.Series, canonical: str) -> IndustryExample:
    summary_parts: list[str] = []
    for field_name in ("prompt_excerpt", "concepts_tested"):
        val = row.get(field_name)
        if isinstance(val, str) and val.strip() and val.strip().lower() != "nan":
            summary_parts.append(val.strip())

    ct = row.get("case_type_normalized") or row.get("case_type") or row.get("case_type_raw")
    legacy = str(row.get("industry") or "").strip()

    return IndustryExample(
        case_title=_row_title(row),
        canonical_industry=canonical,
        legacy_industry=legacy,
        case_type=str(ct or "").strip(),
        summary=" | ".join(summary_parts),
    )


# ── Packet building ──────────────────────────────────────────────────────────

def build_industry_packet(
    row: dict | pd.Series,
    case_text: Optional[str] = None,
) -> dict[str, Any]:
    """Build a compact, token-bounded dict describing one case for the model."""
    if isinstance(row, pd.Series):
        row = row.to_dict()

    def _get(k: str) -> Optional[str]:
        v = row.get(k)
        if v is None:
            return None
        if isinstance(v, float) and pd.isna(v):
            return None
        s = str(v).strip()
        return s or None

    packet: dict[str, Any] = {}
    title = _row_title(row)
    if title:
        packet["case_title"] = title

    for k in ("source_school", "source_year", "case_type_raw",
              "case_type_normalized", "firm"):
        val = _get(k)
        if val is None:
            continue
        if k == "source_year" and val.endswith(".0"):
            val = val[:-2]
        packet[k] = val

    concepts = _get("concepts_tested")
    if concepts:
        packet["concepts_tested"] = _truncate(concepts, 240)

    prompt_excerpt = _get("prompt_excerpt")
    if prompt_excerpt:
        packet["prompt_excerpt"] = _truncate(prompt_excerpt, _PROMPT_EXCERPT_CAP)

    if case_text:
        packet["case_text_excerpt"] = _truncate(case_text.strip(), _CASE_TEXT_CAP)

    for k in ("source_pdf", "output_pdf_path"):
        val = _get(k)
        if val is not None:
            packet[k] = val

    return packet


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


def classify_case_industry(
    packet: dict[str, Any],
    calibration_examples: list[dict],
    *,
    client: Any,
    model: str = DEFAULT_MODEL,
    temperature: float = 0.0,
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
            "Choose the single best industry bucket from the schema enum "
            "for the NEW CASE. Use the calibration examples to stay "
            "consistent with the existing catalog. Return only the JSON "
            "object matching the schema."
        ),
    }
    user_text = json.dumps(user_payload, ensure_ascii=False, indent=2)
    prompt_hash = hashlib.sha256(
        (SYSTEM_PROMPT + "\n" + user_text).encode("utf-8")
    ).hexdigest()[:16]

    request_kwargs: dict[str, Any] = {
        "model": model,
        "input": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_text},
        ],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "case_industry_label",
                "strict": True,
                "schema": INDUSTRY_SCHEMA,
            }
        },
    }
    if _supports_temperature(model):
        request_kwargs["temperature"] = temperature

    last_error: tuple[str, str] = ("", "")
    raw_output = ""

    for attempt in range(1, _MAX_ATTEMPTS + 1):
        try:
            try:
                response = client.responses.create(**request_kwargs)
            except Exception as inner:
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

        except Exception as exc:  # noqa: BLE001
            last_error = (type(exc).__name__, str(exc))
            logger.warning("OpenAI call failed on attempt %d: %s", attempt, exc)

        if attempt < _MAX_ATTEMPTS:
            time.sleep(_BACKOFF_BASE_SECONDS ** attempt)

    return ClassifyResult(
        ok=False, raw_output=raw_output, attempts=_MAX_ATTEMPTS,
        error_type=last_error[0] or "unknown",
        error_message=last_error[1] or "Unknown error",
        prompt_hash=prompt_hash, model=model,
    )


def _parse_and_validate(raw: str) -> Optional[dict[str, Any]]:
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        stripped = raw.strip().strip("`")
        if stripped.lower().startswith("json"):
            stripped = stripped[4:].lstrip()
        try:
            data = json.loads(stripped)
        except json.JSONDecodeError:
            return None
    if not isinstance(data, dict):
        return None
    required = {"industry", "industry_secondary", "notes", "confidence"}
    if not required.issubset(data):
        return None
    if data["industry"] not in INDUSTRY_TAXONOMY:
        return None
    secondary = data.get("industry_secondary", "")
    if secondary and secondary not in INDUSTRY_TAXONOMY:
        return None
    try:
        conf = float(data["confidence"])
    except (TypeError, ValueError):
        return None
    if not 0.0 <= conf <= 1.0:
        return None
    data["confidence"] = round(conf, 3)
    return data


# ── Orchestration ────────────────────────────────────────────────────────────

@dataclass
class AuditRecord:
    case_title: str = ""
    source_school: str = ""
    source_year: str = ""
    source_pdf: str = ""
    industry_existing: str = ""
    industry_predicted: str = ""
    industry_secondary: str = ""
    industry_notes: str = ""
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


def classify_missing_industries(
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
    """Fill missing ``industry`` values via the OpenAI Responses API.

    Mirrors ``classify_missing_difficulties`` for symmetry. Returns the
    updated DataFrame; never overwrites existing labels unless ``force``.
    """
    model = model or DEFAULT_MODEL
    audit_dir = Path(audit_dir) if audit_dir else Path("output/audit")

    df = catalog_df.copy()
    for col in WRITE_BACK_COLUMNS:
        if col not in df.columns:
            df[col] = ""

    rows_to_classify = _select_rows_to_classify(df, force=force, limit=limit)
    if rows_to_classify.empty:
        logger.info("No rows to classify (all rows already have industry).")
        if not dry_run:
            _write_audit_outputs(df, [], [], audit_dir, model=model)
        return df

    calibration_examples = load_industry_examples(df)
    logger.info(
        "Selected %d calibration examples across %d buckets.",
        len(calibration_examples),
        len({e.get("industry") for e in calibration_examples}),
    )

    if not dry_run and client is None:
        client = _build_openai_client()

    predictions: list[AuditRecord] = []
    failures: list[FailureRecord] = []
    needs_review: list[AuditRecord] = []

    for i, (idx, row) in enumerate(rows_to_classify.iterrows(), start=1):
        title = _row_title(row) or f"row_{idx}"
        case_text = _maybe_read_case_text(row, cases_root) if cases_root else None
        packet = build_industry_packet(row, case_text=case_text)

        logger.info("[%d/%d] Classifying: %s", i, len(rows_to_classify), title)

        if dry_run:
            logger.debug(
                "Packet for %s:\n%s", title,
                json.dumps(packet, indent=2, ensure_ascii=False),
            )
            continue

        result = classify_case_industry(
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
        df.at[idx, "industry"] = data["industry"]
        df.at[idx, "industry_secondary"] = data.get("industry_secondary", "")
        df.at[idx, "industry_notes"] = data.get("notes", "")
        df.at[idx, "industry_source"] = "openai_calibrated"
        df.at[idx, "industry_confidence"] = data.get("confidence", "")
        df.at[idx, "industry_model"] = result.model

        record = AuditRecord(
            case_title=title,
            source_school=str(row.get("source_school") or ""),
            source_year=str(row.get("source_year") or ""),
            source_pdf=str(row.get("source_pdf") or ""),
            industry_existing=str(row.get("industry") or ""),
            industry_predicted=data["industry"],
            industry_secondary=data.get("industry_secondary", ""),
            industry_notes=data.get("notes", ""),
            confidence=f"{float(data.get('confidence', 0)):.3f}",
            model_name=result.model,
            prediction_timestamp=timestamp,
            prompt_hash=result.prompt_hash,
        )
        if float(data.get("confidence", 0)) < _LOW_CONFIDENCE_CUTOFF:
            record.needs_review = True
            record.review_reasons.append(f"low_confidence<{_LOW_CONFIDENCE_CUTOFF}")
            needs_review.append(record)
        elif data["industry"] == "Other":
            record.needs_review = True
            record.review_reasons.append("predicted_other")
            needs_review.append(record)

        predictions.append(record)

    if not dry_run:
        _write_audit_outputs(
            df, predictions, failures, audit_dir,
            model=model, needs_review=needs_review,
            calibration_examples=calibration_examples,
        )
        _log_industry_report(predictions)

    return df


# ── Helpers ──────────────────────────────────────────────────────────────────

def _select_rows_to_classify(
    df: pd.DataFrame, *, force: bool, limit: Optional[int],
) -> pd.DataFrame:
    if force:
        sub = df
    else:
        sub = df[df["industry"].apply(_is_blank)]
    if limit is not None and limit >= 0:
        sub = sub.head(limit)
    return sub


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
            "industry_existing": r.industry_existing,
            "industry_predicted": r.industry_predicted,
            "industry_secondary": r.industry_secondary,
            "industry_notes": r.industry_notes,
            "confidence": r.confidence,
            "needs_review": "yes" if r.needs_review else "",
            "review_reasons": "; ".join(r.review_reasons),
            "model_name": r.model_name,
            "prediction_timestamp": r.prediction_timestamp,
            "prompt_hash": r.prompt_hash,
        }
        for r in predictions
    ]
    _write_csv(audit_dir / "llm_industry_predictions.csv", pred_rows)

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
    _write_csv(audit_dir / "llm_industry_failures.csv", fail_rows)

    review_rows = [
        {
            "case_title": r.case_title,
            "source_school": r.source_school,
            "source_year": r.source_year,
            "industry_predicted": r.industry_predicted,
            "industry_secondary": r.industry_secondary,
            "confidence": r.confidence,
            "review_reasons": "; ".join(r.review_reasons),
            "industry_notes": r.industry_notes,
            "model_name": r.model_name,
            "prediction_timestamp": r.prediction_timestamp,
        }
        for r in needs_review
    ]
    _write_csv(audit_dir / "llm_industry_needs_review.csv", review_rows)

    if calibration_examples:
        try:
            (audit_dir / "llm_industry_calibration_examples.json").write_text(
                json.dumps(
                    {"model": model, "examples": calibration_examples},
                    indent=2, ensure_ascii=False,
                ),
                encoding="utf-8",
            )
        except OSError as exc:
            logger.warning("Could not write calibration-examples audit: %s", exc)


def _log_industry_report(predictions: list[AuditRecord]) -> None:
    if not predictions:
        logger.info("No industry predictions produced.")
        return

    pred_df = pd.DataFrame([
        {
            "industry": r.industry_predicted,
            "secondary": r.industry_secondary,
            "confidence": float(r.confidence),
            "case_title": r.case_title,
            "review_reasons": "; ".join(r.review_reasons),
        }
        for r in predictions
    ])

    logger.info("")
    logger.info("── LLM industry classification report ────────────────────────")
    logger.info("Predicted bucket counts (n=%d):", len(pred_df))
    counts = pred_df["industry"].value_counts()
    for bucket, n in counts.items():
        logger.info("  %-26s %d", bucket, n)

    sec_counts = pred_df[pred_df["secondary"] != ""]["secondary"].value_counts()
    if not sec_counts.empty:
        logger.info("Secondary buckets used:")
        for bucket, n in sec_counts.items():
            logger.info("  %-26s %d", bucket, n)

    low_conf = pred_df[pred_df["confidence"] < _LOW_CONFIDENCE_CUTOFF]
    if not low_conf.empty:
        logger.info("Low-confidence predictions (<%.2f):", _LOW_CONFIDENCE_CUTOFF)
        for _, r in low_conf.iterrows():
            logger.info("  %-40s  -> %s  (conf=%.2f)",
                        r["case_title"][:40], r["industry"], r["confidence"])

    other = pred_df[pred_df["industry"] == "Other"]
    if not other.empty:
        logger.info("Predicted 'Other' (review recommended):")
        for _, r in other.iterrows():
            logger.info("  %-40s  (conf=%.2f)", r["case_title"][:40], r["confidence"])

    logger.info("──────────────────────────────────────────────────────────────")
