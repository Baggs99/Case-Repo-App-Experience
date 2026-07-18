# F5 — Session takeover + recap gate · Phase Report

**Status:** DONE · **Branch:** `fe/f5-session` · **Head:** `6f443ae` (base `9cff198`)
**iOS suite:** 500 → **587** green (0 failures) · +87 tests
**Backend suite:** **655** green (0 failures) — no backend files changed this phase (iOS-only)
**Date:** 2026-07-17/18 · Plan: `docs/superpowers/plans/2026-07-17-fe-f5-plan.md` · Ledger: `.superpowers/sdd/f5/progress.md`
**Screenshots:** `.superpowers/sdd/f5/shots/` (13 phone frames, iPhone 17 · F4)

Refit the existing session screen into the dark **session takeover** — lobby (READY/JOINED
seats) → case **negotiation** (their pick / counter-once / "THEY KEPT THEIR PICK") → dark
**LIVE** (glass clock pill, video panes when remote, CASE/EX pills w/ new-dot, exhibit
toast + table/unit-cost-bars) → light **debrief** (avg, rubric bars, serif feedback,
REQUIRED 1–5 = the recap close, Schedule-next, interviewer Swap→invite sent, Close) — and
built the **recap gate** (canvas 6b): a light report page (rubric bars + serif paragraphs +
case-pack PDF row) with a floating glass **close-out sheet** (scroll-to-end unlock at
bottom−16, RATE THIS CASE 1–5 required, thumbs, "Gate cleared."). All on the B3 session-flow
endpoints. **The transport layer (WebRTC/signaling/reveal-crypto) is byte-identical.**

---

## Tasks (each: fresh Opus implementer → fresh Opus reviewer → fix loop)

| Task | Scope | Commit(s) | Suite | Review |
|---|---|---|---|---|
| Plan | Plan + Opus plan-review (REQUEST_CHANGES light; 5 findings folded) | `0b980db` | — | APPROVE (rd 2) |
| T1 | B3 networking layer — models + `SessionFlowService` + 409 helper | `1450d62`,`ffe3f90` | 517/0 | APPROVE (1 blocking fix: nullable `caseTitle`) |
| T2 | Lobby refit (dark) + the single `.dsTheme(.dark)` takeover seam | `8d47abd` | 523/0 | APPROVE |
| T3 | Negotiation stage (new; `negotiating` state) + "THEY KEPT THEIR PICK" | `85622a2` | 538/0 | APPROVE |
| T4 | LIVE refit (dark) — clock pill/panes/pills/toast/table+bars | `6281c09` | 544/0 | APPROVE (transport-boundary audit clean) |
| T5 | Debrief refit (light, dark→light override) + recapClose + swap | `93b108e` | 557/0 | APPROVE |
| T6 | Recap report page (light) + `.recap` presentation wiring | `2c413c8`,`88db738` | 569/0 | APPROVE (re-reviewed) |
| T7 | Recap close-out sheet (the gate) — scroll-unlock + 1–5 + close | `46f9b9c` | 583/0 | APPROVE |
| Close-out | Whole-branch adversarial review → SHIP-WITH-FOLLOWUPS; 3 fixes | `6f443ae` | **587/0** | fixes verified |

Whole-branch adversarial review: transport/boundary/contract/design/security gates ALL pass,
no crash vectors. 1 IMPORTANT + 4 MINOR; fixed #1 (candidate "lobby-flash" race), #2 (recap
409 parity in debrief), #5 (§5 rounded-outlined content card → square hairline). #3/#4
recorded as follow-ups below.

---

## Interfaces — for F6 (Interviewer consoles, shares session plumbing) + orchestrator

### Networking — `Networking/SessionFlowModels.swift` + `APIClient` (`SessionFlowService`)
```swift
negotiation(id:) -> NegotiationView            // GET /api/practice/{id}/negotiation
proposeCase(id:caseId:) -> NegotiationView      // POST .../negotiation/propose {case_id}
acceptCase(id:caseId:) -> SessionDetail         // POST .../negotiation/accept  (flips negotiating→lobby)
swap(id:) -> SwapInitiated                       // POST .../swap   (INTERVIEWER-only; 403 else)
swapAccept(id:) -> SwapAccepted                  // POST .../swap/accept  (service only — no F5 UI; see below)
recaps() -> [RecapListItem]                       // GET /api/v1/recaps  (F3 unread list consumer)
recapViewed(id:) -> RecapViewedResult             // POST .../recap/viewed
recapClose(id:caseRating:thumbs:) -> RecapCloseResult  // POST .../recap/close {case_rating,feedback_thumbs}
feedbackReport(id:) -> FeedbackReport             // GET /api/practice/{id}/feedback  (recap report source)
static APIClient.recapBlockSessionID(from:Data) -> Int?  // {detail:{blocked_by_recap:N}} — candidate SEATS only
```
`Finalized` gained optional `nextRecommendation: Recommendation?` + `prefillProposal: FinalizePrefill?`
(existing 2-arg call sites/decoding preserved). Models: `NegotiationView`, `NegotiatedCaseBrief`
(`difficulty:String?`), `RequestedCaseBrief` (distinct `{caseId,title,fromRole}`), `PickSources`
(reuses B4 `Recommendation`), `SwapInitiated`/`SwapAccepted`, `RecapListItem` (`caseTitle:String?`
— backend LEFT JOIN can null it), `FeedbackReport`/`FeedbackItem`/`FeedbackReveal`, `FinalizePrefill`.

### Takeover theming seam (F6 reuses)
`RootShell` presents `SessionView(sessionId:)` in the session `fullScreenCover` wrapped
`.dsTheme(.dark)` (single dark seam). `DebriefView` root applies `.dsTheme(.light)` to override
back to light — **verified to win over the inherited dark seam in the rendered shots.** Palette
scoping is env-based (`\.dsPalette`); glass/scrim/DSBackground/ScoreCells all re-read it.

### Session state routing — `Views/SessionView.swift`
Switch on `SessionViewModel.state` (String): `negotiating`→`NegotiationStageView`,
`scheduled`/`lobby`→`LobbyView` (dark), `live`→dark live, `debrief`/`finalized`→`DebriefView`
(light). B3 order is `negotiating → lobby → live → debrief → finalized`.

### Recap presentation — `AppRouter` (additive `// MARK: - F5`) + `RootShell`
`AppRouter.recapSessionID: Int?`; `go(to:.recap(id))` sets it + selects `.caseTab`; `RootShell`
presents `RecapReportView(sessionId:)` in a LIGHT `fullScreenCover`. The existing
`HomeView.go(to:.recap(id))` path now functions. F3's `blocked_by_recap` 409→`.recap` seat-entry
routing is F3-owned (not in this worktree) — verified reachable via HomeView + a router unit test.

### Shared component — `DesignSystem/ScoreCells.swift`
Used un-forked at three sizes: `.large` (recap 1–5, debrief 1–5), `.medium`/`.small` (live rubric).
F6's rubric cells share the same handler/component.

### SessionViewModel — additive only (public API + `handle(_ SignalMessage)` intact)
Added `caseId`, `interviewerId`, `negotiationTick` (bumped inside the existing `.sessionUpdate`
case), `refreshDetail()`. The 29 SessionViewModelTests + 37 SignalMessageTests pass untouched.

### DEBUG hatches (all `#if DEBUG`, Release-inert)
`-startTakeover {lobby|negotiating|live|debrief|debrief-interviewer|negoKept}`, `-startRecap
{locked|unlocked|cleared}` + stub `SessionFlowService`/signaling in `State/SessionFixtures.swift`
(mock-driven, no live backend — live WebRTC/finalize can't be driven in one sim).

---

## Design decisions (locked; reviewer-confirmed)
1. **`negotiating` precedes `lobby`** (B3 state machine, overrides the design's "lobby→nego"
   narrative). The lobby CTA is "waiting to begin", not "start negotiation" — the case is already
   settled by lobby.
2. **Dark takeover, light debrief + recap.** One `.dsTheme(.dark)` seam at the cover; debrief
   overrides light at its root; the recap gate is a SEPARATE light cover.
3. **Candidate swap OMITTED (DV-B3-SWAP).** Canvas 4a shows the candidate a "Swap roles" action,
   but B3 `/swap` is INTERVIEWER-only (403 for candidate). Swap is wired only in the interviewer
   debrief. **OWNER FLAG** — design wants candidate swap; backend forbids it.
4. **Recap close-out = REQUIRED 1–5** (§0.5); Close disabled until a valid rating; 409 re-close
   treated as already-cleared (both the recap sheet and the debrief path).
5. **"THEY KEPT THEIR PICK" resolves synchronously** from the already-held negotiation view the
   moment the case is stamped (no lobby flash) — the marquee beat holds the negotiation screen.

## Deviations & OWNER-VISUAL flags (FW5 demo checkpoint)
- **Candidate swap omitted** (decision 3 above) — needs an owner call.
- **Debrief shots show faint right-side glass ghosting** (systematic; likely glass backdrop
  sampling inside the dark cover) — owner glance; correctness unaffected.
- **Copy nits:** interviewer debrief button "Finalize" vs canvas "finalize & send feedback";
  recap close-out locked line uses the Decisions-brief wording ("Read to the end — N% of the way
  there") vs dc.html's "…to close out — N%…"; recap "cleared" is a toast + dismiss vs dc.html's
  full-screen done page. All defensible; flag for owner reconciliation.
- **Recap header shows the finalized date, not "1 OF 1 UNREAD"** (deliberate — the count is a
  population-count on the §5 reject-list).
- **Tablet takeover/recap NOT shipped as distinct layouts** — Decisions §7.6 lists them as "not
  yet designed"; phone layout serves both size classes. No tablet shots this phase.

## Follow-ups (deferred; non-blocking)
- **Candidate counter case-selection is thin** — `candidate_requested_case` is ~always null for
  case-less origins and there is no candidate library-picker in the negotiation screen, so the
  candidate "counter once" path is degenerate (falls back to the interviewer's pick id). Needs a
  candidate case picker to be fully meaningful (adversarial #4).
- **`Finalized.nextRecommendation`/`prefillProposal` decoded but not fully consumed** — the
  candidate "Schedule your next session" reuses `ProposeNowView(toUser:)` (recipient only), so the
  prefill `case_id` is dropped (v1). Either thread it through the composer or drop the fields
  (adversarial #3).
- **`swapAccept(id:)` is a service method with NO F5 UI** — the swap-invite accept row is F3's
  PENDING-rows territory. Whoever builds it MUST render its `409 {blocked_by_recap}` per DV-B3-SWAP
  as "the other party has a recap to finish" — NEVER route the accepter to `.recap(sid)`.

## Screenshot verdict
`.superpowers/sdd/f5/shots/` — dark: `lobby-dark`, `nego-candidate`, `nego-interviewer`,
`nego-kept-pick`, `live-candidate`, `live-candidate-exhibit` (4b Exhibit 01 table + unit-cost
bars), `live-interviewer`; light: `debrief-light`, `debrief-interviewer`, `recap-report`,
`recap-locked`, `recap-unlocked`, `recap-cleared`. Reviewer canvas-anchored each dark screen vs
4a/4b and each light screen vs 4a-debrief/6b; reject-list clean (StaircaseMark-only, square content
corners, underline secondaries, ≤1 glass hero, decorative greens ≤3, tabular clock/scores/table).

## THOMAS MANUAL
Owner-visual sign-off is deferred to the FW5 demo checkpoint (per the visual-judgment gate):
please eyeball dark-palette fidelity (4a/4b) on-device, the debrief right-side ghosting, and rule
on the **candidate-swap** question (design vs B3). On-device run needs your signing (ship tool).
The screenshots used mock services + DEBUG hatches — no dev server was started (port 8105 unused);
the reserved iPad Pro 11" sim was never booted and is shut down.

## ESCALATIONS
None. No Fable/`deep` consult was made or required.
