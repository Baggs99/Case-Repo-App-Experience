/*
 * Purpose: Dark session-takeover lobby (canvas 4a) — a glass LOBBY pill, the
 *          takeover hero ("vs <peer>"), the two participant seats with
 *          READY / JOINED state chips, and the role-appropriate
 *          knock/admit/consent/go-live affordances re-skinned onto the dark
 *          palette. All wiring stays on SessionViewModel's existing actions +
 *          published state (unchanged API).
 * Inputs: SessionViewModel (loaded + WS-connected by the host SessionView);
 *         \.dsPalette (dark, seamed by RootShell's takeover fullScreenCover).
 * Outputs: none.
 * Run: shown by SessionView while state is scheduled/lobby.
 */

import SwiftUI

/// Presentation state for a single lobby seat, derived from the VM's flags.
/// Pure + file-scoped so SessionViewModel's public API stays untouched and the
/// mapping is unit-testable. READY/JOINED are canvas-verbatim copy.
enum LobbySeatStatus: Equatable {
    case ready, joined, knocking, waiting, declined

    /// consented wins (READY), else present (JOINED), with the pre-entry
    /// candidate states (knocking / declined) taking precedence over both.
    static func resolve(consented: Bool, present: Bool, knocking: Bool, denied: Bool) -> LobbySeatStatus {
        if denied { return .declined }
        if knocking { return .knocking }
        if consented { return .ready }
        if present { return .joined }
        return .waiting
    }

    var label: String {
        switch self {
        case .ready:    return "READY"
        case .joined:   return "JOINED"
        case .knocking: return "KNOCKING"
        case .waiting:  return "WAITING"
        case .declined: return "DECLINED"
        }
    }

    /// Only READY/JOINED read as the scarce green accent; transitional states are muted.
    var isPresentState: Bool { self == .ready || self == .joined }
}

struct LobbyView: View {
    var viewModel: SessionViewModel
    @Environment(\.dsPalette) private var palette

    var body: some View {
        ZStack {
            DSBackground()

            VStack(spacing: 0) {
                lobbyPill
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 24)

                hero

                Spacer(minLength: 24)

                actions
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Top pill

    private var lobbyPill: some View {
        HStack(spacing: 7) {
            BlinkDot()
            Text("LOBBY · \(modeLabel)")
                .dsText(.kicker)
                .foregroundStyle(palette.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .glassChip()
    }

    private var modeLabel: String { viewModel.mode == "remote" ? "REMOTE" : "IN PERSON" }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(seatKicker)
                .dsText(.kicker)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 10)

            Text("vs \(peerName)")
                .dsText(.takeoverDisplay)
                .foregroundStyle(palette.ink)
                .padding(.bottom, 6)

            if let caseTitle = viewModel.caseTitle {
                Text(caseTitle)
                    .dsText(.serif(14.5, italic: true))
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 22)
            } else {
                Spacer().frame(height: 22)
            }

            seatRow(name: "You", initials: initials(from: ownName), status: mySeatStatus, isSelf: true)
                .overlay(alignment: .top) { hairline }

            seatRow(name: peerName, initials: initials(from: peerName), status: peerSeatStatus, isSelf: false)
                .overlay(alignment: .top) { hairline }
                .overlay(alignment: .bottom) { hairline }

            Text("Cameras open when the case begins. Feedback lands in your recap after.")
                .dsText(.serif(12, italic: true))
                .foregroundStyle(palette.faint)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hairline: some View {
        Rectangle().fill(palette.hairline).frame(height: 1)
    }

    private func seatRow(name: String, initials: String, status: LobbySeatStatus, isSelf: Bool) -> some View {
        HStack(spacing: 12) {
            avatar(initials: initials, isSelf: isSelf)
            Text(name)
                .dsText(.rowTitle)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(status.label)
                .font(.archivo(9, weight: 600))
                .tracking(9 * 0.13)
                .foregroundStyle(status.isPresentState ? palette.green : palette.muted)
        }
        .padding(.vertical, 13)
    }

    private func avatar(initials: String, isSelf: Bool) -> some View {
        Text(initials)
            .font(.archivo(11, weight: 700))
            .foregroundStyle(isSelf ? palette.onInk : palette.muted)
            .frame(width: 34, height: 34)
            .background(
                Circle().fill(isSelf ? palette.ink : palette.surface)
            )
            .overlay(
                Circle().strokeBorder(isSelf ? .clear : palette.hairline, lineWidth: 1)
            )
    }

    // MARK: - Actions (role + state, wired to existing VM actions)

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if viewModel.role == "candidate" {
                candidateActions
            } else if viewModel.role == "interviewer" {
                interviewerActions
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var candidateActions: some View {
        if viewModel.denied {
            note("Your knock was declined.")
            primaryButton("Knock again") { await viewModel.knock() }
        } else if !viewModel.admitted {
            note("Waiting to be admitted.")
            primaryButton("Knock") { await viewModel.knock() }
        } else if !viewModel.myConsent {
            note("You're in. Consent to recording to take your seat.")
            primaryButton("Consent to record") { await viewModel.toggleConsent() }
        } else {
            note("You're ready — waiting for the interviewer to begin.")
            underlineButton("Withdraw consent") { await viewModel.toggleConsent() }
        }
    }

    @ViewBuilder
    private var interviewerActions: some View {
        if viewModel.peerKnocked {
            note("\(viewModel.knockerName ?? "Your candidate") is knocking.")
            primaryButton("Admit") { await viewModel.admit() }
            underlineButton("Decline") { await viewModel.deny() }
        } else if !viewModel.myConsent {
            note(viewModel.peerPresent ? "\(peerName) is in the lobby." : "Waiting for \(peerName).")
            primaryButton("Consent to record") { await viewModel.toggleConsent() }
        } else if !(viewModel.consentInterviewer && viewModel.consentCandidate) {
            note("Waiting on \(peerName)'s consent.")
            underlineButton("Withdraw consent") { await viewModel.toggleConsent() }
        } else {
            primaryButton("Go Live") { await viewModel.goLive() }
        }
    }

    // MARK: - Reusable affordances

    private func primaryButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.archivo(14, weight: 600))
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(palette.ink))
        }
        .buttonStyle(DSPressStyle())
    }

    private func underlineButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.archivo(12.5, weight: 600))
                .foregroundStyle(palette.muted)
                .underline(true, pattern: .solid)
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.serif(13, italic: true))
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derived

    private var seatKicker: String {
        viewModel.role == "interviewer" ? "INTERVIEWER SEAT" : "CANDIDATE SEAT"
    }

    private var ownName: String {
        (viewModel.role == "interviewer" ? viewModel.interviewerName : viewModel.candidateName) ?? "You"
    }

    private var peerName: String {
        (viewModel.role == "interviewer" ? viewModel.candidateName : viewModel.interviewerName) ?? "Your peer"
    }

    /// My seat: consent drives READY; a pre-admit candidate is KNOCKING/DECLINED.
    private var mySeatStatus: LobbySeatStatus {
        let isCandidate = viewModel.role == "candidate"
        let knocking = isCandidate && !viewModel.admitted && !viewModel.denied
        // Interviewer (host) is always present; candidate is present once admitted.
        let present = !isCandidate || viewModel.admitted
        return .resolve(consented: viewModel.myConsent, present: present,
                        knocking: knocking, denied: isCandidate && viewModel.denied)
    }

    /// Peer seat: their consent drives READY; presence from signaling / knock,
    /// with the interviewer (host) treated as present from the candidate's side.
    private var peerSeatStatus: LobbySeatStatus {
        let peerIsInterviewer = viewModel.role == "candidate"
        let knocking = !peerIsInterviewer && viewModel.peerKnocked
        let present = peerIsInterviewer || viewModel.peerPresent || viewModel.peerConsent
        return .resolve(consented: viewModel.peerConsent, present: present,
                        knocking: knocking, denied: false)
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").compactMap(\.first)
        let joined = String(parts.prefix(2)).uppercased()
        return joined.isEmpty ? "—" : joined
    }
}

#Preview {
    NavigationStack {
        LobbyView(
            viewModel: SessionViewModel(
                sessionId: 1, service: APIClient.shared, signaling: SignalingClient()
            )
        )
    }
    .dsTheme(.dark)
}
