"""
Configure logging for the case-splitter pipeline.

Call setup_logging() once at startup (in main.py).  All other modules
use `logging.getLogger(__name__)` as normal.
"""

import logging
import sys
from pathlib import Path
from typing import Optional


def setup_logging(
    verbose: bool = False,
    log_file: Optional[Path] = None,
) -> None:
    """
    Initialise the root logger with a console handler and an optional file handler.

    Args:
        verbose:  If True the console handler is set to DEBUG; otherwise INFO.
        log_file: Optional path for a full DEBUG log file.  Parent directories
                  are created automatically.
    """
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)  # capture everything; handlers filter

    fmt_console = logging.Formatter(
        "%(asctime)s  %(levelname)-8s  %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
    fmt_file = logging.Formatter(
        "%(asctime)s  %(levelname)-8s  %(name)s: %(message)s"
    )

    # Console — try to force UTF-8 so PDF-extracted unicode doesn't blow up
    # the Windows cp1252 console encoder. Silently no-op on older Pythons.
    console_stream = sys.stdout
    try:
        console_stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
    except Exception:
        pass
    ch = logging.StreamHandler(console_stream)
    ch.setLevel(logging.DEBUG if verbose else logging.INFO)
    ch.setFormatter(fmt_console)
    root.addHandler(ch)

    # File (always DEBUG-level when enabled)
    if log_file is not None:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        fh = logging.FileHandler(log_file, encoding="utf-8")
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(fmt_file)
        root.addHandler(fh)

    # Quiet noisy third-party libraries even at --verbose. The OpenAI SDK's
    # DEBUG output dumps full request bodies (including base64 / unicode
    # from PDF text) which makes the console unreadable and can trip the
    # Windows console encoder. Bumping them to WARNING keeps our own
    # pipeline DEBUG logs visible.
    for noisy in ("httpx", "httpcore", "openai"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
