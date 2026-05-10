"""
Demo server for screenshot capture.

Boots the real FastAPI app from `webapp/` but patches every database and
storage call so it runs without Postgres, R2, or any production dep.
The data comes straight from `output/case_catalog.csv` so the screenshots
show real cases. A fake "demo@yale.edu" admin session is auto-attached
to every request.

Usage:
    python presentation/demo_server.py        # foreground, Ctrl+C to stop
"""

from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from unittest.mock import MagicMock

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

CSV_PATH = REPO_ROOT / "output" / "case_catalog.csv"


def _find_demo_pdf() -> Path:
    """Find any sufficiently small PDF on disk to use as the iframe content
    in the case-detail screenshot. Tries a few likely spots."""
    candidates = [
        REPO_ROOT / "Yale" / "Darden 2017.pdf",
        REPO_ROOT / "Yale" / "Columbia 2017.pdf",
        REPO_ROOT / "Yale" / "Booth 2021.pdf",
        REPO_ROOT / "Booth 2021.pdf",
    ]
    for p in candidates:
        if p.exists():
            return p
    # Fallback: walk the workspace for the first PDF we find.
    for p in REPO_ROOT.rglob("*.pdf"):
        if p.is_file() and p.stat().st_size < 50 * 1024 * 1024:
            return p
    return REPO_ROOT / "DEMO_PDF_NOT_FOUND.pdf"


DEMO_PDF_PATH = _find_demo_pdf()


# ── Env setup ─────────────────────────────────────────────────────────────────

# Force-set BEFORE webapp imports so the demo always controls these,
# regardless of what's in .env or the parent shell.
os.environ["DATABASE_URL"] = "postgresql://stub@localhost/stub"
os.environ["ADMIN_EMAILS"] = "demo@yale.edu"
os.environ["STORAGE_BACKEND"] = "local"
os.environ["EMAIL_BACKEND"] = "console"


# ── DB pool stub ──────────────────────────────────────────────────────────────

# Patch ConnectionPool so init_pool() doesn't actually connect.
import webapp.db as _db_mod  # noqa: E402
_db_mod.ConnectionPool = lambda **kwargs: MagicMock()


# ── Load the catalog once ─────────────────────────────────────────────────────

_df = pd.read_csv(CSV_PATH).fillna("")
# Stable integer ids for /cases/{id}.
_df = _df.reset_index().rename(columns={"index": "id"})
_df["id"] = _df["id"].astype(int) + 1


def _row_to_case_dict(row: pd.Series) -> dict:
    """Shape a CSV row to match what the templates expect."""
    def _str(col: str) -> Optional[str]:
        v = row.get(col, "")
        return str(v) if v not in ("", None) else None

    def _int(col: str) -> Optional[int]:
        v = row.get(col, "")
        try:
            return int(float(v)) if v not in ("", None) else None
        except (ValueError, TypeError):
            return None

    def _float(col: str) -> Optional[float]:
        v = row.get(col, "")
        try:
            return float(v) if v not in ("", None) else None
        except (ValueError, TypeError):
            return None

    out = {
        "id":               int(row["id"]),
        "case_title":       _str("case_title") or "(untitled)",
        "normalized_title": _str("normalized_title"),
        "source_school":    _str("source_school"),
        "source_year":      _int("source_year"),
        "industry":         _str("industry"),
        "case_type":        _str("case_type"),
        "difficulty":       _str("difficulty_normalized") or _str("difficulty"),
        "difficulty_score": _float("difficulty_score"),
        "firm":             _str("firm"),
        "interviewer_led":  _str("interviewer_led"),
        "page_count":       _int("page_count"),
        "pdf_path":         _str("output_pdf_path") or "demo.pdf",
        "created_at":       datetime.now(timezone.utc),
        "updated_at":       datetime.now(timezone.utc),
    }
    attach_industry_display(out)
    return out


# ── Repository patches ────────────────────────────────────────────────────────

import webapp.repositories.cases as _cases_repo  # noqa: E402
from webapp.industry_normalize import attach_industry_display, normalize_industry_label  # noqa: E402
from webapp.repositories.cases import FilterOptions, SearchFilters  # noqa: E402


def _fake_get_filter_options() -> FilterOptions:
    raws = [str(v) for v in _df["industry"].unique() if v and str(v).strip()]
    labels = {normalize_industry_label(r) for r in raws}
    labels.discard(None)
    return FilterOptions(
        industries=sorted(labels),
        case_types=sorted(v for v in _df["case_type"].unique() if v),
        schools=sorted(v for v in _df["source_school"].unique() if v),
        difficulties=["Easy", "Medium", "Hard"],
    )


def _fake_search_cases(filters: SearchFilters, *, limit: int = 100, **_kw):
    rows = _df
    if filters.q:
        q = filters.q.lower()
        rows = rows[rows["case_title"].str.lower().str.contains(q, na=False)]
    if filters.difficulty:
        rows = rows[rows["difficulty_normalized"] == filters.difficulty]
    if filters.industry:
        def _row_canon(s) -> Optional[str]:
            if s is None or (isinstance(s, float) and pd.isna(s)):
                return None
            return normalize_industry_label(str(s).strip())

        rows = rows[rows["industry"].map(_row_canon) == filters.industry]
    if filters.case_type:
        rows = rows[rows["case_type"] == filters.case_type]
    if filters.school:
        rows = rows[rows["source_school"] == filters.school]

    total = len(rows)

    def _diff_sort_key(d):
        return {"Easy": 0, "Medium": 1, "Hard": 2}.get(d, 99)

    rows = rows.copy()
    rows["_diff_key"] = rows["difficulty_normalized"].map(_diff_sort_key)
    rows = rows.sort_values(["_diff_key", "case_title"]).head(limit)

    return [_row_to_case_dict(r) for _, r in rows.iterrows()], total


def _fake_get_case_by_id(case_id: int):
    matches = _df[_df["id"] == case_id]
    if matches.empty:
        return None
    return _row_to_case_dict(matches.iloc[0])


_cases_repo.get_filter_options = _fake_get_filter_options
_cases_repo.search_cases = _fake_search_cases
_cases_repo.get_case_by_id = _fake_get_case_by_id
# Footer "X cases indexed" pulls from a DB COUNT(*); short-circuit it.
_cases_repo.count_all_cases = lambda **_kw: len(_df)

# Routes import these by name at module load — patch them there too.
import webapp.routes.pages as _pages_mod  # noqa: E402
_pages_mod.search_cases = _fake_search_cases
_pages_mod.get_filter_options = _fake_get_filter_options
_pages_mod.get_case_by_id = _fake_get_case_by_id
_pages_mod.count_all_cases = lambda **_kw: len(_df)
_pages_mod._count_all_cases = lambda **_kw: len(_df)
# No real votes table in the CSV demo — stub the decorator so each row
# carries zeros rather than triggering a DB lookup.
_pages_mod._attach_vote_stats = lambda rows: [
    r.update({"useful_count": 0, "not_useful_count": 0, "total_votes": 0, "useful_percentage": None})
    for r in rows
]

import webapp.routes.search as _search_mod  # noqa: E402
_search_mod.search_cases = _fake_search_cases
_search_mod.count_all_cases = lambda **_kw: len(_df)
_search_mod._attach_vote_stats = _pages_mod._attach_vote_stats


# ── Admin repo patches ────────────────────────────────────────────────────────

import webapp.repositories.users as _users_repo  # noqa: E402
from webapp.repositories.users import AdminUserRow, UserStats  # noqa: E402

_now = datetime.now(timezone.utc)
from datetime import timedelta as _td  # noqa: E402

_FAKE_USERS = [
    AdminUserRow(id=1, email="demo@yale.edu",
                 created_at=_now - _td(days=18),
                 email_verified_at=_now - _td(days=18),
                 last_login_at=_now - _td(hours=2)),
    AdminUserRow(id=2, email="alice.chen@yale.edu",
                 created_at=_now - _td(days=12),
                 email_verified_at=_now - _td(days=12),
                 last_login_at=_now - _td(days=1)),
    AdminUserRow(id=3, email="ben.kumar@yale.edu",
                 created_at=_now - _td(days=8),
                 email_verified_at=_now - _td(days=8),
                 last_login_at=_now - _td(hours=14)),
    AdminUserRow(id=4, email="caro.patel@yale.edu",
                 created_at=_now - _td(days=5),
                 email_verified_at=_now - _td(days=5),
                 last_login_at=_now - _td(hours=6)),
    AdminUserRow(id=5, email="dan.lin@yale.edu",
                 created_at=_now - _td(days=2),
                 email_verified_at=None,
                 last_login_at=None),
]


def _fake_list_users(*, limit: int = 500):
    return _FAKE_USERS[:limit]


def _fake_get_user_stats():
    total = len(_FAKE_USERS)
    verified = sum(1 for u in _FAKE_USERS if u.email_verified_at is not None)
    return UserStats(
        total=total, verified=verified, unverified=total - verified,
        new_last_7d=2, new_last_30d=total, active_last_7d=4,
    )


_users_repo.list_users = _fake_list_users
_users_repo.get_user_stats = _fake_get_user_stats

import webapp.routes.admin as _admin_mod  # noqa: E402
_admin_mod.list_users = _fake_list_users
_admin_mod.get_user_stats = _fake_get_user_stats


# ── Auth: auto-attach a verified admin user to every request ──────────────────

from webapp.auth.users import User  # noqa: E402

DEMO_USER = User(
    id=1, email="demo@yale.edu",
    email_verified_at=_now, created_at=_now - _td(days=18),
    last_login_at=_now,
)

import webapp.middleware as _mw_mod  # noqa: E402

# Replace the session middleware's dispatch so every request looks logged in.
async def _demo_dispatch(self, request, call_next):
    request.state.user = DEMO_USER
    return await call_next(request)

_mw_mod.SessionMiddleware.dispatch = _demo_dispatch


# ── Storage: serve the bundled casebook PDF for the iframe ────────────────────

import pipeline.storage as _storage_mod  # noqa: E402

class _DemoStorage:
    def url(self, _path: str) -> str:
        return "/demo-pdf"

    def get_signed_download_url(self, _path: str, *_, **__) -> str:
        return "/demo-pdf"


_storage_mod.get_storage = lambda: _DemoStorage()

# Routes import get_storage by name at module load, so patch the local
# binding too. Otherwise the route still calls the real LocalStorage.
_pages_mod.get_storage = lambda: _DemoStorage()


# ── Build the app ─────────────────────────────────────────────────────────────

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import FileResponse  # noqa: E402
from webapp.main import create_app  # noqa: E402

app: FastAPI = create_app()


@app.get("/demo-pdf")
def _demo_pdf():
    """Serve the bundled casebook so the case-detail iframe renders."""
    if DEMO_PDF_PATH.exists():
        return FileResponse(str(DEMO_PDF_PATH), media_type="application/pdf")
    return {"error": "demo PDF not found"}


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    import uvicorn
    print("\n[demo] Starting demo server on http://127.0.0.1:8765\n", flush=True)
    print(f"[demo] Catalog: {CSV_PATH} ({len(_df)} rows)", flush=True)
    print(f"[demo] Demo PDF: {DEMO_PDF_PATH} ({'present' if DEMO_PDF_PATH.exists() else 'MISSING'})", flush=True)
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")


if __name__ == "__main__":
    main()
