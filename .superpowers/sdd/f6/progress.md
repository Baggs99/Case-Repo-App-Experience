# F6 — Interviewer consoles · Progress ledger

Updated: 2026-07-18 · Branch: fe/f6-console · Worktree: /Users/thomaskgould/dev/fe-f6

## Baselines (bootstrap) — all match required
- Backend: **655**/0 (`caserepo_fe_f6`, schema+migrations 002–035+seed, venv 3.13) ✓
- iOS: **668**/0 (scheme CaseRoom, iPhone 17 942222D4) ✓
- xcodegen: idempotent (git clean after generate) ✓
- Sims: iPhone 17 942222D4 booted + mic granted (app/tests/xctest); iPad 653F37B8 idle (boot+grant per task); stray F4 iPhone shut.

## Now
Plan written (`docs/superpowers/plans/2026-07-17-fe-f6-plan.md`) → dispatching Opus plan-review.
Next: T1 console foundation (VM + ConsoleScript + integration seam).

## Done
- Deep investigation: canvas 8b (phone) + Tablet 1a (STAGES/DIMS/PDF verbatim), backend surface
  (reveal=one-way no recall; finalize; RubricTemplateItem has dimension; real template = 5 dims/max 5
  vs canvas 12/1–10), F5 seams (SessionView interviewer-live branch, shared RubricViewModel,
  ScoreCells, SessionFixtures stub pattern, RootShell/CaseRoomApp hatch wiring, LiveShared media).
- Locked architecture A1–A8 (see plan).

## Blocked / decisions needed
- 4 owner-visual deviations queued (plan §Open deviations) — surface at FW6 demo, non-blocking.

## Assumptions
- Console = interviewer's live seat (supersedes F5 dark InterviewerLiveView); light palette override.
- Rubric template-agnostic; scoring/exhibits/finalize via existing RubricViewModel; no transport touch.
- Stage script + PDF authored client-side (no backend source exists).
