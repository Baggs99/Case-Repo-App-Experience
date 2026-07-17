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
- Task 2 (LibraryViewModel): complete — commits 315b279..2415dd1, review clean (APPROVE A+B).
  Suite 337/337 (+19). Carry-ins to Task 3: (a) change avgRating formatter %g→%.1f + test "4.0"→"4.0"
  (canvas tabular fidelity); (b) view MUST call load() on `type` change (server-side filter);
  (c) "Market Sizing" case_type = documented backend-limited seam (exact-match under-matches compound
  vocab), fixtures cover screenshots.
- Task 3 (phone Library 5a): CODE complete + committed 789e2fd (RootShell detail-chrome gate,
  CasesListView 5a rewrite, LibraryRowView, LibraryFixtures, -LibraryFixtures hatch, avgRating
  %.1f fix). Screenshot task3-phone-list.png verified vs 5a (H1, 5 chips, count, toggles, divider,
  greyed retired rows, FOR YOU/SCHEDULED tags, no icons).
  TEST STATUS: LibraryViewModelTests(20)+LibraryDecodingTests(5)=25 GREEN in isolation (0.026s).
  Earlier full run: EVERY executed test passed EXCEPT the pre-existing env flake
  SessionViewModelTests.testEnteringLiveStartsLiveActivityForInterviewer (blocks on sim mic TCC;
  F0/ORCHESTRATION-documented; GREEN at bootstrap). ENVIRONMENTAL BLOCKER on the one-shot full-suite
  green: (1) mic TCC grant not sticking after screenshot reinstall; (2) SEVERE memory thrash from the
  concurrent FW3-sibling F2 phase building/testing on its own sim (~90+ min continuous) — the doc's
  ">2 xcodebuild+sim stacks thrash the 16GB machine" condition. Exceeded 2-attempt watchdog on both.
  GATE (carried to final review): authoritative full-suite green (skip-flaky or with mic re-grant)
  to be run when the machine is quiet (F2 done). Task-3 diff review proceeds now (reviews code, not a
  live suite).
- Task 3 REVIEW: APPROVE (A spec/canvas + B quality). 3 Minors: (1) hex-in-comment in
  LibraryRowView.swift:12-15 → reword before final review (grep-clean); (2) "Market Sizing"
  case_type filter unverified vs live DB (documented seam); (3) report wording nit (no change).
- Task 4 (case detail 5a): CODE complete + COMPILES (TEST BUILD SUCCEEDED), committed 6aec73c.
  CaseDetailContent (shared phone/tablet) + CaseDetailView (migrated to LibraryService, plain
  ‹ Library back) + -startCaseDetail hatch + CaseDetailContentTests. Rubric clean (no hex/SF Symbols),
  all verbatim copy present. PLAN CORRECTION: CasesViewModel.swift KEPT (PairCreateView/ProposeNowView/
  its tests still use old CasesService — plan's "last reference" premise wrong; coexistence is fine).
  GATED (env): task4 screenshots + focused/full test-green — simctl + test-without-building wedge under
  F2 thrash (2+ hrs, load 9.9); batch at end when F2 quiet. Review proceeds on code+copy via diff.
