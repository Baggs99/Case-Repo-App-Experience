/*
 * Purpose: Community tab (canvas 6a phone) — the ONE glass school hero
 *          (rank/avg member percentile/campus city + serif aside), YOUR
 *          GROUPS (tap pushes .groupPage(id) onto communityPath), and
 *          CONNECTIONS rows (FREE NOW green dot; swap-invite-pending
 *          decoration). No forum, no headcounts (Decisions §0.1/§0.2).
 * Inputs: CommunityViewModel (default live). DEBUG `-CommunityFixtures`
 *         swaps in a fixture-backed CommunityViewModel (CommunityFixtures.swift)
 *         so screenshots need no dev server — mirrors CasesListView/
 *         -LibraryFixtures exactly.
 * Outputs: none (navigation via NavigationLink(value:) onto the communityPath
 *          NavigationStack RootShell mounts).
 * Run: mounted by RootShell inside `NavigationStack(path: $router.communityPath)`.
 */

import SwiftUI

struct CommunityView: View {
    @Environment(\.dsPalette) private var palette
    @State private var viewModel: CommunityViewModel

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-CommunityFixtures") {
            _viewModel = State(initialValue: CommunityViewModel(
                fixtureStanding: CommunityFixtures.standing,
                fixtureGroups: CommunityFixtures.groups,
                fixtureConnections: CommunityFixtures.connections))
        } else {
            _viewModel = State(initialValue: CommunityViewModel())
        }
        #else
        _viewModel = State(initialValue: CommunityViewModel())
        #endif
    }

    var body: some View {
        Group {
            if !viewModel.hasLoaded {
                Text("Loading Community…").dsText(.meta).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .task { await viewModel.load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
                schoolHeroCard
                yourGroupsSection
                connectionsSection
                Color.clear.frame(height: 120)   // room behind the tab bar
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .dsHeaderFade()
    }

    // MARK: - 1. Header

    private var header: some View {
        Text("Community").dsText(.h1Tab).foregroundStyle(palette.ink)
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

    // MARK: - 2. The glass hero — the ONLY glass hero on this screen

    private var schoolHeroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let school = viewModel.schoolStanding?.school {
                Text("№\(school.rank) THIS WEEK").dsText(.kicker).tabularNumbers().foregroundStyle(palette.muted)
                Text(school.name).dsText(.cardTitle).foregroundStyle(palette.ink)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", school.avgMemberPercentile))
                        .font(.archivo(32, weight: 800))
                        .tabularNumbers()
                        .foregroundStyle(palette.ink)
                    Text("AVG MEMBER PCTL").dsText(.kicker).foregroundStyle(palette.muted)
                }
                Text(school.campusCity).dsText(.rowTitle).foregroundStyle(palette.muted)
                Text("your gauntlet counts")
                    .dsText(.serif(13.5, italic: true)).foregroundStyle(palette.muted)
                    .padding(.top, 4)
            } else {
                Text("SCHOOL STANDING").dsText(.kicker).foregroundStyle(palette.muted)
                Text("No standing yet").dsText(.rowTitle).foregroundStyle(palette.muted)
                Text("your gauntlet counts")
                    .dsText(.serif(13.5, italic: true)).foregroundStyle(palette.muted)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 30)
    }

    // MARK: - 3. YOUR GROUPS — tap pushes .groupPage(id) onto communityPath

    private var yourGroupsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR GROUPS").dsText(.kicker).foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            if viewModel.groups.isEmpty {
                Text("No groups yet").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.vertical, 10)
            } else {
                ForEach(viewModel.groups) { group in
                    NavigationLink(value: AppRoute.groupPage(group.id)) {
                        groupRow(group)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    private func groupRow(_ group: GroupSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).dsText(.rowTitle).foregroundStyle(palette.ink)
                Text(group.role.uppercased()).dsText(.meta).foregroundStyle(palette.muted)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }

    // MARK: - 4. CONNECTIONS — FREE NOW green dot; swap-invite-pending decoration

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONNECTIONS").dsText(.kicker).foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            if viewModel.connections.isEmpty {
                Text("No connections yet").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.vertical, 10)
            } else {
                ForEach(viewModel.connections) { connection in
                    connectionRow(connection)
                }
            }
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    private func connectionRow(_ connection: Connection) -> some View {
        HStack(spacing: 12) {
            avatarCircle(initials: initials(for: connection.displayName))
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName).dsText(.rowTitle).foregroundStyle(palette.ink)
                if connection.swapInvitePending {
                    Text("swap invite pending").dsText(.meta).foregroundStyle(palette.muted)
                }
            }
            Spacer(minLength: 12)
            if connection.freeNow {
                HStack(spacing: 5) {
                    Circle().fill(palette.green).frame(width: 7, height: 7)
                    Text("FREE NOW").dsText(.kicker).foregroundStyle(palette.green)
                }
            }
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }

    // Photo optional: connections never render an actual image in this app
    // yet (AvatarSheetView's own header does the same) — always the ink
    // initials circle, matching that precedent exactly.
    private func avatarCircle(initials: String) -> some View {
        ZStack {
            Circle().fill(palette.ink).frame(width: 36, height: 36)
            Text(initials).font(.archivo(12, weight: 700)).foregroundStyle(palette.onInk)
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").compactMap(\.first)
        return String(parts.prefix(2)).uppercased()
    }
}

#if DEBUG
#Preview {
    ZStack { DSBackground(); CommunityView() }
}
#endif
