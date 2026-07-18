/*
 * Purpose: The Drills hub's scoped leaderboard (canvas 5b 949-983 / tablet DC
 *          dScope 0-3 logic) — chips `C-14` `WHARTON` `GLOBAL` `SCHOOLS`
 *          (active = ink underline, inactive = faint no-underline), the
 *          head+note kickers, the per-scope body, and a serif foot line.
 *          Honors the "board reality vs canvas" deviation (bgap-b8-report
 *          "Interfaces delivered"): B8 exposes a literal per-member rank+
 *          points list ONLY for scope=group (C-14). scope=school/global
 *          return the caller's OWN percentile (a single value), not a
 *          member list; scope=schools returns the school-vs-school
 *          avg-percentile list. The canvas's WHARTON/GLOBAL per-member lists
 *          are aspirational — this view never fabricates one. Every ranking
 *          is percentile or literal-cohort-rank; no view path here renders a
 *          count/"of N" (delta §0.2).
 * Inputs: DrillsViewModel (scope state + the 4 board caches + copy/format
 *         helpers).
 * Outputs: none (scope taps call `viewModel.selectBoard(_:)`).
 * Run: mounted by DrillsView as `boardsSection`.
 */

import SwiftUI

struct GauntletBoard: View {
    @Environment(\.dsPalette) private var palette
    let viewModel: DrillsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headNoteRow
            chipsRow
            scopeBody
                .padding(.top, 8)
            Text(viewModel.currentBoardFoot)
                .dsText(.serif(12, italic: true)).foregroundStyle(palette.muted)
                .padding(.top, 10)
        }
        .padding(.top, 13)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .top)
    }

    // MARK: - Head/note kickers + scope chips (canvas 5b 952-961)

    private var headNoteRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(viewModel.currentBoardHead).dsText(.kicker).foregroundStyle(palette.muted)
            Spacer()
            if let note = viewModel.currentBoardNote {
                Text(note).font(.archivo(9, weight: 600)).tracking(0.1 * 9)
                    .tabularNumbers().foregroundStyle(palette.muted)
            }
        }
    }

    private var chipsRow: some View {
        HStack(spacing: 16) {
            ForEach(DrillsViewModel.BoardScope.allCases, id: \.self) { scope in
                chipButton(scope)
            }
        }
        .padding(.bottom, 9)
        .overlay(Rectangle().fill(palette.hairline).frame(height: 1), alignment: .bottom)
    }

    /// Active = ink, weight-600, underline. Inactive = `palette.faint`
    /// (#A9B4C4, owner-locked token), no underline — canvas 5b line 959.
    private func chipButton(_ scope: DrillsViewModel.BoardScope) -> some View {
        let isActive = viewModel.boardScope == scope
        return Button {
            Task { await viewModel.selectBoard(scope) }
        } label: {
            Text(scope.chipLabel)
                .font(.archivo(10.5, weight: 600))
                .tracking(0.1 * 10.5)
                .foregroundStyle(isActive ? palette.ink : palette.faint)
                .underline(isActive)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var scopeBody: some View {
        switch viewModel.boardScope {
        case .c14: c14Body
        case .wharton: whartonBody
        case .global: globalBody
        case .schools: schoolsBody
        }
    }

    // MARK: - C-14 (group) — literal rank+points list, unchanged from Task 2:
    // TOP FIVE ADVANCE divider before rank 6, your row highlighted.

    private var c14Body: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.board?.entries ?? []) { entry in
                if entry.rank == 6 {
                    topFiveDivider
                }
                c14Row(entry)
            }
        }
    }

    private var topFiveDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(palette.hairline).frame(height: 1)
            Text("TOP FIVE ADVANCE").font(.archivo(8, weight: 600)).tracking(0.15 * 8)
                .foregroundStyle(palette.muted)
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
        .padding(.vertical, 5)
    }

    // `BoardEntry` has no `sub` field (canvas `Sloan`/`Booth`) — renders
    // blank, a documented deviation (no fiction); per-row `delta` is
    // similarly omitted (no field on the wire).
    private func c14Row(_ entry: BoardEntry) -> some View {
        let isYou = viewModel.isYourRow(entry)
        return HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.archivo(12.5, weight: 800)).tabularNumbers()
                .foregroundStyle(palette.ink)
                .frame(width: 28, alignment: .leading)
            Text(entry.displayName)
                .font(.archivo(13, weight: isYou ? 700 : 400))
                .foregroundStyle(palette.ink)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entry.points)")
                .font(.archivo(13, weight: 700)).tabularNumbers()
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 4).padding(.vertical, 11)
        .background(isYou ? palette.surface.opacity(0.55) : Color.clear)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }

    // MARK: - WHARTON (school) — the school card + a single YOUR STANDING
    // row. NO fabricated member list (B8 gives no per-member school data).

    private var whartonBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let school = viewModel.schoolBoard?.school {
                whartonCard(school)
            } else {
                Text("No school on file.").dsText(.meta).foregroundStyle(palette.muted)
                    .padding(.vertical, 11)
            }
            yourStandingRow
        }
    }

    private func whartonCard(_ school: SchoolCard) -> some View {
        HStack(spacing: 8) {
            Text("\(school.rank)")
                .font(.archivo(12.5, weight: 800)).tabularNumbers()
                .foregroundStyle(palette.ink)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(school.name).font(.archivo(13, weight: 700)).foregroundStyle(palette.ink)
                Text(school.campusCity).font(.archivo(10.5, weight: 400)).foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(DrillsViewModel.decimal1(school.avgMemberPercentile))
                .font(.archivo(13, weight: 700)).tabularNumbers()
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 4).padding(.vertical, 11)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }

    // Highlighted (surface glass bg, weight 700) — ink, not green (greens
    // budget: the hub already spends its 3).
    private var yourStandingRow: some View {
        HStack(spacing: 8) {
            Text("YOUR STANDING").font(.archivo(10, weight: 600)).tracking(0.12 * 10)
                .foregroundStyle(palette.muted)
            Spacer()
            Text(viewModel.percentileLabel(viewModel.schoolBoard?.yourPercentile))
                .font(.archivo(13, weight: 700)).tabularNumbers()
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 4).padding(.vertical, 11)
        .background(palette.surface.opacity(0.55))
    }

    // MARK: - GLOBAL — a single percentile hero. Ink, never green (greens
    // budget); graceful nil → "—" (cold start / no scored history yet).

    private var globalBody: some View {
        Text(viewModel.percentileLabel(viewModel.globalBoard?.yourPercentile))
            .font(.archivo(40, weight: 800)).tabularNumbers()
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
    }

    // MARK: - SCHOOLS — school-vs-school avg-percentile list, your school
    // highlighted "· yours" (matched by school id, ink weight 700 — not
    // green).

    private var schoolsBody: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.schoolsBoard?.schools ?? []) { school in
                schoolsRow(school)
            }
        }
    }

    private func schoolsRow(_ school: SchoolCard) -> some View {
        let isYours = viewModel.isYourSchool(school)
        return HStack(spacing: 8) {
            Text("\(school.rank)")
                .font(.archivo(12.5, weight: 800)).tabularNumbers()
                .foregroundStyle(palette.ink)
                .frame(width: 28, alignment: .leading)
            HStack(spacing: 4) {
                Text(school.name).font(.archivo(13, weight: isYours ? 700 : 400))
                    .foregroundStyle(palette.ink)
                Text("· \(school.campusCity)\(isYours ? " · yours" : "")")
                    .font(.archivo(10.5, weight: 400))
                    .foregroundStyle(palette.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(DrillsViewModel.decimal1(school.avgMemberPercentile))
                .font(.archivo(13, weight: 700)).tabularNumbers()
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 4).padding(.vertical, 11)
        .background(isYours ? palette.surface.opacity(0.55) : Color.clear)
        .overlay(Rectangle().fill(palette.hairlineSoft).frame(height: 1), alignment: .bottom)
    }
}
