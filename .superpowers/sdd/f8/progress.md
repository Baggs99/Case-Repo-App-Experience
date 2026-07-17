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
Dispatch T1 (Community API layer + Community tab phone).

## Done
- Bootstrap (DB, baselines 655 / 413-0, xcodegen idempotent).
- Plan written + Opus-reviewed + revised.

## Blocked / decisions needed
- none

## Assumptions
- free_now + swap_invite_pending source = /connections (B6 report + live-code confirmed), not /availability.
- Create flow = AppRouter.groupCreate sheet flag (NOT a new AppRoute case) — §6 enum stays pinned.
- T1 mounts community NavigationStack; `.groupPage` destination filled by T2 (no interim user-facing stub).
