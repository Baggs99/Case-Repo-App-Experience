"""Rewrite a PDF so it contains only the first N pages (atomic replace).

Usage:
  python scripts/trim_pdf_first_pages.py <path-to.pdf> <page_count>

Requires PyMuPDF (fitz), same as the rest of the pipeline.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import fitz


def main() -> None:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1]).resolve()
    n = int(sys.argv[2])
    if n < 1:
        raise SystemExit("page_count must be >= 1")

    src = fitz.open(path)
    try:
        if len(src) <= n:
            print(f"No-op: {path} already has {len(src)} page(s) (<= {n}).")
            return
        dst = fitz.open()
        try:
            dst.insert_pdf(src, from_page=0, to_page=n - 1)
            tmp = path.with_suffix(".trim.tmp.pdf")
            dst.save(tmp)
        finally:
            dst.close()
    finally:
        src.close()

    os.replace(tmp, path)
    print(f"Wrote {path} with {n} page(s).")


if __name__ == "__main__":
    main()
