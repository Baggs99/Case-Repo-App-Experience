"""
Playwright screenshot capture for the deck.

Assumes the demo server is already running on http://127.0.0.1:8765.
Outputs PNGs into presentation/screenshots/.

Usage:
    # Terminal 1
    python presentation/demo_server.py

    # Terminal 2
    python presentation/capture_screenshots.py
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = Path(__file__).resolve().parent / "screenshots"
BASE = "http://127.0.0.1:8765"

VIEWPORT = {"width": 1440, "height": 900}


def _wait_for_server(timeout_s: int = 30) -> None:
    """Block until the demo server is responding (or fail loudly)."""
    import urllib.request
    deadline = time.time() + timeout_s
    last_err = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(BASE + "/", timeout=2) as r:
                if r.status == 200:
                    return
        except Exception as exc:  # noqa: BLE001
            last_err = exc
        time.sleep(0.5)
    raise SystemExit(
        f"Demo server not responding at {BASE} within {timeout_s}s. "
        f"Start it with: python presentation/demo_server.py\n"
        f"Last error: {last_err}"
    )


def _capture(page: Page, url: str, filename: str, *, full_page: bool = True,
             wait_for: str | None = None, after_load_ms: int = 800) -> None:
    """Navigate to `url` and write a PNG to OUT_DIR/filename."""
    print(f"  capturing {filename:35s} <- {url}")
    page.goto(BASE + url, wait_until="networkidle")
    if wait_for:
        page.wait_for_selector(wait_for, timeout=5000)
    # Small extra wait so HTMX-driven transitions / chart paints settle.
    page.wait_for_timeout(after_load_ms)
    out = OUT_DIR / filename
    page.screenshot(path=str(out), full_page=full_page)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    _wait_for_server()

    with sync_playwright() as pw:
        # Use Chromium's PDF plugin so the iframe in /cases/1 actually
        # renders. Default headless mode disables it.
        browser = pw.chromium.launch(args=["--enable-features=PDFExtension"])
        ctx = browser.new_context(
            viewport=VIEWPORT,
            device_scale_factor=2,  # crisp on high-res slides
        )
        page = ctx.new_page()

        # 1. Browse / landing — viewport crop showing search + first ~6 cards
        _capture(page, "/", "01_browse.png", full_page=False)

        # 2. Same view but full-page (long scroll) for "look how much catalog
        #    we have" appeal on the by-the-numbers slide
        _capture(page, "/", "01b_browse_fullpage.png", full_page=True)

        # 3. Search with query — viewport, results visible
        _capture(page, "/?q=retirement", "02_search_query.png",
                 full_page=False)

        # 4. Filter by industry + difficulty — viewport
        _capture(page, "/?industry=Technology&difficulty=Hard",
                 "03_filtered.png", full_page=False)

        # 5. Case detail — the iframe is finicky in headless. Capture
        #    viewport-only (shows metadata card + start of PDF) and a
        #    metadata-only crop above the iframe for the cleanest framing.
        _capture(page, "/cases/1", "04_case_detail.png",
                 full_page=False, wait_for="iframe", after_load_ms=2500)

        # 6. Admin users page — viewport
        _capture(page, "/admin/users", "05_admin_users.png",
                 full_page=False)

        # 7. Tight crop on the case-detail metadata card (clean hero for
        #    the product slide)
        page.goto(BASE + "/cases/1", wait_until="networkidle")
        page.wait_for_timeout(800)
        card = page.locator("div.bg-white.rounded-lg.border.shadow-sm").first
        card.screenshot(path=str(OUT_DIR / "06_case_card.png"))
        print(f"  capturing {'06_case_card.png':35s} (card only)")

        browser.close()

    print(f"\nWrote {len(list(OUT_DIR.glob('*.png')))} screenshots to {OUT_DIR}")


if __name__ == "__main__":
    main()
