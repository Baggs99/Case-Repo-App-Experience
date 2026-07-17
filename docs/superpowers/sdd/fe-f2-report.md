# F2 — Home + Timeline detail · Phase Report

**Status:** DONE · **Branch:** `fe/f2-home` · **Base:** `72c4351` (post-F1)
**iOS suite:** 313 → **367** green (0 failures) · +54 tests
**Backend suite:** **655** green — F2 touched ZERO backend files (`git diff --name-only
72c4351..HEAD` = exclusively `ios/` + `docs/` + `.superpowers/`). A full run showed
654/1 where the 1 was `test_ws_integration::test_full_flow_knock_admit_relay_bye`, a
flaky WebSocket-timing test that PASSES in isolation (0.61s) — not F2-caused.
**Date:** 2026-07-17 · Plan: `docs/superpowers/plans/2026-07-17-fe-f2-plan.md` ·
Ledger: `.superpowers/sdd/f2/progress.md` · Shots: `.superpowers/sdd/f2/shots/`

Home (canvas 3a phone + 2a tablet) and the Timeline-detail push (canvas 7b), bound
live to the merged B4/B7/B8 API, on F0's design system and F1's shell/router. F0's two
deferred actions discharged (SteppedTimeline label inversion + flat chip-glass variant).

---

## Tasks (each: fresh implementer → diff package → fresh Opus reviewer → fix→re-review)

| Task | Model | Scope | Commits | Review |
|---|---|---|---|---|
| Plan | opus | Plan + Opus plan-review (2 IMPORTANT + 6 MINOR fixed) | `c019546`,`76e26e1` | APPROVE (rd 2) |
| 1 | opus | DS: invert SteppedTimeline hierarchy + "TODAY" label + flat glass-key (`glassKey`/`glassChipFlat`); fixtures "58d" | `0435129` | PASS |
| 2 | sonnet | HomeModels (24 Codables) + DashboardStats additive + APIClient endpoints + 4 protocols; **review caught a real `Reweight.focusDimension` null-decode crash** | `5f7bfa5`,`0157c7b` | PASS after fix |
| 4 | sonnet | Timeline detail (7b) + passed-deadline prompt; **review caught 3 copy-fidelity defects** (before-BCG / zero-pad dates / PUSH short-form) | `f78db05`,`30d87cd` | PASS after fixes |
| 3 | sonnet | Home phone (3a) + HomeViewModel + Home NavigationStack mount; extract `spellOut`→NumberWords; AppRouter `.timelineDetail`→homePath | `80f3d36` | PASS |
| 5 | sonnet | Tablet Home (2a) two-column + dark LAST-NIGHT strip + iPad header + `h1TabSmall` | `d4edfd6` | PASS |
| Final | opus | Whole-branch adversarial review → APPROVE; fix batch (minor e) | `7ed0c4e` | APPROVE |

Two implementer subagents (T3, T5) stopped before finalizing (background-wait); the lead
completed each: fixed a canvas-fiction test assertion (T3), cleared an orphaned/wedged
xcodebuild + reset the sim (T5), ran suites, captured shots, committed.

## API consumed (all GET cookie-auth; POST/DELETE same-origin native)
`/api/v1/dashboard` (B4 recommendations[key `title`]+dimension_averages, B7 diagnostic+
timeline) · `/api/v1/timeline`, `/timeline/firms`, POST `/timeline/firms`, DELETE
`/timeline/firms/{id}`, POST `/timeline/firms/{id}/result` (offer/no_offer→reweight/
waiting/didnt_interview) · `/api/v1/recommendations?exclude=` (Swap) · `/api/v1/drills/
gauntlet` (streak+slots) · `/api/v1/drills/boards?scope=group` (cohort footer) ·
`/api/v1/sessions?scope=recent` (tablet LAST-NIGHT).

## Interfaces delivered (later FE phases may consume)
- `Networking/HomeModels.swift`: `Recommendation, DimensionAverage, DiagnosticStats,
  DimensionScore, DiagnosticTrend, DashboardTimeline, NextDeadline, TimelineDetail,
  TimelineReadiness, TimelineFirmDetail, FirmDeadline, FirmPrompt, FirmCatalogEntry,
  FirmResult, Reweight, Gauntlet, GauntletSlot, GauntletResult, GauntletGroup,
  WeakSection, GroupBoard, GroupRef, BoardEntry` (all `Codable, Equatable`; snake→camel
  auto). `DashboardStats` gained optionals `dimensionAverages/recommendations/diagnostic/
  timeline` (legacy payload still decodes).
- `APIClient`: `timeline(), timelineFirms(), trackFirm(firmId:), untrackFirm(firmId:),
  firmResult(firmId:outcome:), recommendations(exclude:), gauntlet(), groupBoard()` +
  protocols `TimelineService/RecommendationService/GauntletService/BoardService/
  RecentSessionsService`.
- Views/VMs: `HomeView` (size-class adaptive), `HomeViewModel`, `TimelineDetailView`,
  `TimelineDetailViewModel`. `Shared/NumberWords.swift` (`spellOut(_:)` 0–99).
- DesignSystem (F0-layer additions): `GlassKind.key` + `View.glassKey(cornerRadius:)` +
  `View.glassChipFlat()`; `DSTextStyle.h1TabSmall/actionLabel/timelineFirmKicker/
  timelineDays/timelineTag/timelineTodayLabel`; `SteppedTimeline` now renders the
  canvas-pixel-truth hierarchy (firm·date kicker → "58d" hero + tag) + "TODAY" label.
- Routing: `AppRoute.timelineDetail` wired (`AppRouter.go` selects `.home` + appends to
  `homePath`; RootShell `.home` mounts `NavigationStack(path:homePath)` +
  `navigationDestination`). RootShell iPad top-row shows date+greeting for `.home`.

## Deviations (documented; reviewer-confirmed correct reads)
1. Phone 3a tonight strip is the LIGHT elevated card (canvas pixel-truth; DD §2 prose
   says "dark") — uses `DSPalette.dark.muted/.green` tokens on a light surface. **Owner-
   gate at demo.**
2. Tablet LAST-NIGHT strip: "recap rated 5/5" has NO GET source → renders "{grade} avg
   vs {other}" only. **Backend follow-up.**
3. Per-firm readiness sub-detail prose isn't in the API → tag-derived line on live
   (persona prose in previews only).
4. Hero "N drills, M minutes" — slots live (6); minutes = documented estimate (count×2).
   Rec meta = "{case_type} · {difficulty}" (provenance not in payload). Streak strip
   fills green to `streak` (canvas one-gap art is persona-specific). Cohort footer
   "6TH OF 10" = the ONE sanctioned population count (joined cohort literal rank).
5. Greeting + date kicker are LIVE (time-of-day / real weekday) — shots read "Afternoon,"
   / real date, not the canvas's fixed "Morning,"/"WEDNESDAY". `testDateKickerFormat`
   originally hardcoded the canvas's *fictional* weekday; fixed to the real one.
6. "≤3 greens" read as the §1 enumerated sanctioned uses, not a literal count.
7. Tablet shot is PORTRAIT (macOS TCC blocks programmatic landscape rotate — F0/F1
   fallback); the two-column `.regular` layout renders in either orientation.

## Follow-ups / backlog (non-blocking)
- **Backend:** expose recap star-rating on a GET (tablet LAST-NIGHT); add a set-user-
  deadline endpoint (Timeline "Set date" row is currently INERT — near-untriggered, all
  seeded firms carry a deadline).
- **F7 seam:** Home hero "Begin today's set" routes to `.drillRun` = F1's legacy P4
  single-drill sheet, NOT the 6-slot gauntlet — documented interim until F7.
- **SteppedTimeline robustness (F0-inherited, canvas-locked):** its step path is a fixed
  3–4-riser shape; with a live firm count ≠3 the labels desync from the fixed x-positions,
  and N=0 renders a ghost line with no labels. Recommend a follow-up to cap/handle empty.

## Whole-branch Opus review — VERDICT: APPROVE (0 CRITICAL / 0 IMPORTANT)
Decode-safe (every backend-nullable field optional; legacy dashboard decodes); integration
clean (F1 seams untouched beyond the sanctioned Home-stack mount + iPad header); copy
verbatim vs canvases 3a/7b/2a; exactly one glass hero per screen; zero hex outside
Tokens.swift; DEBUG hatches all `#if DEBUG` + NeverCalled-guarded (Release-inert); VM tests
real (cohort matched by user id, all 4 firm-result outcomes + null focus + legacy dashboard).
Fix batch applied minor (e): small underlined action labels (Details/Re-read/Add a firm/
Retry) bumped `.meta` 400 → `.actionLabel` 600 (canvas-faithful). Banked minors (a)-(d)
left with rationale (F0-inherited / canvas-matches-over-plan / non-issue).

## THOMAS MANUAL
None blocking. Visual owner-gates for the FW3 demo: the light-vs-"dark" tonight strip
(deviation #1) and the secondary-label weight. On-device run needs your signing (ship).
The FW3 (F2/F4) demo build ships to your 15 Pro on request.

## ESCALATIONS
None. No Fable/`deep` consult used or required; no BLOCKED states. (One sim-wedge on the
Live Activity test during Task 3/5 was cleared by an orchestrator sim reboot + mic re-grant;
suites then ran clean.)
