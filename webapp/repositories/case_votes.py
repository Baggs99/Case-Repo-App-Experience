"""
SQL for ``case_votes`` — one vote per user per case (useful / not_useful).
"""

from __future__ import annotations

from typing import Any, Literal, Optional

from psycopg.rows import dict_row

from webapp.db import get_pool

VoteType = Literal["useful", "not_useful"]


def _pct(useful: int, not_useful: int) -> Optional[float]:
    total = useful + not_useful
    if total <= 0:
        return None
    return round(100.0 * useful / total, 1)


def get_vote_state(case_id: int, user_id: int) -> dict[str, Any]:
    """Aggregate counts plus the current user's vote (if any)."""
    sql_counts = """
        SELECT
            COUNT(*) FILTER (WHERE vote_type = 'useful')::int AS useful_count,
            COUNT(*) FILTER (WHERE vote_type = 'not_useful')::int AS not_useful_count
        FROM case_votes
        WHERE case_id = %s;
    """
    sql_mine = """
        SELECT vote_type FROM case_votes
        WHERE case_id = %s AND user_id = %s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql_counts, (case_id,))
            row = cur.fetchone()
            useful = int(row["useful_count"] or 0)
            not_u = int(row["not_useful_count"] or 0)

            cur.execute(sql_mine, (case_id, user_id))
            mine = cur.fetchone()
            my_vote: str | None = mine["vote_type"] if mine else None

    return {
        "vote": my_vote,
        "useful_count": useful,
        "not_useful_count": not_u,
        "useful_percentage": _pct(useful, not_u),
    }


def apply_vote(
    case_id: int,
    user_id: int,
    requested: Optional[VoteType],
) -> dict[str, Any]:
    """
    Set, change, or clear a vote.

    * ``requested is None`` — delete the row (no vote).
    * ``requested`` matches current vote — delete (toggle off).
    * otherwise — insert or update to ``requested``.
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT vote_type FROM case_votes WHERE case_id = %s AND user_id = %s;",
                (case_id, user_id),
            )
            cur_row = cur.fetchone()
            current: str | None = cur_row[0] if cur_row else None

            if requested is None:
                if current is not None:
                    cur.execute(
                        "DELETE FROM case_votes WHERE case_id = %s AND user_id = %s;",
                        (case_id, user_id),
                    )
            elif current == requested:
                cur.execute(
                    "DELETE FROM case_votes WHERE case_id = %s AND user_id = %s;",
                    (case_id, user_id),
                )
            else:
                cur.execute(
                    """
                    INSERT INTO case_votes (case_id, user_id, vote_type)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (case_id, user_id)
                    DO UPDATE SET vote_type = EXCLUDED.vote_type,
                                  updated_at = NOW();
                    """,
                    (case_id, user_id, requested),
                )

    return get_vote_state(case_id, user_id)


# ── Admin listing ──────────────────────────────────────────────────────────────

ADMIN_SORT_SQL = {
    "title": "c.case_title ASC NULLS LAST",
    "useful_desc": "useful_count DESC NULLS LAST, c.case_title ASC",
    "useful_asc": "useful_count ASC NULLS LAST, c.case_title ASC",
    "not_useful_desc": "not_useful_count DESC NULLS LAST, c.case_title ASC",
    "not_useful_asc": "not_useful_count ASC NULLS LAST, c.case_title ASC",
    "most_voted": "total_votes DESC NULLS LAST, c.case_title ASC",
}


def list_cases_with_vote_stats(*, sort: str = "title", limit: int = 2000) -> list[dict[str, Any]]:
    """Return cases with vote aggregates for admin. ``sort`` must be a key in ADMIN_SORT_SQL."""
    order_sql = ADMIN_SORT_SQL.get(sort, ADMIN_SORT_SQL["title"])
    sql = f"""
        SELECT
            c.id,
            c.case_title,
            c.source_school,
            c.source_year,
            COUNT(*) FILTER (WHERE cv.vote_type = 'useful')::int AS useful_count,
            COUNT(*) FILTER (WHERE cv.vote_type = 'not_useful')::int AS not_useful_count,
            COUNT(cv.id)::int AS total_votes
        FROM cases c
        LEFT JOIN case_votes cv ON cv.case_id = c.id
        GROUP BY c.id
        ORDER BY {order_sql}
        LIMIT %(limit)s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, {"limit": limit})
            rows = list(cur.fetchall())

    for r in rows:
        u = int(r["useful_count"] or 0)
        n = int(r["not_useful_count"] or 0)
        r["useful_percentage"] = _pct(u, n)
    return rows
