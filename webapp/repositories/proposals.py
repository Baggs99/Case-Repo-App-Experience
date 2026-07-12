"""
Proposals repository — create / inbox / accept / decline / expire
(spec §4.7, T8.3/T8.4).

Accept runs under SELECT … FOR UPDATE so a double-click or two racing
accepts serialize: the second sees state != 'pending' and gets a 409. The
practice_session row is inserted in the SAME transaction that flips the
proposal, so a crash between the two can't leave an accepted proposal
without its session (room and rubric-template ids are resolved beforehand —
both are idempotent reads/creates).
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from webapp.db import get_pool
from webapp.practice_states import TransitionError
from webapp.repositories.feedback import is_burned
from webapp.repositories.practice_sessions import get_default_rubric_template_id
from webapp.repositories.rooms import get_or_create_room

MAX_PROPOSED_TIMES = 3
EXPIRY_DAYS = 7

_COLS = """
    p.id, p.from_user_id, p.to_user_id, p.case_id, p.from_role, p.message,
    p.proposed_times_json, p.state, p.session_id, p.created_at, p.responded_at
"""


def candidate_of(from_user_id: int, to_user_id: int, from_role: str) -> int:
    """Who would sit as candidate if this proposal became a session."""
    return to_user_id if from_role == "interviewer" else from_user_id


def create_proposal(*, from_user_id: int, to_user_id: int, case_id: int,
                    from_role: str, message: Optional[str],
                    proposed_times: list[datetime]) -> dict:
    if from_user_id == to_user_id:
        raise TransitionError(400, "You can't propose to yourself")
    if len(proposed_times) > MAX_PROPOSED_TIMES:
        raise TransitionError(400, f"At most {MAX_PROPOSED_TIMES} proposed times")
    if is_burned(candidate_of(from_user_id, to_user_id, from_role), case_id):
        # A6 — checked again at accept; this just fails fast.
        raise TransitionError(409, "This case is burned for the would-be candidate")

    times = [t.isoformat() for t in proposed_times]
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "INSERT INTO proposals (from_user_id, to_user_id, case_id,"
                " from_role, message, proposed_times_json)"
                " VALUES (%s, %s, %s, %s, %s, %s)"
                f" RETURNING {_COLS.replace('p.', '')};",
                (from_user_id, to_user_id, case_id, from_role, message,
                 Jsonb(times)),
            )
            return cur.fetchone()


def sweep_expired() -> int:
    """T8.3: pending proposals older than 7 days flip to 'expired' on page
    load — no cron dependency. Returns rows swept."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE proposals SET state = 'expired', responded_at = NOW()"
                " WHERE state = 'pending'"
                f"  AND created_at < NOW() - INTERVAL '{EXPIRY_DAYS} days';"
            )
            return cur.rowcount


def inbox(user_id: int) -> list[dict]:
    """Pending proposals RECEIVED by the user, with proposer and case info."""
    sql = f"""
        SELECT {_COLS},
               COALESCE(u.display_name, split_part(u.email::text, '@', 1)) AS from_name,
               c.case_title, c.case_type, c.difficulty
        FROM proposals p
        JOIN users u ON u.id = p.from_user_id
        JOIN cases c ON c.id = p.case_id
        WHERE p.to_user_id = %s AND p.state = 'pending'
        ORDER BY p.created_at DESC;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (user_id,))
            return cur.fetchall()


def pending_count(user_id: int) -> int:
    """Nav badge. Uses idx_proposals_inbox; called on every page render."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM proposals"
                        " WHERE to_user_id = %s AND state = 'pending';",
                        (user_id,))
            return cur.fetchone()[0]


def respond(proposal_id: int, user_id: int, *, accept: bool,
            scheduled_at: Optional[datetime]) -> dict:
    """Accept (creates + links the session) or decline. Only the recipient,
    only while pending. Returns the proposal row (with session_id on accept).
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(f"SELECT {_COLS} FROM proposals p WHERE p.id = %s"
                        " FOR UPDATE;", (proposal_id,))
            prop = cur.fetchone()
            if prop is None or user_id != prop["to_user_id"]:
                # Existence undisclosed to non-recipients (DV-11 philosophy).
                raise TransitionError(404, "No such proposal")
            if prop["state"] != "pending":
                raise TransitionError(409, f"Proposal is already {prop['state']}")

            if not accept:
                cur.execute(
                    "UPDATE proposals SET state = 'declined', responded_at = NOW()"
                    f" WHERE id = %s RETURNING {_COLS.replace('p.', '')};",
                    (proposal_id,),
                )
                return cur.fetchone()

            if prop["from_role"] == "interviewer":
                interviewer_id, candidate_id = prop["from_user_id"], prop["to_user_id"]
            else:
                interviewer_id, candidate_id = prop["to_user_id"], prop["from_user_id"]

            if is_burned(candidate_id, prop["case_id"]):
                raise TransitionError(409, "This case is burned for the would-be candidate")

            # Resolved outside the locked insert: both are idempotent.
            room = get_or_create_room(interviewer_id)
            template_id = get_default_rubric_template_id(prop["case_id"], interviewer_id)

            cur.execute(
                "INSERT INTO practice_sessions (room_id, interviewer_id,"
                " candidate_id, case_id, rubric_template_id, scheduled_at)"
                " VALUES (%s, %s, %s, %s, %s, %s) RETURNING id;",
                (room["id"], interviewer_id, candidate_id, prop["case_id"],
                 template_id, scheduled_at),
            )
            session_id = cur.fetchone()["id"]
            cur.execute(
                "UPDATE proposals SET state = 'accepted', responded_at = NOW(),"
                f" session_id = %s WHERE id = %s RETURNING {_COLS.replace('p.', '')};",
                (session_id, proposal_id),
            )
            return cur.fetchone()
