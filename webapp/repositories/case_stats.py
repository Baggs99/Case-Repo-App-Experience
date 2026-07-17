"""
Purpose: Per-case rating aggregates for the Library — average close-out rating,
         run count (finalized sessions), and whether the case is burned for the
         requesting user (done_for_you).
Inputs:  practice_sessions, feedback, burned (via get_pool).
Outputs: dict keyed by case_id; no side effects.
Run:     from webapp.repositories import case_stats
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool


def case_aggregates(case_ids: list[int], user_id: int) -> dict[int, dict]:
    """{case_id: {avg_rating: float|None (1dp), run_count: int, done_for_you: bool}}
    for the given ids. Cases with no finalized runs get run_count 0 / avg None."""
    result = {cid: {"avg_rating": None, "run_count": 0, "done_for_you": False}
              for cid in case_ids}
    if not case_ids:
        return result
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT ps.case_id,"
                "       COUNT(*) AS run_count,"
                "       ROUND(AVG(f.case_rating)::numeric, 1) AS avg_rating"
                " FROM practice_sessions ps JOIN feedback f ON f.session_id = ps.id"
                " WHERE ps.case_id = ANY(%(ids)s) AND ps.state = 'finalized'"
                " GROUP BY ps.case_id;",
                {"ids": case_ids})
            for row in cur.fetchall():
                result[row["case_id"]].update(
                    run_count=row["run_count"],
                    avg_rating=(float(row["avg_rating"])
                                if row["avg_rating"] is not None else None))
            cur.execute("SELECT case_id FROM burned WHERE user_id = %(u)s"
                        " AND case_id = ANY(%(ids)s);",
                        {"u": user_id, "ids": case_ids})
            for row in cur.fetchall():
                result[row["case_id"]]["done_for_you"] = True
    return result
