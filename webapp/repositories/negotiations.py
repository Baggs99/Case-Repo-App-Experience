"""
Purpose: Case-negotiation SQL — proposed-case rounds for a pre-lobby session.
Inputs:  case_negotiations, practice_sessions, proposals (via get_pool).
Outputs: negotiation rows; no external side effects (WS/broadcast done by route).
Run:     from webapp.repositories import negotiations as nego
"""

from __future__ import annotations

from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool


def _pick_by_round(session_id: int, round_no: int) -> Optional[dict]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT cn.*, c.case_title, c.case_type, c.difficulty"
                " FROM case_negotiations cn JOIN cases c ON c.id = cn.proposed_case_id"
                " WHERE cn.session_id = %s AND cn.round = %s"
                " ORDER BY cn.id DESC LIMIT 1;", (session_id, round_no))
            return cur.fetchone()


def interviewer_pick(session_id: int) -> Optional[dict]:
    return _pick_by_round(session_id, 1)


def candidate_counter(session_id: int) -> Optional[dict]:
    return _pick_by_round(session_id, 2)


def record_proposal(session_id: int, by_user_id: int, case_id: int,
                    round_no: int) -> dict:
    """Insert one negotiation round (pending)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "INSERT INTO case_negotiations (session_id, proposed_case_id,"
                " by_user_id, round) VALUES (%s, %s, %s, %s) RETURNING *;",
                (session_id, case_id, by_user_id, round_no))
            return cur.fetchone()


def mark_accepted(session_id: int, case_id: int) -> None:
    """Mark the chosen round accepted (and the rest declined)."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE case_negotiations SET state ="
                " CASE WHEN proposed_case_id = %s THEN 'accepted' ELSE 'declined' END"
                " WHERE session_id = %s;", (case_id, session_id))


def interviewer_done_set(interviewer_id: int, limit: int = 5) -> list[dict]:
    """Cases the interviewer has been candidate on (burned) — a source they can
    interview from confidently. Newest first."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT c.id AS case_id, c.case_title AS title, c.case_type,"
                "       c.difficulty"
                " FROM burned b JOIN cases c ON c.id = b.case_id"
                " WHERE b.user_id = %s ORDER BY b.burned_at DESC LIMIT %s;",
                (interviewer_id, limit))
            return cur.fetchall()


def originating_requested_case(session_id: int) -> Optional[dict]:
    """If the proposal that spawned this negotiating session carried a case
    (candidate's request), return it. Case-less entries → None (the norm)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT c.id AS case_id, c.case_title AS title, p.from_role"
                " FROM proposals p JOIN cases c ON c.id = p.case_id"
                " WHERE p.session_id = %s LIMIT 1;", (session_id,))
            return cur.fetchone()
