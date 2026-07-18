# F7 — Drills · Phase Report

**Status:** DONE · **Branch:** `fe/f7-drills` · **Base:** `d471fa7` (post-FW3: F0/F1/F2/F4 merged)
**iOS suite:** 413 → **458** green (0 failures) · +45 tests · **Backend suite:** **655** green — F7 touched
ZERO backend (`git diff --name-only d471fa7..HEAD` = exclusively `ios/` + `docs/` + `.superpowers/`).
**Date:** 2026-07-17 · Plan: `docs/superpowers/plans/2026-07-17-fe-f7-plan.md` · Ledger:
`.superpowers/sdd/f7/progress.md` · Shots: `.superpowers/sdd/f7/shots/`

The DRILLS tab + the gauntlet run experience (canvas 5b phone / 2b tablet), bound live to the merged
B8 gauntlet/boards/trends API, on F0's design system + F1's shell/router, reusing F2's gauntlet/board
Codables. The P4 Foundation-Models on-device drill path is untouched and preserved as the weak-section
practice bridge.

---

## Tasks (each: fresh implementer → diff package → fresh Opus reviewer → fix→re-review)

| Task | Model | Scope | Commits | Review |
|---|---|---|---|---|
| Plan | opus | Plan + Opus plan-review (APPROVE-WITH-FIXES → 7 items fixed) | `f8d087f`,`96296b0` | APPROVE |
| 1 | sonnet | Networking: gauntlet-submit POST (+409→alreadySubmitted), boards school/global/schools, trends Codables + APIClient + `AppRoute.gauntletRun` route/flag | `9a8b940` | SPEC PASS / CODE PASS |
| 2 | sonnet | Drills hub (5b): gauntlet glass hero (six-types grid, DAY N, begin/see-result), 16-bar 4-week trend, C-14 board; replaced DrillsTabStub | `4bc593c`,`f12bd6f` | PASS (kicker-wrap Imp + 3 Min fixed) |
| 3 | sonnet | Scoped boards C-14/WHARTON/GLOBAL/SCHOOLS (chips + per-scope layouts, percentile-not-headcount) | `cbd1978` | SPEC PASS / CODE PASS (2 Min banked) |
| 4 | **opus** | **JUDGMENT** — gauntlet run loop (real clock, progress, keypad+sign / choice grid, per-slot durationMs, abandon, 409 recovery) + percentile result (mark draw, stats, weak-CTA→`.drillRun`) + rewire Begin→`.gauntletRun` | `ad01e82` | SPEC PASS / CODE PASS (3 Min banked) |
| 5 | sonnet | Tablet 2b two-column hub (hero+72px-bar trend \| board); run stays phone habit | `8b1177b` | SPEC PASS / CODE PASS (1 Min) |
| Final | opus | Whole-branch adversarial review → APPROVE-WITH-FIXES (0 Crit, 2 Imp) | `1693d94` (fix) | re-review CLEAN |

Three implementer subagents stopped before finalizing (background-wait on xcodebuild — the known
stranded-lead failure mode); the lead recovered each in-turn: polled the backgrounded build to completion,
verified the suite, captured the screenshots (clean-build to an explicit `-derivedDataPath` to dodge stale
DerivedData; sim shutdown+boot to clear a stuck mic-TCC dialog), and committed. The opus Task-4 implementer
ran synchronously and did not strand.

## API consumed (all GET cookie-auth; POST same-origin native)
`/api/v1/drills/gauntlet` (Gauntlet: slots+streak+submitted+embedded result) · POST
`/api/v1/drills/gauntlet/attempts` (submit → GauntletResult; **409 already_submitted** → recover by re-fetch)
· `/api/v1/drills/boards?scope=group|school|global|schools` · `/api/v1/drills/trends`. The legacy
`/api/v1/drills/daily|templates|attempts` (P4/FM path) are untouched.

## Interfaces delivered (later phases may consume)
- `Networking/HomeModels.swift` (+): `SchoolCard, SchoolBoard, GlobalBoard, SchoolsBoard, GauntletAttempt,
  TrendPoint, TrendByType, GauntletTrends` (all Codable/Equatable; snake→camel). Reused F2's
  `Gauntlet/GauntletSlot/GauntletResult/GauntletGroup/WeakSection/GroupBoard/GroupRef/BoardEntry`.
- `APIClient` (+): `submitGauntlet(_:) -> GauntletResult` (409→`GauntletError.alreadySubmitted`),
  `schoolBoard()/globalBoard()/schoolsBoard()`, `trends()`. `GauntletService`/`BoardService` extended.
- Views/VMs: `DrillsView` (size-class adaptive hub), `DrillsViewModel`, `GauntletBoard`, `GauntletRunView`,
  `GauntletRunViewModel` (run→submit→result state machine), `DesignSystem/GauntletKeypad` (glass numeric
  keypad + sign toggle, reproduces P4 signed-Double semantics — tabular).
- Routing: `AppRoute.gauntletRun` (§6 contract addition, orchestrator-blessed — in-app only, no external
  entry point) + `AppRouter.gauntletRun` flag + `.gauntletResult` seam (opens result directly from a stored
  gauntlet.result — B8 one-per-day blocks a true re-run). RootShell `.gauntletRun` fullScreenCover.
  HomeView "Begin today's set" rewired `.drillRun`→`.gauntletRun`.

## FM invariant (P4) — PRESERVED
`git diff --stat d471fa7..HEAD -- ios/CaseRoom/Drills/` is **EMPTY**: zero changes to
FoundationModelDrillEngine / DrillDressing / LocalDrillGenerator / DrillGrader / DrillEngineProvider or the
FM validation contract. The gauntlet is SERVER-scored (prompts arrive rendered + answer-redacted; the
client submits value/choiceIndex and the server re-scores). The on-device FM path lives only in the legacy
practice `DrillView` reached via `.drillRun`, which is unchanged and is the weak-section result CTA target
("Practice {weak} — 3 focused drills" → `.drillRun`).

## Design-fidelity (the tabular-numeral poster-child phase)
Every timer / score / percentile / points / rank / keypad digit is `.tabularNumbers()`. ≤3 greens on every
screen (hub/result verified in shots). Copy verbatim from canvas 5b/2b. Tokens only — zero `#` hex /
`Color(red:` in code (one `#A9B4C4` appears in a GauntletBoard.swift *comment* only). Square content
corners; underline secondaries; one glass hero per screen. Percentile-not-headcount (delta §0.2): no
count/"of N" anywhere — the C-14 literal cohort rank+points are the ONE sanctioned exception. Evidence:
`task2-hub.png`, `task3-board-{c14,wharton,global,schools}.png`, `task4-{run-numeric,run-choice,result}.png`,
`task5-tablet.png` — each reviewer-compared to its canvas anchor.

## Deviations (documented; reviewer-confirmed reads)
1. **Boards WHARTON/GLOBAL show YOUR standing** (school card + your percentile / your percentile only) vs
   the canvas's aspirational per-member percentile lists — because B8's `school`/`global` scopes return your
   percentile ONLY, no member list (per bgap-b8-report). Percentile-not-headcount fully honored. **Backend
   follow-up:** expose per-member percentile rows for school/global if those lists are wanted.
2. **Trend kicker `TREND — DAILY PERCENTILE, 4 WEEKS` renders over score-derived bars** — B8's `/trends`
   exposes daily `score` (0–6), NOT a daily-percentile series. Bars = score/6; the "— {pctl}" week suffix
   uses the submitted gauntlet's `dailyPercentile`. **Owner-gate at demo** (keep the wording?) + **backend
   follow-up** (add a daily-percentile series). 
3. **Six-types grid** uses the canvas's fixed six labels (design identity), not the live 3-type×2 slot set
   (a B8 seams-only artifact).
4. **No true re-run** (B8 one-per-day 409) — the submitted hero button is "See today's result" (opens the
   stored result). One caveat: that re-view path omits the "· MM:SS" elapsed segment because `GauntletResult`
   carries no elapsed field (**backend follow-up**).
5. **Run/result derived copy** — the result serif line, cold-start percentile (`—`), and elapsed copy are
   composed from persona §3 + the pinned API (the mobile-DC JS logic is in the truncated canvas tail).
   **Owner-gate at demo.**
6. **Tablet shot is PORTRAIT** (macOS TCC blocks programmatic landscape rotate — F2/F4 precedent); the
   two-column `.regular` grid renders in either orientation.

## Whole-branch Opus review — APPROVE-WITH-FIXES → CLEAN
0 Critical. 2 Important (both non-crashing failure-path dead-ends), both FIXED in `1693d94` with 4 covering
tests, re-reviewed CLEAN:
- **I1:** the hub gated the whole screen on `gauntlet == nil` → any `load()` failure (offline / a single
  flaky endpoint) stuck it on "Loading…" forever with the Retry unreachable. Fixed: the `gauntlet == nil`
  branch now renders `errorBanner(errorMessage)` (with Retry → `load()`) when an error is set.
- **I2:** `boardErrorMessage` was set on a scope-fetch failure but rendered nowhere → a network error showed
  "No school on file." (WHARTON) / "—" (GLOBAL) / empty list (SCHOOLS). Fixed: `GauntletBoard` now renders a
  `boardErrorRow` ("Couldn't load board." + Retry → `selectBoard(boardScope)`) on `boardErrorMessage != nil`.
Contract/decode safety verified airtight (every B8-nullable field optional, zero force-unwraps, nil/empty/
cold-start degrade gracefully); FM invariant confirmed empty-diff; reject-list clean; 409 recovery, routing
seams (F1 widgets/App-Intents/deep-links/`.drillRun` untouched), and DEBUG hatches (`#if DEBUG`, Release-inert)
all sound.

## Banked Minors (non-blocking, for backlog)
- `ordinal(_:)` duplicated in DrillsViewModel + GauntletRunViewModel (both correct across 11–13/21; DRY only).
- `#A9B4C4` in a GauntletBoard.swift comment (token reference in prose, not a color literal).
- ⌫ keypad key is a Unicode text glyph U+232B (sanctioned keypad carve-out, not an SF Symbol icon-set).
- Cold-start nil percentile → "—"; score-0 → "0TH TODAY" (owner-gate at demo).
- Tablet inner-column spacing 22 vs HomeView's 14 (cosmetic, defensible).
- GauntletNetworkingTests decoder omits the client's `dateDecodingStrategy` (inert — no Date fields).
- `weekLabels` can render `W-1`/`W0` at the Jan year boundary (out of the demo window).
- I1 hardening (optional): assign partial load successes so one flaky endpoint doesn't blank the whole hub
  (the shipped fix makes the failure recoverable via Retry, which is sufficient).

## THOMAS MANUAL
None blocking. Visual owner-gates for the FW4 demo: (a) the trend "DAILY PERCENTILE" wording over
score-derived bars (deviation #2); (b) the derived result serif line + cold-start percentile copy
(deviation #5). Backend follow-ups queued (non-blocking): per-member school/global percentile rows;
a daily-percentile trend series; an elapsed field on the gauntlet result. On-device run needs your signing
(ship). The FM on-device drill path is provably untouched.

## ESCALATIONS
None. No Fable/`deep` consult used or required; no BLOCKED states. (Three implementer subagents stranded on
background xcodebuild waits; the lead recovered each in-turn per the plan's process rule. Two stuck sim
mic-TCC dialogs cleared by shutdown+boot+re-grant.)
