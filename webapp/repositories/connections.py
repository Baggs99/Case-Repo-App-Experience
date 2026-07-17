"""
Purpose: Mutual connections (friend requests) for B6 Community — request,
         accept, decline, remove, and listing with a free-now decoration.
Inputs:  requester/target user ids; reads users + availability + connections.
Outputs: INSERT/UPDATE/DELETE on connections; dict rows for the API layer.
Run:     from webapp.repositories import connections; connections.request(a, b)
"""

from __future__ import annotations

from psycopg.rows import dict_row

from webapp.db import get_pool

# Card fields the API layer maps to profile cards (photo_url built in the router).
_CARD = ("COALESCE(u.display_name, split_part(u.email::text, '@', 1)) AS display_name,"
         " u.photo_key, u.bio")


def request(requester_id: int, target_id: int) -> dict:
    """Create a pending request requester->target. Auto-accepts a reciprocal
    pending row; idempotent when a relation already exists. Returns the state."""
    if requester_id == target_id:
        raise ValueError("cannot connect to self")
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            # Any existing row in either direction?
            cur.execute(
                "SELECT user_id, friend_id, state FROM connections"
                " WHERE (user_id = %(a)s AND friend_id = %(b)s)"
                "    OR (user_id = %(b)s AND friend_id = %(a)s);",
                {"a": requester_id, "b": target_id})
            existing = cur.fetchone()
            if existing is not None:
                if existing["state"] == "accepted":
                    return {"state": "accepted", "created": False}
                # Pending exists. Reciprocal (target already asked me) -> accept.
                if existing["user_id"] == target_id:
                    cur.execute(
                        "UPDATE connections SET state = 'accepted', responded_at = NOW()"
                        " WHERE user_id = %(t)s AND friend_id = %(r)s;",
                        {"t": target_id, "r": requester_id})
                    return {"state": "accepted", "created": False}
                return {"state": "pending", "created": False}  # my own pending already there
            cur.execute(
                "INSERT INTO connections (user_id, friend_id) VALUES (%(r)s, %(t)s);",
                {"r": requester_id, "t": target_id})
            return {"state": "pending", "created": True}


def accept(requester_id: int, accepter_id: int) -> bool:
    """The target (accepter) accepts requester's pending request."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE connections SET state = 'accepted', responded_at = NOW()"
                " WHERE user_id = %(r)s AND friend_id = %(a)s AND state = 'pending';",
                {"r": requester_id, "a": accepter_id})
            return cur.rowcount > 0


def decline(requester_id: int, decliner_id: int) -> bool:
    """The target declines (deletes) requester's pending request."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM connections"
                " WHERE user_id = %(r)s AND friend_id = %(d)s AND state = 'pending';",
                {"r": requester_id, "d": decliner_id})
            return cur.rowcount > 0


def remove(user_a: int, user_b: int) -> None:
    """Remove an accepted connection (either party); idempotent."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM connections"
                " WHERE ((user_id = %(a)s AND friend_id = %(b)s)"
                "     OR (user_id = %(b)s AND friend_id = %(a)s));",
                {"a": user_a, "b": user_b})


def are_connected(user_a: int, user_b: int) -> bool:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM connections WHERE state = 'accepted'"
                " AND ((user_id = %(a)s AND friend_id = %(b)s)"
                "   OR (user_id = %(b)s AND friend_id = %(a)s));",
                {"a": user_a, "b": user_b})
            return cur.fetchone() is not None


def list_accepted(user_id: int) -> list[dict]:
    """Accepted connections of user_id: the OTHER party's card + free_now."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT other.id AS user_id, {_CARD.replace('u.', 'other.')},"
                f"       (av.user_id IS NOT NULL) AS free_now"
                f" FROM connections c"
                f" JOIN users other ON other.id ="
                f"      CASE WHEN c.user_id = %(u)s THEN c.friend_id ELSE c.user_id END"
                f" LEFT JOIN availability av"
                f"      ON av.user_id = other.id AND av.free_until > now()"
                f" WHERE c.state = 'accepted'"
                f"   AND (c.user_id = %(u)s OR c.friend_id = %(u)s)"
                f" ORDER BY display_name;",
                {"u": user_id})
            return cur.fetchall()


def list_incoming(user_id: int) -> list[dict]:
    """Pending requests awaiting user_id's response (they asked me)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT u.id AS user_id, {_CARD}"
                f" FROM connections c JOIN users u ON u.id = c.user_id"
                f" WHERE c.friend_id = %(u)s AND c.state = 'pending'"
                f" ORDER BY c.requested_at DESC;",
                {"u": user_id})
            return cur.fetchall()


def list_outgoing(user_id: int) -> list[dict]:
    """Pending requests user_id has sent (I asked them)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT u.id AS user_id, {_CARD}"
                f" FROM connections c JOIN users u ON u.id = c.friend_id"
                f" WHERE c.user_id = %(u)s AND c.state = 'pending'"
                f" ORDER BY c.requested_at DESC;",
                {"u": user_id})
            return cur.fetchall()
