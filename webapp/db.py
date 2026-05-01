"""
Postgres connection pool wrapper.

Why a pool: opening a Postgres connection takes ~10ms (TCP + TLS + auth).
At any non-trivial request rate that becomes the dominant latency. A
pool keeps a small set of connections warm and hands them to request
handlers in microseconds.

Usage in routes:
    from webapp.db import get_pool

    @router.get("/...")
    def handler():
        with get_pool().connection() as conn:
            with conn.cursor(row_factory=dict_row) as cur:
                cur.execute("SELECT ...")
                ...
"""

from __future__ import annotations

import logging
from typing import Optional

from psycopg_pool import ConnectionPool

logger = logging.getLogger(__name__)

_pool: Optional[ConnectionPool] = None


def init_pool(database_url: str, *, min_size: int = 2, max_size: int = 10) -> ConnectionPool:
    """Initialize the global connection pool. Called once at app startup."""
    global _pool
    if _pool is not None:
        logger.warning("Connection pool already initialized; ignoring re-init")
        return _pool

    logger.info("Opening Postgres pool (min=%d, max=%d)", min_size, max_size)
    _pool = ConnectionPool(
        conninfo=database_url,
        min_size=min_size,
        max_size=max_size,
        # Wait up to 10s for a connection before giving up — protects
        # against silent hangs if the DB is unreachable.
        timeout=10.0,
        open=True,
    )
    return _pool


def close_pool() -> None:
    """Close the global pool. Called on app shutdown."""
    global _pool
    if _pool is not None:
        logger.info("Closing Postgres pool")
        _pool.close()
        _pool = None


def get_pool() -> ConnectionPool:
    """Get the global pool. Raises if init_pool() has not been called."""
    if _pool is None:
        raise RuntimeError(
            "Connection pool not initialized. Call init_pool() in app startup."
        )
    return _pool
