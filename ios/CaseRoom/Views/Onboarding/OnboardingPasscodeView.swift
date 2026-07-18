/*
 * Purpose: The email-OTP passcode screen (flow step .passcode) — sibling of
 *          OnboardingEmailView: top `‹ Back` + STEP 2 OF 05 progress mark, an H1,
 *          a muted "we sent a code to <email>" line, the 6-dot PasscodeKeypad
 *          (auto-advances → VM.submitCode at six digits), an inline error slot,
 *          and an underlined "Resend" (→ VM.resendCode). No filled button —
 *          submission is the keypad's auto-advance; a subtle spinner marks isSubmitting.
 * Inputs: OnboardingViewModel (Bindable — binds vm.code + reads submitting/error/email).
 * Outputs: OnboardingPasscodeView (full-screen, on DSBackground).
 * Run: hosted by OnboardingRootView (Task 7); DEBUG hatch `-OnbPasscode`.
 */

import SwiftUI

struct OnboardingPasscodeView: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            DSBackground()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { viewModel.back() } label: {
                        Text("‹ Back").dsText(.rowTitle).foregroundStyle(palette.ink)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 12)
                    OnboardingProgressMark(progressStep: viewModel.progressStep)
                }

                Spacer().frame(height: 40)

                Text("Check your email.")
                    .dsText(.h1Tab)
                    .foregroundStyle(palette.ink)

                Text("We sent a code to \(viewModel.email).")
                    .dsText(.serif(15))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 14)

                Spacer()

                keypadBlock
                    .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    private var keypadBlock: some View {
        VStack(spacing: 0) {
            // Fixed-height status slot above the dots so toggling the spinner
            // never shifts the keypad — the "near the dots, doesn't block layout"
            // brief. Empty (reserved) when idle.
            ZStack {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(palette.muted)
                        .accessibilityLabel("Verifying")
                }
            }
            .frame(height: 22)
            .padding(.bottom, 4)

            PasscodeKeypad(code: $viewModel.code, onComplete: {
                Task { await viewModel.submitCode() }
            })
            .disabled(viewModel.isSubmitting)

            // Inline error — same treatment as OnboardingEmailView (meta, muted;
            // tokens only, no red hex). submitCode's 401 also clears the dots.
            if let errorText = viewModel.errorText {
                Text(errorText)
                    .dsText(.meta)
                    .foregroundStyle(palette.muted)
                    .padding(.top, 16)
            }

            Button {
                Task { await viewModel.resendCode() }
            } label: {
                Text("Resend").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSubmitting)
            .padding(.top, 22)
        }
    }
}

#if DEBUG
#Preview {
    OnboardingPasscodeView(viewModel: OnboardingFixtures.viewModel(step: .passcode))
}
#endif
