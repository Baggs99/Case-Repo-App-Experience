# F9 whole-branch review — carried findings / flags

## Resolved during per-task loop (verify they stayed fixed)
- T1: ASWebAuthenticationSession now retained until completion (dormant-live path).
- T2: fixtures throw StubError.unused (not fatalError).
- T3: OnboardingProgressMark ghosts the full staircase behind the ink→green trim (was a stray dash at step 1) — shared component.
- Final batch: submitCode clears code on ANY verify failure; finish() sets errorText if bootstrap fails to auth + Done surfaces it (+VM test); OAuth buttons opacity-dim while submitting; `.id(viewModel.step)` so the rise crossfade fires.

## Flags to carry to the report (NOT bugs — brief says flag, don't invent)
1. Canvas 1d STALE+truncated → ALL onboarding copy is lead-authored from Decisions §2-1d prose. Strings: "Where your cohort preps for the case." / "Your school email." / "you@school.edu" / "We'll check your school's on the list." / "Check your email." / "We sent a code to <email>." / "Resend" / "Who are you?" / "Your name" / "Continue" / "or" / "Continue with Google" / "Continue with LinkedIn" / "Join your cohort." / "If your cohort shared an invite code, enter it to join theirs." / "Invite code" / "Skip for now" / "You're in." / "Your cohort is ready when you are." / "Enter". Plus VM error strings.
2. STEP mapping: email…done = 1…5, welcome = pre-step intro. Done omits STEP chrome (one mark per screen > plan bullet — ratified).
3. Native OAuth is impossible by construction today (callback 302s to `/`, never matches a native scheme; SafariViewService cookie jar isolated from APIClient) AND creds un-provisioned (503). Buttons are protocol-injected/mock+fixture-proven; live OAuth = documented Thomas follow-up (needs backend native-scheme callback + token/cookie hand-back + creds).
4. OWNER-VISUAL gates (per "visual judgment = owner gate"): progress kicker zero-pads "STEP 01 OF 05" (aligns with "05"); welcome/done text-wordmark lockup (avoids double-mark); the rise crossfade between steps (verify it reads calm).
5. JUDGMENT: startOAuth success → .group (skips the display-name profile write; web cookie stands in).

## Areas to adversarially probe
- Retrofit seam: is there ANY path (incl. the LoginView cover, the DEBUG hatches, back()) that flips SessionStore.isAuthenticated before finish()? Could a logged-out user get trapped with no way to reach LoginView or back to welcome?
- Tokens-only across ALL new files (grep `#`hex / `Color(red:` / `Color(.sRGB` — must be none outside DesignSystem).
- Reject-list across all 6 screens: staircase-only/no emoji/SF Symbols, square content corners, underline (not outlined) secondaries, ≤1 glass hero/screen, ≤3 greens/screen, tabular keypad/step numerals, NO population counts anywhere (esp. group-join).
- Additive-only to shared files (CaseRoomApp hatch chain, RootShell logged-out branch only, APIClient/Models/SessionStore additive); no AppRoute case added; DO-NOT-TOUCH (webapp/transport/widgets/App Intents/deep-links/project.yml) untouched.
- Test quality: real assertions, the seam test is genuine, no tautologies.
