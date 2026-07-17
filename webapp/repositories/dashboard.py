"""
Dashboard repository — session history, per-dimension trends, and the three
§4.8 recommendation rules (CaseRoom spec Phase 9; SQL only, no ML).

Privacy (T9.3): every function here is keyed by the requesting user's id and
returns only sessions that user participated in; grades never appear in any
other-user surface. Adaptations: "highest-rated" = case_votes usefulness %
(DV-6); the difficulty ladder is Easy → Medium → Hard, tie-broken by
difficulty_score (DV-7).
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool

HISTORY_LIMIT = 50
TREND_WINDOW = 10          # last N finalized-as-candidate sessions
LADDER_MIN_GRADE = 4.0     # §4.8 rule 2 threshold over the last 3 grades

_LADDER = {"Easy": "Medium", "Medium": "Hard"}   # DV-7; Hard has no +1


def history(user_id: int, limit: int = HISTORY_LIMIT) -> list[dict]:
    """Finalized sessions the user took part in, newest first. The grade is
    session-scoped and both participants already see it post-finalize (P7),
    so it appears for interviewer rows too."""
    sql = """
        SELECT ps.id, ps.ended_at, c.case_title, c.id AS case_id,
               CASE WHEN ps.interviewer_id = %(u)s THEN 'interviewer'
                    ELSE 'candidate' END AS your_role,
               CASE WHEN ps.interviewer_id = %(u)s
                    THEN COALESCE(uc.display_name, split_part(uc.email::text, '@', 1))
                    ELSE COALESCE(ui.display_name, split_part(ui.email::text, '@', 1))
               END AS counterpart,
               f.grade
        FROM practice_sessions ps
        JOIN cases c ON c.id = ps.case_id
        JOIN users ui ON ui.id = ps.interviewer_id
        JOIN users uc ON uc.id = ps.candidate_id
        LEFT JOIN feedback f ON f.session_id = ps.id
        WHERE ps.state = 'finalized'
          AND (ps.interviewer_id = %(u)s OR ps.candidate_id = %(u)s)
        ORDER BY ps.ended_at DESC
        LIMIT %(limit)s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, {"u": user_id, "limit": limit})
            rows = cur.fetchall()
    for row in rows:
        if row["grade"] is not None:
            row["grade"] = float(row["grade"])
    return rows


def dimension_averages(user_id: int, window: int = TREND_WINDOW) -> list[dict]:
    """Per-dimension averages over the user's last `window` finalized
    sessions AS CANDIDATE, normalized to /5 (A11: avg of points/max_points
    × 5, so mixed templates compare fairly). One GROUP BY over
    feedback.rubric_json extractions, per §4.8."""
    sql = """
        WITH recent AS (
            SELECT f.rubric_json, rt.items_json
            FROM practice_sessions ps
            JOIN feedback f ON f.session_id = ps.id
            JOIN rubric_templates rt ON rt.id = ps.rubric_template_id
            WHERE ps.state = 'finalized' AND ps.candidate_id = %(u)s
            ORDER BY ps.ended_at DESC
            LIMIT %(window)s
        ),
        scored AS (
            SELECT item->>'dimension' AS dimension,
                   COALESCE((recent.rubric_json->'items'->(item->>'id')->>'points')::numeric, 0)
                       / NULLIF((item->>'max_points')::numeric, 0) AS ratio
            FROM recent, jsonb_array_elements(recent.items_json) AS item
        )
        SELECT dimension,
               ROUND(AVG(ratio) * 5, 2)::float AS avg_score,
               COUNT(*)::int AS samples
        FROM scored
        WHERE dimension IS NOT NULL
        GROUP BY dimension
        ORDER BY avg_score;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, {"u": user_id, "window": window})
            return cur.fetchall()


# ── §4.8 recommendation rules — each one bounded query ───────────────────────

_ELIGIBLE = """
    c.pdf_path IS NOT NULL
    AND NOT COALESCE(c.is_duplicate_case, FALSE)
    AND NOT EXISTS (SELECT 1 FROM burned b
                    WHERE b.user_id = %(u)s AND b.case_id = c.id)
    AND NOT EXISTS (SELECT 1 FROM queue_want qw
                    WHERE qw.user_id = %(u)s AND qw.case_id = c.id)
    AND NOT EXISTS (SELECT 1 FROM queue_give qg
                    WHERE qg.user_id = %(u)s AND qg.case_id = c.id)
    AND c.id <> ALL(%(exclude)s::int[])
"""

_RATING = """
    (SELECT COALESCE(
        100.0 * COUNT(*) FILTER (WHERE cv.vote_type = 'useful')
              / NULLIF(COUNT(*), 0), 0)
     FROM case_votes cv WHERE cv.case_id = c.id)
"""


def _rule_coverage_gap(cur, user_id: int, exclude_case_ids: list[int]) -> dict | None:
    """Rule 1: the case type with the fewest finalized candidate-sessions →
    highest-usefulness eligible case of that type."""
    cur.execute(
        f"""
        WITH counts AS (
            SELECT ct.case_type,
                   COUNT(ps.id) FILTER (WHERE ps.candidate_id = %(u)s
                                        AND ps.state = 'finalized') AS n
            FROM (SELECT DISTINCT case_type FROM cases
                  WHERE case_type IS NOT NULL) ct
            LEFT JOIN cases pc ON pc.case_type = ct.case_type
            LEFT JOIN practice_sessions ps
                   ON ps.case_id = pc.id AND ps.candidate_id = %(u)s
                  AND ps.state = 'finalized'
            GROUP BY ct.case_type
            ORDER BY n, ct.case_type
            LIMIT 1
        )
        SELECT c.id, c.case_title, c.case_type, c.difficulty,
               {_RATING} AS rating
        FROM cases c JOIN counts ON c.case_type = counts.case_type
        WHERE {_ELIGIBLE}
        ORDER BY rating DESC, c.difficulty_score, c.id
        LIMIT 1;
        """,
        {"u": user_id, "exclude": exclude_case_ids},
    )
    row = cur.fetchone()
    if row:
        row["why"] = (f"{row['case_type']} is your least-practiced case type "
                      f"— this is a top-rated one to start with.")
    return row


def _rule_difficulty_ladder(cur, user_id: int,
                            exclude_case_ids: list[int]) -> dict | None:
    """Rule 2: mean grade over the last 3 finalized-as-candidate sessions
    ≥ 4.0 → suggest the next difficulty up in their most-practiced type."""
    cur.execute(
        """
        SELECT AVG(g.grade) AS mean_grade, COUNT(*) AS n FROM (
            SELECT f.grade
            FROM practice_sessions ps
            JOIN feedback f ON f.session_id = ps.id
            WHERE ps.state = 'finalized' AND ps.candidate_id = %(u)s
              AND f.grade IS NOT NULL
            ORDER BY ps.ended_at DESC LIMIT 3
        ) g;
        """,
        {"u": user_id},
    )
    row = cur.fetchone()
    if not row or row["n"] < 3 or row["mean_grade"] is None \
            or float(row["mean_grade"]) < LADDER_MIN_GRADE:
        return None
    mean_grade = float(row["mean_grade"])

    cur.execute(
        """
        SELECT c.case_type, c.difficulty, COUNT(*) AS n
        FROM practice_sessions ps JOIN cases c ON c.id = ps.case_id
        WHERE ps.state = 'finalized' AND ps.candidate_id = %(u)s
          AND c.case_type IS NOT NULL AND c.difficulty IS NOT NULL
        GROUP BY c.case_type, c.difficulty
        ORDER BY n DESC, c.case_type LIMIT 1;
        """,
        {"u": user_id},
    )
    practiced = cur.fetchone()
    if not practiced:
        return None
    next_difficulty = _LADDER.get(practiced["difficulty"])
    if next_difficulty is None:      # already at Hard — no rung above
        return None

    cur.execute(
        f"""
        SELECT c.id, c.case_title, c.case_type, c.difficulty,
               {_RATING} AS rating
        FROM cases c
        WHERE c.case_type = %(ct)s AND c.difficulty = %(d)s AND {_ELIGIBLE}
        ORDER BY rating DESC, c.difficulty_score, c.id
        LIMIT 1;
        """,
        {"u": user_id, "ct": practiced["case_type"], "d": next_difficulty,
         "exclude": exclude_case_ids},
    )
    row = cur.fetchone()
    if row:
        row["why"] = (f"You're averaging {mean_grade:.1f} on recent cases "
                      f"— ready to step up to {row['difficulty']} "
                      f"{row['case_type']}.")
    return row


def _rule_weak_dimension(cur, user_id: int, weakest: str | None,
                         exclude_case_ids: list[int]) -> dict | None:
    """Rule 3: suggest a case whose rubric template weights the user's
    lowest-averaging dimension heaviest (share of total max_points)."""
    if weakest is None:
        return None
    cur.execute(
        f"""
        WITH weighted AS (
            SELECT rt.case_id,
                   SUM((item->>'max_points')::numeric)
                       FILTER (WHERE item->>'dimension' = %(dim)s)
                     / NULLIF(SUM((item->>'max_points')::numeric), 0) AS share
            FROM rubric_templates rt,
                 jsonb_array_elements(rt.items_json) AS item
            WHERE rt.case_id IS NOT NULL
            GROUP BY rt.case_id
        )
        SELECT c.id, c.case_title, c.case_type, c.difficulty,
               {_RATING} AS rating, weighted.share
        FROM weighted JOIN cases c ON c.id = weighted.case_id
        WHERE weighted.share > 0.2 AND {_ELIGIBLE}
        ORDER BY weighted.share DESC, rating DESC, c.id
        LIMIT 1;
        """,
        {"u": user_id, "dim": weakest, "exclude": exclude_case_ids},
    )
    row = cur.fetchone()
    if row:
        row["why"] = (f"Your weakest dimension is {weakest.replace('_', ' ')} "
                      f"— this case weights it heavily.")
    return row


def recommendations(user_id: int, exclude_case_ids: list[int] = [],
                    limit: int = 5) -> list[dict]:
    """§4.8: run the rules in order, union + dedupe, cap at `limit`, each entry
    tagged with the rule that produced it and a human-readable `why`.

    `exclude_case_ids` drops those cases from every rule (the "Swap
    recommendation" affordance re-calls with the swapped id excluded). It is
    read-only here, so the shared-default empty list is safe."""
    trends = dimension_averages(user_id)
    weakest = trends[0]["dimension"] if trends else None

    out: list[dict] = []
    seen: set[int] = set()
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            for rule, fetch in (
                ("coverage-gap",
                 lambda: _rule_coverage_gap(cur, user_id, exclude_case_ids)),
                ("difficulty-ladder",
                 lambda: _rule_difficulty_ladder(cur, user_id, exclude_case_ids)),
                ("weak-dimension",
                 lambda: _rule_weak_dimension(cur, user_id, weakest,
                                              exclude_case_ids)),
            ):
                if len(out) >= limit:
                    break
                row = fetch()
                if row and row["id"] not in seen:
                    seen.add(row["id"])
                    out.append({
                        "case_id": row["id"],
                        "title": row["case_title"],
                        "case_type": row["case_type"],
                        "difficulty": row["difficulty"],
                        "why": row["why"],
                        "rule": rule,
                    })
    return out
