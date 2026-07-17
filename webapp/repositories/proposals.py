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

import secrets

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
    p.proposed_times_json, p.state, p.session_id, p.created_at, p.responded_at,
    p.claim_token, p.counter_times_json, p.counter_by, p.countered_at
"""


def candidate_of(from_user_id: int, to_user_id: int, from_role: str) -> int:
    """Who would sit as candidate if this proposal became a session."""
    return to_user_id if from_role == "interviewer" else from_user_id


def _resolve_roles(prop: dict) -> tuple[int, int]:
    """(interviewer_id, candidate_id) for a proposal, per from_role."""
    if prop["from_role"] == "interviewer":
        return prop["from_user_id"], prop["to_user_id"]
    return prop["to_user_id"], prop["from_user_id"]


def _create_session_within(cur, prop: dict, scheduled_at) -> int:
    """Create the practice session for an accepted proposal, using the caller's
    already-locked cursor for the INSERT. Room/template lookups open their own
    idempotent connections (existing repo convention). Requires prop['case_id']
    not None (case-less proposals never reach here — see claim_proposal/respond).
    """
    interviewer_id, candidate_id = _resolve_roles(prop)
    if is_burned(candidate_id, prop["case_id"]):
        raise TransitionError(409, "This case is burned for the would-be candidate")
    room = get_or_create_room(interviewer_id)
    template_id = get_default_rubric_template_id(prop["case_id"], interviewer_id)
    cur.execute(
        "INSERT INTO practice_sessions (room_id, interviewer_id, candidate_id,"
        " case_id, rubric_template_id, scheduled_at)"
        " VALUES (%s, %s, %s, %s, %s, %s) RETURNING id;",
        (room["id"], interviewer_id, candidate_id, prop["case_id"],
         template_id, scheduled_at),
    )
    return cur.fetchone()["id"]


def claim_proposal(token: str, user_id: int) -> dict:
    """Claim an open ('send a link') proposal. The claimer becomes to_user_id.
    Scheduled proposals stay 'pending' (claimer now responds); "now" proposals
    (no proposed_times) auto-accept — creating a session when a case is set, or
    marking accepted with needs_negotiation when the case is "interviewer
    decides" (B3 wires the negotiating session). Any authed non-creator may
    claim; B2 overrides the route's auth dependency for guests.
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(f"SELECT {_COLS} FROM proposals p"
                        " WHERE p.claim_token = %s FOR UPDATE;", (token,))
            prop = cur.fetchone()
            if prop is None:
                raise TransitionError(404, "No such claim link")
            if prop["state"] != "pending":
                raise TransitionError(409, f"Proposal is already {prop['state']}")
            if prop["to_user_id"] is not None:
                raise TransitionError(409, "This link has already been claimed")
            if user_id == prop["from_user_id"]:
                raise TransitionError(409, "You can't claim your own link")

            cur.execute("UPDATE proposals SET to_user_id = %s WHERE id = %s;",
                        (user_id, prop["id"]))
            prop["to_user_id"] = user_id

            result = {"proposal_id": prop["id"], "from_user_id": prop["from_user_id"]}
            if prop["proposed_times_json"]:
                # Scheduled: claimer is now the recipient; awaits accept/counter.
                result.update(state="pending", session_id=None,
                              accepted=False, needs_negotiation=False)
                return result

            if prop["case_id"] is None:
                cur.execute("UPDATE proposals SET state = 'accepted',"
                            " responded_at = NOW() WHERE id = %s;", (prop["id"],))
                result.update(state="accepted", session_id=None,
                              accepted=True, needs_negotiation=True)
                return result

            session_id = _create_session_within(cur, prop, None)
            cur.execute("UPDATE proposals SET state = 'accepted', responded_at = NOW(),"
                        " session_id = %s WHERE id = %s;", (session_id, prop["id"]))
            result.update(state="accepted", session_id=session_id,
                          accepted=True, needs_negotiation=False)
            return result


def counter_proposal(proposal_id: int, user_id: int,
                     times: list[datetime]) -> dict:
    """Recipient's one-round "Suggest new time" (spec §5.2). Only the recipient,
    only from 'pending'. Returns the countered row (incl. from_user_id, for the
    proposal_countered push to the proposer)."""
    if not times:
        raise TransitionError(400, "Provide at least one counter time")
    if len(times) > MAX_PROPOSED_TIMES:
        raise TransitionError(400, f"At most {MAX_PROPOSED_TIMES} counter times")
    iso = [t.isoformat() for t in times]
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(f"SELECT {_COLS} FROM proposals p WHERE p.id = %s"
                        " FOR UPDATE;", (proposal_id,))
            prop = cur.fetchone()
            if prop is None or user_id != prop["to_user_id"]:
                raise TransitionError(404, "No such proposal")
            if prop["state"] != "pending":
                raise TransitionError(409, f"Proposal is already {prop['state']}")
            cur.execute(
                "UPDATE proposals SET state = 'countered', counter_times_json = %s,"
                " counter_by = %s, countered_at = NOW() WHERE id = %s"
                f" RETURNING {_COLS.replace('p.', '')};",
                (Jsonb(iso), user_id, proposal_id),
            )
            return cur.fetchone()


def create_proposal(*, from_user_id: int, to_user_id: Optional[int],
                    case_id: Optional[int], from_role: str,
                    message: Optional[str],
                    proposed_times: list[datetime]) -> dict:
    if to_user_id is not None and from_user_id == to_user_id:
        raise TransitionError(400, "You can't propose to yourself")
    if len(proposed_times) > MAX_PROPOSED_TIMES:
        raise TransitionError(400, f"At most {MAX_PROPOSED_TIMES} proposed times")
    # Burned only checkable when both case and candidate are known up front;
    # open-link / case-less proposals defer the check to claim/accept.
    if case_id is not None and to_user_id is not None:
        if is_burned(candidate_of(from_user_id, to_user_id, from_role), case_id):
            raise TransitionError(409, "This case is burned for the would-be candidate")

    times = [t.isoformat() for t in proposed_times]
    claim_token = secrets.token_urlsafe(24) if to_user_id is None else None
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "INSERT INTO proposals (from_user_id, to_user_id, case_id,"
                " from_role, message, proposed_times_json, claim_token)"
                " VALUES (%s, %s, %s, %s, %s, %s, %s)"
                f" RETURNING {_COLS.replace('p.', '')};",
                (from_user_id, to_user_id, case_id, from_role, message,
                 Jsonb(times), claim_token),
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
            scheduled_at: Optional[datetime] = None,
            counter_time: Optional[datetime] = None) -> dict:
    """Accept or decline. 'pending' → the recipient acts (existing flow).
    'countered' → the original proposer acts, choosing counter_time from the
    stored counter times (spec §5.2). Case-less accepts mark the proposal
    accepted with session_id NULL and needs_negotiation=True (B3 negotiation).
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(f"SELECT {_COLS} FROM proposals p WHERE p.id = %s"
                        " FOR UPDATE;", (proposal_id,))
            prop = cur.fetchone()
            if prop is None:
                raise TransitionError(404, "No such proposal")

            state = prop["state"]
            if state == "pending":
                if user_id != prop["to_user_id"]:
                    raise TransitionError(404, "No such proposal")
            elif state == "countered":
                if user_id != prop["from_user_id"]:
                    raise TransitionError(404, "No such proposal")
            else:
                # DV-11: existence undisclosed to non-participants — a stranger
                # gets the same 404 as a missing proposal, only a participant
                # sees the 409 "already {state}".
                if user_id not in (prop["from_user_id"], prop["to_user_id"]):
                    raise TransitionError(404, "No such proposal")
                raise TransitionError(409, f"Proposal is already {state}")

            if not accept:
                cur.execute(
                    "UPDATE proposals SET state = 'declined', responded_at = NOW()"
                    f" WHERE id = %s RETURNING {_COLS.replace('p.', '')};",
                    (proposal_id,),
                )
                return cur.fetchone()

            if state == "countered":
                allowed = {datetime.fromisoformat(s)
                           for s in (prop["counter_times_json"] or [])}
                if counter_time is None or counter_time not in allowed:
                    raise TransitionError(409, "Chosen time must be one of the counter times")
                use_scheduled = counter_time
            else:
                use_scheduled = scheduled_at

            if prop["case_id"] is None:
                cur.execute(
                    "UPDATE proposals SET state = 'accepted', responded_at = NOW()"
                    f" WHERE id = %s RETURNING {_COLS.replace('p.', '')};",
                    (proposal_id,),
                )
                row = cur.fetchone()
                row["needs_negotiation"] = True
                return row

            session_id = _create_session_within(cur, prop, use_scheduled)
            cur.execute(
                "UPDATE proposals SET state = 'accepted', responded_at = NOW(),"
                f" session_id = %s WHERE id = %s RETURNING {_COLS.replace('p.', '')};",
                (session_id, proposal_id),
            )
            return cur.fetchone()
