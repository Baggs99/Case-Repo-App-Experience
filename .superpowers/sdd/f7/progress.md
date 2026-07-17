# F7 Drills — phase ledger

Updated: 2026-07-17 · Branch: fe/f7-drills · Worktree: /Users/thomaskgould/dev/fe-f7
DB: caserepo_fe_f7 · port 8107 · sims iPhone 17 942222D4 / iPad Pro 653F37B8

## Baselines (bootstrap, §3) — both GREEN
- Backend: **655 passed** (`.venv/bin/python -m pytest tests/ -q`) — matches required 655.
- iOS: **413 / 0 failures** (CaseRoom scheme, iPhone 17 942222D4, Xcode 27 beta via DEVELOPER_DIR) — matches required 413.
- xcodegen generate: idempotent (clean git after run). xcodeproj is TRACKED.
- DB: createdb → schema → migrations 0*.sql (32 files, thru 035) → seed_caseroom_dev.py all OK.

## Finish line
Backend stays 655 (F7 touches ZERO backend). iOS 413 + N new VM/decode tests.

## Tasks
- Plan: in progress
</content>
