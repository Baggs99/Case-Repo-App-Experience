# F5 — Session takeover + recap gate · Ledger
Updated: 2026-07-17 · Branch: fe/f5-session · Base: 9cff198

## Now
Bootstrap done + plan approved (after fixes). Starting task loop at T1.

## Baselines (bootstrap gate PASSED)
- Backend suite: 655 passed / 0 — `pytest tests/ -q` against caserepo_fe_f5 (seeded)
- iOS suite: 500 passed / 0 — xcodebuild test, iPhone 17 (F4) sim
- xcodegen generate: idempotent (no diff)
- DB caserepo_fe_f5: schema + migrations 002..035 + seed_caseroom_dev (users=3, cases=1)
- Mic granted: study.mycase / .CaseRoomTests / com.apple.dt.xctest.tool on iPhone 17 (F4)

## Done
- Bootstrap — evidence above
- Plan written + Opus plan-review REQUEST_CHANGES(light, 5 findings) → all 5 folded
  (candidate_requested_case struct, swapAccept UI-deferred + 409 scoping, F3 409
  integration check, debrief light-in-dark risk) — plan committed

## Tasks
- [x] T1 Networking foundation (Opus) — 1450d62 + fix ffe3f90; 517/0; Opus APPROVE. Deviations: acceptCase→SessionDetail, difficulty String?, RecapListItem.caseTitle optional (legacy null), reveals lenient.
- [x] T2 Lobby refit dark (Opus) — 8d47abd; 523/0; Opus APPROVE. Single `.dsTheme(.dark)` seam in RootShell. DEBUG hatch `-startTakeover lobby`. Deviations: lobby CTA "waiting…" (negotiating precedes lobby per B3), pill omits schedule, hero subtitle = caseTitle (no peer-bio VM field).
- [x] T3 Negotiation stage (Opus) — 85622a2; 538/0; Opus APPROVE (no fixes). NegotiationStageView + NegotiationLogic (15 tests). Additive SessionVM negotiationTick kept 29 VM + 37 signal green. B3 ordering: negotiating→lobby (SessionView switch gains "negotiating"). Known limitation: candidate counter case-selection thin (candidate_requested_case ~always null for case-less; no library picker) — deferrable.
- [x] T4 LIVE refit dark (Opus) — 6281c09; 544/0; Opus APPROVE (no fixes). Transport boundary byte-identical (RTC representable untouched), transport regression subset green+untouched. LiveShared.swift (clock pill/new-dot/table+bars). Real AES-GCM ciphertext through decrypt seam. 3 shots. Green density: filled ScoreCells sanctioned (Decisions §1); decorative greens ≤3.
- [x] T5 Debrief refit light (Opus) — 93b108e; 557/0; Opus APPROVE. `.dsTheme(.light)` override wins over dark seam (verified in shots). DebriefViewModel + DebriefPresentation (13 tests). recapClose REQUIRED-gated. OWNER FLAGS: (a) candidate swap OMITTED per DV-B3-SWAP (design wants it, backend interviewer-only); (b) faint right-side glass ghosting on debrief shots — owner glance; (c) interviewer button "Finalize" vs canvas "finalize & send feedback". Schedule-next reuses ProposeNowView (case_id not threaded — v1).
- [x] T6 Recap report page (Opus) — 2c413c8 + fix 88db738; 569/0; Opus APPROVE (re-reviewed). RecapReportView + RecapViewModel + RecapPresentation (11 tests). Wired `.recap` route: AppRouter.recapSessionID (additive) + go(to:.recap) + RootShell LIGHT fullScreenCover; AppRouterTests extended. T7 overlay seam left. Fixes: fabricated ATTACHED subtitle removed (canon 6b row), subline grade fallback report.grade. OWNER FLAG: header shows finalized date not "1 OF 1 UNREAD" (population-count avoidance).
- [x] T7 Recap close-out sheet (Opus) — 46f9b9c; 583/0. RecapCloseOutSheet + RecapCloseOutViewModel + RecapCloseOutPresentation (18 tests: scroll-progress, bottom−16 unlock, required-rating gate, gate-clear + 409-as-cleared, defensive 422). Floats in T6's overlay seam; unlock observed via scroll PreferenceKey (offset+contentH) vs viewport GeometryReader. Shared ScoreCells (not forked). Thumbs = text "Worth it/Thin" (always sendable). DEBUG hatch `-startRecap locked|unlocked|cleared`; 3 shots. DEVIATION: cleared uses `.dsToast` "Gate cleared." + dismiss (brief-directed) instead of dc.html's full-screen done. Locked copy per Decisions §59 "Read to the end — N%".
- [ ] Close-out: suites + adversarial review + report

## Blocked / decisions needed
- none

## Assumptions
- Tablet takeover/recap undesigned (Decisions §7.6) → ship phone layout, document deviation
- Recap presented as RootShell fullScreenCover keyed on new AppRouter.recapSessionID
- swapAccept invitee UI deferred (F3 PENDING-rows territory); service method provided
