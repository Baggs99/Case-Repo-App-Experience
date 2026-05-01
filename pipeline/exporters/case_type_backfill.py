"""
Deterministic case_type (and industry) backfill for rows where those fields
are blank.

Strategy
--------
RocketBlocks encodes both the case type and industry directly in the PDF
filename slug, e.g.::

    RocketBlocks-Case-23-market-entry-energy.pdf
                        ^^^^^^^^^^^^^ ^^^^^^
                        case_type     industry hint

We extract the slug portion (everything after ``Case-N-``), then scan it
against an ordered list of patterns — longest-match first to prefer the most
specific rule.

Only fills blanks — never overwrites a value that was set by a ground-truth
enrichment module or the manifest.
"""

from __future__ import annotations

import logging
import re
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


# ── Case type patterns ─────────────────────────────────────────────────────────
# Ordered longest → shortest so the most specific match wins first.
# Each entry: (slug_fragment, canonical_case_type)

_CASE_TYPE_PATTERNS: list[tuple[str, str]] = [
    # Compound / specific patterns (checked first)
    ("competitive-response-automotive-manufacturing", "Competitive Response"),
    ("competitive-response-healthcare-financing",    "Competitive Response"),
    ("competitive-response-food-delivery",           "Competitive Response"),
    ("competitive-response-hotel-tourism",           "Competitive Response"),
    ("competitive-response-manufacturing",           "Competitive Response"),
    ("competitive-response-delivery",                "Competitive Response"),
    ("competitive-response-retail",                  "Competitive Response"),
    ("retail-competitive-response",                  "Competitive Response"),
    ("business-response-food-manufacturing",         "Competitive Response"),
    ("business-response-fast-food",                  "Competitive Response"),
    ("retail-business-response",                     "Competitive Response"),
    ("operations-consumer-packaged-goods",           "Operations"),
    ("operations-technology-company",                "Operations"),
    ("operations-manufacturing",                     "Operations"),
    ("operations-ai-healthcare",                     "Operations"),
    ("public-sector-operations",                     "Operations"),
    ("public-sector-growth",                         "Growth Strategy"),
    ("public-sector-transportation",                 "Operations"),
    ("technology-market-entry",                      "Market Entry"),
    ("market-entry-rail-transportation",             "Market Entry"),
    ("market-entry-payment-cards",                   "Market Entry"),
    ("market-entry-restaurant",                      "Market Entry"),
    ("market-entry-energy",                          "Market Entry"),
    ("market-entry-retail",                          "Market Entry"),
    ("media-market-entry",                           "Market Entry"),
    ("profitability-consumer-internet",              "Profitability"),
    ("profitability-pharmaceutical",                 "Profitability"),
    ("profitability-technology",                     "Profitability"),
    ("profitability-retail",                         "Profitability"),
    ("food-and-beverage-growth",                     "Growth Strategy"),
    ("airlines-growth",                              "Growth Strategy"),
    ("growth-healthcare",                            "Growth Strategy"),
    ("growth-brewery",                               "Growth Strategy"),
    ("growth-strava",                                "Growth Strategy"),
    ("growth-media",                                 "Growth Strategy"),
    ("strategy-public-sector",                       "Strategy"),
    ("strategy-airline-carrier",                     "Strategy"),
    ("strategy-energy-subsidy",                      "Strategy"),
    ("airlines-technology",                          "Strategy"),
    ("investment-decision",                          "Investment Decision"),
    ("human-resources",                              "Human Resources"),
    ("cost-reduction",                               "Cost Reduction"),
    ("pricing-tariff",                               "Pricing"),
    ("pricing-hotel",                                "Pricing"),
    # Generic / single-word patterns (checked last)
    ("competitive-response",                         "Competitive Response"),
    ("business-response",                            "Competitive Response"),
    ("market-entry",                                 "Market Entry"),
    ("profitability",                                "Profitability"),
    ("growth",                                       "Growth Strategy"),
    ("m-and-a",                                      "M&A"),
    ("operations",                                   "Operations"),
    ("pricing",                                      "Pricing"),
    ("implementation",                               "Implementation"),
    ("strategy",                                     "Strategy"),
]

# ── Industry patterns ──────────────────────────────────────────────────────────
# Only applied when industry is also blank.  Same longest-first ordering.

_INDUSTRY_PATTERNS: list[tuple[str, str]] = [
    ("food-and-beverage",       "Food & Beverage"),
    ("consumer-internet",       "Technology"),
    ("consumer-packaged-goods", "Consumer Goods"),
    ("healthcare-financing",    "Healthcare"),
    ("food-delivery",           "Food & Beverage"),
    ("food-manufacturing",      "Food & Beverage"),
    ("hotel-tourism",           "Hospitality"),
    ("social-media",            "Technology"),
    ("public-sector",           "Government & Public Sector"),
    ("payment-cards",           "Financial Services"),
    ("streaming-media",         "Media & Entertainment"),
    ("rail-transportation",     "Transportation & Logistics"),
    ("fast-food",               "Food & Beverage"),
    ("healthcare",              "Healthcare"),
    ("pharmaceutical",          "Healthcare"),
    ("restaurant",              "Food & Beverage"),
    ("construction",            "Engineering & Construction"),
    ("manufacturing",           "Industrials"),
    ("automotive",              "Automotive"),
    ("entertainment",           "Media & Entertainment"),
    ("retail",                  "Retail & CPG"),
    ("technology",              "Technology"),
    ("airlines",                "Airline"),
    ("airline",                 "Airline"),
    ("brewery",                 "Food & Beverage"),
    ("energy",                  "Energy, Utilities & Mining"),
    ("media",                   "Media & Entertainment"),
]


# ── Slug extractor ─────────────────────────────────────────────────────────────

# Matches both "RocketBlocks-Case-N-" and "RocketBlocks Case-N-" (with space),
# case-insensitively, stripping leading path and extension.
_SLUG_RE = re.compile(
    r"rocketblocks[\s-]+case[\s-]+\d+[\s-]+(.+?)(?:_\d+)?$",
    re.IGNORECASE,
)


def _extract_slug(source_pdf: str) -> str:
    """
    Return the type/industry slug portion of a RocketBlocks filename, lower-cased.

    Example::
        "RocketBlocks/RocketBlocks-Case-23-market-entry-energy.pdf"
        → "market-entry-energy"
    """
    stem = Path(source_pdf).stem          # strip directory and extension
    m    = _SLUG_RE.search(stem.lower())
    if m:
        return m.group(1).strip("-").strip()
    return stem.lower()


def _match_patterns(slug: str, patterns: list[tuple[str, str]]) -> str | None:
    """Return the first pattern value whose key appears in *slug*, or None."""
    for fragment, value in patterns:
        if fragment in slug:
            return value
    return None


# ── Canonical normalisation map ───────────────────────────────────────────────
# Fixes non-standard values that may have been set by heuristic extraction.
# Keys are lowercased for case-insensitive matching.

_CANONICALISE: dict[str, str] = {
    "growth":                "Growth Strategy",
    "market entry":          "Market Entry",
    "m&a":                   "M&A",
    "mergers and acquisitions": "M&A",
    "mergers & acquisitions":   "M&A",
    "investment":            "Investment Decision",
    "cost reduction":        "Cost Reduction",
    "competitive response":  "Competitive Response",
    "business response":     "Competitive Response",
    "human resources":       "Human Resources",
    "new product":           "New Product",
    "product launch":        "Product Launch",
    "opportunity assessment":"Opportunity Assessment",
}


def canonicalise_case_types(rows: list[dict[str, Any]]) -> int:
    """
    Normalise any non-standard case_type values to the controlled vocabulary.
    Only modifies RocketBlocks rows (gold-standard sources are left untouched).
    Returns the count of values that were changed.
    """
    changed = 0
    for row in rows:
        if not _is_rocketblocks(row):
            continue
        ct = (row.get("case_type") or "").strip()
        if not ct:
            continue
        canonical = _CANONICALISE.get(ct.lower())
        if canonical and canonical != ct:
            logger.debug("Canonicalised case_type %r → %r for %s", ct, canonical, row.get("source_pdf",""))
            row["case_type"] = canonical
            changed += 1
    if changed:
        logger.info("Canonicalised %d non-standard case_type values.", changed)
    return changed


# ── Public API ────────────────────────────────────────────────────────────────

def backfill_rocketblocks(rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict]:
    """
    Fill blank ``case_type`` (and ``industry``) values for RocketBlocks rows
    by parsing the source_pdf filename slug.

    Parameters
    ----------
    rows : List of catalog row dicts (modified in-place).

    Returns
    -------
    (rows, stats) where stats contains before/after counts and unresolved slugs.
    """
    before_ct = sum(
        1 for r in rows
        if _is_rocketblocks(r) and _is_blank(r.get("case_type"))
    )
    before_ind = sum(
        1 for r in rows
        if _is_rocketblocks(r) and _is_blank(r.get("industry"))
    )

    filled_ct  = 0
    filled_ind = 0
    unresolved: list[dict] = []

    for row in rows:
        if not _is_rocketblocks(row):
            continue

        source_pdf = row.get("source_pdf", "") or row.get("output_pdf_path", "")
        slug       = _extract_slug(source_pdf)

        # ── case_type ─────────────────────────────────────────────────────────
        if _is_blank(row.get("case_type")):
            ct = _match_patterns(slug, _CASE_TYPE_PATTERNS)
            if ct:
                row["case_type"] = ct
                filled_ct += 1
                logger.debug("Backfilled case_type=%r for %s", ct, source_pdf)
            else:
                unresolved.append({
                    "source_pdf": source_pdf,
                    "slug":       slug,
                    "field":      "case_type",
                })
                logger.warning("Could not infer case_type from slug %r (%s)", slug, source_pdf)

        # ── industry ──────────────────────────────────────────────────────────
        if _is_blank(row.get("industry")):
            ind = _match_patterns(slug, _INDUSTRY_PATTERNS)
            if ind:
                row["industry"] = ind
                filled_ind += 1
                logger.debug("Backfilled industry=%r for %s", ind, source_pdf)

    stats = {
        "rocketblocks_rows":       sum(1 for r in rows if _is_rocketblocks(r)),
        "case_type_before":        before_ct,
        "case_type_filled":        filled_ct,
        "case_type_after_missing": before_ct - filled_ct,
        "industry_before":         before_ind,
        "industry_filled":         filled_ind,
        "unresolved":              unresolved,
    }

    logger.info(
        "RocketBlocks backfill: case_type %d→%d filled (%d remain blank); "
        "industry %d→%d filled.",
        before_ct, filled_ct, before_ct - filled_ct,
        before_ind, filled_ind,
    )
    return rows, stats


def _is_rocketblocks(row: dict) -> bool:
    school = (row.get("source_school") or "").strip().lower()
    src    = (row.get("source_pdf")    or "").lower()
    return school == "rocketblocks" or "rocketblocks" in src


def _is_blank(val: Any) -> bool:
    if val is None:
        return True
    if isinstance(val, float):
        import math
        return math.isnan(val)
    return str(val).strip() in ("", "None", "nan", "NaN")
