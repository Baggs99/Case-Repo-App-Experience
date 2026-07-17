"""
Cases repository — all SQL touching the `cases` table lives here.

Keeping SQL out of route handlers means:
  - the routes stay readable (just orchestration)
  - schema changes only ripple through one file
  - it's trivial to swap to async psycopg later without rewriting routes
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Optional
from urllib.parse import urlencode

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.industry_normalize import (
    attach_industry_display,
    industry_raws_matching_canonical,
    normalize_industry_label,
)


# ── Filter options (populate the dropdowns) ────────────────────────────────────

@dataclass(frozen=True)
class FilterOptions:
    industries:  list[str]
    case_types:  list[str]
    schools:     list[str]
    difficulties: list[str]


def _distinct_raw_industries() -> list[str]:
    """Distinct ``industry`` values as stored in the database."""
    sql = """
        SELECT DISTINCT industry
        FROM cases
        WHERE industry IS NOT NULL AND TRIM(industry) <> ''
        ORDER BY industry;
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            return [str(r[0]) for r in cur.fetchall()]


def _canonical_industry_options(raw_values: list[str]) -> list[str]:
    """Sorted unique canonical labels for the industry dropdown."""
    labels: set[str] = set()
    for raw in raw_values:
        c = normalize_industry_label(raw)
        if c:
            labels.add(c)
    return sorted(labels)


def get_filter_options() -> FilterOptions:
    """Return the distinct values for each filterable column.

    Industries are collapsed to canonical labels (see
    ``webapp.industry_normalize``) while the DB keeps raw strings.
    """
    raw_industries = _distinct_raw_industries()
    industries = _canonical_industry_options(raw_industries)

    sql = """
        SELECT
          ARRAY(SELECT DISTINCT case_type     FROM cases WHERE case_type     IS NOT NULL ORDER BY 1) AS case_types,
          ARRAY(SELECT DISTINCT source_school FROM cases WHERE source_school IS NOT NULL ORDER BY 1) AS schools;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql)
            row = cur.fetchone()

    return FilterOptions(
        industries  = industries,
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
    # Admin/debug toggle — when False (default), public search hides newer
    # duplicate copies and only returns the canonical (oldest) row per
    # normalized_title group. See ``pick_canonical_case_ids`` for the rule.
    include_duplicates: bool = False

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
            include_duplicates = _coerce_bool(kwargs.get("include_duplicates")),
        )

    def is_empty(self) -> bool:
        """True iff no content filter is set. ``include_duplicates`` is a
        view toggle, not a content filter, so it doesn't count here."""
        return all(v is None for v in (
            self.q, self.difficulty, self.industry, self.case_type, self.school,
        ))

    def to_query_string(self, *, include_blanks: bool = True) -> str:
        """Encode the filters as a ``key=value&...`` query string.

        ``include_blanks=True`` mirrors the form's submit shape (every field
        present, empty when unset) — keeping the resulting URL stable so it
        round-trips cleanly through ``hx-push-url`` and the browser cache.

        ``include_duplicates`` is appended only when truthy, so the public
        URL stays clean unless the override has been explicitly set.
        """
        pairs = [
            ("q",          self.q          or ""),
            ("difficulty", self.difficulty or ""),
            ("industry",   self.industry   or ""),
            ("case_type",  self.case_type  or ""),
            ("school",     self.school     or ""),
        ]
        if not include_blanks:
            pairs = [(k, v) for k, v in pairs if v]
        if self.include_duplicates:
            pairs.append(("include_duplicates", "1"))
        return urlencode(pairs)

    def to_search_url(self) -> str:
        """``/search?...`` URL that re-renders this filter set as a full page."""
        qs = self.to_query_string()
        return f"/search?{qs}" if qs else "/search"


_TRUTHY = {"1", "true", "yes", "y", "on"}


def _coerce_bool(val) -> bool:
    """Lenient bool parsing for query strings: accepts True, 1, "1", "true", etc."""
    if val is None:
        return False
    if isinstance(val, bool):
        return val
    if isinstance(val, (int, float)):
        return bool(val)
    return str(val).strip().lower() in _TRUTHY


# ── Duplicate hiding ───────────────────────────────────────────────────────────
#
# The publisher historically left stale rows in `cases` when a casebook
# re-published the same case under a new (school, year) pair. Public browse
# should show only the canonical (oldest) row per ``normalized_title`` group;
# admin pages and direct ``/cases/{id}`` URLs continue to see every row.
#
# Tie-break rule (mirrors the catalog's ``unique_case_count_eligible`` logic):
#   1. Lowest non-NULL ``source_year`` wins (NULL years rank last so we never
#      promote a year-less RocketBlocks row over a dated school original).
#   2. Lowest ``id`` breaks remaining ties.
#
# The same rule lives in SQL (``ROW_NUMBER`` window in SEARCH_SQL/COUNT_SQL)
# and in the pure-Python ``pick_canonical_case_ids`` helper used by tests.

def pick_canonical_case_ids(rows: Iterable[dict]) -> set[int]:
    """Return the set of ``id`` values that should remain visible after dedup.

    Each input row must carry ``id``, ``normalized_title``, and ``source_year``
    (year may be ``None``). Rows whose ``normalized_title`` is empty / None
    are treated as their own group (we only collapse exact-match titles, per
    requirement 2).

    Rows with ``is_duplicate_case`` true are excluded from grouping (they
    never appear in public deduped search).
    """
    canonical: dict[str, dict] = {}
    standalone: list[int] = []

    for r in rows:
        if r.get("is_duplicate_case"):
            continue
        nt = (r.get("normalized_title") or "").strip()
        rid = int(r["id"])
        year = r.get("source_year")

        if not nt:
            standalone.append(rid)
            continue

        prev = canonical.get(nt)
        if prev is None or _is_better_canonical(r, prev):
            canonical[nt] = r

    keep: set[int] = {int(r["id"]) for r in canonical.values()}
    keep.update(standalone)
    return keep


def _is_better_canonical(candidate: dict, current: dict) -> bool:
    """True iff ``candidate`` should replace ``current`` as the canonical row."""
    cand_year = candidate.get("source_year")
    curr_year = current.get("source_year")

    # NULL years rank last; otherwise lower year wins.
    if cand_year is None and curr_year is None:
        pass  # fall through to id tie-break
    elif cand_year is None:
        return False
    elif curr_year is None:
        return True
    else:
        if cand_year < curr_year:
            return True
        if cand_year > curr_year:
            return False

    # Same calendar year (including both NULL): prefer already-eligible rows.
    ce = bool(candidate.get("unique_case_count_eligible", True))
    ue = bool(current.get("unique_case_count_eligible", True))
    if ce != ue:
        return ce and not ue

    return int(candidate["id"]) < int(current["id"])


# Each `IS NULL OR ...` clause short-circuits when the filter wasn't provided
# — Postgres optimises these at plan time so unused filters cost nothing.
#
# The dedup variant wraps `cases` in a CTE that ranks rows per
# normalized_title (oldest source_year first, lowest id breaks ties), then
# only the rn=1 row is exposed to the WHERE/filter layer above. This means
# filters apply to the canonical row only — exactly the behaviour we want
# (newer copies are invisible to the public search regardless of filter).

_FILTER_WHERE = """
    (%(q)s::text IS NULL OR case_title ILIKE '%%' || %(q)s || '%%')
    AND (%(difficulty)s::text IS NULL OR difficulty    = %(difficulty)s)
    AND (
        CASE WHEN NOT %(industry_active)s THEN true
        ELSE industry = ANY(%(industry_raws)s::text[]) END
    )
    AND (%(case_type)s::text  IS NULL OR case_type     = %(case_type)s)
    AND (%(school)s::text     IS NULL OR source_school = %(school)s)
"""

_DEDUP_CTE = """
    WITH ranked AS (
        SELECT
            cs.id, cs.case_title, cs.normalized_title,
            cs.source_school, cs.source_year,
            cs.industry, cs.case_type, cs.difficulty, cs.difficulty_score,
            cs.firm, cs.page_count, cs.pdf_path,
            ROW_NUMBER() OVER (
                -- Empty / NULL normalized_title rows must NOT collapse into
                -- one another; bucket each by a synthetic per-row key so
                -- they all survive as their own canonical.
                PARTITION BY COALESCE(NULLIF(cs.normalized_title, ''), '__id_' || cs.id::text)
                ORDER BY
                    cs.source_year ASC NULLS LAST,
                    CASE WHEN COALESCE(cs.unique_case_count_eligible, true) THEN 0 ELSE 1 END ASC,
                    cs.id ASC
            ) AS rn
        FROM cases cs
        WHERE NOT COALESCE(cs.is_duplicate_case, false)
    )
"""

SEARCH_SQL_ALL = f"""
    SELECT
        id, case_title, source_school, source_year,
        industry, case_type, difficulty, difficulty_score,
        firm, page_count, pdf_path
    FROM cases
    WHERE {_FILTER_WHERE}
    ORDER BY difficulty_score NULLS LAST, case_title
    LIMIT %(limit)s;
"""

COUNT_SQL_ALL = f"""
    SELECT COUNT(*) AS total
    FROM cases
    WHERE {_FILTER_WHERE};
"""

SEARCH_SQL_DEDUP = f"""
    {_DEDUP_CTE}
    SELECT
        id, case_title, source_school, source_year,
        industry, case_type, difficulty, difficulty_score,
        firm, page_count, pdf_path
    FROM ranked
    WHERE rn = 1 AND {_FILTER_WHERE}
    ORDER BY difficulty_score NULLS LAST, case_title
    LIMIT %(limit)s;
"""

COUNT_SQL_DEDUP = f"""
    {_DEDUP_CTE}
    SELECT COUNT(*) AS total
    FROM ranked
    WHERE rn = 1 AND {_FILTER_WHERE};
"""

# Kept as aliases so any external imports of SEARCH_SQL / COUNT_SQL still work.
SEARCH_SQL = SEARCH_SQL_ALL
COUNT_SQL = COUNT_SQL_ALL


def _industry_filter_params(
    filters: SearchFilters, *, raw_distinct: list[str],
) -> dict[str, object]:
    """Build SQL params for canonical industry filtering."""
    if not filters.industry:
        return {"industry_active": False, "industry_raws": []}
    raws = industry_raws_matching_canonical(filters.industry, raw_distinct)
    return {"industry_active": True, "industry_raws": raws}


def search_cases(filters: SearchFilters, *, limit: int = 100) -> tuple[list[dict], int]:
    """Run the search and return (rows, total_matching).

    Honours ``filters.include_duplicates``: when False (default), the SQL
    layer collapses each ``normalized_title`` group to its canonical row
    before applying filters; when True, every row is searchable.

    ``limit`` caps how many rows we return for display; ``total_matching``
    is the unbounded count so the UI can show "showing 100 of 247".
    """
    raw_distinct = _distinct_raw_industries()
    params: dict[str, object] = {
        "q":          filters.q,
        "difficulty": filters.difficulty,
        "case_type":  filters.case_type,
        "school":     filters.school,
        "limit":      limit,
    }
    params.update(_industry_filter_params(filters, raw_distinct=raw_distinct))

    if filters.include_duplicates:
        search_sql = SEARCH_SQL_ALL
        count_sql = COUNT_SQL_ALL
    else:
        search_sql = SEARCH_SQL_DEDUP
        count_sql = COUNT_SQL_DEDUP

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(search_sql, params)
            rows = list(cur.fetchall())

            cur.execute(count_sql, params)
            total = cur.fetchone()["total"]

    for r in rows:
        attach_industry_display(r)
    return rows, total


def library_counts(filters: SearchFilters, user_id: int) -> dict:
    """{"open_count", "done_count"} over the user's canonical (deduped) library
    matching `filters` — done = burned for the user. Reuses the search dedup CTE
    and filter clause so the counts track the active filter set."""
    raw_distinct = _distinct_raw_industries()
    params: dict[str, object] = {
        "q": filters.q, "difficulty": filters.difficulty,
        "case_type": filters.case_type, "school": filters.school,
        "user_id": user_id,
    }
    params.update(_industry_filter_params(filters, raw_distinct=raw_distinct))
    sql = f"""
        {_DEDUP_CTE}
        SELECT
            COUNT(*) FILTER (WHERE b.user_id IS NOT NULL) AS done_count,
            COUNT(*) FILTER (WHERE b.user_id IS NULL)     AS open_count
        FROM ranked
        LEFT JOIN burned b ON b.case_id = ranked.id AND b.user_id = %(user_id)s
        WHERE ranked.rn = 1 AND {_FILTER_WHERE};
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, params)
            row = cur.fetchone()
    return {"open_count": int(row["open_count"] or 0),
            "done_count": int(row["done_count"] or 0)}


def count_all_cases(*, include_duplicates: bool = False) -> int:
    """Return total case count for the footer / "showing X of Y" text.

    Mirrors ``search_cases`` dedup behaviour: by default counts canonicals
    only, so the public-facing total reflects what's actually browsable.
    """
    if include_duplicates:
        sql = "SELECT COUNT(*) FROM cases;"
    else:
        # Same partition rule as SEARCH_SQL_DEDUP, after excluding rows the
        # operator marked ``is_duplicate_case`` (cross-title dupes).
        sql = f"""
            {_DEDUP_CTE}
            SELECT COUNT(*) AS total
            FROM ranked
            WHERE rn = 1;
        """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
            row = cur.fetchone()
            return int(row[0] or 0)


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
                       preview_public_slug,
                       is_duplicate_case, unique_case_count_eligible,
                       created_at, updated_at
                FROM cases
                WHERE id = %s;
                """,
                (case_id,),
            )
            row = cur.fetchone()
            if row:
                attach_industry_display(row)
            return row


def fetch_or_assign_preview_slug(conn, case_id: int) -> str:
    """Return ``preview_public_slug`` for the case; assign an opaque slug if absent."""
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE cases
            SET preview_public_slug = REPLACE(gen_random_uuid()::text, '-', '')
            WHERE id = %s AND preview_public_slug IS NULL
            RETURNING preview_public_slug;
            """,
            (case_id,),
        )
        inserted = cur.fetchone()
        if inserted and inserted[0]:
            return str(inserted[0])

        cur.execute(
            "SELECT preview_public_slug FROM cases WHERE id = %s;",
            (case_id,),
        )
        existing = cur.fetchone()
        if not existing or not existing[0]:
            raise LookupError(f"case id {case_id} has no preview_public_slug")
        return str(existing[0])
