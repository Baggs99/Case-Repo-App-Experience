"""
Rooms repository — all SQL touching the `rooms` table lives here.

One permanent room per user (UNIQUE on owner_user_id), auto-created on first
visit. Slugs come from the user's display name and are public/non-secret;
access control lives on practice sessions, not rooms.
"""

from __future__ import annotations

from typing import Optional

from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row

from utils.slug import make_case_slug
from webapp.db import get_pool


def get_room_by_slug(slug: str) -> Optional[dict]:
    """Room + owner identity, or None. display_name falls back to the email
    local-part (the 011 backfill guarantees it for existing users, but a
    fresh signup post-backfill would have NULL)."""
    sql = """
        SELECT r.id, r.owner_user_id, r.slug, r.created_at,
               COALESCE(u.display_name, split_part(u.email::text, '@', 1)) AS owner_name
        FROM rooms r
        JOIN users u ON u.id = r.owner_user_id
        WHERE r.slug = %s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (slug,))
            return cur.fetchone()


def get_room_for_user(user_id: int) -> Optional[dict]:
    sql = """
        SELECT r.id, r.owner_user_id, r.slug, r.created_at,
               COALESCE(u.display_name, split_part(u.email::text, '@', 1)) AS owner_name
        FROM rooms r
        JOIN users u ON u.id = r.owner_user_id
        WHERE r.owner_user_id = %s;
    """
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, (user_id,))
            return cur.fetchone()


def get_or_create_room(user_id: int) -> dict:
    """Return the user's room, creating it with a deduped slug if absent.

    Slug collisions (two users named 'dan') get -2, -3, … suffixes. The
    insert races are settled by the UNIQUE constraints: on a slug collision
    we retry with the next suffix; on an owner collision (two concurrent
    first visits) we return the winner's row.
    """
    existing = get_room_for_user(user_id)
    if existing:
        return existing

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT COALESCE(display_name, split_part(email::text, '@', 1)) AS name"
                " FROM users WHERE id = %s;",
                (user_id,),
            )
            row = cur.fetchone()
            if row is None:
                raise ValueError(f"No such user: {user_id}")
            base = make_case_slug(row["name"], max_length=50) or "room"

    for attempt in range(1, 50):
        slug = base if attempt == 1 else f"{base}-{attempt}"
        try:
            with get_pool().connection() as conn:
                with conn.cursor(row_factory=dict_row) as cur:
                    cur.execute(
                        "INSERT INTO rooms (owner_user_id, slug) VALUES (%s, %s)"
                        " RETURNING id, owner_user_id, slug, created_at;",
                        (user_id, slug),
                    )
                    created = cur.fetchone()
                    created["owner_name"] = row["name"]
                    return created
        except UniqueViolation as exc:
            # Lost an owner race → their row exists now; lost a slug race →
            # try the next suffix.
            if "rooms_owner_user_id" in str(exc) or "owner_user_id" in str(exc):
                won = get_room_for_user(user_id)
                if won:
                    return won
            continue

    raise RuntimeError(f"Could not allocate a room slug from base {base!r}")
