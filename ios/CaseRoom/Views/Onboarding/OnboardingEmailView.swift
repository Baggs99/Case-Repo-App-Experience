/*
 * Purpose: The school-email gate (flow step .email) — top `‹ Back` + STEP 1 OF 05
 *          progress mark, an H1, ONE glass field bound to the VM email, a serif
 *          aside about the registry check, an inline error row, and the ink-capsule
 *          "Send the code" (→ VM.submitEmail), disabled until an "@" is present.
 * Inputs: OnboardingViewModel (Bindable — binds the email field + reads state).
 * Outputs: OnboardingEmailView (full-screen, on DSBackground).
 * Run: hosted by OnboardingRootView (Task 7); DEBUG hatch `-OnbEmail`.
 */

import SwiftUI

struct OnboardingEmailView: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var viewModel: OnboardingViewModel

    // Client-side UX only — the server is the real validator (requestOTP is a
    // no-enumeration 202 regardless). Just enough to keep the button honest.
    private var canSubmit: Bool {
        let trimmed = viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && !viewModel.isSubmitting
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

                Text("Your school email.")
                    .dsText(.h1Tab)
                    .foregroundStyle(palette.ink)

                emailField
                    .padding(.top, 22)

                Text("We'll check your school's on the list.")
                    .dsText(.serif(15))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 14)

                if let errorText = viewModel.errorText {
                    Text(errorText)
                        .dsText(.meta)
                        .foregroundStyle(palette.muted)
                        .padding(.top, 12)
                }

                Spacer()

                sendButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    private var emailField: some View {
        TextField("you@school.edu", text: $viewModel.email)
            .dsText(.rowTitle)
            .foregroundStyle(palette.ink)
            .tint(palette.ink)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.username)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassChip()
            .disabled(viewModel.isSubmitting)
    }

    private var sendButton: some View {
        Button {
            Task { await viewModel.submitEmail() }
        } label: {
            Group {
                if viewModel.isSubmitting {
                    ProgressView().tint(palette.onInk)
                } else {
                    Text("Send the code").dsText(.rowTitle).foregroundStyle(palette.onInk)
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
}

#if DEBUG
#Preview {
    OnboardingEmailView(viewModel: OnboardingFixtures.viewModel(step: .email))
}
#endif
