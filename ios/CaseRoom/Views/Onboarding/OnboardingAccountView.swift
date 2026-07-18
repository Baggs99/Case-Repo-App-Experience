/*
 * Purpose: The account-completion / profile-import screen (flow step .account,
 *          Decisions §2-1d "profile import (LinkedIn/Google skip code)") — sibling
 *          of OnboardingEmailView: top `‹ Back` + STEP 3 OF 05 progress mark, an
 *          H1, ONE glass hero field bound to vm.displayName, the ink-capsule
 *          "Continue" (→ VM.submitAccount), a serif "or" divider, then two flat
 *          glass secondary buttons "Continue with Google/LinkedIn" (→ VM.startOAuth;
 *          text labels only — staircase-mark-only rule forbids brand glyphs), plus
 *          the shared inline error slot that surfaces the OAuth-unavailable note.
 * Inputs: OnboardingViewModel (Bindable — binds vm.displayName + reads submitting/error).
 * Outputs: OnboardingAccountView (full-screen, on DSBackground).
 * Run: hosted by OnboardingRootView (Task 7); DEBUG hatch `-OnbAccount`.
 */

import SwiftUI

struct OnboardingAccountView: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var viewModel: OnboardingViewModel

    // Client-side UX only — the server (updateProfile) is the real validator.
    // Just enough to keep the primary button honest: a name must be present.
    private var canSubmit: Bool {
        !viewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSubmitting
    }

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

                Text("Who are you?")
                    .dsText(.h1Tab)
                    .foregroundStyle(palette.ink)

                nameField
                    .padding(.top, 22)

                continueButton
                    .padding(.top, 18)

                orDivider
                    .padding(.top, 26)

                oauthButton(title: "Continue with Google", provider: .google)
                    .padding(.top, 20)

                oauthButton(title: "Continue with LinkedIn", provider: .linkedin)
                    .padding(.top, 12)

                // Shared inline error — same treatment as OnboardingEmailView (meta,
                // muted; tokens only, no red hex). Surfaces both a profile-save
                // failure and the OAuth-unavailable message from VM.startOAuth.
                if let errorText = viewModel.errorText {
                    Text(errorText)
                        .dsText(.meta)
                        .foregroundStyle(palette.muted)
                        .padding(.top, 16)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    // The single glass HERO on this screen (matches the Email field recipe).
    private var nameField: some View {
        TextField("Your name", text: $viewModel.displayName)
            .dsText(.rowTitle)
            .foregroundStyle(palette.ink)
            .tint(palette.ink)
            .textContentType(.name)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassChip()
            .disabled(viewModel.isSubmitting)
    }

    // The one filled button per screen (§1): ink capsule primary.
    private var continueButton: some View {
        Button {
            Task { await viewModel.submitAccount() }
        } label: {
            Group {
                if viewModel.isSubmitting {
                    ProgressView().tint(palette.onInk)
                } else {
                    Text("Continue").dsText(.rowTitle).foregroundStyle(palette.onInk)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.5)
    }

    // A thin hairline rule with a small centered serif "or".
    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(palette.hairline).frame(height: 1)
            Text("or")
                .dsText(.serif(13))
                .foregroundStyle(palette.muted)
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    // Flat glass secondary button (§1 line 29 "glass key/chip/secondary button",
    // rgba(255,255,255,.55) capsule) — deliberately lighter than the hero field so
    // three glass surfaces still read as ONE hero + two secondary chips. Text label
    // only: no brand glyph/logo (staircase-mark-only rule).
    private func oauthButton(title: String, provider: OAuthProvider) -> some View {
        Button {
            Task { await viewModel.startOAuth(provider) }
        } label: {
            Text(title)
                .dsText(.rowTitle)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(DSPressStyle())
        .glassChipFlat()
        .disabled(viewModel.isSubmitting)
    }
}

#if DEBUG
#Preview {
    OnboardingAccountView(viewModel: OnboardingFixtures.viewModel(step: .account))
}
#endif
