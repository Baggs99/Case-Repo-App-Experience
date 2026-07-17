"""
Pairing-token repository — ad-hoc in-person pairing (db/migrations/014).

An interviewer mints a short-TTL token bound to a chosen case; the scanner
(candidate) later claims it, which creates the practice session.
"""

from __future__ import annotations

import secrets
from typing import Optional

from psycopg import errors as pg_errors
from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.practice_states import TransitionError
from webapp.repositories.feedback import is_burned
from webapp.repositories.practice_sessions import create_practice_session


# Unambiguous 6-char set (spec §8): A-Z + 2-9, minus 0/O/1/I.
_SHORT_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _gen_short_code(n: int = 6) -> str:
    return "".join(secrets.choice(_SHORT_ALPHABET) for _ in range(n))


def mint_token(interviewer_id: int, case_id: Optional[int] = None,
               ttl_minutes: int = 10) -> dict:
    """Mint a pairing token (spec §8). case_id optional ("interviewer decides",
    negotiated in B3). Returns token + 6-char short_code + expiry. Retries on
    the astronomically rare short_code collision (partial-unique index)."""
    sql = """
        INSERT INTO pairing_tokens (token, interviewer_id, case_id, short_code, expires_at)
        VALUES (%s, %s, %s, %s, now() + make_interval(mins => %s))
        RETURNING token, short_code, expires_at;
    """
    with get_pool().connection() as conn:
        for _ in range(5):
            try:
                with conn.cursor(row_factory=dict_row) as cur:
                    # Regenerate BOTH on retry so a token clash (astronomically
                    # rare) is also escaped, not just a short_code clash.
                    cur.execute(sql, (secrets.token_urlsafe(24), interviewer_id,
                                      case_id, _gen_short_code(), ttl_minutes))
                    return cur.fetchone()
            except pg_errors.UniqueViolation:
                conn.rollback()  # token/short_code clash — regenerate
                continue
        raise TransitionError(500, "Could not allocate a pairing code")


def claim(*, candidate_id: int, token: Optional[str] = None,
          short_code: Optional[str] = None) -> dict:
    """Claim a pairing token by token OR short_code (spec §8), creating the
    practice session in one transaction. Case-less tokens can't create a
    session in B1 (sessions stay case-bound) — they 409 pending B3 negotiation.

    The token row is locked with SELECT ... FOR UPDATE for the whole
    transaction — this is the anti-double-claim mechanism. A concurrent
    second claim of the same token blocks on the lock until this one
    commits, then sees claimed_session_id already set and gets a 409.

    create_practice_session() opens its OWN connection/transaction (repo
    convention) and commits independently of the lock we're holding here.
    Accepted caveat: if the process crashes after that commit but before
    our UPDATE ... claimed_session_id below commits, a stray 'scheduled'
    session can be left behind while the token remains claimable. Rare
    crash window, low harm (an orphaned scheduled session, not a data
    corruption), acceptable for v1.
    """
    if token:
        where, val = "token = %s", token
    elif short_code:
        where, val = "short_code = %s", short_code
    else:
        raise TransitionError(400, "Provide a token or short_code")

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT *, (expires_at < now()) AS expired"
                f" FROM pairing_tokens WHERE {where} FOR UPDATE;",
                (val,),
            )
            row = cur.fetchone()
            if row is None:
                raise TransitionError(404, "No such pairing token")
            if row["expired"]:
                raise TransitionError(409, "Pairing token has expired")
            if row["claimed_session_id"] is not None:
                raise TransitionError(409, "Pairing token already claimed")
            if row["interviewer_id"] == candidate_id:
                raise TransitionError(409, "Cannot claim your own pairing token")
            if row["case_id"] is None:
                raise TransitionError(409, "Choose a case before pairing")
            if is_burned(candidate_id, row["case_id"]):
                raise TransitionError(409, "You have already completed this case")

            session = create_practice_session(
                interviewer_id=row["interviewer_id"],
                candidate_id=candidate_id,
                case_id=row["case_id"],
                mode="in_person",
            )
            cur.execute(
                "UPDATE pairing_tokens SET claimed_session_id = %s WHERE id = %s;",
                (session["id"], row["id"]),
            )
            return {"session_id": session["id"]}


def status(token: str, interviewer_id: int) -> Optional[int]:
    """The claimed session id for a token this interviewer minted, or None
    if it hasn't been claimed yet.

    Raises TransitionError(404) if the token doesn't exist or isn't owned
    by this interviewer — distinct from "found but unclaimed" (row exists,
    claimed_session_id is NULL), which returns None, same as claim()'s
    404 convention for an unknown/foreign token.
    """
    sql = "SELECT claimed_session_id FROM pairing_tokens WHERE token = %s AND interviewer_id = %s;"
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (token, interviewer_id))
            row = cur.fetchone()
            if row is None:
                raise TransitionError(404, "No such pairing token")
            return row[0]
