"""
Practice-sessions repository — all SQL for practice_sessions and
rubric_templates defaults lives here.

Transitions run inside a SELECT … FOR UPDATE so two racing requests (e.g.
both participants clicking at once, or a reconnecting client re-posting)
serialize; validation itself is the pure webapp.practice_states module.
"""

from __future__ import annotations

import json
from datetime import timedelta
from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.practice_states import TransitionError, validate_transition
from webapp.repositories.rooms import get_or_create_room

# Seeded once, lazily (INTEGRATION.md A3). Five items mirror the spec's five
# rubric dimensions with equal weight; owners can add richer templates later.
_GENERIC_TEMPLATE_NAME = "Generic case rubric"
_GENERIC_ITEMS = [
    {"id": "structure", "label": "Structuring & framework", "dimension": "structure", "max_points": 5},
    {"id": "quant", "label": "Quantitative accuracy", "dimension": "quant", "max_points": 5},
    {"id": "insight", "label": "Business insight", "dimension": "insight", "max_points": 5},
    {"id": "communication", "label": "Communication & presence", "dimension": "communication", "max_points": 5},
    {"id": "synthesis", "label": "Synthesis & recommendation", "dimension": "synthesis", "max_points": 5},
]

_SESSION_COLS = """
    ps.id, ps.room_id, ps.interviewer_id, ps.candidate_id, ps.case_id,
    ps.rubric_template_id, ps.state, ps.consent_interviewer,
    ps.consent_candidate, ps.scheduled_at, ps.started_at, ps.ended_at,
    ps.state_changed_at, ps.created_at, ps.mode
"""


def get_default_rubric_template_id(case_id: int, created_by: int) -> int:
    """A3: the case's own newest template if any, else the generic one
    (created on first use)."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM rubric_templates WHERE case_id = %s"
                " ORDER BY created_at DESC LIMIT 1;",
                (case_id,),
            )
            row = cur.fetchone()
            if row:
                return row[0]

            cur.execute(
                "SELECT id FROM rubric_templates"
                " WHERE case_id IS NULL AND name = %s LIMIT 1;",
                (_GENERIC_TEMPLATE_NAME,),
            )
            row = cur.fetchone()
            if row:
                return row[0]

            cur.execute(
                "INSERT INTO rubric_templates (case_id, name, items_json, created_by)"
                " VALUES (NULL, %s, %s, %s) RETURNING id;",
                (_GENERIC_TEMPLATE_NAME, json.dumps(_GENERIC_ITEMS), created_by),
            )
            return cur.fetchone()[0]


def create_practice_session(
    *,
    interviewer_id: int,
    candidate_id: int,
    case_id: int,
    rubric_template_id: Optional[int] = None,
    scheduled_at: Optional[str] = None,
    mode: str = "remote",
) -> dict:
    """Create a session in 'scheduled'. The room is the interviewer's (A1),
    auto-created if they never visited theirs."""
    room = get_or_create_room(interviewer_id)
    if rubric_template_id is None:
        rubric_template_id = get_default_rubric_template_id(case_id, interviewer_id)

    sql = f"""
        INSERT INTO practice_sessions
            (room_id, interviewer_id, candidate_id, case_id,
             rubric_template_id, scheduled_at, mode)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING {_SESSION_COLS.replace('ps.', '')};
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (room["id"], interviewer_id, candidate_id,
                              case_id, rubric_template_id, scheduled_at, mode))
            return cur.fetchone()


def create_negotiating_session_within(
    cur, *, interviewer_id: int, candidate_id: int, mode: str = "remote",
    scheduled_at=None, swapped_from_session_id: int | None = None,
) -> int:
    """Create a pre-lobby 'negotiating' session (case undecided) using the
    caller's already-locked cursor (case-less proposal accept/claim run this
    inside their proposal lock). Room lookup opens its own idempotent
    connection (repo convention). case_id/rubric_template_id stay NULL until
    the interviewer and candidate settle a case (stamp_negotiated_case)."""
    room = get_or_create_room(interviewer_id)
    cur.execute(
        "INSERT INTO practice_sessions (room_id, interviewer_id, candidate_id,"
        " case_id, rubric_template_id, state, scheduled_at, mode,"
        " swapped_from_session_id)"
        " VALUES (%s, %s, %s, NULL, NULL, 'negotiating', %s, %s, %s)"
        " RETURNING id;",
        (room["id"], interviewer_id, candidate_id, scheduled_at, mode,
         swapped_from_session_id),
    )
    return cur.fetchone()["id"]


def create_negotiating_session(
    *, interviewer_id: int, candidate_id: int, mode: str = "remote",
    scheduled_at=None, swapped_from_session_id: int | None = None,
) -> dict:
    """Own-connection variant (pairing claim / swap accept). Returns the row."""
    room = get_or_create_room(interviewer_id)
    sql = f"""
        INSERT INTO practice_sessions
            (room_id, interviewer_id, candidate_id, case_id, rubric_template_id,
             state, scheduled_at, mode, swapped_from_session_id)
        VALUES (%s, %s, %s, NULL, NULL, 'negotiating', %s, %s, %s)
        RETURNING {_SESSION_COLS.replace('ps.', '')};
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (room["id"], interviewer_id, candidate_id,
                              scheduled_at, mode, swapped_from_session_id))
            return cur.fetchone()


def stamp_negotiated_case(session_id: int, case_id: int,
                          rubric_template_id: int) -> dict:
    """Settle a negotiating session on a case: stamp case_id + rubric_template_id
    and move negotiating → lobby (bypasses the generic state machine, which
    forbids negotiating→lobby, because the case must be set in the same act)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT {_SESSION_COLS} FROM practice_sessions ps"
                " WHERE ps.id = %s FOR UPDATE;", (session_id,))
            row = cur.fetchone()
            if row is None:
                raise TransitionError(404, "No such session")
            if row["state"] != "negotiating":
                raise TransitionError(409, "Session is not in negotiation")
            cur.execute(
                "UPDATE practice_sessions SET case_id = %s, rubric_template_id = %s,"
                " state = 'lobby', state_changed_at = NOW() WHERE id = %s"
                f" RETURNING {_SESSION_COLS.replace('ps.', '')};",
                (case_id, rubric_template_id, session_id),
            )
            return cur.fetchone()


def get_practice_session(session_id: int) -> Optional[dict]:
    """Session row + display names and case metadata for the session UI."""
    sql = f"""
        SELECT {_SESSION_COLS},
               COALESCE(ui.display_name, split_part(ui.email::text, '@', 1)) AS interviewer_name,
               COALESCE(uc.display_name, split_part(uc.email::text, '@', 1)) AS candidate_name,
               ui.is_guest AS interviewer_is_guest,
               uc.is_guest AS candidate_is_guest,
               c.case_title, r.slug AS room_slug
        FROM practice_sessions ps
        JOIN users ui ON ui.id = ps.interviewer_id
        JOIN users uc ON uc.id = ps.candidate_id
        LEFT JOIN cases c  ON c.id = ps.case_id
        JOIN rooms r  ON r.id = ps.room_id
        WHERE ps.id = %s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (session_id,))
            return cur.fetchone()


def role_of(session: dict, user_id: int) -> Optional[str]:
    if user_id == session["interviewer_id"]:
        return "interviewer"
    if user_id == session["candidate_id"]:
        return "candidate"
    return None


def set_consent(session_id: int, role: str, consent: bool) -> dict:
    """Record a participant's recording consent. Locked once live or later —
    consent is a lobby-time decision (INV-10); flipping it mid-call is a
    product question v1 doesn't open."""
    column = "consent_interviewer" if role == "interviewer" else "consent_candidate"
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT {_SESSION_COLS} FROM practice_sessions ps"
                " WHERE ps.id = %s FOR UPDATE;",
                (session_id,),
            )
            row = cur.fetchone()
            if row is None:
                raise TransitionError(404, "No such session")
            if row["state"] not in ("scheduled", "lobby"):
                raise TransitionError(409, "Consent can only change before the call starts")
            cur.execute(
                f"UPDATE practice_sessions SET {column} = %s WHERE id = %s"
                f" RETURNING {_SESSION_COLS.replace('ps.', '')};",
                (consent, session_id),
            )
            return cur.fetchone()


def transition(session_id: int, actor_id: int, target: str) -> dict:
    """Validated state transition; stamps started_at / ended_at /
    state_changed_at as appropriate."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT {_SESSION_COLS} FROM practice_sessions ps"
                " WHERE ps.id = %s FOR UPDATE;",
                (session_id,),
            )
            row = cur.fetchone()
            if row is None:
                raise TransitionError(404, "No such session")

            actor_role = role_of(row, actor_id)
            if actor_role is None:
                # Non-participants get the same 404 as a missing session —
                # existence is not disclosed (repo convention, see
                # require_admin; INTEGRATION.md DV-11).
                raise TransitionError(404, "No such session")

            validate_transition(
                row["state"], target, actor_role,
                row["consent_interviewer"], row["consent_candidate"],
            )

            stamps = "state_changed_at = NOW()"
            if target == "live":
                stamps += ", started_at = NOW()"
            if target in ("debrief", "aborted"):
                stamps += ", ended_at = NOW()"

            cur.execute(
                f"UPDATE practice_sessions SET state = %s, {stamps}"
                f" WHERE id = %s RETURNING {_SESSION_COLS.replace('ps.', '')};",
                (target, session_id),
            )
            return cur.fetchone()


def public_stats(user_id: int) -> dict:
    """Room-page public stats (spec §4.7): finalized-session count and the
    A8 streak — consecutive calendar weeks with ≥ 1 finalized session,
    counted back from the current week (a still-sessionless current week
    doesn't break a streak that ran through last week). Never grades."""
    sql = """
        SELECT DISTINCT date_trunc('week', ended_at) AS week
        FROM practice_sessions
        WHERE state = 'finalized' AND ended_at IS NOT NULL
          AND (interviewer_id = %(u)s OR candidate_id = %(u)s)
        ORDER BY week DESC;
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, {"u": user_id})
            weeks = [row[0] for row in cur.fetchall()]
            cur.execute("SELECT date_trunc('week', NOW());")
            this_week = cur.fetchone()[0]

    streak = 0
    expected = this_week
    for week in weeks:
        if week == expected:
            streak += 1
            expected -= timedelta(weeks=1)
        elif streak == 0 and week == this_week - timedelta(weeks=1):
            # Current week has no session yet — start counting from last week.
            streak = 1
            expected = week - timedelta(weeks=1)
        else:
            break
    return {"sessions_finalized": count_finalized(user_id), "streak_weeks": streak}


def count_finalized(user_id: int) -> int:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FROM practice_sessions"
                " WHERE state = 'finalized'"
                "   AND (interviewer_id = %(u)s OR candidate_id = %(u)s);",
                {"u": user_id},
            )
            return cur.fetchone()[0]


def list_upcoming_for_user(user_id: int) -> list[dict]:
    """Sessions the user can still join (scheduled/lobby/live), soonest
    first, for the own-room panel."""
    sql = """
        SELECT ps.id, ps.state, ps.scheduled_at, ps.created_at,
               c.case_title,
               CASE WHEN ps.interviewer_id = %(u)s THEN 'interviewer'
                    ELSE 'candidate' END AS your_role,
               CASE WHEN ps.interviewer_id = %(u)s
                    THEN COALESCE(uc.display_name, split_part(uc.email::text, '@', 1))
                    ELSE COALESCE(ui.display_name, split_part(ui.email::text, '@', 1))
               END AS counterpart
        FROM practice_sessions ps
        JOIN cases c ON c.id = ps.case_id
        JOIN users ui ON ui.id = ps.interviewer_id
        JOIN users uc ON uc.id = ps.candidate_id
        WHERE (ps.interviewer_id = %(u)s OR ps.candidate_id = %(u)s)
          AND ps.state IN ('scheduled', 'lobby', 'live')
        ORDER BY ps.scheduled_at NULLS FIRST, ps.created_at;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, {"u": user_id})
            return cur.fetchall()


def sweep_stale_sessions() -> int:
    """A4: abort sessions stuck pre-debrief for > 6 h (no cron on the target
    host — called from page loads). Returns rows swept.

    'scheduled' counts too (it is pre-debrief): a no-show 6 h past its
    scheduled_at, or an unscheduled ("now") session nobody opened within
    6 h of creation, is dead — otherwise it sits in Upcoming forever.
    Future-scheduled sessions are untouched."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE practice_sessions"
                " SET state = 'aborted', ended_at = NOW(), state_changed_at = NOW()"
                " WHERE (state IN ('lobby', 'live')"
                "        AND state_changed_at < NOW() - INTERVAL '6 hours')"
                "    OR (state IN ('scheduled', 'negotiating')"
                "        AND COALESCE(scheduled_at, created_at)"
                "            < NOW() - INTERVAL '6 hours');"
            )
            return cur.rowcount


def sweep_missed(missed_after_min: int = 60) -> int:
    """A3: an accepted session never joined (still 'scheduled'/'lobby')
    missed_after_min past its scheduled start becomes 'missed' — distinct from
    the 6-h 'aborted' backstop (sweep_stale_sessions). Only scheduled sessions
    (scheduled_at set) qualify; unscheduled "now" sessions fall to the backstop.
    Run this BEFORE sweep_stale_sessions so a past-start scheduled session is
    marked 'missed', not 'aborted'. Returns rows swept."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE practice_sessions"
                " SET state = 'missed', ended_at = NOW(), state_changed_at = NOW()"
                " WHERE state IN ('scheduled', 'lobby')"
                "   AND scheduled_at IS NOT NULL"
                "   AND scheduled_at < NOW() - make_interval(mins => %s);",
                (missed_after_min,),
            )
            return cur.rowcount
