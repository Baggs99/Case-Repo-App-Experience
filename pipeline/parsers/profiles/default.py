"""
Parsing profiles — default and school-specific variants.

A CasebookProfile bundles the heuristic parameters that differ across
schools: which section headers to look for, whether a TOC is expected,
whether all files from this source are already single-case, etc.

Each school factory (create_booth_profile, …) starts from the default
and overrides only the fields that differ.  This makes diffs obvious and
keeps profiles easy to audit.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional


# ── Shared defaults ───────────────────────────────────────────────────────────

DEFAULT_SECTION_HEADERS: List[str] = [
    "Prompt",
    "Background",
    "Case Background",
    "Clarifying Information",
    "Clarifying Questions",
    "Additional Information",
    "Exhibits",
    "Exhibit 1",
    "Exhibit A",
    "Conclusion",
    "Suggested Framework",
    "Sample Framework",
    "Potential Framework",
    "Case Information",
    "Interviewer Guide",
    "Candidate Handout",
    "Answer",
    "Solution",
    "Overview",
    "Question",
    "Case Overview",
    "Framework",
]

DEFAULT_TOC_INDICATORS: List[str] = [
    "Table of Contents",
    "Contents",
    "Cases in This Guide",
    "Cases in this Casebook",
    "Index of Cases",
    "Case List",
    "Case Index",
    "List of Cases",
]


# ── Profile dataclass ─────────────────────────────────────────────────────────

@dataclass
class CasebookProfile:
    """
    Heuristic parameters for a single school's casebook format.

    Fields:
        name                  Matches the school slug in known_schools config.
        preferred_parser      "auto" | "toc_driven" | "header_pattern" | "single_case"
                              "auto" = try TOC first, fall back to header pattern.
        section_headers       Strings to look for when detecting case structure.
        toc_indicators        Phrases that indicate a page is a TOC.
        case_number_prefix    E.g. "Case" if cases are labelled "Case 1:", "Case 2:".
                              None = no numbered prefix expected.
        min_case_pages_override   Override config min_case_pages for this school.
        max_case_pages_override   Override config max_case_pages for this school.
        always_single_case    If True the pipeline skips boundary detection and
                              treats every PDF as already a single case (RocketBlocks).
    """

    name: str = "default"
    preferred_parser: str = "auto"
    section_headers: List[str] = field(
        default_factory=lambda: list(DEFAULT_SECTION_HEADERS)
    )
    toc_indicators: List[str] = field(
        default_factory=lambda: list(DEFAULT_TOC_INDICATORS)
    )
    case_number_prefix: Optional[str] = None
    min_case_pages_override: Optional[int] = None
    max_case_pages_override: Optional[int] = None
    always_single_case: bool = False


# ── Factory functions ─────────────────────────────────────────────────────────

def create_default_profile() -> CasebookProfile:
    return CasebookProfile(name="default")


def create_booth_profile() -> CasebookProfile:
    """
    Booth casebooks typically:
    - Have a clear TOC with numbered cases ("Case 1:", "Case 2:", …)
    - Use "Case Overview" and "Framework" as section headers
    """
    return CasebookProfile(
        name="booth",
        preferred_parser="toc_driven",
        case_number_prefix="Case",
        section_headers=DEFAULT_SECTION_HEADERS + ["Case Overview", "Framework"],
        toc_indicators=DEFAULT_TOC_INDICATORS,
    )


def create_yale_profile() -> CasebookProfile:
    """
    Yale / Ross / Darden casebooks typically have clean TOCs.
    No special overrides needed beyond preferring the TOC parser.
    """
    return CasebookProfile(
        name="yale",
        preferred_parser="toc_driven",
        toc_indicators=DEFAULT_TOC_INDICATORS + ["Cases", "Case Studies"],
    )


def create_rocketblocks_profile() -> CasebookProfile:
    """
    RocketBlocks distributes individual case PDFs, so each file IS one case.
    Skip boundary detection entirely.
    """
    return CasebookProfile(
        name="rocketblocks",
        preferred_parser="single_case",
        always_single_case=True,
    )
