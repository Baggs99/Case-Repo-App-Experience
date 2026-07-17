# F0 — Design Foundation · progress ledger

Updated: 2026-07-17 · Branch: fe/f0-foundation · Base SHA: d106111

## Bootstrap
- `xcodegen generate` idempotent: PASS (byte-identical on re-run).
- Scheme: `CaseRoom`. Xcode 26.6, xcodegen 2.45.4.
- Baseline iOS suite: **273 passed / 0 failed / TEST SUCCEEDED** on sim
  `iPhone 17` UDID `A10D5A1D…` (iOS 27.0 runtime).
- **Environment note (blocking → resolved):** the suite hangs indefinitely on
  `SessionViewModelTests.testEnteringLiveStartsLiveActivityForInterviewer` on a
  FRESH sim — that test uses the real `RoomRecorder()`, whose
  `AVAudioApplication.requestRecordPermission()` blocks in a host-less test with
  no prompt UI. Fix (no code change): grant mic on the sim before testing —
  `xcrun simctl privacy <sim> grant microphone study.mycase` +
  `…study.mycase.CaseRoomTests` + `…com.apple.dt.xctest.tool`. After granting,
  the test passes in ~5.6s. ALL later test runs pin `-destination id=A10D5A1D…`.
- Bounded-timeout wrapper (macOS has no `timeout`):
  `perl -e 'alarm shift @ARGV; exec @ARGV' <secs> xcodebuild …`.

## Now
Implementing DesignSystem directly (Opus lead) + Opus review-subagent gates —
see report for the orchestration-adaptation rationale.

## Done
- Plan written + self-reviewed: docs/superpowers/plans/2026-07-17-fe-f0-plan.md
- Fonts downloaded (Archivo + Source Serif 4 variable TTFs + OFL) — CoreText
  probe confirmed family+weight-trait resolves correct named instances.
- Source files written: Tokens, Typography, Motion, StaircaseMark,
  SteppedTimeline, ScoreCells, Glass, Chrome/*, PreviewFixtures, Gallery.

## Assumptions
- `.xcodeproj` stays gitignored (repo convention); commit `project.yml` only.
- Dark palette = per-screen takeover theme via `\.dsPalette`, not iOS dark mode.
- Glass hand-built over `.ultraThinMaterial` (fidelity > native glassEffect;
  deployment target iOS 17).
