/*
 * Purpose: The F9 onboarding container — owns the OnboardingViewModel and renders
 *          a rise-timed switch over the six signup screens (welcome → email →
 *          passcode → account → group → done), holding auth local until finish().
 *          Mounted by RootShell's logged-out branch; "Log in" opens LoginView.
 * Inputs: SessionStore (live init) or a pre-parked OnboardingViewModel (DEBUG hatch).
 * Outputs: none (the VM drives the flow; auth flips only via finish()→bootstrap()).
 * Run: RootShell renders it while !isAuthenticated; -Onboarding <step> hatch shots.
 */

import SwiftUI

struct OnboardingRootView: View {
    @Environment(\.dsPalette) private var palette
    // The container owns the VM for the whole flow so field values + the locally
    // held verified user survive every step change (auth stays false until finish).
    @State private var viewModel: OnboardingViewModel
    @State private var showLogin = false

    // Live entry: build the VM against the app's shared APIClient/WebAuth impls,
    // threading the environment SessionStore (it is NOT a singleton).
    init(sessionStore: SessionStore) {
        _viewModel = State(initialValue: OnboardingViewModel(sessionStore: sessionStore))
    }

    // DEBUG hatch entry: adopt a fixture-parked VM so -Onboarding <step> captures
    // the container chrome (progress mark + transitions) with no dev server.
    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            DSBackground()
            content
                .transition(.opacity)
        }
        // Rise curve (Decisions §1: 0.22,1,0.36,1) crossfades step changes — calm,
        // nothing bounces; each screen carries its own entrance motion within.
        .animation(DSMotion.riseCurve, value: viewModel.step)
        // Existing-user login. A successful sign-in sets sessionStore.user →
        // RootShell swaps to the shell, unmounting this view (no manual dismiss);
        // the "‹ Back" affordance lets a user who changed their mind return.
        .fullScreenCover(isPresented: $showLogin) { loginCover }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .welcome:
            OnboardingWelcomeView(viewModel: viewModel, onLogin: { showLogin = true })
        case .email:
            OnboardingEmailView(viewModel: viewModel)
        case .passcode:
            OnboardingPasscodeView(viewModel: viewModel)
        case .account:
            OnboardingAccountView(viewModel: viewModel)
        case .group:
            OnboardingGroupJoinView(viewModel: viewModel)
        case .done:
            OnboardingDoneView(viewModel: viewModel)
        }
    }

    private var loginCover: some View {
        ZStack(alignment: .topLeading) {
            LoginView()
            Button { showLogin = false } label: {
                Text("‹ Back").dsText(.rowTitle).foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20).padding(.top, 12)
        }
    }
}
