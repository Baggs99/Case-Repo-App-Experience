# F4 — Library · Phase Report

**Status:** DONE (with one env-gated caveat on the full-suite one-shot — see Suite counts)
**Branch:** `fe/f4-library` · **Head:** `5bf293a` (branch point `72c4351` off `feature/backend-gap`)
**Worktree:** `/Users/thomaskgould/dev/fe-f4` · **DB:** `caserepo_fe_f4`
**Date:** 2026-07-17 · Plan: `docs/superpowers/plans/2026-07-17-fe-f4-plan.md` · Ledger: `.superpowers/sdd/f4/progress.md`

Rebuilt the LIBRARY tab as a casebook-row browser + case detail bound to the pinned `/api/v1/cases*`
B3 contract (`avg_rating`/`run_count`/`done_for_you` + `open_count`/`done_count`), implementing the
retired-done rules (Decisions §0.4): type chips + Everything/Not done/Done toggles + "N OPEN · N DONE"
live count; open rows first, retired rows greyed below a "DONE — YOURS TO INTERVIEW WITH" divider;
detail flips the CTA to "Case someone with this" with a faint "Get re-cased anyway · won't count
toward diagnostics". Phone (canvas 5a) is a NavigationStack list → pushed detail (chrome-suppressed);
iPad (canvas 2c) is a 1fr|470 master–detail with an always-visible detail pane. The legacy
system-List/SF-Symbol Cases screen is fully replaced with F0-token styling.

## Tasks (each: fresh Sonnet implementer → fresh Opus reviewer, fix loops)

| Task | Scope | Commit range | Review |
|---|---|---|---|
| Plan | Plan + 2 Opus review rounds (4 Important + minors r1; stale-deletion strike r2) | `8405d39..3e8e302` | APPROVE (r2) |
| 1 | Networking: `CaseSummary`/`CaseDetail` aggregates + `LibraryPage` + `APIClient.library()` + decoding tests | `3e8e302..315b279` | APPROVE (A+B) |
| 2 | `LibraryViewModel` + `LibraryService` + `LibraryCase` mapping + retired-done partition/count | `315b279..2415dd1` | APPROVE (A+B) |
| 3 | Phone Library list (5a) + `NavigationStack(libraryPath)` + `RootShell` detail-chrome gate + DEBUG fixtures | `9d8885e..789e2fd` | APPROVE (A+B) |
| 4 | Case detail (5a): `CaseDetailContent`(phone/tablet) + `CaseDetailView` (→`LibraryService`) + §0.4 CTA | `6aec73c` (+ fix `01ebe73`) | (A) APPROVE, (B) fixed→clean |
| 5 | Tablet master–detail (2c): `LibraryMasterDetailView` + history attach | `dacae17` | APPROVE (A+B) |
| Polish | grep-clean hex comments + tablet pane width (Task 3/5 minors) + loading/error states (final finding) | `4d5f5e8`, `5bf293a` | — |
| Final | Whole-branch Opus review — all §5-F4 + 4 screenshots + rubric verified; 1 finding fixed | — | clean |

Ledger + per-task diff packages + reports under `.superpowers/sdd/f4/`. Screenshots under
`.superpowers/sdd/f4/shots/` (task3-phone-list, task4-phone-detail-open, task4-phone-detail-done,
task5-tablet) — each reviewer-compared to its canvas anchor.

## Suite counts

| | Result |
|---|---|
| Backend (bootstrap) | 655 passed (unchanged — iOS-only phase) |
| iOS baseline | 313 passed / 0 failures |
| iOS after F4 (full suite **excluding** the pre-existing `SessionViewModelTests` class) | **329 passed / 0 failures** |
| F4 focused (LibraryViewModelTests 25 + LibraryDecodingTests 5 + CaseDetailContentTests 15) | 45/45 green |

**Env caveat (not an F4 defect):** a clean one-shot of the *entire* iOS suite could not be captured
this session because ≥2 tests in the **pre-existing** `SessionViewModelTests` class (mic/recorder:
`testEnteringLiveStartsLiveActivityForInterviewer` + a Finalize-region test) HANG on the simulator
mic-permission TCC under **Xcode 27 beta**, even after a sim reboot + the F0-documented
`simctl privacy … grant microphone` — and the FW3-sibling **F2** phase thrashed the 16 GB machine
(>2 concurrent xcodebuild+sim stacks, load avg 9.9→119) for ~2.5 h. F4 touches **zero** session code;
the 329/0 run proves every non-Session test (incl. all F4 tests) passes with no regression. Once the
machine is quiet and the mic grant sticks, the full suite should return to its bootstrap-green state.
**Recommendation for the orchestrator / F5 (owns session code):** investigate the Xcode-27-beta mic
TCC regression on these Live-Activity/recorder tests before the next iOS merge.

## Interfaces delivered (later phases / F3 consume)

- `LibraryService` protocol (`ios/CaseRoom/State/LibraryViewModel.swift`): `library(query:) ->
  LibraryPage`, `caseDetail(id:) -> CaseDetail`, `recentSessions() -> [SessionSummary]`; `APIClient`
  conforms. (The old `CasesService`/`CasesViewModel` is RETAINED — still used by `PairCreateView` +
  `ProposeNowView` case pickers; the two protocols coexist.)
- `struct LibraryPage { cases:[CaseSummary]; total:Int; openCount:Int; doneCount:Int }`;
  `CaseSummary`/`CaseDetail` gained `avgRating:Double?`, `runCount:Int?`, `doneForYou:Bool?`
  (optional, nil-coalesced at use: runCount→0, doneForYou→false).
- `LibraryViewModel` (`@Observable`): `type:LibraryType`, `done:LibraryDone`, `filteredRows:[LibraryRow]`
  (`.row`/`.divider`), `countLine` (client-filtered), `selectedID`/`selectedCase`/`selectedCaseWithHistory`,
  `isLoading`/`errorMessage`. `LibraryCase` view type (ordinal/kicker/detailMeta/history/pdfLabel).
- Navigation: F4 mounts the library `NavigationStack(path: AppRouter.shared.libraryPath)` and consumes
  `.caseDetail(Int)` (no new `AppRoute` cases). **RootShell touch (F1-deferred seam):** a minimal
  additive `libraryDetailOpen` gate suppresses the top pills + tab bar when Library has a pushed detail
  (canvas 5a detail = back + tag only). Other tabs unaffected.

## Design decisions / accepted deviations & seams

- **Row "FOR YOU"/"SCHEDULED" + detail "RECOMMENDED FOR YOU"** need B4 recs + upcoming-sessions
  cross-reference (absent from `/api/v1/cases*`) → **live omits them**; the DEBUG fixture carries them
  so screenshots match canvas. The pushed phone detail loads via `caseDetail(id)` (no decoration) so a
  recommended case's phone-detail shows "OPEN FOR YOU" (= correct live behavior); the tablet pane uses
  the decorated `selectedCase` so it shows the green "RECOMMENDED FOR YOU" (visible in task5-tablet).
- **Detail CTA + "Get re-cased anyway"** route to `.caseTab` as an **interim seam** — F3 owns the
  "case pre-filled" open flow; no new `AppRoute` added this phase.
- **Type-chip filter** passes the case's full-string `case_type` to the API (exact server match).
  "Market Entry"/"Profitability"/"M&A" are confirmed canonical; **"Market Sizing" is unverified** and
  may under-match live compound values (e.g. "Market Sizing / Optimization") — graceful (empty set),
  documented; a normalized `case_type` facet would harden the Sizing chip.
- **"YOUR HISTORY WITH IT"** joins `recentSessions()` by `case_title` (no `case_id` on session rows) —
  best-effort; a per-case history / `case_id` on the session payload would make it exact.
- **Row meta = `D<Int(difficulty_score)>`** (the `~25 min` duration is not in `/api/v1/cases`).
- **iPad screenshot is portrait** — landscape rotate is the F0/F1-documented macOS TCC block; the
  master–detail is size-class `.regular`-driven so it renders identically.
- **DEBUG hatches** (`#if DEBUG`, Release-inert): `-LibraryFixtures` (fake-auth + stub `LibraryService`,
  no dev server) + `-startCaseDetail <id>` — screenshot-only; no persona data reaches the live path.
- Loading/error states are **undesigned** (Decisions §6) — added minimal token-styled `ProgressView`
  (loading) + serif error line, distinct from the "Nothing here under these filters." empty state.

## DEFERRED
- Rec/scheduled decorations on live rows/detail (needs B4 + upcoming cross-ref).
- Case-prefill on the detail CTA (F3's "Get cased now" flow).
- Exact per-case user history (needs `case_id` on session payloads).
- Hardened Sizing-chip filter vs the live compound `case_type` vocabulary.

## ESCALATIONS
- **Xcode-27-beta mic-TCC hang** on `SessionViewModelTests` Live-Activity/recorder tests (pre-existing,
  not F4) blocked a full-suite one-shot; needs investigation before the next iOS merge (owner = F5 /
  the session-code phase). No Fable/`deep` consult used.

## Notes for the orchestrator (before merging)
- Shared-file touches (additive): `RootShell.swift` (chrome gate + library NavigationStack mount —
  the F1-deferred seam), `CaseRoomApp.swift` (DEBUG hatches), `Models.swift`/`APIClient.swift` (cases
  aggregates + `library()`), `CasesListView.swift`/`CaseDetailView.swift` (rewrites). Incidental honest
  arg-adds to `CasesViewModelTests.swift`/`IntentsTests.swift` (new optional CaseSummary fields; no
  assertion weakened). `CasesViewModel.swift` intentionally NOT deleted. `.gitignore` adds `ios/build/`.
- No backend files changed. No `xcodeproj` hand-edits (regenerated via `xcodegen`, `.xcodeproj`
  gitignored per repo convention). No dev server left running.
