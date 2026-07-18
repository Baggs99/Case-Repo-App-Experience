# F9 Onboarding retrofit — progress ledger

## STATUS: DONE — head d4c51e8. iOS 727/0, backend 655. Whole-branch review APPROVE (0 CRIT/0 IMP/3 MINOR). Report: docs/superpowers/sdd/fe-f9-report.md. No dev server started (fixture hatches); iPad never booted; port 8109 clear.


Branch: fe/f9-onboarding · Worktree: /Users/thomaskgould/dev/fe-f9 · Cut at ae46fed.

## Baselines (bootstrap, verified 2026-07-18)
- Backend suite: **655 passed** (`.venv/bin/python -m pytest tests/ -q`).
- iOS suite: **699 passed / 0** (xcodebuild test, iPhone 17 sim 942222D4, Xcode 27.0 27A5218g via DEVELOPER_DIR).
- xcodegen generate: idempotent (git clean after regen).
- DB caserepo_fe_f9: schema + 32 migrations + seed (a/b/c@yale.edu, case 1) — DONE.

## Plan
- docs/superpowers/plans/2026-07-17-fe-f9-plan.md — WRITTEN. Plan review: PENDING.

## Tasks
- Task 1 (plumbing: OnboardingService + OAuthStarter + SessionStore hook): COMPLETE (34b336c; review APPROVE both axes; fix c... session-retain committed). Suite 708/0 (+9). Reviewer IMPORTANT (dormant session-retain) fixed; MINORs = xcodeproj folder-globbed (no pbxproj change expected), thin transport coverage on verify/join (optional).
- Task 2 (VM + progress mark + passcode keypad + fixtures): COMPLETE (b7cfc77; review APPROVE/APPROVE). Suite 726/0 (+18). Fixes: StubError.unused convention (committed). OWNER-VISUAL FLAG: progress kicker renders "STEP 01 OF 05" (zero-padded to align with "05") vs plan's unpadded "STEP 1 OF 05" — kept padded, Thomas gate. Judgment: startOAuth success → .group (skips display-name write). Nit deferred: finish() lacks re-entry guard (terminal, idempotent).
- Task 3 (Welcome + Email screens): COMPLETE (1efc8d1; review APPROVE code / A REQUEST_CHANGES fixed). Suite 726/0. Shots t3-welcome.png (lead-eyeballed: clean, on-brand), t3-email.png (reshot after fix). FIX: OnboardingProgressMark now ghosts the full staircase (hairline) behind the ink→green trim so it reads as a mark filling in (was a stray dash at step 1) — shared component, benefits Tasks 4-6. Authored copy: lede "Where your cohort preps for the case.", placeholder "you@school.edu", aside "We'll check your school's on the list." Deviation: text wordmark lockup on welcome (avoids double-mark) — approved.
- Task 4 (Passcode screen): COMPLETE (c7e7749; review APPROVE/APPROVE). Suite 726/0. Shot t4-passcode.png (lead-eyeballed: clean, sibling of email, mark 2/5 inked). Authored copy: "Check your email.", "We sent a code to <email>.", "Resend". DEBUG hatch seeds vm.code="123" locally (fixture factory stays code-free). DEFERRED-to-final MINOR: submitCode clears dots only on 401; a generic verify failure leaves 6 filled dots and re-submit needs a manual delete — consider clearing code on ANY verify failure (VM tweak) at final pass.
- Task 5 (Account completion + OAuth buttons): COMPLETE (a458d14; review APPROVE/APPROVE). Suite 726/0. Shot t5-account.png (lead-eyeballed: mark 3/5, glass name-field hero brighter, 2 flat-glass OAuth secondaries text-only, no glyphs). glassChip(field hero)/glassChipFlat(OAuth .55 secondary) split confirmed correct vs ≤1-hero + §1 recipe. Authored copy: "Who are you?", "Your name", "Continue", "or", "Continue with Google/LinkedIn". OAuth mock/fixture-proven; live gap = Thomas follow-up. DEFERRED-to-final MINORs (optional cosmetic): isSubmitting spinner shows on Continue when an OAuth chip is tapped; disabled OAuth chips lack opacity dim.
- Task 6 (Group join + Done): COMPLETE (87bd644; review APPROVE/APPROVE). Suite 726/0. Shots t6-group.png (skippable clear, mark 4/5, no population counts) + t6-done.png (lead-eyeballed: full mark drawn, "You're in." bookends welcome). RATIFIED deviation: STEP-05 chrome omitted on Done (one mark per screen > plan bullet — reviewer + lead agree). Authored copy: "Join your cohort.", "If your cohort shared an invite code, enter it to join theirs.", "Invite code", "Your cohort is ready when you are.", "Enter". DEFERRED-to-final MINOR: Done "Enter" has no failure affordance if finish()/bootstrap fails to auth (add errorText on bootstrap failure).
- Task 7 (Container + RootShell integration + hatches): COMPLETE (0140cf6; review APPROVE/APPROVE). Suite 726/0. Shot t7-container-welcome.png. Seam VERIFIED intact (auth stays false until finish; LoginView preserved via welcome→cover w/ ‹Back escape). MINOR (transition no-op) fixed in batch below.
- FINAL-FIX BATCH (b382453): T4 clear code on ANY verify failure; T6 finish() sets errorText if bootstrap fails to auth + Done surfaces it (+1 VM test); T5 OAuth buttons opacity-dim while submitting; T7 `.id(viewModel.step)` so the rise crossfade fires. Suite 727/0.

## Flags to carry into report
- Canvas 1d STALE+truncated → all onboarding copy lead-authored from Decisions §2-1d prose.
- STEP N OF 05 mapping = email…done (1..5); welcome = pre-step intro. Judgment call.
- Native OAuth callback-scheme gap + un-provisioned creds → live OAuth is a Thomas follow-up (§8.1); buttons mock/fixture-proven.
