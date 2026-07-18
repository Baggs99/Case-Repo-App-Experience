/*
 * Purpose: Group page CHROME (canvas 6a C-14 detail push) — the `‹ Back` +
 *          slate context-label header (Design §1 Recurring chrome) around
 *          GroupPageContent, which owns the actual board/admin-note/
 *          transfer/progress body (content/chrome split, mirrors
 *          CaseDetailView wrapping CaseDetailContent). Kept byte-for-byte
 *          identical in rendered output to the pre-split view (Task 4 —
 *          the phone screenshot must not regress).
 * Inputs: GroupPageViewModel (default live). RootShell's `.groupPage`
 *         destination passes `currentUserId: sessionStore.user?.id` on the
 *         live path, or an injected fixture-backed VM under `-GroupPageFixtures`
 *         (mirrors the AvatarSheetView injectable-VM pattern).
 * Outputs: none (navigation via AppRouter.shared.communityPath — externally
 *          driven by RootShell's `NavigationStack(path: $router.communityPath)`,
 *          same idiom as CaseDetailView popping libraryPath).
 * Run: pushed via `NavigationLink(value: AppRoute.groupPage(id))` from
 *      CommunityView's YOUR GROUPS rows; RootShell's `communityDetailOpen`
 *      gate hides the top pills/tab bar while this is on screen. Task 4's
 *      tablet right pane embeds GroupPageContent directly (layout: .tablet)
 *      with NO back chrome / no top pills instead of this view.
 */

import SwiftUI

struct GroupPageView: View {
    let groupId: Int
    @Environment(\.dsPalette) private var palette
    @State private var viewModel: GroupPageViewModel

    // Injectable VM (default = live, built from currentUserId). The DEBUG
    // -GroupPageFixtures hatch (wired in RootShell) passes a fixture-backed
    // VM directly — AvatarSheetView's `init(viewModel:)` pattern.
    @MainActor
    init(groupId: Int, currentUserId: Int? = nil, viewModel: GroupPageViewModel? = nil) {
        self.groupId = groupId
        _viewModel = State(initialValue: viewModel ?? GroupPageViewModel(currentUserId: currentUserId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await viewModel.load(groupId: groupId)
            if viewModel.isAdmin {
                await viewModel.loadProgress(groupId: groupId)
            }
        }
    }

    // MARK: - Header — `‹ Back` + slate context label (Design §1 Recurring
    // chrome: "Sub-pages use ‹ Back text + small slate context label").
    // communityPath is externally driven (RootShell's NavigationStack binds
    // straight to AppRouter.shared.communityPath) — popping means trimming
    // that array, same as CaseDetailView's `‹ Library` back (libraryPath).

    private var header: some View {
        Button {
            if !AppRouter.shared.communityPath.isEmpty {
                AppRouter.shared.communityPath.removeLast()
            }
        } label: {
            BackPill(label: "Back", context: viewModel.detail?.group.name)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    // MARK: - Content

    // The loaded board/admin-note/transfer/progress body now lives in
    // GroupPageContent (Task 4 content/chrome split) — this stays a thin
    // ScrollView wrapper so the rendered output (padding, scroll fade,
    // bottom tab-bar spacer) is byte-for-byte identical to before the split.
    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            Text("Loading group…").dsText(.meta).foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.detail == nil {
            errorState
        } else {
            ScrollView {
                GroupPageContent(viewModel: viewModel, layout: .phone)
                    .padding(22)
            }
            .scrollIndicators(.hidden)
            .dsHeaderFade()
        }
    }

    private var errorState: some View {
        VStack(spacing: 10) {
            Text(viewModel.errorMessage ?? "Couldn't load this group.")
                .dsText(.meta).foregroundStyle(palette.muted)
            Button { Task { await viewModel.load(groupId: groupId) } } label: {
                Text("Retry").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

#if DEBUG
#Preview {
    ZStack {
        DSBackground()
        GroupPageView(groupId: 14, viewModel: GroupPageViewModel(
            fixtureDetail: CommunityFixtures.groupDetail,
            fixtureIsAdmin: true,
            fixtureProgress: CommunityFixtures.groupProgress))
    }
}
#endif
