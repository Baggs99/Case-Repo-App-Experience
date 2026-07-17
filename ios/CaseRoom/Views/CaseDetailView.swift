/*
 * Purpose: Case detail screen, phone push (canvas 5a detail) — a fixed header
 *          (`‹ Library` plain-text back + the detail tag) above the scrollable
 *          CaseDetailContent(layout: .phone) body. Migrated off the retired
 *          CasesService onto LibraryService so it shares the retired-done tag/
 *          CTA/note rules and the `-LibraryFixtures` screenshot path with the
 *          rest of Library (Task 2/3).
 * Inputs: caseId; LibraryService (default APIClient.shared; DEBUG
 *         `-LibraryFixtures` swaps in LibraryFixtures.service — this view is
 *         pushed independently of CasesListView's own init, so it re-checks
 *         the launch arg itself rather than inheriting a passed-in service).
 * Outputs: none.
 * Run: pushed via `AppRouter.shared.go(to: .caseDetail(id))` onto
 *      libraryPath (RootShell's libraryDetailOpen gate hides the tab bar/
 *      pills while this is on screen — Task 3).
 */

import SwiftUI

struct CaseDetailView: View {
    let caseId: Int
    private let service: LibraryService

    @State private var libraryCase: LibraryCase?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dsPalette) private var palette

    init(caseId: Int, service: LibraryService? = nil) {
        self.caseId = caseId
        #if DEBUG
        if let service {
            self.service = service
        } else if ProcessInfo.processInfo.arguments.contains("-LibraryFixtures") {
            self.service = LibraryFixtures.service
        } else {
            self.service = APIClient.shared
        }
        #else
        self.service = service ?? APIClient.shared
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // Canvas 5a's fixed row: plain ink `‹ Library` (13/600, no glass, no
    // underline — NOT the BackPill) + the detail tag, top-trailing. Lives
    // outside the ScrollView so it never scrolls with the body.
    private var header: some View {
        HStack {
            Button {
                // libraryPath is externally driven (Task 3's NavigationStack
                // binds straight to AppRouter.shared.libraryPath) — popping
                // means trimming that array, not dismiss()/presentationMode.
                if !AppRouter.shared.libraryPath.isEmpty {
                    AppRouter.shared.libraryPath.removeLast()
                }
            } label: {
                Text("‹ Library")
                    .font(.archivo(13, weight: 600))
                    .foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)

            Spacer()

            if let libraryCase {
                DetailTagLabel(libraryCase: libraryCase)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let libraryCase {
            ScrollView {
                CaseDetailContent(layout: .phone, libraryCase: libraryCase)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            Text(errorMessage)
                .font(.serifVoice(14, italic: true))
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let detail = try await service.caseDetail(id: caseId)
            // Best-effort: a recentSessions() failure shouldn't block the
            // detail from rendering — it just means "You haven't run this
            // one." shows instead of a real history line.
            let sessions = (try? await service.recentSessions()) ?? []
            var built = Self.makeLibraryCase(from: detail)
            let history = LibraryDetailCopy.history(from: sessions, caseTitle: detail.caseTitle)
            built.historyLine = history.line
            built.historyScore = history.score
            libraryCase = built
        } catch {
            libraryCase = nil
            errorMessage = "Couldn't load this case. Try again."
        }
    }

    // CaseDetail carries every CaseSummary field plus previewUrls/pdfUrl;
    // routing through a CaseSummary lets this reuse LibraryCase.from's
    // kicker/meta/rating derivation instead of re-deriving it here. Ordinal
    // is the empty string — canvas 5a detail never renders it (list-only
    // decoration, plan item 11); recommended/scheduledNote stay at their
    // LibraryCase defaults (false/nil) on this live path, same as
    // LibraryViewModel's live load() — fixtures are the only source of those
    // decorations (documented seam, plan "Deferred / seams").
    private static func makeLibraryCase(from detail: CaseDetail) -> LibraryCase {
        let summary = CaseSummary(
            id: detail.id, caseTitle: detail.caseTitle, caseType: detail.caseType,
            difficulty: detail.difficulty, difficultyScore: detail.difficultyScore,
            firm: detail.firm, industry: detail.industry, industryDisplay: detail.industryDisplay,
            industryRaw: detail.industryRaw, pageCount: detail.pageCount,
            sourceSchool: detail.sourceSchool, sourceYear: detail.sourceYear,
            avgRating: detail.avgRating, runCount: detail.runCount, doneForYou: detail.doneForYou
        )
        var libraryCase = LibraryCase.from(summary, ordinal: "")
        libraryCase.previewUrls = detail.previewUrls
        libraryCase.pdfUrl = detail.pdfUrl
        return libraryCase
    }
}

#if DEBUG
#Preview {
    CaseDetailView(caseId: 8, service: LibraryFixtures.service)
}
#endif
