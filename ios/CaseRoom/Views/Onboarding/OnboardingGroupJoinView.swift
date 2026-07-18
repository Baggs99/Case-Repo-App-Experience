/*
 * Purpose: The group-join step (flow step .group, Decisions §2-1d "group join
 *          (C-14 etc.) → 'You're in.' summary") — sibling of OnboardingEmailView:
 *          top `‹ Back` + STEP 4 OF 05 progress mark, an H1, a serif aside, ONE
 *          glass invite-code field bound to vm.inviteCode, the ink-capsule "Join"
 *          (→ VM.joinGroup), an underlined "Skip for now" (→ VM.skipGroup — the
 *          key skippable affordance, kept plainly present under the primary), and
 *          the shared inline error slot surfacing the unknown-invite-code note.
 * Inputs: OnboardingViewModel (Bindable — binds vm.inviteCode + reads state).
 * Outputs: OnboardingGroupJoinView (full-screen, on DSBackground).
 * Run: hosted by OnboardingRootView (Task 7); DEBUG hatch `-OnbGroup`.
 */

import SwiftUI

struct OnboardingGroupJoinView: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var viewModel: OnboardingViewModel

    // Client-side UX only — the server (joinGroup → 404) is the real validator.
    // Just enough to keep the primary honest: a code must be present.
    private var canSubmit: Bool {
        !viewModel.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                Text("Join your cohort.")
                    .dsText(.h1Tab)
                    .foregroundStyle(palette.ink)

                inviteField
                    .padding(.top, 22)

                Text("If your cohort shared an invite code, enter it to join theirs.")
                    .dsText(.serif(15))
                    .foregroundStyle(palette.muted)
                    .padding(.top, 14)

                // Inline error — same treatment as OnboardingEmailView (meta,
                // muted; tokens only, no red hex). Surfaces the unknown-code case.
                if let errorText = viewModel.errorText {
                    Text(errorText)
                        .dsText(.meta)
                        .foregroundStyle(palette.muted)
                        .padding(.top, 12)
                }

                Spacer()

                joinButton

                // Skippable is the key affordance: an UNDERLINED text button
                // (never an outlined box), centered under the primary so it reads
                // as a plainly-offered second path, not a buried link.
                Button { viewModel.skipGroup() } label: {
                    Text("Skip for now")
                        .dsText(.actionLabel)
                        .underline()
                        .foregroundStyle(palette.ink)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isSubmitting)
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    // The single glass HERO on this screen (matches the Email field recipe).
    // Codes read like "C14-XXXX" → uppercase, no autocorrect.
    private var inviteField: some View {
        TextField("Invite code", text: $viewModel.inviteCode)
            .dsText(.rowTitle)
            .foregroundStyle(palette.ink)
            .tint(palette.ink)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassChip()
            .disabled(viewModel.isSubmitting)
    }

    // The one filled button per screen (§1): ink capsule primary.
    private var joinButton: some View {
        Button {
            Task { await viewModel.joinGroup() }
        } label: {
            Group {
                if viewModel.isSubmitting {
                    ProgressView().tint(palette.onInk)
                } else {
                    Text("Join").dsText(.rowTitle).foregroundStyle(palette.onInk)
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
    OnboardingGroupJoinView(viewModel: OnboardingFixtures.viewModel(step: .group))
}
#endif
