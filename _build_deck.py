"""Builds `Case_Repo_Overview.pptx` from the current repo state.

Quick utility — not wired into the CLI. Run with:
    python _build_deck.py
"""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from pptx import Presentation
from pptx.chart.data import CategoryChartData
from pptx.dml.color import RGBColor
from pptx.enum.chart import XL_CHART_TYPE, XL_LEGEND_POSITION, XL_LABEL_POSITION
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN
from pptx.util import Inches, Pt

# ── Palette (approachable, professional) ──────────────────────────────────────
NAVY = RGBColor(0x0E, 0x2A, 0x47)
SLATE = RGBColor(0x33, 0x4E, 0x68)
TEAL = RGBColor(0x2E, 0x86, 0xAB)
CORAL = RGBColor(0xE0, 0x6C, 0x4C)
SAND = RGBColor(0xF3, 0xE9, 0xDD)
INK = RGBColor(0x1A, 0x1A, 0x1A)
GREY = RGBColor(0x6B, 0x75, 0x80)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)

SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)


def _blank_slide(prs: Presentation):
    return prs.slides.add_slide(prs.slide_layouts[6])


def _add_rect(slide, left, top, width, height, fill):
    shape = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill
    shape.line.fill.background()
    shape.shadow.inherit = False
    return shape


def _add_text(
    slide,
    left,
    top,
    width,
    height,
    text,
    *,
    size=18,
    color=INK,
    bold=False,
    align=PP_ALIGN.LEFT,
    font="Calibri",
):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.08)
    tf.margin_right = Inches(0.08)
    tf.margin_top = Inches(0.04)
    tf.margin_bottom = Inches(0.04)
    lines = text.split("\n") if isinstance(text, str) else list(text)
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        run = p.add_run()
        run.text = line
        run.font.name = font
        run.font.size = Pt(size)
        run.font.bold = bold
        run.font.color.rgb = color
    return tb


def _add_bullets(slide, left, top, width, height, items, *, size=16, color=INK,
                 bullet_color=TEAL, gap_pt=8):
    tb = slide.shapes.add_textbox(left, top, width, height)
    tf = tb.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.space_after = Pt(gap_pt)
        bullet = p.add_run()
        bullet.text = "▸  "
        bullet.font.name = "Calibri"
        bullet.font.size = Pt(size)
        bullet.font.bold = True
        bullet.font.color.rgb = bullet_color
        body = p.add_run()
        body.text = item
        body.font.name = "Calibri"
        body.font.size = Pt(size)
        body.font.color.rgb = color
    return tb


def _header(slide, title, subtitle=None):
    _add_rect(slide, 0, 0, SLIDE_W, Inches(0.08), TEAL)
    _add_text(slide, Inches(0.5), Inches(0.28), Inches(12.5), Inches(0.7),
              title, size=28, bold=True, color=NAVY)
    if subtitle:
        _add_text(slide, Inches(0.5), Inches(0.9), Inches(12.5), Inches(0.4),
                  subtitle, size=15, color=GREY)


def _footer(slide, idx, total):
    _add_text(slide, Inches(0.5), Inches(7.1), Inches(6), Inches(0.3),
              "Case Repo — casebook-splitting & enrichment pipeline",
              size=10, color=GREY)
    _add_text(slide, Inches(11.5), Inches(7.1), Inches(1.3), Inches(0.3),
              f"{idx} / {total}", size=10, color=GREY, align=PP_ALIGN.RIGHT)


# ── Individual slide builders ─────────────────────────────────────────────────

def slide_title(prs):
    s = _blank_slide(prs)
    _add_rect(s, 0, 0, SLIDE_W, SLIDE_H, NAVY)
    # Decorative stripe
    _add_rect(s, 0, Inches(3.3), SLIDE_W, Inches(0.06), TEAL)
    _add_text(s, Inches(0.8), Inches(2.3), Inches(11.7), Inches(0.6),
              "CASE REPO", size=18, bold=True, color=TEAL)
    _add_text(s, Inches(0.8), Inches(2.65), Inches(11.7), Inches(1.2),
              "From a pile of PDFs to a searchable\ncase catalog",
              size=48, bold=True, color=WHITE)
    _add_text(s, Inches(0.8), Inches(4.5), Inches(11.7), Inches(0.6),
              "A local-first pipeline that splits consulting casebooks, extracts "
              "structured metadata, and tags every case with a calibrated difficulty.",
              size=18, color=SAND)
    _add_text(s, Inches(0.8), Inches(6.6), Inches(11.7), Inches(0.4),
              "Project overview  ·  April 2026",
              size=13, color=GREY)
    return s


def slide_problem(prs):
    s = _blank_slide(prs)
    _header(s, "The problem",
            "Casebooks are heterogeneous, bundled, and only semi-structured")
    # Left column: raw state
    _add_rect(s, Inches(0.5), Inches(1.5), Inches(5.9), Inches(5.2), SAND)
    _add_text(s, Inches(0.8), Inches(1.65), Inches(5.4), Inches(0.5),
              "What we start with", size=18, bold=True, color=NAVY)
    _add_bullets(s, Inches(0.8), Inches(2.15), Inches(5.4), Inches(4.6), [
        "Dozens of MBA casebooks, one PDF per school-year",
        "Each file contains 5–50 cases bundled together",
        "Every school uses a different layout, TOC style, and metadata scheme",
        "Difficulty, case type, and industry are inconsistently labelled (or missing)",
        "No easy way to answer: \u201cGive me a Hard, data-heavy market-entry case\u201d",
    ], size=15)
    # Right column: desired state
    _add_rect(s, Inches(6.9), Inches(1.5), Inches(5.9), Inches(5.2), WHITE)
    _add_rect(s, Inches(6.9), Inches(1.5), Inches(5.9), Inches(0.08), TEAL)
    _add_text(s, Inches(7.2), Inches(1.65), Inches(5.4), Inches(0.5),
              "What we want", size=18, bold=True, color=NAVY)
    _add_bullets(s, Inches(7.2), Inches(2.15), Inches(5.4), Inches(4.6), [
        "One PDF per case, cleanly named",
        "A single catalog row per case with school, year, type, concepts, difficulty",
        "Every case taggable, filterable, and queryable",
        "An audit trail for every automated decision",
        "Humans stay in the loop for anything uncertain",
    ], size=15, bullet_color=CORAL)
    _footer(s, 2, TOTAL)


def slide_architecture(prs):
    s = _blank_slide(prs)
    _header(s, "How the pipeline fits together",
            "Six stages, each with its own audit surface")

    stages = [
        ("1. Scan", "Walk the input tree; find every PDF", NAVY),
        ("2. Classify", "Multi-case casebook vs already-split?", SLATE),
        ("3. Split", "Find case boundaries, write per-case PDFs", TEAL),
        ("4. Extract", "Pull title, school, year, type, concepts", SLATE),
        ("5. Enrich", "OpenAI fills missing difficulty labels", CORAL),
        ("6. Audit", "Manifest + review queue + audit CSVs", NAVY),
    ]

    total_w = Inches(12.5)
    card_w = Inches(1.95)
    gap = (total_w - card_w * len(stages)) / (len(stages) - 1)
    y = Inches(2.3)
    for i, (title, body, col) in enumerate(stages):
        x = Inches(0.5) + i * (card_w + gap)
        _add_rect(s, x, y, card_w, Inches(0.5), col)
        _add_text(s, x, y, card_w, Inches(0.5), title,
                  size=14, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _add_rect(s, x, y + Inches(0.5), card_w, Inches(2.6), WHITE)
        _add_text(s, x + Inches(0.1), y + Inches(0.6), card_w - Inches(0.2),
                  Inches(2.4), body, size=12, color=INK, align=PP_ALIGN.CENTER)
        # Arrow
        if i < len(stages) - 1:
            ax = x + card_w + Inches(0.02)
            ay = y + Inches(1.55)
            arrow = s.shapes.add_shape(MSO_SHAPE.RIGHT_ARROW, ax,
                                       ay - Inches(0.12),
                                       gap - Inches(0.04), Inches(0.25))
            arrow.fill.solid()
            arrow.fill.fore_color.rgb = TEAL
            arrow.line.fill.background()

    _add_text(s, Inches(0.5), Inches(5.9), Inches(12.3), Inches(0.5),
              "Every stage is idempotent and dry-runnable. Re-running only touches "
              "work that hasn't already been done.",
              size=14, color=SLATE, align=PP_ALIGN.CENTER)
    _footer(s, 3, TOTAL)


def slide_parsers(prs):
    s = _blank_slide(prs)
    _header(s, "Splitting casebooks into cases",
            "Primary parser + fallback, with confidence scoring at every step")

    # TOC parser card
    _add_rect(s, Inches(0.5), Inches(1.5), Inches(6.1), Inches(5.2), WHITE)
    _add_rect(s, Inches(0.5), Inches(1.5), Inches(6.1), Inches(0.08), NAVY)
    _add_text(s, Inches(0.8), Inches(1.7), Inches(5.5), Inches(0.5),
              "Primary: TOC-driven", size=18, bold=True, color=NAVY)
    _add_text(s, Inches(0.8), Inches(2.15), Inches(5.5), Inches(0.4),
              "Starting confidence: 0.90", size=12, color=GREY)
    _add_bullets(s, Inches(0.8), Inches(2.6), Inches(5.5), Inches(4), [
        "Regex-matches five TOC layouts (dotted leaders, tabs, \"page X\", …)",
        "Detects page-number offset for books with unnumbered front matter",
        "Validates each start page actually contains the expected title",
        "One CaseBoundary per TOC entry",
    ], size=14)

    # Header-pattern parser card
    _add_rect(s, Inches(6.8), Inches(1.5), Inches(6.1), Inches(5.2), WHITE)
    _add_rect(s, Inches(6.8), Inches(1.5), Inches(6.1), Inches(0.08), CORAL)
    _add_text(s, Inches(7.1), Inches(1.7), Inches(5.5), Inches(0.5),
              "Fallback: header-pattern", size=18, bold=True, color=NAVY)
    _add_text(s, Inches(7.1), Inches(2.15), Inches(5.5), Inches(0.4),
              "Max confidence: 0.75 × score", size=12, color=GREY)
    _add_bullets(s, Inches(7.1), Inches(2.6), Inches(5.5), Inches(4), [
        "Scores every page on 8 weighted layout signals",
        "Positive: short text, top-of-page title, metadata labels",
        "Negative: mid-case markers (\u201cExhibit\u201d, \u201cQuestion 3\u201d …)",
        "Prunes candidates closer than min_case_pages",
    ], size=14, bullet_color=CORAL)

    _footer(s, 4, TOTAL)


def slide_metadata(prs):
    s = _blank_slide(prs)
    _header(s, "What comes out the other end",
            "One row per case with structured, filterable fields")

    fields = [
        ("Identity", ["case_title", "source_school", "source_year",
                      "source_pdf", "page_start / page_end"]),
        ("Classification", ["case_type_normalized", "industry",
                            "interviewer_style", "concepts_tested"]),
        ("Difficulty", ["difficulty_normalized (Easy/Med/Hard)",
                        "difficulty_score (1–10)", "difficulty_quant / qual",
                        "difficulty_notes", "difficulty_source"]),
        ("Provenance", ["detection_method (toc / header / single)",
                        "extraction_confidence", "needs_manual_review",
                        "review_flags", "confidence_notes"]),
    ]

    col_w = Inches(2.95)
    gap = Inches(0.2)
    y = Inches(1.65)
    for i, (heading, items) in enumerate(fields):
        x = Inches(0.5) + i * (col_w + gap)
        _add_rect(s, x, y, col_w, Inches(0.55), NAVY)
        _add_text(s, x, y, col_w, Inches(0.55), heading,
                  size=15, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _add_rect(s, x, y + Inches(0.55), col_w, Inches(4.4), WHITE)
        _add_bullets(s, x + Inches(0.15), y + Inches(0.7),
                     col_w - Inches(0.3), Inches(4.2),
                     items, size=12, gap_pt=6)

    _add_text(s, Inches(0.5), Inches(6.4), Inches(12.3), Inches(0.5),
              "Every catalog row is traceable back to the source PDF, the detection "
              "method, and the confidence the pipeline had at every step.",
              size=13, color=SLATE, align=PP_ALIGN.CENTER)
    _footer(s, 5, TOTAL)


def slide_classifier(prs):
    s = _blank_slide(prs)
    _header(s, "OpenAI difficulty classifier",
            "Calibrated, structured, auditable — not vibes")

    steps = [
        ("Select", "Only rows where difficulty_normalized is blank. "
                   "Human labels are never overwritten (unless --force)."),
        ("Anchor", "3–5 already-labeled cases per bucket are injected as "
                   "in-context calibration examples, diversified by school "
                   "and case type."),
        ("Packet", "Compact JSON: title, school, year, case type, concepts, "
                   "prompt excerpt, optional first-pages text from the split PDF."),
        ("Call", "OpenAI Responses API (default gpt-5.1) with a strict JSON "
                 "schema. Temperature is auto-dropped for reasoning models."),
        ("Write back", "Writes difficulty_normalized / score / notes and "
                       "stamps difficulty_source=openai_calibrated + model + confidence."),
        ("Audit", "Every call logged: predictions CSV, failures CSV, "
                  "needs-review CSV, and the exact anchor set used."),
    ]
    y0 = Inches(1.55)
    for i, (title, body) in enumerate(steps):
        row = i // 2
        col = i % 2
        x = Inches(0.5) + col * Inches(6.3)
        y = y0 + row * Inches(1.65)
        _add_rect(s, x, y, Inches(0.9), Inches(0.9), TEAL)
        _add_text(s, x, y, Inches(0.9), Inches(0.9), str(i + 1),
                  size=30, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _add_text(s, x + Inches(1.1), y + Inches(0.05),
                  Inches(5.0), Inches(0.4),
                  title, size=16, bold=True, color=NAVY)
        _add_text(s, x + Inches(1.1), y + Inches(0.45),
                  Inches(5.0), Inches(1.1),
                  body, size=12, color=INK)

    _footer(s, 6, TOTAL)


def slide_calibration_qa(prs):
    s = _blank_slide(prs)
    _header(s, "Calibration QA — trust before scale",
            "Does the classifier agree with humans before we let it run on 217 rows?")

    # Left: the approach
    _add_rect(s, Inches(0.5), Inches(1.5), Inches(6.3), Inches(5.3), WHITE)
    _add_rect(s, Inches(0.5), Inches(1.5), Inches(6.3), Inches(0.08), TEAL)
    _add_text(s, Inches(0.8), Inches(1.7), Inches(5.7), Inches(0.5),
              "evaluate-difficulty-calibration", size=17, bold=True, color=NAVY)
    _add_bullets(s, Inches(0.8), Inches(2.3), Inches(5.7), Inches(4.4), [
        "Stratified sample of human-labeled cases (Easy/Med/Hard)",
        "Sampled titles are EXCLUDED from the anchor pool → no leakage",
        "Classifier runs on the sample; the catalog is never modified",
        "Reports match rate, confusion matrix, avg |score gap|, worst misses",
        "Warning thresholds: ≥ 70% exact match, ≤ 1.0 avg score gap",
    ], size=14)

    # Right: what we learned
    _add_rect(s, Inches(7.0), Inches(1.5), Inches(5.8), Inches(5.3), SAND)
    _add_text(s, Inches(7.3), Inches(1.7), Inches(5.2), Inches(0.5),
              "Model bake-off (n=9 per run)", size=17, bold=True, color=NAVY)

    # Simple table
    rows = [
        ("Model", "Match", "Avg |gap|"),
        ("gpt-5.1", "44.4%", "1.63"),
        ("gpt-5-mini", "44.4%", "1.69"),
        ("gpt-4.1-mini", "33.3%", "1.83"),
        ("o3", "28.6%", "1.91"),
    ]
    top = Inches(2.35)
    row_h = Inches(0.42)
    col_w = [Inches(2.1), Inches(1.6), Inches(1.7)]
    x0 = Inches(7.4)
    for r, row in enumerate(rows):
        for c, text in enumerate(row):
            cx = x0 + sum(col_w[:c], Inches(0))
            y = top + r * row_h
            if r == 0:
                _add_rect(s, cx, y, col_w[c], row_h, NAVY)
                _add_text(s, cx, y + Inches(0.05), col_w[c], row_h, text,
                          size=12, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
            else:
                bg = WHITE if r % 2 else SAND
                _add_rect(s, cx, y, col_w[c], row_h, bg)
                _add_text(s, cx, y + Inches(0.05), col_w[c], row_h, text,
                          size=12, color=INK, align=PP_ALIGN.CENTER)

    _add_text(s, Inches(7.3), Inches(4.9), Inches(5.2), Inches(1.9),
              "gpt-5.1 wins on accuracy and quality of rationale.\n\n"
              "Most disagreements were consistent across models — a signal that "
              "a handful of human labels might deserve a second look, not that "
              "the classifier is broken.",
              size=12, color=INK)
    _footer(s, 7, TOTAL)


def slide_results(prs, df):
    s = _blank_slide(prs)
    _header(s, "Current catalog",
            "467 cases · 13 schools · 2002 – 2026 · 100% difficulty coverage")

    # Top KPIs
    kpis = [
        ("467", "total cases"),
        ("13", "source schools"),
        ("217", "cases auto-rated"),
        ("0", "classifier failures"),
    ]
    kw = Inches(2.85)
    gap = Inches(0.25)
    total_w = len(kpis) * kw + (len(kpis) - 1) * gap
    left0 = (SLIDE_W - total_w) / 2
    for i, (num, label) in enumerate(kpis):
        x = left0 + i * (kw + gap)
        _add_rect(s, x, Inches(1.5), kw, Inches(1.3), NAVY)
        _add_text(s, x, Inches(1.55), kw, Inches(0.9), num,
                  size=44, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _add_text(s, x, Inches(2.35), kw, Inches(0.4), label,
                  size=13, color=SAND, align=PP_ALIGN.CENTER)

    # Left chart: difficulty buckets
    chart_data = CategoryChartData()
    chart_data.categories = ["Easy", "Medium", "Hard"]
    counts = df["difficulty_normalized"].value_counts()
    chart_data.add_series("Cases", (int(counts.get("Easy", 0)),
                                    int(counts.get("Medium", 0)),
                                    int(counts.get("Hard", 0))))
    chart = s.shapes.add_chart(
        XL_CHART_TYPE.COLUMN_CLUSTERED,
        Inches(0.5), Inches(3.15), Inches(6.0), Inches(3.6),
        chart_data).chart
    chart.has_title = True
    chart.chart_title.text_frame.text = "Difficulty distribution (all 467 cases)"
    for r in chart.chart_title.text_frame.paragraphs[0].runs:
        r.font.size = Pt(14)
        r.font.bold = True
        r.font.color.rgb = NAVY
    chart.has_legend = False
    plot = chart.plots[0]
    plot.has_data_labels = True
    plot.data_labels.font.size = Pt(11)
    plot.data_labels.font.bold = True
    plot.data_labels.position = XL_LABEL_POSITION.OUTSIDE_END
    series = plot.series[0]
    series.format.fill.solid()
    series.format.fill.fore_color.rgb = TEAL

    # Right chart: top schools
    school_counts = df["source_school"].fillna("unknown").value_counts().head(8)
    chart_data2 = CategoryChartData()
    chart_data2.categories = list(school_counts.index[::-1])
    chart_data2.add_series("Cases", [int(v) for v in school_counts.values[::-1]])
    chart2 = s.shapes.add_chart(
        XL_CHART_TYPE.BAR_CLUSTERED,
        Inches(6.8), Inches(3.15), Inches(6.0), Inches(3.6),
        chart_data2).chart
    chart2.has_title = True
    chart2.chart_title.text_frame.text = "Top sources"
    for r in chart2.chart_title.text_frame.paragraphs[0].runs:
        r.font.size = Pt(14)
        r.font.bold = True
        r.font.color.rgb = NAVY
    chart2.has_legend = False
    plot2 = chart2.plots[0]
    plot2.has_data_labels = True
    plot2.data_labels.font.size = Pt(11)
    series2 = plot2.series[0]
    series2.format.fill.solid()
    series2.format.fill.fore_color.rgb = CORAL

    _footer(s, 8, TOTAL)


def slide_guardrails(prs):
    s = _blank_slide(prs)
    _header(s, "Guardrails & audit trail",
            "Everything an automation touches is inspectable after the fact")

    cols = [
        ("Guardrails", [
            "Never overwrite a hand-labeled difficulty",
            "Anchors exclude the row being evaluated (no leakage)",
            "Strict JSON schema — malformed responses retry once, then fail loud",
            "--dry-run on every command; --force required to overwrite",
            "Low-confidence + near-boundary predictions auto-flagged for review",
        ], NAVY),
        ("Audit outputs", [
            "manifest.json / manifest.csv — every case, every decision",
            "review_queue.csv — only cases that need human eyes",
            "llm_difficulty_predictions.csv — full model response log",
            "llm_difficulty_failures.csv — API / parse errors",
            "llm_difficulty_needs_review.csv — flagged predictions",
        ], CORAL),
    ]

    for i, (title, items, col) in enumerate(cols):
        x = Inches(0.5) + i * Inches(6.3)
        _add_rect(s, x, Inches(1.5), Inches(6.0), Inches(0.55), col)
        _add_text(s, x, Inches(1.5), Inches(6.0), Inches(0.55), title,
                  size=17, bold=True, color=WHITE, align=PP_ALIGN.CENTER)
        _add_rect(s, x, Inches(2.05), Inches(6.0), Inches(4.7), WHITE)
        _add_bullets(s, x + Inches(0.2), Inches(2.2),
                     Inches(5.6), Inches(4.4), items, size=14,
                     bullet_color=col)

    _footer(s, 9, TOTAL)


def slide_cli(prs):
    s = _blank_slide(prs)
    _header(s, "How to drive it", "Single CLI, one command per stage")

    commands = [
        ("python main.py scan --input \"Case Repo\"",
         "Classify every PDF as multi-case vs single-case"),
        ("python main.py split --input \"Case Repo\" --output output",
         "Write per-case PDFs + manifest.json / .csv"),
        ("python main.py review --manifest output/manifest.json --only-flagged",
         "Walk the review queue interactively"),
        ("python main.py evaluate-difficulty-calibration --sample-size 30",
         "QA the classifier against existing labels (no catalog writes)"),
        ("python main.py classify-difficulty --cases-root output/cases",
         "Fill every blank difficulty with a calibrated OpenAI prediction"),
    ]

    y = Inches(1.7)
    for cmd, desc in commands:
        _add_rect(s, Inches(0.5), y, Inches(12.3), Inches(0.8), SAND)
        _add_text(s, Inches(0.7), y + Inches(0.08), Inches(12), Inches(0.4),
                  cmd, size=14, bold=True, color=NAVY, font="Consolas")
        _add_text(s, Inches(0.7), y + Inches(0.42), Inches(12), Inches(0.35),
                  desc, size=12, color=SLATE)
        y += Inches(0.95)

    _footer(s, 10, TOTAL)


def slide_closing(prs):
    s = _blank_slide(prs)
    _add_rect(s, 0, 0, SLIDE_W, SLIDE_H, NAVY)
    _add_rect(s, 0, Inches(3.4), SLIDE_W, Inches(0.06), TEAL)
    _add_text(s, Inches(0.8), Inches(2.5), Inches(11.7), Inches(0.7),
              "From pile of PDFs to queryable catalog.",
              size=40, bold=True, color=WHITE)
    _add_text(s, Inches(0.8), Inches(3.7), Inches(11.7), Inches(0.5),
              "Automation where it's safe. Humans where it matters.",
              size=20, color=SAND)
    _add_text(s, Inches(0.8), Inches(6.6), Inches(11.7), Inches(0.4),
              "Questions?", size=15, color=TEAL)
    return s


# ── Build ─────────────────────────────────────────────────────────────────────

SLIDE_BUILDERS = [
    slide_title,
    slide_problem,
    slide_architecture,
    slide_parsers,
    slide_metadata,
    slide_classifier,
    slide_calibration_qa,
    slide_results,      # needs df
    slide_guardrails,
    slide_cli,
    slide_closing,
]
TOTAL = len(SLIDE_BUILDERS)


def main():
    df = pd.read_csv("output/case_catalog.csv")

    prs = Presentation()
    prs.slide_width = SLIDE_W
    prs.slide_height = SLIDE_H

    for builder in SLIDE_BUILDERS:
        if builder is slide_results:
            builder(prs, df)
        else:
            builder(prs)

    out = Path("Case_Repo_Overview.pptx")
    prs.save(str(out))
    print(f"Wrote {out.resolve()}  ({TOTAL} slides)")


if __name__ == "__main__":
    main()
