# F9 Onboarding retrofit — progress ledger

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
- Task 2 (VM + progress mark + passcode keypad + fixtures): PENDING
- Task 3 (Welcome + Email screens): PENDING
- Task 4 (Passcode screen): PENDING
- Task 5 (Account completion + OAuth buttons): PENDING
- Task 6 (Group join + Done): PENDING
- Task 7 (Container + RootShell integration + hatches): PENDING

## Flags to carry into report
- Canvas 1d STALE+truncated → all onboarding copy lead-authored from Decisions §2-1d prose.
- STEP N OF 05 mapping = email…done (1..5); welcome = pre-step intro. Judgment call.
- Native OAuth callback-scheme gap + un-provisioned creds → live OAuth is a Thomas follow-up (§8.1); buttons mock/fixture-proven.
