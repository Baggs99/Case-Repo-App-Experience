/*
 * Purpose: The onboarding welcome hero (flow step .welcome) — the staircase mark
 *          drawing itself on entry above the myCase wordmark and a serif lede,
 *          with ONE ink-capsule "Get started" (→ VM.goToEmail) and an underlined
 *          "Log in" secondary (→ onLogin, wired by the container in Task 7).
 * Inputs: OnboardingViewModel (read-only here); onLogin closure (no-op standalone).
 * Outputs: OnboardingWelcomeView (full-screen, on DSBackground).
 * Run: hosted by OnboardingRootView (Task 7); DEBUG hatch `-OnbWelcome`.
 */

import SwiftUI

struct OnboardingWelcomeView: View {
    @Environment(\.dsPalette) private var palette
    let viewModel: OnboardingViewModel
    var onLogin: () -> Void = {}

    var body: some View {
        ZStack {
            DSBackground()

            VStack(spacing: 0) {
                Spacer()

                // The hero moment: the mark draws itself on appear.
                StaircaseMarkView(lineWidth: 6, animated: true)
                    .frame(width: 132, height: 110)

                // Wordmark lockup (the big mark above IS the mark, so the lockup
                // is text-only — not the chrome WordmarkChip, which carries its
                // own small mark and a glass chip we don't want as a second hero).
                (Text("my").font(.serifVoice(20, italic: true))
                 + Text("Case").font(.archivo(20, weight: 800)).tracking(-0.4))
                    .foregroundStyle(palette.ink)
                    .padding(.top, 22)

                Text("Where your cohort preps for the case.")
                    .dsText(.serif(16.5))
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)

                Spacer()

                getStartedButton

                Button { onLogin() } label: {
                    Text("Log in").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }

    private var getStartedButton: some View {
        Button {
            viewModel.goToEmail()
        } label: {
            Text("Get started")
                .dsText(.rowTitle)
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
    }
}

#if DEBUG
#Preview {
    OnboardingWelcomeView(viewModel: OnboardingFixtures.viewModel(step: .welcome))
}
#endif
