# F2 — Home + Timeline detail · Ledger

Updated: 2026-07-17 · Branch: fe/f2-home · Worktree: /Users/thomaskgould/dev/fe-f2
Base commit: 72c4351 (cut from feature/backend-gap after F1 merge)

## Bootstrap (DONE)
- DB caserepo_fe_f2 created → schema.sql → migrations 0*.sql (all idempotent) → seed_caseroom_dev.py (users a/b/c@yale.edu, case 1). evidence: all steps exit 0.
- Backend baseline: `DATABASE_URL=…/caserepo_fe_f2 <venv> -m pytest tests/ -q` → **655 passed** (matches target).
- iOS baseline: `xcodegen generate` (idempotent) + `xcodebuild -scheme CaseRoom -destination id=942222D4-…(iPhone 17) test` → **313 tests, 0 failures** (matches target). mic granted on sim.
- Env: DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer for all xcode* calls. venv = /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python.

## Now
Plan-review PASS (after fixes). Executing task loop.
Order: T1 DS primitives → T2 API → T4 Timeline detail → T3 Home phone → T5 Tablet → T6 close-out.

## Done
- Bootstrap (above): backend 655, iOS 313.
- Plan written + committed (c019546).
- Plan-review (Opus): REQUEST_CHANGES → 2 IMPORTANT (I-1 add profile() for identity/cohort rank; I-2 T4-before-T3 ordering, no stub) + 6 MINOR all fixed in plan. Re-commit pending.

## Tasks
- (T1..T6 pending)

## Blocked / decisions needed
- (none yet)

## Assumptions
- Test/shot sim = iPhone 17 UDID 942222D4-A174-4963-AA23-9853F5ABDFB6 (env block overrides F0's stale A10D5A1D). iPad Pro 11 (M5) UDID 653F37B8-9FA1-48AE-BE7E-47E2F3AD982C for tablet shots (landscape).
