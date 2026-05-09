"""
SQL for ``case_votes`` — one vote per user per case (useful / not_useful).
"""

from __future__ import annotations

import logging
from typing import Any, Literal, Optional

from psycopg.errors import UndefinedTable
from psycopg.rows import dict_row

from webapp.db import get_pool

logger = logging.getLogger(__name__)

VoteType = Literal["useful", "not_useful"]

EMPTY_VOTE_STATE: dict[str, Any] = {
    "vote": None,
    "useful_count": 0,
    "not_useful_count": 0,
    "useful_percentage": None,
}


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


def get_vote_state_safe(case_id: int, user_id: int) -> dict[str, Any]:
    """Like ``get_vote_state`` but returns empty aggregates if ``case_votes`` is missing.

    Deployments must run ``db/migrations/007_case_votes.sql``; until then case pages
    still render and voting buttons no-op at the API layer.
    """
    try:
        return get_vote_state(case_id, user_id)
    except UndefinedTable:
        logger.warning(
            "case_votes table missing — apply db/migrations/007_case_votes.sql "
            "(case_id=%s)",
            case_id,
        )
        return dict(EMPTY_VOTE_STATE)


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


def list_cases_with_vote_stats_safe(*, sort: str = "title", limit: int = 2000) -> list[dict[str, Any]]:
    """Same as ``list_cases_with_vote_stats`` but returns [] if ``case_votes`` is missing."""
    try:
        return list_cases_with_vote_stats(sort=sort, limit=limit)
    except UndefinedTable:
        logger.warning(
            "case_votes table missing — apply db/migrations/007_case_votes.sql "
            "(admin case list empty)"
        )
        return []


# ── Per-user vote views (admin) ────────────────────────────────────────────────

def list_votes_for_user(user_id: int, *, limit: int = 1000) -> list[dict[str, Any]]:
    """Return every vote a user has cast, joined with case metadata.

    Newest votes first (uses ``updated_at`` so toggling a vote bubbles it
    up — i.e. "voted_at" reflects the most recent action on that case).
    """
    sql = """
        SELECT
            cv.id           AS vote_id,
            cv.vote_type,
            cv.created_at,
            cv.updated_at   AS voted_at,
            c.id            AS case_id,
            c.case_title,
            c.source_school,
            c.source_year,
            c.industry,
            c.case_type,
            c.difficulty
        FROM case_votes cv
        JOIN cases c ON c.id = cv.case_id
        WHERE cv.user_id = %s
        ORDER BY cv.updated_at DESC, cv.id DESC
        LIMIT %s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (user_id, limit))
            return list(cur.fetchall())


def list_votes_for_user_safe(user_id: int, *, limit: int = 1000) -> list[dict[str, Any]]:
    """Same as ``list_votes_for_user`` but tolerates a missing ``case_votes`` table."""
    try:
        return list_votes_for_user(user_id, limit=limit)
    except UndefinedTable:
        logger.warning(
            "case_votes table missing — apply db/migrations/007_case_votes.sql "
            "(user_id=%s vote list empty)",
            user_id,
        )
        return []


def get_vote_counts_for_user(user_id: int) -> dict[str, Any]:
    """Aggregate useful / not-useful counts plus the most recent vote time for one user."""
    sql = """
        SELECT
            COUNT(*) FILTER (WHERE vote_type = 'useful')::int     AS useful_count,
            COUNT(*) FILTER (WHERE vote_type = 'not_useful')::int AS not_useful_count,
            COUNT(*)::int                                         AS total_count,
            MAX(updated_at)                                       AS last_voted_at
        FROM case_votes
        WHERE user_id = %s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (user_id,))
            row = cur.fetchone() or {}

    return {
        "useful_count":     int(row.get("useful_count") or 0),
        "not_useful_count": int(row.get("not_useful_count") or 0),
        "total_count":      int(row.get("total_count") or 0),
        "last_voted_at":    row.get("last_voted_at"),
    }


def get_vote_counts_for_user_safe(user_id: int) -> dict[str, Any]:
    """Same as ``get_vote_counts_for_user`` but returns zeros if ``case_votes`` is missing."""
    try:
        return get_vote_counts_for_user(user_id)
    except UndefinedTable:
        logger.warning(
            "case_votes table missing — apply db/migrations/007_case_votes.sql "
            "(user_id=%s counts zeroed)",
            user_id,
        )
        return {
            "useful_count":     0,
            "not_useful_count": 0,
            "total_count":      0,
            "last_voted_at":    None,
        }


def get_vote_counts_by_user(*, user_ids: Optional[list[int]] = None) -> dict[int, dict[str, int]]:
    """Bulk: return ``{user_id: {useful_count, not_useful_count, total_count}}``.

    When ``user_ids`` is None, returns counts for every user that has voted.
    Used by the admin Users page to render per-user aggregate columns in a
    single query (vs N+1).
    """
    if user_ids is not None and not user_ids:
        return {}

    sql = """
        SELECT
            user_id,
            COUNT(*) FILTER (WHERE vote_type = 'useful')::int     AS useful_count,
            COUNT(*) FILTER (WHERE vote_type = 'not_useful')::int AS not_useful_count,
            COUNT(*)::int                                         AS total_count,
            MAX(updated_at)                                       AS last_voted_at
        FROM case_votes
        {where}
        GROUP BY user_id;
    """
    where_clause = ""
    params: tuple = ()
    if user_ids is not None:
        where_clause = "WHERE user_id = ANY(%s)"
        params = (list(user_ids),)
    sql = sql.format(where=where_clause)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()

    return {
        int(r["user_id"]): {
            "useful_count":     int(r["useful_count"] or 0),
            "not_useful_count": int(r["not_useful_count"] or 0),
            "total_count":      int(r["total_count"] or 0),
            "last_voted_at":    r["last_voted_at"],
        }
        for r in rows
    }


def get_vote_counts_by_user_safe(*, user_ids: Optional[list[int]] = None) -> dict[int, dict[str, int]]:
    """Same as ``get_vote_counts_by_user`` but returns {} if ``case_votes`` is missing."""
    try:
        return get_vote_counts_by_user(user_ids=user_ids)
    except UndefinedTable:
        logger.warning(
            "case_votes table missing — apply db/migrations/007_case_votes.sql "
            "(per-user vote aggregates zeroed)"
        )
        return {}
