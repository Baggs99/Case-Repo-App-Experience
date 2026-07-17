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


def mark_accepted(invite_id: int, new_session_id: int) -> None:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE swap_invites SET state = 'accepted', new_session_id = %s,"
                " responded_at = NOW() WHERE id = %s AND state = 'pending';",
                (new_session_id, invite_id))
