"""Rewrite a PDF so it contains only the first N pages (atomic replace).

Usage:
  python scripts/trim_pdf_first_pages.py <path-to.pdf> <page_count>

Requires PyMuPDF (fitz), same as the rest of the pipeline.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow running from repo root without PYTHONPATH hacks
_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from utils.pdf_utils import rewrite_pdf_first_n_pages  # noqa: E402


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1]).resolve()
    n = int(sys.argv[2])
    changed, msg = rewrite_pdf_first_n_pages(path, n)
    print(f"{path}: {msg}")
    if not changed and not msg.startswith("no-op"):
        sys.exit(1)


if __name__ == "__main__":
    main()
