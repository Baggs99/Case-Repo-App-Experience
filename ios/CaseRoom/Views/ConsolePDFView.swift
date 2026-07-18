/*
 * Purpose: The interviewer console's PDF case-pack mode (F6-T5, canvas Tablet
 *          §7-1a PDF mode). Renders the 3 authored `ConsoleScript.pdfPages`
 *          (brief + timing plan / Exhibit 01 volumes-fares table / answer key)
 *          on a white 566px "paper" page over the `pdfBackdrop` paper-grey.
 *          - Tablet: `TabletPDFOverlay` sits `inset:0` INSIDE the LEFT pane only
 *            (the 380px rail stays visible + live) — the canvas overlay div.
 *          - Phone: `PhonePDFPager` is a full-screen single-column authored pager
 *            (deviation #5 — no canvas anchor; same content + design tokens).
 *          Page-02's "Release" calls the SAME `model.release("e1")` and shows the
 *          SAME SENT · mm:ss as the script's e1 exhibit row (A2). Pure display —
 *          all state flows through the shared ConsoleViewModel. Tokens only.
 * Inputs: the shared ConsoleViewModel (pdfPage, release/sentAt, pager nav).
 * Outputs: none directly — release/close/prev/next forward through the VM.
 * Run: mounted by InterviewerConsoleView when `model.isPDFOpen`; the shot
 *      fixtures seed `openPDF()` + a page under `-startTakeover console-pdf` /
 *      `console-phone-pdf`.
 */

import SwiftUI

// MARK: - Tablet overlay (canvas 1a PDF mode — covers the LEFT pane only)

/// The tablet PDF overlay. Mounted as an `.overlay` on the LEFT pane so it covers
/// ONLY the left column (the rail stays rendered + live), matching the canvas
/// `position:absolute; inset:0; z-index:15` inside the left-pane div.
struct TabletPDFOverlay: View {
    let model: ConsoleViewModel

    var body: some View {
        ConsolePDFReader(model: model, compact: false)
    }
}

// MARK: - Phone full-screen pager (deviation #5 — no canvas anchor)

/// The phone PDF pager: the same 3 authored pages at phone widths, full-screen.
struct PhonePDFPager: View {
    let model: ConsoleViewModel

    var body: some View {
        ConsolePDFReader(model: model, compact: true)
    }
}

// MARK: - Shared reader (toolbar + paper page + pager)

/// The shared PDF reader chrome, sized by `compact` (phone) vs the tablet hero.
private struct ConsolePDFReader: View {
    let model: ConsoleViewModel
    let compact: Bool
    @Environment(\.dsPalette) private var palette

    private var page: ConsolePDFPage { model.pdfPages[model.pdfPage] }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                paperPage
                    .frame(maxWidth: .infinity)   // centred in the scroll region
                    .padding(.vertical, compact ? 6 : 10)
            }
            .scrollIndicators(.hidden)
            pager
        }
        .padding(.horizontal, compact ? 16 : 24)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.pdfBackdrop.ignoresSafeArea())
    }

    // Toolbar: kicker + headline (Archivo bold, canvas l.684) | "‹ Back to script".
    private var toolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CASE PACK — INTERVIEWER COPY · 8 PAGES")
                    .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                    .foregroundStyle(palette.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)   // wrap, never truncate (tracking can't shrink)
                Text("The script keeps scoring; this is the paper.")
                    .font(.archivo(14, weight: 700)).tracking(-0.14)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 10)
            Button { model.closePDF() } label: {
                Text("‹ Back to script")
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(Capsule().fill(palette.ink))
            }
            .buttonStyle(DSPressStyle())
            .fixedSize()
        }
        .padding(.bottom, 12)
    }

    // The white 566px "paper" page (square corners, hairline border, soft shadow).
    private var paperPage: some View {
        ConsolePDFPageView(page: page, model: model)
            .padding(compact ? 24 : 46)
            .padding(.top, compact ? 26 : 40)
            .frame(maxWidth: compact ? .infinity : 566, alignment: .leading)
            .background(palette.surface)
            .overlay(Rectangle().strokeBorder(palette.hairline, lineWidth: 1))   // square corners
            .shadow(color: Color.dsShadowInk.opacity(0.14), radius: 20, x: 0, y: 18)
    }

    // Pager: "‹ Previous page" (grey at page 0) | "PAGE 0N OF 08" | "Next page ›".
    private var pager: some View {
        HStack(spacing: 16) {
            Button { model.pdfPrev() } label: {
                Text("‹ Previous page")
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(model.isFirstPDFPage ? palette.hairline : palette.ink)
                    .underline(true, pattern: .solid)
            }
            .buttonStyle(.plain)
            .disabled(model.isFirstPDFPage)

            Text(model.pdfPageText)
                .font(.archivo(10, weight: 600)).tracking(10 * 0.14).tabularNumbers()
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(1).minimumScaleFactor(0.7)

            Button { model.pdfNext() } label: {
                Text("Next page ›")
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(model.isLastPDFPage ? palette.hairline : palette.ink)
                    .underline(true, pattern: .solid)
            }
            .buttonStyle(.plain)
            .disabled(model.isLastPDFPage)
        }
        .padding(.top, 11)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }
}

// MARK: - One authored page

/// Renders a single `ConsolePDFPage`: the header rule + corner affordance, the
/// title, then the ordered `blocks`. Width-agnostic — the caller frames it (566px
/// on tablet, full width on phone).
private struct ConsolePDFPageView: View {
    let page: ConsolePDFPage
    let model: ConsoleViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(page.title)
                .font(.archivo(page.id == 0 ? 22 : 19, weight: 800))
                .tracking(-(page.id == 0 ? 22 : 19) * 0.022)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            ForEach(Array(page.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 2px ink header rule: kicker (left) + corner affordance (right).
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(page.kicker)
                .font(.archivo(9, weight: 600)).tracking(9 * 0.16)
                .foregroundStyle(palette.muted)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)   // wrap on sub-566 widths, never truncate authored text
            Spacer(minLength: 10)
            corner.fixedSize()
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.ink).frame(height: 2) }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var corner: some View {
        switch page.corner {
        case .meta(let text):
            Text(text)
                .font(.archivo(9, weight: 600)).tracking(9 * 0.12)
                .foregroundStyle(palette.faint)
        case .interviewerOnly:
            Text("INTERVIEWER ONLY")
                .font(.archivo(9, weight: 600)).tracking(9 * 0.14)
                .foregroundStyle(palette.green)
        case .exhibitRelease(let scriptId):
            // The SAME reveal + SENT · mm:ss as the script's e1 exhibit row (A2).
            if let sent = model.sentAt(scriptId: scriptId) {
                Text("SENT · \(sent)")
                    .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.1).tabularNumbers()
                    .foregroundStyle(palette.green)
            } else {
                Button { Task { await model.release(scriptId: scriptId) } } label: {
                    Text("Release to candidate")
                        .font(.archivo(11, weight: 600))
                        .foregroundStyle(palette.onInk)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(palette.ink))
                }
                .buttonStyle(DSPressStyle())
                .fixedSize()
            }
        }
    }

    // MARK: Blocks

    @ViewBuilder
    private func blockView(_ block: PDFBlock) -> some View {
        switch block {
        case .sectionKicker(let text):
            Text(text)
                .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 6)

        case .serif(let text):
            Text(text)
                .font(.serifVoice(13.5)).lineSpacing(13.5 * 0.65)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

        case .timingPlan(let title, let rows):
            timingPlan(title: title, rows: rows)

        case .table(let columns, let rows, let footnote):
            tableBlock(columns: columns, rows: rows, footnote: footnote)

        case .bulletChain(let lines):
            bulletChain(lines)

        case .gradingNotes(let title, let body):
            gradingNotes(title: title, body: body)
        }
    }

    // TIMING PLAN — HOLD THE LAST TWO MINUTES: label (ink) / value (muted, tabular).
    private func timingPlan(title: String, rows: [PDFRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 8)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label)
                            .font(.archivo(12, weight: 600))
                            .foregroundStyle(palette.ink)
                        Text(row.value)
                            .font(.archivo(12)).tabularNumbers()
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    // Exhibit-01 table: header row (faint) + data rows (hairline top rule) + a
    // 2px-ink total row + serif source footnote. Right columns tabular.
    private func tableBlock(columns: [String], rows: [PDFTableRow], footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                        Text(col)
                            .font(.archivo(9, weight: 600)).tracking(9 * 0.12)
                            .foregroundStyle(palette.faint)
                            .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
                    }
                }
                .padding(.bottom, 10)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { i, cell in
                            tableCell(cell, isTotal: row.isTotal, leading: i == 0)
                        }
                    }
                }
            }
            Text(footnote)
                .font(.serifVoice(11.5, italic: true))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
        .padding(.bottom, 4)
    }

    private func tableCell(_ text: String, isTotal: Bool, leading: Bool) -> some View {
        Text(text)
            .font(.archivo(13.5, weight: isTotal || leading ? 700 : 400))
            .tabularNumbers()
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isTotal ? palette.ink : palette.hairline)
                    .frame(height: isTotal ? 2 : 1)
            }
    }

    // Answer-key quant chain: "—" dash + line (tabular for the arithmetic).
    private func bulletChain(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("—")
                        .foregroundStyle(palette.faint)
                        .frame(width: 18, alignment: .leading)
                    Text(line)
                        .font(.archivo(13.5)).tabularNumbers()
                        .lineSpacing(13.5 * 0.6)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.bottom, 18)
    }

    // GRADING NOTES: kicker + italic serif callout under a hairline.
    private func gradingNotes(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.archivo(9.5, weight: 600)).tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            Text(body)
                .font(.serifVoice(13, italic: true)).lineSpacing(13 * 0.6)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }
}
