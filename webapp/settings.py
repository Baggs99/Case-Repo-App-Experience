"""
Web app settings. Reads environment variables (already loaded from .env
by the entry point) and exposes them through a single `settings` object
so route handlers don't sprinkle os.environ access everywhere.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Settings:
    database_url: str
    debug: bool
    templates_dir: Path
    static_dir: Path
    pdf_route_prefix: str
    search_result_limit: int
    admin_emails: frozenset[str]

    def is_admin(self, email: str | None) -> bool:
        """True iff `email` is in the admin allowlist (case-insensitive)."""
        if not email:
            return False
        return email.strip().lower() in self.admin_emails


def _parse_admin_emails(raw: str | None) -> frozenset[str]:
    """Parse ADMIN_EMAILS env var ('a@x.edu, b@x.edu') into a normalized set."""
    if not raw:
        return frozenset()
    return frozenset(
        e.strip().lower() for e in raw.split(",") if e.strip()
    )


def load_settings() -> Settings:
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        raise RuntimeError(
            "DATABASE_URL is not set. Add it to .env or your shell environment."
        )

    return Settings(
        database_url      = db_url,
        debug             = os.environ.get("WEBAPP_DEBUG", "false").lower() in ("1", "true", "yes"),
        templates_dir     = REPO_ROOT / "webapp" / "templates",
        static_dir        = REPO_ROOT / "webapp" / "static",
        pdf_route_prefix  = "/files",
        search_result_limit = int(os.environ.get("WEBAPP_RESULT_LIMIT", "100")),
        admin_emails      = _parse_admin_emails(os.environ.get("ADMIN_EMAILS")),
    )
