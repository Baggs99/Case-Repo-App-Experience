# FE Phase F9 — Onboarding retrofit — Report

**Status:** DONE
**Branch:** `fe/f9-onboarding` · **Worktree:** `/Users/thomaskgould/dev/fe-f9` · cut at `ae46fed`.
**Head SHA:** `d4c51e8`
**Suites:** iOS **699 → 727 / 0** (+28: 9 service + 13 VM + 6 keypad — counting the finish-failure + guard tests). Backend **655 / 0** (webapp untouched). xcodegen idempotent. Xcode 27.0 (27A5218g) via DEVELOPER_DIR, iPhone 17 sim `942222D4`.

Retrofits the LoginView-era entry into the designed **signup onboarding flow** while keeping
existing email/password login working for existing users. Flow: welcome (staircase mark draws)
→ school-email gate → passcode keypad (auto-advance at 6) → account completion incl.
Google/LinkedIn → group join (skippable) → "You're in." `STEP N OF 05` progress = the mark
drawing itself.

Plan: `docs/superpowers/plans/2026-07-17-fe-f9-plan.md` (Opus plan-review APPROVE, 1 IMPORTANT +
6 MINOR folded in). Ledger: `.superpowers/sdd/f9/progress.md`. Diffs/shots:
`.superpowers/sdd/f9/`.

---

## Tasks (each: fresh Opus implementer → diff → fresh Opus reviewer, fix loops)

| Task | Scope | Head | Review |
|---|---|---|---|
| 1 | Plumbing: `OnboardingService` (OTP/join) + `OAuthStarter` + `SessionStore.finishOnboarding` + models + tests | `34b336c` (+fix `ddeb143`) | APPROVE/APPROVE (1 IMPORTANT session-retain fixed) |
| 2 | VM state machine + `OnboardingProgressMark` + `PasscodeKeypad` + fixtures + tests | `b7cfc77` (+fix `67335bb`) | APPROVE/APPROVE (StubError.unused fix) |
| 3 | Welcome + School-email screens + hatches | `1efc8d1` (+fix `74…` ghost) | A REQUEST_CHANGES→fixed (progress-mark ghost); code APPROVE |
| 4 | Passcode screen (keypad, dots, auto-advance, resend) | `c7e7749` | APPROVE/APPROVE |
| 5 | Account completion (name + Google/LinkedIn OAuth buttons) | `a458d14` | APPROVE/APPROVE |
| 6 | Group join (skippable) + "You're in." Done | `87bd644` | APPROVE/APPROVE |
| 7 | `OnboardingRootView` container + RootShell logged-out branch + `-Onboarding` hatch | `0140cf6` | APPROVE/APPROVE (seam intact) |
| Final-fix batch | clear-code-on-any-verify-fail, Done failure affordance (+test), OAuth opacity dim, rise `.id` transition | `b382453` | (from per-task reviews) |
| Whole-branch | adversarial review over `ae46fed..HEAD` | `d4c51e8` (guard fix) | APPROVE — 0 CRITICAL / 0 IMPORTANT / 3 MINOR |

Screen evidence (fixture hatches — simctl can't type; no dev server needed): welcome, email,
passcode, account, group, done, container-welcome under `.superpowers/sdd/f9/shots/`. Every
screen reviewer compared the shot against the Decisions §2-1d prose (NOT the stale canvas).

---

## New iOS interfaces (all additive)

- `Networking/APIClient.swift` — `protocol OnboardingService { requestOTP(email:); verifyOTP(email:code:)->User; joinGroup(inviteCode:)->JoinedGroup }`; APIClient conforms. Endpoints (verified vs bgap-b5/b6 reports, exact): `POST /api/v1/auth/otp/request` `{email}` (any-2xx ok, 202), `POST /api/v1/auth/otp/verify` `{email,code}`→`{user}` wrapper (401→`APIError.unauthorized`), `POST /api/v1/groups/join` `{invite_code}` (404→`OnboardingError.unknownInviteCode`); account write reuses `PUT /api/v1/profile` display_name.
- `Networking/Models.swift` — `struct JoinedGroup {id,name,alreadyMember}` (deliberate 3-of-6 subset), `enum OnboardingError {unknownInviteCode, oauthUnavailable}`.
- `Networking/OnboardingOAuth.swift` — `enum OAuthProvider{google,linkedin}`, `protocol OAuthStarter{start(provider:)}`, `WebAuthOAuthStarter` (ASWebAuthenticationSession, scheme "caseroom", retained until completion).
- `State/SessionStore.swift` — `func finishOnboarding() async { await bootstrap() }` (the ONLY auth flip in the flow).
- `State/OnboardingViewModel.swift` — `@Observable @MainActor` state machine (`Step`, `progressStep`, submit/resend/oauth/join/skip/finish). Holds the verified user LOCALLY; never writes `SessionStore.user`.
- `Views/Onboarding/` — 6 screens + `OnboardingRootView` container + `OnboardingProgressMark` + `PasscodeKeypad`.
- `App/RootShell.swift` — logged-out branch now `OnboardingRootView(sessionStore:)` (existing-user LoginView reached via welcome "Log in", fullScreenCover + ‹ Back escape). No AppRoute case added. `App/CaseRoomApp.swift` — additive DEBUG hatches `-OnbWelcome/-OnbEmail/-OnbPasscode/-OnbAccount/-OnbGroup/-OnbDone` (per-screen) + `-Onboarding <step>` (container).

The retrofit seam (adversarially verified): `isAuthenticated == user != nil`; the OTP-verify
session cookie is the durable auth; the VM holds the user locally so RootShell keeps the
onboarding cover through account/group; `finish()`→`finishOnboarding()`→`bootstrap()`→`/me` is
the sole flip. Seam test walks welcome→group asserting `isAuthenticated == false` at every step.

---

## Deviations / uncertainty flags (per brief: FLAG, don't invent)

1. **Canvas 1d is STALE + truncated** → ALL onboarding copy is lead-authored from the
   Decisions §2-1d prose + F0 tokens + the 8a/3-series look. Full authored-string list in
   `.superpowers/sdd/f9/final-minor-findings.md` (welcome lede, screen H1s, field placeholders,
   button labels, error strings). OWNER copy review recommended.
2. **STEP mapping** = email…done (1…5); welcome is the pre-step intro. Done screen omits STEP
   chrome (one mark per screen > the plan bullet — ratified by lead + reviewer; the big
   fully-drawn mark IS the 5/5 state).
3. **Native OAuth impossible by construction today** (NOT just un-provisioned): B5's callback
   302s to `/` — never matches a native `callbackURLScheme`; and the SafariViewService cookie
   jar is isolated from APIClient's HTTPCookieStorage. Combined with un-provisioned creds
   (503). Buttons are protocol-injected + mock/fixture-proven (VM tests + t5-account shot),
   not a live round-trip. → **Thomas follow-up (ORCHESTRATION §8.1): backend must add a
   native-scheme callback redirect + a token/cookie hand-back, AND provision Google/LinkedIn
   creds + WEBAPP_SESSION_SECRET.**
4. **JUDGMENT:** `startOAuth` success advances straight to `.group` (the web session cookie
   stands in for the display-name profile write); a typed name is discarded if the user then
   taps an OAuth button. Documented inline.

### OWNER-VISUAL gates (per "visual judgment = owner gate" — render + ask Thomas)
- Progress kicker zero-pads "STEP 01 OF 05" (aligns tabularly with "05").
- Welcome + Done use a text wordmark lockup (serif-italic "my" + Archivo-800 "Case") instead
  of the chrome `WordmarkChip`, to avoid a second mark next to the giant hero staircase.
- The step-to-step rise crossfade (`.id(step)` + opacity, DSMotion.riseCurve) — confirm it reads calm.
- All 7 shots (`.superpowers/sdd/f9/shots/`) — lead eyeballed each as clean/on-brand; final
  aesthetic sign-off is Thomas's.

## DEFERRED (non-blocking, from the whole-branch review)
- Done-screen stale-cookie dead-end: if `bootstrap()` fails to auth, the error surfaces but the
  only recovery is app relaunch (→ welcome). Optional "Start over" affordance.
- (OAuth typed-name discard — see flag 4.)

## ESCALATIONS
None. No Fable/deep consults used or required.

## For the orchestrator before merging
- Expected merge conflict with F10 (parallel FW7): none in iOS — F10 is web-only (`webapp/`),
  untouched here. F9 touched RootShell's logged-out branch + CaseRoomApp hatch chain + additive
  APIClient/Models/SessionStore; if any later FE work re-touched those, reconcile keep-both.
- No new AppRoute case; no migrations; webapp/transport/widgets/App Intents/deep-links/
  project.yml untouched (grep-clean). `.xcodeproj` is gitignored (xcodegen folder-globs new
  files) — nothing project-file to commit; run `xcodegen generate` before building at merge.
- FW7 is the final wave — after F9 + F10 merge, the full-app demo checkpoint (§7) is ready
  (needs Thomas signing via `ship`).
