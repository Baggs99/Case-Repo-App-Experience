"""
Purpose: Read-only access to the firm reference table + curated interview
  deadlines (migration 026) for the B7 timeline.
Inputs:  firm_id; the firms / firm_deadlines tables via the shared pool.
Outputs: plain dict rows (no side effects).
Run:     from webapp.repositories import firms; firms.list_firms()
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool


def list_firms() -> list[dict]:
    """All firms, alphabetical — the add-a-firm catalog source."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id, name, slug FROM firms ORDER BY name;")
            return cur.fetchall()


def get_firm(firm_id: int) -> dict | None:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT id, name, slug FROM firms WHERE id = %(id)s;",
                        {"id": firm_id})
            return cur.fetchone()


def all_deadlines() -> list[dict]:
    """Every firm deadline; the timeline service groups these by firm_id and
    picks the relevant one (soonest upcoming, else latest passed) in Python."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT firm_id, cycle_label, deadline_date, region, is_estimate"
                " FROM firm_deadlines ORDER BY firm_id, deadline_date;")
            return cur.fetchall()
