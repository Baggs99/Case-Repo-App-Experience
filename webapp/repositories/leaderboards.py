"""
Purpose: B6 leaderboards + school standings — per-user activity points, group
         boards (ranks+points, joined-group scope only), group member progress,
         and percentile-based school standings (NO population counts, ever).
Inputs:  reads feedback + practice_sessions + drill_attempts + group_members +
         users.school_id + schools.campus_city.
Outputs: dict rows for the API layer; no writes.
Run:     from webapp.repositories import leaderboards; leaderboards.school_standings()
Seam:    ACTIVITY_POINTS_SQL + scope_user_ids() are the scoping CTEs B8 reuses;
         B8 extends the points expression with drill scores (migration 034).
"""

from __future__ import annotations

from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.repositories.drill_attempts import streak_days

# Weights are tunable; kept as trusted int constants (safe to f-string into SQL).
POINTS_PER_SESSION: int = 10
POINTS_PER_DRILL: int = 1

# CTE body (named `activity_points`) yielding (user_id, points) for every user
# active in the last 30 days: >=1 finalized session as candidate OR >=1 drill.
# The 30-day rolling window matches the brief's "group leaderboard … last 30 d"
# and the design's "THIS WEEK" school-standing framing. B8 extends the points
# expression with gauntlet drill scores. All standings/percentiles reuse this
# single population (30-day-active users), documented so surfaces stay aligned.
ACTIVITY_POINTS_SQL: str = f"""
activity_points AS (
    SELECT u.id AS user_id,
           COALESCE(fs.n, 0) * {POINTS_PER_SESSION}
         + COALESCE(da.n, 0) * {POINTS_PER_DRILL} AS points
    FROM users u
    LEFT JOIN (
        SELECT ps.candidate_id AS uid, COUNT(*) AS n
        FROM feedback f JOIN practice_sessions ps ON ps.id = f.session_id
        WHERE f.finalized_at IS NOT NULL
          AND f.finalized_at > now() - interval '30 days'
        GROUP BY ps.candidate_id
    ) fs ON fs.uid = u.id
    LEFT JOIN (
        SELECT user_id AS uid, COUNT(*) AS n
        FROM drill_attempts
        WHERE completed_at > now() - interval '30 days'
        GROUP BY user_id
    ) da ON da.uid = u.id
    WHERE (COALESCE(fs.n, 0) > 0 OR COALESCE(da.n, 0) > 0)
      AND NOT COALESCE(u.is_guest, FALSE)
)
"""


def scope_user_ids(scope: str, *, user_id: int, group_id: Optional[int] = None) -> list[int]:
    """User ids in a leaderboard scope. B8 reuses this to bound its percentile
    population. scope ∈ {'group','school','global'}."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            if scope == "group":
                if group_id is None:
                    raise ValueError("group scope requires group_id")
                cur.execute("SELECT user_id FROM group_members WHERE group_id = %s;",
                            (group_id,))
            elif scope == "school":
                cur.execute(
                    "SELECT id FROM users WHERE school_id = ("
                    "  SELECT school_id FROM users WHERE id = %s) AND school_id IS NOT NULL;",
                    (user_id,))
            elif scope == "global":
                cur.execute("SELECT id FROM users;")
            else:
                raise ValueError(f"unknown scope {scope!r}")
            return [r[0] for r in cur.fetchall()]


def group_leaderboard(group_id: int) -> list[dict]:
    """Group board (ranks+points allowed — joined-group scope). Streak per member."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"WITH {ACTIVITY_POINTS_SQL}"
                f" SELECT gm.user_id,"
                f"        COALESCE(u.display_name, split_part(u.email::text,'@',1)) AS display_name,"
                f"        u.photo_key, COALESCE(ap.points, 0) AS points"
                f" FROM group_members gm JOIN users u ON u.id = gm.user_id"
                f" LEFT JOIN activity_points ap ON ap.user_id = gm.user_id"
                f" WHERE gm.group_id = %(g)s"
                f" ORDER BY points DESC, gm.joined_at ASC;",
                {"g": group_id})
            rows = cur.fetchall()
    # Ordinal ranks (1-based). Ties get distinct sequential ranks with a
    # deterministic points-desc, joined_at-asc order (not competition ranking) —
    # a small joined cohort where an exact position reads fine.
    out = []
    for i, r in enumerate(rows, start=1):
        out.append({"user_id": r["user_id"], "display_name": r["display_name"],
                    "photo_key": r["photo_key"], "points": int(r["points"]),
                    "rank": i, "streak": streak_days(r["user_id"])})
    return out


def group_progress(group_id: int) -> list[dict]:
    """Admin-only per-member progress (joined-group scope): cases done, mean
    grade, drills last 30 d, streak."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT gm.user_id,"
                " COALESCE(u.display_name, split_part(u.email::text,'@',1)) AS display_name,"
                " COALESCE(cd.n, 0) AS cases_done, cd.mean_grade,"
                " COALESCE(da.n, 0) AS drill_attempts_30d"
                " FROM group_members gm JOIN users u ON u.id = gm.user_id"
                " LEFT JOIN (SELECT ps.candidate_id AS uid, COUNT(*) AS n,"
                "                   ROUND(AVG(f.grade), 1) AS mean_grade"
                "            FROM feedback f JOIN practice_sessions ps ON ps.id = f.session_id"
                "            WHERE f.finalized_at IS NOT NULL GROUP BY ps.candidate_id) cd"
                "   ON cd.uid = gm.user_id"
                " LEFT JOIN (SELECT user_id AS uid, COUNT(*) AS n FROM drill_attempts"
                "            WHERE completed_at > now() - interval '30 days'"
                "            GROUP BY user_id) da ON da.uid = gm.user_id"
                " WHERE gm.group_id = %(g)s ORDER BY display_name;",
                {"g": group_id})
            rows = cur.fetchall()
    out = []
    for r in rows:
        out.append({"user_id": r["user_id"], "display_name": r["display_name"],
                    "cases_done": int(r["cases_done"]),
                    "mean_grade": float(r["mean_grade"]) if r["mean_grade"] is not None else None,
                    "drill_attempts_30d": int(r["drill_attempts_30d"]),
                    "streak": streak_days(r["user_id"])})
    return out


def user_global_percentile(user_id: int) -> Optional[float]:
    """The user's percentile (0–100, one decimal) among all active users by
    activity points. None if the user has no activity."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"WITH {ACTIVITY_POINTS_SQL},"
                f" ranked AS (SELECT user_id,"
                f"   100.0 * percent_rank() OVER (ORDER BY points) AS pct FROM activity_points)"
                f" SELECT ROUND(pct::numeric, 1) AS pct FROM ranked WHERE user_id = %(u)s;",
                {"u": user_id})
            row = cur.fetchone()
            return float(row["pct"]) if row else None


def school_standings() -> list[dict]:
    """School-vs-school board: avg member percentile + campus city + rank.
    NO population counts. Schools with no active members are omitted. The
    percentile population is ALL 30-day-active users (same as user_global_
    percentile and school_group_rollup) so every surface stays consistent."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"WITH {ACTIVITY_POINTS_SQL},"
                f" pct AS (SELECT ap.user_id, u.school_id,"
                f"   100.0 * percent_rank() OVER (ORDER BY ap.points) AS pctile"
                f"   FROM activity_points ap JOIN users u ON u.id = ap.user_id)"
                f" SELECT s.id AS school_id, s.name, s.campus_city,"
                f"        ROUND(AVG(p.pctile)::numeric, 1) AS avg_member_percentile"
                f" FROM pct p JOIN schools s ON s.id = p.school_id"
                f" GROUP BY s.id, s.name, s.campus_city"
                f" ORDER BY avg_member_percentile DESC, s.name;")
            rows = cur.fetchall()
    return [{"school_id": r["school_id"], "name": r["name"],
             "campus_city": r["campus_city"],
             "avg_member_percentile": float(r["avg_member_percentile"]),
             "rank": i} for i, r in enumerate(rows, start=1)]


def my_school_standing(user_id: int) -> dict:
    """The user's school standing card + the user's own percentile."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT school_id FROM users WHERE id = %s;", (user_id,))
            row = cur.fetchone()
            school_id = row[0] if row else None
    if school_id is None:
        return {"school": None, "your_percentile": None}
    school = next((s for s in school_standings() if s["school_id"] == school_id), None)
    return {"school": school, "your_percentile": user_global_percentile(user_id)}


def school_group_rollup(school_id: int) -> list[dict]:
    """Per-group avg member percentile for a school (school-leader view).
    NO population counts."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"WITH {ACTIVITY_POINTS_SQL},"
                f" pct AS (SELECT ap.user_id,"
                f"   100.0 * percent_rank() OVER (ORDER BY ap.points) AS pctile"
                f"   FROM activity_points ap)"
                f" SELECT g.id AS group_id, g.name,"
                f"        ROUND(AVG(p.pctile)::numeric, 1) AS avg_member_percentile"
                f" FROM groups g JOIN group_members gm ON gm.group_id = g.id"
                f" LEFT JOIN pct p ON p.user_id = gm.user_id"
                f" WHERE g.school_id = %(s)s"
                f" GROUP BY g.id, g.name ORDER BY avg_member_percentile DESC NULLS LAST, g.name;",
                {"s": school_id})
            rows = cur.fetchall()
    return [{"group_id": r["group_id"], "name": r["name"],
             "avg_member_percentile": (float(r["avg_member_percentile"])
                                       if r["avg_member_percentile"] is not None else None)}
            for r in rows]
