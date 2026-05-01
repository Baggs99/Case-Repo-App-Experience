"""
Cases repository — all SQL touching the `cases` table lives here.

Keeping SQL out of route handlers means:
  - the routes stay readable (just orchestration)
  - schema changes only ripple through one file
  - it's trivial to swap to async psycopg later without rewriting routes
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool


# ── Filter options (populate the dropdowns) ────────────────────────────────────

@dataclass(frozen=True)
class FilterOptions:
    industries:  list[str]
    case_types:  list[str]
    schools:     list[str]
    difficulties: list[str]


def get_filter_options() -> FilterOptions:
    """Return the distinct values for each filterable column.

    Cheap query (~3ms total): the indexes on these columns mean Postgres
    just walks the b-tree. No need to cache yet.
    """
    sql = """
        SELECT
          ARRAY(SELECT DISTINCT industry      FROM cases WHERE industry      IS NOT NULL ORDER BY 1) AS industries,
          ARRAY(SELECT DISTINCT case_type     FROM cases WHERE case_type     IS NOT NULL ORDER BY 1) AS case_types,
          ARRAY(SELECT DISTINCT source_school FROM cases WHERE source_school IS NOT NULL ORDER BY 1) AS schools;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql)
            row = cur.fetchone()

    return FilterOptions(
        industries  = row["industries"]  or [],
        case_types  = row["case_types"]  or [],
        schools     = row["schools"]     or [],
        difficulties = ["Easy", "Medium", "Hard"],
    )


# ── Search ─────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class SearchFilters:
    q:           Optional[str] = None  # free-text title search
    difficulty:  Optional[str] = None  # Easy | Medium | Hard
    industry:    Optional[str] = None
    case_type:   Optional[str] = None
    school:      Optional[str] = None

    @classmethod
    def from_query(cls, **kwargs) -> "SearchFilters":
        """Build from raw querystring values, normalizing empties to None."""
        def _norm(v: Optional[str]) -> Optional[str]:
            if v is None:
                return None
            v = v.strip()
            return v if v else None

        return cls(
            q          = _norm(kwargs.get("q")),
            difficulty = _norm(kwargs.get("difficulty")),
            industry   = _norm(kwargs.get("industry")),
            case_type  = _norm(kwargs.get("case_type")),
            school     = _norm(kwargs.get("school")),
        )

    def is_empty(self) -> bool:
        return all(v is None for v in (
            self.q, self.difficulty, self.industry, self.case_type, self.school,
        ))


# Single SQL string handles every combination of filters: each `IS NULL OR ...`
# clause short-circuits when the filter wasn't provided. Postgres optimises
# these at plan time so unused filters don't cost anything at runtime.
SEARCH_SQL = """
    SELECT
        id,
        case_title,
        source_school,
        source_year,
        industry,
        case_type,
        difficulty,
        difficulty_score,
        firm,
        page_count,
        pdf_path
    FROM cases
    WHERE
        (%(q)s::text IS NULL OR case_title ILIKE '%%' || %(q)s || '%%')
        AND (%(difficulty)s::text IS NULL OR difficulty    = %(difficulty)s)
        AND (%(industry)s::text   IS NULL OR industry      = %(industry)s)
        AND (%(case_type)s::text  IS NULL OR case_type     = %(case_type)s)
        AND (%(school)s::text     IS NULL OR source_school = %(school)s)
    ORDER BY
        difficulty_score NULLS LAST,
        case_title
    LIMIT %(limit)s;
"""

COUNT_SQL = """
    SELECT COUNT(*) AS total
    FROM cases
    WHERE
        (%(q)s::text IS NULL OR case_title ILIKE '%%' || %(q)s || '%%')
        AND (%(difficulty)s::text IS NULL OR difficulty    = %(difficulty)s)
        AND (%(industry)s::text   IS NULL OR industry      = %(industry)s)
        AND (%(case_type)s::text  IS NULL OR case_type     = %(case_type)s)
        AND (%(school)s::text     IS NULL OR source_school = %(school)s);
"""


def search_cases(filters: SearchFilters, *, limit: int = 100) -> tuple[list[dict], int]:
    """Run the search and return (rows, total_matching).

    `limit` caps how many rows we return for display; `total_matching`
    is the unbounded count so the UI can show "showing 100 of 247".
    """
    params = {
        "q":          filters.q,
        "difficulty": filters.difficulty,
        "industry":   filters.industry,
        "case_type":  filters.case_type,
        "school":     filters.school,
        "limit":      limit,
    }

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(SEARCH_SQL, params)
            rows = list(cur.fetchall())

            cur.execute(COUNT_SQL, params)
            total = cur.fetchone()["total"]

    return rows, total


# ── Single-case fetch ──────────────────────────────────────────────────────────

def get_case_by_id(case_id: int) -> Optional[dict]:
    """Return one row by primary key, or None if not found."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, case_title, normalized_title, source_school, source_year,
                       industry, case_type, difficulty, difficulty_score,
                       firm, interviewer_led, page_count, pdf_path,
                       created_at, updated_at
                FROM cases
                WHERE id = %s;
                """,
                (case_id,),
            )
            return cur.fetchone()
