"""
Purpose: Role-swap invite SQL — a pending "swap roles & go again" between two
         real users, resolved into a reversed negotiating session on accept.
Inputs:  swap_invites (via get_pool).
Outputs: swap_invite rows; no external side effects.
Run:     from webapp.repositories import swaps as swap_repo
"""

from __future__ import annotations

from typing import Optional

import psycopg
from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.practice_states import TransitionError


def create_invite(from_session_id: int, initiator_id: int, invitee_id: int) -> dict:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            try:
                cur.execute(
                    "INSERT INTO swap_invites (from_session_id, initiator_id, invitee_id)"
                    " VALUES (%s, %s, %s) RETURNING *;",
                    (from_session_id, initiator_id, invitee_id))
                return cur.fetchone()
            except psycopg.errors.UniqueViolation as exc:
                raise TransitionError(409, "A swap invite is already pending") from exc


def pending_invite(from_session_id: int) -> Optional[dict]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT * FROM swap_invites WHERE from_session_id = %s"
                " AND state = 'pending' ORDER BY id DESC LIMIT 1;", (from_session_id,))
            return cur.fetchone()


def claim_invite(invite_id: int, invitee_id: int) -> bool:
    """Atomically transition a pending invite to 'accepted' for its invitee.
    Returns True iff THIS call won the transition (so exactly one accept creates
    the reversed session — a concurrent second accept gets False). new_session_id
    is attached afterwards by attach_new_session."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE swap_invites SET state = 'accepted', responded_at = NOW()"
                " WHERE id = %s AND invitee_id = %s AND state = 'pending';",
                (invite_id, invitee_id))
            return cur.rowcount == 1


def attach_new_session(invite_id: int, new_session_id: int) -> None:
    """Record the reversed session created for an already-claimed invite."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE swap_invites SET new_session_id = %s WHERE id = %s;",
                (new_session_id, invite_id))
