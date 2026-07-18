# F6 — Interviewer consoles · Progress ledger

Updated: 2026-07-18 · Branch: fe/f6-console · Worktree: /Users/thomaskgould/dev/fe-f6

## Baselines (bootstrap) — all match required
- Backend: **655**/0 (`caserepo_fe_f6`, schema+migrations 002–035+seed, venv 3.13) ✓
- iOS: **668**/0 (scheme CaseRoom, iPhone 17 942222D4) ✓
- xcodegen: idempotent (git clean after generate) ✓
- Sims: iPhone 17 942222D4 booted + mic granted (app/tests/xctest); iPad 653F37B8 idle (boot+grant per task); stray F4 iPhone shut.

## Now
T1–T4 done + approved. Dispatching T5 (PDF mode — tablet left-overlay + phone).

## Done
- T4 tablet hero RIGHT rail (68d5750, +fix 9be1e6d): candidate feed (dark pane, LIVE chip, self-view
  118×66, dark tokens) + SEGMENT TIMER (34pt tabular, RUNNING chip, Start/Pause, Stop·log) + SEGMENTS
  LOGGED laps + RUBRIC — LIVE (all dims, 16pt mini-cells sharing score handler, ink/slate split,
  overallAvgText green). iOS **697**/0. Shots tablet-console-full/-rail (portrait). Opus review
  APPROVE-WITH-NITS → all 3 fixed: (1) tablet SCORE unscored "0/10"→"— /10" [was a real miss];
  (2) rail cells BLANK via new `ScoreCells.showsNumbers` param (default true — F5 usages byte-
  identical); (3) rail readout compact "—"/"8/10" vs left-pane spaced. OWNER-GATE flagged: numbered
  vs blank live-cells (matched canvas blank; confirm at demo).
- T3 tablet hero chrome + LEFT pane (4ffd565 15194bc 8a5640a d038adb): top bar (mark/wordmark | case |
  CANDIDATE | tap-run master-clock chip MM:SS+N LEFT green<5 | Finalize & send), 2px cap bar, 7 stage
  chips, READ ALOUD, exhibit rows, GUIDANCE, SCORE THIS STAGE stacked dims (name+desc+{pts}/{max}+24pt
  cells+evidence), footer; right rail = T4 placeholder. Fixed T2 nit#1 (STAGE OF %02d from
  stages.count). 12-dim/max-10 tablet shot fixture (A3 mock). iOS **696**/0. Shots PORTRAIT (landscape
  can't be forced headless — accepted constraint; top-bar/chip truncation is portrait-only, resolves
  at hero width). Opus review APPROVE-WITH-NITS. Open nit → fold into T4: unscored dim readout "0/{max}"
  → "— / {max}" on BOTH tablet(:752) and phone(:318).
- T2 phone console 8b (d53fe1c a6ecd82 3d50f18 2511478): InterviewerConsoleView (phone `.compact`
  full; `.regular` interim=phone until T3) + SessionView repoint at liveContent level (rv#3, candidate
  branch byte-identical, no 300h video wrapper) + `-startTakeover console-phone[-scored]` hatches +
  real-shaped 5-dim fixture. iOS **694**/0. 2 shots (phone-console, phone-console-scored — SENT·mm:ss
  frame). Opus review APPROVE-WITH-NITS (shots match 8b, light wins, tabular, rv#3 confirmed, reveal-
  once proven). Nit dispositions: #1 hardcoded "OF 06"→fold into T3 (stages.count); #2 rounded F0
  ScoreCells RATIFIED as canon (§6 pinned, F5-shipped); #3 no interviewer mute/self-view on phone =
  owner-visual deviation (canvas-8b-faithful); #4 tablet branch → T3.
- Plan (f0b5e5e): Opus plan-review REQUEST_CHANGES (2 blocking + 4 important + 5 nits) all folded.
- T1 console foundation (fff3396, c15308d, +fix 3dcce80): ConsoleScript (7 tablet / 6 phone stages +
  dims name/desc map + 3 authored PDF pages, verbatim) + pure ConsoleViewModel (clocks, laps,
  release/recall, toggle-clear, stage→dim resolution tablet-union-catchall / phone-1:1, finalize→
  moveToDebrief) + 23 tests. iOS **691**/0. Opus review: APPROVE-WITH-NITS (coverage guarantee
  adversarially proven) → 3 nits fixed. Additive-only, no transport/SessionView touch.
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
