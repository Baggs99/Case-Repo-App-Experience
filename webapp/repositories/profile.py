"""
Purpose: Read/update the profile fields on users (display_name, bio,
         linkedin_url, photo_key) plus the read-only school binding.
Inputs:  users + schools tables; DATABASE_URL-backed pool.
Outputs: UPDATEs users rows (never touches email/password/school_id here).
Run:     imported by webapp/routes/profile.py.
"""

from __future__ import annotations

from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.repositories.schools import get_school_by_id


def get_profile(user_id: int) -> Optional[dict]:
    """Return the profile dict for user_id, or None if the user doesn't exist."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, email, display_name, bio, linkedin_url,
                       photo_key, school_id
                FROM users WHERE id = %s;
                """,
                (user_id,),
            )
            row = cur.fetchone()
    if row is None:
        return None
    school = get_school_by_id(row["school_id"]) if row["school_id"] else None
    return {
        "id": row["id"],
        "email": row["email"],
        "display_name": row["display_name"],
        "bio": row["bio"],
        "linkedin_url": row["linkedin_url"],
        "photo_key": row["photo_key"],
        "school": school,
    }


def update_profile(
    user_id: int,
    *,
    display_name: Optional[str],
    bio: Optional[str],
    linkedin_url: Optional[str],
) -> dict:
    """Update only the fields that are not None (COALESCE keeps the rest).

    Returns the fresh profile. Callers validate lengths before calling.
    """
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE users SET
                    display_name = COALESCE(%s, display_name),
                    bio          = COALESCE(%s, bio),
                    linkedin_url = COALESCE(%s, linkedin_url)
                WHERE id = %s;
                """,
                (display_name, bio, linkedin_url, user_id),
            )
    return get_profile(user_id)


def set_photo_key(user_id: int, photo_key: str) -> None:
    """Point the user's avatar at a storage key (avatars/{user_id}.{ext})."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE users SET photo_key = %s WHERE id = %s;",
                (photo_key, user_id),
            )
