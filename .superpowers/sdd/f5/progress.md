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
- [ ] T1 Networking foundation (Opus)
- [ ] T2 Lobby refit dark (Opus)
- [ ] T3 Negotiation stage (Opus)
- [ ] T4 LIVE refit dark (Opus) — HIGHEST RISK
- [ ] T5 Debrief refit light (Opus)
- [ ] T6 Recap report page (Opus)
- [ ] T7 Recap close-out sheet (Opus)
- [ ] Close-out: suites + adversarial review + report

## Blocked / decisions needed
- none

## Assumptions
- Tablet takeover/recap undesigned (Decisions §7.6) → ship phone layout, document deviation
- Recap presented as RootShell fullScreenCover keyed on new AppRouter.recapSessionID
- swapAccept invitee UI deferred (F3 PENDING-rows territory); service method provided
