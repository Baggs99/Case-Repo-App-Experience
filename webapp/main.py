"""
FastAPI app for the Case Repo website.

Run via:
    python main.py serve            # convenience wrapper
    uvicorn webapp.main:app --reload  # direct
"""

from __future__ import annotations

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from urllib.parse import quote as urlquote


# ── .env loading (so `uvicorn webapp.main:app` works without main.py) ──────────

def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


_load_dotenv(Path(__file__).resolve().parents[1] / ".env")


# ── App ────────────────────────────────────────────────────────────────────────

from webapp.auth.dependencies import RedirectToLogin
from webapp.db import close_pool, init_pool
from webapp.middleware import SessionMiddleware
from webapp.push.events import push_enabled
from webapp.push.starting_soon import starting_soon_loop
from webapp.routes import admin as admin_routes
from webapp.routes import api_v1 as api_v1_routes
from webapp.routes import auth as auth_routes
from webapp.routes import files as files_routes
from webapp.routes import exhibits as exhibits_routes
from webapp.routes import pages as pages_routes
from webapp.routes import practice as practice_routes
from webapp.routes import practice_exhibits as practice_exhibits_routes
from webapp.routes import practice_feedback as practice_feedback_routes
from webapp.routes import practice_recordings as practice_recordings_routes
from webapp.routes import proposals as proposals_routes
from webapp.routes import queues as queues_routes
from webapp.routes import rooms as rooms_routes
from webapp.routes import search as search_routes
from webapp.routes import signal_ws as signal_ws_routes
from webapp.routes import votes as votes_routes
from webapp.settings import load_settings


logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Open the Postgres pool at startup, close it cleanly at shutdown."""
    settings = load_settings()
    app.state.settings = settings

    init_pool(settings.database_url)
    logger.info("Connected to Postgres at %s", _safe_url(settings.database_url))

    app.state.templates = Jinja2Templates(directory=settings.templates_dir)

    # Single-worker constraint: with multiple workers each would run its own
    # loop (wasteful, though still correct — the UPDATE...RETURNING claim in
    # notify_starting_soon() is atomic, so no session is ever double-pushed).
    starting_soon_task = None
    if push_enabled(settings):
        starting_soon_task = asyncio.create_task(starting_soon_loop())

    yield

    if starting_soon_task is not None:
        starting_soon_task.cancel()
        try:
            await starting_soon_task
        except asyncio.CancelledError:
            pass

    close_pool()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Case Repo",
        description="Consulting cases, searchable.",
        lifespan=lifespan,
    )

    # Session middleware runs first — sets request.state.user on every
    # request before any route handler or dependency executes.
    app.add_middleware(SessionMiddleware)

    @app.exception_handler(RedirectToLogin)
    async def _redirect_to_login(request: Request, exc: RedirectToLogin):
        # HTMX requests (sent with the HX-Request header) should not redirect
        # the embedded fragment — they should trigger a full-page reload to
        # the login form. Send 401 + HX-Redirect header.
        if request.headers.get("hx-request") == "true":
            return RedirectResponse(
                url=f"/login?next={urlquote(exc.next_url)}",
                status_code=401,
                headers={"HX-Redirect": f"/login?next={urlquote(exc.next_url)}"},
            )
        return RedirectResponse(
            url=f"/login?next={urlquote(exc.next_url)}",
            status_code=303,
        )

    settings = load_settings()
    if settings.static_dir.exists():
        app.mount("/static", StaticFiles(directory=settings.static_dir), name="static")

    app.include_router(auth_routes.router)
    app.include_router(pages_routes.router)
    app.include_router(search_routes.router)
    app.include_router(files_routes.router)
    app.include_router(votes_routes.router)
    app.include_router(admin_routes.router)
    app.include_router(rooms_routes.router)
    app.include_router(practice_routes.router)
    app.include_router(practice_exhibits_routes.router)
    app.include_router(practice_feedback_routes.router)
    app.include_router(practice_recordings_routes.router)
    app.include_router(queues_routes.router)
    app.include_router(proposals_routes.router)
    app.include_router(signal_ws_routes.router)
    app.include_router(exhibits_routes.router)
    app.include_router(api_v1_routes.router)

    return app


def _safe_url(url: str) -> str:
    """Strip the password from a connection URL before logging."""
    try:
        from urllib.parse import urlparse, urlunparse
        u = urlparse(url)
        if u.password:
            netloc = f"{u.username}:***@{u.hostname}"
            if u.port:
                netloc += f":{u.port}"
            return urlunparse(u._replace(netloc=netloc))
    except Exception:
        pass
    return url


app = create_app()
