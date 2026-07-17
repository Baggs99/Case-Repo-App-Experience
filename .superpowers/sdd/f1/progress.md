# F1 — Shell & Navigation · Ledger

Branch: `fe/f1-shell` · Worktree: `/Users/thomaskgould/dev/fe-f1` · Base: `000f0c8`

## Bootstrap (DONE)
- DB `caserepo_fe_f1` created; `db/schema.sql` + all 32 `db/migrations/0*.sql` applied clean (no errors).
- Worktree `.env` copied from main checkout; `DATABASE_URL=postgresql://localhost/caserepo_fe_f1`; gitignored.
- Seeded dev users a/b/c@yale.edu (`caseroom-dev-1`) + dummy case via `scripts/seed_caseroom_dev.py`.
- **Backend baseline: 655 passed / 0 failed** (`$PY -m pytest tests/ -q`, 10.5s). GREEN.
- **iOS baseline: 289 passed / 0 failed** (`xcodebuild ... -destination id=A10D5A1D-D389-4A71-9523-551C4D08A113 test`). GREEN. `** TEST SUCCEEDED **`.
- `xcodegen generate` idempotent; `.xcodeproj` gitignored (repo convention).
- Sim iPhone 17 (A10D5A1D…) booted, mic granted (study.mycase / .CaseRoomTests / com.apple.dt.xctest.tool).

## Entry-point audit (COMPLETE — 8 distinct steering sources; all remapped in Task 1)
1. `caseroom://drill` (Streak widget widgetURL) → drillRun (Home + drill token)
2. `caseroom://sessions` (NextSession widget widgetURL) → caseTab
3. `caseroom://freenow` (tested; no live emitter) → caseTab
4. push `proposal` → caseTab
5. push `accepted`/`knock`/`feedback`/`starting_soon` (session_id) → caseTab
6. push `free_now` (user_id) → caseTab + ProposeNow sheet
7. `StartDrillIntent` (Siri/Shortcuts) → drillRun ; `NextSessionIntent` (spoken, no nav) ; `ToggleFreeNowIntent` (Siri/Action/widget button, no nav)
8. APNs device registration (AppDelegate.didRegister…, registerDevice) — unchanged
Locked by tests: `IntentsTests` (URL parse + push fold), `PushRouteTests` (payload parse). Legacy `AppRoute` enum → renamed `DeepLink`; new pinned `AppRoute` = destination registry.

## Now
T1 DONE + APPROVED (78e7e4e; 304 tests/0 fail = 289+15 AppRouterTests). Dispatching T2 (sonnet). All subagents synchronous.

## Deferred MINOR nits (sweep at close-out)
- IntentsTests.swift:2 header still says "AppRoute" (tests now exercise DeepLink) — cosmetic, file persists.
- RootTabView.swift header stale — moot, deleted in T4.

## PHASE DONE
Whole-branch Opus review APPROVE (0 CRIT/0 IMP/6 MIN follow-ups, all recorded in report). Report written: docs/superpowers/sdd/fe-f1-report.md. Dev server killed; all sims shut down. Head `f65fb94` (pre-report commit); report + this ledger add 2 more commits.

## Tasks
- [x] Plan review (Opus) — APPROVED after 2 rounds (be346f2)
- [x] T1 AppRoute registry + AppRouter + remap (opus) — 78e7e4e, APPROVE
- [x] T2 profile/settings models + APIClient (sonnet) — 773c7df, APPROVE (309 tests/0; multipart field `file` confirmed vs profile.py)
- [x] T3 avatar sheet 7a + VM (opus) — f7bf899, APPROVE (313 tests/0; screenshot matches 7a, greens=3 at ceiling; deviations: injectable @MainActor VM init + DEBUG PreviewProfileService for populated shot)
- [x] T4 RootShell: chrome + re-home + wire (opus) — 176fa70, APPROVE (313 tests/0; 6 real-content shots match §1 chrome; RootTabView+ProfileView git-rm'd; drill sheet shell-owned w/ initial:true; DEBUG hatches -DevLogin/-startTab/-avatarOpen + push-auth skip, all gated). Dev server on :8077 for shots.

## Close-out
- Doc-nit sweep DONE (891583f): LoginView + IntentsTests headers de-staled. (RootTabView header moot — file deleted in T4.)
- Both suites GREEN: iOS 313/0 (post-sweep re-run); backend 655 (no backend files changed since base — verified `git diff --stat 000f0c8..HEAD -- webapp db tests main.py` empty).
- xcodegen idempotent (project.yml unchanged by regen).
- Dev server still on :8077 (kill before finishing). iPad sim shut down; iPhone 17 sim booted.
- Next: final whole-branch Opus review → fix → kill server/sim → report.
- [x] T5 iPad variant (opus) — be2894c, APPROVE (313/0; 560 bar + wordmark|H1|avatar, portrait fallback)
- [x] Close-out — iOS 313/0 + backend 655; whole-branch Opus review APPROVE (0 CRIT/0 IMP/6 MIN); report DONE; server+sims down

## Assumptions (to confirm at review)
- Notifications = single master pill (writes all 5 B5 categories); granular screen deferred (Decisions §6).
- Linked-accounts LINKED derived from `linkedin_url` presence — GET /profile lacks OAuth sub flags (backend gap; report recommends follow-up).
- School VERIFIED ⇐ non-empty `profile.school`.
- Drill run stays Home-hosted transitionally (F7 moves to Drills tab).
- "Administer a group" → `.community` seam until F8's create-group route lands.
