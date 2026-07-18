/*
 * Purpose: The terminal "You're in." payoff (flow step .done, Decisions §2-1d
 *          "→ 'You're in.' summary") — the celebratory full-drawn StaircaseMark
 *          (the whole mark inking itself ink→green on appear, the payoff of "the
 *          mark drawing itself"), the takeoverDisplay headline "You're in.", a
 *          calm serif welcome line, and ONE ink-capsule "Enter" (→ VM.finish() →
 *          SessionStore.bootstrap → shell). No Back and no STEP chrome: the done
 *          screen is the flow's end, and the big mark drawing fully IS the
 *          fully-inked staircase, so a second small progress mark is omitted.
 * Inputs: OnboardingViewModel (read-only — drives finish()).
 * Outputs: OnboardingDoneView (full-screen, on DSBackground).
 * Run: hosted by OnboardingRootView (Task 7); DEBUG hatch `-OnbDone`.
 */

import SwiftUI

struct OnboardingDoneView: View {
    @Environment(\.dsPalette) private var palette
    let viewModel: OnboardingViewModel
    // Local spinner state: finish() flips SessionStore (not vm.isSubmitting) and
    // the VM is out of scope for this task, so the "Enter" progress is tracked here.
    @State private var isFinishing = false

    var body: some View {
        ZStack {
            DSBackground()

            VStack(spacing: 0) {
                Spacer()

                // The payoff: the whole mark draws itself ink→green on appear.
                StaircaseMarkView(lineWidth: 6, animated: true)
                    .frame(width: 148, height: 123)

                Text("You're in.")
                    .dsText(.takeoverDisplay)
                    .foregroundStyle(palette.ink)
                    .padding(.top, 26)

                Text("Your cohort is ready when you are.")
                    .dsText(.serif(16.5))
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)

                Spacer()

                // Surfaces finish()'s failure affordance (e.g. the post-verify
                // cookie went stale) so "Enter" is never silently inert.
                if let error = viewModel.errorText {
                    Text(error)
                        .dsText(.meta)
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }

                enterButton
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }

    // The one filled button per screen (§1): ink capsule primary.
    private var enterButton: some View {
        Button {
            isFinishing = true
            Task {
                await viewModel.finish()
                isFinishing = false
            }
        } label: {
            Group {
                if isFinishing {
                    ProgressView().tint(palette.onInk)
                } else {
                    Text("Enter").dsText(.rowTitle).foregroundStyle(palette.onInk)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
        .disabled(isFinishing)
    }
}

#if DEBUG
#Preview {
    OnboardingDoneView(viewModel: OnboardingFixtures.viewModel(step: .done))
}
#endif
