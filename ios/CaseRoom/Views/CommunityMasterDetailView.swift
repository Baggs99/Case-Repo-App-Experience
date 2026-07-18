/*
 * Purpose: Tablet master–detail Community (canvas 2d) — regular-size-class
 *          body for CommunityView: a 1fr | 470pt grid divided by a hairline
 *          (LibraryMasterDetailView's exact proportions — canvas §7 names
 *          "Community group page" as a master-detail pane alongside "Library
 *          detail"). Left reuses CommunitySchoolHeroCard + CommunityConnections
 *          Section + a YOUR GROUPS selector (select-on-tap, no push — canvas
 *          2d order: hero, CONNECTIONS, then YOUR GROUPS). Right is an
 *          always-visible GroupPageContent(layout: .tablet) for
 *          viewModel.selectedGroup (falls back to the first group). Bottom
 *          padding clears the 560pt floating tab bar.
 * Inputs: CommunityViewModel — owned and `.load()`ed by CommunityView; this
 *         view only mutates `viewModel.selectedGroupID` on row tap. Reads
 *         SessionStore for the right pane's isAdmin match (live path).
 * Outputs: none.
 * Run: `CommunityMasterDetailView(viewModel:)` from CommunityView.sizeClassBody
 *      when `hSize == .regular`.
 */

import SwiftUI

struct CommunityMasterDetailView: View {
    let viewModel: CommunityViewModel
    @Environment(\.dsPalette) private var palette
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            masterColumn
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.trailing, 28)
                .overlay(alignment: .trailing) {
                    // Exact F0 hairline token match, same as LibraryMasterDetailView.
                    Rectangle().fill(palette.hairline).frame(width: 1)
                }

            detailColumn
                .padding(.leading, 28)
                .frame(width: 470, alignment: .top)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Left: hero + CONNECTIONS + YOUR GROUPS selector (canvas 2d order)

    private var masterColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
                CommunitySchoolHeroCard(school: viewModel.schoolStanding?.school)
                CommunityConnectionsSection(connections: viewModel.connections)
                groupsSelectorSection
            }
        }
        .scrollIndicators(.hidden)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message).dsText(.meta).foregroundStyle(palette.muted)
            Button { Task { await viewModel.load() } } label: {
                Text("Retry").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // YOUR GROUPS pointer (canvas 2d) — select-on-tap, no push (no
    // NavigationLink; tapping sets `selectedGroupID` and the right pane
    // reloads for the new selection).
    private var groupsSelectorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR GROUPS").dsText(.kicker).foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            if viewModel.groups.isEmpty {
                Text("No groups yet").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.vertical, 10)
            } else {
                ForEach(viewModel.groups) { group in
                    Button {
                        viewModel.selectedGroupID = group.id
                    } label: {
                        CommunityGroupRow(group: group, isSelected: group.id == viewModel.selectedGroup?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    // MARK: - Right: always-visible group page for the selection

    @ViewBuilder
    private var detailColumn: some View {
        ScrollView {
            if let group = viewModel.selectedGroup {
                // `.id(group.id)` tears the pane down and rebuilds it (fresh
                // GroupPageViewModel + `.task`) whenever the selection
                // changes — mirrors how each phone push mounts a fresh
                // GroupPageView for its own groupId.
                GroupPageDetailPane(groupId: group.id, sessionUserId: sessionStore.user?.id)
                    .id(group.id)
            } else {
                Text("No groups yet").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.top, 40)
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Tablet right-pane loader — owns its own GroupPageViewModel (no
// back chrome / no top pills, unlike GroupPageView's phone push). Under
// `-CommunityFixtures` it injects the SAME admin-variant fixture
// `-GroupPageFixtures` uses (CommunityFixtures.groupDetail/groupProgress,
// isAdmin=true) so the right pane renders without a dev server — reusing
// the existing launch arg rather than adding a new one (per the T4 brief).

private struct GroupPageDetailPane: View {
    let groupId: Int
    let sessionUserId: Int?
    @State private var viewModel: GroupPageViewModel
    @Environment(\.dsPalette) private var palette

    init(groupId: Int, sessionUserId: Int?) {
        self.groupId = groupId
        self.sessionUserId = sessionUserId
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CommunityFixtures") {
            _viewModel = State(initialValue: GroupPageViewModel(
                fixtureDetail: CommunityFixtures.groupDetail,
                fixtureIsAdmin: true,
                fixtureProgress: CommunityFixtures.groupProgress))
        } else {
            _viewModel = State(initialValue: GroupPageViewModel(currentUserId: sessionUserId))
        }
        #else
        _viewModel = State(initialValue: GroupPageViewModel(currentUserId: sessionUserId))
        #endif
    }

    var body: some View {
        Group {
            if !viewModel.hasLoaded {
                Text("Loading group…").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.top, 40)
            } else if viewModel.detail == nil {
                Text(viewModel.errorMessage ?? "Couldn't load this group.")
                    .dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.top, 40)
            } else {
                GroupPageContent(viewModel: viewModel, layout: .tablet)
            }
        }
        .task {
            await viewModel.load(groupId: groupId)
            if viewModel.isAdmin {
                await viewModel.loadProgress(groupId: groupId)
            }
        }
    }
}

#if DEBUG
#Preview {
    let vm = CommunityViewModel(
        fixtureStanding: CommunityFixtures.standing,
        fixtureGroups: CommunityFixtures.groups,
        fixtureConnections: CommunityFixtures.connections)
    return ZStack { DSBackground(); CommunityMasterDetailView(viewModel: vm) }
        .environment(SessionStore())
}
#endif
