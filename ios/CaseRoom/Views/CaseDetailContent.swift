/*
 * Purpose: Shared case-detail body (canvas 5a detail / 2c right pane) — kicker,
 *          title, meta, rating row, "YOUR HISTORY WITH IT", "THE CASE PACK"
 *          PDF row, primary CTA, serif note, and the done-only "Get re-cased
 *          anyway" afterthought. `layout` drives the few phone/tablet deltas
 *          (rating/title size, case-pack sub copy, the "It knows." aside, and
 *          — per the tablet dc's own markup, which has no recase-button block
 *          at all — the recase afterthought itself, phone-only).
 * Inputs: DetailLayout (.phone/.tablet); LibraryCase (built by CaseDetailView
 *         for phone, LibraryViewModel.selectedCase for Task 5's tablet pane).
 * Outputs: none (CTA/re-cased actions are the documented F4→F3 seam below).
 * Run: `CaseDetailContent(layout: .phone, libraryCase: case)` inside a
 *      ScrollView (CaseDetailView); Task 5 hosts `.tablet` directly in the
 *      always-visible right pane (no ScrollView wrapper assumed here).
 */

import SwiftUI

enum DetailLayout {
    case phone, tablet
}

/// Pure copy derivations for canvas 5a/2c's `libDTag`/`libDCta`/`libDNote`/
/// `libDHist*` — Design Decisions §0.4's retired-done rules. Kept as static
/// funcs (not inlined into the view) so CaseDetailContentTests can assert
/// them directly without snapshotting SwiftUI views.
enum LibraryDetailCopy {
    struct Tag: Equatable {
        let text: String
        let isGreen: Bool
    }

    /// libDTag / libDTagColor (tablet dc ~1240-1241): `rec` is checked before
    /// `done` — fixtures only ever pair one flag at a time, but the canvas
    /// logic itself gives recommendation priority.
    static func tag(recommended: Bool, done: Bool) -> Tag {
        if recommended { return Tag(text: "RECOMMENDED FOR YOU", isGreen: true) }
        if done { return Tag(text: "DONE — RETIRED FOR YOU", isGreen: false) }
        return Tag(text: "OPEN FOR YOU", isGreen: false)
    }

    /// libDCta.
    static func cta(done: Bool) -> String {
        done ? "Case someone with this" : "Get cased on this"
    }

    /// libDNote.
    static func note(done: Bool) -> String {
        done
            ? "Done cases join your interviewer deck — you know the answer key now."
            : "Opens the Case tab with this case pre-filled."
    }

    struct History: Equatable {
        let line: String?
        let score: String?
    }

    /// libDHist/libDHistScore, joined by `case_title` since SessionSummary
    /// carries no `case_id` (plan resolution #6, documented seam). Picks the
    /// most-recent title match by `endedAt`; a session missing `endedAt`
    /// sorts earliest so it's only chosen if it's the sole match. Score is
    /// always "<grade> avg" (plan resolution #6 — no "given rating" field
    /// exists to distinguish interviewer- from candidate-side phrasing, so
    /// the canvas's own "X/5 given" variants are intentionally not
    /// reproduced here).
    static func history(from sessions: [SessionSummary], caseTitle: String) -> History {
        let matches = sessions.filter { $0.caseTitle == caseTitle }
        guard let mostRecent = matches.max(by: { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }) else {
            return History(line: nil, score: nil)
        }
        let line: String
        if let endedAt = mostRecent.endedAt {
            line = "\(historyDateFormatter.string(from: endedAt)) · \(mostRecent.otherUser)"
        } else {
            line = mostRecent.otherUser
        }
        let score = mostRecent.grade.map { String(format: "%.1f avg", $0) }
        return History(line: line, score: score)
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter
    }()

    // MARK: - Layout deltas (plan item 12) — pure, so tests don't need to
    // snapshot the view to prove the phone/tablet split.

    static func titleSize(layout: DetailLayout) -> CGFloat { layout == .phone ? 24 : 22 }
    static func ratingSize(layout: DetailLayout) -> CGFloat { layout == .phone ? 26 : 24 }

    /// Tablet drops the "— interviewer side" suffix (canvas 2c).
    static func casePackSub(layout: DetailLayout) -> String {
        layout == .phone
            ? "Prompt script, exhibits, answer key — interviewer side"
            : "Prompt script, exhibits, answer key"
    }

    /// The "It knows." serif aside is phone-only (canvas 2c's right pane omits it).
    static func showsKnowsAside(layout: DetailLayout) -> Bool { layout == .phone }

    /// The done-only "Get re-cased anyway" afterthought — phone-only: the
    /// tablet dc's detail-pane markup has no recase-button block at all, even
    /// for done cases (canvas truth, not an inferred omission).
    static func showsRecasedAfterthought(layout: DetailLayout, done: Bool) -> Bool {
        layout == .phone && done
    }
}

/// The `libDTag`/`libDTagColor` label (9/600/.13em). CaseDetailView's phone
/// header renders this top-trailing next to `‹ Library` (canvas 5a's fixed
/// header row); CaseDetailContent renders it itself only under `.tablet`,
/// since canvas 2c's right pane has no separate header to hold it.
struct DetailTagLabel: View {
    let libraryCase: LibraryCase
    @Environment(\.dsPalette) private var palette

    var body: some View {
        let tag = LibraryDetailCopy.tag(recommended: libraryCase.recommended, done: libraryCase.done)
        Text(tag.text)
            .font(.archivo(9, weight: 600))
            .tracking(9 * 0.13)
            .foregroundStyle(tag.isGreen ? palette.green : palette.faint)
    }
}

struct CaseDetailContent: View {
    let layout: DetailLayout
    let libraryCase: LibraryCase

    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if layout == .tablet {
                DetailTagLabel(libraryCase: libraryCase)
                    .padding(.bottom, 10)
            }

            Text(libraryCase.kicker)
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)
                .padding(.bottom, layout == .phone ? 9 : 8)

            Text(libraryCase.title)
                .font(.archivo(titleSize, weight: 800))
                .tracking(titleSize * -0.03)
                .foregroundStyle(palette.ink)
                .padding(.bottom, layout == .phone ? 8 : 6)

            Text(libraryCase.detailMeta)
                .font(.archivo(12, weight: 400))
                .foregroundStyle(palette.muted)
                .padding(.bottom, layout == .phone ? 16 : 14)

            ratingRow
            historySection
            casePackSection
            ctaSection
        }
    }

    private var titleSize: CGFloat { LibraryDetailCopy.titleSize(layout: layout) }
    private var ratingSize: CGFloat { LibraryDetailCopy.ratingSize(layout: layout) }

    // MARK: - Rating row

    private var ratingRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(libraryCase.avgRating)
                .font(.archivo(ratingSize, weight: 800))
                .tabularNumbers()
                .foregroundStyle(palette.ink)
            Text("AVG RATING · \(libraryCase.runCount) SESSIONS")
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.12)
                .tabularNumbers()
                .foregroundStyle(palette.muted)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR HISTORY WITH IT")
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)

            if let historyLine = libraryCase.historyLine {
                HStack(alignment: .lastTextBaseline) {
                    Text(historyLine)
                        .font(.archivo(13, weight: 600))
                        .foregroundStyle(palette.ink)
                    Spacer()
                    if let historyScore = libraryCase.historyScore {
                        Text(historyScore)
                            .font(.archivo(11, weight: 600))
                            .tabularNumbers()
                            .foregroundStyle(palette.muted)
                    }
                }
            } else {
                Text("You haven't run this one.")
                    .font(.serifVoice(13, italic: true))
                    .foregroundStyle(palette.muted)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    // MARK: - Case pack

    private var casePackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THE CASE PACK")
                .font(.archivo(9.5, weight: 600))
                .tracking(9.5 * 0.15)
                .foregroundStyle(palette.muted)

            casePackRow

            // "It knows." aside is PHONE ONLY — canvas 2c's right pane omits
            // it (plan item 12).
            if LibraryDetailCopy.showsKnowsAside(layout: layout) {
                Text("Reading the pack before being cased on it defeats the point. It knows.")
                    .font(.serifVoice(11.5, italic: true))
                    .foregroundStyle(palette.faint)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }

    private var casePackRow: some View {
        HStack(alignment: .center, spacing: 14) {
            StripedThumb(size: layout == .phone ? CGSize(width: 38, height: 48) : CGSize(width: 36, height: 46))

            VStack(alignment: .leading, spacing: 1) {
                Text(libraryCase.pdfLabel)
                    .font(.archivo(12.5, weight: 600))
                    .foregroundStyle(palette.ink)
                Text(casePackSub)
                    .font(.archivo(11, weight: 400))
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            previewButton
        }
        .padding(.horizontal, layout == .phone ? 16 : 15)
        .padding(.vertical, layout == .phone ? 14 : 13)
        .background(palette.surface)
        .overlay(Rectangle().stroke(palette.hairline, lineWidth: 1))
    }

    // Tablet drops the "— interviewer side" suffix (plan item 12).
    private var casePackSub: String { LibraryDetailCopy.casePackSub(layout: layout) }

    // Canvas 5a always renders the "Preview" affordance in the pack row; wrap it
    // in a ShareLink only when a pdf URL resolves, otherwise show the plain label
    // (a case may lack a pdf_url) rather than dropping it entirely.
    @ViewBuilder
    private var previewButton: some View {
        let label = Text("Preview")
            .font(.archivo(12, weight: 600))
            .foregroundStyle(palette.ink)
            .underline(true, pattern: .solid)
        if let pdfURL {
            ShareLink(item: pdfURL) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private var pdfURL: URL? {
        guard let pdfUrl = libraryCase.pdfUrl else { return nil }
        return APIClient.shared.resolveURL(pdfUrl)
    }

    // MARK: - CTA / note / re-cased afterthought

    private var ctaSection: some View {
        VStack(spacing: 8) {
            Button {
                // F4→F3 seam: F3 owns the Case-tab case-prefill; this interim
                // just selects the Case tab bare (plan resolution — no new
                // AppRoute this phase).
                AppRouter.shared.go(to: .caseTab)
            } label: {
                Text(LibraryDetailCopy.cta(done: libraryCase.done))
                    .font(.archivo(layout == .phone ? 13.5 : 13, weight: 600))
                    .foregroundStyle(palette.onInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: layout == .phone ? 50 : 48)
            }
            .background(Capsule().fill(palette.ink))
            .buttonStyle(DSPressStyle())

            Text(LibraryDetailCopy.note(done: libraryCase.done))
                .font(.serifVoice(11.5, italic: true))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if LibraryDetailCopy.showsRecasedAfterthought(layout: layout, done: libraryCase.done) {
                recasedSection
            }
        }
        .padding(.top, 4)
    }

    private var recasedSection: some View {
        VStack(spacing: 2) {
            Button {
                // Same F4→F3 interim seam as the primary CTA.
                AppRouter.shared.go(to: .caseTab)
            } label: {
                Text("Get re-cased anyway")
                    .font(.archivo(11, weight: 600))
                    .foregroundStyle(palette.faint)
                    .underline(true, pattern: .solid)
            }
            .buttonStyle(.plain)

            // Design Decisions §0.4's lowercase qualifier — not on the
            // canvas itself; rendered alongside the button per the task brief.
            Text("won't count toward diagnostics")
                .font(.archivo(9, weight: 400))
                .foregroundStyle(palette.faint.opacity(0.85))
        }
        .padding(.top, 10)
    }
}

/// The case-pack thumb — the canvas's 6px repeating horizontal stripe
/// reproduced exactly (not approximated) via two exact F0 token matches: the
/// light band is `palette.onInk`, the surface band is `palette.surface` — so
/// the stripe needs no new color literals.
private struct StripedThumb: View {
    let size: CGSize
    @Environment(\.dsPalette) private var palette

    var body: some View {
        Canvas { context, canvasSize in
            let bandHeight: CGFloat = 6
            var y: CGFloat = 0
            var isOnInk = true
            while y < canvasSize.height {
                let band = CGRect(x: 0, y: y, width: canvasSize.width, height: bandHeight)
                context.fill(Path(band), with: .color(isOnInk ? palette.onInk : palette.surface))
                y += bandHeight
                isOnInk.toggle()
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(Rectangle().stroke(palette.hairline, lineWidth: 1))
    }
}
