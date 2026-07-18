/*
 * Purpose: Shared group-page BODY (canvas 6a C-14 detail push / 2d tablet
 *          right pane) — the weekly points board (rank · name · streak ·
 *          points, tabular numerals; streak column ink/muted, NEVER green),
 *          the TOP FIVE ADVANCE divider, the serif admin-only note, and
 *          (admin-only) the "Transfer leadership" affordance + member-
 *          progress surface. Mirrors CaseDetailContent's content/chrome
 *          split: this view renders ONLY the already-loaded state
 *          (`viewModel.detail != nil`) — GroupPageView (phone push chrome)
 *          and CommunityView's tablet right pane (no chrome) each own their
 *          own loading/error/`.task` wiring and wrap this in a ScrollView.
 * Inputs: GroupPageViewModel (already loaded); DetailLayout (.phone/.tablet)
 *         — tablet drops the phone-only bottom spacer that clears the
 *         (suppressed) floating tab bar, since the tablet master-detail
 *         container clears the 560pt bar itself (LibraryMasterDetailView's
 *         .bottom 96 precedent).
 * Outputs: none.
 * Run: `GroupPageContent(viewModel:, layout: .phone)` inside GroupPageView's
 *      ScrollView; `GroupPageContent(viewModel:, layout: .tablet)` inside
 *      CommunityMasterDetailView's right pane.
 */

import SwiftUI

struct GroupPageContent: View {
    let viewModel: GroupPageViewModel
    let layout: DetailLayout

    @Environment(\.dsPalette) private var palette
    @State private var showTransferPicker = false

    var body: some View {
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
            if layout == .phone {
                Color.clear.frame(height: 120)   // room behind the (suppressed) tab bar
            }
        }
    }

    // Shown over an already-loaded board when a later action (transfer/
    // progress load) fails — mirrors CommunityView's errorBanner + Retry.
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message).dsText(.meta).foregroundStyle(palette.muted)
            Button { Task { await viewModel.reload() } } label: {
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
        ScrollView {
            GroupPageContent(
                viewModel: GroupPageViewModel(
                    fixtureDetail: CommunityFixtures.groupDetail,
                    fixtureIsAdmin: true,
                    fixtureProgress: CommunityFixtures.groupProgress),
                layout: .phone)
            .padding(22)
        }
    }
}
#endif
