# Presentation builder

Reproducible 7-slide deck about the live Case Repo web app, with real
screenshots captured against a stubbed local copy of the FastAPI app
(no Postgres, R2, or production credentials required).

## What's here

| File | Purpose |
| --- | --- |
| `demo_server.py` | Boots the real FastAPI app on `127.0.0.1:8765`. Patches every DB / storage / auth call so it runs against `output/case_catalog.csv` and a bundled sample PDF. Auto-attaches a fake `demo@yale.edu` admin session. |
| `capture_screenshots.py` | Drives Playwright (headless Chromium) at the demo server and writes 7 PNGs into `screenshots/`. |
| `build_deck.py` | Reads the catalog + screenshots and writes `Case_Repo_Product.pptx` (16:9, 7 slides). |
| `screenshots/` | Generated PNGs. Gitignored. |
| `Case_Repo_Product.pptx` | Final deck. Gitignored — rebuild any time. |

## Rebuild from scratch

In two terminals:

```powershell
# Terminal 1 — demo server (leave running)
python presentation/demo_server.py

# Terminal 2 — capture + build
python presentation/capture_screenshots.py
python presentation/build_deck.py
```

Then open `presentation/Case_Repo_Product.pptx`.

## Iterating on slides

Edit `build_deck.py`. The slide builders (`slide_title`, `slide_problem`,
`slide_browse`, …) are independent — swap, reorder, or change copy in
`SLIDE_BUILDERS`. Re-run `build_deck.py`; no need to re-capture.

## Iterating on screenshots

Edit `capture_screenshots.py` to change URLs, viewport size, or which
elements are cropped. Re-run; no need to rebuild the deck unless you
also tweak `build_deck.py`.

To capture a different case in slide 4, change the `/cases/1` URL — the
demo server assigns IDs sequentially from the catalog (1 = first row).

## Caveats

- **PDF iframe is blank in headless Chromium.** Slide 4 uses a tight
  metadata-card crop (`06_case_card.png`) instead. To get a real PDF
  preview, either run capture under `headless=False` and grant the
  PDF plugin time to render, or use a screenshot you take in a real
  browser session and drop into `screenshots/`.
- **`demo@yale.edu` is hardcoded** as the demo session. To screenshot
  the unauthenticated `/login` page, comment out the dispatch override
  in `demo_server.py` for that capture.
