# F4 Task 4 — Case detail (canvas 5a detail) · Report

Status: DONE_WITH_CONCERNS (code complete + compiles; screenshots + focused-test green GATED on the
environmental blocker — see below). Implementer stranded on a thrash-wedged background test; phase
lead verified compile + copy/rubric and committed.

## Files (commit 6aec73c)
- ios/CaseRoom/Views/CaseDetailContent.swift (new) — shared detail body,
  `CaseDetailContent(layout: .phone/.tablet, libraryCase:)`. Tag (RECOMMENDED FOR YOU green / OPEN
  FOR YOU / DONE — RETIRED FOR YOU faint), kicker, title (24 phone/22 tablet), detailMeta (" · rated
  by N candidates"), rating row (26/24, tabular) + "AVG RATING · N SESSIONS", YOUR HISTORY WITH IT
  (line/score or "You haven't run this one."), THE CASE PACK (striped thumb, pdfLabel, sub differs by
  layout — "— interviewer side" phone only, ShareLink Preview), "It knows." aside (phone only),
  primary ink-capsule CTA ("Get cased on this" / "Case someone with this"), serif note (open/done
  copy), done-only "Get re-cased anyway" + faint "won't count toward diagnostics". CTA + re-cased →
  `AppRouter.shared.go(to: .caseTab)` (F4→F3 interim seam; no new AppRoute).
- ios/CaseRoom/Views/CaseDetailView.swift (rewrite) — migrated OFF old CasesService ONTO
  LibraryService; plain ink "‹ Library" back (no glass/underline) + detail tag; loads caseDetail +
  title-matches recentSessions() for history; hosts CaseDetailContent(.phone). All legacy SF
  Symbols/Label(systemImage:)/Color("BrandAccent") removed.
- ios/CaseRoom/App/CaseRoomApp.swift — `-startCaseDetail <id>` DEBUG hatch (push .caseDetail after
  fake-auth) for detail screenshots.
- ios/CaseRoomTests/CaseDetailContentTests.swift (new) — derivation tests (tag/CTA/note flip by
  done+recommended; detailMeta; history title-match line/score + nil case; layout-driven pack sub +
  "It knows." presence).

## PLAN CORRECTION (deviation, deliberate)
Plan Task 4 said delete `CasesViewModel.swift` as "the last CasesService reference." FALSE — grep
shows `PairCreateView.swift` + `ProposeNowView.swift` (P1 case-picker sheets) + `CasesViewModelTests`
still use `CasesViewModel`/`CasesService`. Deleting it breaks the build and is out of F4 scope (those
are F3-adjacent surfaces). **KEPT `CasesViewModel.swift`.** The old `CasesService` (cases/caseDetail)
coexists with the new `LibraryService` — no harm; `CaseDetailView` no longer uses the old one.

## Verification
- COMPILE: `build-for-testing` → **TEST BUILD SUCCEEDED** (CaseDetailContent + CaseDetailView +
  CaseDetailContentTests all compile).
- Rubric grep (detail files): NO hex literals / Color(red:) / Color("BrandAccent"); NO SF Symbols
  (the `Label(` grep hits are a custom `DetailTagLabel` view, not `Label(systemImage:)`).
- Verbatim copy present (grep-confirmed): "Get cased on this", "Case someone with this", "Get
  re-cased anyway", "won't count toward diagnostics", "It knows.", "You haven't run this one.",
  "AVG RATING", "YOUR HISTORY WITH IT", "THE CASE PACK", "OPEN FOR YOU", "DONE — RETIRED FOR YOU",
  "RECOMMENDED FOR YOU", "— interviewer side", "Opens the Case tab with this case pre-filled",
  "Done cases join your interviewer deck …".

## ENVIRONMENTAL GATE (carried to final review)
- Screenshots (task4-phone-detail-open.png id=8 open+rec, task4-phone-detail-done.png id=7
  done+history) NOT yet captured: `simctl install`/`launch`/`io` all wedge under SEVERE memory thrash
  from the concurrent FW3-sibling F2 phase (continuous xcodebuild+sim ~2+ hrs; 15-min load avg hit
  9.9). `-startCaseDetail`/-LibraryFixtures wiring is in place and verified by code.
- Focused Library/detail tests wedge at package-resolution setup under the same thrash (2 attempts →
  watchdog). Earlier isolated run proved the pattern (25 Library tests, 0.026s). CaseDetailContentTests
  compile.
- BOTH captured as the phase gate: run the 3 detail screenshots + full-suite green (re-grant sim mic
  TCC) in ONE quiet batch once F2's wave completes, before the final report.

## Deviations / seams
- Detail CTA + re-cased → Case tab is an interim seam (F3 owns case-prefill).
- "Your history" joins recentSessions() by case_title (no case_id on session rows) — best-effort.
- CaseDetailContent(layout:.tablet) present but exercised only by Task 5.
