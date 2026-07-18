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
- Plan: complete (f8d087f) · Opus plan-review APPROVE-WITH-FIXES → fixes applied (96296b0)
- Task 1 (net + gauntletRun route): complete (9a8b940, review SPEC PASS/CODE PASS, 1 inert Minor banked). iOS 424/0.
- Task 2 (Drills hub hero+trend): complete (4bc593c + fix f12bd6f). iOS 433/0. Review SPEC PASS/CODE PASS; Important kicker-wrap fixed (minimumScaleFactor 0.8 → one-line), 3 Minors fixed. Shot task2-hub.png faithful to canvas 5b hub.
  - NOTE: screenshot recipe = build to `-derivedDataPath /tmp/f7dd` (avoids stale DerivedData that predates hatches), uninstall+install, launch hatch. If a stale mic dialog blocks: simctl shutdown+boot, re-grant mic.
- Task 3 (scoped boards C-14/Wharton/Global/Schools): impl complete (cbd1978). iOS 443/0 (433+10, exit-0 verified). 4 shots task3-board-{c14,wharton,global,schools}.png clean + faithful. Lead finished the subagent's stranded run (test verify + shots + commit). Reviewer: pending.
  - RECIPE REFINED: after uninstall+install, the sim needs shutdown+boot to clear a stuck mic TCC dialog before shots (grant alone doesn't dismiss a shown dialog).
  - Review SPEC PASS/CODE PASS. BANKED MINORS (final-review triage): (1) DrillsViewModel.boardErrorMessage set in selectBoard catch but never rendered — board fails silently; render it in scopeBody. (2) transient "No school on file." during WHARTON fetch reads as error (no loading state spec'd).
- Task 4 (gauntlet run + result + rewire — OPUS JUDGMENT): complete (ad01e82). iOS 454/0 (443+11). Shots task4-run-numeric/run-choice/result faithful. FM diff EMPTY (invariant held); .drillRun unchanged (FM practice bridge). Review SPEC PASS/CODE PASS, no Crit/Imp. Wall-clock non-drifting timer, 409 recovery no re-submit. Implementer did NOT strand (ran synchronous + polled).
  - BANKED MINORS: (1) "See today's result" re-view drops elapsed "· MM:SS" (GauntletResult has no elapsed field — backend follow-up); (2) ⌫ text glyph U+232B (within-brief); (3) cold-start percentile "—" (acceptable).
- Task 5 (tablet 2b two-column hub — sonnet): complete (8b1177b). iOS 454/0 (no new tests — no new logic). Shot task5-tablet.png (portrait per macOS-rotate precedent) faithful to canvas 2b two-column. Review SPEC PASS/CODE PASS; 1 non-blocking Minor (inner-column spacing 22 vs HomeView 14 — defensible).

## ALL 5 TASKS COMPLETE. Final commits: 9a8b940(T1) 4bc593c+f12bd6f(T2) cbd1978(T3) ad01e82(T4) 8b1177b(T5).
## Full suites: backend 655, iOS 458/0 (454 + 4 fix tests).
## Whole-branch adversarial review: APPROVE-WITH-FIXES, 0 Crit, 2 Important (both failure-path dead-ends):
##   I1 hub stuck "Loading…" on any load() fail (Retry unreachable); I2 boardErrorMessage never rendered ("No school on file." on net error).
## FIXED (1693d94): I1 → errorBanner+Retry in gauntlet==nil branch; I2 → boardErrorRow+Retry; +4 tests.
## Re-review: CLEAN — both Important closed, no residual Crit/Imp. PHASE F7 = APPROVE.
## Report committed: docs/superpowers/sdd/fe-f7-report.md. Housekeeping done. PHASE COMPLETE.
</content>
