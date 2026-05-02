"""
Read-only user queries for the admin dashboard.

Mutating user operations live in webapp/auth/users.py — this module only
exposes the aggregate / list views the admin page needs.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

from psycopg.rows import dict_row

from webapp.db import get_pool


@dataclass(frozen=True)
class AdminUserRow:
    id: int
    email: str
    created_at: datetime
    email_verified_at: Optional[datetime]
    last_login_at: Optional[datetime]

    @property
    def is_verified(self) -> bool:
        return self.email_verified_at is not None


@dataclass(frozen=True)
class UserStats:
    total: int
    verified: int
    unverified: int
    new_last_7d: int
    new_last_30d: int
    active_last_7d: int

    @property
    def verified_pct(self) -> int:
        if self.total == 0:
            return 0
        return round(100 * self.verified / self.total)


def list_users(*, limit: int = 500) -> list[AdminUserRow]:
    """Newest users first. `limit` keeps the page bounded if user count
    grows; default is plenty for the foreseeable future."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT id, email, created_at, email_verified_at, last_login_at
                FROM users
                ORDER BY created_at DESC
                LIMIT %s;
                """,
                (limit,),
            )
            rows = cur.fetchall()
    return [
        AdminUserRow(
            id=r["id"],
            email=r["email"],
            created_at=r["created_at"],
            email_verified_at=r["email_verified_at"],
            last_login_at=r["last_login_at"],
        )
        for r in rows
    ]


def get_user_stats() -> UserStats:
    """Single round-trip aggregate query for the dashboard cards."""
    now = datetime.now(timezone.utc)
    seven_days_ago = now - timedelta(days=7)
    thirty_days_ago = now - timedelta(days=30)

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT
                    COUNT(*) AS total,
                    COUNT(email_verified_at) AS verified,
                    COUNT(*) FILTER (WHERE created_at >= %s) AS new_7d,
                    COUNT(*) FILTER (WHERE created_at >= %s) AS new_30d,
                    COUNT(*) FILTER (WHERE last_login_at >= %s) AS active_7d
                FROM users;
                """,
                (seven_days_ago, thirty_days_ago, seven_days_ago),
            )
            row = cur.fetchone()

    total = row["total"] or 0
    verified = row["verified"] or 0
    return UserStats(
        total=total,
        verified=verified,
        unverified=total - verified,
        new_last_7d=row["new_7d"] or 0,
        new_last_30d=row["new_30d"] or 0,
        active_last_7d=row["active_7d"] or 0,
    )
