/*
 * Purpose: Group page (canvas 6a C-14 detail push) — the weekly points board
 *          (rank · name · streak · points, tabular numerals; streak column
 *          renders ink/muted, NEVER green — a green column would blow the
 *          ≤3-greens ceiling), the TOP FIVE ADVANCE divider (ranks 1–5 above,
 *          the rest greyed/demoted below), a serif note on admin-only member
 *          progress + leadership transfers, and (admin-only, gated on
 *          `isAdmin` — defense-in-depth over the backend 403) the "Transfer
 *          leadership" affordance + member-progress surface. Non-admins never
 *          see the admin section.
 * Inputs: GroupPageViewModel (default live). RootShell's `.groupPage`
 *         destination passes `currentUserId: sessionStore.user?.id` on the
 *         live path, or an injected fixture-backed VM under `-GroupPageFixtures`
 *         (mirrors the AvatarSheetView injectable-VM pattern).
 * Outputs: none (navigation via AppRouter.shared.communityPath — externally
 *          driven by RootShell's `NavigationStack(path: $router.communityPath)`,
 *          same idiom as CaseDetailView popping libraryPath).
 * Run: pushed via `NavigationLink(value: AppRoute.groupPage(id))` from
 *      CommunityView's YOUR GROUPS rows; RootShell's `communityDetailOpen`
 *      gate hides the top pills/tab bar while this is on screen.
 */

import SwiftUI

struct GroupPageView: View {
    let groupId: Int
    @Environment(\.dsPalette) private var palette
    @State private var viewModel: GroupPageViewModel
    @State private var showTransferPicker = false

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

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            Text("Loading group…").dsText(.meta).foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.detail == nil {
            errorState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }
                    boardSection
                    adminNote
                    if viewModel.isAdmin {
                        transferSection
                        progressSection
                    }
                    Color.clear.frame(height: 120)   // room behind the (suppressed) tab bar
                }
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

    // Shown over an already-loaded board when a later action (transfer/
    // progress load) fails — mirrors CommunityView's errorBanner + Retry.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message).dsText(.meta).foregroundStyle(palette.muted)
            Button { Task { await viewModel.load(groupId: groupId) } } label: {
                Text("Retry").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 1. Weekly points board — rank · name · streak · points
    // (all numerals tabular). The ONE sanctioned literal-population surface
    // (joined cohort) — still no "of N" headcount anywhere on this screen.

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WEEKLY POINTS").dsText(.kicker).foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            ForEach(viewModel.topFive) { entry in
                boardRow(entry, demoted: false)
            }
            topFiveDivider
            ForEach(viewModel.restOfBoard) { entry in
                boardRow(entry, demoted: true)
            }
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    // Verbatim canvas copy. Ranks 6+ render greyed/demoted below this line.
    private var topFiveDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(palette.hairline).frame(height: 1)
            Text("TOP FIVE ADVANCE").dsText(.kicker).foregroundStyle(palette.muted).fixedSize()
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
        .padding(.vertical, 10)
    }

    private func boardRow(_ entry: GroupLeaderboardEntry, demoted: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .dsText(.rowTitle).tabularNumbers()
                .foregroundStyle(demoted ? palette.faint : palette.ink)
                .frame(width: 22, alignment: .leading)
            Text(entry.displayName).dsText(.rowTitle)
                .foregroundStyle(demoted ? palette.muted : palette.ink)
            Spacer(minLength: 12)
            // Streak column — ink/muted, deliberately NOT green (the green
            // "DAY streak" tag elsewhere in the system is a single-tag
            // concession, not a full column; a green column here would blow
            // the ≤3-greens ceiling).
            Text("\(entry.streak)D").dsText(.meta).tabularNumbers()
                .foregroundStyle(palette.muted)
            Text("\(entry.points)")
                .dsText(.rowTitleStrong).tabularNumbers()
                .foregroundStyle(demoted ? palette.muted : palette.ink)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }

    // MARK: - 2. Serif admin-only note — visible to every member, explaining
    // that full member progress is admin-only and that leadership transfers
    // between members (the copy itself, not the note's visibility, is what's
    // admin-gated — the admin surfaces below are the actual gate).

    private var adminNote: some View {
        Text(viewModel.isAdmin
             ? "As admin you can see everyone's progress below, and hand leadership to another member."
             : "Full member progress is visible to your group's admin. Admins can transfer leadership to another member.")
            .dsText(.serif(13.5, italic: true)).foregroundStyle(palette.muted)
    }

    // MARK: - 3. Admin-only: transfer leadership (secondary = underline text)

    private var transferSection: some View {
        Button {
            showTransferPicker = true
        } label: {
            Text("Transfer leadership").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Transfer leadership to…", isPresented: $showTransferPicker, titleVisibility: .visible
        ) {
            ForEach(transferCandidates) { member in
                Button(member.displayName) {
                    Task { await viewModel.transfer(toUserId: member.userId) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // members[] minus self — the caller's own row is the current admin (the
    // pinned schema has exactly one admin per group), so filtering out the
    // "admin" role is equivalent to filtering out self.
    private var transferCandidates: [GroupMember] {
        (viewModel.detail?.members ?? []).filter { $0.role != "admin" }
    }

    // MARK: - 4. Admin-only: member-progress surface (tabular)

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MEMBER PROGRESS").dsText(.kicker).foregroundStyle(palette.muted)
                .padding(.bottom, 6)
            if let progress = viewModel.progress {
                ForEach(progress) { member in
                    progressRow(member)
                }
            } else {
                Text("Loading…").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.vertical, 10)
            }
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    private func progressRow(_ member: GroupProgressMember) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(member.displayName).dsText(.rowTitle).foregroundStyle(palette.ink)
            HStack(spacing: 18) {
                statPair(label: "CASES", value: "\(member.casesDone)")
                statPair(label: "MEAN GRADE", value: member.meanGrade.map { String(format: "%.1f", $0) } ?? "—")
                statPair(label: "DRILLS 30D", value: "\(member.drillAttempts30D)")
                statPair(label: "STREAK", value: "\(member.streak)D")
            }
        }
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }

    private func statPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).dsText(.rowTitleStrong).tabularNumbers().foregroundStyle(palette.ink)
            Text(label).dsText(.kicker).foregroundStyle(palette.muted)
        }
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
