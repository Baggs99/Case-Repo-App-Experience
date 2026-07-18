# F8 Community — progress ledger
Updated: 2026-07-17 · Branch: fe/f8-community · Lead: F8

## Bootstrap — DONE
- DB caserepo_fe_f8: createdb → schema → migrations 002..035 (ON_ERROR_STOP clean) → seed. 35 tables.
- Baselines GREEN (match required): backend **655 passed**; iOS **413/0**; xcodegen idempotent.

## Plan — DONE + Opus-reviewed (APPROVE after 4 required revisions, all folded)
- docs/superpowers/plans/2026-07-17-fe-f8-plan.md
- Tasks: T1 API+Community tab (phone) · T2 Group page (phone) · T3 Group create + avatar wiring · T4 Tablet 2d.
- Review deltas: router sheet flag (no `.groupCreate` enum); T2 chrome suppression; streak col non-green;
  pinned `GET /groups/{id}` shapes + isAdmin from members[]. Reviewer confirmed swap_invite_pending live on branch.

## Now
All 4 tasks DONE + Opus-PASS. Running full suites (iOS + backend), then whole-branch adversarial review, then report.

## Done
- Bootstrap (DB, baselines 655 / 413-0, xcodegen idempotent).
- Plan written + Opus-reviewed + revised.
- **T1 DONE** (commit d6d7a05) — Community API + tab (phone). Opus PASS. 425 tests/0 fail;
  shot task1-community.png matches canvas 6a (1 hero, 1 green). CommunityTabStub deleted.
- **T2 DONE** (commit 08fb4dc) — Group page (phone). Opus PASS. 441 tests/0 fail;
  shot task2-grouppage.png matches canvas 6a. Sanctioned board rank/points OK; streak col non-green;
  detailOpen chrome suppression (Library preserved). KNOWN MINOR (non-blocking): admin progress-fetch
  failure shows "Loading…" indefinitely; errorBanner Retry re-runs load() not progress.
- **T3 DONE** (commit d83dc13) — Group create flow + avatar wiring. Opus PASS. 449 tests/0 fail;
  shot task3-groupcreate.png matches 7a create ("YOU'RE THE ADMIN" + invite code). No AppRoute case added.
- **T4 DONE** — Tablet master-detail (canvas 2d). Opus PASS. iOS 455 tests/0 fail; iPad portrait
  shot task4-ipad-community.png matches 2d (TCC-rotate landscape blocked → portrait fallback, pre-acknowledged).
  GroupPageContent extracted (phone unregressed); ≤3 greens; streak col non-green.

## Blocked / decisions needed
- none

## Assumptions
- free_now + swap_invite_pending source = /connections (B6 report + live-code confirmed), not /availability.
- Create flow = AppRouter.groupCreate sheet flag (NOT a new AppRoute case) — §6 enum stays pinned.
- T1 mounts community NavigationStack; `.groupPage` destination filled by T2 (no interim user-facing stub).
