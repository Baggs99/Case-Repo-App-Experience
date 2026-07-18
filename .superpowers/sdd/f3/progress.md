# F3 — Case tab · SDD Progress Ledger

Branch: fe/f3-case · Worktree: /Users/thomaskgould/dev/fe-f3 · Cut at 9cff198
DB: caserepo_fe_f3 · Dev port: 8103 · Sims: iPhone 17 942222D4 / iPad Pro 11" 653F37B8
Interpreter: /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python

## Baseline (bootstrap complete)
- DB caserepo_fe_f3 created; db/schema.sql + all db/migrations/0*.sql applied ON_ERROR_STOP clean; seed_caseroom_dev.py → users a/b/c@yale.edu + case 1.
- Backend suite: **655 passed** (`pytest tests/ -q`, 17.2s) — MATCHES required baseline 655. Finish line = 655 (F3 is FE-only; adds no backend tests) OR 655+N if any.
- iOS suite: **500 tests, 0 failures** (xcodebuild test, iPhone 17 942222D4) — MATCHES required baseline 500/0. Finish line = 500 + new VM tests.
- xcodegen generate idempotent (no diff after regen).
- Mic granted to study.mycase / .CaseRoomTests / com.apple.dt.xctest.tool on 942222D4.

## Reuse inventory (existing, do NOT rebuild)
- SessionsViewModel (proposals inbox + upcoming, accept/decline, EventKit via CalendarAdding) — Case tab currently renders SessionsView(); F3 replaces the tab body.
- APIClient: proposals(), acceptProposal(id:scheduledAt:), declineProposal(id:), pairCreate/pairStatus/pairClaim, availability()/setFree/clearFree, recommendations(exclude:).
- PairViewModel, FreeNowViewModel; CalendarWriter (EventKitCalendarWriter / CalendarAdding).
- AppRoute already has .caseTab, .recap(Int), .sessionTakeover(Int) (F1-pinned). caseTab currently NOT wrapped in a NavigationStack in RootShell (selectedTab: case .caseTab: SessionsView()).

## Seams inherited
- F4: case-detail CTA "Case someone with this" + "Get re-cased anyway" route to .caseTab plainly (no id). F3 OWNS case-prefill → add a router field; update CaseDetailView CTA to set it; Case tab auto-opens Case-someone prefilled. (No new AppRoute — enum pinned.)
- F5 parallel (~/dev/fe-f5): owns SessionView/SessionViewModel + recap screens. F3 navigates .recap(sessionID) on any blocked_by_recap 409; provides a MARK-bounded interim recap destination stub (F5 replaces at merge). Do NOT edit session/recap files.

## Plan
- docs/superpowers/plans/2026-07-17-fe-f3-plan.md (T1 data → T2 phone spine → T3/T4/T5 sheets → T6 tablet → close-out). Contract sheet extracted (scout). Opus plan-review: SOUND-WITH-FIXES (1 Crit + 4 Imp + 8 Min) — all dispositioned in the plan's "Plan-review dispositions" section. Key fixes: Proposal explicit init + optional case fields (blast radius = 5 sites not 1); HISTORY scope="recent" (NOT "past"); QR payload pinned caseroom://pair?code=<short_code>; go(.recap) steering DEFERRED to F5 per hard boundary; Ping = now-proposal.

## Tasks
- **T1 DONE** (commits 04de029, c81b115). Data layer: Proposal (optional case fields + direction/state/claimToken/counterTimes/counterBy/counteredAt + explicit defaulted init), AcceptedSession urls optional, PairToken.shortCode, RecapItem, ClaimResult, CaseGateError.blockedByRecap(Int) wired into accept/claim/pairClaim only (nested {"detail":{"blocked_by_recap":id}} @ 409). CaseTabViewModel + CaseTabService + CaseFixtures. APIClient.recaps()/claimProposal/counterProposal. Suite **509/0** (500+9). Opus review APPROVE-WITH-NITS (0 Crit/Imp; 4 minors: VM not @MainActor = mirrors SessionsViewModel precedent; 2 dead gate-catch arms in decline/counter = spec-directed; minor test gaps; claimProposal token path-interp low-risk). xcodeproj stays gitignored/regenerable (repo convention — only Package.resolved tracked).
- **T2** (phone spine) — dispatching.
- T3/T4/T5 (sheets), T6 (tablet), close-out — pending.
