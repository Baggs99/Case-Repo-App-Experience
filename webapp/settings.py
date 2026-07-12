"""
Web app settings. Reads environment variables (already loaded from .env
by the entry point) and exposes them through a single `settings` object
so route handlers don't sprinkle os.environ access everywhere.
"""

from __future__ import annotations

import json
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
    #: HTTPS origin (bucket public URL / custom domain) for preview JPEGs — no path suffix.
    #: Reads ``R2_PUBLIC_BASE_URL`` first, then ``CASE_PREVIEW_PUBLIC_BASE_URL``.
    #: With ``preview_public_slug``, pages load from ``{base}/previews/{slug}/page-NNN.jpg``.
    case_preview_public_base_url: str | None
    #: RTCPeerConnection.iceServers for practice calls (ICE_SERVERS_JSON env).
    #: Default is STUN-only; TURN entries are added at launch (INTEGRATION.md A2/O2).
    ice_servers: tuple

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

    preview_base = (
        os.environ.get("R2_PUBLIC_BASE_URL", "").strip()
        or os.environ.get("CASE_PREVIEW_PUBLIC_BASE_URL", "").strip()
    )

    ice_raw = os.environ.get("ICE_SERVERS_JSON", "").strip()
    if ice_raw:
        ice_servers = tuple(json.loads(ice_raw))
    else:
        ice_servers = ({"urls": ["stun:stun.l.google.com:19302"]},)

    return Settings(
        database_url      = db_url,
        debug             = os.environ.get("WEBAPP_DEBUG", "false").lower() in ("1", "true", "yes"),
        templates_dir     = REPO_ROOT / "webapp" / "templates",
        static_dir        = REPO_ROOT / "webapp" / "static",
        pdf_route_prefix  = "/files",
        search_result_limit = int(os.environ.get("WEBAPP_RESULT_LIMIT", "100")),
        admin_emails      = _parse_admin_emails(os.environ.get("ADMIN_EMAILS")),
        case_preview_public_base_url = preview_base or None,
        ice_servers       = ice_servers,
    )
