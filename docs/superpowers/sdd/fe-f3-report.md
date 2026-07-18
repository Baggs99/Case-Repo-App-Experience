# F3 — Case tab · Phase Report

Branch `fe/f3-case` (cut at 9cff198). Status: **DONE — APPROVED FOR MERGE.**
Suites: iOS **581/0** (baseline 500 + 81 new), backend **655/0** (unchanged — F3 is
FE-only). xcodegen idempotent; xcodeproj stays gitignored/regenerable (repo
convention). Canon: Decisions §1/§2-3b (CANON)/§5/§7-1b (CANON); contracts bgap-
b1/b2/b3/b4. Reports override briefs.

## What shipped

The Case tab is rebuilt from the legacy `SessionsView()` into the canvas-3b "calm
spine" (phone) + Tablet-1b "tray hero + two-column spine" (iPad), with three glass
sheets and full recap-gate handling. 6 tasks, each individually reviewed + a
whole-branch adversarial pass.

- **T1 data layer** — `Proposal` gains optional `caseId`/`caseTitle` + `direction`/
  `state`/`claimToken`/`counterTimes`/`counterBy`/`counteredAt` (explicit defaulted
  init); `AcceptedSession.sessionUrl`/`icsUrl` optional; `PairToken.shortCode`;
  `RecapItem`; `ClaimResult`; `CaseGateError.blockedByRecap(Int)`. `CaseTabViewModel`
  + `CaseTabService`. `CaseFixtures`.
- **T2 phone spine (3b)** — glass verb bar (filled "Get cased now" + underline "Case
  someone"/"Schedule"), glass recap-gate card → `.recap`, NEXT UP + Swap (green
  BlinkDot + countdown), UPCOMING (hollow-ring dot + T-xH countdown + add-to-calendar),
  PENDING (Accept/New time/Decline) + sent "awaiting reply", HISTORY.
- **T3/T4/T5 glass sheets** — Get-cased-now (real CIQRCodeGenerator QR + inline code +
  LIVE-NOW Ping board), Case-someone (Scan-their-QR + open invites + interviewer log +
  "never gated" note), Schedule composer (WHO/WHEN/CASE chips + Send + serif rule).
- **T6 tablet (1b)** — glass tray hero + two-column spine, size-class-branched, reusing
  the phone subviews + the shared sheet seam; July-17 fixtures.

## Interfaces delivered (later phases / merge consume)

- **`AppRoute` / router:** F3 mounts the Case tab as
  `NavigationStack(path: $router.casePath)` with a `.recap(id)` destination →
  **`RecapGateStub`** (`Views/RecapGateStub.swift`, `// MARK: F3 INTERIM — F5 replaces`).
  `AppRouter` gained 3 additive router-state fields (`// MARK: F3`):
  `caseSomeonePrefillCaseID`, `caseSomeonePrefillTitle`, `caseGetCasedPrefillCaseID`.
  `AppRouter.go(.recap)` steering is UNTOUCHED (F5 owns it).
- **APIClient (new, `// MARK: F3`):** `recaps() -> [RecapItem]`,
  `counterProposal(id:times:)`, `claimProposal(token:) -> ClaimResult`,
  `pairCreate(caseId: Int?)` (non-breaking sibling of the `Int` version),
  `pairClaim(shortCode:) -> Int`, `createNowInvite(toUserId:)`,
  `sendScheduledProposal(toUserId:caseId:Int?:fromRole:proposedTimes:)`. Gate
  (`allowRecapGate:true`) on `acceptProposal`/`claimProposal`/`pairClaim(token:)`/
  `pairClaim(shortCode:)` ONLY. `createProposal` UNCHANGED (ProposeNowView).
- **`CaseGateError.blockedByRecap(Int)`** + `decodeRecapGate(status:data:)` — parses
  `{"detail":{"blocked_by_recap":id}}` @ 409. The shared gate → `.recap(id)` pattern.
- **`CaseSheet` enum seam** (`.getCased/.caseSomeone/.schedule`) + `.sheet(item:)` — the
  stable presentation seam (phone verb bar + tablet verb column).
- **QR payload PINNED:** `caseroom://pair?code=<short_code>` — T3 encodes, T4 parses +
  claims via `short_code`.

## Design decisions / accepted deviations & seams

- **F4→F3 case-prefill seam (delivered).** `CaseDetailContent` CTA now sets a router
  prefill before `go(.caseTab)`: done case → Case-someone sheet (+title); open/re-cased
  → Get-cased-now sheet (case-scoped). `CaseTabView.consumePrefill` captures context into
  `@State` before clearing the router fields (no `.sheet(item:)` rebuild race, no loop).
- **Recap-gate card = glass hero (26px)** per canvas 3b line 1544 (overrode an early
  plan disposition that guessed "flat"). Verb bar re-scoped as glass CHROME bar; the two
  sanctioned filled buttons (verb primary + "Read the recap") preserved.
- **HISTORY = `sessions(scope:"recent")`** — backend supports `upcoming|recent` only
  (NOT "past"). NEXT UP binds the soonest scheduled session + Swap (brief "NEXT UP w/
  Swap"), not a recommendation card (VM has no rec entity) — inherited on tablet.
- **`go(.recap)` deep-link/push steering DEFERRED to F5** (hard boundary: no App
  Intents/deep-link touch). F3 wires only its own entry points (VM gate + card tap) to
  `casePath`.
- **Data gaps handled gracefully (live omits, fixtures carry for canvas fidelity):**
  live `availability`/`FreeUser` has no `school` → the "· school" segment omitted live
  (fixture-only continuity); interviewer-log "avg feedback quality" has no API metric →
  live shows "N cased this month" only. Documented in-code.
- **Additive-copy deviations** (canvas predates the seam): Case-someone "Using this
  case: <title>" prefill line (prefill path only); manual short-code entry copy (sim/
  denied-camera fallback). Countered-SENT proposals show "awaiting reply" only (no
  accept-the-counter from the Case tab) — matches canon 3b.
- **QR is true-black** (CIQRCodeGenerator) for scan contrast, not `palette.ink`.
- **Tablet shot is portrait** — landscape rotate is the F0/F1/F4-documented macOS TCC
  block; the layout is size-class `.regular`-driven so it renders identically.
- **Swap** is a cosmetic toast this phase (real swap-roles endpoint is F5's B3 flow).

## DEFERRED (non-blocking)

- **Orphan cleanup (whole-branch M1):** the legacy `SessionsView`/`PairScanView`/
  `PairCreateView`/`PairViewModel` are no longer mounted (`.caseTab` → `CaseTabView`);
  `pairClaim(token:)` + `claimProposal(token:)` now have no live consumer.
  `PairViewModel.claim` lacks a gate catch — NOT a live dead-end (unreachable), but a
  future re-wire should add the catch or the orphans should be deleted. Left in place to
  keep F3's scope clean (ProposeNowView + CasesService are still live per F4).
- **T3 code presentation (M2):** the 6-char code renders inline in the serif line per
  canvas sheetNow3 ("Code K7Q-4TN works too."), not a separately grouped tabular block
  — canvas-faithful; a grouped/tabular treatment would deviate from pixel-truth.
- **Live `.pickTime` on shorter devices** — the schedule sheet body is now a ScrollView
  (fixed at close-out), so the expanded DatePicker no longer clips.
- Recap-gate card lede binds `caseTitle` (RecapItem has no feedback-quote field).

## ESCALATIONS / OWNER-GATE (Thomas)

- **T5 CASE segmented control (whole-branch M3, VISUAL JUDGMENT):** the selected
  "Interviewer decides" option renders as a rounded (radius-999) glass row with a
  selected border, matching canvas sheetLater3's `border-radius:999px` CASE options —
  but it brushes §5's "never outlined box" rule for a SELECTION control. Per standing
  practice (visual judgment = owner gate) this is not self-certified: eyeball the CASE
  segment on `t5-schedule.png`; reshape if it reads wrong.
- Demo checkpoint: FW5 is a Thomas checkpoint (§7). On-device run needs his signing.

## Notes for the orchestrator (before merging)

- **Shared-file touches (all `// MARK: F3`-bounded):** `RootShell.swift` (caseTab
  NavigationStack + `.recap` destination + `caseTabRoot` fixture branch),
  `CaseRoomApp.swift` (`-CaseFixtures`/`-CaseSheet` DEBUG hatches + docblock),
  `APIClient.swift`/`Models.swift`/`SessionModels.swift` (F3 endpoints + model fields),
  `CaseRoomIntents.swift` (3 router prefill fields — router STATE only),
  `CaseDetailContent.swift` (prefill seam), + one-line nil-coalesce read fixes in
  `SessionsViewModel`/`SessionsView`/`CaseRoomEntities` + 2 test fixups.
- **F5 conflict at merge (expected):** F3's `.recap` destination renders the interim
  `RecapGateStub`; F5's real `RecapView` replaces it. RootShell's caseTab
  NavigationStack + `.recap` navigationDestination is the seam both touch — settle
  keep-F5's-recap-screen at merge. `AppRouter.go(.recap)` is untouched by F3 (F5 wires
  push/deep-link recap steering).
- xcodeproj is regenerated in-place (gitignored per repo convention — only
  `Package.resolved` is tracked); run `cd ios && xcodegen generate` at merge.
- Sims: iPhone 17 (942222D4) left booted; iPad Pro 11" (653F37B8) shut down at
  close-out. Dev port 8103 never needed (all screens fixture-driven).

Shots: `.superpowers/sdd/f3/shots/{t2-phone-spine,t3-getcased,t4-casesomeone,
t5-schedule,t6-tablet}.png`. Ledger: `.superpowers/sdd/f3/progress.md`.
