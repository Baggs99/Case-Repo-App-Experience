"""
Audit log for authenticated case PDF access (in-browser view vs download).

Rows are written when users hit ``GET /files/cases/{case_id}`` (**view**) or
``GET /api/cases/{case_id}/download`` (**download**). Legacy ``GET /files/{key}``
URLs are not logged (no stable case id).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Literal, Optional

from psycopg.rows import dict_row

from webapp.db import get_pool

logger = logging.getLogger(__name__)

AccessKind = Literal["view", "download"]


@dataclass(frozen=True)
class CaseAccessRow:
    id: int
    case_id: int
    case_title: str
    source_school: Optional[str]
    kind: str
    created_at: datetime


def record_case_access(user_id: int, case_id: int, kind: AccessKind) -> None:
    """Best-effort insert — PDF delivery succeeds even if logging fails."""
    try:
        with get_pool().connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO case_access_events (user_id, case_id, kind)
                    VALUES (%s, %s, %s);
                    """,
                    (user_id, case_id, kind),
                )
    except Exception:
        logger.exception(
            "Failed to record case access user_id=%s case_id=%s kind=%s",
            user_id,
            case_id,
            kind,
        )


def list_case_access_for_user(user_id: int, *, limit: int = 200) -> list[CaseAccessRow]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                """
                SELECT e.id, e.case_id, c.case_title, c.source_school, e.kind,
                       e.created_at
                FROM case_access_events e
                JOIN cases c ON c.id = e.case_id
                WHERE e.user_id = %s
                ORDER BY e.created_at DESC
                LIMIT %s;
                """,
                (user_id, limit),
            )
            rows = cur.fetchall()
    return [
        CaseAccessRow(
            id=r["id"],
            case_id=r["case_id"],
            case_title=r["case_title"],
            source_school=r["source_school"],
            kind=r["kind"],
            created_at=r["created_at"],
        )
        for r in rows
    ]
