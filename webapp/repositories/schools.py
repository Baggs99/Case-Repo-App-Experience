"""
Purpose: Read access to the schools registry (domain -> school). The registry is
         the source of truth for which email domains may sign up (OD-B5-2).
Inputs:  schools table (migration 023); DATABASE_URL-backed pool.
Outputs: no writes; add a school by inserting a row (no code change needed).
Run:     imported by webapp.auth.users and the onboarding/profile routes.
"""

from __future__ import annotations

from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool


def get_school_by_domain(domain: str) -> Optional[dict]:
    """Return {id, name, domain} for a registered domain, else None."""
    d = (domain or "").strip().lower()
    if not d:
        return None
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT id, name, domain FROM schools WHERE domain = %s;",
                (d,),
            )
            return cur.fetchone()


def get_school_by_id(school_id: int) -> Optional[dict]:
    """Return {id, name, domain} for a school id, else None."""
    if school_id is None:
        return None
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT id, name, domain FROM schools WHERE id = %s;",
                (school_id,),
            )
            return cur.fetchone()


def domain_is_registered(domain: str) -> bool:
    """True iff `domain` matches a schools row."""
    return get_school_by_domain(domain) is not None
