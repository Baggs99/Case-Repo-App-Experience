/*
 * Purpose: Community tab (canvas 6a phone / 2d tablet) — the ONE glass
 *          school hero (rank/avg member percentile/campus city + serif
 *          aside), YOUR GROUPS, and CONNECTIONS rows (FREE NOW green dot;
 *          swap-invite-pending decoration). No forum, no headcounts
 *          (Decisions §0.1/§0.2). Branches on `hSize` (F4/CasesListView
 *          precedent): phone pushes .groupPage(id) onto communityPath;
 *          `.regular` renders CommunityMasterDetailView instead — a
 *          permanently-open right pane with select-on-tap, no push (so
 *          communityPath stays empty and RootShell's shell chrome shows).
 * Inputs: CommunityViewModel (default live). DEBUG `-CommunityFixtures`
 *         swaps in a fixture-backed CommunityViewModel (CommunityFixtures.swift)
 *         so screenshots need no dev server — mirrors CasesListView/
 *         -LibraryFixtures exactly.
 * Outputs: none (navigation via NavigationLink(value:) onto the communityPath
 *          NavigationStack RootShell mounts — phone only).
 * Run: mounted by RootShell inside `NavigationStack(path: $router.communityPath)`.
 */

import SwiftUI

struct CommunityView: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.horizontalSizeClass) private var hSize
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
                sizeClassBody
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var sizeClassBody: some View {
        if hSize == .regular {
            // Task 4: tablet master–detail (canvas 2d). No H1 here — RootShell
            // draws the centered "Community" tab label on .regular.
            CommunityMasterDetailView(viewModel: viewModel)
        } else {
            content
        }
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
        CommunitySchoolHeroCard(school: viewModel.schoolStanding?.school)
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
                        CommunityGroupRow(group: group)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    // MARK: - 4. CONNECTIONS — FREE NOW green dot; swap-invite-pending decoration

    private var connectionsSection: some View {
        CommunityConnectionsSection(connections: viewModel.connections)
    }
}

// MARK: - Shared subviews (phone body above + Task 4's CommunityMasterDetailView
// left column both bind these to the same CommunityViewModel data).

/// The glass school hero (rank/avg member percentile/campus city + serif
/// aside) — the ONLY glass hero on the screen (canvas 6a phone / 2d tablet
/// both open with this card, verbatim).
struct CommunitySchoolHeroCard: View {
    let school: SchoolInfo?
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let school {
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
}

/// A single YOUR GROUPS row's visual content (name + role) — shared by the
/// phone NavigationLink push and Task 4's tablet select-on-tap Button.
/// `isSelected` only matters on tablet (false on phone, no highlight; same
/// square-corner glass-chip treatment as LibraryRowView's selected row).
struct CommunityGroupRow: View {
    let group: GroupSummary
    var isSelected: Bool = false
    @Environment(\.dsPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).dsText(.rowTitle).foregroundStyle(palette.ink)
                Text(group.role.uppercased()).dsText(.meta).foregroundStyle(palette.muted)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background {
            if isSelected { GlassSurface(shape: Rectangle(), kind: .chip) }
        }
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }
}

/// CONNECTIONS rows — FREE NOW green dot; swap-invite-pending decoration.
/// Shared by the phone body and Task 4's tablet left column (canvas 6a / 2d
/// both render this section verbatim, only differing in surrounding order).
struct CommunityConnectionsSection: View {
    let connections: [Connection]
    @Environment(\.dsPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONNECTIONS").dsText(.kicker).foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            if connections.isEmpty {
                Text("No connections yet").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.vertical, 10)
            } else {
                ForEach(connections) { connection in
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
