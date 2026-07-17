# F4 — Library · Phase Ledger

Updated: 2026-07-17 · Branch: fe/f4-library · Worktree: /Users/thomaskgould/dev/fe-f4 · DB: caserepo_fe_f4

## Baselines (bootstrap)
- Backend suite: 655 passed (`.venv/bin/python -m pytest tests/ -q`) — DB seeded.
- iOS suite: 313 passed / 0 failures (scheme CaseRoom, iPhone 17 F4 sim 49C5BC31, mic granted).
- xcodegen generate: idempotent (working tree clean, .xcodeproj gitignored).
- Finish line: iOS ≥ 313 + new VM tests; backend stays 655 (iOS-only phase).

## Now
Plan APPROVED (2 review rounds) → executing Task 1 (networking).

## Done
- Bootstrap: DB created + seeded; baselines backend 655 / iOS 313 / xcodegen idempotent.
- Plan + plan-review r1 (4 Important + 9 Minor, all resolved) + r2 (blocking stale-deletion strike
  + detail-meta nit, both fixed) → reviewer stated "Fix #1 and it's an APPROVE" → APPROVED.
  Plan: docs/superpowers/plans/2026-07-17-fe-f4-plan.md.

## Blocked / decisions needed
- (none yet)

## Assumptions
- "YOUR HISTORY WITH IT" derives from `/api/v1/sessions?scope=recent` title-matched to the case
  (the pinned /api/v1/cases* contract carries no per-case user history and no case_id on session
  rows) — best-effort join, documented as a backend follow-up seam.
- Row "FOR YOU"/"SCHEDULED" + detail "RECOMMENDED FOR YOU" decorations need B4 recs +
  upcoming-sessions cross-reference (not in the Library payload) → live rows omit them; the DEBUG
  fixture carries them so screenshots match the canvas. Detail tag OPEN FOR YOU / DONE — RETIRED
  FOR YOU IS derivable from done_for_you and renders live.

## Task log
- Task 1 (networking): complete — commits 3e8e302..315b279, review clean (APPROVE A+B).
  Suite 318/318. Minors (non-blocking): test name overpromises (cosmetic); use sites must
  nil-coalesce runCount→0 / doneForYou→false (carried into Task 2/3).
